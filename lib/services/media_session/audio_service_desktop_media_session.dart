import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../../core/platform/app_platform.dart';
import '../../core/theme/app_colors.dart';
import '../player/notification_artwork_service.dart';
import '../player/player_service.dart';
import 'desktop_media_session.dart';

const androidAutoActionToggleFavorite = 'inutil.toggle_favorite';
const androidAutoActionToggleShuffle = 'inutil.toggle_shuffle';
const androidAutoActionCycleRepeat = 'inutil.cycle_repeat';

@visibleForTesting
PlaybackState buildAudioServicePlaybackState(
  DesktopMediaSessionState state, {
  bool includeExtendedControls = false,
}) {
  final snapshot = state.snapshot;
  final wantsToPlay = snapshot.wantsToPlay;
  final transportControls = <MediaControl>[
    if (state.hasPrevious) MediaControl.skipToPrevious,
    wantsToPlay ? MediaControl.pause : MediaControl.play,
    if (state.hasNext) MediaControl.skipToNext,
  ];
  final compactActions = List<int>.generate(
    transportControls.length.clamp(0, 3),
    (index) => index,
    growable: false,
  );
  final controls = <MediaControl>[
    ...transportControls,
    if (includeExtendedControls) ...[
      MediaControl.custom(
        androidIcon: state.isFavorite
            ? 'drawable/ic_aa_favorite_filled'
            : 'drawable/ic_aa_favorite_border',
        label: state.isFavorite ? 'Quitar de favoritos' : 'Favorito',
        name: androidAutoActionToggleFavorite,
      ),
      MediaControl.custom(
        androidIcon: snapshot.shuffleEnabled
            ? 'drawable/ic_aa_shuffle_on'
            : 'drawable/ic_aa_shuffle_off',
        label: snapshot.shuffleEnabled ? 'Desactivar aleatorio' : 'Aleatorio',
        name: androidAutoActionToggleShuffle,
      ),
      MediaControl.custom(
        androidIcon: switch (snapshot.repeatMode) {
          PlaybackRepeatMode.off => 'drawable/ic_aa_repeat_off',
          PlaybackRepeatMode.all => 'drawable/ic_aa_repeat_all',
          PlaybackRepeatMode.one => 'drawable/ic_aa_repeat_one',
        },
        label: switch (snapshot.repeatMode) {
          PlaybackRepeatMode.off => 'Repetir',
          PlaybackRepeatMode.all => 'Repitiendo lista',
          PlaybackRepeatMode.one => 'Repitiendo canción',
        },
        name: androidAutoActionCycleRepeat,
      ),
    ],
  ];

  return PlaybackState(
    controls: controls,
    androidCompactActionIndices: compactActions,
    systemActions: const {
      MediaAction.seek,
      MediaAction.seekForward,
      MediaAction.seekBackward,
      MediaAction.skipToQueueItem,
      MediaAction.playFromMediaId,
      MediaAction.playFromSearch,
      MediaAction.setShuffleMode,
      MediaAction.setRepeatMode,
    },
    processingState: switch (snapshot.status) {
      PlayerStatus.idle => AudioProcessingState.idle,
      PlayerStatus.loading => AudioProcessingState.loading,
      PlayerStatus.playing || PlayerStatus.paused => AudioProcessingState.ready,
      // Loading a successor or recovering a stream is still one continuous
      // playback session. In particular, Android must not leave foreground
      // mode and release its CPU wake lock during these automatic gaps.
      // The controller owns the bounded recovery and clears playback intent
      // on a user pause/stop, final completion or exhausted retry.
      PlayerStatus.completed =>
        wantsToPlay
            ? AudioProcessingState.loading
            : AudioProcessingState.completed,
      PlayerStatus.stopped => AudioProcessingState.idle,
      PlayerStatus.failed =>
        wantsToPlay ? AudioProcessingState.loading : AudioProcessingState.error,
    },
    playing: wantsToPlay,
    updatePosition: snapshot.position,
    bufferedPosition: snapshot.position,
    speed: 1,
    queueIndex:
        state.currentIndex >= 0 && state.currentIndex < state.queue.length
        ? state.currentIndex
        : null,
    repeatMode: switch (snapshot.repeatMode) {
      PlaybackRepeatMode.off => AudioServiceRepeatMode.none,
      PlaybackRepeatMode.all => AudioServiceRepeatMode.all,
      PlaybackRepeatMode.one => AudioServiceRepeatMode.one,
    },
    shuffleMode: snapshot.shuffleEnabled
        ? AudioServiceShuffleMode.all
        : AudioServiceShuffleMode.none,
    errorCode: snapshot.status == PlayerStatus.failed && !wantsToPlay
        ? 1
        : null,
    errorMessage: snapshot.status == PlayerStatus.failed && !wantsToPlay
        ? snapshot.errorMessage
        : null,
  );
}

