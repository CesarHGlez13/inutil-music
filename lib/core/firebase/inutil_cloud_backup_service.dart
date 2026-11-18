import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/music/domain/entities/local_track.dart';
import '../../features/music/domain/entities/playlist.dart';
import '../../services/storage/local_database_service.dart';
import 'firebase_auth_service.dart';
import 'firebase_firestore_service.dart';

/// Respaldo en la nube del usuario (perfil, playlists, biblioteca y ajustes).
///
/// Sin este servicio, borrar los datos o desinstalar la app dejaba al usuario
/// sin sus playlists. Aquí cada cuenta guarda su biblioteca en
/// `users/{uid}/data/*` de Firestore:
///   * `backup_meta`   → playlists + ajustes (un solo documento)
///   * `backup_tracks_0..n` → metadatos de pistas, en bloques de <800 KB para
///     respetar el límite de 1 MiB por documento de Firestore.
///
/// El respaldo es LÓGICO (no copia el archivo SQLite): solo viaja lo que le
/// pertenece al usuario; las cachés de recomendaciones o el historial de
/// reproducción se quedan en el teléfono.
class InutilCloudBackupService {
  InutilCloudBackupService({required LocalDatabaseService database})
    : _db = database;

  final LocalDatabaseService _db;
  final InutilAuthService _auth = InutilAuthService.instance;

  static const int _chunkSoftLimitBytes = 700 * 1024;
  static const Duration _pushDebounce = Duration(seconds: 20);
  static const Duration _autoPushInterval = Duration(minutes: 30);

  Timer? _debounce;
  Timer? _interval;
  bool _pushing = false;
  bool _pulling = false;
  DateTime? _lastPushAt;
  String _lastError = '';

  DateTime? get lastPushAt => _lastPushAt;
  String get lastError => _lastError;

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

  /// true si la cuenta puede respaldar (autenticada y con idToken vivo).
  bool get canSync =>
      _auth.currentUser?.idToken.isNotEmpty == true && _auth.isAccessAllowed;

  // ---------------------------------------------------------------------------
  // PUSH — local → nube
  // ---------------------------------------------------------------------------

  /// Empuja con debounce: los cambios consecutivos (mover pistas, renombrar
  /// playlists) generan un solo viaje a Firestore.
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
    if (_pushing || !canSync) return;
    _pushing = true;
    try {
      final uid = _auth.currentUser!.uid;
      final prefs = await SharedPreferences.getInstance();

      final playlists = await _db.getPlaylists();
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
        'settings': _collectSettings(prefs),
        'updatedAt': DateTime.now().toIso8601String(),
        'appVersion': Platform.operatingSystemVersion,
      };
      final metaOk = await InutilFirestoreService.instance
          .setDocument('users/$uid/data/backup_meta', meta);

      final tracks = await _db.getLocalTracks();
      final encoded = tracks.map(_trackToMap).toList(growable: false);
      final chunks = <List<Map<String, dynamic>>>[];
      var current = <Map<String, dynamic>>[];
      var currentBytes = 2; // corchetes del array
      for (final track in encoded) {
        final size = utf8.encode(jsonEncode(track)).length + 1;
        if (currentBytes + size > _chunkSoftLimitBytes && current.isNotEmpty) {
          chunks.add(current);
          current = <Map<String, dynamic>>[];
          currentBytes = 2;
        }
        current.add(track);
        currentBytes += size;
      }
      if (current.isNotEmpty) chunks.add(current);

      var tracksOk = true;
      for (var i = 0; i < chunks.length; i++) {
        final ok = await InutilFirestoreService.instance
            .setDocument('users/$uid/data/backup_tracks_$i', {
              'tracks': chunks[i],
              'updatedAt': DateTime.now().toIso8601String(),
            });
        tracksOk = tracksOk && ok;
      }
      // Borra chunk sobrantes si la biblioteca se encogió.
      for (var i = chunks.length; i < chunks.length + 4; i++) {
        final probe = await InutilFirestoreService.instance
            .getDocument('users/$uid/data/backup_tracks_$i');
        if (probe == null) break;
        await InutilFirestoreService.instance
            .deleteDocument('users/$uid/data/backup_tracks_$i');
      }

