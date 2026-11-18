import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import 'firebase_auth_service.dart';
import 'firebase_firestore_service.dart';

/// QR ya interpretado: código de la sesión + clave secreta de 256 bits.
@immutable
class ParsedMusicQr {
  const ParsedMusicQr({required this.code, required this.secretKey});

  final String code;
  final Uint8List secretKey;
}

/// Sesión de vinculación abierta en la PC mientras espera al celular.
@immutable
class MusicPairingSession {
  const MusicPairingSession({
    required this.code,
    required this.secretKey,
    required this.qrUri,
    required this.expiresAt,
  });

  final String code;
  final Uint8List secretKey;
  final String qrUri;
  final DateTime expiresAt;

  String get displayCode => MusicQrPairingService.formatDisplayCode(code);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Resultado de un sondeo de la PC.
enum MusicPairingPollState { waiting, approved, expired, failed }

@immutable
class MusicPairingPollResult {
  const MusicPairingPollResult(this.state, {this.payload, this.message});

  final MusicPairingPollState state;
  final Map<String, dynamic>? payload;
  final String? message;
}

/// Inicio de sesión de la app de escritorio escaneando un QR con el celular.
///
/// Flujo (cifrado extremo a extremo):
///  1. La PC genera un código de 8 caracteres y una clave AES-256 aleatoria.
///     Publica `music_pairing/{code}` con `status: pending` (sin secretos) y
///     muestra el QR `inutilmusic://pair?c=CODE&k=CLAVE`.
///  2. El celular (con sesión iniciada) escanea el QR, cifra su sesión con la
///     clave del QR (AES-256-CBC + HMAC-SHA256, Encrypt-then-MAC) y marca el
///     documento como `approved` con el `payload` cifrado.
///  3. La PC descifra, inicia sesión y borra el documento temporal.
///
/// La clave solo viaja dentro de la imagen QR, nunca en Firestore. Como
/// alternativa sin cámara se puede escribir el código `XXXX-XXXX`; en ese caso
/// la clave se deriva del propio código y la sesión expira en 3 minutos.
class MusicQrPairingService {
  MusicQrPairingService._();
  static final MusicQrPairingService instance = MusicQrPairingService._();

  static const String collection = 'music_pairing';
  static const Duration sessionTtl = Duration(minutes: 3);
  static const String _scheme = 'inutilmusic';
  static const String _host = 'pair';
  static const String _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static final RegExp _codePattern = RegExp(r'^[A-HJKMNP-Z2-9]{8}$');

  static final Random _random = Random.secure();

  // ---------------------------------------------------------------------------
  // Utilidades puras (probadas en unit tests)
  // ---------------------------------------------------------------------------

  static String generateCode() {
    final buffer = StringBuffer();
    for (var i = 0; i < 8; i++) {
      buffer.write(_alphabet[_random.nextInt(_alphabet.length)]);
    }
    return buffer.toString();
  }

  static String normalizeCode(String raw) =>
      raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

  static String formatDisplayCode(String code) {
    final c = normalizeCode(code);
    if (c.length != 8) return c;
    return '${c.substring(0, 4)}-${c.substring(4)}';
  }

  static bool isValidCode(String code) => _codePattern.hasMatch(code);

  static Uint8List _randomBytes(int length) =>
      Uint8List.fromList(List<int>.generate(length, (_) => _random.nextInt(256)));

  static Uint8List generateSecretKey() => _randomBytes(32);

  static Uint8List deriveManualCodeKey(String code) {
    final norm = normalizeCode(code);
    return Uint8List.fromList(
      crypto.sha256.convert(utf8.encode('inutilmusic-manual-pair-v1:$norm')).bytes,
    );
  }

