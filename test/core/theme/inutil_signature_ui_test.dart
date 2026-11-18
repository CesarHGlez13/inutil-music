import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/firebase/inutil_promo_popup_service.dart';
import 'package:inutil_music/core/firebase/inutil_wrapped_service.dart';
import 'package:inutil_music/core/theme/inutil_icons.dart';
import 'package:inutil_music/features/music/presentation/providers/music_providers.dart';
import 'package:inutil_music/features/music/presentation/widgets/inutil_sleep_timer_sheet.dart';
import 'package:inutil_music/features/music/presentation/widgets/inutil_support_popup.dart';
import 'package:inutil_music/features/music/presentation/widgets/inutil_wrapped_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('every InutilGlyph paints cleanly in outline and filled states', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final glyph in InutilGlyph.values) ...[
                  InutilIcon(glyph, filled: false, size: 24),
                  InutilIcon(glyph, filled: true, size: 24),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byType(InutilIcon),
      findsNWidgets(InutilGlyph.values.length * 2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('InutilSleepTimerSheet activates and cancels sleep timer', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => InutilSleepTimerSheet.show(context),
                  child: const Text('Timer'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Timer'));
    await tester.pumpAndSettle();
    expect(find.text('Temporizador de sueño'), findsOneWidget);

    await tester.tap(find.text('30 minutos'));
    await tester.pumpAndSettle();
    expect(container.read(sleepTimerControllerProvider).isActive, isTrue);
    expect(
      container.read(sleepTimerControllerProvider).selectedDuration,
      const Duration(minutes: 30),
    );

    await tester.tap(find.text('Timer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desactivar temporizador'));
    await tester.pumpAndSettle();
    expect(container.read(sleepTimerControllerProvider).isActive, isFalse);
  });

  test('InutilPromoPopupService rotates through all creative campaigns without repeating', () async {
    SharedPreferences.setMockInitialValues({});
    final seenIds = <String>[];
    for (var i = 0; i < InutilPromoPopupService.creatorCampaigns.length; i++) {
      final campaign =
          await InutilPromoPopupService.instance.nextRotatingCampaign();
      seenIds.add(campaign.id);
    }
    expect(
      seenIds.toSet().length,
      InutilPromoPopupService.creatorCampaigns.length,
    );
  });

  testWidgets('InutilSupportPopupDialog displays campaign and launches CTA cleanly', (
    tester,
  ) async {
    Uri? launchedUri;
    final campaign = InutilPromoPopupService.creatorCampaigns.first;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => InutilSupportPopupDialog.show(
                  context,
                  campaign,
                  onOpenUrl: (uri) async => launchedUri = uri,
                ),
                child: const Text('Popup'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Popup'));
    await tester.pumpAndSettle();
    expect(find.text(campaign.headline), findsOneWidget);
    expect(find.text(campaign.primaryCta), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('inutil-support-popup-primary')));
    await tester.pumpAndSettle();
    expect(launchedUri, isNotNull);
    expect(find.byKey(const ValueKey('inutil-support-popup-card')), findsNothing);
  });

  test('InutilWrappedService accumulates listening seconds, plays, top artist and song', () async {
    SharedPreferences.setMockInitialValues({});
    final service = InutilWrappedService.instance..resetForTesting();

    // Simula 25 segundos de reproducción continua de una canción.
    for (var sec = 0; sec <= 25; sec += 5) {
      service.recordPlaybackTick(
        trackId: 'track-nodal-1',
        title: 'Adiós Amor',
        artist: 'Christian Nodal',
        thumbnailUrl: null,
        positionMs: sec * 1000,
        isPlaying: true,
      );
    }
    final summary = await service.buildSummary();
    expect(summary.totalSeconds, greaterThanOrEqualTo(20));
    expect(summary.totalPlays, 1);
    expect(summary.topArtist?.name, 'Christian Nodal');
    expect(summary.topTrack?.title, 'Adiós Amor');
    service.resetForTesting();
  });

  testWidgets('InutilWrappedDialog renders all 6 slides and closes cleanly', (
    tester,
  ) async {
    const summary = InutilWrappedSummary(
      year: 2026,
      totalSeconds: 18420,
      totalPlays: 84,
      topTracks: [
        WrappedTrackStat(
          id: 't1',
          title: 'Amor del Bueno',
          artist: 'Reyli Barba',
          plays: 22,
          seconds: 5100,
        ),
      ],
      topArtists: [
        WrappedArtistStat(
          name: 'Reyli Barba',
          plays: 31,
          seconds: 7400,
        ),
      ],
      uniqueTrackCount: 42,
      uniqueArtistCount: 15,
      activeDaysCount: 18,
      peakHour: 23,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => InutilWrappedDialog.show(
                  context,
                  summary: summary,
                  userName: 'César',
                  playlistCount: 4,
                ),
                child: const Text('Wrapped'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Wrapped'));
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(const ValueKey('inutil-wrapped-dialog')), findsOneWidget);

    // Avanzar por las 6 diapositivas tocando a la derecha.
    for (var i = 0; i < 5; i++) {
      await tester.tapAt(const Offset(650, 300));
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byKey(const ValueKey('inutil-wrapped-share')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('inutil-wrapped-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inutil-wrapped-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
