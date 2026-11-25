import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import 'firebase_config.dart';
import 'firebase_firestore_service.dart';

/// Modelo de usuario autenticado en INUTIX MUSIC.
///
/// Las credenciales (idToken/refreshToken) provienen exclusivamente de
/// Firebase Auth; esta clase solo refleja la identidad y la LICENCIA que el
/// administrador concede desde su panel.
@immutable
class InutilUser {
  const InutilUser({
    required this.uid,
    required this.email,
    this.displayName = '',
    this.idToken = '',
    this.refreshToken = '',
    this.accountExpiresAt,
    this.isActive = true,
    this.role = 'user',
    this.accountDurationDays = 30,
    this.createdAt,
    this.lastLoginAt,
    this.status = 'pending',
    this.currentPhoneDeviceId = '',
    this.phoneSwitchCount = 0,
    this.phoneSwitchMonth = '',
  });

  final String uid;
  final String email;
  final String displayName;
  final String idToken;
  final String refreshToken;
  final DateTime? accountExpiresAt;
  final bool isActive;
  final String role;
  final int accountDurationDays;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  /// Estado de licencia gestionado por el administrador:
  /// `pending` (registrado, sin vigencia) | `active` | `blocked`.
  final String status;

  /// Teléfono autorizado para reproducir (bloqueo de un solo teléfono).
  final String currentPhoneDeviceId;

  /// Cambios de teléfono realizados en el mes en curso (límite mensual).
  final int phoneSwitchCount;
  final String phoneSwitchMonth;

  /// Administrador solo por rol (Firebase Auth/Firestore). Ya no se decide
  /// por UID ni por correo hardcodeados: conocer el correo no es un secreto.
  bool get isAdmin => role == 'admin';

  /// Licencia Premium Permanente (año 2090 en adelante o rol admin)
  bool get isPermanent =>
      isAdmin || (accountExpiresAt != null && accountExpiresAt!.year >= 2090);

  /// Estado de expiración: Administradores y Licencias Permanentes nunca expiran
  bool get isExpired {
    if (isAdmin || isPermanent) return false;
    if (accountExpiresAt == null) return true;
    return DateTime.now().isAfter(accountExpiresAt!);
  }

  /// Días restantes de vigencia
  int get daysRemaining {
    if (isAdmin || isPermanent) return 9999;
    if (accountExpiresAt == null) return 0;
    final diff = accountExpiresAt!.difference(DateTime.now()).inDays;
    return diff > 0 ? diff : 0;
  }

