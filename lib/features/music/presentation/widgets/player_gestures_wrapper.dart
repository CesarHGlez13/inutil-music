import 'dart:async';
import 'package:flutter/material.dart';
import 'double_tap_seek_ripple.dart';

/// Envoltorio interactivo para el reproductor de pantalla completa.
///
/// Soporta:
/// - Deslizamiento horizontal: Cambiar pista (Siguiente / Anterior).
/// - Deslizamiento vertical abajo (> 80px): Minimizar reproductor.
/// - Deslizamiento vertical arriba (> 80px): Mostrar letras sincronizadas.
/// - Doble toque en mitades laterales: Saltar ±10s con acumulación rápida (+20s, +30s...).
class PlayerGesturesWrapper extends StatefulWidget {
  const PlayerGesturesWrapper({
    super.key,
    required this.child,
    this.onNextTrack,
    this.onPreviousTrack,
    this.onMinimize,
    this.onOpenLyrics,
    this.onSeekRelative,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onNextTrack;
  final VoidCallback? onPreviousTrack;
  final VoidCallback? onMinimize;
  final VoidCallback? onOpenLyrics;
  final ValueChanged<Duration>? onSeekRelative;
  final bool enabled;

  @override
  State<PlayerGesturesWrapper> createState() => _PlayerGesturesWrapperState();
}

class _PlayerGesturesWrapperState extends State<PlayerGesturesWrapper> {
  Offset _dragTotalDelta = Offset.zero;

  // Seguimiento de doble toque acumulativo
  DateTime? _lastTapTime;
  Offset? _lastTapPosition;
  bool? _activeRippleForward;
  int _accumulatedSeconds = 0;
  Timer? _seekResetTimer;

  static const double _horizontalThreshold = 60.0;
  static const double _verticalThreshold = 80.0;
  static const Duration _doubleTapMaxInterval = Duration(milliseconds: 400);

  @override
  void dispose() {
    _seekResetTimer?.cancel();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (!widget.enabled) return;

    final now = DateTime.now();
    final localPos = details.localPosition;

    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) <= _doubleTapMaxInterval &&
        _lastTapPosition != null &&
        (localPos - _lastTapPosition!).distance < 60) {
      // Doble toque (o toques consecutivos rápidos)
      final size = context.size ?? Size.zero;
      final isForward = localPos.dx > (size.width / 2);

      if (_activeRippleForward == isForward && _accumulatedSeconds > 0) {
        _accumulatedSeconds += 10;
      } else {
        _accumulatedSeconds = 10;
        _activeRippleForward = isForward;
      }

      _seekResetTimer?.cancel();
      _seekResetTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) {
          setState(() {
            _activeRippleForward = null;
            _accumulatedSeconds = 0;
          });
        }
      });

      widget.onSeekRelative?.call(
        Duration(seconds: isForward ? _accumulatedSeconds : -_accumulatedSeconds),
      );

      setState(() {});
    }

    _lastTapTime = now;
    _lastTapPosition = localPos;
  }

  void _handlePanStart(DragStartDetails details) {
    _dragTotalDelta = Offset.zero;
    _lastTapTime = null;
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    _dragTotalDelta += details.delta;
  }

  void _handlePanEnd(DragEndDetails details) {
    if (!widget.enabled) return;

    final dx = _dragTotalDelta.dx;
    final dy = _dragTotalDelta.dy;
    final vx = details.velocity.pixelsPerSecond.dx;
    final vy = details.velocity.pixelsPerSecond.dy;

    // Comprobar dirección dominante para evitar disparos en gestos diagonales
    if (dx.abs() > dy.abs() * 1.2) {
      // Horizontal
      if (dx < -_horizontalThreshold || vx < -300) {
        widget.onNextTrack?.call();
      } else if (dx > _horizontalThreshold || vx > 300) {
        widget.onPreviousTrack?.call();
      }
    } else if (dy.abs() > dx.abs() * 1.2) {
      // Vertical
      if (dy > _verticalThreshold || vy > 300) {
        widget.onMinimize?.call();
      } else if (dy < -_verticalThreshold || vy < -300) {
        widget.onOpenLyrics?.call();
      }
    }

    _dragTotalDelta = Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: _handleTapDown,
      onPanStart: _handlePanStart,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: _handlePanEnd,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_activeRippleForward != null && _accumulatedSeconds > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: DoubleTapSeekRipple(
                  key: ValueKey('seek-ripple-$_activeRippleForward-$_accumulatedSeconds'),
                  isForward: _activeRippleForward!,
                  seconds: _accumulatedSeconds,
                  onAnimationComplete: () {
                    // La animación se completa
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
