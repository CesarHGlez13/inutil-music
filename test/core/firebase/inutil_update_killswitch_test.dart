import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inutil_music/core/firebase/inutil_update_gate.dart';
import 'package:inutil_music/core/firebase/inutil_update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manifiesto de prueba: lo que el panel de administración publica en
/// `app_config/release`. [min] es el kill switch (minSupportedVersion).
InutilReleaseInfo manifest({
  required String installed,
  required String latest,
  String min = '',
  bool mandatory = false,
}) {
  return InutilReleaseInfo(
    currentVersion: installed,
    latestVersion: latest,
    minSupportedVersion: min,
    mandatory: mandatory,
    releaseNotes: const ['Letras sincronizadas.', 'Respaldo en la nube.'],
    apkDownloadUrl: 'https://example.test/inutil_latest.apk',
    linuxDownloadUrl: 'https://example.test/inutil_linux.tar.gz',
    publishedAt: DateTime.utc(2026, 11, 17),
    androidDownloads: const {
      'arm64_v8a': 'https://example.test/inutil_arm64.apk',
      'universal': 'https://example.test/inutil_universal.apk',
    },
    androidDownloadSizes: const {'arm64_v8a': 47185920},
  );
}

void main() {
  group('Kill switch OTA (InutilReleaseInfo)', () {
    test('Una versión instalada por debajo del mínimo queda inhabilitada', () {
      final release = manifest(
        installed: '2.0.0',
        latest: '2.1.0',
        min: '2.1.0',
      );
      expect(release.belowMinSupported, isTrue);
      expect(release.updateAvailable, isTrue);
      // Sin `mandatory` explícito, el kill switch vuelve el diálogo obligatorio.
      expect(release.effectiveMandatory, isTrue);
    });

    test('minSupportedVersion igual a la instalada sigue funcionando', () {
      final release = manifest(
        installed: '2.1.0',
        latest: '2.1.0',
        min: '2.1.0',
      );
      expect(release.belowMinSupported, isFalse);
      expect(release.updateAvailable, isFalse);
      expect(release.effectiveMandatory, isFalse);
    });

    test('Compara semver por componentes, no como texto', () {
      expect(
        manifest(installed: '2.9.9', latest: '2.10.0').updateAvailable,
        isTrue,
      );
      expect(
        manifest(installed: '2.10.0', latest: '2.9.9').updateAvailable,
        isFalse,
      );
      expect(
        manifest(
          installed: '2.10.0',
          latest: '2.11.0',
          min: '2.10',
        ).belowMinSupported,
        isFalse,
      );
    });

    test('mandatory manual también hace el diálogo no descartable', () {
      final release = manifest(
        installed: '2.0.0',
        latest: '2.1.0',
        mandatory: true,
      );
      expect(release.belowMinSupported, isFalse);
      expect(release.effectiveMandatory, isTrue);
    });

    test('Elige el APK de la ABI del dispositivo con respaldo universal', () {
      final release = manifest(installed: '2.0.0', latest: '2.1.0');
      expect(
        release.apkUrlForAbi('arm64-v8a'),
        'https://example.test/inutil_arm64.apk',
      );
      expect(
        release.apkUrlForAbi('x86_64'),
        'https://example.test/inutil_universal.apk',
      );
      expect(release.packageSizeForAbi('arm64-v8a'), 47185920);
      final plain = InutilReleaseInfo(
        currentVersion: '2.0.0',
        latestVersion: '2.1.0',
        releaseNotes: const <String>[],
        apkDownloadUrl: 'https://example.test/inutil_latest.apk',
        publishedAt: DateTime.utc(2026, 11, 17),
      );
      expect(
        plain.apkUrlForAbi('arm64-v8a'),
        'https://example.test/inutil_latest.apk',
      );
      // En Linux de pruebas el enlace de la plataforma es el paquete de PC.
      expect(
        release.platformDownloadUrl,
        'https://example.test/inutil_linux.tar.gz',
      );
    });
  });

  group('InutilUpdateGate (OTA forzosa a pantalla completa)', () {
    setUp(() {
      InutilUpdateService.testReleaseOverride = null;
    });

    tearDown(() {
      InutilUpdateService.testReleaseOverride = null;
    });

    Future<void> pumpGate(WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: InutilUpdateGate(child: Scaffold(body: Text('APP_INTERIOR'))),
          ),
        ),
      );
      // Deja resolver el checkForUpdate del gate (manifiesto fijado, sin red).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets(
      'Bloquea TODA la app con el letrero si la versión quedó sin soporte',
      (tester) async {
        InutilUpdateService.testReleaseOverride = manifest(
          installed: '2.0.0',
          latest: '2.1.0',
          min: '2.1.0',
        );

        await pumpGate(tester);

        expect(find.text('ACTUALIZACIÓN REQUERIDA'), findsOneWidget);
        expect(find.text('Actualización requerida'), findsOneWidget);
        expect(find.text('APP_INTERIOR'), findsNothing);
        // Obligada: no existe botón para descartar el letrero.
        expect(find.text('Más tarde'), findsNothing);
        expect(find.text('Actualizar v2.1.0'), findsOneWidget);
      },
    );

    testWidgets('El letrero no se puede cerrar con el botón atrás', (
      tester,
    ) async {
      InutilUpdateService.testReleaseOverride = manifest(
        installed: '1.9.0',
        latest: '2.1.0',
        min: '2.1.0',
      );

      await pumpGate(tester);
      expect(find.text('APP_INTERIOR'), findsNothing);

      // El bloqueo no es un diálogo descartable: la puerta envuelve la
      // pantalla con PopScope(canPop: false).
      final scope = tester.widget<PopScope>(
        find
            .descendant(
              of: find.byType(InutilUpdateGate),
              matching: find.byType(PopScope),
            )
            .first,
      );
      expect(scope.canPop, isFalse);

      // Simula el botón "atrás" del sistema (pop de ruta).
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('ACTUALIZACIÓN REQUERIDA'), findsOneWidget);
      expect(find.text('APP_INTERIOR'), findsNothing);
    });

    testWidgets('Con la versión al día la app se usa con normalidad', (
      tester,
    ) async {
      InutilUpdateService.testReleaseOverride = manifest(
        installed: '2.1.0',
        latest: '2.1.0',
        min: '2.1.0',
      );

      await pumpGate(tester);

      expect(find.text('APP_INTERIOR'), findsOneWidget);
      expect(find.text('ACTUALIZACIÓN REQUERIDA'), findsNothing);
    });

    testWidgets('Actualización opcional no interrumpe el arranque', (
      tester,
    ) async {
      InutilUpdateService.testReleaseOverride = manifest(
        installed: '2.0.0',
        latest: '2.1.0',
      );

      await pumpGate(tester);

      expect(find.text('APP_INTERIOR'), findsOneWidget);
      expect(find.byType(InutilForceUpdateScreen), findsNothing);
    });

    testWidgets('mandatory del manifiesto también bloquea', (tester) async {
      InutilUpdateService.testReleaseOverride = manifest(
        installed: '2.0.0',
        latest: '2.1.0',
        mandatory: true,
      );

      await pumpGate(tester);

      expect(find.text('ACTUALIZACIÓN DISPONIBLE'), findsOneWidget);
      // mandatory=true hace el letrero no descartable: nada de "Más tarde".
      expect(find.text('Más tarde'), findsNothing);
      expect(find.text('APP_INTERIOR'), findsNothing);
    });

    testWidgets('Sin manifiesto accesible la app arranca normal (no se '
        'autobloquea por estar sin red)', (tester) async {
      InutilUpdateService.testReleaseOverride = null;

      await pumpGate(tester);

      expect(find.text('APP_INTERIOR'), findsOneWidget);
      expect(find.byType(InutilForceUpdateScreen), findsNothing);
    });
  });

  group('Aviso OTA no bloqueante (InutilUpdateGate)', () {
    setUp(() {
      InutilUpdateService.testReleaseOverride = null;
      // prefs en memoria: aquí es donde el aviso recuerda la versión pospuesta.
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    tearDown(() {
      InutilUpdateService.testReleaseOverride = null;
    });

    Future<void> pumpGate(WidgetTester tester, {String key = 'gate'}) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: InutilUpdateGate(
              key: ValueKey(key),
              child: const Scaffold(body: Text('APP_INTERIOR')),
            ),
          ),
        ),
      );
      // Deja resolver el checkForUpdate del gate y la animación del diálogo.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 350));
    }

    testWidgets('Con una actualización opcional la app avisa sin bloquear', (
      tester,
    ) async {
      InutilUpdateService.testReleaseOverride = manifest(
        installed: '2.5.9',
        latest: '2.5.10',
        min: '2.5.0',
      );

      await pumpGate(tester);

      // El aviso es un cartel encima de la app: el interior sigue usable.
      expect(find.text('Actualización disponible'), findsOneWidget);
      expect(
        find.text('Versión 2.5.10 disponible · Tienes v2.5.9'),
        findsOneWidget,
      );
      expect(find.text('Novedades'), findsOneWidget);
      expect(find.text('Actualizar v2.5.10'), findsOneWidget);
      expect(find.text('Más tarde'), findsOneWidget);
      expect(find.text('APP_INTERIOR'), findsOneWidget);
      expect(find.byType(InutilForceUpdateScreen), findsNothing);
    });

    testWidgets('Al posponerlo no vuelve a salir en el siguiente arranque', (
      tester,
    ) async {
      InutilUpdateService.testReleaseOverride = manifest(
        installed: '2.5.9',
        latest: '2.5.10',
        min: '2.5.0',
      );

      await pumpGate(tester);
      await tester.tap(find.text('Más tarde'));
      await tester.pumpAndSettle();
      expect(find.text('Actualización disponible'), findsNothing);

      // La versión pospuesta quedó guardada en prefs (clave del gate).
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('inutil_update_notice_snoozed_for'), '2.5.10');

      // Arranque nuevo con la misma versión publicada: ya quedó pospuesto.
      await pumpGate(tester, key: 'gate-2');
      expect(find.text('Actualización disponible'), findsNothing);
      expect(find.text('APP_INTERIOR'), findsOneWidget);
    });

    testWidgets('Una versión superior publicada reactiva el aviso', (
      tester,
    ) async {
      InutilUpdateService.testReleaseOverride = manifest(
        installed: '2.5.9',
        latest: '2.5.10',
        min: '2.5.0',
      );

      await pumpGate(tester);
      await tester.tap(find.text('Más tarde'));
      await tester.pumpAndSettle();

      // Se publica 2.5.11: el aviso vuelve aunque se haya pospuesto 2.5.10.
      InutilUpdateService.testReleaseOverride = manifest(
        installed: '2.5.9',
        latest: '2.5.11',
        min: '2.5.0',
      );
      await pumpGate(tester, key: 'gate-3');
      expect(
        find.text('Versión 2.5.11 disponible · Tienes v2.5.9'),
        findsOneWidget,
      );
    });

    testWidgets('Estando al día no se muestra ningún aviso', (tester) async {
      InutilUpdateService.testReleaseOverride = manifest(
        installed: '2.5.10',
        latest: '2.5.10',
        min: '2.5.0',
      );

      await pumpGate(tester);

      expect(find.text('Actualización disponible'), findsNothing);
      expect(find.text('APP_INTERIOR'), findsOneWidget);
      expect(find.byType(InutilForceUpdateScreen), findsNothing);
    });

    testWidgets('El kill switch manda: obligatoria sin "Más tarde"', (
      tester,
    ) async {
      InutilUpdateService.testReleaseOverride = manifest(
        installed: '2.5.9',
        latest: '2.5.10',
        min: '2.5.10',
      );

      await pumpGate(tester);

      expect(find.text('ACTUALIZACIÓN REQUERIDA'), findsOneWidget);
      expect(find.text('Más tarde'), findsNothing);
      expect(find.text('APP_INTERIOR'), findsNothing);
    });
  });
}