      _lastPushAt = DateTime.now();
      _lastError = metaOk && tracksOk
          ? ''
          : 'El respaldo parcial falló; se reintentará automáticamente.';
    } catch (e) {
      _lastError = 'Respaldo no completado: $e';
      debugPrint('Cloud backup push falló: $e');
    } finally {
      _pushing = false;
    }
  }

  Map<String, dynamic> _trackToMap(LocalTrack t) => <String, dynamic>{
    'id': t.id,
    'title': t.title,
    'artist': t.artist,
    'filePath': t.filePath,
    'addedAt': t.addedAt.toIso8601String(),
    if (t.sourceUrl != null) 'sourceUrl': t.sourceUrl,
    if (t.thumbnailUrl != null) 'thumbnailUrl': t.thumbnailUrl,
    if (t.catalogThumbnailUrl != null) 'catalogThumbnailUrl': t.catalogThumbnailUrl,
    if (t.duration != null) 'durationMs': t.duration!.inMilliseconds,
    if (t.album != null) 'album': t.album,
    'artists': t.artists,
    'artistBrowseIds': t.artistBrowseIds.map((e) => e ?? '').toList(),
    'metadataSource': t.metadataSource.name,
    if (t.sourceId != null) 'sourceId': t.sourceId,
  };

  Map<String, dynamic> _collectSettings(SharedPreferences prefs) {
    final result = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (_volatilePrefKeys.contains(key)) continue;
      if (key.contains('token') || key.contains('secret')) continue;
      final value = prefs.get(key);
      if (value == null) continue;
      // JSON y listas son nativos de Firestore; los bool/int/double/string
      // también. Todo lo demás se guarda como texto.
      result[key] = value;
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // PULL — nube → local (instalación nueva)
  // ---------------------------------------------------------------------------

  /// Restaura playlists/biblioteca/ajustes desde la nube. Solo escribe datos
  /// que aún NO existen localmente: una instalación nueva recupera todo, un
  /// dispositivo con biblioteca propia no es aplastado.
  Future<String> pullAndRestoreIfEmpty() async {
    if (_pulling) return 'Respaldo en curso…';
    if (!canSync) return 'Inicia sesión para restaurar tu respaldo.';
    _pulling = true;
    try {
      final uid = _auth.currentUser!.uid;
      final prefs = await SharedPreferences.getInstance();

      final meta = await InutilFirestoreService.instance
          .getDocument('users/$uid/data/backup_meta');

      var restoredPlaylists = 0;
      if (meta != null) {
        final localPlaylists = await _db.getPlaylists();
        final remote = meta['playlists'];
        if (remote is List) {
          final localIds = localPlaylists.map((p) => p.id).toSet();
          for (final raw in remote) {
            if (raw is! Map) continue;
            final playlist = _playlistFromMap(raw.cast<String, dynamic>());
            if (playlist == null) continue;
            if (localIds.contains(playlist.id)) continue;
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

      var restoredTracks = 0;
      for (var i = 0; i < 64; i++) {
        final doc = await InutilFirestoreService.instance
            .getDocument('users/$uid/data/backup_tracks_$i');
        if (doc == null) break;
        final tracks = doc['tracks'];
        if (tracks is! List) continue;
        for (final raw in tracks) {
          if (raw is! Map) continue;
          final track = _trackFromMap(raw.cast<String, dynamic>());
          if (track == null) continue;
          await _db.saveLocalTrack(track);
          restoredTracks += 1;
        }
      }

      _lastError = '';
      if (restoredPlaylists == 0 && restoredTracks == 0 && meta == null) {
        return 'Aún no hay respaldo en la nube para esta cuenta.';
      }
      return 'Respaldo restaurado: $restoredPlaylists playlists, '
          '$restoredTracks pistas.';
    } catch (e) {
      _lastError = 'Restauración no completada: $e';
      debugPrint('Cloud backup pull falló: $e');
      return 'No se pudo restaurar (¿sin conexión?). Reintenta más tarde.';
    } finally {
      _pulling = false;
    }
  }

  Playlist? _playlistFromMap(Map<String, dynamic> map) {
    final id = map['id'] as String? ?? '';
    final name = map['name'] as String? ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    final trackIds = (map['trackIds'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    return Playlist(
      id: id,
      name: name,
      trackIds: trackIds,
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      deletedAt: DateTime.tryParse(map['deletedAt']?.toString() ?? ''),
      customArtworkFileName: map['customArtworkFileName'] as String?,
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
      addedAt: DateTime.tryParse(map['addedAt']?.toString() ?? '') ?? DateTime.now(),
      sourceUrl: map['sourceUrl'] as String?,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      catalogThumbnailUrl: map['catalogThumbnailUrl'] as String?,
      duration: durationMs != null ? Duration(milliseconds: durationMs) : null,
      album: map['album'] as String?,
      artists: (map['artists'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      artistBrowseIds: (map['artistBrowseIds'] as List?)
          ?.map((e) => e?.toString())
          .toList() ??
          const [],
      sourceId: map['sourceId'] as String?,
    );
  }
}
