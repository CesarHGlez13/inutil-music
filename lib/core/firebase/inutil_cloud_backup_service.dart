import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/music/domain/entities/catalog_track.dart';
import '../../features/music/domain/entities/local_track.dart';
import '../../features/music/domain/entities/playlist.dart';
import '../../features/music/domain/entities/playlist_entry.dart';
import '../../services/storage/local_database_service.dart';
import 'firebase_auth_service.dart';
import 'firebase_firestore_service.dart';
import 'inutil_wrapped_service.dart';

typedef CloudDocumentGetter =
    Future<Map<String, dynamic>?> Function(String path);
typedef CloudDocumentSetter =
    Future<bool> Function(String path, Map<String, dynamic> data);
typedef CloudDocumentDeleter = Future<bool> Function(String path);
typedef CloudWrappedHook = Future<void> Function();

@visibleForTesting
class InutilCloudBackupHooks {
  const InutilCloudBackupHooks({
    this.getDocument,
    this.setDocument,
    this.deleteDocument,
    this.currentUid,
    this.canSync,
    this.ensureFreshSession,
    this.onPersistWrapped,
    this.onPullWrapped,
  });

  final CloudDocumentGetter? getDocument;
  final CloudDocumentSetter? setDocument;
  final CloudDocumentDeleter? deleteDocument;
  final String? Function()? currentUid;
  final bool Function()? canSync;
  final Future<bool> Function()? ensureFreshSession;
  final CloudWrappedHook? onPersistWrapped;
  final CloudWrappedHook? onPullWrapped;
}

/// Respaldo en la nube del usuario (perfil, playlists, entradas de catálogo,
/// biblioteca descargada y ajustes).
///
/// Sin este servicio, borrar los datos o desinstalar la app dejaba al usuario
/// sin sus playlists. Cada cuenta guarda su biblioteca en `users/{uid}/data/*`:
///   * `backup_meta`            → playlists (con `trackIds`) + ajustes
///   * `backup_entries_0..n`    → entradas de `CatalogPlaylist` (`playlist_items`
///                                + `catalog_tracks`) para listas importadas de
///                                Spotify/CSV, YouTube y añadidas desde buscar
///   * `backup_tracks_0..n`     → metadatos de `local_tracks` en bloques <700 KB
class InutilCloudBackupService {
  InutilCloudBackupService({
    required LocalDatabaseService database,
    @visibleForTesting this.hooks,
  }) : _db = database;

  final LocalDatabaseService _db;
  @visibleForTesting
  final InutilCloudBackupHooks? hooks;

  CloudDocumentGetter get _getDocument =>
      hooks?.getDocument ?? InutilFirestoreService.instance.getDocument;
  CloudDocumentSetter get _setDocument =>
      hooks?.setDocument ?? InutilFirestoreService.instance.setDocument;
  CloudDocumentDeleter get _deleteDocument =>
      hooks?.deleteDocument ?? InutilFirestoreService.instance.deleteDocument;

  static const int _chunkSoftLimitBytes = 700 * 1024;
  static const int _maxChunks = 64;
  static const Duration _pushDebounce = Duration(seconds: 5);
  static const Duration _autoPushInterval = Duration(minutes: 30);

  Timer? _debounce;
  Timer? _interval;
  bool _pushing = false;
  bool _pulling = false;
  bool _initialPullCompleted = false;
  bool _lastRestoreHadChanges = false;
  String? _lastUid;
  DateTime? _lastPushAt;
  String _lastError = '';

  DateTime? get lastPushAt => _lastPushAt;
  String get lastError => _lastError;
  bool get lastRestoreHadChanges => _lastRestoreHadChanges;

  /// Claves de prefs que NUNCA se respaldan: identidad de sesión/dispositivo
  /// (cada instalación genera la suya) y cachés que se reconstruyen solos.
  static const Set<String> _volatilePrefKeys = {
    'inutil_music_auth_user_v2',
    'inutil_music_auth_user_v3',
    'inutil_music_auth_session_v3',
    'inutil_music_users_registry_v2',
    'inutil_music_users_cache_v3',
    'inutil_music_device_id_v2',
    'inutil_music_cached_release_v2',
    'inutil_release_manifest_url',
  };

