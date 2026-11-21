import 'dart:async';

import 'package:inutil_music/core/platform/app_platform.dart';
import 'package:inutil_music/features/music/domain/entities/local_track.dart';
import 'package:inutil_music/features/music/domain/entities/lyrics_document.dart';
import 'package:inutil_music/features/music/domain/entities/lyrics_lookup.dart';
import 'package:inutil_music/features/music/domain/entities/playlist.dart';
import 'package:inutil_music/features/music/presentation/providers/music_providers.dart';
import 'package:inutil_music/features/music/presentation/providers/playback_visual_cache_provider.dart';
import 'package:inutil_music/features/music/presentation/providers/spotify_canvas_provider.dart';
import 'package:inutil_music/features/music/presentation/widgets/player_panel.dart';
import 'package:inutil_music/services/lyrics/lyrics_service.dart';
import 'package:inutil_music/services/player/playback_visual_cache.dart';
import 'package:inutil_music/services/player/player_service.dart';
import 'package:inutil_music/services/spotify_canvas/spotify_canvas_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _snapshot = PlayerSnapshot(
  status: PlayerStatus.paused,
  title: 'Canvas pending fixture',
  artist: 'Inútil Music',
  trackId: 'canvas-pending-fixture',
  thumbnailUrl: '/fixture/cover.jpg',
  duration: Duration(minutes: 3),
);

/// Canvas URL the fixture resolver hands back while the clip is not downloaded.
final _canvasUrl = Uri.https('canvaz.scdn.co', '/fixture.mp4');

/// Cache that knows the Canvas URL but has not downloaded the clip yet, which is
/// the state every cold start passes through: `videoFileFor()` answers null
/// until the file lands, so `hasCanvasNow` is false for the opening frames.
class _PendingCanvasCache extends PlaybackVisualCache {
  Uri? activatedVideoUrl;

  @override
  void activate({
    required String trackKey,
    required String? coverSource,
    String? coverFallbackSource,
    required Uri? videoUrl,
  }) {
    activatedVideoUrl = videoUrl;
  }

  @override
  Uri? videoFileFor(String trackKey, Uri? url) => null;
}

/// Resolver with a switchable answer, so a test can also model a track with no
/// Canvas at all.
class _FlippableCanvasResolver extends SpotifyCanvasResolver {
  Uri? answer = _canvasUrl;

  @override
  Future<Uri?> resolve(SpotifyCanvasTrack track) async => answer;
}

/// Resolver backed by a manual Completer so tests can inspect the opening frame
/// while the network lookup is still in flight.
class _DelayedCanvasResolver extends SpotifyCanvasResolver {
  final Completer<Uri?> completer = Completer<Uri?>();

  @override
  Future<Uri?> resolve(SpotifyCanvasTrack track) => completer.future;
}

