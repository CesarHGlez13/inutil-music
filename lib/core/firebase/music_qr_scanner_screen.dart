import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'music_qr_pairing_service.dart';

/// Abre el flujo de «Iniciar sesión en PC» desde un dispositivo con sesión.
///
/// En Android/iOS abre la cámara para escanear el QR; en el resto de
/// plataformas (o si el usuario lo prefiere) pide el código `XXXX-XXXX`.
Future<void> openPcLoginFlow(BuildContext context) async {
  final hasCamera = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  if (hasCamera) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MusicQrScannerScreen()),
    );
  } else {
    await showPcLoginCodeDialog(context);
  }
}

/// Diálogo para escribir el código de 8 caracteres que muestra la PC.
/// Devuelve `true` si la PC quedó autorizada.
Future<bool> showPcLoginCodeDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _PcCodeDialog(),
  );
  if (ok == true && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('PC autorizada. Iniciará sesión en unos segundos.'),
      ),
    );
  }
  return ok == true;
}

class _PcCodeDialog extends StatefulWidget {
  const _PcCodeDialog();

  @override
  State<_PcCodeDialog> createState() => _PcCodeDialogState();
}

class _PcCodeDialogState extends State<_PcCodeDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await MusicQrPairingService.instance.approveWithCode(
      _controller.text,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Iniciar sesión en PC'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Escribe el código de 8 caracteres que aparece debajo del QR en tu PC.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('pc-code-field'),
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            maxLength: 9,
            decoration: InputDecoration(
              hintText: 'ABCD-2345',
              errorText: _error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _busy ? null : _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('pc-code-submit'),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Autorizar'),
        ),
      ],
    );
  }
}

/// Escáner de cámara para el QR que muestra la app de escritorio.
class MusicQrScannerScreen extends StatefulWidget {
  const MusicQrScannerScreen({super.key});

  @override
  State<MusicQrScannerScreen> createState() => _MusicQrScannerScreenState();
}

class _MusicQrScannerScreenState extends State<MusicQrScannerScreen> {
  final MobileScannerController _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _processing = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _handleCode(String raw) async {
    if (_processing || _done || _error != null) return;
    setState(() => _processing = true);
    final error = await MusicQrPairingService.instance.approveFromQr(raw);
    if (!mounted) return;
    setState(() {
      _processing = false;
      _done = error == null;
      _error = error;
    });
    if (error == null) {
      await _scanner.stop();
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  Future<void> _manual() async {
    final ok = await showPcLoginCodeDialog(context);
    if (ok && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Iniciar sesión en PC'),
        actions: [
          IconButton(
            tooltip: 'Linterna',
            onPressed: () => _scanner.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_rounded),
          ),
          TextButton.icon(
            onPressed: _manual,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.keyboard_rounded, size: 18),
            label: const Text('Usar código'),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scanner,
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;
                if (value != null && value.isNotEmpty) {
                  _handleCode(value);
                  break;
                }
              }
            },
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.videocam_off_rounded,
                      color: Colors.white60,
                      size: 46,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No se pudo abrir la cámara',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _manual,
                      icon: const Icon(Icons.keyboard_rounded, size: 18),
                      label: const Text('Escribir código'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 248,
                height: 248,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _done ? const Color(0xFF18C75A) : accent,
                    width: 3,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xEE0E0E13),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white24),
              ),
              child: _buildStatus(accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatus(Color accent) {
    const title = TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w800,
    );
    const body = TextStyle(color: Colors.white70, fontSize: 12.5);
    if (_done) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, color: Color(0xFF18C75A), size: 36),
          SizedBox(height: 8),
          Text('¡PC autorizada!', style: title),
          SizedBox(height: 4),
          Text(
            'Tu PC iniciará sesión automáticamente en unos segundos.',
            textAlign: TextAlign.center,
            style: body,
          ),
        ],
      );
    }
    if (_processing) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: accent, strokeWidth: 2.5),
          const SizedBox(height: 10),
          const Text('Autorizando tu PC…', style: title),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Apunta al código QR de tu PC', style: title),
        const SizedBox(height: 4),
        const Text(
          'O toca «Usar código» para escribir las 8 letras.',
          textAlign: TextAlign.center,
          style: body,
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.redAccent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => setState(() => _error = null),
            child: const Text('Intentar de nuevo'),
          ),
        ],
      ],
    );
  }
}
