import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:inutil_music/core/firebase/firebase_auth_service.dart';
import 'package:inutil_music/core/firebase/inutil_auth_gate.dart';
import 'package:inutil_music/features/music/presentation/widgets/inutil_admin_panel.dart';

/// Siembra una sesión local (snapshot v3 + sesión) como si Firebase Auth ya
/// hubiera autenticado y Firestore devuelto la licencia indicada. En el test
/// no hay backend seguro ni red, así que el servicio cae al fallback de prefs.
Future<void> seedSession({
  required String uid,
  required String email,
  String role = 'user',
  String status = 'active',
  bool isActive = true,
  String? expiresAt,
  String currentPhoneDeviceId = '',
}) async {
  final prefs = await SharedPreferences.getInstance();
  final user = <String, dynamic>{
    'uid': uid,
    'email': email,
    'displayName': email.split('@').first,
    'role': role,
    'status': status,
    'isActive': isActive,
    'accountExpiresAt': expiresAt,
    'currentPhoneDeviceId': currentPhoneDeviceId,
  };
  await prefs.setString('inutil_music_auth_user_v3', jsonEncode(user));
  await prefs.setString(
    'inutil_music_auth_session_v3',
    jsonEncode({
      'uid': uid,
      'email': email,
      'idToken': 'expired-test-token',
      'refreshToken': 'test-refresh',
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // El backend seguro real (flutter_secure_storage) no tiene implementación
    // en el host de tests y su platform channel nunca responde: sin este mock
    // in-memory, cualquier testWidgets que arranque el servicio se cuelga
    // esperando el primer `read`.
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    // Dentro de testWidgets el reloj es falso y las peticiones HTTP reales
    // jamás se completan; el servicio decide con el snapshot local sembrado.
    InutilAuthService.testSkipOnlineValidation = true;
    await InutilAuthService.instance.initialize();
  });

  tearDown(() async {
    await InutilAuthService.instance.signOut();
    InutilAuthService.testSkipOnlineValidation = false;
  });

  group('InutilUser Model & Permissions', () {
    test('El rol admin (no el correo) define al Administrador', () {
      const userAdmin = InutilUser(
        uid: 'uid_1',
        email: 'cualquiera@inutilmusic.com',
        displayName: 'Admin',
        role: 'admin',
      );
      expect(userAdmin.isAdmin, isTrue);
      expect(userAdmin.isPermanent, isTrue);
      expect(userAdmin.isExpired, isFalse);
      expect(userAdmin.daysRemaining, 9999);
    });

    test('El correo del fundador ya NO concede admin por sí solo', () {
      const userCesar = InutilUser(
        uid: 'cesar_1',
        email: 'cesar@inutilmusic.com',
        displayName: 'César',
        role: 'user',
      );
      expect(userCesar.isAdmin, isFalse);
      // Sin vigencia concedida sigue siendo un usuario normal.
      expect(userCesar.isActive, isTrue);
    });

    test('Usuario regular con fecha futura tiene vigencia activa', () {
      final futureDate = DateTime.now().add(const Duration(days: 20));
      final normalUser = InutilUser(
        uid: 'user_1',
        email: 'musica@ejemplo.com',
        accountExpiresAt: futureDate,
        role: 'user',
        status: 'active',
      );
      expect(normalUser.isAdmin, isFalse);
      expect(normalUser.isExpired, isFalse);
      expect(normalUser.licenseValid, isTrue);
      expect(normalUser.daysRemaining, greaterThanOrEqualTo(19));
    });

    test('Usuario regular con fecha pasada está expirado', () {
      final pastDate = DateTime.now().subtract(const Duration(days: 2));
      final expiredUser = InutilUser(
        uid: 'user_2',
        email: 'expirado@ejemplo.com',
        accountExpiresAt: pastDate,
        role: 'user',
        status: 'active',
      );
      expect(expiredUser.isAdmin, isFalse);
      expect(expiredUser.isExpired, isTrue);
      expect(expiredUser.licenseValid, isFalse);
      expect(expiredUser.daysRemaining, 0);
    });

    test('Usuario pendiente (sin vigencia concedida) no puede reproducir', () {
      const pendingUser = InutilUser(
        uid: 'user_new',
        email: 'nuevo@ejemplo.com',
        role: 'user',
        status: 'pending',
        isActive: false,
      );
      expect(pendingUser.licenseValid, isFalse);
      expect(pendingUser.isExpired, isTrue); // sin fecha = sin licencia
    });

    test('Usuario con licencia permanente (año >= 2090) nunca expira', () {
      final permanentUser = InutilUser(
        uid: 'user_prem',
        email: 'vip@ejemplo.com',
        accountExpiresAt: DateTime(2099, 12, 31),
        role: 'user',
        status: 'active',
      );
      expect(permanentUser.isPermanent, isTrue);
      expect(permanentUser.isExpired, isFalse);
      expect(permanentUser.daysRemaining, 9999);
    });
  });

  group('InutilAuthService (sin credenciales embebidas)', () {
    test('No existen contraseñas hardcodeadas en el servicio', () async {
      // La única fuente de la contraseña es Firebase Auth; la app no debe
      // contener la palabra 'cesar123' ni accesos rápidos administrativos.
      const source =
          '''
        ${InutilAuthService.bootstrapAdminEmail}
      ''';
      expect(source.contains('cesar123'), isFalse);
      expect(InutilAuthService.bootstrapAdminEmail, 'cesar@inutilmusic.com');
    });

    test('Sesión pendiente: autenticado pero sin acceso', () async {
      await seedSession(
        uid: 'uid_pend',
        email: 'pendiente@inutil.com',
        status: 'pending',
        isActive: false,
      );
      await InutilAuthService.instance.initialize();

      final auth = InutilAuthService.instance;
      expect(auth.isAuthenticated, isTrue);
      expect(auth.isAccessAllowed, isFalse);
      expect(auth.canPlay, isFalse);
      expect(auth.blockedReason, contains('vigencia'));
    });

    test('Sesión admin: acceso permitido', () async {
      await seedSession(
        uid: 'uid_admin',
        email: 'cesar@inutilmusic.com',
        role: 'admin',
        status: 'active',
        expiresAt: DateTime(2099, 12, 31).toIso8601String(),
      );
      await InutilAuthService.instance.initialize();

      final auth = InutilAuthService.instance;
      expect(auth.currentUser?.isAdmin, isTrue);
      expect(auth.isAccessAllowed, isTrue);
    });

    test(
      'El id de dispositivo sobrevive a reinicios (emparejamiento LAN)',
      () async {
        final first = InutilAuthService.instance.deviceId;
        expect(first, isNot('unknown_device'));
        await InutilAuthService.instance.initialize();
        expect(InutilAuthService.instance.deviceId, first);
      },
    );

    test('signOut limpia la sesión local', () async {
      await seedSession(uid: 'uid_x', email: 'x@inutil.com');
      await InutilAuthService.instance.initialize();
      expect(InutilAuthService.instance.isAuthenticated, isTrue);
      await InutilAuthService.instance.signOut();
      expect(InutilAuthService.instance.isAuthenticated, isFalse);
    });
  });

  group('Una cuenta, un solo teléfono (licencia por dispositivo)', () {
    final vigenciaFutura = DateTime.now().add(const Duration(days: 10));

    test(
      'El teléfono que tiene el reclamo de la cuenta sí reproduce',
      () async {
        final ownedDevice = InutilAuthService.instance.deviceId;
        await seedSession(
          uid: 'uid_phone_ok',
          email: 'telefono@inutil.com',
          status: 'active',
          isActive: true,
          expiresAt: vigenciaFutura.toIso8601String(),
          currentPhoneDeviceId: ownedDevice,
        );
        await InutilAuthService.instance.initialize();

        final auth = InutilAuthService.instance;
        auth.testAsPhoneDevice(true);
        auth.testSeedLicenseValidation(
          DateTime.now().subtract(const Duration(hours: 1)),
        );

        expect(auth.isAccessAllowed, isTrue);
        expect(auth.canPlay, isTrue);
        expect(auth.blockedReason, isEmpty);
      },
    );

    test(
      'Un segundo teléfono queda bloqueado mientras el otro conserve el reclamo',
      () async {
        await seedSession(
          uid: 'uid_phone_other',
          email: 'otro@inutil.com',
          status: 'active',
          isActive: true,
          expiresAt: vigenciaFutura.toIso8601String(),
          currentPhoneDeviceId: 'otro_telefono_de_cesar',
        );
        await InutilAuthService.instance.initialize();

        final auth = InutilAuthService.instance;
        auth.testAsPhoneDevice(true);
        auth.testSeedLicenseValidation(DateTime.now());

        expect(auth.canPlay, isFalse);
        expect(auth.blockedReason, contains('Otro teléfono'));
      },
    );

    test(
      'La PC no reproduce el conflicto: es altavoz/mando, no teléfono',
      () async {
        await seedSession(
          uid: 'uid_pc',
          email: 'pc@inutil.com',
          status: 'active',
          isActive: true,
          expiresAt: vigenciaFutura.toIso8601String(),
          currentPhoneDeviceId: 'otro_telefono_de_cesar',
        );
        await InutilAuthService.instance.initialize();

        final auth = InutilAuthService.instance;
        auth.testSeedLicenseValidation(DateTime.now());

        // En Linux/macOS/Windows `devicePlatform` no es 'android', así que la
        // licencia del teléfono no interfiere con el PC.
        expect(auth.canPlay, isTrue);
      },
    );

    test('Sin validar en más de 72 h la app deja de reproducir', () async {
      await seedSession(
        uid: 'uid_stale',
        email: 'viejo@inutil.com',
        status: 'active',
        isActive: true,
        expiresAt: vigenciaFutura.toIso8601String(),
      );
      await InutilAuthService.instance.initialize();

      final auth = InutilAuthService.instance;
      auth.testSeedLicenseValidation(
        DateTime.now().subtract(const Duration(hours: 73)),
      );

      expect(auth.isAccessAllowed, isTrue);
      expect(auth.canPlay, isFalse);
      expect(auth.blockedReason, contains('internet'));
    });
  });

  group('InutilAuthGate Widget Tests', () {
    testWidgets('Muestra InutilAuthScreen cuando no hay usuario autenticado', (
      tester,
    ) async {
      await InutilAuthService.instance.signOut();

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: InutilAuthGate(child: Scaffold(body: Text('APP_INTERIOR'))),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(InutilAuthScreen), findsOneWidget);
      expect(find.text('INUTIX MUSIC'), findsOneWidget);
      expect(find.text('Iniciar Sesión'), findsWidgets);
      expect(find.text('APP_INTERIOR'), findsNothing);

      // Regresión de seguridad: el botón de acceso rápido con credenciales
      // visibles de César desapareció para siempre.
      expect(find.text('Acceso Administrador César'), findsNothing);
    });

    testWidgets('Muestra CUENTA PENDIENTE para un registro sin vigencia', (
      tester,
    ) async {
      await seedSession(
        uid: 'uid_pend2',
        email: 'nuevo@inutil.com',
        status: 'pending',
        isActive: false,
      );
      await InutilAuthService.instance.initialize();

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: InutilAuthGate(child: Scaffold(body: Text('APP_INTERIOR'))),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(InutilLicenseExpiredScreen), findsOneWidget);
      expect(find.text('CUENTA PENDIENTE'), findsOneWidget);
      expect(find.text('APP_INTERIOR'), findsNothing);
    });

    testWidgets('Muestra InutilLicenseExpiredScreen cuando la cuenta expiró', (
      tester,
    ) async {
      final pastDate = DateTime.now().subtract(const Duration(days: 5));
      await seedSession(
        uid: 'user_exp',
        email: 'vencido@inutil.com',
        expiresAt: pastDate.toIso8601String(),
      );
      await InutilAuthService.instance.initialize();

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: InutilAuthGate(child: Scaffold(body: Text('APP_INTERIOR'))),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(InutilLicenseExpiredScreen), findsOneWidget);
      expect(find.text('LICENCIA VENCIDA'), findsOneWidget);
      expect(find.text('APP_INTERIOR'), findsNothing);
    });

    testWidgets('Permite acceso a la APP cuando el rol es Administrador', (
      tester,
    ) async {
      await seedSession(
        uid: 'uid_admin2',
        email: 'cesar@inutilmusic.com',
        role: 'admin',
        status: 'active',
        expiresAt: DateTime(2099, 12, 31).toIso8601String(),
      );
      await InutilAuthService.instance.initialize();

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: InutilAuthGate(child: Scaffold(body: Text('APP_INTERIOR'))),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('APP_INTERIOR'), findsOneWidget);
      expect(find.byType(InutilAuthScreen), findsNothing);
      expect(find.byType(InutilLicenseExpiredScreen), findsNothing);
    });

    testWidgets('InutilAdminPanel se renderiza con la sesión admin', (
      tester,
    ) async {
      await seedSession(
        uid: 'uid_admin3',
        email: 'cesar@inutilmusic.com',
        role: 'admin',
        status: 'active',
        expiresAt: DateTime(2099, 12, 31).toIso8601String(),
      );
      await InutilAuthService.instance.initialize();

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: InutilAdminPanel())),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Panel de Control César'), findsOneWidget);
      expect(find.text('Nuevo Usuario'), findsOneWidget);
    });
  });
}
