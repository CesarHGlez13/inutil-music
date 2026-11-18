import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/firebase/firebase_auth_service.dart';
import 'package:inutil_music/core/firebase/inutil_inactivity_paused_screen.dart';
import 'package:inutil_music/features/music/presentation/widgets/inutil_onboarding_tour.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('InutilAuthService.inactivityPauseDays', () {
    final now = DateTime(2026, 11, 18, 12, 0);

    test('returns null when policy is disabled or user is exempt', () {
      final old = now.subtract(const Duration(days: 40));
      expect(
        InutilAuthService.inactivityPauseDays(
          lastActiveAt: old,
          exempt: false,
          enabled: false,
          thresholdDays: 15,
          now: now,
        ),
        isNull,
      );
      expect(
        InutilAuthService.inactivityPauseDays(
          lastActiveAt: old,
          exempt: true,
          enabled: true,
          thresholdDays: 15,
          now: now,
        ),
        isNull,
      );
    });

    test('returns null during migration when lastActiveAt is null', () {
      expect(
        InutilAuthService.inactivityPauseDays(
          lastActiveAt: null,
          exempt: false,
          enabled: true,
          thresholdDays: 15,
          now: now,
        ),
        isNull,
      );
    });

    test('pauses once elapsed days reach or exceed thresholdDays', () {
      expect(
        InutilAuthService.inactivityPauseDays(
          lastActiveAt: now.subtract(const Duration(days: 14, hours: 23)),
          exempt: false,
          enabled: true,
          thresholdDays: 15,
          now: now,
        ),
        isNull,
      );
      expect(
        InutilAuthService.inactivityPauseDays(
          lastActiveAt: now.subtract(const Duration(days: 15)),
          exempt: false,
          enabled: true,
          thresholdDays: 15,
          now: now,
        ),
        15,
      );
      expect(
        InutilAuthService.inactivityPauseDays(
          lastActiveAt: now.subtract(const Duration(days: 22)),
          exempt: false,
          enabled: true,
          thresholdDays: 15,
          now: now,
        ),
        22,
      );
    });
  });

  testWidgets(
    'InutilInactivityPausedScreen shows cloud-safe details and sends reactivation request',
    (tester) async {
      var requested = false;
      const user = InutilUser(
        uid: 'u-paused-1',
        email: 'prueba@correo.com',
        displayName: 'Cesar Prueba',
        status: 'active',
        isActive: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: InutilInactivityPausedScreen(
            user: user,
            inactiveDays: 18,
            policyDays: 15,
            onRequestReactivation: () async {
              requested = true;
              return true;
            },
            onCheckStatus: () async {},
            onSignOut: () async {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(const ValueKey('inutil-inactivity-paused-screen')),
        findsOneWidget,
      );
      expect(find.textContaining('18 días'), findsOneWidget);
      expect(find.textContaining('TU MÚSICA SIGUE A SALVO'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('inactivity-request-reactivation')),
      );
      await tester.tap(
        find.byKey(const ValueKey('inactivity-request-reactivation')),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(requested, isTrue);
      expect(find.text('Solicitud enviada'), findsOneWidget);
      expect(find.byKey(const ValueKey('inactivity-feedback')), findsOneWidget);
    },
  );

  testWidgets(
    'InutilOnboardingTour runs interactive demos across all 8 steps and marks completion',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      expect(await InutilOnboardingTour.shouldShow(), isTrue);

      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      InutilOnboardingTour.show(context, inactivityDays: 15),
                  child: const Text('Abrir guía'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir guía'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.byKey(const ValueKey('onboarding-tour')), findsOneWidget);
      expect(find.text('1 de 8'), findsOneWidget);

      Future<void> tapNext() async {
        await tester.tap(find.byKey(const ValueKey('onboarding-next')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 650));
      }

      // Avanzar al paso 3 (Reproductor) y probar demo interactiva de Play.
      await tapNext();
      expect(find.text('2 de 8'), findsOneWidget);

      await tapNext();
      expect(find.text('3 de 8'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('onboarding-demo-play')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('amor del bueno'), findsOneWidget);

      // Avanzar al paso 4 (Desliza a la cola) y probar gesto horizontal real.
      await tapNext();
      expect(find.text('4 de 8'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('onboarding-demo-swipe')),
        const Offset(140, 0),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('¡Añadida a la cola!'), findsOneWidget);

      // Avanzar al paso 5 (Favoritos) y tocar el corazón interactivo.
      await tapNext();
      expect(find.text('5 de 8'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('onboarding-demo-heart')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('respaldada en la nube'), findsOneWidget);

      // Avanzar hasta el paso 8 y cerrar con «¡Empezar a escuchar!».
      for (var step = 6; step <= 8; step++) {
        await tapNext();
        expect(find.text('$step de 8'), findsOneWidget);
      }

      expect(find.textContaining('15 días'), findsAtLeastNWidgets(1));
      await tester.tap(find.byKey(const ValueKey('onboarding-finish')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const ValueKey('onboarding-tour')), findsNothing);
      expect(await InutilOnboardingTour.shouldShow(), isFalse);
    },
  );
}
