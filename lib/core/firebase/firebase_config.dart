/// Configuración cliente de Firebase para INÚTIL MUSIC.
///
/// Solo contiene identificadores públicos (projectId, apiKey, appId...). Ninguno
/// de estos valores es secreto: la seguridad real la imponen las reglas de
/// Firestore y el propio Firebase Auth. Aquí NO hay contraseñas ni claves de
/// servicio (Service Account), por lo que descompilar el APK no revela ninguna
/// credencial del administrador.
///
/// Valores leídos de la app ANDROID `inutil_music_android` del proyecto
/// `inutil-music-app` (`firebase apps:sdkconfig ANDROID`, 2026-11-17).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

class FirebaseConfig {
  const FirebaseConfig._();

  // Proyecto dedicado de Inútil Music (cuenta humbertoglez96@gmail.com).
  static const String projectId = String.fromEnvironment(
    'FB_PROJECT_ID',
    defaultValue: 'inutil-music-app',
  );
  static const String apiKey = String.fromEnvironment(
    'FB_API_KEY',
    defaultValue: 'AIzaSyBLg1eN_N7Djc8X1Kri5MQFS-bnS2vVv-c',
  );
  static const String messagingSenderId = '129744480084';
  static const String appId = '1:129744480084:android:ab2b7127b9ee6ef511cac1';

  /// Client ID OAuth Web (client_type 3) de `inutil-music-app` para canjear el
  /// `idToken` de Google Sign-In en Firebase Auth (`accounts:signInWithIdp`).
  static const String googleWebClientId = String.fromEnvironment(
    'FB_GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '129744480084-l2df9mg9o2i7218vt8mq3899nkta43pe.apps.googleusercontent.com',
  );

  static String get authDomain => '$projectId.firebaseapp.com';