@visibleForTesting
class AudioServiceMediaSessionCallbackBridge {
  DesktopMediaSessionCallbacks? _callbacks;

  void attach(DesktopMediaSessionCallbacks callbacks) {
    _callbacks = callbacks;
  }

  bool detach(DesktopMediaSessionCallbacks callbacks) {
    if (identical(_callbacks, callbacks)) {
      _callbacks = null;
      return true;
    }
    return false;
  }

  Future<void> play() => _callbacks?.play() ?? Future<void>.value();

  Future<void> pause() => _callbacks?.pause() ?? Future<void>.value();

  Future<void> stop() => _callbacks?.stop() ?? Future<void>.value();

  Future<void> taskRemoved() =>
      _callbacks?.taskRemoved() ?? Future<void>.value();

  Future<void> next() => _callbacks?.next() ?? Future<void>.value();

  Future<void> previous() => _callbacks?.previous() ?? Future<void>.value();

  Future<void> seek(Duration position) =>
      _callbacks?.seek(position) ?? Future<void>.value();

  Future<void> playQueueIndex(int index) =>
      _callbacks?.playQueueIndex(index) ?? Future<void>.value();

  Future<void> setShuffleEnabled(bool enabled) =>
      _callbacks?.setShuffleEnabled(enabled) ?? Future<void>.value();

  Future<void> setRepeatMode(PlaybackRepeatMode mode) =>
      _callbacks?.setRepeatMode(mode) ?? Future<void>.value();

  Future<void> toggleFavorite() =>
      _callbacks?.toggleFavorite?.call() ?? Future<void>.value();

  Future<void> toggleShuffle() =>
      _callbacks?.toggleShuffle?.call() ?? Future<void>.value();

  Future<void> cycleRepeatMode() =>
      _callbacks?.cycleRepeatMode?.call() ?? Future<void>.value();

  Future<List<DesktopMediaBrowseItem>> getBrowseChildren(
    String parentMediaId,
  ) =>
      _callbacks?.getBrowseChildren?.call(parentMediaId) ??
      Future<List<DesktopMediaBrowseItem>>.value(const []);

  Future<void> playFromMediaId(String mediaId) =>
      _callbacks?.playFromMediaId?.call(mediaId) ?? Future<void>.value();

  Future<List<DesktopMediaBrowseItem>> searchMedia(String query) =>
      _callbacks?.searchMedia?.call(query) ??
      Future<List<DesktopMediaBrowseItem>>.value(const []);

  Future<void> playFromSearch(String query) =>
      _callbacks?.playFromSearch?.call(query) ?? Future<void>.value();
}

class AudioServiceDesktopMediaSession implements DesktopMediaSession {
  static Future<_DesktopAudioHandler>? _handlerInitialization;

  _DesktopAudioHandler? _handler;
  DesktopMediaSessionCallbacks? _callbacks;
  DesktopMediaSessionState? _latestState;
  Timer? _positionTimer;