  String? get _activeUid =>
      hooks?.currentUid?.call() ?? InutilAuthService.instance.currentUser?.uid;

  /// true si la cuenta puede respaldar (autenticada, vigente y con sesión).
  bool get canSync {
    final override = hooks?.canSync;
    if (override != null) return override();
    final auth = InutilAuthService.instance;
    return auth.currentUser?.idToken.isNotEmpty == true && auth.isAccessAllowed;
  }

  Future<bool> _refreshAuthIfNeeded() async {
    final hook = hooks?.ensureFreshSession;
    if (hook != null) return hook();
    return InutilAuthService.instance.ensureFreshSession();
  }

  Future<void> _syncWrappedToCloud() async {
    final hook = hooks?.onPersistWrapped;
    if (hook != null) {
      await hook();
      return;
    }
    await InutilWrappedService.instance.persistNow();
    await InutilWrappedService.instance.syncCurrentYearToCloud();
  }

  Future<void> _pullWrappedFromCloud() async {
    final hook = hooks?.onPullWrapped;
    if (hook != null) {
      await hook();
      return;
    }
    await InutilWrappedService.instance.pullYearFromCloud();
  }

  /// Reinicia el estado de sesión al cerrar sesión o cambiar de cuenta.
  void resetSessionState() {
    _initialPullCompleted = false;
    _lastRestoreHadChanges = false;
    _lastUid = null;
    _lastPushAt = null;
    _lastError = '';
  }

  void _syncAccountBoundary(String? uid) {
    if (uid != _lastUid) {
      _initialPullCompleted = false;
      _lastUid = uid;
    }
  }

  // ---------------------------------------------------------------------------
  // PUSH — local → nube
  // ---------------------------------------------------------------------------

  /// Empuja con debounce corto: cambios consecutivos (importar playlists,
  /// mover pistas, renombrar) generan un solo viaje rápido a Firestore.
  void schedulePush() {
    if (!canSync) return;
    _debounce?.cancel();
    _debounce = Timer(_pushDebounce, () => unawaited(pushNow()));
  }

  /// Inicia la sincronización periódica (llamada por la UI al montar la app).
  void startAutoSync() {
    _interval?.cancel();
    _interval = Timer.periodic(_autoPushInterval, (_) {
      if (canSync) unawaited(pushNow());
    });
  }

  void stopAutoSync() {
    _interval?.cancel();
    _interval = null;
    _debounce?.cancel();
    _debounce = null;
  }

