import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Canvas generativo en GPU que renderiza una malla de gradientes líquidos
/// orgánicos y partículas flotantes neón. Reemplaza de forma 100% autónoma y
/// sin consumo de red a scrapers externos caídos (`spotycovs.lol`).
class GenerativeMeshCanvas extends StatefulWidget {
  const GenerativeMeshCanvas({
    super.key,
    this.primaryColor,
    this.secondaryColor,
    this.isPlaying = true,
  });

  final Color? primaryColor;
  final Color? secondaryColor;
  final bool isPlaying;

  @override
  State<GenerativeMeshCanvas> createState() => _GenerativeMeshCanvasState();
}

class _GenerativeMeshCanvasState extends State<GenerativeMeshCanvas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const Color _defaultCyan = Color(0xFF00E5FF);
  static const Color _defaultPurple = Color(0xFF7C4DFF);
  static const Color _deepBackground = Color(0xFF0A0B10);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );

    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant GenerativeMeshCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Asegura que el color tenga suficiente vivacidad y contraste,
  /// evitando negros o blancos planos que degradarían la estética Inutix.
  Color _resolveColor(Color? color, Color fallback) {
    if (color == null) return fallback;
    final luminance = color.computeLuminance();
    if (luminance < 0.08) {
      // Demasiado oscuro / negro: mezclar con el fallback neón
      return Color.alphaBlend(fallback.withValues(alpha: 0.65), color);
    }
    if (luminance > 0.85) {
      // Demasiado claro / blanco: atenuar
      return Color.alphaBlend(color.withValues(alpha: 0.5), fallback);
    }
    return color;
  }

  @override
  Widget build(BuildContext context) {
    final c1 = _resolveColor(widget.primaryColor, _defaultCyan);
    final c2 = _resolveColor(widget.secondaryColor, _defaultPurple);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _GenerativeMeshPainter(
              progress: _controller.value,
              color1: c1,
              color2: c2,
              backgroundColor: _deepBackground,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _GenerativeMeshPainter extends CustomPainter {
  _GenerativeMeshPainter({
    required this.progress,
    required this.color1,
    required this.color2,
    required this.backgroundColor,
  });

  final double progress;
  final Color color1;
  final Color color2;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // Fondo profundo carbón Inutix
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = backgroundColor,
    );

    final angle = progress * 2 * math.pi;

    // 4 nodos de color fluidos con movimiento sinusoidal orgánico
    final node1 = Offset(
      w * 0.25 + math.sin(angle) * (w * 0.18),
      h * 0.28 + math.cos(angle * 0.8) * (h * 0.15),
    );
    final node2 = Offset(
      w * 0.78 + math.cos(angle * 0.9) * (w * 0.16),
      h * 0.38 + math.sin(angle * 1.1) * (h * 0.14),
    );
    final node3 = Offset(
      w * 0.32 + math.sin(angle * 1.2) * (w * 0.15),
      h * 0.74 + math.cos(angle) * (h * 0.16),
    );
    final node4 = Offset(
      w * 0.72 + math.cos(angle * 0.7) * (w * 0.18),
      h * 0.78 + math.sin(angle * 0.85) * (h * 0.15),
    );

    final paint1 = Paint()
      ..shader = RadialGradient(
        colors: [
          color1.withValues(alpha: 0.38),
          color1.withValues(alpha: 0.15),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: node1, radius: w * 0.65))
      ..blendMode = BlendMode.screen;

    final paint2 = Paint()
      ..shader = RadialGradient(
        colors: [
          color2.withValues(alpha: 0.35),
          color2.withValues(alpha: 0.12),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: node2, radius: w * 0.62))
      ..blendMode = BlendMode.screen;

    final paint3 = Paint()
      ..shader = RadialGradient(
        colors: [
          color2.withValues(alpha: 0.30),
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: node3, radius: w * 0.58))
      ..blendMode = BlendMode.screen;

    final paint4 = Paint()
      ..shader = RadialGradient(
        colors: [
          color1.withValues(alpha: 0.32),
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: node4, radius: w * 0.60))
      ..blendMode = BlendMode.screen;

    canvas.drawCircle(node1, w * 0.65, paint1);
    canvas.drawCircle(node2, w * 0.62, paint2);
    canvas.drawCircle(node3, w * 0.58, paint3);
    canvas.drawCircle(node4, w * 0.60, paint4);

    // Micro-partículas estelares sutiles Inutix
    final particlePaint = Paint()..color = Colors.white.withValues(alpha: 0.25);
    for (int i = 0; i < 12; i++) {
      final pPhase = (progress + (i * 0.083)) % 1.0;
      final px = (w * (0.1 + (i * 0.075) % 0.8)) + math.sin(angle + i) * 15;
      final py = h * (1.0 - pPhase);
      final pRadius = 1.2 + (i % 3) * 0.6;
      canvas.drawCircle(Offset(px, py), pRadius, particlePaint);
    }

    // Viñeta periférica para asegurar máxima legibilidad de textos y controles
    final vignettePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          backgroundColor.withValues(alpha: 0.45),
          backgroundColor.withValues(alpha: 0.85),
        ],
        stops: const [0.55, 0.85, 1.0],
      ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, vignettePaint);
  }

  @override
  bool shouldRepaint(covariant _GenerativeMeshPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color1 != color1 ||
        oldDelegate.color2 != color2;
  }
}
