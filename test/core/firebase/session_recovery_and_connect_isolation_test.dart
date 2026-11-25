import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inutil_music/core/firebase/firebase_auth_service.dart';
import 'package:inutil_music/core/firebase/firebase_playback_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _seedUser({
  required String uid,
  required String email,
  required String displayName,
  String role = 'user',
  String status = 'active',
  bool isActive = true,
  String? expiresAt,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'inutil_music_auth_user_v3',
    jsonEncode(<String, dynamic>{
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'role': role,
      'status': status,
      'isActive': isActive,
      'accountExpiresAt': expiresAt,
      'currentPhoneDeviceId': '',
    }),
  );
  await prefs.setString(
    'inutil_music_auth_session_v3',
    jsonEncode(<String, dynamic>{
      'uid': uid,
      'email': email,
      'idToken': 'fake-test-token',
      'refreshToken': 'fake-refresh-token',
    }),
  );
  await InutilAuthService.instance.initialize();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    InutilAuthService.testSkipOnlineValidation = true;
  });

  tearDown(() async {
    await InutilAuthService.instance.signOut();
  });

  group('Recuperación de sesión bloqueada (Bug #1)', () {
    test(
      'reconciliar un perfil activo limpia _kickedOutReason y devuelve el acceso',
      () async {
        final auth = InutilAuthService.instance;
        await _seedUser(
          uid: 'DXFmnwV8NdQecavgmVezAg7MmpD3',
          email: 'sermando91@gmail.com',
          displayName: 'Sergio',
          role: 'user',
          status: 'active',
          isActive: true,
          expiresAt: DateTime(2099, 12, 31, 6).toIso8601String(),
        );

        // Simular el bloqueo falso tras un 404 transitorio del respaldo.
        auth.testSetKickedOutReason(
          'Tu cuenta ya no existe. Contacta al administrador.',
        );
        expect(auth.isKickedOut, isTrue);
        expect(auth.isAccessAllowed, isFalse);

        // Al revalidar o pulsar «Comprobar Estado» y llegar el perfil autorizado,
        // el bloqueo debe limpiarse automáticamente sin quitar/dar permiso.
        await auth.testReconcileRemoteProfile(<String, dynamic>{
          'uid': 'DXFmnwV8NdQecavgmVezAg7MmpD3',
          'email': 'sermando91@gmail.com',
          'displayName': 'Sergio',
          'role': 'user',
          'status': 'active',
          'isActive': true,
          'accountExpiresAt': DateTime(2099, 12, 31, 6),
        });

        expect(auth.isKickedOut, isFalse);
        expect(auth.kickedOutReason, isEmpty);
        expect(auth.isAccessAllowed, isTrue);
        expect(auth.canPlay, isTrue);
      },
    );
  });

  group('Aislamiento estricto por cuenta en Inutix Connect (Bug #2)', () {
    test('isSameAccountIdentity exige coincidencia real y rechaza sin sesión', () {
      // Mismo UID -> permitido
      expect(
        LanDevicePeer.isSameAccountIdentity(
          myUid: 'uid_cesar',
          myEmail: 'cesar@example.com',
          otherUid: 'uid_cesar',
          otherEmail: 'cesar@example.com',
        ),
        isTrue,
      );

      // UID diferente -> RECHAZADO aunque compartan correo o uno esté vacío
      expect(
        LanDevicePeer.isSameAccountIdentity(
          myUid: 'uid_cesar',
          myEmail: 'cesar@example.com',
          otherUid: 'uid_sergio',
          otherEmail: 'sergio@example.com',
        ),
        isFalse,
      );
      expect(
        LanDevicePeer.isSameAccountIdentity(
          myUid: 'uid_cesar',
          myEmail: 'cesar@example.com',
          otherUid: 'uid_sergio',
          otherEmail: 'cesar@example.com',
        ),
        isFalse,
      );

      // Equipo sin sesión iniciada (local o remoto) -> NUNCA empareja
      expect(
        LanDevicePeer.isSameAccountIdentity(
          myUid: '',
          myEmail: '',
          otherUid: 'uid_cesar',
          otherEmail: 'cesar@example.com',
        ),
        isFalse,
      );
      expect(
        LanDevicePeer.isSameAccountIdentity(
          myUid: 'uid_cesar',
          myEmail: 'cesar@example.com',
          otherUid: '',
          otherEmail: '',
        ),
        isFalse,
      );
      expect(
        LanDevicePeer.isSameAccountIdentity(
          myUid: '',
          myEmail: '',
          otherUid: '',
          otherEmail: '',
        ),
        isFalse,
      );

      // Compatibilidad: sólo si falta un UID se acepta correo idéntico
      expect(
        LanDevicePeer.isSameAccountIdentity(
          myUid: 'uid_cesar',
          myEmail: 'Cesar@Example.com',
          otherUid: '',
          otherEmail: 'cesar@example.com',
        ),
        isTrue,
      );
    });

    test(
      'selectPeer y sendLanCommand ignoran dispositivos de otra cuenta',
      () async {
        await _seedUser(
          uid: 'uid_cesar',
          email: 'cesar@example.com',
          displayName: 'Cesar',
          role: 'admin',
          status: 'active',
          isActive: true,
          expiresAt: DateTime(2099, 12, 31).toIso8601String(),
        );

        final sync = InutilPlaybackSyncService.instance;
        final otherAccountPeer = LanDevicePeer(
          ip: '192.168.100.88',
          port: 52445,
          deviceId: 'other-user-pc',
          deviceName: 'PC de Otro Usuario',
          platform: 'windows',
          uid: 'uid_otra_persona',
          userEmail: 'otro@example.com',
          isHost: true,
        );

        expect(sync.isSameAccountAsPeer(otherAccountPeer), isFalse);
        sync.selectPeer(otherAccountPeer);
        expect(sync.autoPairedPeer, isNull);

        final sent = await sync.sendLanCommand(
          commandType: 'pause',
          targetPeer: otherAccountPeer,
        );
        expect(sent, isFalse);
      },
    );
  });
}
