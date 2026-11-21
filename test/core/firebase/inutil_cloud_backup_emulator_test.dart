import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:inutil_music/core/firebase/firebase_auth_service.dart';
import 'package:inutil_music/core/firebase/firebase_config.dart';
import 'package:inutil_music/core/firebase/firebase_firestore_service.dart';
import 'package:inutil_music/core/firebase/inutil_cloud_backup_service.dart';
import 'package:inutil_music/features/music/domain/entities/local_track.dart';
import 'package:inutil_music/features/music/domain/entities/playlist.dart';
import 'package:inutil_music/services/storage/local_database_service.dart';

/// Base de datos local apuntada a un archivo concreto (cada "dispositivo" de
/// la prueba usa el suyo, igual que una instalación nueva en un teléfono).
class _TestDatabase extends LocalDatabaseService {
  _TestDatabase(this.path);

  final String path;

  @override
  Future<String> databasePath() async => path;
}

/// E2E del respaldo en la nube contra los emuladores de Firebase
/// (Auth 9099 + Firestore 18080 con las reglas reales de `firestore.rules`):
///
/// 1. La cuenta fundadora inicia sesión y su documento nace `role: admin`.
/// 2. Un registro nuevo nace `pending`: no puede reproducir nada.
/// 3. El administrador le concede vigencia desde su API de admin.
/// 4. El usuario ya puede reproducir y empuja playlists/biblioteca/ajustes a
///    `users/{uid}/data`.
/// 5. Con base de datos y preferencias borradas (borrar datos o desinstalar),
///    la misma cuenta recupera todo desde la nube.
///
/// Corre solo con el emulador apuntado:
///   flutter test --dart-define=FB_EMULATOR=true \
///     --dart-define=FB_EMULATOR_FIRESTORE_PORT=18080 \
///     test/core/firebase/inutil_cloud_backup_emulator_test.dart
/// Inicia sesión; si la cuenta no existe en el emulador (arranca vacío en cada
/// reinicio) la crea con Firebase Auth.
Future<InutilUser> loginOrRegister(
  String email,
  String password, {
  String? displayName,
}) async {
  try {
    return await InutilAuthService.instance.signIn(
      email: email,
      password: password,
    );
  } catch (signInError) {
    try {
      return await InutilAuthService.instance.register(
        email: email,
        password: password,
        displayName: displayName,
      );
    } catch (registerError) {
      // Si el registro dice que el correo ya existe, el fallo real fue el
      // inicio de sesión (p. ej. otra prueba sembró la cuenta con otra
      // contraseña). Se propaga ese error para no enmascarar la causa.
      if (registerError.toString().contains('registrado')) {
        throw signInError;
      }
      rethrow;
    }
  }
}

