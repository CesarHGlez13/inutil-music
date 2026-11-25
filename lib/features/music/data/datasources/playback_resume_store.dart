import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../services/player/player_service.dart';
import '../../domain/entities/local_track.dart';
import '../../domain/entities/track_info.dart';

/// Serialized entry inside [SavedPlaybackSession] (either a remote catalog track,
/// a local audio file, or both for hybrid downloaded items).
@immutable
class SavedPlaybackQueueEntry {
  const SavedPlaybackQueueEntry({this.remote, this.local});

  final TrackInfo? remote;
  final LocalTrack? local;

  bool get isValid => remote != null || local != null;

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (remote != null) 'remote': _encodeTrackInfo(remote!),
    if (local != null) 'local': _encodeLocalTrack(local!),
  };

  static SavedPlaybackQueueEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final remote = _decodeTrackInfo(map['remote']);
    final local = _decodeLocalTrack(map['local']);
    if (remote == null && local == null) return null;
    return SavedPlaybackQueueEntry(remote: remote, local: local);
  }
}

/// Persisted snapshot of the last played song, exact playback timestamp
/// (minute:second), immediate queue, and playback options across app restarts.
@immutable
class SavedPlaybackSession {
  const SavedPlaybackSession({
    required this.accountUid,
    required this.queue,
    required this.currentIndex,
    required this.positionMs,
    required this.durationMs,
    required this.repeatMode,
    required this.shuffleEnabled,
    required this.savedAtMs,
  });

  final String? accountUid;
  final List<SavedPlaybackQueueEntry> queue;
  final int currentIndex;
  final int positionMs;
  final int durationMs;
  final PlaybackRepeatMode repeatMode;
  final bool shuffleEnabled;
  final int savedAtMs;

  SavedPlaybackQueueEntry? get currentEntry =>
      currentIndex >= 0 && currentIndex < queue.length
      ? queue[currentIndex]
      : null;

  Duration get clampedPosition {
    if (positionMs <= 0) return Duration.zero;
    if (durationMs > 2500 && positionMs >= durationMs - 2000) {
      // If the user closed the app right at the very end of the track,
      // restart cleanly from 0:00 of that same track.
      return Duration.zero;
    }
    return Duration(milliseconds: positionMs);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': 1,
    if (accountUid != null && accountUid!.isNotEmpty) 'accountUid': accountUid,
    'queue': queue.map((e) => e.toJson()).toList(growable: false),
    'currentIndex': currentIndex,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'repeatMode': repeatMode.name,
    'shuffleEnabled': shuffleEnabled,
    'savedAtMs': savedAtMs,
  };

  static SavedPlaybackSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final rawQueue = map['queue'];
    if (rawQueue is! List || rawQueue.isEmpty) return null;
    final entries = rawQueue
        .map(SavedPlaybackQueueEntry.fromJson)
        .whereType<SavedPlaybackQueueEntry>()
        .toList(growable: false);
    if (entries.isEmpty) return null;

    final rawIndex = (map['currentIndex'] as num?)?.toInt() ?? 0;
    final safeIndex = rawIndex.clamp(0, entries.length - 1);
    final repeatName = (map['repeatMode'] ?? 'off').toString();
    final repeatMode = PlaybackRepeatMode.values.firstWhere(
      (mode) => mode.name == repeatName,
      orElse: () => PlaybackRepeatMode.off,
    );

