import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/platform/app_platform.dart';
import 'package:inutil_music/features/music/domain/entities/lyrics.dart';
import 'package:inutil_music/features/music/presentation/providers/moment_clip_providers.dart';
import 'package:inutil_music/features/music/presentation/providers/music_providers.dart';
import 'package:inutil_music/features/music/presentation/widgets/moment_share_sheet.dart';
import 'package:inutil_music/services/player/player_service.dart';
import 'package:inutil_music/services/sharing/moment_clip_export_service.dart';
import 'package:inutil_music/services/sharing/moment_clip_models.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MomentClipWindow', () {
    test('clamps duration to [5s, 30s] and shifts start inside track bounds', () {
      final shortReq = MomentClipWindow.resolve(
        requestedStart: const Duration(seconds: 20),
        requestedDuration: const Duration(seconds: 2),
        trackDuration: const Duration(minutes: 3),
      );
      expect(shortReq.duration, const Duration(seconds: 5));
      expect(shortReq.start, const Duration(seconds: 20));
      expect(shortReq.end, const Duration(seconds: 25));

      final longReq = MomentClipWindow.resolve(
        requestedStart: const Duration(seconds: 170),
        requestedDuration: const Duration(seconds: 45),
        trackDuration: const Duration(minutes: 3),
      );
      expect(longReq.duration, const Duration(seconds: 30));
      expect(longReq.start, const Duration(seconds: 150));
      expect(longReq.end, const Duration(seconds: 180));
    });

    test('handles tracks shorter than 5 seconds gracefully', () {
      final tiny = MomentClipWindow.resolve(
        requestedStart: const Duration(seconds: 2),
        requestedDuration: const Duration(seconds: 15),
        trackDuration: const Duration(seconds: 3),
      );
      expect(tiny.start, Duration.zero);
      expect(tiny.duration, const Duration(seconds: 3));
      expect(tiny.end, const Duration(seconds: 3));
    });
  });

  group('MomentClipExportRequest', () {
    test('serializes mode, headers, and valid word timings to channel payload', () {
      const request = MomentClipExportRequest(
        jobId: 'job-1',
        mode: MomentClipMode.lyrics,
        title: 'Nadie Sabe Lo Que Tiene',
        artist: 'Efecto Elegante',
        album: 'En Vivo',
        audioSource: MomentExportableAudioSource(
          uri: 'https://example.com/audio.webm',
          httpHeaders: {'User-Agent': 'InutilTest/1.0'},
        ),
        videoUri: null,
        artworkSource: 'https://example.com/cover.jpg',
        accentColorArgb: 0xFF1DB954,
        start: Duration(seconds: 25),
        end: Duration(seconds: 40),
        trackDuration: Duration(minutes: 3, seconds: 41),
        lyricsOffset: Duration(milliseconds: -200),
        lyricsCentered: true,
        lyrics: [
          LyricLine(
            timestamp: Duration(seconds: 28),
            text: 'Un gran amor',
            words: [
              LyricWord(
                text: 'Un',
                start: Duration(seconds: 28),
                end: Duration(seconds: 28, milliseconds: 400),
                startOffset: 0,
                endOffset: 2,
              ),
              LyricWord(
                text: 'gran',
                start: Duration(seconds: 28, milliseconds: 400),
                end: Duration(seconds: 28, milliseconds: 900),
                startOffset: 3,
                endOffset: 7,
              ),
              LyricWord(
                text: 'amor',
                start: Duration(seconds: 28, milliseconds: 900),
                end: Duration(seconds: 29, milliseconds: 500),
                startOffset: 8,
                endOffset: 12,
              ),
            ],
          ),
        ],
      );

      final map = request.toChannelMap(outputPath: '/tmp/clip.mp4');
      expect(map['mode'], 'lyrics');
      expect(map['audioUri'], 'https://example.com/audio.webm');
      expect(map['audioHeaders'], {'User-Agent': 'InutilTest/1.0'});
      expect(map['startMs'], 25000);
      expect(map['endMs'], 40000);
      expect(map['lyricsOffsetMs'], -200);
      expect(map['lyricsCentered'], true);
      expect(map['outputPath'], '/tmp/clip.mp4');

      final serializedLyrics = map['lyrics'] as List<dynamic>;
      expect(serializedLyrics, hasLength(1));
      final firstLine = serializedLyrics.first as Map<String, Object?>;
      expect(firstLine['text'], 'Un gran amor');
      expect((firstLine['words'] as List<dynamic>), hasLength(3));
    });
  });

  group('DefaultMomentClipExportService', () {
    test('reports Android supported and Linux unsupported', () {
      final androidService = DefaultMomentClipExportService(
        platform: () => AppPlatformType.android,
      );
      final linuxService = DefaultMomentClipExportService(
        platform: () => AppPlatformType.linux,
      );
      expect(androidService.isSupported, isTrue);
      expect(linuxService.isSupported, isFalse);
    });

    test('exports via channel, shares as video/mp4, and saves via Android exporter', () async {
      final tempRoot = await Directory.systemTemp.createTemp('moment_test_');
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      const methodChannel = MethodChannel('test/moment_exporter');
      const progressChannel = EventChannel('test/moment_exporter/progress');
      Map<dynamic, dynamic>? capturedArgs;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            if (call.method == 'exportMoment') {
              capturedArgs = call.arguments as Map<dynamic, dynamic>;
              final outPath = capturedArgs!['outputPath'] as String;
              await File(outPath).writeAsBytes(const [0, 0, 0, 24, 102, 116, 121, 112]);
              return {
                'outputPath': outPath,
                'width': 1080,
                'height': 1920,
                'fps': 60,
                'sizeBytes': 8,
                'durationMs': 15000,
              };
            }
            if (call.method == 'probeCapabilities') {
              return {'width': 1080, 'height': 1920, 'fps': 60};
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, null);
      });

      ShareParams? capturedShare;
      String? capturedSaveMime;
      final service = DefaultMomentClipExportService(
        platform: () => AppPlatformType.android,
        methodChannel: methodChannel,
        progressChannel: progressChannel,
        temporaryDirectoryFactory: () async => tempRoot,
        nativeShare: (params) async {
          capturedShare = params;
        },
        androidSave: ({required sourcePath, required fileName, required mimeType}) async {
          capturedSaveMime = mimeType;
          return 'content://media/external/video/42';
        },
      );

      final caps = await service.probeCapabilities();
      expect(caps?.badgeLabel, '1080p · 60fps');

      final result = await service.exportMoment(
        const MomentClipExportRequest(
          jobId: 'job-export-1',
          mode: MomentClipMode.player,
          title: 'Nadie Sabe Lo Que Tiene',
          artist: 'Efecto Elegante',
          audioSource: MomentExportableAudioSource(uri: '/music/song.m4a'),
          start: Duration(seconds: 10),
          end: Duration(seconds: 25),
          trackDuration: Duration(minutes: 3),
          accentColorArgb: 0xFF6C8CFF,
        ),
      );

      expect(result.width, 1080);
      expect(result.height, 1920);
      expect(result.fps, 60);
      expect(p.basename(result.outputPath), 'InutilMusic_Nadie_Sabe_Lo_Que_Tiene.mp4');
      expect(capturedArgs?['mode'], 'player');

      await service.shareClip(
        filePath: result.outputPath,
        title: 'Nadie Sabe Lo Que Tiene',
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 100, 100),
      );
      expect(capturedShare?.files?.single.mimeType, 'video/mp4');

      final savedUri = await service.saveClip(
        filePath: result.outputPath,
        title: 'Nadie Sabe Lo Que Tiene',
      );
      expect(savedUri, 'content://media/external/video/42');
      expect(capturedSaveMime, 'video/mp4');
    });

    test('maps CANCELLED platform error to MomentExportCancelledException', () async {
      final tempRoot = await Directory.systemTemp.createTemp('moment_cancel_');
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      const methodChannel = MethodChannel('test/moment_exporter_cancel');
      const progressChannel = EventChannel('test/moment_exporter_cancel/progress');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            throw PlatformException(code: 'CANCELLED', message: 'cancelled');
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, null);
      });

      final service = DefaultMomentClipExportService(
        platform: () => AppPlatformType.android,
        methodChannel: methodChannel,
        progressChannel: progressChannel,
        temporaryDirectoryFactory: () async => tempRoot,
      );

      await expectLater(
        () => service.exportMoment(
          const MomentClipExportRequest(
            jobId: 'job-cancel',
            mode: MomentClipMode.lyrics,
            title: 'Song',
            artist: 'Artist',
            audioSource: MomentExportableAudioSource(uri: '/music/song.m4a'),
            start: Duration.zero,
            end: Duration(seconds: 15),
            trackDuration: Duration(minutes: 2),
            accentColorArgb: 0xFF6C8CFF,
          ),
        ),
        throwsA(isA<MomentExportCancelledException>()),
      );
    });
  });

  group('MomentShareSheet widget', () {
    testWidgets('renders mode pills, watermark, presets and switches modes', (tester) async {
      final fakeService = _FakeMomentClipExportService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            momentClipExportServiceProvider.overrideWithValue(fakeService),
            playerControllerProvider.overrideWith(_FakePlayerController.new),
            currentLyricsDocumentProvider.overrideWithValue(
              const LyricsDocument(
                provider: 'Better Lyrics',
                trackName: 'Nadie Sabe Lo Que Tiene',
                artistName: 'Efecto Elegante',
                lines: [
                  LyricLine(
                    timestamp: Duration(seconds: 28),
                    text: 'Un gran amor tuve ayer',
                  ),
                  LyricLine(
                    timestamp: Duration(seconds: 34),
                    text: 'Era tan linda y hermosa',
                  ),
                ],
              ),
            ),
          ],
          child: const MaterialApp(
            home: MomentShareSheet(initialMode: MomentClipMode.lyrics),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inutix Music'), findsWidgets);
      expect(find.byKey(const ValueKey('moment-mode-lyrics')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-mode-player')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-duration-15s')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-duration-30s')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-lyric-anchor-0')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('moment-mode-player')));
      await tester.pumpAndSettle();
      expect(find.text('Nadie Sabe Lo Que Tiene'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('moment-duration-20s')));
      await tester.pumpAndSettle();
      expect(find.text('0:28 – 0:48'), findsOneWidget);
    });
  });
}

