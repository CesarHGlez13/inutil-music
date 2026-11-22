import '../player/player_service.dart';

typedef DesktopMediaAction = Future<void> Function();
typedef DesktopMediaSeekAction = Future<void> Function(Duration position);
typedef DesktopMediaShuffleAction = Future<void> Function(bool enabled);
typedef DesktopMediaRepeatAction =
    Future<void> Function(PlaybackRepeatMode mode);
typedef DesktopMediaQueueAction = Future<void> Function(int index);
typedef DesktopMediaBrowseChildrenLoader =
    Future<List<DesktopMediaBrowseItem>> Function(String parentMediaId);
typedef DesktopMediaPlayIdAction = Future<void> Function(String mediaId);
typedef DesktopMediaSearchLoader =
    Future<List<DesktopMediaBrowseItem>> Function(String query);
typedef DesktopMediaPlaySearchAction = Future<void> Function(String query);

/// One browsable folder or playable track exposed to external media browsers
/// such as Android Auto.
class DesktopMediaBrowseItem {
  const DesktopMediaBrowseItem({
    required this.id,
    required this.title,
    required this.playable,
    this.subtitle,
    this.album,
    this.thumbnailUrl,
    this.duration,
    this.extras,
  });

  final String id;
  final String title;
  final bool playable;
  final String? subtitle;
  final String? album;
  final String? thumbnailUrl;
  final Duration? duration;
  final Map<String, dynamic>? extras;
}

class DesktopMediaSessionCallbacks {
  const DesktopMediaSessionCallbacks({
    required this.play,
    required this.pause,
    required this.togglePlayPause,
    required this.next,
    required this.previous,
    required this.stop,
    required this.taskRemoved,
    required this.seek,
    required this.seekBy,
    required this.setShuffleEnabled,
    required this.setRepeatMode,
    required this.playQueueIndex,
    this.toggleFavorite,
    this.toggleShuffle,
    this.cycleRepeatMode,
    this.getBrowseChildren,
    this.playFromMediaId,
    this.searchMedia,
    this.playFromSearch,
  });

  final DesktopMediaAction play;
  final DesktopMediaAction pause;
  final DesktopMediaAction togglePlayPause;
  final DesktopMediaAction next;
  final DesktopMediaAction previous;
  final DesktopMediaAction stop;

  /// El sistema operativo eliminó la tarea de la app (deslizar fuera de
  /// Recientes). La sesión multimedia debe detenerse por completo: sin este
  /// callback el proceso del reproductor sobrevive a la Activity y la música
  /// continúa sonando aunque la app ya no esté en pantalla.
  final DesktopMediaAction taskRemoved;
  final DesktopMediaSeekAction seek;
  final DesktopMediaSeekAction seekBy;
  final DesktopMediaShuffleAction setShuffleEnabled;
  final DesktopMediaRepeatAction setRepeatMode;
  final DesktopMediaQueueAction playQueueIndex;
  final DesktopMediaAction? toggleFavorite;
  final DesktopMediaAction? toggleShuffle;
  final DesktopMediaAction? cycleRepeatMode;
  final DesktopMediaBrowseChildrenLoader? getBrowseChildren;
  final DesktopMediaPlayIdAction? playFromMediaId;
  final DesktopMediaSearchLoader? searchMedia;
  final DesktopMediaPlaySearchAction? playFromSearch;
}

class DesktopMediaQueueItem {
  const DesktopMediaQueueItem({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.thumbnailUrl,
  });

  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? thumbnailUrl;
}

/// Immutable system-session metadata, prepared when the logical queue changes.
/// Position updates can reuse both the entries and their fingerprint.
class DesktopMediaQueue {
  DesktopMediaQueue(Iterable<DesktopMediaQueueItem> entries)
    : items = List<DesktopMediaQueueItem>.unmodifiable(entries) {
    fingerprint = _fingerprintQueue(items);
  }

  final List<DesktopMediaQueueItem> items;
  late final int fingerprint;
}

int _fingerprintQueue(List<DesktopMediaQueueItem> queue) => Object.hashAll(
  queue.map(
    (item) => Object.hash(
      item.id,
      item.title,
      item.artist,
      item.album,
      item.thumbnailUrl,
    ),
  ),
);

class DesktopMediaSessionState {
  const DesktopMediaSessionState({
    required this.snapshot,
    required this.queue,
    required this.currentIndex,
    this.isFavorite = false,
  }) : _queueFingerprint = null;

  DesktopMediaSessionState.withQueue({
    required this.snapshot,
    required DesktopMediaQueue queue,
    required this.currentIndex,
    this.isFavorite = false,
  }) : queue = queue.items,
       _queueFingerprint = queue.fingerprint;

  final PlayerSnapshot snapshot;
  final List<DesktopMediaQueueItem> queue;
  final int currentIndex;
  final bool isFavorite;
  final int? _queueFingerprint;

  String get queueKey =>
      '$currentIndex:${_queueFingerprint ?? _fingerprintQueue(queue)}';

  bool get hasPrevious => queue.length > 1 && currentIndex >= 0;

  bool get hasNext => queue.length > 1 && currentIndex >= 0;
}

abstract class DesktopMediaSession {
  Future<void> initialize(DesktopMediaSessionCallbacks callbacks);

  Future<void> update(DesktopMediaSessionState state);

  Future<void> dispose();
}