  /// La cuenta está vigente para reproducir (independiente del dispositivo).
  bool get licenseValid {
    if (isAdmin) return true;
    return isActive && status == 'active' && !isExpired;
  }

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'email': email,
    'displayName': displayName,
    'idToken': idToken,
    'refreshToken': refreshToken,
    'accountExpiresAt': accountExpiresAt?.toIso8601String(),
    'isActive': isActive,
    'role': role,
    'accountDurationDays': accountDurationDays,
    'createdAt': createdAt?.toIso8601String(),
    'lastLoginAt': lastLoginAt?.toIso8601String(),
    'status': status,
    'currentPhoneDeviceId': currentPhoneDeviceId,
    'phoneSwitchCount': phoneSwitchCount,
    'phoneSwitchMonth': phoneSwitchMonth,
  };

  factory InutilUser.fromJson(Map<String, dynamic> json) {
    return InutilUser(
      uid: json['uid'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      idToken: json['idToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
      accountExpiresAt: json['accountExpiresAt'] != null
          ? DateTime.tryParse(json['accountExpiresAt'] as String)
          : null,
      isActive: json['isActive'] as bool? ?? true,
      role: json['role'] as String? ?? 'user',
      accountDurationDays: json['accountDurationDays'] as int? ?? 30,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      lastLoginAt: json['lastLoginAt'] != null
          ? DateTime.tryParse(json['lastLoginAt'] as String)
          : null,
      status: json['status'] as String? ?? 'pending',
      currentPhoneDeviceId: json['currentPhoneDeviceId'] as String? ?? '',
      phoneSwitchCount: (json['phoneSwitchCount'] as num?)?.toInt() ?? 0,
      phoneSwitchMonth: json['phoneSwitchMonth'] as String? ?? '',
    );
  }

  InutilUser copyWith({
    String? displayName,
    String? idToken,
    String? refreshToken,
    DateTime? accountExpiresAt,
    bool? isActive,
    String? role,
    int? accountDurationDays,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    String? status,
    String? currentPhoneDeviceId,
    int? phoneSwitchCount,
    String? phoneSwitchMonth,
  }) {
    return InutilUser(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      idToken: idToken ?? this.idToken,
      refreshToken: refreshToken ?? this.refreshToken,
      accountExpiresAt: accountExpiresAt ?? this.accountExpiresAt,
      isActive: isActive ?? this.isActive,
      role: role ?? this.role,
      accountDurationDays: accountDurationDays ?? this.accountDurationDays,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      status: status ?? this.status,
      currentPhoneDeviceId: currentPhoneDeviceId ?? this.currentPhoneDeviceId,
      phoneSwitchCount: phoneSwitchCount ?? this.phoneSwitchCount,
      phoneSwitchMonth: phoneSwitchMonth ?? this.phoneSwitchMonth,
    );
  }
}

/// Servicio integral de autenticación y gestión de usuarios para INUTIX MUSIC.
///
/// Autenticación REAL contra Firebase Auth (Identity Toolkit REST v1):
///   * El único lugar donde existe la contraseña es Firebase; la app nunca la
///     guarda en claro ni la compara localmente.
///   * Los tokens (idToken/refreshToken) se guardan en almacenamiento seguro
///     (flutter_secure_storage; fallback a prefs solo si el backend seguro no
///     está disponible, p. ej. Linux sin libsecret).
///   * La licencia (vigencia/estado/rol) vive en Firestore `users/{uid}` y la
///     controla el administrador. Sin documento vigente no se reproduce nada.
class InutilAuthService extends ChangeNotifier {
  InutilAuthService._();
  static final InutilAuthService instance = InutilAuthService._();

  static const _storageUserKey = 'inutil_music_auth_user_v3';
  // IMPORTANTE: la clave del id de dispositivo NO cambia (v2): el emparejamiento
  // LAN de PC↔celular identifica a los clientes con este valor.
  static const _storageDeviceIdKey = 'inutil_music_device_id_v2';
  static const _storageSessionKey = 'inutil_music_auth_session_v3';
  static const _storageUsersCacheKey = 'inutil_music_users_cache_v3';
  static const _storageLegacyUserKey = 'inutil_music_auth_user_v2';
  static const _storageRegistryKey = 'inutil_music_users_registry_v2';

  /// Correos del administrador fundador. NO son credenciales: Firebase Auth o
  /// Google Sign-In siguen exigiendo la autenticación real; estos valores solo
  /// deciden qué documento `users/{uid}` puede crearse o elevarse a `role: 'admin'`
  /// (lo validan además las reglas de Firestore).
  static const String bootstrapAdminEmail = 'cesar@inutilmusic.com';
  static const Set<String> bootstrapAdminEmails = {
    'cesar@inutilmusic.com',
    'humbertoglez96@gmail.com',
    'cesarmaster133@gmail.com',
  };

  static bool isBootstrapAdminEmail(String email) =>
      bootstrapAdminEmails.contains(email.trim().toLowerCase());

  /// Ventana de gracia sin validación en línea (72 h acordadas).
  static const Duration offlineGrace = Duration(hours: 72);

  /// Cambios de teléfono permitidos por mes natural.
  static const int maxMonthlyPhoneSwitches = 3;

  static const Duration _validateInterval = Duration(minutes: 15);

  /// Política de inactividad por defecto (se puede cambiar desde el portal
  /// admin en `app_config/inactivity_policy`): las cuentas gratuitas que no
  /// abren la app durante este número de días quedan en pausa automática.
  static const int defaultInactivityDays = 15;
  static const int _minInactivityDays = 2;
  static const int _maxInactivityDays = 365;

  /// Frecuencia máxima con la que se escribe `lastActiveAt` en Firestore.
  static const Duration _heartbeatThrottle = Duration(hours: 1);

  /// Decide si una cuenta debe quedar en pausa por inactividad.
  ///
  /// Devuelve los días transcurridos sin actividad cuando corresponde pausar,
  /// o `null` si la cuenta sigue vigente. Las cuentas sin `lastActiveAt`
  /// (anteriores a la v2.4.0) se consideran activas para no castigar a nadie
  /// durante la migración.
  static int? inactivityPauseDays({
    required DateTime? lastActiveAt,
    required bool exempt,
    required bool enabled,
    required int thresholdDays,
    required DateTime now,
  }) {
    if (!enabled || exempt || lastActiveAt == null) return null;
    final days = now.difference(lastActiveAt).inDays;
    return days >= thresholdDays ? days : null;
  }

  /// Tiempo máximo de espera al backend seguro antes de rendirse y usar prefs.
  /// En Linux sin anillo de claves (libsecret/D-Bus) el channel del plugin
  /// puede quedarse colgado indefinidamente, y en los widget tests simplemente
  /// nunca responde; el arranque de la app jamás debe bloquearse por eso, así
  /// que toda operación segura se corta por tiempo y cae al espejo en prefs.
  static const Duration _secureTimeout = Duration(seconds: 3);

  /// Hook de pruebas de widget: anula toda validación en línea (Secure Token
  /// Manager, Firestore `users/{uid}` y listado del panel). Dentro de
  /// `testWidgets` el reloj es falso y las peticiones HTTP reales nunca se
  /// completan, así que los tests de UI dejan de preguntar a la red y deciden
  /// con el snapshot local. En producción siempre es `false`.
  @visibleForTesting
  static bool testSkipOnlineValidation = false;

  /// Hook de pruebas de unidad: finge que este dispositivo es un teléfono
  /// Android, el único caso donde aplica la regla de "una cuenta, un teléfono"
  /// (en PC la app actúa como altavoz/mando y nunca reclama la licencia).
  @visibleForTesting
  void testAsPhoneDevice(bool value) {
    _devicePlatform = value ? 'android' : 'linux';
  }

  /// Hook de pruebas de unidad: registra que la licencia se validó contra la
  /// nube en [validatedAt], sin necesidad de tocar Firestore.
  @visibleForTesting
  void testSeedLicenseValidation(DateTime validatedAt) {
    _lastValidatedAt = validatedAt;
  }

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: true,
      migrateOnAlgorithmChange: true,
    ),
    wOptions: WindowsOptions(useBackwardCompatibility: false),
  );

  InutilUser? _currentUser;
  String? _deviceId;
  String? _deviceName;
  String? _devicePlatform;
  Timer? _validateTimer;
  bool _validating = false;

  /// Motivo por el cual esta sesión fue expulsada (otro teléfono tomó el
  /// control, cuenta bloqueada, etc.). Vacío si la sesión está vigente.
  String _kickedOutReason = '';

  bool _inactivityPaused = false;
  int _inactiveDays = 0;
  bool _inactivityPolicyEnabled = true;
  int _inactivityPolicyDays = defaultInactivityDays;
  DateTime? _lastHeartbeatAt;

  /// true si la cuenta gratuita quedó en pausa automática por inactividad.
  bool get isInactivityPaused => _inactivityPaused;

  /// Días sin actividad detectados al pausar la cuenta.
  int get inactiveDays => _inactiveDays;

  /// Límite vigente de días sin uso antes de la pausa automática.
  int get inactivityPolicyDays => _inactivityPolicyDays;
  bool get inactivityPolicyEnabled => _inactivityPolicyEnabled;

  InutilUser? get currentUser => _currentUser;

  /// Indica si hay una sesión iniciada
  bool get isAuthenticated => _currentUser != null;

  /// true si esta sesión fue expulsada por validez/licencia; la UI muestra el
  /// motivo y exige reconectarse.
  bool get isKickedOut => _kickedOutReason.isNotEmpty;
  String get kickedOutReason => _kickedOutReason;

  /// Control estricto de acceso (Gatekeeper):
  /// sesión válida + (admin O licencia vigente) + sesión de teléfono propia.
  bool get isAccessAllowed =>
      _currentUser != null &&
      _kickedOutReason.isEmpty &&
      !_inactivityPaused &&
      (_currentUser!.isAdmin ||
          (_currentUser!.isActive && !_currentUser!.isExpired));

  /// true solo si ADEMÁS la validación remota está fresca (dentro de la
  /// ventana de gracia). Es el interruptor real de la reproducción.
  bool get canPlay => _currentUser != null && _licenseFresh();

  /// Explicación legible del bloqueo actual para banners y diálogos.
  String get blockedReason {
    final user = _currentUser;
    if (user == null) return 'Inicia sesión para reproducir.';
    if (_kickedOutReason.isNotEmpty) return _kickedOutReason;
    if (!user.isAdmin && user.status == 'pending') {
      return 'Tu cuenta está registrada pero sin vigencia. El administrador debe aprobarla.';
    }
    if (!user.isActive || user.status == 'blocked') {
      return 'Tu cuenta fue suspendida por el administrador.';
    }
    if (user.isExpired) {
      return 'Tu vigencia terminó. Solicita al administrador una renovación.';
    }
    if (_inactivityPaused) {
      return 'Tu acceso gratuito está en pausa: no usaste la app durante '
          '$_inactiveDays días (el límite es $_inactivityPolicyDays).';
    }
    if (!_phoneSessionOk(user)) {
      return 'Otro teléfono tomó el control de esta cuenta. En este teléfono '
          'no se puede reproducir hasta que liberes el dispositivo desde tu '
          'otra sesión o desde el panel del administrador.';
    }
    if (!_licenseFresh()) {
      return 'Necesitas conectarte a internet para validar tu licencia '
          '(la última validación fue hace más de 72 horas).';
    }
    return '';
  }

  String get deviceId => _deviceId ?? 'unknown_device';
  String get deviceName => _deviceName ?? 'Inútil Client';
  String get devicePlatform => _devicePlatform ?? 'generic';

  /// true cuando este dispositivo es un teléfono (Android). Solo los teléfonos
  /// reclaman `currentPhoneDeviceId`; PC/tablet actúan como altavoz o mando.
  bool get _isPhoneDevice => (_devicePlatform ?? '') == 'android';

  /// Nombre legible del equipo derivado dinámicamente del sistema operativo y
  /// del hostname local (o del nombre personalizado guardado), sin valores
  /// fijos ligados a un usuario concreto.
  @visibleForTesting
  static String resolveDefaultDeviceName({
    required String platform,
    required String hostname,
    String? savedCustomName,
  }) {
    final custom = savedCustomName?.trim() ?? '';
    if (custom.isNotEmpty) return custom;

    if (platform == 'android') return 'Teléfono Android';
    if (platform == 'ios') return 'iPhone';

    var cleanHost = hostname.trim();
    if (cleanHost.toLowerCase().endsWith('.local')) {
      cleanHost = cleanHost.substring(0, cleanHost.length - 6);
    }
    final genericHost =
        cleanHost.isEmpty ||
        cleanHost.toLowerCase() == 'localhost' ||
        cleanHost.toLowerCase() == '127.0.0.1';

    final osLabel = switch (platform) {
      'linux' => 'Linux',
      'windows' => 'Windows',
      'macos' => 'macOS',
      _ => 'Desktop',
    };
    if (genericHost) {
      return switch (platform) {
        'linux' => 'PC Linux',
        'windows' => 'PC Windows',
        'macos' => 'Mac',
        _ => 'PC Desktop',
      };
    }
    return '$cleanHost ($osLabel)';
  }

  // ---------------------------------------------------------------------------
  // 1. ARRANQUE Y PERSISTENCIA DE SESIÓN
  // ---------------------------------------------------------------------------
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Identificación única de dispositivo
    _deviceId = prefs.getString(_storageDeviceIdKey);
    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await prefs.setString(_storageDeviceIdKey, _deviceId!);
    }

    if (Platform.isAndroid) {
      _devicePlatform = 'android';
    } else if (Platform.isIOS) {
      _devicePlatform = 'ios';
    } else if (Platform.isLinux) {
      _devicePlatform = 'linux';
    } else if (Platform.isWindows) {
      _devicePlatform = 'windows';
    } else if (Platform.isMacOS) {
      _devicePlatform = 'macos';
    } else {
      _devicePlatform = 'desktop';
    }

    var localHostname = '';
    try {
      localHostname = Platform.localHostname;
    } catch (_) {
      localHostname = '';
    }
    _deviceName = resolveDefaultDeviceName(
      platform: _devicePlatform ?? 'desktop',
      hostname: localHostname,
      savedCustomName: prefs.getString('inutil_custom_device_name'),
    );

    // 2. Restaurar sesión desde el almacenamiento seguro (o fallback prefs)
    final sessionJson = await _readSecure(prefs, _storageSessionKey);
    if (sessionJson != null) {
      try {
        final map = jsonDecode(sessionJson) as Map<String, dynamic>;
        final snap = prefs.getString(_storageUserKey);
        var user = snap != null
            ? InutilUser.fromJson(jsonDecode(snap) as Map<String, dynamic>)
            : InutilUser.fromJson({
                'uid': map['uid'] ?? '',
                'email': map['email'] ?? '',
              });
        user = user.copyWith(
          idToken: map['idToken'] as String? ?? user.idToken,
          refreshToken: map['refreshToken'] as String? ?? user.refreshToken,
        );
        _currentUser = user;
        notifyListeners();
      } catch (e) {
        debugPrint('Error decodificando sesión guardada: $e');
        await _clearSession(prefs);
      }
    } else {
      // Migración única desde el formato v2 (prefs en claro, anterior a la
      // autenticación con Firebase): se borra el registro con contraseñas en
      // claro para no dejar credenciales residuales en el dispositivo.
      await _migrateLegacy(prefs);
    }

    if (_currentUser == null) return;

    // 3. Renovar idToken si caducó y validar licencia/dispositivo en línea.
    await _ensureFreshIdToken();
    unawaited(_validateSession(reason: 'arranque'));
    // El temporizador únicamente re-intenta la validación en línea; cuando esa
    // validación está desactivada no tiene nada que hacer, y dejarlo activo
    // dejaría un Timer periódico pendiente al cerrar la app.
    if (!testSkipOnlineValidation) _startValidationTimer();
  }

  void _startValidationTimer() {
    _validateTimer?.cancel();
    _validateTimer = Timer.periodic(_validateInterval, (_) {
      unawaited(_validateSession(reason: 'temporizador'));
    });
  }

  /// Revalida la licencia al volver a primer plano (lo llama la UI).
  Future<void> onAppResumed() async {
    await _ensureFreshIdToken();
    await _validateSession(reason: 'reanudada');
  }

  /// Renueva el token de sesión si está próximo a caducar antes de leer/escribir
  /// documentos de respaldo en Firestore.
  Future<bool> ensureFreshSession() => _ensureFreshIdToken();

  /// Migración desde el registro local antiguo (contraseñas en claro): se
  /// elimina por completo; la sesión solo puede renacer de Firebase Auth.
  Future<void> _migrateLegacy(SharedPreferences prefs) async {
    final hadLegacy =
        prefs.containsKey(_storageLegacyUserKey) ||
        prefs.containsKey(_storageRegistryKey);
    if (!hadLegacy) return;
    await prefs.remove(_storageLegacyUserKey);
    await prefs.remove(_storageRegistryKey);
  }

  Future<String?> _readSecure(SharedPreferences prefs, String key) async {
    try {
      final v = await _secure.read(key: key).timeout(_secureTimeout);
      if (v != null && v.isNotEmpty) return v;
    } catch (e) {
      debugPrint('Almacenamiento seguro no disponible ($e); usando prefs');
    }
    return prefs.getString(key);
  }

  Future<void> _writeSecure(
    SharedPreferences prefs,
    String key,
    String value,
  ) async {
    try {
      await _secure.write(key: key, value: value).timeout(_secureTimeout);
      // Borrado del espejo en prefs cuando el backend seguro funciona.
      await prefs.remove(key);
    } catch (e) {
      debugPrint('Almacenamiento seguro falló ($e); espejando en prefs');
      await prefs.setString(key, value);
    }
  }

  Future<void> _deleteSecure(SharedPreferences prefs, String key) async {
    try {
      await _secure.delete(key: key).timeout(_secureTimeout);
    } catch (e) {
      debugPrint('InutilAuthService: fallo al borrar clave segura $key: $e');
    }
    await prefs.remove(key);
  }

  Future<void> _clearSession(SharedPreferences prefs) async {
    await _deleteSecure(prefs, _storageSessionKey);
    await prefs.remove(_storageUserKey);
    _currentUser = null;
    notifyListeners();
  }

  Future<void> _saveSession() async {
    final user = _currentUser;
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    // Tokens → almacenamiento seguro; snapshot de identidad/licencia → prefs.
    await _writeSecure(
      prefs,
      _storageSessionKey,
      jsonEncode({
        'uid': user.uid,
        'email': user.email,
        'idToken': user.idToken,
        'refreshToken': user.refreshToken,
        'savedAt': DateTime.now().toIso8601String(),
      }),
    );
    await prefs.setString(_storageUserKey, jsonEncode(user.toJson()));
  }

  // ---------------------------------------------------------------------------
  // 2. FIREBASE AUTH REST (Identity Toolkit v1) — única fuente de verdad
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> _authPost(
    String path,
    Map<String, dynamic> body,
  ) async {
    final url = Uri.parse(
      '${FirebaseConfig.authBaseUrl}/$path?${FirebaseConfig.keyParam}',
    );
    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));
    final data = response.statusCode == 200
        ? jsonDecode(response.body) as Map<String, dynamic>
        : null;
    if (data == null) {
      final decoded = _tryDecode(response.body);
      final message =
          decoded['error']?['message']?.toString() ?? 'Error de autenticación';
      throw Exception(_mapAuthError(message));
    }
    return data;
  }

  static Map<String, dynamic> _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Intercambio de refreshToken por un idToken nuevo (Secure Token Manager).
  Future<bool> _ensureFreshIdToken() async {
    final user = _currentUser;
    if (user == null || user.refreshToken.isEmpty) return false;
    if (testSkipOnlineValidation) return _idTokenValid(user.idToken);
    if (_idTokenValid(user.idToken)) return true;
    try {
      final url = Uri.parse(
        '${FirebaseConfig.secureTokenUrl}?${FirebaseConfig.keyParam}',
      );
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'grant_type': 'refresh_token',
              'refresh_token': user.refreshToken,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;
      final data = _tryDecode(response.body);
      final idToken = data['id_token'] as String? ?? '';
      if (idToken.isEmpty) return false;
      _currentUser = user.copyWith(
        idToken: idToken,
        refreshToken: (data['refresh_token'] as String?) ?? user.refreshToken,
      );
      await _saveSession();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Fallo refrescando idToken: $e');
      return false;
    }
  }

  /// Decodifica el payload JWT y comprueba `exp` con margen de 60 s.
  static bool _idTokenValid(String idToken) {
    if (idToken.isEmpty) return false;
    try {
      final parts = idToken.split('.');
      if (parts.length < 2) return false;
      final payload =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map<String, dynamic>;
      final exp = (payload['exp'] as num?)?.toInt() ?? 0;
      return exp - DateTime.now().millisecondsSinceEpoch ~/ 1000 > 60;
    } catch (_) {
      return false;
    }
  }

  /// Registro de usuario con Email y Contraseña (Firebase Auth real).
  ///
  /// El alta queda `status: 'pending'`: el usuario puede registrarse pero no
  /// reproduce nada hasta que el administrador le conceda vigencia.
  Future<InutilUser> register({
    required String email,
    required String password,
    String? displayName,
    int initialDays = 30,
  }) async {
    final trimmedEmail = email.trim().toLowerCase();
    if (trimmedEmail.isEmpty || password.length < 6) {
      throw Exception(
        'El correo y la contraseña (mínimo 6 caracteres) son obligatorios.',
      );
    }

    final data = await _authPost('accounts:signUp', {
      'email': trimmedEmail,
      'password': password,
      'returnSecureToken': true,
    });

    final user = InutilUser(
      uid: data['localId'] as String,
      email: trimmedEmail,
      displayName: displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : trimmedEmail.split('@').first,
      idToken: data['idToken'] as String? ?? '',
      refreshToken: data['refreshToken'] as String? ?? '',
      // La vigencia real la fija el administrador; localmente se refleja lo
      // que devuelva `_bootstrapSession()` desde Firestore.
      accountExpiresAt: null,
      accountDurationDays: initialDays,
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
    );

    _currentUser = user;
    _kickedOutReason = '';
    await _saveSession();
    await _bootstrapSession(createIfMissing: true);
    notifyListeners();
    return _currentUser!;
  }

  /// Inicio de sesión con Email y Contraseña (Firebase Auth real).
  Future<InutilUser> signIn({
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim().toLowerCase();

    final data = await _authPost('accounts:signInWithPassword', {
      'email': trimmedEmail,
      'password': password,
      'returnSecureToken': true,
    });

    final user = InutilUser(
      uid: data['localId'] as String,
      email: trimmedEmail,
      displayName:
          data['displayName'] as String? ?? trimmedEmail.split('@').first,
      idToken: data['idToken'] as String? ?? '',
      refreshToken: data['refreshToken'] as String? ?? '',
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
    );

    _currentUser = user;
    _kickedOutReason = '';
    await _saveSession();
    await _bootstrapSession(createIfMissing: true);
    notifyListeners();
    return _currentUser!;
  }

  /// Inicio de sesión o registro con cuenta de Google (Google Sign-In nativo
  /// + intercambio `accounts:signInWithIdp` contra Firebase Auth REST).
  ///
  /// Las cuentas nuevas con Google quedan en estado `pending` hasta que el
  /// administrador les conceda vigencia, salvo los correos fundadores en
  /// [bootstrapAdminEmails].
  Future<InutilUser?> signInWithGoogle() async {
    final googleSignIn = GoogleSignIn(
      scopes: const ['email', 'profile'],
      serverClientId: FirebaseConfig.googleWebClientId,
    );

    GoogleSignInAccount? account;
    try {
      account = await googleSignIn.signIn();
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('ApiException: 10')) {
        throw Exception(
          'Error de configuración OAuth (código 10). Verifica que estés usando el APK oficial.',
        );
      }
      if (msg.contains('ApiException: 7') || msg.contains('network')) {
        throw Exception(
          'Sin conexión a internet para iniciar sesión con Google.',
        );
      }
      if (msg.contains('MissingPluginException') ||
          msg.contains('not available')) {
        throw Exception(
          'Google Sign-In no está disponible en este dispositivo. Usa correo y contraseña.',
        );
      }
      throw Exception('No se pudo conectar con Google: $msg');
    }

    if (account == null) return null;

    final googleAuth = await account.authentication;
    final googleIdToken = googleAuth.idToken;
    final googleAccessToken = googleAuth.accessToken;
    if ((googleIdToken == null || googleIdToken.isEmpty) &&
        (googleAccessToken == null || googleAccessToken.isEmpty)) {
      throw Exception(
        'Google no devolvió un token válido. Intenta de nuevo o usa correo y contraseña.',
      );
    }

    final postBody = (googleIdToken != null && googleIdToken.isNotEmpty)
        ? 'id_token=$googleIdToken&providerId=google.com'
        : 'access_token=$googleAccessToken&providerId=google.com';

    final data = await _authPost('accounts:signInWithIdp', {
      'postBody': postBody,
      'requestUri': 'http://localhost',
      'returnIdpCredential': true,
      'returnSecureToken': true,
    });

    final email = (data['email'] as String? ?? account.email)
        .trim()
        .toLowerCase();
    final displayName = (data['displayName'] as String?)?.isNotEmpty == true
        ? data['displayName'] as String
        : ((account.displayName?.isNotEmpty == true)
              ? account.displayName!
              : email.split('@').first);

    final user = InutilUser(
      uid: data['localId'] as String,
      email: email,
      displayName: displayName,
      idToken: data['idToken'] as String? ?? '',
      refreshToken: data['refreshToken'] as String? ?? '',
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
    );

    _currentUser = user;
    _kickedOutReason = '';
    await _saveSession();
    await _bootstrapSession(createIfMissing: true);
    if (!testSkipOnlineValidation) _startValidationTimer();
    notifyListeners();
    return _currentUser!;
  }

  /// Cambio de contraseña de la cuenta en sesión (`accounts:update`).
  Future<void> changePassword(String newPassword) async {
    final user = _currentUser;
    if (user == null || user.idToken.isEmpty) {
      throw Exception('Inicia sesión antes de cambiar la contraseña.');
    }
    if (newPassword.length < 6) {
      throw Exception('La nueva contraseña debe tener al menos 6 caracteres.');
    }
    final data = await _authPost('accounts:update', {
      'idToken': user.idToken,
      'password': newPassword,
      'returnSecureToken': true,
    });
    _currentUser = user.copyWith(
      idToken: data['idToken'] as String? ?? user.idToken,
      refreshToken: data['refreshToken'] as String? ?? user.refreshToken,
    );
    await _saveSession();
    notifyListeners();
  }

  /// Inicia sesión en la PC con el `refreshToken` recibido cifrado desde el
  /// celular (vinculación por QR o código de 8 caracteres).
  ///
  /// Devuelve `null` si todo salió bien o un mensaje legible si falló. La PC
  /// no reclama el slot de teléfono, así que el celular no queda expulsado.
  Future<String?> signInWithPairedRefreshToken(
    String refreshToken, {
    String emailHint = '',
    String displayNameHint = '',
  }) async {
    final token = refreshToken.trim();
    if (token.isEmpty) return 'La sesión enviada desde el celular está vacía.';
    try {
      final tokenRes = await http
          .post(
            Uri.parse(
              '${FirebaseConfig.secureTokenUrl}?${FirebaseConfig.keyParam}',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'grant_type': 'refresh_token',
              'refresh_token': token,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (tokenRes.statusCode != 200) {
        return 'La sesión del celular no es válida. Vuelve a iniciar sesión en el celular.';
      }
      final data = _tryDecode(tokenRes.body);
      final idToken = data['id_token'] as String? ?? '';
      final uid = data['user_id'] as String? ?? '';
      final newRefresh = (data['refresh_token'] as String?) ?? token;
      if (idToken.isEmpty || uid.isEmpty) {
        return 'No se pudo validar la sesión recibida.';
      }

      var email = emailHint.trim().toLowerCase();
      var displayName = displayNameHint.trim();
      try {
        final lookup = await _authPost('accounts:lookup', {'idToken': idToken});
        final users = lookup['users'] as List?;
        if (users != null && users.isNotEmpty && users.first is Map) {
          final u = users.first as Map;
          final e = (u['email'] ?? '').toString().trim().toLowerCase();
          final d = (u['displayName'] ?? '').toString().trim();
          if (e.isNotEmpty) email = e;
          if (d.isNotEmpty) displayName = d;
        }
      } catch (e) {
        debugPrint(
          'InutilAuthService: no se pudo enriquecer perfil en lookup: $e',
        );
      }

      _currentUser = InutilUser(
        uid: uid,
        email: email,
        displayName: displayName.isNotEmpty
            ? displayName
            : (email.contains('@') ? email.split('@').first : 'Usuario'),
        idToken: idToken,
        refreshToken: newRefresh,
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );
      _kickedOutReason = '';
      _inactivityPaused = false;
      await _saveSession();
      await _bootstrapSession(createIfMissing: true);
      if (!testSkipOnlineValidation) _startValidationTimer();
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('[InutilAuth] Error iniciando sesión por QR: $e');
      return 'Error de conexión al iniciar sesión con el celular.';
    }
  }

  /// Cierre de sesión seguro. Libera el teléfono reclamado para que otro
  /// dispositivo pueda usar la cuenta sin gastar el cambio mensual.
  Future<void> signOut() async {
    final user = _currentUser;
    final prefs = await SharedPreferences.getInstance();
    if (user != null && _isPhoneDevice && user.idToken.isNotEmpty) {
      // Mejor esfuerzo: sin red simplemente se ignora.
      try {
        await InutilFirestoreService.instance.setDocument('users/${user.uid}', {
          'currentPhoneDeviceId': '',
        });
      } catch (e) {
        debugPrint(
          'InutilAuthService: no se pudo limpiar currentPhoneDeviceId: $e',
        );
      }
    }
    _validateTimer?.cancel();
    _validateTimer = null;
    _kickedOutReason = '';
    _inactivityPaused = false;
    await prefs.remove('inutix.playback.resume_session.v1');
    _inactiveDays = 0;
    _lastHeartbeatAt = null;
    _currentUser = null;
    if (!testSkipOnlineValidation) {
      try {
        await GoogleSignIn().signOut();
      } catch (e) {
        debugPrint('InutilAuthService: GoogleSignIn.signOut falló: $e');
      }
    }
    await _clearSession(prefs);
  }

  @override
  // ignore: must_call_super
  void dispose() {
    // La instancia singleton de InutilAuthService persiste durante la ejecución de la app.
  }

  /// Recuperación de contraseña por correo
  Future<void> sendPasswordReset(String email) async {
    final trimmedEmail = email.trim();
    try {
      await _authPost('accounts:sendOobCode', {
        'requestType': 'PASSWORD_RESET',
        'email': trimmedEmail,
      });
    } catch (_) {
      // Mensaje de confirmación estándar de seguridad: no se revela si el
      // correo existe o no.
    }
  }

  // ---------------------------------------------------------------------------
  // 3. LICENCIA EN FIRESTORE: arranque de sesión, validez y teléfono único
  // ---------------------------------------------------------------------------

  /// Lee `users/{uid}`; si no existe lo crea con la semilla correcta:
  ///  * el correo fundador obtiene `role: 'admin'` + `status: 'active'`
  ///    (las reglas de Firestore solo dejan crear ese doc admin si el token
  ///    pertenece a `bootstrapAdminEmail`);
  ///  * cualquier otro queda `status: 'pending'` (sin vigencia).
  Future<void> _bootstrapSession({required bool createIfMissing}) async {
    final user = _currentUser;
    if (user == null || user.uid.isEmpty || user.idToken.isEmpty) return;
    try {
      final remote = await _fetchVerifiedUserProfile(user.uid);
      if (remote == null || remote.isEmpty) {
        if (!createIfMissing) return;
        final isAdminSeed = isBootstrapAdminEmail(user.email);
        final seeded = <String, dynamic>{
          'uid': user.uid,
          'email': user.email,
          'displayName': user.displayName,
          'role': isAdminSeed ? 'admin' : 'user',
          'status': isAdminSeed ? 'active' : 'pending',
          'isActive': isAdminSeed,
          'accountExpiresAt': isAdminSeed ? DateTime(2099, 12, 31) : null,
          'accountDurationDays': isAdminSeed ? 9999 : 0,
          'currentPhoneDeviceId': '',
          'phoneSwitchCount': 0,
          'phoneSwitchMonth': '',
          'createdAt': DateTime.now(),
          'lastLoginAt': DateTime.now(),
          'lastValidatedAt': DateTime.now(),
          'lastActiveAt': DateTime.now(),
          'schemaVersion': 3,
        };
        final ok = await InutilFirestoreService.instance.setDocument(
          'users/${user.uid}',
          seeded,
          merge: false,
        );
        if (ok) {
          _currentUser = user.copyWith(
            role: isAdminSeed ? 'admin' : 'user',
            status: isAdminSeed ? 'active' : 'pending',
            isActive: isAdminSeed,
            accountExpiresAt: isAdminSeed ? DateTime(2099, 12, 31) : null,
          );
          await _saveSession();
        }
        // Si `ok == false` (reglas/red) el usuario queda pendiente localmente:
        // exactamente el comportamiento deseado, sin licencia no reproduce.
        await _claimPhoneDevice();
        return;
      }
      await _applyRemoteDoc(remote);
      // El fundador puede elevar su propio documento a admin la primera vez:
      // las reglas Firestore solo permiten este caso exacto y solo para sus
      // correos (la identidad ya la validó Firebase Auth / Google Sign-In).
      final me = _currentUser;
      if (me != null && isBootstrapAdminEmail(me.email) && !me.isAdmin) {
        final upgraded = await InutilFirestoreService.instance
            .setDocument('users/${me.uid}', {
              'role': 'admin',
              'status': 'active',
              'isActive': true,
              'accountExpiresAt': DateTime(2099, 12, 31),
            }, merge: true);
        if (upgraded) {
          _currentUser = me.copyWith(
            role: 'admin',
            status: 'active',
            isActive: true,
            accountExpiresAt: DateTime(2099, 12, 31),
          );
          await _saveSession();
        }
      }
      await _claimPhoneDevice();
      if (_currentUser?.licenseValid == true) {
        await _enforceInactivityPolicy(remote);
      }
    } catch (e) {
      debugPrint('Bootstrap de sesión sin respuesta remota: $e');
      // Sin red: se conserva el snapshot local y su fecha de validación.
    }
  }

  DateTime? _lastValidatedAt;
  DateTime? get lastValidatedAt => _lastValidatedAt;

  bool _licenseFresh() {
    final user = _currentUser;
    if (user == null) return false;
    if (!user.licenseValid) return false;
    if (_inactivityPaused) return false;
    if (!_phoneSessionOk(user)) return false;
    final validated = _lastValidatedAt;
    if (validated == null) return false;
    return DateTime.now().difference(validated) <= offlineGrace;
  }

  bool _phoneSessionOk(InutilUser user) {
    if (!_isPhoneDevice || user.isAdmin) return true;
    return user.currentPhoneDeviceId.isEmpty ||
        user.currentPhoneDeviceId == _deviceId;
  }

  /// Aplica el documento remoto de licencia sobre el snapshot local.
  Future<void> _applyRemoteDoc(Map<String, dynamic> remote) async {
    final user = _currentUser;
    if (user == null) return;
    final expiresAt = remote['accountExpiresAt'] is DateTime
        ? remote['accountExpiresAt'] as DateTime
        : (remote['accountExpiresAt'] != null
              ? DateTime.tryParse(remote['accountExpiresAt'].toString())
              : user.accountExpiresAt);
    final role = remote['role'] as String? ?? user.role;
    final status =
        remote['status'] as String? ??
        ((remote['isActive'] as bool?) == false ? 'blocked' : user.status);
    _currentUser = user.copyWith(
      accountExpiresAt: expiresAt,
      isActive: (remote['isActive'] as bool?) ?? user.isActive,
      role: role,
      status: status,
      displayName: (remote['displayName'] as String?)?.isNotEmpty == true
          ? remote['displayName'] as String
          : user.displayName,
      currentPhoneDeviceId:
          remote['currentPhoneDeviceId'] as String? ??
          user.currentPhoneDeviceId,
      phoneSwitchCount:
          (remote['phoneSwitchCount'] as num?)?.toInt() ??
          user.phoneSwitchCount,
      phoneSwitchMonth:
          remote['phoneSwitchMonth'] as String? ?? user.phoneSwitchMonth,
    );
    _lastValidatedAt = DateTime.now();
    await _saveSession();
    notifyListeners();
  }

  /// Un solo teléfono por cuenta: Android reclama el slot. Si otro teléfono lo
  /// tiene, este dispositivo queda expulsado; los cambios de teléfono están
  /// limitados a [maxMonthlyPhoneSwitches] por mes natural.
  Future<void> _claimPhoneDevice() async {
    final user = _currentUser;
    if (user == null || !_isPhoneDevice) return;
    final doc = await InutilFirestoreService.instance.getUserProfile(user.uid);
    if (doc == null) return;
    final holder = doc['currentPhoneDeviceId'] as String? ?? '';
    if (holder == _deviceId) return;

    if (user.isAdmin) {
      final ok = await InutilFirestoreService.instance.setDocument(
        'users/${user.uid}',
        {'currentPhoneDeviceId': _deviceId!, 'lastValidatedAt': DateTime.now()},
      );
      if (ok) {
        _currentUser = user.copyWith(currentPhoneDeviceId: _deviceId);
        await _saveSession();
        notifyListeners();
      }
      return;
    }

    final month = _monthKey(DateTime.now());
    var switches = doc['phoneSwitchMonth'] == month
        ? ((doc['phoneSwitchCount'] as num?)?.toInt() ?? 0)
        : 0;

    if (holder.isNotEmpty) {
      if (switches >= maxMonthlyPhoneSwitches) {
        _kickedOutReason =
            'Esta cuenta ya cambió de teléfono $switches veces este mes. '
            'Espera al próximo mes o pide al administrador que libere el dispositivo.';
        notifyListeners();
        return;
      }
      switches += 1;
    }

    final ok = await InutilFirestoreService.instance
        .setDocument('users/${user.uid}', {
          'currentPhoneDeviceId': _deviceId!,
          'phoneSwitchCount': switches,
          'phoneSwitchMonth': month,
          'lastValidatedAt': DateTime.now(),
        });
    if (ok) {
      _currentUser = user.copyWith(
        currentPhoneDeviceId: _deviceId,
        phoneSwitchCount: switches,
        phoneSwitchMonth: month,
      );
      await _saveSession();
      notifyListeners();
    }
  }

  static String _monthKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}';

  static const String _accountDeletedReason =
      'Tu cuenta ya no existe. Contacta al administrador.';

  /// Consulta el perfil `users/{uid}` en el tier activo (S7/backup) y, si
  /// recibe un 404 (`null`) mientras algún relay está configurado, hace una
  /// doble verificación directa contra Google Firestore antes de aceptar que
  /// la cuenta fue borrada. Evita bloqueos falsos cuando el nodo de respaldo o
  /// la caché aún no tiene el documento de una cuenta autorizada.
  Future<Map<String, dynamic>?> _fetchVerifiedUserProfile(String uid) async {
    final remote = await InutilFirestoreService.instance.getUserProfile(uid);
    if (remote != null && remote.isNotEmpty) return remote;
    final usingRelay =
        FirebaseConfig.relayUsable ||
        FirebaseConfig.cloudRelayUsable ||
        FirebaseConfig.backupRelayUsable;
    if (!usingRelay || FirebaseConfig.useEmulator) {
      return remote;
    }
    return await InutilFirestoreService.instance.getUserProfileDirect(uid);
  }

  /// Reconcilia `_kickedOutReason` con el estado real recién leído de la nube.
  /// Antes, una vez que `_kickedOutReason` se llenaba (p. ej. por un 404
  /// transitorio de un nodo de respaldo), nunca se limpiaba aunque el usuario
  /// estuviera autorizado y pulsara «Comprobar Estado».
  Future<void> _reconcileRemoteProfile(Map<String, dynamic> remote) async {
    await _applyRemoteDoc(remote);
    final updated = _currentUser;
    if (updated == null) return;
    if (_isPhoneDevice && !_phoneSessionOk(updated)) {
      _kickedOutReason =
          'Otro teléfono tomó el control de esta cuenta. '
          'Esta sesión quedó bloqueada.';
      notifyListeners();
      return;
    }
    if (!updated.licenseValid) {
      if (_kickedOutReason == _accountDeletedReason ||
          _kickedOutReason.contains('Otro teléfono')) {
        _kickedOutReason = '';
      }
      notifyListeners();
      return;
    }
    final clearedKick = _kickedOutReason.isNotEmpty;
    if (clearedKick) {
      _kickedOutReason = '';
    }
    await _enforceInactivityPolicy(remote);
    if (clearedKick) {
      notifyListeners();
    }
  }

  /// Revalida la licencia contra Firestore (arranque, temporizador, reanudar).
  Future<void> _validateSession({required String reason}) async {
    final user = _currentUser;
    if (user == null || user.uid.isEmpty) return;
    if (testSkipOnlineValidation) return;
    if (_validating) return;
    _validating = true;
    try {
      await _ensureFreshIdToken();
      final remote = await _fetchVerifiedUserProfile(user.uid);
      if (remote == null) {
        // Confirmado 404 (incluyendo verificación directa contra Firestore si
        // se usaba relay): documento eliminado por el administrador.
        if (_kickedOutReason.isEmpty) {
          _kickedOutReason = _accountDeletedReason;
        }
        notifyListeners();
        return;
      }
      await _reconcileRemoteProfile(remote);
    } catch (e) {
      debugPrint('Validación de sesión ($reason) sin conexión: $e');
      // Sin red: la ventana de gracia decide (ver canPlay).
    } finally {
      _validating = false;
    }
  }

  /// Actualiza el perfil del usuario actual desde Firestore y registro local
  Future<void> refreshCurrentUserProfile() async {
    if (_currentUser == null) return;
    if (testSkipOnlineValidation) return;
    try {
      await _ensureFreshIdToken();
      final remoteDoc = await _fetchVerifiedUserProfile(_currentUser!.uid);
      if (remoteDoc != null && remoteDoc.isNotEmpty) {
        await _reconcileRemoteProfile(remoteDoc);
      } else if (remoteDoc == null) {
        if (_kickedOutReason.isEmpty) {
          _kickedOutReason = _accountDeletedReason;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error refrescando perfil de usuario: $e');
    }
  }

  @visibleForTesting
  Future<void> testReconcileRemoteProfile(Map<String, dynamic> remote) =>
      _reconcileRemoteProfile(remote);

  @visibleForTesting
  void testSetKickedOutReason(String reason) {
    _kickedOutReason = reason;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 3b. USO REAL Y PAUSA AUTOMÁTICA POR INACTIVIDAD
  // ---------------------------------------------------------------------------

  static DateTime? _parseRemoteDate(Object? raw) {
    if (raw is DateTime) return raw;
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  /// Lee la política vigente (`app_config/inactivity_policy`). Si no existe o
  /// no hay red se conserva la última conocida (por defecto 15 días).
  Future<void> _loadInactivityPolicy() async {
    try {
      final doc = await InutilFirestoreService.instance.getDocument(
        'app_config/inactivity_policy',
      );
      if (doc == null) return;
      final enabled = doc['enabled'];
      if (enabled is bool) _inactivityPolicyEnabled = enabled;
      final days =
          (doc['days'] as num?)?.toInt() ??
          int.tryParse(doc['days']?.toString() ?? '');
      if (days != null) {
        _inactivityPolicyDays = days.clamp(
          _minInactivityDays,
          _maxInactivityDays,
        );
      }
    } catch (e) {
      debugPrint('Política de inactividad no disponible: $e');
    }
  }

  /// Aplica la pausa automática por inactividad. Mientras la cuenta está en
  /// pausa NO se actualiza `lastActiveAt`, así que reinstalar o volver a
  /// iniciar sesión no la reactiva: solo el administrador (o una licencia
  /// permanente/exención) la libera.
  Future<void> _enforceInactivityPolicy(Map<String, dynamic> remote) async {
    final user = _currentUser;
    if (user == null) return;
    await _loadInactivityPolicy();
    final lastActiveAt = _parseRemoteDate(remote['lastActiveAt']);
    final exempt =
        user.isAdmin || user.isPermanent || remote['inactivityExempt'] == true;
    final days = inactivityPauseDays(
      lastActiveAt: lastActiveAt,
      exempt: exempt,
      enabled: _inactivityPolicyEnabled,
      thresholdDays: _inactivityPolicyDays,
      now: DateTime.now(),
    );
    if (days != null) {
      final changed = !_inactivityPaused || _inactiveDays != days;
      _inactivityPaused = true;
      _inactiveDays = days;
      if (changed) notifyListeners();
      return;
    }
    final wasPaused = _inactivityPaused;
    _inactivityPaused = false;
    _inactiveDays = 0;
    await _writeActivityHeartbeat(force: lastActiveAt == null || wasPaused);
    if (wasPaused) notifyListeners();
  }

  /// Registra el uso real de la app (`lastActiveAt`) como máximo 1 vez/hora.
  Future<void> _writeActivityHeartbeat({bool force = false}) async {
    final user = _currentUser;
    if (user == null || user.uid.isEmpty || _inactivityPaused) return;
    final now = DateTime.now();
    final last = _lastHeartbeatAt;
    if (!force && last != null && now.difference(last) < _heartbeatThrottle) {
      return;
    }
    final ok = await InutilFirestoreService.instance
        .setDocument('users/${user.uid}', {
          'lastActiveAt': now,
          'lastActivePlatform': devicePlatform,
          'lastActiveAppVersion': AppConstants.appVersion,
        });
    if (ok) _lastHeartbeatAt = now;
  }

  /// El usuario en pausa solicita reactivación; el administrador la ve en el
  /// portal web (badge «Pidió reactivación»).
  Future<bool> requestReactivation() async {
    final user = _currentUser;
    if (user == null || user.uid.isEmpty) return false;
    try {
      await _ensureFreshIdToken();
      return await InutilFirestoreService.instance.setDocument(
        'users/${user.uid}',
        {'reactivationRequestedAt': DateTime.now()},
      );
    } catch (e) {
      debugPrint('No se pudo solicitar reactivación: $e');
      return false;
    }
  }

  @visibleForTesting
  void testSetInactivityPaused({required bool paused, int days = 0}) {
    _inactivityPaused = paused;
    _inactiveDays = days;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 4. MÓDULO DE ADMINISTRACIÓN (EXCLUSIVO PARA ADMINS)
  //
  // Todas las operaciones escriben en Firestore; las reglas de seguridad
  // rechazan a quien no sea admin, así que un cliente manipulado no puede
  // autoconcederse vigencia.
  // ---------------------------------------------------------------------------

  /// Obtiene todos los usuarios registrados (Firestore; cache local si no hay
  /// conexión para que el panel siga mostrando la lista).
  Future<List<InutilUser>> getAllUsers() async {
    final usersMap = <String, InutilUser>{};
    final prefs = await SharedPreferences.getInstance();
    try {
      // Con `testSkipOnlineValidation` no se toca la red: el panel se pinta
      // con la caché local (los widget tests no pueden completar HTTP real).
      final remoteUsers = testSkipOnlineValidation
          ? const <Map<String, dynamic>>[]
          : await InutilFirestoreService.instance.getAllUsers();
      if (remoteUsers.isEmpty) {
        final cache = prefs.getString(_storageUsersCacheKey);
        if (cache != null) {
          for (final entry in (jsonDecode(cache) as List? ?? [])) {
            if (entry is Map<String, dynamic>) {
              final u = InutilUser.fromJson(entry);
              usersMap[u.uid] = u;
            }
          }
        }
        return _sortedUsers(usersMap.values.toList());
      }
      final encoded = <Map<String, dynamic>>[];
      for (final doc in remoteUsers) {
        final uid = doc['uid'] as String? ?? '';
        if (uid.isEmpty) continue;
        final u = InutilUser(
          uid: uid,
          email: doc['email'] as String? ?? '',
          displayName: doc['displayName'] as String? ?? '',
          role: doc['role'] as String? ?? 'user',
          isActive: doc['isActive'] as bool? ?? true,
          status:
              doc['status'] as String? ??
              ((doc['isActive'] as bool?) == false ? 'blocked' : 'active'),
          accountExpiresAt: doc['accountExpiresAt'] is DateTime
              ? doc['accountExpiresAt'] as DateTime
              : (doc['accountExpiresAt'] != null
                    ? DateTime.tryParse(doc['accountExpiresAt'].toString())
                    : null),
          accountDurationDays:
              (doc['accountDurationDays'] as num?)?.toInt() ?? 30,
          lastLoginAt: doc['lastLoginAt'] is DateTime
              ? doc['lastLoginAt'] as DateTime
              : (doc['lastLoginAt'] != null
                    ? DateTime.tryParse(doc['lastLoginAt'].toString())
                    : null),
          currentPhoneDeviceId: doc['currentPhoneDeviceId'] as String? ?? '',
          phoneSwitchCount: (doc['phoneSwitchCount'] as num?)?.toInt() ?? 0,
          phoneSwitchMonth: doc['phoneSwitchMonth'] as String? ?? '',
        );
        usersMap[uid] = u;
        encoded.add(u.toJson());
      }
      await prefs.setString(_storageUsersCacheKey, jsonEncode(encoded));
    } catch (e) {
      debugPrint('Error obteniendo usuarios de Firestore: $e');
    }
    return _sortedUsers(usersMap.values.toList());
  }

  List<InutilUser> _sortedUsers(List<InutilUser> list) {
    // Ordenar: primero los administradores, luego activos, luego por correo
    list.sort((a, b) {
      if (a.isAdmin && !b.isAdmin) return -1;
      if (!a.isAdmin && b.isAdmin) return 1;
      if (a.isActive && !b.isActive) return -1;
      if (!a.isActive && b.isActive) return 1;
      return a.email.compareTo(b.email);
    });
    return list;
  }

  /// Administrador: crea un nuevo usuario en Firebase Auth + Firestore **sin
  /// cerrar ni sobrescribir la sesión actual del administrador**.
  Future<InutilUser> adminCreateUser({
    required String email,
    required String password,
    String? displayName,
    int initialDays = 30,
    bool isPermanent = false,
  }) async {
    final admin = _currentUser;
    if (admin == null || !admin.isAdmin) {
      throw Exception('Solo un administrador puede crear usuarios.');
    }
    final trimmedEmail = email.trim().toLowerCase();
    if (trimmedEmail.isEmpty || password.length < 6) {
      throw Exception(
        'El correo y la contraseña (mínimo 6 caracteres) son obligatorios.',
      );
    }

    await _ensureFreshIdToken();

    final data = await _authPost('accounts:signUp', {
      'email': trimmedEmail,
      'password': password,
      'returnSecureToken': true,
    });
    final newUid = data['localId'] as String;
    final cleanName = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : trimmedEmail.split('@').first;
    final expiresAt = isPermanent
        ? DateTime(2099, 12, 31)
        : DateTime.now().add(Duration(days: initialDays));
    final durationDays = isPermanent ? 9999 : initialDays;

    final ok = await InutilFirestoreService.instance
        .setDocument('users/$newUid', {
          'uid': newUid,
          'email': trimmedEmail,
          'displayName': cleanName,
          'role': 'user',
          'status': 'active',
          'isActive': true,
          'accountExpiresAt': expiresAt,
          'accountDurationDays': durationDays,
          'currentPhoneDeviceId': '',
          'currentTvDeviceId': '',
          'phoneSwitchCount': 0,
          'phoneSwitchMonth': '',
          'createdAt': DateTime.now(),
          'lastLoginAt': DateTime.now(),
          'lastValidatedAt': DateTime.now(),
          'schemaVersion': 3,
        }, merge: false);
    if (!ok) {
      throw Exception(
        'La cuenta se creó en Auth, pero falló al guardar su licencia en Firestore.',
      );
    }

    notifyListeners();
    return InutilUser(
      uid: newUid,
      email: trimmedEmail,
      displayName: cleanName,
      role: 'user',
      status: 'active',
      isActive: true,
      accountExpiresAt: expiresAt,
      accountDurationDays: durationDays,
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
    );
  }

  /// Administrador: Conceder vigencia en días o Licencia Premium Permanente.
  Future<void> adminGrantVigencia({
    required String uid,
    required int additionalDays,
    bool isPermanent = false,
  }) async {
    DateTime newExpiresAt;
    int days = additionalDays;
    if (isPermanent) {
      newExpiresAt = DateTime(2099, 12, 31);
      days = 9999;
    } else {
      DateTime? currentExpiry;
      try {
        final doc = await InutilFirestoreService.instance.getUserProfile(uid);
        final raw = doc?['accountExpiresAt'];
        currentExpiry = raw is DateTime
            ? raw
            : (raw != null ? DateTime.tryParse(raw.toString()) : null);
      } catch (e) {
        debugPrint(
          'InutilAuthService: no se pudo leer expiración actual de $uid: $e',
        );
      }
      if (currentExpiry != null && currentExpiry.isAfter(DateTime.now())) {
        newExpiresAt = currentExpiry.add(Duration(days: additionalDays));
      } else {
        newExpiresAt = DateTime.now().add(Duration(days: additionalDays));
      }
    }

    final ok = await InutilFirestoreService.instance.adminUpdateUser(uid, {
      'accountExpiresAt': newExpiresAt,
      'isActive': true,
      'status': 'active',
      'accountDurationDays': days,
      // Renovar vigencia también reinicia el contador de inactividad.
      'lastActiveAt': DateTime.now(),
    });
    if (!ok) {
      throw Exception(
        'No se pudo guardar la vigencia en la nube. Revisa la conexión.',
      );
    }

    // Si el usuario modificado es el usuario actualmente activo en esta sesión
    if (_currentUser?.uid == uid) {
      _currentUser = _currentUser!.copyWith(
        accountExpiresAt: newExpiresAt,
        isActive: true,
        status: 'active',
      );
      await _saveSession();
    }

    notifyListeners();
  }

  /// Administrador: Establecer fecha exacta de vencimiento
  Future<void> adminSetExactExpiration({
    required String uid,
    required DateTime newExpiry,
  }) async {
    final ok = await InutilFirestoreService.instance.adminUpdateUser(uid, {
      'accountExpiresAt': newExpiry,
      'isActive': true,
      'status': 'active',
      'lastActiveAt': DateTime.now(),
    });
    if (!ok) {
      throw Exception('No se pudo guardar la fecha en la nube.');
    }

    if (_currentUser?.uid == uid) {
      _currentUser = _currentUser!.copyWith(
        accountExpiresAt: newExpiry,
        isActive: true,
        status: 'active',
      );
      await _saveSession();
    }

    notifyListeners();
  }

  /// Administrador: Activar o suspender cuenta
  Future<void> adminToggleUserActive({
    required String uid,
    required bool isActive,
  }) async {
    final ok = await InutilFirestoreService.instance.adminUpdateUser(uid, {
      'isActive': isActive,
      'status': isActive ? 'active' : 'blocked',
      if (isActive) 'lastActiveAt': DateTime.now(),
    });
    if (!ok) {
      throw Exception('No se pudo actualizar la cuenta en la nube.');
    }

    if (_currentUser?.uid == uid) {
      _currentUser = _currentUser!.copyWith(
        isActive: isActive,
        status: isActive ? 'active' : 'blocked',
      );
      await _saveSession();
    }

    notifyListeners();
  }

  /// Administrador: Asignar o revocar rol de Administrador
  Future<void> adminToggleUserRole({
    required String uid,
    required String role,
  }) async {
    final ok = await InutilFirestoreService.instance.adminUpdateUser(uid, {
      'role': role,
    });
    if (!ok) {
      throw Exception('No se pudo actualizar el rol en la nube.');
    }

    if (_currentUser?.uid == uid) {
      _currentUser = _currentUser!.copyWith(role: role);
      await _saveSession();
    }

    notifyListeners();
  }

  /// Administrador: liberar el teléfono de un usuario (permite cambiar de
  /// dispositivo sin esperar el límite mensual).
  Future<void> adminRevokeDevice(String uid) async {
    final ok = await InutilFirestoreService.instance.adminUpdateUser(uid, {
      'currentPhoneDeviceId': '',
      'currentTvDeviceId': '',
      'phoneSwitchCount': 0,
      'phoneSwitchMonth': '',
    });
    if (!ok) {
      throw Exception('No se pudo liberar el dispositivo en la nube.');
    }

    if (_currentUser?.uid == uid) {
      _currentUser = _currentUser!.copyWith(currentPhoneDeviceId: '');
      await _saveSession();
    }

    notifyListeners();
  }

  /// Administrador: Eliminar usuario
  Future<void> adminDeleteUser(String uid) async {
    if (_currentUser?.uid == uid) {
      await signOut();
    }

    unawaited(InutilFirestoreService.instance.deleteDocument('users/$uid'));
    notifyListeners();
  }

  String _mapAuthError(String error) {
    if (error.contains('EMAIL_EXISTS')) {
      return 'Este correo ya está registrado.';
    }
    if (error.contains('EMAIL_NOT_FOUND')) {
      return 'No existe ninguna cuenta con este correo.';
    }
    if (error.contains('INVALID_PASSWORD') ||
        error.contains('INVALID_LOGIN_CREDENTIALS')) {
      return 'Contraseña o credenciales incorrectas.';
    }
    if (error.contains('USER_DISABLED')) {
      return 'Esta cuenta ha sido desactivada por el administrador.';
    }
    if (error.contains('TOO_MANY_ATTEMPTS_TRY_LATER')) {
      return 'Demasiados intentos fallidos. Inténtalo más tarde.';
    }
    if (error.contains('CONFIGURATION_NOT_FOUND') ||
        error.contains('OPERATION_NOT_ALLOWED')) {
      return 'El servicio de cuentas no está disponible. Inténtalo más tarde.';
    }
    if (error.contains('NETWORK_ERROR') || error.contains('SocketException')) {
      return 'Sin conexión con el servidor de cuentas. Revisa tu internet.';
    }
    return 'Error de autenticación: $error';
  }
}