class _FakePlayerController extends PlayerController {
  @override
  Future<PlayerSnapshot> build() async => const PlayerSnapshot(
    status: PlayerStatus.playing,
    title: 'Nadie Sabe Lo Que Tiene',
    artist: 'Efecto Elegante',
    album: 'En Vivo',
    trackId: 'track-1',
    sourceUrl: '/tmp/fake.m4a',
    position: Duration(seconds: 29),
    duration: Duration(minutes: 3, seconds: 41),
  );
}

class _FakeMomentClipExportService implements MomentClipExportService {
  @override
  bool get isSupported => true;

  @override
  Future<MomentClipCapabilities?> probeCapabilities() async =>
      const MomentClipCapabilities(width: 1080, height: 1920, fps: 60);

  @override
  Future<MomentClipExportResult> exportMoment(
    MomentClipExportRequest request, {
    void Function(MomentClipProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      MomentClipProgress(
        jobId: request.jobId,
        stage: MomentExportStage.done,
        progress: 1.0,
      ),
    );
    return MomentClipExportResult(
      outputPath: '/tmp/out.mp4',
      width: 1080,
      height: 1920,
      fps: 60,
      sizeBytes: 1024,
      duration: request.end - request.start,
    );
  }

  @override
  Future<void> cancelExport({String? jobId}) async {}

  @override
  Future<void> shareClip({
    required String filePath,
    required String title,
    required Rect sharePositionOrigin,
  }) async {}

  @override
  Future<String?> saveClip({
    required String filePath,
    required String title,
  }) async => 'content://saved/out.mp4';
}