  Future<void> pushNow() async {
    if (_pushing) return;
    if (!canSync) {
      await _refreshAuthIfNeeded();
      if (!canSync) return;
    } else {
      await _refreshAuthIfNeeded();
    }
    final uid = _activeUid;
    if (uid == null || uid.isEmpty) return;
    _syncAccountBoundary(uid);

    // Protección anti-sobrescritura: si esta instalación aún no completa su
    // pull inicial (p. ej. tras reinstalar y crear o importar algo enseguida),
    // primero fusionamos el respaldo remoto sin sobrescribir lo nuevo local.
    if (!_initialPullCompleted) {
      await pullAndRestoreIfEmpty();
      if (!_initialPullCompleted) {
        await _syncWrappedToCloud();
        return;
      }
    }

    _pushing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final playlists = await _db.getPlaylists();
      final tracks = await _db.getLocalTracks();

      final catalogEntries = <Map<String, dynamic>>[];
      for (final playlist in playlists) {
        if (playlist.deletedAt != null) continue;
        final catalog = await _db.getCatalogPlaylist(playlist.id);
        if (catalog == null) continue;
        for (final entry in catalog.entries) {
          if (entry.isDeleted) continue;
          catalogEntries.add(_entryToMap(entry));
        }
      }

      final meta = <String, dynamic>{
        'playlists': playlists
            .map(
              (p) => <String, dynamic>{
                'id': p.id,
                'name': p.name,
                'trackIds': p.trackIds,
                'createdAt': p.createdAt.toIso8601String(),
                'updatedAt': p.updatedAt.toIso8601String(),
                if (p.deletedAt != null)
                  'deletedAt': p.deletedAt!.toIso8601String(),
                if (p.customArtworkFileName != null)
                  'customArtworkFileName': p.customArtworkFileName,
              },
            )
            .toList(growable: false),
        'catalogEntriesCount': catalogEntries.length,
        'settings': _collectSettings(prefs),
        'updatedAt': DateTime.now().toIso8601String(),
        'appVersion': Platform.operatingSystemVersion,
      };
      final metaOk = await _setDocument('users/$uid/data/backup_meta', meta);

      final tracksOk = await _writeChunkedCollection(
        uid: uid,
        prefix: 'backup_tracks_',
        fieldName: 'tracks',
        items: tracks.map(_trackToMap).toList(growable: false),
      );

      final entriesOk = await _writeChunkedCollection(
        uid: uid,
        prefix: 'backup_entries_',
        fieldName: 'entries',
        items: catalogEntries,
      );

      await _syncWrappedToCloud();

      _lastPushAt = DateTime.now();
      _lastError = metaOk && tracksOk && entriesOk
          ? ''
          : 'El respaldo parcial falló; se reintentará automáticamente.';
    } catch (e) {
      _lastError = 'Respaldo no completado: $e';
      debugPrint('Cloud backup push falló: $e');
    } finally {
      _pushing = false;
    }
  }

  Future<bool> _writeChunkedCollection({
    required String uid,
    required String prefix,
    required String fieldName,
    required List<Map<String, dynamic>> items,
  }) async {
    final chunks = <List<Map<String, dynamic>>>[];
    var current = <Map<String, dynamic>>[];
    var currentBytes = 2;
    for (final item in items) {
      final size = utf8.encode(jsonEncode(item)).length + 1;
      if (currentBytes + size > _chunkSoftLimitBytes && current.isNotEmpty) {
        chunks.add(current);
        current = <Map<String, dynamic>>[];
        currentBytes = 2;
      }
      current.add(item);
      currentBytes += size;
    }
    if (current.isNotEmpty) chunks.add(current);

    var okAll = true;
    final nowIso = DateTime.now().toIso8601String();
    for (var i = 0; i < chunks.length; i++) {
      final ok = await _setDocument('users/$uid/data/$prefix$i', {
        fieldName: chunks[i],
        'updatedAt': nowIso,
      });
      okAll = okAll && ok;
    }
    for (var i = chunks.length; i < chunks.length + 4; i++) {
      final probe = await _getDocument('users/$uid/data/$prefix$i');
      if (probe == null) break;
      await _deleteDocument('users/$uid/data/$prefix$i');
    }
    return okAll;
  }

  Map<String, dynamic> _trackToMap(LocalTrack t) => <String, dynamic>{
    'id': t.id,
    'title': t.title,
    'artist': t.artist,
    'filePath': t.filePath,
    'addedAt': t.addedAt.toIso8601String(),
    if (t.sourceUrl != null) 'sourceUrl': t.sourceUrl,
    if (t.thumbnailUrl != null) 'thumbnailUrl': t.thumbnailUrl,
    if (t.catalogThumbnailUrl != null)
      'catalogThumbnailUrl': t.catalogThumbnailUrl,
    if (t.duration != null) 'durationMs': t.duration!.inMilliseconds,
    if (t.album != null) 'album': t.album,
    'artists': t.artists,
    'artistBrowseIds': t.artistBrowseIds.map((e) => e ?? '').toList(),
    'metadataSource': t.metadataSource.name,
    if (t.sourceId != null) 'sourceId': t.sourceId,
  };

  Map<String, dynamic> _entryToMap(PlaylistEntry entry) => <String, dynamic>{
    'id': entry.id,
    'playlistId': entry.playlistId,
    'position': entry.position,
    'origin': entry.origin.name,
    'createdAt': entry.createdAt.toIso8601String(),
    'updatedAt': entry.updatedAt.toIso8601String(),
    if (entry.localTrackId != null) 'localTrackId': entry.localTrackId,
    if (entry.remoteVideoId != null) 'remoteVideoId': entry.remoteVideoId,
    if (entry.setVideoId != null) 'setVideoId': entry.setVideoId,
    'track': <String, dynamic>{
      'key': entry.track.key,
      'provider': entry.track.provider.name,
      'providerId': entry.track.providerId,
      'title': entry.track.title,
      'artists': entry.track.artists,
      'artistBrowseIds': entry.track.artistBrowseIds
          .map((e) => e ?? '')
          .toList(growable: false),
      if (entry.track.album != null) 'album': entry.track.album,
      if (entry.track.duration != null)
        'durationMs': entry.track.duration!.inMilliseconds,
      if (entry.track.thumbnailUrl != null)
        'thumbnailUrl': entry.track.thumbnailUrl,
      if (entry.track.sourceUrl != null) 'sourceUrl': entry.track.sourceUrl,
    },
  };

  Map<String, dynamic> _collectSettings(SharedPreferences prefs) {
    final result = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (_volatilePrefKeys.contains(key)) continue;
      if (key.contains('token') || key.contains('secret')) continue;
      final value = prefs.get(key);
      if (value == null) continue;
      result[key] = value;
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // PULL — nube → local (instalación nueva o inicio de sesión)
  // ---------------------------------------------------------------------------

  /// Restaura playlists, entradas de catálogo, biblioteca y ajustes desde la
  /// nube. Solo escribe datos que aún NO existen localmente: tras reinstalar o
  /// iniciar sesión recupera todo; en un dispositivo con playlists activas no
  /// sobrescribe las canciones existentes.
  Future<String> pullAndRestoreIfEmpty() async {
    if (_pulling) return 'Respaldo en curso…';
    if (!canSync) {
      await _refreshAuthIfNeeded();
      if (!canSync) return 'Inicia sesión para restaurar tu respaldo.';
    } else {
      await _refreshAuthIfNeeded();
    }
    final uid = _activeUid;
    if (uid == null || uid.isEmpty) {
      return 'Inicia sesión para restaurar tu respaldo.';
    }
    _syncAccountBoundary(uid);

    _pulling = true;
    _lastRestoreHadChanges = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await _pullWrappedFromCloud();

      final meta = await _getDocument('users/$uid/data/backup_meta');

      var restoredPlaylists = 0;
      if (meta != null) {
        final localPlaylists = await _db.getPlaylists();
        final remote = meta['playlists'];
        if (remote is List) {
          final localById = <String, Playlist>{
            for (final p in localPlaylists) p.id: p,
          };
          for (final raw in remote) {
            if (raw is! Map) continue;
            final playlist = _playlistFromMap(raw.cast<String, dynamic>());
            if (playlist == null) continue;
            final existingLocal = localById[playlist.id];
            // Restaura si la playlist no existe localmente (típico tras
            // reinstalar), o si existe localmente vacía (p. ej. Favoritos
            // recién creada en frío) y la nube sí trae tracks.
            final shouldRestore =
                existingLocal == null ||
                (existingLocal.deletedAt == null &&
                    playlist.deletedAt == null &&
                    existingLocal.trackIds.isEmpty &&
                    playlist.trackIds.isNotEmpty);
            if (!shouldRestore) continue;
            await _db.savePlaylist(playlist);
            restoredPlaylists += 1;
          }
        }

        final settings = meta['settings'];
        if (settings is Map) {
          settings.cast<String, dynamic>().forEach((key, value) {
            if (_volatilePrefKeys.contains(key)) return;
            if (prefs.containsKey(key)) return;
            if (value is String) {
              prefs.setString(key, value);
            } else if (value is bool) {
              prefs.setBool(key, value);
            } else if (value is int) {
              prefs.setInt(key, value);
            } else if (value is double) {
              prefs.setDouble(key, value);
            } else if (value is List) {
              final strings = value.map((e) => e.toString()).toList();
              prefs.setStringList(key, strings);
            }
          });
        }
      }

      final existingLocalTracks = await _db.getLocalTracks();
      final knownLocalIds = existingLocalTracks.map((t) => t.id).toSet();
      final localIdByVideoId = <String, String>{
        for (final t in existingLocalTracks)
          if (t.sourceId != null && t.sourceId!.trim().isNotEmpty)
            t.sourceId!.trim(): t.id,
      };

      var restoredTracks = 0;
      for (var i = 0; i < _maxChunks; i++) {
        final doc = await _getDocument('users/$uid/data/backup_tracks_$i');
        if (doc == null) break;
        final tracks = doc['tracks'];
        if (tracks is! List) continue;
        for (final raw in tracks) {
          if (raw is! Map) continue;
          final track = _trackFromMap(raw.cast<String, dynamic>());
          if (track == null || knownLocalIds.contains(track.id)) continue;
          await _db.saveLocalTrack(track);
          knownLocalIds.add(track.id);
          final sourceId = track.sourceId?.trim();
          if (sourceId != null && sourceId.isNotEmpty) {
            localIdByVideoId.putIfAbsent(sourceId, () => track.id);
          }
          restoredTracks += 1;
        }
      }

      // Restaurar entradas de catálogo (Spotify/CSV, YouTube, añadidas a
      // playlists sin descargar): si la playlist existe y no tiene entradas
      // activas locales, restauramos todas sus canciones en orden exacto.
      final remoteEntriesByPlaylist = <String, List<PlaylistEntry>>{};
      for (var i = 0; i < _maxChunks; i++) {
        final doc = await _getDocument('users/$uid/data/backup_entries_$i');
        if (doc == null) break;
        final rawEntries = doc['entries'];
        if (rawEntries is! List) continue;
        for (final raw in rawEntries) {
          if (raw is! Map) continue;
          final entry = _entryFromMap(raw.cast<String, dynamic>());
          if (entry == null) continue;
          remoteEntriesByPlaylist
              .putIfAbsent(entry.playlistId, () => <PlaylistEntry>[])
              .add(entry);
        }
      }

      var restoredEntries = 0;
      final now = DateTime.now();
      for (final mapEntry in remoteEntriesByPlaylist.entries) {
        final playlistId = mapEntry.key;
        final existingCatalog = await _db.getCatalogPlaylist(playlistId);
        if (existingCatalog == null ||
            existingCatalog.playlist.deletedAt != null) {
          continue;
        }
        final hasActiveEntries = existingCatalog.entries.any(
          (e) => !e.isDeleted,
        );
        if (hasActiveEntries) continue;

        final sorted = mapEntry.value.toList()
          ..sort((a, b) => a.position.compareTo(b.position));
        final normalized = <PlaylistEntry>[];
        for (var idx = 0; idx < sorted.length; idx++) {
          final item = sorted[idx];
          final safeLocalId =
              item.localTrackId != null &&
                  knownLocalIds.contains(item.localTrackId)
              ? item.localTrackId
              : (item.videoId != null ? localIdByVideoId[item.videoId!] : null);
          normalized.add(
            item.copyWith(
              position: idx,
              localTrackId: safeLocalId,
              deletedAt: null,
            ),
          );
        }
        if (normalized.isEmpty) continue;
        await _db.replaceCatalogEntries(
          playlistId: playlistId,
          entries: normalized,
          now: now,
        );
        restoredEntries += normalized.length;
      }

      _initialPullCompleted = true;
      _lastRestoreHadChanges =
          restoredPlaylists > 0 || restoredTracks > 0 || restoredEntries > 0;
      _lastError = '';
      if (!_lastRestoreHadChanges && meta == null) {
        return 'Aún no hay respaldo en la nube para esta cuenta.';
      }
      return 'Respaldo restaurado: $restoredPlaylists playlists, '
          '$restoredEntries canciones en listas, $restoredTracks pistas locales.';
    } catch (e) {
      _lastError = 'Restauración no completada: $e';
      debugPrint('Cloud backup pull falló: $e');
      return 'No se pudo restaurar (¿sin conexión?). Reintenta más tarde.';
    } finally {
      _pulling = false;
    }
  }

  Playlist? _playlistFromMap(Map<String, dynamic> map) {
    final rawId = map['id'] as String? ?? '';
    final id = rawId.endsWith(':favorites') ? Playlist.favoritesId : rawId;
    final name = map['name'] as String? ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    final trackIds =
        (map['trackIds'] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[];
    return Playlist(
      id: id,
      name: name,
      trackIds: trackIds,
      createdAt:
          DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      deletedAt: DateTime.tryParse(map['deletedAt']?.toString() ?? ''),
      customArtworkFileName: map['customArtworkFileName'] as String?,
    );
  }

  PlaylistEntry? _entryFromMap(Map<String, dynamic> map) {
    final id = map['id'] as String? ?? '';
    final rawPlaylistId = map['playlistId'] as String? ?? '';
    final playlistId = rawPlaylistId.endsWith(':favorites')
        ? Playlist.favoritesId
        : rawPlaylistId;
    final rawTrack = map['track'];
    if (id.isEmpty || playlistId.isEmpty || rawTrack is! Map) return null;
    final trackMap = rawTrack.cast<String, dynamic>();
    final key = trackMap['key'] as String? ?? '';
    final providerId = trackMap['providerId'] as String? ?? '';
    if (key.isEmpty || providerId.isEmpty) return null;
    final providerName = trackMap['provider'] as String? ?? 'youtube';
    final provider = CatalogProvider.values.firstWhere(
      (candidate) => candidate.name == providerName,
      orElse: () => CatalogProvider.youtube,
    );
    final durationMs = (trackMap['durationMs'] as num?)?.toInt();
    final originName = map['origin'] as String? ?? 'local';
    final origin = PlaylistEntryOrigin.values.firstWhere(
      (candidate) => candidate.name == originName,
      orElse: () => PlaylistEntryOrigin.local,
    );
    final browseRaw = (trackMap['artistBrowseIds'] as List?)
        ?.map((e) {
          final s = e?.toString() ?? '';
          return s.isEmpty ? null : s;
        })
        .toList(growable: false);
    return PlaylistEntry(
      id: id,
      playlistId: playlistId,
      track: CatalogTrack(
        key: key,
        provider: provider,
        providerId: providerId,
        title: trackMap['title'] as String? ?? 'Canción',
        artists:
            (trackMap['artists'] as List?)
                ?.map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList(growable: false) ??
            const <String>[],
        artistBrowseIds: browseRaw ?? const <String?>[],
        album: trackMap['album'] as String?,
        duration: durationMs != null
            ? Duration(milliseconds: durationMs)
            : null,
        thumbnailUrl: trackMap['thumbnailUrl'] as String?,
        sourceUrl: trackMap['sourceUrl'] as String?,
      ),
      localTrackId: map['localTrackId'] as String?,
      remoteVideoId: map['remoteVideoId'] as String?,
      setVideoId: map['setVideoId'] as String?,
      position: (map['position'] as num?)?.toInt() ?? 0,
      origin: origin,
      createdAt:
          DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  LocalTrack? _trackFromMap(Map<String, dynamic> map) {
    final id = map['id'] as String? ?? '';
    if (id.isEmpty) return null;
    final durationMs = (map['durationMs'] as num?)?.toInt();
    return LocalTrack(
      id: id,
      title: map['title'] as String? ?? 'Canción',
      artist: map['artist'] as String? ?? 'Inútil Music',
      filePath: map['filePath'] as String? ?? '',
      addedAt:
          DateTime.tryParse(map['addedAt']?.toString() ?? '') ?? DateTime.now(),
      sourceUrl: map['sourceUrl'] as String?,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      catalogThumbnailUrl: map['catalogThumbnailUrl'] as String?,
      duration: durationMs != null ? Duration(milliseconds: durationMs) : null,
      album: map['album'] as String?,
      artists:
          (map['artists'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      artistBrowseIds:
          (map['artistBrowseIds'] as List?)
              ?.map((e) => e?.toString())
              .toList() ??
          const [],
      sourceId: map['sourceId'] as String?,
    );
  }
}
