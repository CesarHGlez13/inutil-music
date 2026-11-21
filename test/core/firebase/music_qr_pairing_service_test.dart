import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/firebase/music_qr_pairing_service.dart';

void main() {
  group('MusicQrPairingService · códigos', () {
    test('generateCode produce 8 caracteres sin ambiguos (0/O/1/I/L)', () {
      final seen = <String>{};
      for (var i = 0; i < 200; i++) {
        final code = MusicQrPairingService.generateCode();
        expect(code, matches(RegExp(r'^[A-HJKMNP-Z2-9]{8}$')));
        seen.add(code);
      }
      expect(seen.length, greaterThan(190));
    });

    test('formatDisplayCode y normalizeCode son inversos', () {
      expect(MusicQrPairingService.formatDisplayCode('ABCD2345'), 'ABCD-2345');
      expect(MusicQrPairingService.normalizeCode(' abcd-2345 '), 'ABCD2345');
    });

    test('generateSecretKey entrega 32 bytes aleatorios', () {
      final a = MusicQrPairingService.generateSecretKey();
      final b = MusicQrPairingService.generateSecretKey();
      expect(a.length, 32);
      expect(a, isNot(equals(b)));
    });

    test('deriveManualCodeKey es determinista e ignora guiones/minúsculas', () {
      final a = MusicQrPairingService.deriveManualCodeKey('ABCD-2345');
      final b = MusicQrPairingService.deriveManualCodeKey('abcd2345');
      final c = MusicQrPairingService.deriveManualCodeKey('ABCD2346');
      expect(a.length, 32);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('MusicQrPairingService · URI del QR', () {
    test('buildQrUri / parseQrUri ida y vuelta', () {
      final key = MusicQrPairingService.generateSecretKey();
      final uri = MusicQrPairingService.buildQrUri('ABCD2345', key);
      expect(uri, startsWith('inutilmusic://pair?'));
      final parsed = MusicQrPairingService.parseQrUri(uri);
      expect(parsed, isNotNull);
      expect(parsed!.code, 'ABCD2345');
      expect(parsed.secretKey, equals(key));
    });

    test('parseQrUri rechaza QR ajenos o incompletos', () {
      expect(MusicQrPairingService.parseQrUri('https://example.com'), isNull);
      expect(
        MusicQrPairingService.parseQrUri('inutilmusic://pair?c=ABCD2345'),
        isNull,
      );
      expect(
        MusicQrPairingService.parseQrUri('inutilmusic://pair?c=X&k=AAAA'),
        isNull,
      );
      expect(MusicQrPairingService.parseQrUri('basura total'), isNull);
    });
  });

  group('MusicQrPairingService · cifrado E2E', () {
    final payload = <String, dynamic>{
      'refreshToken': 'tok-123',
      'email': 'a@b.com',
      'uid': 'u1',
    };

    test('encryptPayload / decryptPayload ida y vuelta', () {
      final key = MusicQrPairingService.generateSecretKey();
      final enc = MusicQrPairingService.encryptPayload(payload, key);
      expect(enc, isNot(contains('tok-123')));
      expect(MusicQrPairingService.decryptPayload(enc, key), payload);
    });

    test('dos cifrados del mismo payload difieren (IV aleatorio)', () {
      final key = MusicQrPairingService.generateSecretKey();
      expect(
        MusicQrPairingService.encryptPayload(payload, key),
        isNot(MusicQrPairingService.encryptPayload(payload, key)),
      );
    });

    test('clave equivocada o MAC alterado devuelven null', () {
      final key = MusicQrPairingService.generateSecretKey();
      final enc = MusicQrPairingService.encryptPayload(payload, key);
      expect(
        MusicQrPairingService.decryptPayload(
          enc,
          MusicQrPairingService.generateSecretKey(),
        ),
        isNull,
      );
      final chars = enc.split('');
      final i = chars.length - 3;
      chars[i] = chars[i] == 'A' ? 'B' : 'A';
      expect(MusicQrPairingService.decryptPayload(chars.join(), key), isNull);
      expect(MusicQrPairingService.decryptPayload('nada', key), isNull);
    });

    test('la clave del código manual descifra lo cifrado con ella', () {
      final Uint8List key = MusicQrPairingService.deriveManualCodeKey(
        'ABCD2345',
      );
      final enc = MusicQrPairingService.encryptPayload(payload, key);
      expect(
        MusicQrPairingService.decryptPayload(
          enc,
          MusicQrPairingService.deriveManualCodeKey('abcd-2345'),
        ),
        payload,
      );
    });
  });
}
