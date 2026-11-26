import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/firebase/firebase_playback_sync_service.dart';
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

/// Extracts the canonical video/track identifier for Listening Room comparisons.
String canonicalListeningRoomTrackId({
  String? sourceUrl,
  String? rawTrackId,
}) {
  const codec = InutilTrackLinkCodec();
  final url = sourceUrl?.trim() ?? '';
  final raw = rawTrackId?.trim() ?? '';
  if (url.isNotEmpty) {
    final fromUrl = codec.extractVideoId(url);
    if (fromUrl != null && fromUrl.isNotEmpty) return fromUrl;
  }
  if (raw.isNotEmpty) {
    final fromRaw = codec.extractVideoId(raw);
    if (fromRaw != null && fromRaw.isNotEmpty) return fromRaw;
    return raw;
  }
  return '';
}

/// Keeps the active [PlayerController] synchronized with the active Listening
/// Room (publishes playback and auto-advances collaborative queue when Host;
/// follows track/play/pause/position with drift compensation when Guest).
final listeningRoomPlayerBridgeProvider = Provider<void>((ref) {
  final service = ref.watch(listeningRoomServiceProvider);
  String? lastPublishedTrackId;
  bool? lastPublishedPlaying;
  int lastPublishedPosMs = 0;
  DateTime lastPublishAt = DateTime.fromMillisecondsSinceEpoch(0);

  String? lastAutoAdvancedTrackId;
  bool hostAutoAdvanceBusy = false;

  String? lastGuestTrackId;
  DateTime? lastGuestAttemptAt;
  DateTime? lastGuestSeekAt;
  bool guestSyncBusy = false;

  Future<void> maybeAutoAdvanceCollaborativeQueue(
    String finishedTrackId,
  ) async {
    if (!service.isHost || hostAutoAdvanceBusy) return;
    final room = service.room;
    if (room == null || room.sortedQueue.isEmpty) return;
    if (lastAutoAdvancedTrackId == finishedTrackId) return;
    hostAutoAdvanceBusy = true;
    lastAutoAdvancedTrackId = finishedTrackId;
    try {
      final next = await service.popNextQueuedTrack();
      if (next != null && service.isHost) {
        await ref
            .read(playerControllerProvider.notifier)
            .playRemote(next.track.toTrackInfo());
      }
    } catch (error) {
      debugPrint('ListeningRoom auto-advance failed: $error');
    } finally {
      hostAutoAdvanceBusy = false;
    }
  }

  // 1. Host -> Room push when local PlayerController changes.
  ref.listen<AsyncValue<PlayerSnapshot>>(playerControllerProvider, (_, next) {
    final snap = next.asData?.value;
    if (snap == null || !service.isHost) return;
    final canonicalId = canonicalListeningRoomTrackId(
      sourceUrl: snap.sourceUrl,
      rawTrackId: snap.trackId,
    );
    if (canonicalId.isEmpty) return;

    // Auto-advance the highest-voted collaborative queue track when the host's
    // current song finishes.
    final durationMs = snap.duration?.inMilliseconds ?? 0;
    final posMs = snap.position.inMilliseconds;
    final nearTrackEnd =
        snap.status == PlayerStatus.completed ||
        (snap.status == PlayerStatus.playing &&
            durationMs > 8000 &&
            posMs >= durationMs - 1100);
    if (nearTrackEnd && (service.room?.sortedQueue.isNotEmpty ?? false)) {
      unawaited(maybeAutoAdvanceCollaborativeQueue(canonicalId));
      return;
    }

    if (canonicalId != lastAutoAdvancedTrackId &&
        snap.status == PlayerStatus.playing &&
        posMs < 5000) {
      lastAutoAdvancedTrackId = null;
    }

    final isPlaying = snap.status == PlayerStatus.playing;
    final now = DateTime.now();

    final trackChanged = canonicalId != lastPublishedTrackId;
    final playStateChanged = isPlaying != lastPublishedPlaying;
    final manualSeek =
        !trackChanged &&
        (posMs - lastPublishedPosMs).abs() > 2000 &&
        now.difference(lastPublishAt) >= const Duration(milliseconds: 800);
    final heartbeatDue =
        isPlaying && now.difference(lastPublishAt) >= const Duration(seconds: 4);

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
          : 'Inutix Music',
      album: snap.album,
      thumbnailUrl: snap.thumbnailUrl,
      durationMs: durationMs,
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
      final localTrackId = canonicalListeningRoomTrackId(
        sourceUrl: localSnap?.sourceUrl,
        rawTrackId: localSnap?.trackId,
      );
      final remoteCanonicalId = canonicalListeningRoomTrackId(
        sourceUrl: remoteTrack.url,
        rawTrackId: remoteTrack.trackId,
      );

      if (localTrackId != remoteCanonicalId &&
          lastGuestTrackId != remoteCanonicalId) {
        final now = DateTime.now();
        if (lastGuestAttemptAt != null &&
            now.difference(lastGuestAttemptAt!) < const Duration(seconds: 2)) {
          return;
        }
        lastGuestAttemptAt = now;
        await playerCtrl.playRemote(remoteTrack.toTrackInfo());
        // Mark track synced only after playRemote succeeds so transient errors
        // can retry cleanly on the next poll.
        lastGuestTrackId = remoteCanonicalId;
        final latestRoom = service.room ?? room;
        final postLoadTargetMs = latestRoom.estimatedPositionMsAt(
          DateTime.now(),
        );
        if (!latestRoom.isPlaying) {
          await playerCtrl.pause();
        } else if (postLoadTargetMs > 2500) {
          await playerCtrl.seek(Duration(milliseconds: postLoadTargetMs));
        }
        return;
      }

      if (localSnap != null) {
        // Never fight a track that is still loading.
        if (localSnap.status == PlayerStatus.loading) {
          return;
        }
        final localPlaying = localSnap.status == PlayerStatus.playing;
        if (room.isPlaying && !localPlaying) {
          await playerCtrl.resume();
        } else if (!room.isPlaying && localPlaying) {
          await playerCtrl.pause();
        }
        final targetPosMs = room.estimatedPositionMsAt(DateTime.now());
        final localPosMs = localSnap.position.inMilliseconds;
        final now = DateTime.now();
        final canSeek = lastGuestSeekAt == null ||
            now.difference(lastGuestSeekAt!) >= const Duration(seconds: 4);
        if (canSeek &&
            ListeningRoomState.shouldResyncPosition(
              localMs: localPosMs,
              targetMs: targetPosMs,
              thresholdMs: 3500,
            )) {
          lastGuestSeekAt = now;
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
    InutilPlaybackSyncService.instance.setListeningRoomGuestMode(
      service.isGuest,
    );
    if (service.isGuest) {
      unawaited(applyGuestSync());
    } else if (!service.isInRoom) {
      lastPublishedTrackId = null;
      lastPublishedPlaying = null;
      lastAutoAdvancedTrackId = null;
      lastGuestTrackId = null;
      lastGuestAttemptAt = null;
      lastGuestSeekAt = null;
    }
  }

  service.addListener(onRoomChanged);
  ref.onDispose(() {
    service.removeListener(onRoomChanged);
    InutilPlaybackSyncService.instance.setListeningRoomGuestMode(false);
  });
});