  bool _disposed = false;
  String? _lastTrackKey;
  String? _lastQueueKey;
  PlayerStatus? _lastStatus;
  bool? _lastWantsToPlay;
  bool? _lastShuffleEnabled;
  PlaybackRepeatMode? _lastRepeatMode;
  bool? _lastIsFavorite;
  DateTime? _lastPositionUpdate;

  static Future<void> ensureInitialized() async {
    await _recoverableHandler();
  }

  static Future<_DesktopAudioHandler> _recoverableHandler() async {
    final initialization = _ensureHandler();
    try {
      return await initialization;
    } catch (_) {
      // AudioService initialization can fail transiently while the mobile
      // process is being restored. Do not permanently cache a rejected Future.
      if (identical(_handlerInitialization, initialization)) {
        _handlerInitialization = null;
      }
      rethrow;
    }
  }

  static Future<_DesktopAudioHandler> _ensureHandler() {
    return _handlerInitialization ??= () async {
      late final _DesktopAudioHandler handler;
      await AudioService.init(
        builder: () {
          handler = _DesktopAudioHandler();
          return handler;
        },
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.inutilmusic.app.audio',
          androidNotificationChannelName: 'Inútil Music',
          androidNotificationChannelDescription: 'Inútil Music playback',
          notificationColor: AppColors.brandGreen,
          androidNotificationIcon: 'drawable/ic_stat_inutil_music',
          androidShowNotificationBadge: true,
          androidNotificationOngoing: true,
          // Playback intent keeps automatic loads/retries active. A genuine
          // pause must still release foreground priority and its wake lock.
          androidStopForegroundOnPause: true,
          artDownscaleWidth: 512,
          artDownscaleHeight: 512,
          androidBrowsableRootExtras: <String, dynamic>{
            AndroidContentStyle.supportedKey: true,
            AndroidContentStyle.browsableHintKey:
                AndroidContentStyle.gridItemHintValue,
            AndroidContentStyle.playableHintKey:
                AndroidContentStyle.listItemHintValue,
            'android.media.browse.SEARCH_SUPPORTED': true,
          },
        ),
      );
      return handler;
    }();
  }

  @override
  Future<void> initialize(DesktopMediaSessionCallbacks callbacks) async {
    _callbacks = callbacks;
    try {
      final handler = await _recoverableHandler();
      if (_disposed) {
        handler.publishIdle();
        return;
      }
      handler.attach(callbacks);
      _handler = handler;
      final latestState = _latestState;
      if (latestState != null) {
        await _sync(latestState, force: true);
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Desktop audio service could not be initialized: $error\n$stackTrace',
      );
      rethrow;
    }
  }

  @override
  Future<void> update(DesktopMediaSessionState state) async {
    _latestState = state;
    if (_disposed || _handler == null) {
      return;
    }

    final snapshot = state.snapshot;
    final trackKey = _trackKey(snapshot);
    final queueKey = state.queueKey;
    final requiresImmediateSync =
        trackKey != _lastTrackKey ||
        queueKey != _lastQueueKey ||
        snapshot.status != _lastStatus ||
        snapshot.wantsToPlay != _lastWantsToPlay ||
        snapshot.shuffleEnabled != _lastShuffleEnabled ||
        snapshot.repeatMode != _lastRepeatMode ||
        state.isFavorite != _lastIsFavorite;

    if (requiresImmediateSync || _positionIsDue) {
      _positionTimer?.cancel();
      _positionTimer = null;
      await _sync(state, force: requiresImmediateSync);
      return;
    }

    _positionTimer ??= Timer(const Duration(milliseconds: 850), () {
      _positionTimer = null;
      final latestState = _latestState;
      if (latestState != null && !_disposed) {
        unawaited(_sync(latestState));
      }
    });
  }

  bool get _positionIsDue {
    final lastUpdate = _lastPositionUpdate;
    return lastUpdate == null ||
        DateTime.now().difference(lastUpdate) >=
            const Duration(milliseconds: 850);
  }

  Future<void> _sync(
    DesktopMediaSessionState state, {
    bool force = false,
  }) async {
    final handler = _handler;
    if (_disposed || handler == null) {
      return;
    }

    try {
      final snapshot = state.snapshot;
      if (!_hasTrack(snapshot)) {
        handler.publishIdle();
        _remember(state);
        return;
      }

      final trackKey = _trackKey(snapshot);
      if (force || trackKey != _lastTrackKey) {
        handler.mediaItem.add(
          MediaItem(
            id: snapshot.trackId ?? snapshot.sourceUrl ?? trackKey,
            title: snapshot.title?.trim().isNotEmpty == true
                ? snapshot.title!.trim()
                : 'Inútil Music',
            artist: snapshot.artist?.trim(),
            album: snapshot.album?.trim().isNotEmpty == true
                ? snapshot.album!.trim()
                : 'Inútil Music',
            duration: snapshot.duration,
            artUri: _artUri(snapshot.thumbnailUrl),
          ),
        );
      }

      final queueKey = state.queueKey;
      if (force || queueKey != _lastQueueKey) {
        handler.queue.add(
          state.queue
              .map(
                (item) => MediaItem(
                  id: item.id,
                  title: item.title,
                  artist: item.artist,
                  album: item.album?.trim().isNotEmpty == true
                      ? item.album!.trim()
                      : 'Inútil Music',
                  artUri: _artUri(item.thumbnailUrl),
                ),
              )
              .toList(growable: false),
        );
      }

      handler.playbackState.add(
        buildAudioServicePlaybackState(
          state,
          includeExtendedControls: AppPlatform.isAndroid,
        ),
      );
      _lastPositionUpdate = DateTime.now();
      _remember(state);
    } catch (error) {
      debugPrint('Desktop audio service update failed: $error');
    }
  }

  void _remember(DesktopMediaSessionState state) {
    final snapshot = state.snapshot;
    _lastTrackKey = _trackKey(snapshot);
    _lastQueueKey = state.queueKey;
    _lastStatus = snapshot.status;
    _lastWantsToPlay = snapshot.wantsToPlay;
    _lastShuffleEnabled = snapshot.shuffleEnabled;
    _lastRepeatMode = snapshot.repeatMode;
    _lastIsFavorite = state.isFavorite;
  }

  bool _hasTrack(PlayerSnapshot snapshot) =>
      (snapshot.trackId?.isNotEmpty ?? false) ||
      (snapshot.title?.isNotEmpty ?? false);

  String _trackKey(PlayerSnapshot snapshot) =>
      '${snapshot.trackId}|${snapshot.title}|${snapshot.artist}|${snapshot.album}|'
      '${snapshot.thumbnailUrl}|${snapshot.duration?.inMilliseconds}';

  Uri? _artUri(String? source) {
    final value = source?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    if (AppPlatform.isMobile) {
      final notificationUri = NotificationArtworkService.instance.uriFor(value);
      if (notificationUri != null) {
        return notificationUri;
      }
    }
    if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value)) {
      return Uri.file(File(value).absolute.path);
    }
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) {
      return uri;
    }
    return Uri.file(File(value).absolute.path);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _positionTimer?.cancel();
    final handler = _handler;
    final callbacks = _callbacks;
    if (handler != null && callbacks != null) {
      if (handler.detach(callbacks)) {
        handler.publishIdle();
      }
    }
    _handler = null;
    _callbacks = null;
  }
}

