import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/firebase/firebase_auth_service.dart';
import 'package:inutil_music/core/firebase/firebase_firestore_service.dart';
import 'package:inutil_music/core/firebase/firebase_playback_sync_service.dart';
import 'package:inutil_music/features/music/domain/entities/local_track.dart';
import 'package:inutil_music/features/music/presentation/providers/music_providers.dart';
import 'package:inutil_music/features/music/presentation/widgets/desktop_now_playing_rail.dart';
import 'package:inutil_music/services/player/player_service.dart';

void main() {
  group('Universal PC onboarding & relay bypass', () {
    test(
      'pairing collections bypass authenticated relays directly to Firestore',
      () {
        expect(
          InutilFirestoreService.shouldBypassRelay('music_pairing/F8CXWA7K'),
          isTrue,
        );
        expect(
          InutilFirestoreService.shouldBypassRelay('tv_pairing/12345678'),
          isTrue,
        );
        expect(
          InutilFirestoreService.shouldBypassRelay(
            'users/uid1/playback_session/current',
          ),
          isFalse,
        );
        expect(
          InutilFirestoreService.shouldBypassRelay('app_config/release'),
          isFalse,
        );
      },
    );

    test(
      'default device names are derived dynamically and never hardcoded to a single user',
      () {
        final linuxName = InutilAuthService.resolveDefaultDeviceName(
          platform: 'linux',
          hostname: 'matebook-pro.local',
        );
        expect(linuxName, 'matebook-pro (Linux)');
        expect(linuxName.toLowerCase(), isNot(contains('césar')));

        final windowsName = InutilAuthService.resolveDefaultDeviceName(
          platform: 'windows',
          hostname: 'DESKTOP-9K2L',
        );
        expect(windowsName, 'DESKTOP-9K2L (Windows)');

        final macName = InutilAuthService.resolveDefaultDeviceName(
          platform: 'macos',
          hostname: 'MacBook-Air.local',
        );
        expect(macName, 'MacBook-Air (macOS)');

        final fallbackLinux = InutilAuthService.resolveDefaultDeviceName(
          platform: 'linux',
          hostname: 'localhost',
        );
        expect(fallbackLinux, 'PC Linux');

        final androidName = InutilAuthService.resolveDefaultDeviceName(
          platform: 'android',
          hostname: 'localhost',
        );
        expect(androidName, 'Teléfono Android');

        final custom = InutilAuthService.resolveDefaultDeviceName(
          platform: 'linux',
          hostname: 'matebook',
          savedCustomName: 'Laptop Sala',
        );
        expect(custom, 'Laptop Sala');
      },
    );
  });

  group('Spotify Connect LAN-first & session parity', () {
    test(
      'extractProbeableLanEndpoint accepts private LAN IPv4 hints from cloud devices',
      () {
        final endpoint = InutilPlaybackSyncService.extractProbeableLanEndpoint({
          'lanIp': '192.168.100.32',
          'lanPort': 52445,
        });
        expect(endpoint, isNotNull);
        expect(endpoint!.ip, '192.168.100.32');
        expect(endpoint.port, 52445);

        expect(
          InutilPlaybackSyncService.extractProbeableLanEndpoint({
            'lanIp': '10.0.0.15',
            'lanPort': 52445,
          }),
          isNotNull,
        );
        expect(
          InutilPlaybackSyncService.extractProbeableLanEndpoint({
            'lanIp': '172.20.1.5',
            'lanPort': 52445,
          }),
          isNotNull,
        );
        // Reject loopback, public, empty, or invalid port.
        expect(
          InutilPlaybackSyncService.extractProbeableLanEndpoint({
            'lanIp': '127.0.0.1',
            'lanPort': 52445,
          }),
          isNull,
        );
        expect(
          InutilPlaybackSyncService.extractProbeableLanEndpoint({
            'lanIp': '8.8.8.8',
            'lanPort': 52445,
          }),
          isNull,
        );
        expect(
          InutilPlaybackSyncService.extractProbeableLanEndpoint({
            'lanIp': '192.168.100.32',
            'lanPort': 0,
          }),
          isNull,
        );
      },
    );

    test(
      'PlaybackSyncSession round-trips volume, shuffle, repeat, and compact queue',
      () {
        final session = PlaybackSyncSession(
          activeDeviceId: 'laptop-1',
          activeDeviceName: 'matebook (Linux)',
          activeDevicePlatform: 'linux',
          trackId: 'abc123',
          title: 'Because Of You',
          artist: 'LIZOT',
          positionMs: 42000,
          durationMs: 138000,
          isPlaying: true,
          volume: 0.65,
          shuffleEnabled: true,
          repeatMode: 'all',
          queueIndex: 1,
          queue: const [
            {'id': 't0', 'title': 'Song 0', 'artist': 'A0'},
            {'id': 'abc123', 'title': 'Because Of You', 'artist': 'LIZOT'},
          ],
        );

        final lanJson = session.toJson();
        final decoded = PlaybackSyncSession.fromJson(lanJson);
        expect(decoded.volume, closeTo(0.65, 0.001));
        expect(decoded.shuffleEnabled, isTrue);
        expect(decoded.repeatMode, 'all');
        expect(decoded.queueIndex, 1);
        expect(decoded.queue, hasLength(2));
        expect(decoded.queue[1]['id'], 'abc123');

        // Cloud document omits the queue array to avoid Firestore payload bloat.
        final cloudJson = session.toCloudJson();
        expect(cloudJson.containsKey('queue'), isFalse);
        expect(cloudJson['volume'], closeTo(0.65, 0.001));
        expect(cloudJson['shuffleEnabled'], isTrue);
        expect(cloudJson['repeatMode'], 'all');
      },
    );

    test(
      'remote speaker badge only shows when another device is the active speaker',
      () {
        expect(
          InutilPlaybackSyncService.remoteSpeakerBadgeName(
            isCurrentDeviceActive: true,
            remoteActiveDeviceName: 'matebook (Linux)',
          ),
          isNull,
        );
        expect(
          InutilPlaybackSyncService.remoteSpeakerBadgeName(
            isCurrentDeviceActive: false,
            remoteActiveDeviceName: 'matebook (Linux)',
          ),
          'matebook (Linux)',
        );
        expect(
          InutilPlaybackSyncService.remoteSpeakerBadgeName(
            isCurrentDeviceActive: false,
            remoteActiveDeviceName: '',
          ),
          isNull,
        );
      },
    );

    test(
      'single-device accounts throttle cloud session and command polling to 30s',
      () {
        expect(
          InutilPlaybackSyncService.cloudSessionPollInterval(
            activeOnLan: false,
            isCurrentDeviceActive: true,
            hasAnyLanPeer: false,
            hasAnyOnlinePeer: false,
          ),
          const Duration(seconds: 30),
        );
        expect(
          InutilPlaybackSyncService.cloudSessionPollInterval(
            activeOnLan: false,
            isCurrentDeviceActive: true,
            hasAnyLanPeer: false,
            hasAnyOnlinePeer: true,
          ),
          const Duration(seconds: 3),
        );
        expect(
          InutilPlaybackSyncService.cloudSessionPollInterval(
            activeOnLan: true,
            isCurrentDeviceActive: false,
            hasAnyLanPeer: true,
            hasAnyOnlinePeer: true,
          ),
          const Duration(seconds: 15),
        );
        expect(
          InutilPlaybackSyncService.cloudCommandPollInterval(
            burst: false,
            hasCloudOnlyPeer: false,
            hasAnyLanPeer: false,
            hasAnyOnlinePeer: false,
          ),
          const Duration(seconds: 30),
        );
        expect(
          InutilPlaybackSyncService.cloudCommandPollInterval(
            burst: false,
            hasCloudOnlyPeer: true,
            hasAnyLanPeer: false,
            hasAnyOnlinePeer: true,
          ),
          InutilPlaybackSyncService.commandsPollInterval,
        );
      },
    );

    testWidgets(
      'Spotify 2026 DesktopNowPlayingRail renders active track, Connect card, and Up Next queue',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            playerControllerProvider.overrideWith(_FakeRailPlayer.new),
            libraryTracksProvider.overrideWith(
              (ref) async => const <LocalTrack>[],
            ),
          ],
        );
        addTearDown(container.dispose);

        container
            .read(playbackQueueProvider.notifier)
            .replace(const <PlaybackQueueEntry>[
              PlaybackQueueEntry(
                id: 't1',
                title: 'Te Veo a la Vuelta',
                artist: 'Danny Ocean',
                isRemote: true,
              ),
              PlaybackQueueEntry(
                id: 't2',
                title: 'Because Of You',
                artist: 'LIZOT',
                isRemote: true,
              ),
            ], 0);

        var expanded = false;
        var closed = false;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: DesktopNowPlayingRail(
                  spotifyCanvasEnabled: false,
                  animatedArtworkEnabled: false,
                  onOpenPlayer: () => expanded = true,
                  onOpenLyrics: () {},
                  onClose: () => closed = true,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('desktop-now-playing-rail')),
          findsOneWidget,
        );
        expect(find.text('Te Veo a la Vuelta'), findsOneWidget);
        expect(find.text('Danny Ocean'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('desktop-now-playing-connect-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('desktop-now-playing-up-next')),
          findsOneWidget,
        );
        expect(find.text('Because Of You'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('desktop-now-playing-expand-button')),
        );
        expect(expanded, isTrue);

        await tester.tap(
          find.byKey(const ValueKey('desktop-now-playing-close-button')),
        );
        expect(closed, isTrue);
      },
    );
  });
}

class _FakeRailPlayer extends PlayerController {
  @override
  Future<PlayerSnapshot> build() async => const PlayerSnapshot(
    status: PlayerStatus.playing,
    trackId: 't1',
    title: 'Te Veo a la Vuelta',
    artist: 'Danny Ocean',
    album: 'Babylon Club',
    duration: Duration(minutes: 3, seconds: 20),
  );
}