  static String _b64(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List _unb64(String s) =>
      Uint8List.fromList(base64Url.decode(base64Url.normalize(s)));

  static String buildQrUri(String code, Uint8List secretKey) =>
      '$_scheme://$_host?c=$code&k=${_b64(secretKey)}';

  static ParsedMusicQr? parseQrUri(String raw) {
    try {
      final uri = Uri.parse(raw.trim());
      if (uri.scheme != _scheme || uri.host != _host) return null;
      final code = normalizeCode(uri.queryParameters['c'] ?? '');
      final k = uri.queryParameters['k'] ?? '';
      if (!isValidCode(code) || k.isEmpty) return null;
      final key = _unb64(k);
      if (key.length != 32) return null;
      return ParsedMusicQr(code: code, secretKey: key);
    } catch (_) {
      return null;
    }
  }

  /// Subclaves independientes para cifrar y autenticar.
  static Uint8List _subKey(Uint8List key, String label) => Uint8List.fromList(
        crypto.Hmac(crypto.sha256, key).convert(utf8.encode(label)).bytes,
      );

  static PaddedBlockCipher _cipher(bool encrypt, Uint8List key, Uint8List iv) {
    return PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
      ..init(
        encrypt,
        PaddedBlockCipherParameters<CipherParameters, CipherParameters?>(
          ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
          null,
        ),
      );
  }

  /// `v1.` + base64url(iv[16] | ciphertext | hmac[32]).
  static String encryptPayload(Map<String, dynamic> payload, Uint8List key) {
    final iv = _randomBytes(16);
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final ct = _cipher(true, _subKey(key, 'enc'), iv).process(plain);
    final body = Uint8List.fromList([...iv, ...ct]);
    final mac = crypto.Hmac(crypto.sha256, _subKey(key, 'mac')).convert(body).bytes;
    return 'v1.${_b64([...body, ...mac])}';
  }

  static Map<String, dynamic>? decryptPayload(String encoded, Uint8List key) {
    try {
      if (!encoded.startsWith('v1.')) return null;
      final all = _unb64(encoded.substring(3));
      if (all.length < 16 + 16 + 32) return null;
      final body = all.sublist(0, all.length - 32);
      final mac = all.sublist(all.length - 32);
      final expected =
          crypto.Hmac(crypto.sha256, _subKey(key, 'mac')).convert(body).bytes;
      var diff = 0;
      for (var i = 0; i < 32; i++) {
        diff |= mac[i] ^ expected[i];
      }
      if (diff != 0) return null;
      final iv = body.sublist(0, 16);
      final plain = _cipher(false, _subKey(key, 'enc'), iv).process(body.sublist(16));
      final decoded = jsonDecode(utf8.decode(plain));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Lado PC (sin sesión)
  // ---------------------------------------------------------------------------

  Future<MusicPairingSession?> createPcSession() async {
    final auth = InutilAuthService.instance;
    final code = generateCode();
    final key = generateSecretKey();
    final now = DateTime.now();
    final expiresAt = now.add(sessionTtl);
    try {
      final ok = await InutilFirestoreService.instance.setDocument(
        '$collection/$code',
        {
          'status': 'pending',
          'deviceId': auth.deviceId,
          'deviceName': auth.deviceName,
          'createdAt': now,
          'expiresAt': expiresAt,
        },
      );
      if (!ok) return null;
      return MusicPairingSession(
        code: code,
        secretKey: key,
        qrUri: buildQrUri(code, key),
        expiresAt: expiresAt,
      );
    } catch (e) {
      debugPrint('[MusicQrPairing] No se pudo crear la sesión: $e');
      return null;
    }
  }

  Future<MusicPairingPollResult> pollPcSession(MusicPairingSession session) async {
    if (session.isExpired) {
      return const MusicPairingPollResult(MusicPairingPollState.expired);
    }
    try {
      final doc = await InutilFirestoreService.instance
          .getDocument('$collection/${session.code}');
      if (doc == null) {
        return const MusicPairingPollResult(MusicPairingPollState.expired);
      }
      if (doc['status'] != 'approved') {
        return const MusicPairingPollResult(MusicPairingPollState.waiting);
      }
      final key = doc['mode'] == 'code'
          ? deriveManualCodeKey(session.code)
          : session.secretKey;
      final payload = decryptPayload(doc['payload'] as String? ?? '', key);
      if (payload == null) {
        return const MusicPairingPollResult(
          MusicPairingPollState.failed,
          message: 'No se pudo descifrar la sesión enviada por el celular.',
        );
      }
      return MusicPairingPollResult(MusicPairingPollState.approved,
          payload: payload);
    } catch (e) {
      // Sin red momentáneamente: se reintenta en el siguiente sondeo.
      debugPrint('[MusicQrPairing] Sondeo sin respuesta: $e');
      return const MusicPairingPollResult(MusicPairingPollState.waiting);
    }
  }

  Future<void> cleanupPcSession(MusicPairingSession? session) async {
    if (session == null) return;
    try {
      await InutilFirestoreService.instance
          .deleteDocument('$collection/${session.code}');
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Lado celular (con sesión)
  // ---------------------------------------------------------------------------

  /// Aprueba la PC a partir del contenido del QR. `null` = éxito.
  Future<String?> approveFromQr(String raw) async {
    final parsed = parseQrUri(raw);
    if (parsed == null) {
      return 'Este QR no es de Inútil Music. Escanea el código que muestra tu PC.';
    }
    return _approve(parsed.code, parsed.secretKey, mode: 'qr');
  }

  /// Aprueba la PC escribiendo el código `XXXX-XXXX`. `null` = éxito.
  Future<String?> approveWithCode(String raw) async {
    final code = normalizeCode(raw);
    if (!isValidCode(code)) {
      return 'Escribe los 8 caracteres que muestra tu PC (ej. ABCD-2345).';
    }
    return _approve(code, deriveManualCodeKey(code), mode: 'code');
  }

  Future<String?> _approve(String code, Uint8List key, {required String mode}) async {
    final auth = InutilAuthService.instance;
    final user = auth.currentUser;
    if (user == null || user.refreshToken.isEmpty) {
      return 'Necesitas tener sesión iniciada en este dispositivo.';
    }
    if (!auth.isAccessAllowed) {
      return 'Tu cuenta debe estar activa para vincular una PC.';
    }
    try {
      await auth.ensureFreshSession();
      final existing =
          await InutilFirestoreService.instance.getDocument('$collection/$code');
      if (existing == null) {
        return 'No se encontró ese código o ya expiró. Genera uno nuevo en la PC.';
      }
      if (existing['status'] != 'pending') {
        return 'Este código ya fue usado. Genera uno nuevo en la PC.';
      }
      final expiresAt = existing['expiresAt'];
      if (expiresAt is DateTime && DateTime.now().isAfter(expiresAt)) {
        return 'El código expiró. Genera uno nuevo en la PC.';
      }
      final current = auth.currentUser ?? user;
      final encrypted = encryptPayload({
        'refreshToken': current.refreshToken,
        'email': current.email,
        'displayName': current.displayName,
        'uid': current.uid,
      }, key);
      final ok = await InutilFirestoreService.instance.setDocument(
        '$collection/$code',
        {
          'status': 'approved',
          'mode': mode,
          'payload': encrypted,
          'approvedByUid': current.uid,
          'approvedAt': DateTime.now(),
        },
      );
      if (!ok) {
        return 'No se pudo autorizar la PC. Verifica tu conexión e intenta de nuevo.';
      }
      return null;
    } catch (e) {
      debugPrint('[MusicQrPairing] Error aprobando PC: $e');
      return 'Error de conexión al vincular la PC. Intenta de nuevo.';
    }
  }
}
