import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../player/player_service.dart';

/// Instantánea mínima de reproducción que el OTA guarda antes de abrir el
/// instalador de Android.
///
/// Sólo se persiste lo necesario para volver al mismo punto: identificador,
/// identidad visible, fuente y posición. La clase es inmutable para que el
/// estado de Riverpod nunca comparta referencias mutables con SharedPreferences.
class OtaPlaybackSnapshot {
  const OtaPlaybackSnapshot({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.isPlaying,
    required this.isRemote,
    required this.position,
    required this.savedAt,
    this.thumbnailUrl,
    this.sourceUrl,
    this.queueEntryId,
  });

  final String trackId;
  final String title;
  final String artist;

  /// `true` cuando el usuario quería escuchar (reproduciendo o en pausa
  /// intencional). Si es `false`, la restauración no debe iniciar audio.
  final bool isPlaying;

  /// `true` para streaming remoto (`sourceUrl` = URL pública del video),
  /// `false` para un archivo descargado de la biblioteca.
  final bool isRemote;

  final Duration position;
  final String? thumbnailUrl;
  final String? sourceUrl;
  final String? queueEntryId;
  final DateTime savedAt;

  bool get hasIdentity => trackId.isNotEmpty || (sourceUrl ?? '').isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'trackId': trackId,
    'title': title,
    'artist': artist,
    'isPlaying': isPlaying,
    'isRemote': isRemote,
    'positionMs': position.inMilliseconds,
    'thumbnailUrl': thumbnailUrl,
    'sourceUrl': sourceUrl,
    'queueEntryId': queueEntryId,
    'savedAt': savedAt.toUtc().toIso8601String(),
  };

  static OtaPlaybackSnapshot? fromJson(Object? decoded) {
    if (decoded is! Map) return null;
    final trackId = (decoded['trackId'] as String?)?.trim() ?? '';
    final sourceUrl = (decoded['sourceUrl'] as String?)?.trim() ?? '';
    if (trackId.isEmpty && sourceUrl.isEmpty) return null;
    final savedAt =
        DateTime.tryParse(decoded['savedAt']?.toString() ?? '') ??
        DateTime.utc(2026);
    return OtaPlaybackSnapshot(
      trackId: trackId,
      title: (decoded['title'] as String?)?.trim() ?? '',
      artist: (decoded['artist'] as String?)?.trim() ?? '',
      isPlaying: decoded['isPlaying'] as bool? ?? true,
      isRemote: decoded['isRemote'] as bool? ?? true,
      position: Duration(
        milliseconds: (decoded['positionMs'] as num?)?.toInt() ?? 0,
      ),
      thumbnailUrl: (decoded['thumbnailUrl'] as String?)?.trim(),
      sourceUrl: sourceUrl.isEmpty ? null : sourceUrl,
      queueEntryId: (decoded['queueEntryId'] as String?)?.trim(),
      savedAt: savedAt,
    );
  }

  /// Construye la instantánea desde el estado vivo del reproductor.
  ///
  /// Devuelve `null` cuando no hay nada que restaurar (pantalla en reposo,
  /// pista sin identidad o audio detenido explícitamente).
  static OtaPlaybackSnapshot? fromPlayerSnapshot(
    PlayerSnapshot? snapshot, {
    DateTime? now,
  }) {
    if (snapshot == null) return null;
    final trackId = (snapshot.trackId ?? '').trim();
    final sourceUrl = (snapshot.sourceUrl ?? '').trim();
    if (trackId.isEmpty && sourceUrl.isEmpty) return null;
    if (snapshot.status == PlayerStatus.idle ||
        snapshot.status == PlayerStatus.stopped) {
      return null;
    }
    return OtaPlaybackSnapshot(
      trackId: trackId,
      title: snapshot.title ?? '',
      artist: snapshot.artist ?? '',
      isPlaying: snapshot.wantsToPlay,
      isRemote: snapshot.isRemote,
      position: snapshot.position,
      thumbnailUrl: snapshot.thumbnailUrl,
      sourceUrl: sourceUrl.isEmpty ? null : sourceUrl,
      queueEntryId: snapshot.queueEntryId,
      savedAt: now?.toUtc() ?? DateTime.now().toUtc(),
    );
  }
}

/// Almacén de la instantánea de reproducción del OTA.
///
/// Se guarda en `SharedPreferences` (no en la base de datos) porque debe
/// sobrevivir al reemplazo del paquete: cuando Android mata el proceso de
/// Inutix Music para instalar el APK nuevo, la única forma de saber qué se
/// estaba escuchando es un archivo clave-valor que la nueva versión lee en el
/// arranque.
class OtaPlaybackResumeStore {
  const OtaPlaybackResumeStore();

  static const String storageKey = 'inutil_music_ota_playback_resume_v1';

  /// Ventana de validez. Una instalación fallida o un "Ahora no" antiguo no
  /// deben reclamar la reproducción días después.
  static const Duration maxAge = Duration(minutes: 30);

  Future<void> write(OtaPlaybackSnapshot snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode(snapshot.toJson()));
    } catch (_) {}
  }

  Future<OtaPlaybackSnapshot?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return null;
      final snapshot = OtaPlaybackSnapshot.fromJson(jsonDecode(raw));
      if (snapshot == null) {
        await clear();
        return null;
      }
      if (DateTime.now().toUtc().difference(snapshot.savedAt) > maxAge) {
        await clear();
        return null;
      }
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  /// Lee y elimina en un solo paso: la reproducción se restaura una única vez.
  Future<OtaPlaybackSnapshot?> consume() async {
    final snapshot = await read();
    if (snapshot != null) {
      await clear();
    }
    return snapshot;
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (_) {}
  }
}

/// Preferencia que controla el chequeo OTA al abrir la app.
///
/// Vive separado de `settings_controller_provider` para que el arranque pueda
/// leerlo sin instanciar el controlador completo de Ajustes (que carga base de
/// datos y directorios) y así no bloquear el inicio.
class OtaPreferences {
  const OtaPreferences();

  static const String autoUpdateKey = 'inutil_music_auto_updates_enabled';
  static const String dismissedVersionKey =
      'inutil_music_update_dismissed_version';
  static const String lastSeenVersionKey = 'inutil_music_last_seen_version';

  /// Por defecto las actualizaciones automáticas están activadas.
  Future<bool> automaticUpdatesEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(autoUpdateKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> setAutomaticUpdatesEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(autoUpdateKey, enabled);
    } catch (_) {}
  }

  Future<String> dismissedVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(dismissedVersionKey) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> setDismissedVersion(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(dismissedVersionKey, version);
    } catch (_) {}
  }

  Future<void> clearDismissedVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(dismissedVersionKey);
    } catch (_) {}
  }

  Future<String> lastSeenVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(lastSeenVersionKey) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> setLastSeenVersion(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastSeenVersionKey, version);
    } catch (_) {}
  }
}

/// Texto auxiliar reutilizable para formatear tamaños del OTA.
String formatOtaBytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  final mebibytes = bytes / (1024 * 1024);
  if (mebibytes >= 1024) {
    return '${(mebibytes / 1024).toStringAsFixed(2)} GB';
  }
  return '${mebibytes.toStringAsFixed(1)} MB';
}