    return SavedPlaybackSession(
      accountUid: map['accountUid']?.toString(),
      queue: List<SavedPlaybackQueueEntry>.unmodifiable(entries),
      currentIndex: safeIndex,
      positionMs: ((map['positionMs'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30),
      durationMs: ((map['durationMs'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30),
      repeatMode: repeatMode,
      shuffleEnabled: map['shuffleEnabled'] == true,
      savedAtMs: (map['savedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Lightweight local store for remembering the last active track and exact
/// playback position across cold restarts.
class PlaybackResumeStore {
  const PlaybackResumeStore({
    this.storageKey = defaultStorageKey,
    this.maxQueueEntries = 30,
    this.verifyLocalFiles = true,
  });

  static const String defaultStorageKey = 'inutix.playback.resume_session.v1';

  final String storageKey;
  final int maxQueueEntries;
  final bool verifyLocalFiles;

  Future<void> save(SavedPlaybackSession session) async {
    if (session.queue.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final trimmed = _trimWindow(session, maxQueueEntries);
      await prefs.setString(storageKey, jsonEncode(trimmed.toJson()));
    } catch (error) {
      debugPrint('PlaybackResumeStore.save error: $error');
    }
  }

  Future<SavedPlaybackSession?> load({String? expectedAccountUid}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      final parsed = SavedPlaybackSession.fromJson(decoded);
      if (parsed == null) return null;

      // Strict per-account isolation: never leak one user's last played track
      // into another account after switching users.
      final savedUid = parsed.accountUid?.trim() ?? '';
      final currentUid = expectedAccountUid?.trim() ?? '';
      if (savedUid.isNotEmpty &&
          currentUid.isNotEmpty &&
          savedUid != currentUid) {
        return null;
      }

      final current = parsed.currentEntry;
      if (current == null) return null;

      // If the restored item is local-only and its file was removed from disk,
      // discard cleanly rather than showing a broken mini-player.
      if (verifyLocalFiles && current.remote == null && current.local != null) {
        final filePath = current.local!.filePath.trim();
        if (filePath.isEmpty || !File(filePath).existsSync()) {
          await clear();
          return null;
        }
      }

      return parsed;
    } catch (error) {
      debugPrint('PlaybackResumeStore.load error: $error');
      return null;
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (error) {
      debugPrint('PlaybackResumeStore.clear error: $error');
    }
  }

  static SavedPlaybackSession _trimWindow(
    SavedPlaybackSession session,
    int maxItems,
  ) {
    if (session.queue.length <= maxItems) return session;
    final idx = session.currentIndex.clamp(0, session.queue.length - 1);
    final half = maxItems ~/ 2;
    var start = (idx - half).clamp(0, session.queue.length - maxItems);
    final end = (start + maxItems).clamp(start + 1, session.queue.length);
    return SavedPlaybackSession(
      accountUid: session.accountUid,
      queue: List<SavedPlaybackQueueEntry>.unmodifiable(
        session.queue.sublist(start, end),
      ),
      currentIndex: idx - start,
      positionMs: session.positionMs,
      durationMs: session.durationMs,
      repeatMode: session.repeatMode,
      shuffleEnabled: session.shuffleEnabled,
      savedAtMs: session.savedAtMs,
    );
  }
}

Map<String, dynamic> _encodeTrackInfo(TrackInfo track) {
  final clean = track.withoutAudioTransport();
  return <String, dynamic>{
    'id': clean.id,
    'title': clean.title,
    'artist': clean.artist,
    'url': clean.url,
    if (clean.thumbnailUrl != null && clean.thumbnailUrl!.isNotEmpty)
      'thumbnailUrl': clean.thumbnailUrl,
    if (clean.catalogThumbnailUrl != null &&
        clean.catalogThumbnailUrl!.isNotEmpty)
      'catalogThumbnailUrl': clean.catalogThumbnailUrl,
    if (clean.duration != null) 'durationMs': clean.duration!.inMilliseconds,
    if (clean.album != null && clean.album!.isNotEmpty) 'album': clean.album,
    if (clean.albumBrowseId != null && clean.albumBrowseId!.isNotEmpty)
      'albumBrowseId': clean.albumBrowseId,
    if (clean.artists.isNotEmpty) 'artists': clean.artists,
    if (clean.artistBrowseIds.isNotEmpty)
      'artistBrowseIds': clean.artistBrowseIds,
    'metadataSource': clean.metadataSource.name,
  };
}

TrackInfo? _decodeTrackInfo(Object? raw) {
  if (raw is! Map) return null;
  final map = Map<String, dynamic>.from(raw);
  final id = (map['id'] ?? '').toString().trim();
  final title = (map['title'] ?? '').toString().trim();
  final url = (map['url'] ?? '').toString().trim();
  if (id.isEmpty || title.isEmpty || url.isEmpty) return null;
  final durationMs = (map['durationMs'] as num?)?.toInt();
  final sourceName = (map['metadataSource'] ?? 'youtube').toString();
  final metadataSource = TrackMetadataSource.values.firstWhere(
    (s) => s.name == sourceName,
    orElse: () => TrackMetadataSource.youtube,
  );
  return TrackInfo(
    id: id,
    title: title,
    artist: (map['artist'] ?? 'Inutix Music').toString(),
    url: url,
    thumbnailUrl: map['thumbnailUrl']?.toString(),
    catalogThumbnailUrl: map['catalogThumbnailUrl']?.toString(),
    duration: durationMs != null && durationMs > 0
        ? Duration(milliseconds: durationMs)
        : null,
    album: map['album']?.toString(),
    albumBrowseId: map['albumBrowseId']?.toString(),
    artists: (map['artists'] as List? ?? const [])
        .map((e) => e.toString())
        .toList(growable: false),
    artistBrowseIds: (map['artistBrowseIds'] as List? ?? const [])
        .map((e) => e?.toString())
        .toList(growable: false),
    metadataSource: metadataSource,
  );
}

Map<String, dynamic> _encodeLocalTrack(LocalTrack track) => <String, dynamic>{
  'id': track.id,
  'title': track.title,
  'artist': track.artist,
  'filePath': track.filePath,
  'addedAtMs': track.addedAt.millisecondsSinceEpoch,
  if (track.sourceUrl != null && track.sourceUrl!.isNotEmpty)
    'sourceUrl': track.sourceUrl,
  if (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty)
    'thumbnailUrl': track.thumbnailUrl,
  if (track.catalogThumbnailUrl != null &&
      track.catalogThumbnailUrl!.isNotEmpty)
    'catalogThumbnailUrl': track.catalogThumbnailUrl,
  if (track.thumbnailPath != null && track.thumbnailPath!.isNotEmpty)
    'thumbnailPath': track.thumbnailPath,
  if (track.duration != null) 'durationMs': track.duration!.inMilliseconds,
  if (track.album != null && track.album!.isNotEmpty) 'album': track.album,
  if (track.artists.isNotEmpty) 'artists': track.artists,
  if (track.artistBrowseIds.isNotEmpty)
    'artistBrowseIds': track.artistBrowseIds,
  'metadataSource': track.metadataSource.name,
  if (track.sourceId != null && track.sourceId!.isNotEmpty)
    'sourceId': track.sourceId,
  'isExternal': track.isExternal,
};

LocalTrack? _decodeLocalTrack(Object? raw) {
  if (raw is! Map) return null;
  final map = Map<String, dynamic>.from(raw);
  final id = (map['id'] ?? '').toString().trim();
  final title = (map['title'] ?? '').toString().trim();
  final filePath = (map['filePath'] ?? '').toString().trim();
  if (id.isEmpty || title.isEmpty || filePath.isEmpty) return null;
  final durationMs = (map['durationMs'] as num?)?.toInt();
  final addedAtMs = (map['addedAtMs'] as num?)?.toInt() ?? 0;
  final sourceName = (map['metadataSource'] ?? 'youtube').toString();
  final metadataSource = TrackMetadataSource.values.firstWhere(
    (s) => s.name == sourceName,
    orElse: () => TrackMetadataSource.youtube,
  );
  return LocalTrack(
    id: id,
    title: title,
    artist: (map['artist'] ?? 'Inutix Music').toString(),
    filePath: filePath,
    addedAt: DateTime.fromMillisecondsSinceEpoch(addedAtMs),
    sourceUrl: map['sourceUrl']?.toString(),
    thumbnailUrl: map['thumbnailUrl']?.toString(),
    catalogThumbnailUrl: map['catalogThumbnailUrl']?.toString(),
    thumbnailPath: map['thumbnailPath']?.toString(),
    duration: durationMs != null && durationMs > 0
        ? Duration(milliseconds: durationMs)
        : null,
    album: map['album']?.toString(),
    artists: (map['artists'] as List? ?? const [])
        .map((e) => e.toString())
        .toList(growable: false),
    artistBrowseIds: (map['artistBrowseIds'] as List? ?? const [])
        .map((e) => e?.toString())
        .toList(growable: false),
    metadataSource: metadataSource,
    sourceId: map['sourceId']?.toString(),
    isExternal: map['isExternal'] == true,
  );
}
