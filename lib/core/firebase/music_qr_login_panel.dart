import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/inutil_design_system.dart';
import 'firebase_auth_service.dart';
import 'music_qr_pairing_service.dart';

/// Tarjeta de inicio de sesión por QR para la app de escritorio.
///
/// Muestra un QR (y el código `XXXX-XXXX` como alternativa) que el celular con
/// sesión iniciada escanea desde «Mi cuenta → Iniciar sesión en PC». Sondea
/// cada 2 s hasta recibir la sesión cifrada, inicia sesión y borra el
/// documento temporal. Al expirar ofrece generar un código nuevo.
class MusicQrLoginPanel extends StatefulWidget {
  const MusicQrLoginPanel({super.key});

  /// true en Linux, Windows y macOS (la app de escritorio).
  static bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  /// Permite a los widget tests inyectar una sesión sin tocar la red.
  @visibleForTesting
  static Future<MusicPairingSession?> Function()? debugSessionFactory;

  @override
  State<MusicQrLoginPanel> createState() => _MusicQrLoginPanelState();
}

class _MusicQrLoginPanelState extends State<MusicQrLoginPanel> {
  final _service = MusicQrPairingService.instance;
  MusicPairingSession? _session;
  Timer? _pollTimer;
  bool _loading = true;
  bool _expired = false;
  bool _signingIn = false;
  bool _polling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (MusicQrLoginPanel.debugSessionFactory == null) {
      unawaited(_service.cleanupPcSession(_session));
    }
    super.dispose();
  }

  Future<void> _start() async {
    _pollTimer?.cancel();
    final previous = _session;
    setState(() {
      _loading = true;
      _expired = false;
      _error = null;
      _session = null;
    });
    // Las pruebas de widget inyectan su propia fábrica ([debugSessionFactory]);
    // sin ella se habla con Firestore normal y la pantalla tarda lo que tarde
    // la red.
    final factory = MusicQrLoginPanel.debugSessionFactory;
    if (factory == null) unawaited(_service.cleanupPcSession(previous));
    final session = await (factory ?? _service.createPcSession)();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _session = session;
      if (session == null) {
        _error = 'No se pudo generar el código. Revisa tu conexión a internet.';
      }
    });
    if (session != null && factory == null) {
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    }
  }

  Future<void> _poll() async {
    final session = _session;
    if (session == null || _polling || _signingIn) return;
    _polling = true;
    try {
      final result = await _service.pollPcSession(session);
      if (!mounted || session != _session) return;
      switch (result.state) {
        case MusicPairingPollState.waiting:
          break;
        case MusicPairingPollState.expired:
          _pollTimer?.cancel();
          setState(() => _expired = true);
        case MusicPairingPollState.failed:
          _pollTimer?.cancel();
          setState(() => _error = result.message);
        case MusicPairingPollState.approved:
          _pollTimer?.cancel();
          setState(() => _signingIn = true);
          final payload = result.payload!;
          unawaited(_service.cleanupPcSession(session));
          final error = await InutilAuthService.instance
              .signInWithPairedRefreshToken(
                payload['refreshToken'] as String? ?? '',
                emailHint: payload['email'] as String? ?? '',
                displayNameHint: payload['displayName'] as String? ?? '',
              );
          if (!mounted) return;
          setState(() {
            _signingIn = false;
            _error = error;
          });
      }
    } finally {
      _polling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('pc-qr-login-panel'),
      width: 320,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: InutilDesignSystem.surfaceElevated.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: InutilDesignSystem.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.qr_code_2_rounded,
                color: InutilDesignSystem.accentCyan,
                size: 22,
              ),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Entrar con tu celular',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'En la app del celular abre Mi cuenta → «Iniciar sesión en PC» y escanea este código.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: InutilDesignSystem.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          _buildQrArea(),
          const SizedBox(height: 14),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildQrArea() {
    final session = _session;
    Widget child;
    if (_loading || _signingIn) {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: InutilDesignSystem.primaryNeon,
          ),
          if (_signingIn) ...[
            const SizedBox(height: 12),
            const Text(
              'Iniciando sesión…',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      );
    } else if (session == null || _expired) {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _expired ? Icons.timer_off_rounded : Icons.wifi_off_rounded,
            color: Colors.black54,
            size: 40,
          ),
          const SizedBox(height: 10),
          Text(
            _expired ? 'El código expiró' : 'Sin código',
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const ValueKey('pc-qr-refresh'),
            onPressed: _start,
            style: FilledButton.styleFrom(
              backgroundColor: InutilDesignSystem.primaryNeon,
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Generar nuevo'),
          ),
        ],
      );
    } else {
      child = QrImageView(
        data: session.qrUri,
        size: 200,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.white,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
      );
    }
    return Container(
      width: 232,
      height: 232,
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }

  Widget _buildFooter() {
    final session = _session;
    if (_error != null) {
      return Column(
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.redAccent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextButton(onPressed: _start, child: const Text('Reintentar')),
        ],
      );
    }
    if (session == null || _expired) return const SizedBox.shrink();
    return Column(
      children: [
        const Text(
          '¿Sin cámara? Escribe este código en el celular:',
          textAlign: TextAlign.center,
          style: TextStyle(color: InutilDesignSystem.textMuted, fontSize: 11.5),
        ),
        const SizedBox(height: 6),
        SelectableText(
          session.displayCode,
          key: const ValueKey('pc-qr-display-code'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Válido 3 minutos · cifrado de extremo a extremo',
          style: TextStyle(color: InutilDesignSystem.textMuted, fontSize: 10.5),
        ),
      ],
    );
  }
}
