import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/startup/inutil_settings_hydration_gate.dart';
import 'package:inutil_music/features/music/presentation/providers/app_strings.dart';
import 'package:inutil_music/features/music/presentation/providers/music_providers.dart';

const _state = SettingsState(
  downloadDirectory: '/tmp/musica',
  language: AppLanguage.spanish,
);

/// Controlador que queda en `AsyncLoading` hasta que el test lo suelta.
class _PendingSettingsController extends SettingsController {
  static Completer<SettingsState>? release;

  @override
  Future<SettingsState> build() async {
    final completer = Completer<SettingsState>();
    release = completer;
    return completer.future;
  }
}

/// Controlador que falla: las pruebas de hidratación deben tratar un error de
/// preferencias como "ya no hay nada que esperar", no como un loading eterno.
class _FailingSettingsController extends SettingsController {
  @override
  Future<SettingsState> build() async => throw StateError('prefs ilegibles');
}

Widget _app({required Widget child, Duration? ceiling}) {
  return MaterialApp(
    home: InutilSettingsHydrationGate(
      ceiling: ceiling ?? const Duration(milliseconds: 1200),
      child: child,
    ),
  );
}

void main() {
  tearDown(() {
    _PendingSettingsController.release = null;
  });

  testWidgets('pinta el esqueleto y luego el shell, sin frame intermedio', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _PendingSettingsController(),
          ),
        ],
        child: _app(child: const Text('SHELL')),
      ),
    );

    expect(
      find.byKey(const ValueKey('settings-hydration-skeleton')),
      findsOneWidget,
    );
    expect(find.text('SHELL'), findsNothing);

    _PendingSettingsController.release!.complete(_state);
    await tester.pump();

    expect(find.text('SHELL'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-hydration-skeleton')),
      findsNothing,
    );
  });

  testWidgets('un fallo de preferencias también deja pintar el shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _FailingSettingsController(),
          ),
        ],
        child: _app(child: const Text('SHELL')),
      ),
    );
    await tester.pump();

    expect(find.text('SHELL'), findsOneWidget);
  });

  testWidgets('el techo evita una pantalla de carga infinita', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _PendingSettingsController(),
          ),
        ],
        child: _app(
          child: const Text('SHELL'),
          ceiling: const Duration(milliseconds: 300),
        ),
      ),
    );

    expect(find.text('SHELL'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('SHELL'), findsOneWidget);
  });
}