class _DesktopAudioHandler extends BaseAudioHandler with SeekHandler {
  final _callbacks = AudioServiceMediaSessionCallbackBridge();

  void attach(DesktopMediaSessionCallbacks callbacks) {
    _callbacks.attach(callbacks);
  }

  bool detach(DesktopMediaSessionCallbacks callbacks) =>
      _callbacks.detach(callbacks);

  void publishIdle() {
    queue.add(const []);
    mediaItem.add(null);
    playbackState.add(
      PlaybackState(processingState: AudioProcessingState.idle),
    );
  }

  @override
  Future<void> play() => _callbacks.play();

  @override
  Future<void> pause() => _callbacks.pause();

  @override
  Future<void> stop() async {
    await _callbacks.stop();
    await super.stop();
  }

  /// El sistema eliminó la tarea de la app (deslizar fuera de Recientes o
  /// "Borrar todo"). Sin esta sobreescritura `BaseAudioHandler.onTaskRemoved`
  /// es un no-op y el FlutterEngine que posee `audio_service` sobrevive a la
  /// Activity: la música seguía sonando con la app ya cerrada.
  /// Detenemos la sesión y, como red de seguridad, publicamos `idle` para que
  /// el plugin libere el servicio en primer plano y destruya ese engine.
  @override
  Future<void> onTaskRemoved() async {
    await _callbacks.taskRemoved();
    publishIdle();
  }

