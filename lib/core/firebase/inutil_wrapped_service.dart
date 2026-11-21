import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/music/domain/entities/local_track.dart';
import 'firebase_auth_service.dart';
import 'firebase_config.dart';
import 'firebase_firestore_service.dart';

@immutable
class WrappedTrackStat {
  const WrappedTrackStat({
    required this.id,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    required this.plays,
    required this.seconds,
  });

  final String id;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final int plays;
  final int seconds;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'artist': artist,
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
      'thumbnailUrl': thumbnailUrl,
    'plays': plays,
    'seconds': seconds,
  };

  factory WrappedTrackStat.fromJson(Map<String, dynamic> json) =>
      WrappedTrackStat(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? 'Canción').toString(),
        artist: (json['artist'] ?? 'Inútil Music').toString(),
        thumbnailUrl: json['thumbnailUrl']?.toString(),
        plays: (json['plays'] as num?)?.toInt() ?? 0,
        seconds: (json['seconds'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class WrappedArtistStat {
  const WrappedArtistStat({
    required this.name,
    this.thumbnailUrl,
    required this.plays,
    required this.seconds,
  });

  final String name;
  final String? thumbnailUrl;
  final int plays;
  final int seconds;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
      'thumbnailUrl': thumbnailUrl,
    'plays': plays,
    'seconds': seconds,
  };

  factory WrappedArtistStat.fromJson(Map<String, dynamic> json) =>
      WrappedArtistStat(
        name: (json['name'] ?? 'Artista').toString(),
        thumbnailUrl: json['thumbnailUrl']?.toString(),
        plays: (json['plays'] as num?)?.toInt() ?? 0,
        seconds: (json['seconds'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class InutilWrappedSummary {
  const InutilWrappedSummary({
    required this.year,
    required this.totalSeconds,
    required this.totalPlays,
    required this.topTracks,
    required this.topArtists,
    required this.uniqueTrackCount,
    required this.uniqueArtistCount,
    required this.activeDaysCount,
    required this.peakHour,
    this.fromHistoryFallback = false,
  });

  final int year;
  final int totalSeconds;
  final int totalPlays;
  final List<WrappedTrackStat> topTracks;
  final List<WrappedArtistStat> topArtists;
  final int uniqueTrackCount;
  final int uniqueArtistCount;
  final int activeDaysCount;
  final int peakHour;
  final bool fromHistoryFallback;

  int get totalMinutes => (totalSeconds / 60).round();
  double get totalHours => totalSeconds / 3600.0;
  int get equivalentAlbums => (totalMinutes / 42).ceil().clamp(1, 9999);
  WrappedArtistStat? get topArtist =>
      topArtists.isNotEmpty ? topArtists.first : null;
  WrappedTrackStat? get topTrack =>
      topTracks.isNotEmpty ? topTracks.first : null;

  bool get hasListeningData => totalPlays > 0 || topTracks.isNotEmpty;

  ({String emoji, String title, String subtitle}) get listeningScheduleVibe {
    if (peakHour >= 22 || peakHour < 5) {
      return (
        emoji: '🌙',
        title: 'Alma nocturna',
        subtitle: 'Tus mejores sesiones llegan cuando la ciudad se apaga.',
      );
    }
    if (peakHour >= 5 && peakHour < 12) {
      return (
        emoji: '☀️',
        title: 'Energía matutina',
        subtitle: 'Arrancas cada mañana poniéndole ritmo al día.',
      );
    }
    if (peakHour >= 12 && peakHour < 18) {
      return (
        emoji: '⚡',
        title: 'Ritmo de tarde',
        subtitle: 'La música es tu combustible durante las horas más activas.',
      );
    }
    return (
      emoji: '🌅',
      title: 'Atardecer musical',
      subtitle: 'Cierres de jornada siempre acompañados de buena música.',
    );
  }

  ({String emoji, String title, String description}) get personalityArchetype {
    final topTrackShare = totalPlays > 0 && topTrack != null
        ? topTrack!.plays / totalPlays
        : 0.0;
    if (topTrackShare >= 0.18 && (topTrack?.plays ?? 0) >= 5) {
      return (
        emoji: '🔁',
        title: 'El Insaciable del Repeat',
        description:
            'Cuando una canción te atrapa, no la sueltas hasta sabértela de memoria.',
      );
    }
    if (peakHour >= 22 || peakHour < 5) {
      return (
        emoji: '🌙',
        title: 'Noctámbulo Melómano',
        description:
            'Vives tus mejores playlists bajo las luces de la noche y sin prisas.',
      );
    }
    if (uniqueArtistCount >= 12 &&
        totalPlays > 0 &&
        uniqueArtistCount / totalPlays >= 0.45) {
      return (
        emoji: '🧭',
        title: 'Explorador Sin Fronteras',
        description:
            'Siempre descubres voces nuevas y saltas de género en género con naturalidad.',
      );
    }
    return (
      emoji: '🎧',
      title: 'Corazón de Playlist',
      description:
          'Tienes el oído fino para armar la banda sonora exacta de cada momento.',
    );
  }
}

/// Motor de estadísticas anuales («Inútil Wrapped») con respaldo automático en
/// Firestore (`users/{uid}/data/wrapped_<year>`).
///
/// Acumula en memoria durante la reproducción (cero I/O en el hilo de audio) y
/// guarda en local + nube de forma diferida al pausar o cambiar de canción.
class InutilWrappedService {
  InutilWrappedService._();
  static final InutilWrappedService instance = InutilWrappedService._();

  static const _prefsPrefix = 'inutil_wrapped_stats_v1_';
  static const _prefsShownYearKey = 'inutil_wrapped_auto_shown_year_v1';
  static const _maxStoredTracks = 120;
  static const _maxStoredArtists = 80;
  static const _minSecondsForPlay = 15;

  final Map<int, _YearBucket> _buckets = <int, _YearBucket>{};
  String? _activeTrackId;
  String _activeTitle = '';
  String _activeArtist = '';
  String? _activeThumb;
  int _activePositionMs = 0;
  int _activeAccumulatedSec = 0;
  bool _activePlayCounted = false;
  bool _dirty = false;
  Timer? _persistTimer;
  Timer? _cloudPushTimer;

  bool get _canSyncCloud =>
      InutilAuthService.instance.currentUser?.idToken.isNotEmpty == true &&
      InutilAuthService.instance.isAccessAllowed;

  /// Registra el progreso en vivo desde `playerControllerProvider` sin bloquear
  /// el audio ni escribir en disco en cada tick.
  void recordPlaybackTick({
    required String? trackId,
    required String? title,
    required String? artist,
    required String? thumbnailUrl,
    required int positionMs,
    required bool isPlaying,
  }) {
    final normalizedId = (trackId ?? '').trim();
    if (normalizedId.isEmpty) {
      _flushActiveTrack();
      return;
    }

    if (_activeTrackId != normalizedId) {
      _flushActiveTrack();
      _activeTrackId = normalizedId;
      _activeTitle = (title ?? '').trim().isNotEmpty
          ? title!.trim()
          : 'Canción';
      _activeArtist = (artist ?? '').trim().isNotEmpty
          ? artist!.trim()
          : 'Inútil Music';
      _activeThumb = thumbnailUrl;
      _activePositionMs = positionMs;
      _activeAccumulatedSec = 0;
      _activePlayCounted = false;
      return;
    }

    // Actualiza metadatos si llegaron tarde (p. ej. tras resolver InnerTube).
    if ((title ?? '').trim().isNotEmpty) _activeTitle = title!.trim();
    if ((artist ?? '').trim().isNotEmpty) _activeArtist = artist!.trim();
    if ((thumbnailUrl ?? '').trim().isNotEmpty) _activeThumb = thumbnailUrl;

    if (!isPlaying) {
      _activePositionMs = positionMs;
      if (_dirty) _schedulePersist();
      return;
    }

    final deltaMs = positionMs - _activePositionMs;
    _activePositionMs = positionMs;
    // Ignorar saltos bruscos de seek (> 12 s) o retrocesos negativos.
    if (deltaMs <= 0 || deltaMs > 12000) return;

    final deltaSec = (deltaMs / 1000).round();
    if (deltaSec <= 0) return;

    final now = DateTime.now();
    final bucket = _ensureBucketInMemory(now.year);
    _addListeningDelta(
      bucket: bucket,
      trackId: normalizedId,
      title: _activeTitle,
      artist: _activeArtist,
      thumbnailUrl: _activeThumb,
      deltaSec: deltaSec,
      now: now,
    );
  }

  void _addListeningDelta({
    required _YearBucket bucket,
    required String trackId,
    required String title,
    required String artist,
    required String? thumbnailUrl,
    required int deltaSec,
    required DateTime now,
  }) {
    bucket.totalSeconds += deltaSec;
    bucket.hourBuckets[now.hour] =
        (bucket.hourBuckets[now.hour] ?? 0) + deltaSec;
    final dayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    bucket.activeDays.add(dayKey);

    _activeAccumulatedSec += deltaSec;
    var incrementPlay = 0;
    if (!_activePlayCounted && _activeAccumulatedSec >= _minSecondsForPlay) {
      _activePlayCounted = true;
      incrementPlay = 1;
      bucket.totalPlays += 1;
    }

    final existingTrack = bucket.tracks[trackId];
    bucket.tracks[trackId] = WrappedTrackStat(
      id: trackId,
      title: title,
      artist: artist,
      thumbnailUrl: (thumbnailUrl?.isNotEmpty == true)
          ? thumbnailUrl
          : existingTrack?.thumbnailUrl,
      plays: (existingTrack?.plays ?? 0) + incrementPlay,
      seconds: (existingTrack?.seconds ?? 0) + deltaSec,
    );

    final primaryArtist = _primaryArtistName(artist);
    final artistKey = primaryArtist.toLowerCase();
    final existingArtist = bucket.artists[artistKey];
    bucket.artists[artistKey] = WrappedArtistStat(
      name: existingArtist?.name ?? primaryArtist,
      thumbnailUrl: (thumbnailUrl?.isNotEmpty == true)
          ? thumbnailUrl
          : existingArtist?.thumbnailUrl,
      plays: (existingArtist?.plays ?? 0) + incrementPlay,
      seconds: (existingArtist?.seconds ?? 0) + deltaSec,
    );

    _dirty = true;
    _schedulePersist();
  }

  void _flushActiveTrack() {
    _activeTrackId = null;
    _activePositionMs = 0;
    _activeAccumulatedSec = 0;
    _activePlayCounted = false;
    if (_dirty) _schedulePersist(immediate: true);
  }

  String _primaryArtistName(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return 'Inútil Music';
    final split = cleaned.split(
      RegExp(r'\s*(?:,|&|feat\.|ft\.|x|•)\s*', caseSensitive: false),
    );
    final first = split.first.trim();
    return first.isEmpty ? cleaned : first;
  }

  _YearBucket _ensureBucketInMemory(int year) {
    return _buckets.putIfAbsent(year, () => _YearBucket(year: year));
  }

  void _schedulePersist({bool immediate = false}) {
    _persistTimer?.cancel();
    _persistTimer = Timer(
      immediate
          ? const Duration(milliseconds: 400)
          : const Duration(seconds: 15),
      () => unawaited(persistNow()),
    );
    _cloudPushTimer?.cancel();
    _cloudPushTimer = Timer(
      const Duration(seconds: 45),
      () => unawaited(syncCurrentYearToCloud()),
    );
  }

  Future<void> persistNow({int? year}) async {
    final targetYear = year ?? DateTime.now().year;
    final bucket = _buckets[targetYear];
    if (bucket == null) return;
    _dirty = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!bucket.hydratedFromDisk) {
        final existingRaw = prefs.getString('$_prefsPrefix$targetYear');
        if (existingRaw != null && existingRaw.isNotEmpty) {
          final diskBucket = _YearBucket.fromJsonString(
            targetYear,
            existingRaw,
          );
          bucket.mergeFrom(diskBucket);
        }
        bucket.hydratedFromDisk = true;
      }
      bucket.prune(_maxStoredTracks, _maxStoredArtists);
      await prefs.setString('$_prefsPrefix$targetYear', bucket.toJsonString());
    } catch (e) {
      debugPrint('Wrapped local persist failed: $e');
    }
  }

  Future<_YearBucket> _loadBucket(int year) async {
    final bucket = _ensureBucketInMemory(year);
    if (!bucket.hydratedFromDisk) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefsPrefix$year');
      if (raw != null && raw.isNotEmpty) {
        final disk = _YearBucket.fromJsonString(year, raw);
        bucket.mergeFrom(disk);
      }
      bucket.hydratedFromDisk = true;
    }
    return bucket;
  }

  /// Empuja las estadísticas anuales del usuario a Firestore
  /// (`users/{uid}/data/wrapped_<year>`) para que sobrevivan desinstalaciones
  /// y también permitan conocer las preferencias de la comunidad.
  Future<void> syncCurrentYearToCloud({int? year}) async {
    if (!_canSyncCloud) return;
    final targetYear = year ?? DateTime.now().year;
    try {
      final bucket = await _loadBucket(targetYear);
      if (bucket.totalSeconds == 0 && bucket.totalPlays == 0) return;
      final uid = InutilAuthService.instance.currentUser!.uid;
      bucket.prune(_maxStoredTracks, _maxStoredArtists);
      await InutilFirestoreService.instance.setDocument(
        'users/$uid/data/wrapped_$targetYear',
        bucket.toFirestoreMap(),
      );
    } catch (e) {
      debugPrint('Wrapped cloud push failed: $e');
    }
  }

  /// Restaura las estadísticas anuales desde Firestore tras reinstalar la app
  /// o borrar datos locales, fusionándolas sin perder lo escuchado hoy.
  Future<void> pullYearFromCloud({int? year}) async {
    if (!_canSyncCloud) return;
    final targetYear = year ?? DateTime.now().year;
    try {
      final uid = InutilAuthService.instance.currentUser!.uid;
      final remote = await InutilFirestoreService.instance.getDocument(
        'users/$uid/data/wrapped_$targetYear',
      );
      if (remote == null) return;
      final remoteBucket = _YearBucket.fromMap(targetYear, remote);
      final local = await _loadBucket(targetYear);
      local.mergeTakingMax(remoteBucket);
      local.prune(_maxStoredTracks, _maxStoredArtists);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefsPrefix$targetYear', local.toJsonString());
    } catch (e) {
      debugPrint('Wrapped cloud pull failed: $e');
    }
  }

  /// Construye el resumen anual listo para mostrar en el pop-up animado.
  /// Si el usuario acaba de actualizar y todavía no acumula suficiente tiempo
  /// registrado en el nuevo motor, complementa desde su historial real para
  /// ofrecerle una vista previa fiel desde el primer día.
  Future<InutilWrappedSummary> buildSummary({
    int? year,
    List<LocalTrack> fallbackHistory = const <LocalTrack>[],
  }) async {
    final targetYear = year ?? DateTime.now().year;
    await persistNow(year: targetYear);
    final bucket = await _loadBucket(targetYear);

    if (bucket.totalPlays > 0 || bucket.tracks.isNotEmpty) {
      return bucket.toSummary();
    }

    if (fallbackHistory.isNotEmpty) {
      return _buildFromHistoryFallback(targetYear, fallbackHistory);
    }

    return InutilWrappedSummary(
      year: targetYear,
      totalSeconds: 0,
      totalPlays: 0,
      topTracks: const [],
      topArtists: const [],
      uniqueTrackCount: 0,
      uniqueArtistCount: 0,
      activeDaysCount: 0,
      peakHour: DateTime.now().hour,
      fromHistoryFallback: true,
    );
  }

  InutilWrappedSummary _buildFromHistoryFallback(
    int year,
    List<LocalTrack> history,
  ) {
    final tracks = <String, WrappedTrackStat>{};
    final artists = <String, WrappedArtistStat>{};
    var totalSeconds = 0;
    for (final item in history) {
      final sec = (item.duration?.inSeconds ?? 210).clamp(60, 600);
      totalSeconds += sec;
      final prevTrack = tracks[item.id];
      tracks[item.id] = WrappedTrackStat(
        id: item.id,
        title: item.title,
        artist: item.artist,
        thumbnailUrl: item.thumbnailUrl ?? item.catalogThumbnailUrl,
        plays: (prevTrack?.plays ?? 0) + 1,
        seconds: (prevTrack?.seconds ?? 0) + sec,
      );
      final artistName = _primaryArtistName(item.artist);
      final key = artistName.toLowerCase();
      final prevArtist = artists[key];
      artists[key] = WrappedArtistStat(
        name: prevArtist?.name ?? artistName,
        thumbnailUrl:
            item.thumbnailUrl ??
            item.catalogThumbnailUrl ??
            prevArtist?.thumbnailUrl,
        plays: (prevArtist?.plays ?? 0) + 1,
        seconds: (prevArtist?.seconds ?? 0) + sec,
      );
    }
    final topTracks = tracks.values.toList()
      ..sort((a, b) => b.seconds.compareTo(a.seconds));
    final topArtists = artists.values.toList()
      ..sort((a, b) => b.seconds.compareTo(a.seconds));
    return InutilWrappedSummary(
      year: year,
      totalSeconds: totalSeconds,
      totalPlays: history.length,
      topTracks: topTracks.take(5).toList(growable: false),
      topArtists: topArtists.take(5).toList(growable: false),
      uniqueTrackCount: tracks.length,
      uniqueArtistCount: artists.length,
      activeDaysCount: history.length.clamp(1, 30),
      peakHour: DateTime.now().hour,
      fromHistoryFallback: true,
    );
  }

  /// Determina si corresponde lanzar automáticamente el pop-up animado de fin
  /// de año (1 de diciembre al 15 de enero, una sola vez por año, o activado
  /// remotamente desde Firestore `app_config/wrapped_campaign`).
  Future<int?> evaluateAutoWrappedYear({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final alreadyShownYear = prefs.getInt(_prefsShownYearKey) ?? 0;

    // 1. Posibilidad de activar Wrapped remotamente en cualquier fecha.
    final remoteYear = await _fetchRemoteForcedWrappedYear();
    if (remoteYear != null && remoteYear != alreadyShownYear) {
      await prefs.setInt(_prefsShownYearKey, remoteYear);
      return remoteYear;
    }

    // 2. Ventana automática de fin de año: 1 dic – 15 ene.
    int? targetYear;
    if (current.month == DateTime.december) {
      targetYear = current.year;
    } else if (current.month == DateTime.january && current.day <= 15) {
      targetYear = current.year - 1;
    }
    if (targetYear == null || targetYear == alreadyShownYear) return null;

    await prefs.setInt(_prefsShownYearKey, targetYear);
    return targetYear;
  }

  Future<int?> _fetchRemoteForcedWrappedYear() async {
    try {
      final uri = Uri.parse(
        '${FirebaseConfig.firestoreBaseUrl}/app_config/wrapped_campaign?key=${FirebaseConfig.apiKey}',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      final fields = decoded['fields'];
      if (fields is! Map<String, dynamic>) return null;
      final enabled =
          (fields['enabled'] as Map<String, dynamic>?)?['booleanValue'] == true;
      if (!enabled) return null;
      final yearRaw =
          (fields['year'] as Map<String, dynamic>?)?['integerValue'] ??
          (fields['year'] as Map<String, dynamic>?)?['stringValue'];
      return int.tryParse(yearRaw?.toString() ?? '') ?? DateTime.now().year;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _persistTimer?.cancel();
    _cloudPushTimer?.cancel();
    _buckets.clear();
    _activeTrackId = null;
    _activePositionMs = 0;
    _activeAccumulatedSec = 0;
    _activePlayCounted = false;
    _dirty = false;
  }
}

class _YearBucket {
  _YearBucket({required this.year});

  final int year;
  int totalSeconds = 0;
  int totalPlays = 0;
  final Map<String, WrappedTrackStat> tracks = <String, WrappedTrackStat>{};
  final Map<String, WrappedArtistStat> artists = <String, WrappedArtistStat>{};
  final Map<int, int> hourBuckets = <int, int>{};
  final Set<String> activeDays = <String>{};
  bool hydratedFromDisk = false;

  void mergeFrom(_YearBucket other) {
    totalSeconds += other.totalSeconds;
    totalPlays += other.totalPlays;
    other.hourBuckets.forEach((h, sec) {
      hourBuckets[h] = (hourBuckets[h] ?? 0) + sec;
    });
    activeDays.addAll(other.activeDays);
    other.tracks.forEach((id, stat) {
      final cur = tracks[id];
      tracks[id] = WrappedTrackStat(
        id: id,
        title: cur?.title ?? stat.title,
        artist: cur?.artist ?? stat.artist,
        thumbnailUrl: cur?.thumbnailUrl ?? stat.thumbnailUrl,
        plays: (cur?.plays ?? 0) + stat.plays,
        seconds: (cur?.seconds ?? 0) + stat.seconds,
      );
    });
    other.artists.forEach((key, stat) {
      final cur = artists[key];
      artists[key] = WrappedArtistStat(
        name: cur?.name ?? stat.name,
        thumbnailUrl: cur?.thumbnailUrl ?? stat.thumbnailUrl,
        plays: (cur?.plays ?? 0) + stat.plays,
        seconds: (cur?.seconds ?? 0) + stat.seconds,
      );
    });
  }

  /// Al restaurar desde la nube, toma el máximo por clave para evitar duplicar
  /// contadores si parte de los datos ya estaba en local.
  void mergeTakingMax(_YearBucket remote) {
    if (remote.totalSeconds > totalSeconds) totalSeconds = remote.totalSeconds;
    if (remote.totalPlays > totalPlays) totalPlays = remote.totalPlays;
    remote.hourBuckets.forEach((h, sec) {
      final cur = hourBuckets[h] ?? 0;
      if (sec > cur) hourBuckets[h] = sec;
    });
    activeDays.addAll(remote.activeDays);
    remote.tracks.forEach((id, stat) {
      final cur = tracks[id];
      if (cur == null || stat.seconds > cur.seconds) {
        tracks[id] = stat;
      }
    });
    remote.artists.forEach((key, stat) {
      final cur = artists[key];
      if (cur == null || stat.seconds > cur.seconds) {
        artists[key] = stat;
      }
    });
  }

  void prune(int maxTracks, int maxArtists) {
    if (tracks.length > maxTracks) {
      final sorted = tracks.entries.toList()
        ..sort((a, b) => b.value.seconds.compareTo(a.value.seconds));
      tracks
        ..clear()
        ..addEntries(sorted.take(maxTracks));
    }
    if (artists.length > maxArtists) {
      final sorted = artists.entries.toList()
        ..sort((a, b) => b.value.seconds.compareTo(a.value.seconds));
      artists
        ..clear()
        ..addEntries(sorted.take(maxArtists));
    }
  }

  InutilWrappedSummary toSummary() {
    final sortedTracks = tracks.values.toList()
      ..sort((a, b) {
        final byPlays = b.plays.compareTo(a.plays);
        return byPlays != 0 ? byPlays : b.seconds.compareTo(a.seconds);
      });
    final sortedArtists = artists.values.toList()
      ..sort((a, b) => b.seconds.compareTo(a.seconds));
    var peakHour = 21;
    var bestSec = -1;
    hourBuckets.forEach((h, sec) {
      if (sec > bestSec) {
        bestSec = sec;
        peakHour = h;
      }
    });
    return InutilWrappedSummary(
      year: year,
      totalSeconds: totalSeconds,
      totalPlays: totalPlays,
      topTracks: sortedTracks.take(5).toList(growable: false),
      topArtists: sortedArtists.take(5).toList(growable: false),
      uniqueTrackCount: tracks.length,
      uniqueArtistCount: artists.length,
      activeDaysCount: activeDays.length,
      peakHour: peakHour,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    final summary = toSummary();
    return <String, dynamic>{
      'year': year,
      'totalSeconds': totalSeconds,
      'totalPlays': totalPlays,
      'uniqueTrackCount': tracks.length,
      'uniqueArtistCount': artists.length,
      'activeDays': activeDays.toList(growable: false),
      'hourBuckets': <String, int>{
        for (final entry in hourBuckets.entries) '${entry.key}': entry.value,
      },
      'topArtistName': summary.topArtist?.name ?? '',
      'topTrackTitle': summary.topTrack?.title ?? '',
      'tracks': tracks.values.map((t) => t.toJson()).toList(growable: false),
      'artists': artists.values.map((a) => a.toJson()).toList(growable: false),
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  String toJsonString() => jsonEncode(toFirestoreMap());

  factory _YearBucket.fromJsonString(int year, String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return _YearBucket.fromMap(year, decoded);
      }
    } catch (_) {}
    return _YearBucket(year: year);
  }

  factory _YearBucket.fromMap(int year, Map<String, dynamic> map) {
    final bucket = _YearBucket(year: year)
      ..totalSeconds = (map['totalSeconds'] as num?)?.toInt() ?? 0
      ..totalPlays = (map['totalPlays'] as num?)?.toInt() ?? 0;

    final days = map['activeDays'];
    if (days is List) {
      for (final d in days) {
        final s = d.toString().trim();
        if (s.isNotEmpty) bucket.activeDays.add(s);
      }
    }
    final hours = map['hourBuckets'];
    if (hours is Map) {
      hours.forEach((k, v) {
        final h = int.tryParse(k.toString());
        final sec = (v as num?)?.toInt() ?? 0;
        if (h != null && h >= 0 && h < 24 && sec > 0) {
          bucket.hourBuckets[h] = sec;
        }
      });
    }
    final rawTracks = map['tracks'];
    if (rawTracks is List) {
      for (final item in rawTracks) {
        if (item is Map) {
          final stat = WrappedTrackStat.fromJson(item.cast<String, dynamic>());
          if (stat.id.isNotEmpty) bucket.tracks[stat.id] = stat;
        }
      }
    }
    final rawArtists = map['artists'];
    if (rawArtists is List) {
      for (final item in rawArtists) {
        if (item is Map) {
          final stat = WrappedArtistStat.fromJson(item.cast<String, dynamic>());
          if (stat.name.isNotEmpty) {
            bucket.artists[stat.name.toLowerCase()] = stat;
          }
        }
      }
    }
    return bucket;
  }
}
