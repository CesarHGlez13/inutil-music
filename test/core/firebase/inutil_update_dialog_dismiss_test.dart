import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/firebase/inutil_update_service.dart';

void main() {
  test(
    'isBlockingUpdate is false when already on latestVersion even if mandatory=true',
    () {
      final upToDate = InutilReleaseInfo(
        currentVersion: '2.1.2',
        latestVersion: '2.1.2',
        minSupportedVersion: '2.1.2',
        mandatory: true,
        releaseNotes: const ['Mejoras de estabilidad'],
        publishedAt: DateTime.utc(2026, 11, 17),
      );
      expect(upToDate.updateAvailable, isFalse);
      expect(upToDate.belowMinSupported, isFalse);
      expect(upToDate.isBlockingUpdate, isFalse);

      final outdated = InutilReleaseInfo(
        currentVersion: '2.1.1',
        latestVersion: '2.1.2',
        minSupportedVersion: '2.1.2',
        mandatory: true,
        releaseNotes: const ['Mejoras de estabilidad'],
        publishedAt: DateTime.utc(2026, 11, 17),
      );
      expect(outdated.updateAvailable, isTrue);
      expect(outdated.isBlockingUpdate, isTrue);
    },
  );

  testWidgets(
    'up-to-date dialog exposes Aceptar and close controls and dismisses cleanly',
    (tester) async {
      final upToDate = InutilReleaseInfo(
        currentVersion: '2.1.2',
        latestVersion: '2.1.2',
        minSupportedVersion: '2.1.2',
        mandatory: true,
        releaseNotes: const ['Mejoras'],
        publishedAt: DateTime.utc(2026, 11, 17),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showInutilUpdateDialog(context, upToDate),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Tu app está actualizada'), findsOneWidget);
      expect(find.text('Aceptar'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();

      expect(find.text('Tu app está actualizada'), findsNothing);
    },
  );
}
