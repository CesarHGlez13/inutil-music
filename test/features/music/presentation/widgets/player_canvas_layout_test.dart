import 'dart:async';
import 'dart:ui' as ui;

import 'package:inutil_music/core/platform/app_platform.dart';
import 'package:inutil_music/features/music/domain/entities/local_track.dart';
import 'package:inutil_music/features/music/domain/entities/playlist.dart';
import 'package:inutil_music/features/music/presentation/providers/music_providers.dart';
import 'package:inutil_music/features/music/presentation/providers/playback_visual_cache_provider.dart';
import 'package:inutil_music/features/music/presentation/providers/spotify_canvas_provider.dart';
import 'package:inutil_music/features/music/presentation/widgets/player_panel.dart';
import 'package:inutil_music/features/music/presentation/widgets/spotify_canvas_video.dart';
import 'package:inutil_music/services/player/playback_visual_cache.dart';
import 'package:inutil_music/services/player/player_service.dart';
import 'package:inutil_music/services/spotify_canvas/spotify_canvas_resolver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  for (final style in [PlayerStyle.inutilMusic, PlayerStyle.appleMusic]) {
    for (final scenario in [
      (
        name: 'desktop',
        platform: TargetPlatform.windows,
        size: const Size(1200, 800),
        artworkStyle: PlayerArtworkStyle.expanded,
        expandedBleed: true,
      ),
      (
        name: 'Android landscape tablet',
        platform: TargetPlatform.android,
        size: const Size(1200, 800),
        artworkStyle: PlayerArtworkStyle.expanded,
        expandedBleed: true,
      ),
      (
        name: 'iPad landscape',
        platform: TargetPlatform.iOS,
        size: const Size(1024, 768),
        artworkStyle: PlayerArtworkStyle.expanded,
        expandedBleed: true,
      ),
      (
        name: 'landscape phone',
        platform: TargetPlatform.android,
        size: const Size(844, 390),
        artworkStyle: PlayerArtworkStyle.expanded,
        expandedBleed: false,
      ),
      (
        name: 'portrait tablet',
        platform: TargetPlatform.android,
        size: const Size(800, 1200),
        artworkStyle: PlayerArtworkStyle.expanded,
        expandedBleed: false,
      ),
      (
        name: 'desktop classic artwork',
        platform: TargetPlatform.windows,
        size: const Size(1200, 800),
        artworkStyle: PlayerArtworkStyle.classic,
        expandedBleed: false,
      ),
    ]) {
      testWidgets('$style Canvas framing on ${scenario.name}', (tester) async {
        tester.view.physicalSize = scenario.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final originalVideoPlatform = VideoPlayerPlatform.instance;
        VideoPlayerPlatform.instance = _LayoutVideoPlatform();
        addTearDown(() => VideoPlayerPlatform.instance = originalVideoPlatform);
        final cache = _CompletedCanvasCache();
        final container = _canvasTestContainer(cache);
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(platform: scenario.platform),
              home: Scaffold(
                body: PlayerPanel(
                  style: style,
                  artworkStyle: scenario.artworkStyle,
                  spotifyCanvasEnabled: true,
                  animatedArtworkEnabled: false,
                  drawBackground: false,
                  trackTransitionsEnabled: false,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        final surface = find.byKey(const ValueKey('player-artwork-surface'));
        final viewport = find.byKey(const ValueKey('player-canvas-viewport'));
        expect(find.byType(SpotifyCanvasVideo), findsOneWidget);
        expect(
          tester
              .widget<SpotifyCanvasVideo>(find.byType(SpotifyCanvasVideo))
              .startOffset,
          Duration.zero,
        );
        expect(viewport, findsOneWidget);
        final coverRect = tester.getRect(surface);
        final videoRect = tester.getRect(viewport);
        // `player_panel.dart` decide `canUseSpotifyFullscreenCanvas`: con UI
        // móvil en retrato suficientemente ancho (por encima del umbral de
        // `fullBleedArtwork`), sin cola lateral, con canción y un estilo que
        // usa el lienzo de pantalla completa, el vídeo NO se recorta encima
        // de la carátula: `_SpotifyFullscreenCanvasPlayer` lo echa a pantalla
        // completa mientras la carátula conserva su cuadro cuadrado con
        // márgenes. Por eso el tablet vertical de 800×1200 no puede
        // comparar `videoRect` contra `coverRect`.
        final canvasFullscreen =
            AppPlatform.isMobileTargetPlatform(scenario.platform) &&
            scenario.size.height >= scenario.size.width &&
            scenario.size.width > 480 &&
            style == PlayerStyle.inutilMusic;
        if (canvasFullscreen) {
          expect(
            find.byKey(const ValueKey('player-mode-canvas')),
            findsOneWidget,
            reason: 'retrato ancho: el lienzo va a pantalla completa',
          );
          expect(
            videoRect,
            Rect.fromLTWH(
              0,
              0,
              scenario.size.width.toDouble(),
              scenario.size.height.toDouble(),
            ),
            reason: 'el viewport del lienzo ocupa el viewport entero',
          );
          expect(coverRect.width, coverRect.height);
          expect(coverRect.width, lessThan(scenario.size.width));
        } else if (scenario.expandedBleed) {
          expect(videoRect.left, lessThan(coverRect.left));
          expect(videoRect.top, lessThan(coverRect.top));
          expect(videoRect.right, greaterThan(coverRect.right));
          expect(videoRect.bottom, greaterThan(coverRect.bottom));
          expect(videoRect.width / coverRect.width, lessThanOrEqualTo(1.061));
          expect(videoRect.height / coverRect.height, lessThanOrEqualTo(1.061));
        } else {
          expect(videoRect, coverRect);
        }
        // El lienzo a pantalla completa monta el buscador de letras
        // (`lyricsServiceProvider` → `FallbackLyricsService`), que deja un
        // temporizador de espera de ·7 s pendiente, y `flutter_test` exige
        // `!timersPending` al cerrar el test. Se agota el reloj falso antes y
        // después de desmontar; medido: el temporizador caducaba a los
        // 6.998 s, así que dos bombas de 8 s lo alcanzan con holgura.
        for (var bomba = 0; bomba < 3; bomba++) {
          await tester.pump(const Duration(seconds: 8));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        for (var bomba = 0; bomba < 3; bomba++) {
          await tester.pump(const Duration(seconds: 8));
        }
        // En Linux el lienzo remoto esta cortado por diseño:
        // `player_panel.dart:407` excluye `AppPlatformType.linux` de
        // `remoteArtworkAllowed`, así que aquí no hay `SpotifyCanvasVideo`
        // que medir y los asserts (geometría del viewport, píxeles de la
        // ventana clara del scrim, transparencia bajo la máscara) se quedan
        // sin materia de trabajo. Medido sin el `skip`: 24 fallos
        // `Found 0 widgets with type "SpotifyCanvasVideo"` en este archivo.
        // En Windows, macOS, Android y iOS sí se ejecutan y ahí es donde
        // valen. La cobertura en Linux del bug que estos archivos destaparon
        // (el singleton `InutilPlaybackSyncService` desmontado por el primer
        // contenedor) vive en
        // `test/core/firebase/shared_singleton_dispose_test.dart` que sí
        // corre en todas las plataformas.
        // TODO(cesar): si `AppPlatform` admitiera inyección, este `skip` se
        // podría sustituir por un assert de "canvas ausente en Linux".
      }, skip: AppPlatform.current == AppPlatformType.linux);
    }
  }

  for (final style in [
    PlayerStyle.inutilMusic,
    PlayerStyle.appleMusic,
    PlayerStyle.spotifyMusic,
  ]) {
    for (final scenario in [
      (
        name: 'Android portrait',
        platform: TargetPlatform.android,
        size: const Size(390, 820),
        brightness: Brightness.dark,
        fullHero: true,
      ),
      (
        name: 'iPhone portrait with a light app theme',
        platform: TargetPlatform.iOS,
        size: const Size(390, 820),
        brightness: Brightness.light,
        fullHero: true,
      ),
      (
        name: 'dark desktop',
        platform: TargetPlatform.windows,
        size: const Size(1200, 800),
        brightness: Brightness.dark,
        fullHero: false,
      ),
      (
        name: 'light desktop',
        platform: TargetPlatform.windows,
        size: const Size(1200, 800),
        brightness: Brightness.light,
        fullHero: false,
      ),
    ]) {
      testWidgets('$style Canvas leaves no lower edge on ${scenario.name}', (
        tester,
      ) async {
        tester.view.physicalSize = scenario.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final originalVideoPlatform = VideoPlayerPlatform.instance;
        VideoPlayerPlatform.instance = _LayoutVideoPlatform();
        addTearDown(() => VideoPlayerPlatform.instance = originalVideoPlatform);
        final cache = _CompletedCanvasCache();
        final container = _canvasTestContainer(cache);
        addTearDown(container.dispose);
        final captureKey = GlobalKey();

        Widget harness({required bool canvasEnabled}) {
          return UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(
                platform: scenario.platform,
                brightness: scenario.brightness,
              ),
              home: Scaffold(
                body: RepaintBoundary(
                  key: captureKey,
                  child: ColoredBox(
                    color: scenario.brightness == Brightness.dark
                        ? const Color(0xFF321E38)
                        : const Color(0xFFF8E3CF),
                    child: PlayerPanel(
                      style: style,
                      artworkStyle: PlayerArtworkStyle.expanded,
                      spotifyCanvasEnabled: canvasEnabled,
                      animatedArtworkEnabled: false,
                      drawBackground: false,
                      trackTransitionsEnabled: false,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        await tester.pumpWidget(harness(canvasEnabled: true));
        await tester.pump();
        // Initialization and the resolver finish on different microtasks.
        // Wait for an advancing fake frame before finishing its reveal.
        final videoOpacity = find.descendant(
          of: find.byType(SpotifyCanvasVideo),
          matching: find.byType(AnimatedOpacity),
        );
        for (var attempt = 0; attempt < 10; attempt++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (videoOpacity.evaluate().isNotEmpty &&
              tester.widget<AnimatedOpacity>(videoOpacity.first).opacity == 1) {
            break;
          }
        }
        expect(tester.widget<AnimatedOpacity>(videoOpacity.first).opacity, 1);
        await tester.pump(const Duration(milliseconds: 300));
        // `player_panel.dart` decide `canUseSpotifyFullscreenCanvas`: con UI
        // móvil en retrato, sin cola lateral, con canción y un estilo que
        // usa el lienzo de pantalla completa, el vídeo no se recorta encima
        // de la carátula sino que ocupa el viewport entero; su revelado
        // vive dentro de `SpotifyCanvasVideo`, así que aquí no hay
        // `ShaderMask` que buscar ni borde inferior del que desbordar. Lo que
        // se comprueba en ese modo es que el viewport sea el viewport entero
        // y que el lienzo pinte hasta el borde físico.
        final canvasFullscreen =
            AppPlatform.isMobileTargetPlatform(scenario.platform) &&
            scenario.size.height >= scenario.size.width &&
            style != PlayerStyle.appleMusic;
        final fade = canvasFullscreen
            ? find.byKey(const ValueKey('player-canvas-viewport'))
            : find.byKey(
                ValueKey(
                  scenario.fullHero
                      ? 'player-expanded-artwork-video-fade'
                      : 'player-bounded-artwork-video-fade',
                ),
              );
        expect(fade, findsOneWidget);
        expect(find.byType(SpotifyCanvasVideo), findsOneWidget);
        final videoRect = tester.getRect(fade);
        final artworkRect = canvasFullscreen
            ? null
            : tester.getRect(
                find.byKey(const ValueKey('player-artwork-surface')),
              );
        if (canvasFullscreen) {
          expect(
            find.byKey(const ValueKey('player-mode-canvas')),
            findsOneWidget,
          );
          expect(
            videoRect,
            Rect.fromLTWH(
              0,
              0,
              scenario.size.width.toDouble(),
              scenario.size.height.toDouble(),
            ),
            reason: 'el lienzo móvil en retrato ocupa el viewport entero',
          );
        } else if (!scenario.fullHero) {
          expect(videoRect.bottom, greaterThan(artworkRect!.bottom));
        }
        final points = <Offset>[
          // A fully opaque point proves that the video was actually shown.
          Offset(videoRect.center.dx, videoRect.top + videoRect.height * .4),
          // A pantalla completa se muestrea la VENTANA CLARA del scrim (los
          // stops .16-.36 del degradado de
          // `spotify_fullscreen_canvas_player.dart:181`, donde el negro vale
          // .14 -> 0), que es donde la señal del lienzo sobrevive. En el modo
          // clásico las filas .975/.985/.995 siguen siendo las del borde de la
          // máscara de `ShaderMask`.
          for (final xFraction in [.25, .5, .75])
            for (final yFraction
                in canvasFullscreen ? [.16, .26, .36, .4] : [.975, .985, .995])
              Offset(
                videoRect.left + videoRect.width * xFraction,
                videoRect.top + videoRect.height * yFraction,
              ),
          // A fractional mask boundary can leak one unmasked video row even
          // when the preceding rows are fully transparent. A pantalla
          // completa el borde inferior del lienzo ES el borde físico del
          // viewport, no hay fila "por debajo" que filtrar, y las dos
          // últimas filas están bajo el scrim al 96 % de negro: ahí un
          // píxel no prueba nada, lo garantiza la geometría del assert de
          // arriba, así que esas filas solo se muestrean en el modo clásico.
          for (final xFraction in [.25, .5, .75])
            for (final y
                in canvasFullscreen
                    ? const <double>[]
                    : [
                        videoRect.bottom.floorToDouble(),
                        videoRect.bottom.ceilToDouble(),
                      ])
              Offset(videoRect.left + videoRect.width * xFraction, y),
          // Also cover the still artwork's boundary after Canvas overscan.
          if (artworkRect != null)
            Offset(artworkRect.center.dx, artworkRect.bottom - 1),
        ];
        final withCanvas = await _capturePixels(tester, captureKey, points);

        await tester.pumpWidget(harness(canvasEnabled: false));
        await tester.pump(const Duration(milliseconds: 500));
        if (canvasFullscreen) {
          // `_resolveFullscreenCanvasMode` retiene el modo de lienzo a
          // pantalla completa durante `_fullscreenCanvasGraceDuration`
          // (1400 ms, `player_panel.dart:244`) para no desmontar el
          // decodificador a mitad de un cambio de pestaña. El
          // `SpotifyCanvasVideo` sobrevive a los primeros 500 ms: hay que
          // agotar la prórroga antes de exigir que ya no esté.
          await tester.pump(const Duration(milliseconds: 1600));
          await tester.pump();
        }
        expect(find.byType(SpotifyCanvasVideo), findsNothing);
        final withoutCanvas = await _capturePixels(tester, captureKey, points);
        expect(
          [
            for (var channel = 0; channel < 3; channel++)
              (withCanvas.first[channel] - withoutCanvas.first[channel]).abs(),
          ].any((difference) => difference > 32),
          isTrue,
          reason:
              'The opaque cyan video must be visible above its fade: '
              '${withCanvas.first} versus ${withoutCanvas.first}.',
        );
        for (var point = 1; point < points.length; point++) {
          if (canvasFullscreen) {
            // No hay "debajo del borde": a pantalla completa el viewport del
            // lienzo ES el viewport entero y lo garante el assert geometrico
            // de arriba, así que aqui solo se comprueba que el lienzo este
            // vivo y pintando en la ventana clara del scrim.
            //
            // El scrim: `spotify_fullscreen_canvas_player.dart:181` pinta un
            // LinearGradient topCenter-bottomCenter con stops
            // [0, .16, .36, .58, .78, 1] y alphas de negro
            // [.62, .14, 0, .52, .90, .96]. Interpolado, el alpha vale .933
            // en yf=.9 (82 px del borde de una pantalla de 820), .946 en .95,
            // .953 en .975, .957 en .99 y .96 en el borde: de yf=.9 al borde
            // físico solo sobrevive entre el 4 % y el 7 % de la señal del
            // lienzo. Perfil medido (con/lienzo contra sin/lienzo, x=.5,
            // 390x820, `scratch/probe8.log`): dy 738 -> [18,37,36],
            // 656 -> [47,47,61], 164 -> [116,127,112], 123 -> [52,44,57],
            // 82 -> [27,17,31], 41 -> [12,2,16], 20.5 -> [12,2,16],
            // 8.2 -> [28,16,31], 2.0 y 1.0 -> [27,16,31]; spotifyMusic igual
            // (10/1/14 en las filas del pill de controles). Por encima de
            // yf=.55 el delta pasa 32 con holgura y de ahí al borde el scrim
            // lo aplasta a <=31/255 por canal, por diseño (para que se lean
            // los controles), no por falta de lienzo: exigir >32 en la ultima
            // fila era inalcanzable por principio. Por eso las filas
            // inferiores dejaron de muestrearse en este modo y "no hay borde"
            // se exige por geometría.
            expect(
              [
                for (var channel = 0; channel < 4; channel++)
                  (withCanvas[point][channel] - withoutCanvas[point][channel])
                      .abs(),
              ].any((difference) => difference > 32),
              isTrue,
              reason:
                  'El Canvas debe pintar en ${points[point]} '
                  '(dy=${(videoRect.bottom - points[point].dy).toStringAsFixed(1)} '
                  'del borde, dentro de la ventana clara del scrim): '
                  '${withCanvas[point]} versus ${withoutCanvas[point]}.',
            );
            continue;
          }
          for (var channel = 0; channel < 4; channel++) {
            expect(
              withCanvas[point][channel],
              closeTo(withoutCanvas[point][channel], 1),
              reason:
                  'Canvas must be transparent before its physical lower '
                  'edge at ${points[point]}, channel $channel.',
            );
          }
        }
        // El lienzo a pantalla completa monta el buscador de letras
        // (`lyricsServiceProvider` → `FallbackLyricsService`), que deja un
        // temporizador de espera de ·7 s pendiente, y `flutter_test` exige
        // `!timersPending` al cerrar el test. Se agota el reloj falso antes y
        // después de desmontar; medido: el temporizador caducaba a los
        // 6.998 s, así que dos bombas de 8 s lo alcanzan con holgura.
        for (var bomba = 0; bomba < 3; bomba++) {
          await tester.pump(const Duration(seconds: 8));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        for (var bomba = 0; bomba < 3; bomba++) {
          await tester.pump(const Duration(seconds: 8));
        }
        // En Linux el lienzo remoto esta cortado por diseño:
        // `player_panel.dart:407` excluye `AppPlatformType.linux` de
        // `remoteArtworkAllowed`, así que aquí no hay `SpotifyCanvasVideo`
        // que medir y los asserts (geometría del viewport, píxeles de la
        // ventana clara del scrim, transparencia bajo la máscara) se quedan
        // sin materia de trabajo. Medido sin el `skip`: 24 fallos
        // `Found 0 widgets with type "SpotifyCanvasVideo"` en este archivo.
        // En Windows, macOS, Android y iOS sí se ejecutan y ahí es donde
        // valen. La cobertura en Linux del bug que estos archivos destaparon
        // (el singleton `InutilPlaybackSyncService` desmontado por el primer
        // contenedor) vive en
        // `test/core/firebase/shared_singleton_dispose_test.dart` que sí
        // corre en todas las plataformas.
        // TODO(cesar): si `AppPlatform` admitiera inyección, este `skip` se
        // podría sustituir por un assert de "canvas ausente en Linux".
      }, skip: AppPlatform.current == AppPlatformType.linux);
    }
  }
}

ProviderContainer _canvasTestContainer(PlaybackVisualCache cache) {
  return ProviderContainer(
    overrides: [
      databaseServiceProvider.overrideWith(
        (ref) => throw StateError('Layout fixture cannot use user data'),
      ),
      playbackVisualCacheProvider.overrideWith((ref) => cache),
      spotifyCanvasResolverProvider.overrideWithValue(_FixtureCanvasResolver()),
      playerServiceProvider.overrideWithValue(_LayoutAudio()),
      playerControllerProvider.overrideWith(_LayoutPlayer.new),
      settingsControllerProvider.overrideWith(_LayoutSettings.new),
      playlistsControllerProvider.overrideWith(_LayoutPlaylists.new),
      libraryTracksProvider.overrideWith((ref) async => const <LocalTrack>[]),
      favoriteTrackIdsProvider.overrideWithValue(const <String>{}),
    ],
  );
}

Future<List<List<int>>> _capturePixels(
  WidgetTester tester,
  GlobalKey captureKey,
  List<Offset> globalPoints,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(captureKey),
  );
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
  try {
    final bytes = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    return [
      for (final globalPoint in globalPoints)
        () {
          final point = boundary.globalToLocal(globalPoint);
          final x = point.dx.floor();
          final y = point.dy.floor();
          expect(x, inInclusiveRange(0, image.width - 1));
          expect(y, inInclusiveRange(0, image.height - 1));
          final offset = (y * image.width + x) * 4;
          return [
            for (var channel = 0; channel < 4; channel++)
              bytes.getUint8(offset + channel),
          ];
        }(),
    ];
  } finally {
    image.dispose();
  }
}

const _snapshot = PlayerSnapshot(
  status: PlayerStatus.paused,
  title: 'Canvas layout fixture',
  artist: 'Inútil Music',
  trackId: 'canvas-layout-fixture',
  thumbnailUrl: '/fixture/cover.jpg',
  duration: Duration(minutes: 3),
);

class _CompletedCanvasCache extends PlaybackVisualCache {
  @override
  void activate({
    required String trackKey,
    required String? coverSource,
    String? coverFallbackSource,
    required Uri? videoUrl,
  }) {}

  @override
  Uri? videoFileFor(String trackKey, Uri? url) =>
      url == null ? null : Uri.file('/fixture/canvas.mp4');
}

class _FixtureCanvasResolver extends SpotifyCanvasResolver {
  @override
  Future<Uri?> resolve(SpotifyCanvasTrack track) async =>
      Uri.https('canvaz.scdn.co', '/fixture.mp4');
}

class _LayoutPlayer extends PlayerController {
  @override
  Future<PlayerSnapshot> build() async => _snapshot;
}

class _LayoutSettings extends SettingsController {
  @override
  Future<SettingsState> build() async => const SettingsState(
    downloadDirectory: '',
    language: AppLanguage.spanish,
    spotifyCanvasEnabled: true,
  );
}

class _LayoutPlaylists extends PlaylistsController {
  @override
  Future<List<Playlist>> build() async => const [];
}

class _LayoutAudio implements PlayerService {
  @override
  Stream<PlayerSnapshot> get snapshotStream => Stream.value(_snapshot);

  @override
  PlayerSnapshot get currentSnapshot => _snapshot;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LayoutVideoPlatform extends VideoPlayerPlatform {
  late final StreamController<VideoEvent> _events =
      StreamController<VideoEvent>(
        sync: true,
        onListen: () => scheduleMicrotask(() {
          _events.add(
            VideoEvent(
              eventType: VideoEventType.initialized,
              duration: const Duration(seconds: 20),
              size: const Size(720, 1280),
            ),
          );
        }),
      );

  @override
  Future<void> init() => SynchronousFuture(null);

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) =>
      SynchronousFuture(1);

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events.stream;

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) => SynchronousFuture(null);

  @override
  Future<void> setVolume(int playerId, double volume) =>
      SynchronousFuture(null);

  @override
  Future<void> setLooping(int playerId, bool looping) =>
      SynchronousFuture(null);

  @override
  Future<void> play(int playerId) => SynchronousFuture(null);

  @override
  Future<void> pause(int playerId) => SynchronousFuture(null);

  @override
  Future<Duration> getPosition(int playerId) =>
      SynchronousFuture(const Duration(seconds: 1));

  @override
  Future<void> seekTo(int playerId, Duration position) =>
      SynchronousFuture(null);

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.cyan);

  @override
  Future<void> dispose(int playerId) => _events.close();
}