/// Keeps the standard layout's lyrics preview from scheduling real network
/// timeouts, which would leave pending timers after the test.
class _QuietLyrics implements LyricsService {
  @override
  Future<LyricsDocument?> findLyrics(LyricsLookup lookup) => Future.value(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingPlayer extends PlayerController {
  @override
  Future<PlayerSnapshot> build() async => _snapshot;
}

class _PendingSettings extends SettingsController {
  @override
  Future<SettingsState> build() async => const SettingsState(
    downloadDirectory: '',
    language: AppLanguage.spanish,
    spotifyCanvasEnabled: true,
  );
}

class _PendingPlaylists extends PlaylistsController {
  @override
  Future<List<Playlist>> build() async => const [];
}

class _PendingAudio implements PlayerService {
  @override
  Stream<PlayerSnapshot> get snapshotStream => Stream.value(_snapshot);

  @override
  PlayerSnapshot get currentSnapshot => _snapshot;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _pendingTestContainer({
  required PlaybackVisualCache cache,
  required SpotifyCanvasResolver resolver,
}) {
  return ProviderContainer(
    overrides: [
      databaseServiceProvider.overrideWith(
        (ref) => throw StateError('Pending fixture cannot use user data'),
      ),
      playbackVisualCacheProvider.overrideWith((ref) => cache),
      spotifyCanvasResolverProvider.overrideWithValue(resolver),
      playerServiceProvider.overrideWithValue(_PendingAudio()),
      playerControllerProvider.overrideWith(_PendingPlayer.new),
      settingsControllerProvider.overrideWith(_PendingSettings.new),
      playlistsControllerProvider.overrideWith(_PendingPlaylists.new),
      libraryTracksProvider.overrideWith((ref) async => const <LocalTrack>[]),
      favoriteTrackIdsProvider.overrideWithValue(const <String>{}),
      lyricsServiceProvider.overrideWithValue(_QuietLyrics()),
    ],
  );
}

Widget _phonePlayer() {
  return MaterialApp(
    theme: ThemeData(platform: TargetPlatform.android),
    home: Scaffold(
      body: PlayerPanel(
        style: PlayerStyle.inutilMusic,
        artworkStyle: PlayerArtworkStyle.classic,
        spotifyCanvasEnabled: true,
        animatedArtworkEnabled: false,
        drawBackground: false,
        trackTransitionsEnabled: false,
      ),
    ),
  );
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // Drain the 7 s lyric/relay timeouts the opening layouts scheduled.
  await tester.pump(const Duration(seconds: 8));
  await tester.pump();
}

void main() {
  testWidgets('a known Canvas URL paints the Canvas layout before the clip lands', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cache = _PendingCanvasCache();
    final container = _pendingTestContainer(
      cache: cache,
      resolver: _FlippableCanvasResolver(),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _phonePlayer()),
    );
    await tester.pump();
    await tester.pump();

    // The URL is known while the clip is still downloading: that is exactly the
    // frame where the classic square-artwork layout used to open first and then
    // dissolve into the Canvas 850 ms later.
    expect(cache.activatedVideoUrl, _canvasUrl);
    expect(find.byKey(const ValueKey('player-mode-canvas')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('player-canvas-viewport')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('fullscreen-canvas-pending')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('player-canvas-mode-switcher')),
      findsOneWidget,
    );
    // `player-canvas-mode-switcher` cross-fades the two layouts, so the old key
    // coexists for 850 ms; once the fade is over it must be gone for good.
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(const ValueKey('player-mode-canvas')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-mode-standard')), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, skip: AppPlatform.current == AppPlatformType.linux);

  testWidgets('without a Canvas URL the player opens in the standard layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final resolver = _FlippableCanvasResolver()..answer = null;
    final cache = _PendingCanvasCache();
    final container = _pendingTestContainer(cache: cache, resolver: resolver);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _phonePlayer()),
    );
    await tester.pump();
    await tester.pump();

    // No Canvas for this track: the pending mode must not pretend otherwise, so
    // the standard layout is the correct opening frame and never gets replaced.
    expect(cache.activatedVideoUrl, isNull);
    expect(find.byKey(const ValueKey('player-mode-standard')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-mode-canvas')), findsNothing);
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(const ValueKey('player-mode-standard')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-mode-canvas')), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, skip: AppPlatform.current == AppPlatformType.linux);

  testWidgets(
    'in-flight Canvas lookup mounts Canvas layout on frame 1 with no standard flash',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final resolver = _DelayedCanvasResolver();
      final cache = _PendingCanvasCache();
      final container = _pendingTestContainer(cache: cache, resolver: resolver);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: _phonePlayer()),
      );
      await tester.pump();

      // While the Canvas lookup is still unresolved, the fullscreen Canvas
      // shell is already mounted and the standard square-artwork layout must
      // never flash or crossfade underneath it.
      expect(find.byKey(const ValueKey('player-mode-canvas')), findsOneWidget);
      expect(find.byKey(const ValueKey('player-mode-standard')), findsNothing);

      resolver.completer.complete(_canvasUrl);
      await tester.pump();
      await tester.pump();

      expect(cache.activatedVideoUrl, _canvasUrl);
      expect(find.byKey(const ValueKey('player-mode-canvas')), findsOneWidget);
      expect(find.byKey(const ValueKey('player-mode-standard')), findsNothing);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    },
    skip: AppPlatform.current == AppPlatformType.linux,
  );
}