  @override
  Future<void> skipToNext() => _callbacks.next();

  @override
  Future<void> skipToPrevious() => _callbacks.previous();

  @override
  Future<void> seek(Duration position) => _callbacks.seek(position);

  @override
  Future<void> skipToQueueItem(int index) => _callbacks.playQueueIndex(index);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode mode) =>
      _callbacks.setShuffleEnabled(mode != AudioServiceShuffleMode.none);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode mode) =>
      _callbacks.setRepeatMode(switch (mode) {
        AudioServiceRepeatMode.none => PlaybackRepeatMode.off,
        AudioServiceRepeatMode.one => PlaybackRepeatMode.one,
        AudioServiceRepeatMode.all ||
        AudioServiceRepeatMode.group => PlaybackRepeatMode.all,
      });

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    try {
      final items = await _callbacks.getBrowseChildren(parentMediaId);
      return items.map(_toBrowseMediaItem).toList(growable: false);
    } catch (error) {
      debugPrint('Android Auto getChildren($parentMediaId) failed: $error');
      return const <MediaItem>[];
    }
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    try {
      await _callbacks.playFromMediaId(mediaId);
    } catch (error) {
      debugPrint('Android Auto playFromMediaId($mediaId) failed: $error');
    }
  }

  @override
  Future<List<MediaItem>> search(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    try {
      final items = await _callbacks.searchMedia(query);
      return items.map(_toBrowseMediaItem).toList(growable: false);
    } catch (error) {
      debugPrint('Android Auto search($query) failed: $error');
      return const <MediaItem>[];
    }
  }

  @override
  Future<void> playFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    try {
      await _callbacks.playFromSearch(query);
    } catch (error) {
      debugPrint('Android Auto playFromSearch($query) failed: $error');
    }
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    switch (name) {
      case androidAutoActionToggleFavorite:
        await _callbacks.toggleFavorite();
        return null;
      case androidAutoActionToggleShuffle:
        await _callbacks.toggleShuffle();
        return null;
      case androidAutoActionCycleRepeat:
        await _callbacks.cycleRepeatMode();
        return null;
      default:
        return super.customAction(name, extras);
    }
  }

  MediaItem _toBrowseMediaItem(DesktopMediaBrowseItem item) => MediaItem(
    id: item.id,
    title: item.title,
    artist: item.subtitle,
    album: item.album,
    playable: item.playable,
    duration: item.duration,
    artUri: _browseArtUri(item.thumbnailUrl),
    extras: item.extras,
  );

  Uri? _browseArtUri(String? source) {
    final value = source?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri != null &&
        (uri.scheme == 'https' ||
            uri.scheme == 'http' ||
            uri.scheme == 'android.resource')) {
      return uri;
    }
    if (AppPlatform.isMobile) {
      final notificationUri = NotificationArtworkService.instance.uriFor(value);
      if (notificationUri != null) {
        return notificationUri;
      }
    }
    if (uri != null && uri.hasScheme) {
      return uri;
    }
    return null;
  }
}
