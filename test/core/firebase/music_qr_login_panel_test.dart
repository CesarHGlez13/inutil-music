import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/firebase/music_qr_login_panel.dart';
import 'package:inutil_music/core/firebase/music_qr_pairing_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  tearDown(() => MusicQrLoginPanel.debugSessionFactory = null);

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: MusicQrLoginPanel())),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('muestra el QR y el código XXXX-XXXX de la sesión', (
    tester,
  ) async {
    final key = Uint8List(32);
    MusicQrLoginPanel.debugSessionFactory = () async => MusicPairingSession(
      code: 'ABCD2345',
      secretKey: key,
      qrUri: MusicQrPairingService.buildQrUri('ABCD2345', key),
      expiresAt: DateTime.now().add(const Duration(minutes: 3)),
    );
    await pump(tester);

    expect(find.text('Entrar con tu celular'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('ABCD-2345'), findsOneWidget);
  });

  testWidgets('sin conexión ofrece generar un código nuevo', (tester) async {
    MusicQrLoginPanel.debugSessionFactory = () async => null;
    await pump(tester);

    expect(find.byType(QrImageView), findsNothing);
    expect(find.byKey(const ValueKey('pc-qr-refresh')), findsOneWidget);
    expect(find.textContaining('No se pudo generar'), findsOneWidget);
  });
}
