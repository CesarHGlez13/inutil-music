import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/firebase/listening_room_service.dart';
import '../../../../services/player/player_service.dart';
import '../../../../services/sharing/inutil_track_link.dart';
import 'music_providers.dart';

final listeningRoomServiceProvider = Provider<ListeningRoomService>((ref) {
  final service = ListeningRoomService();
  ref.onDispose(service.dispose);
  return service;
});

final listeningRoomStateProvider = StreamProvider<ListeningRoomState?>((ref) {
  final service = ref.watch(listeningRoomServiceProvider);
  final controller = StreamController<ListeningRoomState?>.broadcast();
  void emit() {
    if (!controller.isClosed) {
      controller.add(service.room);
    }
  }

  service.addListener(emit);
  emit();
  ref.onDispose(() {
    service.removeListener(emit);
    unawaited(controller.close());
  });
  return controller.stream;
});

/// Keeps the active [PlayerController] synchronized with the active Listening
/// Room (publishes playback when Host; follows track/play/pause/position with
/// drift compensation when Guest).
final listeningRoomPlayerBridgeProvider = Provider<void>((ref) {
  final service = ref.watch(listeningRoomServiceProvider);
  String? lastPublishedTrackId;
  bool? lastPublishedPlaying;
  int lastPublishedPosMs = 0;
  DateTime lastPublishAt = DateTime.fromMillisecondsSinceEpoch(0);

  String? lastGuestTrackId;
  bool guestSyncBusy = false;

  // 1. Host -> Room push when local PlayerController changes.
  ref.listen<AsyncValue<PlayerSnapshot>>(playerControllerProvider, (_, next) {
    final snap = next.asData?.value;
    if (snap == null || !service.isHost) return;
    final rawTrackId = snap.trackId?.trim() ?? '';
    if (rawTrackId.isEmpty) return;

    const codec = InutilTrackLinkCodec();
    final canonicalId =
        codec.extractVideoId(snap.sourceUrl ?? '') ??
        codec.extractVideoId(rawTrackId) ??
        rawTrackId;
    final isPlaying = snap.status == PlayerStatus.playing;
    final posMs = snap.position.inMilliseconds;
    final now = DateTime.now();

    final trackChanged = canonicalId != lastPublishedTrackId;
    final playStateChanged = isPlaying != lastPublishedPlaying;
    final manualSeek =
        !trackChanged &&
        (posMs - lastPublishedPosMs).abs() > 3500 &&
        now.difference(lastPublishAt) >= const Duration(seconds: 1);
    final heartbeatDue =
        isPlaying && now.difference(lastPublishAt) >= const Duration(seconds: 5);

    if (!trackChanged && !playStateChanged && !manualSeek && !heartbeatDue) {
      return;
    }

    lastPublishedTrackId = canonicalId;
    lastPublishedPlaying = isPlaying;
    lastPublishedPosMs = posMs;
    lastPublishAt = now;

    final track = ListeningRoomTrack(
      trackId: canonicalId,
      title: (snap.title ?? '').trim().isNotEmpty ? snap.title!.trim() : 'Canción',
      artist: (snap.artist ?? '').trim().isNotEmpty
          ? snap.artist!.trim()
          : 'Inútil Music',
      album: snap.album,
      thumbnailUrl: snap.thumbnailUrl,
      durationMs: snap.duration?.inMilliseconds ?? 0,
      url: snap.sourceUrl?.trim().isNotEmpty == true
          ? snap.sourceUrl!.trim()
          : 'https://music.youtube.com/watch?v=$canonicalId',
    );
    unawaited(
      service.publishHostPlayback(
        track: track,
        positionMs: posMs,
        isPlaying: isPlaying,
      ),
    );
  });

  // 2. Room -> Guest pull when room updates arrive.
  Future<void> applyGuestSync() async {
    if (!service.isGuest || guestSyncBusy) return;
    final room = service.room;
    final remoteTrack = room?.currentTrack;
    if (room == null || remoteTrack == null || !remoteTrack.isValid) return;

    guestSyncBusy = true;
    try {
      final playerCtrl = ref.read(playerControllerProvider.notifier);
      final localSnap = ref.read(playerControllerProvider).asData?.value;
      final targetPosMs = room.estimatedPositionMsAt(DateTime.now());
      final localTrackId = localSnap?.trackId?.trim() ?? '';

      if (localTrackId != remoteTrack.trackId &&
          lastGuestTrackId != remoteTrack.trackId) {
        lastGuestTrackId = remoteTrack.trackId;
        await playerCtrl.playRemote(remoteTrack.toTrackInfo());
        if (targetPosMs > 1500) {
          await playerCtrl.seek(Duration(milliseconds: targetPosMs));
        }
        if (!room.isPlaying) {
          await playerCtrl.togglePlayPause();
        }
        return;
      }

      if (localSnap != null) {
        final localPlaying = localSnap.status == PlayerStatus.playing;
        if (room.isPlaying != localPlaying) {
          await playerCtrl.togglePlayPause();
        }
        final localPosMs = localSnap.position.inMilliseconds;
        if (ListeningRoomState.shouldResyncPosition(
          localMs: localPosMs,
          targetMs: targetPosMs,
        )) {
          await playerCtrl.seek(Duration(milliseconds: targetPosMs));
        }
      }
    } catch (error) {
      debugPrint('ListeningRoom guest sync failed: $error');
    } finally {
      guestSyncBusy = false;
    }
  }

  void onRoomChanged() {
    if (service.isGuest) {
      unawaited(applyGuestSync());
    } else if (!service.isInRoom) {
      lastPublishedTrackId = null;
      lastPublishedPlaying = null;
      lastGuestTrackId = null;
    }
  }

  service.addListener(onRoomChanged);
  ref.onDispose(() => service.removeListener(onRoomChanged));
});
