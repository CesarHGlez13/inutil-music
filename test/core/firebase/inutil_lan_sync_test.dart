import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/firebase/firebase_auth_service.dart';
import 'package:inutil_music/core/firebase/firebase_playback_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = null;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await InutilAuthService.instance.initialize();
  });

  tearDown(() {
    InutilPlaybackSyncService.instance.stopSync();
  });

  group('LanDevicePeer & Auto-Pairing Tests', () {
    test('isSameAccount reconoce coincidencia exacta de correo', () {
      final peer = LanDevicePeer(
        ip: '192.168.100.24',
        port: 52445,
        deviceId: 'device_pc_123',
        deviceName: 'PC de César (Ubuntu)',
        platform: 'linux',
        userEmail: 'cesar@inutilmusic.com',
        uid: 'admin_cesar_001',
      );

      // Misma cuenta con diferente casing/espacios
      expect(
        peer.isSameAccount('cesar@inutilmusic.com', 'admin_cesar_001'),
        isTrue,
      );
      expect(peer.isSameAccount(' CESAR@INUTILMUSIC.COM ', null), isTrue);
      expect(peer.isSameAccount(null, 'admin_cesar_001'), isTrue);

      // Otra cuenta diferente
      expect(peer.isSameAccount('otro@correo.com', 'otro_uid'), isFalse);
    });

    test('isSameAccount rechaza cuentas no coincidentes', () {
      final peer = LanDevicePeer(
        ip: '192.168.100.50',
        port: 52445,
        deviceId: 'device_phone_456',
        deviceName: 'Celular Desconocido',
        platform: 'android',
        userEmail: 'invitado@gmail.com',
        uid: 'user_999',
      );

      expect(
        peer.isSameAccount('cesar@inutilmusic.com', 'admin_cesar_001'),
        isFalse,
      );
    });
  });

  group('InutilPlaybackSyncService LAN Server & Remote Control Tests', () {
    test(
      'Inicia LAN HTTP Server y responde a /api/ping con metadatos de usuario',
      () async {
        final service = InutilPlaybackSyncService.instance;
        service.startSync();

        // Dar medio segundo para que el servidor local enlace el puerto
        await Future<void>.delayed(const Duration(milliseconds: 600));

        final port = service.currentLanPort;
        expect(port, greaterThanOrEqualTo(52445));

        final client = HttpClient();
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/api/ping'),
        );
        final response = await request.close();

        expect(response.statusCode, HttpStatus.ok);
        final bodyStr = await utf8.decodeStream(response);
        final json = jsonDecode(bodyStr) as Map<String, dynamic>;

        expect(json['status'], equals('ok'));
        expect(json['port'], equals(port));
        client.close();
      },
    );

    test('Ejecuta comandos remotos via /api/command en tiempo real', () async {
      final service = InutilPlaybackSyncService.instance;
      service.startSync();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final port = service.currentLanPort;
      String receivedCommand = '';
      dynamic receivedParam;

      service.onRemoteCommandReceived = (cmd, param) async {
        receivedCommand = cmd;
        receivedParam = param;
      };

      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:$port/api/command'),
      );
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'commandType': 'playTrack',
          'param': {
            'trackId': 'test_video_123',
            'title': 'Y Que',
            'artist': 'Inspector',
            'positionMs': 1500,
          },
        }),
      );
      final response = await request.close();

      expect(response.statusCode, HttpStatus.ok);
      expect(receivedCommand, equals('playTrack'));
      expect(receivedParam, isA<Map<String, dynamic>>());
      expect(receivedParam['trackId'], equals('test_video_123'));
      expect(receivedParam['title'], equals('Y Que'));
      expect(receivedParam['positionMs'], equals(1500));

      client.close();
    });
  });
}
