import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/features/music/domain/entities/lyric_line.dart';
import 'package:inutil_music/features/music/domain/entities/lyrics_document.dart';
import 'package:inutil_music/features/music/presentation/widgets/playback_gradient_background.dart';
import 'package:inutil_music/features/music/presentation/widgets/player_panel.dart';
import 'package:inutil_music/features/music/presentation/widgets/source_image.dart';

void main() {
  group('activeSyncedLyricLineText', () {
    const doc = LyricsDocument(
      provider: 'lrclib',
      trackName: 'Fluid Track',
      artistName: 'Artist',
      lines: [
        LyricLine(timestamp: Duration(seconds: 2), text: '  First line  '),
        LyricLine(timestamp: Duration(seconds: 5), text: ''),
        LyricLine(timestamp: Duration(seconds: 8), text: 'Second line'),
        LyricLine(timestamp: Duration(seconds: 12), text: 'Third line'),
      ],
    );

    test('falls back to first non-empty line before initial timestamp', () {
      expect(
        activeSyncedLyricLineText(doc, const Duration(milliseconds: 500)),
        'First line',
      );
    });

    test('matches exact timestamps and skips blank separator lines', () {
      expect(
        activeSyncedLyricLineText(doc, const Duration(seconds: 2)),
        'First line',
      );
      expect(
        activeSyncedLyricLineText(doc, const Duration(seconds: 6)),
        'First line',
      );
      expect(
        activeSyncedLyricLineText(doc, const Duration(seconds: 9)),
        'Second line',
      );
      expect(
        activeSyncedLyricLineText(doc, const Duration(seconds: 30)),
        'Third line',
      );
    });

    test('returns empty string when document has no non-empty lines', () {
      const emptyDoc = LyricsDocument(
        provider: 'lrclib',
        trackName: 'Instrumental',
        artistName: 'Artist',
      );
      expect(activeSyncedLyricLineText(emptyDoc, Duration.zero), isEmpty);
    });
  });

  testWidgets(
    'PlaybackArtworkBackdrop downsamples heavy blur decode unless sharp reflection is active',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 400,
              child: PlaybackArtworkBackdrop(
                source: '/fixture/cover.png',
                animateTrackChanges: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final blurredImage = tester.widget<SourceImage>(
        find.byType(SourceImage).first,
      );
      expect(blurredImage.cacheWidth, 256);
      expect(blurredImage.filterQuality, FilterQuality.low);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 400,
              child: PlaybackArtworkBackdrop(
                source: '/fixture/cover.png',
                animateTrackChanges: false,
                reflectionArtworkRect: Rect.fromLTWH(24, 24, 342, 342),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final reflectedImage = tester.widget<SourceImage>(
        find.byType(SourceImage).first,
      );
      expect(reflectedImage.cacheWidth, 1280);
      expect(reflectedImage.filterQuality, FilterQuality.medium);
    },
  );
}
