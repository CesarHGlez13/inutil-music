import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/theme/inutil_icons.dart';
import 'package:inutil_music/features/music/presentation/providers/music_providers.dart';
import 'package:inutil_music/features/music/presentation/widgets/inutil_sleep_timer_sheet.dart';

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
}