void main() {
  if (!FirebaseConfig.useEmulator) {
    test(
      'respaldo en la nube (E2E con emulador)',
      skip: 'Requiere --dart-define=FB_EMULATOR=true y el emulador levantado.',
      () {},
    );
    return;
  }

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory sandbox;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // HTTP real: sin esto flutter_test intercepta HttpClient y devuelve 400.
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    sandbox = await Directory.systemTemp.createTemp('inutil_cloud_backup_');
  });

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          return switch (call.method) {
            'getTemporaryDirectory' => p.join(sandbox.path, 'temp'),
            'getApplicationSupportDirectory' => p.join(sandbox.path, 'support'),
            _ => null,
          };
        });
    SharedPreferences.setMockInitialValues({});
    await InutilAuthService.instance.signOut();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    await InutilAuthService.instance.signOut();
  });

  tearDownAll(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test(
    'registro pendiente → admin concede vigencia → respaldo y restauración total',
    () async {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      const adminEmail = 'cesar@inutilmusic.com';
      final userEmail = 'respaldo$stamp@inutil.test';
      const password = 'Passw0rd!23';

      // 1. Fundador: Firebase Auth + documento `role: admin` en Firestore.
      final admin = await loginOrRegister(adminEmail, password);
      expect(admin.idToken, isNotEmpty);
      expect(admin.isAdmin, isTrue);
      expect(InutilAuthService.instance.isAccessAllowed, isTrue);

      // 2. Registro nuevo: autenticado pero SIN vigencia concedida.
      await InutilAuthService.instance.signOut();
      final user = await InutilAuthService.instance.register(
        email: userEmail,
        password: password,
        displayName: 'Usuario Respaldo',
      );
      final uid = user.uid;
      expect(user.status, 'pending');
      expect(InutilAuthService.instance.isAccessAllowed, isFalse);
      expect(InutilAuthService.instance.canPlay, isFalse);
      expect(InutilAuthService.instance.blockedReason, contains('vigencia'));

      // 3. El administrador concede 30 días (las reglas solo dejan a admins).
      await InutilAuthService.instance.signOut();
      await loginOrRegister(adminEmail, password);
      await InutilAuthService.instance.adminGrantVigencia(
        uid: uid,
        additionalDays: 30,
      );

      // Un usuario pendiente no puede respaldar; con licencia sí.
      await InutilAuthService.instance.signOut();
      await InutilAuthService.instance.signIn(
        email: userEmail,
        password: password,
      );
      expect(InutilAuthService.instance.isAccessAllowed, isTrue);
      expect(InutilAuthService.instance.canPlay, isTrue);

      // 4. Datos locales del "teléfono": biblioteca, playlist y un ajuste.
      final phone = _TestDatabase(p.join(sandbox.path, 'library_phone.db'));
      await phone.initialize();
      final addedAt = DateTime.now();
      await phone.saveLocalTrack(
        LocalTrack(
          id: 'track_$stamp',
          title: 'Never Gonna Give You Up',
          artist: 'Rick Astley',
          filePath: '/music/rick.mp3',
          addedAt: addedAt,
          duration: const Duration(seconds: 213),
          album: 'Whenever You Need Somebody',
          artists: const ['Rick Astley'],
          sourceUrl: 'https://example.test/audio',
        ),
      );
      await phone.savePlaylist(
        Playlist(
          id: 'pl_$stamp',
          name: 'Favoritas de César',
          trackIds: ['track_$stamp'],
          createdAt: addedAt,
          updatedAt: addedAt,
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('inutil_theme_$stamp', 'neon_cyan');
      await prefs.setStringList('inutil_tags_$stamp', ['rock', 'synth']);

      final backup = InutilCloudBackupService(database: phone);
      expect(backup.canSync, isTrue);
      await backup.pushNow();
      expect(backup.lastError, isEmpty);
      expect(backup.lastPushAt, isNotNull);

      final remoteMeta = await InutilFirestoreService.instance.getDocument(
        'users/$uid/data/backup_meta',
      );
      expect(remoteMeta, isNotNull);
      final remotePlaylists = remoteMeta!['playlists'];
      expect(remotePlaylists, isA<List>());
      expect(
        (remotePlaylists as List).any(
          (raw) => (raw as Map)['name'] == 'Favoritas de César',
        ),
        isTrue,
      );
      expect(
        (remoteMeta['settings'] as Map)['inutil_theme_$stamp'],
        'neon_cyan',
      );

      // 5. Instalación nueva: base de datos y preferencias recién creadas
      // (equivale a borrar datos o desinstalar la app).
      SharedPreferences.setMockInitialValues({});
      final fresh = _TestDatabase(p.join(sandbox.path, 'library_fresh.db'));
      await fresh.initialize();
      expect(await fresh.getPlaylists(), isEmpty);
      expect(await fresh.getLocalTracks(), isEmpty);

      final restored = await InutilCloudBackupService(
        database: fresh,
      ).pullAndRestoreIfEmpty();
      expect(restored, contains('1 playlists'));
      expect(restored, contains('1 pistas'));

      final freshPlaylists = await fresh.getPlaylists();
      expect(
        freshPlaylists.any((pl) => pl.name == 'Favoritas de César'),
        isTrue,
      );
      final freshTracks = await fresh.getLocalTracks();
      expect(
        freshTracks.any(
          (t) => t.id == 'track_$stamp' && t.title == 'Never Gonna Give You Up',
        ),
        isTrue,
      );
      final freshPrefs = await SharedPreferences.getInstance();
      expect(freshPrefs.getString('inutil_theme_$stamp'), 'neon_cyan');
      expect(freshPrefs.getStringList('inutil_tags_$stamp'), ['rock', 'synth']);

      await phone.dispose();
      await fresh.dispose();
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );
}