  /// true cuando se apunta a la suite de emuladores local
  /// (`firebase emulators:start --only auth,firestore`) en lugar de la nube
  /// real. Permite validar el flujo de cuentas sin tocar producción:
  ///   flutter run -d linux --dart-define=FB_EMULATOR=true
  static const bool useEmulator = bool.fromEnvironment(
    'FB_EMULATOR',
    defaultValue: false,
  );
  static const String emulatorHost = String.fromEnvironment(
    'FB_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );

  /// Puertos de la suite local. El de Firestore se puede mover cuando 8080 ya
  /// está ocupado en la máquina (p. ej. 18080, como en `firebase.json`).
  static const String emulatorAuthPort = String.fromEnvironment(
    'FB_EMULATOR_AUTH_PORT',
    defaultValue: '9099',
  );
  static const String emulatorFirestorePort = String.fromEnvironment(
    'FB_EMULATOR_FIRESTORE_PORT',
    defaultValue: '8080',
  );

  static String get storageBucket => String.fromEnvironment(
    'FB_STORAGE_BUCKET',
    defaultValue: '$projectId.firebasestorage.app',
  );

  /// Host del relay propio (el S7 Edge, `relay.py`). Vacío = Firebase real.
  /// Redirige Firestore Y Storage (las lecturas son lo que gasta cuota y el
  /// relay las sirve desde su caché); el Auth sigue en Firebase real
  /// (decisión del plan: auth en Firebase, lecturas en el servidor propio).
  static const String relayHost = String.fromEnvironment(
    'FB_RELAY_HOST',
    defaultValue: '',
  );
  static const String relayPort = String.fromEnvironment(
    'FB_RELAY_PORT',
    defaultValue: '8080',
  );

  // ---------------------------------------------------------------------------
  // Fallback de alcance del relay (decidido por Cesar el 2026-11-20)
  // ---------------------------------------------------------------------------

  /// Estado de alcance del relay: `null` = todavía sin medir, `true` = vivo,
  /// `false` = no respondió a la sonda. Arranca `null` para que un build
  /// horneado con `FB_RELAY_HOST` no pierda el ahorro de cuota en casa: en
  /// cuanto la sonda lo encuentra, [firestoreBaseUrl] y [storageBaseUrl]
  /// empiezan a usarlo. Si nunca responde (usuario fuera de la LAN del S7),
  /// se queda con Google y la app funciona igual que antes del relay.
  static bool? _relayReachable;

  /// `true` sólo cuando hay relay horneado, no estamos en emuladores y la sonda
  /// lo declaró vivo. Es la única puerta de los endpoints redirigidos.
  static bool get relayUsable =>
      relayHost.trim().isNotEmpty && !useEmulator && _relayReachable == true;

  /// Decisión pura de endpoint, expuesta para pruebas: el relay se usa sólo si
  /// está configurado, fuera de emuladores y alcanzable; de lo contrario se
  /// devuelve tal cual el endpoint de Google (o del emulador) que le pase el
  /// llamante.
  @visibleForTesting
  static String relayAwareUrl({
    required String configuredHost,
    required String configuredPort,
    required bool emulator,
    required bool? reachable,
    required String emulatorUrl,
    required String googleUrl,
  }) {
    if (configuredHost.trim().isEmpty) return googleUrl;
    if (emulator) return emulatorUrl;
    if (reachable != true) return googleUrl;
    return 'http://$configuredHost:$configuredPort'
        '${Uri.parse(googleUrl).path}';
  }

  /// Cache en SharedPreferences del último estado medido, para que un arranque
  /// no arranque de cero: `true` = lo vimos vivo alguna vez desde este equipo,
  /// `false` = nunca respondió (el usuario no está en la LAN del S7). Lo lee
  /// `_probeRelayReachabilityAndCache` en `main.dart`.
  static const String relayReachabilityCacheKey = 'inutil_relay_reachable_v1';

  /// Sonda de TCP al relay. Devuelve el estado medido y lo deja en el estado
  /// de clase para que los getters lo respeten de inmediato.
  ///
  /// Prueba los puertos `relayPort` y `5555` en paralelo (el segundo es el
  /// puerto TCP del ADB shell del S7, por si el `relay.py` quedó levantado
  /// sobre otro número) y abandona al primer handshake.
  ///
  /// Costo medido en la LAN: ~1 ms cuando el relay vive. Para un usuario
  /// fuera de la LAN son `timeout` segundos de espera en el arranque, y a
  /// cambio la app nunca le falla una lectura.
  static Future<bool> probeRelayReachability({
    Duration timeout = const Duration(milliseconds: 1200),
    List<int>? ports,
    String? host,
  }) async {
    final target = (host ?? relayHost).trim();
    if (useEmulator || target.isEmpty) {
      _relayReachable = false;
      return false;
    }
    final candidates = <int>{
      int.tryParse(relayPort.trim()) ?? 8080,
      5555,
    }.toList(growable: false);
    for (final port in ports ?? candidates) {
      if (await _canOpen(target, port, timeout)) {
        _relayReachable = true;
        return true;
      }
    }
    _relayReachable = false;
    return false;
  }

  static Future<bool> _canOpen(
    String host,
    int port,
    Duration timeout,
  ) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  /// Lo que debe llamar cualquier servicio que reciba un `SocketException`,
  /// `TimeoutException` o `Connection refused` del relay: marca el relay como
  /// caído y a partir de la siguiente petición los endpoints vuelven a Google,
  /// sin reiniciar la app.
  static void markRelayUnreachable() {
    if (_relayReachable == false) return;
    _relayReachable = false;
  }

  /// Restablece la medición (pruebas y re-sondas programadas).
  @visibleForTesting
  static void resetRelayReachability() => _relayReachable = null;

  /// Estado actual conocido, para telemetría y pruebas.
  @visibleForTesting
  static bool? get relayReachabilityState => _relayReachable;

  // Endpoints REST oficiales de Google Cloud / Firebase
  static String get authBaseUrl => useEmulator
      ? 'http://$emulatorHost:$emulatorAuthPort/identitytoolkit.googleapis.com/v1'
      : 'https://identitytoolkit.googleapis.com/v1';

  /// Intercambio de refreshToken por idToken (Secure Token Manager).
  static String get secureTokenUrl => useEmulator
      ? 'http://$emulatorHost:$emulatorAuthPort/securetoken.googleapis.com/v1/token'
      : 'https://securetoken.googleapis.com/v1/token';

  static String get firestoreBaseUrl {
    if (relayUsable) {
      return 'http://$relayHost:$relayPort/v1/projects/$projectId/databases/(default)/documents';
    }
    return useEmulator
        ? 'http://$emulatorHost:$emulatorFirestorePort/v1/projects/$projectId/databases/(default)/documents'
        : 'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';
  }

  static String get storageBaseUrl => relayUsable
      ? 'http://$relayHost:$relayPort/v0/b/$storageBucket/o'
      : 'https://firebasestorage.googleapis.com/v0/b/$storageBucket/o';

  /// El emulador de Auth ignora la clave, pero el endpoint exige el parámetro.
  static String get keyParam => useEmulator ? 'key=emulator' : 'key=$apiKey';
}
