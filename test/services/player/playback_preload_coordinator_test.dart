import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/features/music/domain/entities/track_info.dart';
import 'package:inutil_music/services/player/playback_preload_coordinator.dart';

void main() {
  group('PlaybackPreloadCoordinator Tests', () {
    const track2 = TrackInfo(
      id: 'track-2',
      title: 'Song 2',
      artist: 'Artist 2',
      url: 'https://youtube.com/watch?v=2',
    );

    test('Preloads next track N+1 without blocking and marks preloaded', () async {
      final coordinator = PlaybackPreloadCoordinator();
      var resolved = false;

      await coordinator.schedulePreload(
        nextTrack: track2,
        resolveStreamUrl: (t) async {
          resolved = true;
          return 'https://example.com/audio-stream-2.mp4';
        },
      );

      expect(resolved, isTrue);
      expect(coordinator.isPreloaded('track-2'), isTrue);
    });

    test('Cancels obsolete preload when queue/track changes', () async {
      final coordinator = PlaybackPreloadCoordinator();

      // Inicia precarga de track2 con delay
      final preloadFuture = coordinator.schedulePreload(
        nextTrack: track2,
        resolveStreamUrl: (t) async {
          await Future.delayed(const Duration(milliseconds: 50));
          return 'https://example.com/audio-stream-2.mp4';
        },
      );

      // Inmediatamente cancela / salta a track3
      coordinator.cancel();

      await preloadFuture;
      expect(coordinator.isPreloaded('track-2'), isFalse);
    });

    test('Silent failure when stream resolution throws network error', () async {
      final coordinator = PlaybackPreloadCoordinator();

      // Debe no lanzar excepción (silent failure)
      await coordinator.schedulePreload(
        nextTrack: track2,
        resolveStreamUrl: (t) async {
          throw const SocketException('No route to host');
        },
      );

      expect(coordinator.isPreloaded('track-2'), isFalse);
    });
  });
}
