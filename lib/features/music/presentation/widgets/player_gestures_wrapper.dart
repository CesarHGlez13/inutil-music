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

class _PlayerGesturesWrapperState extends State<PlayerGesturesWrapper>
    with SingleTickerProviderStateMixin {
  Offset _dragTotalDelta = Offset.zero;
  double _horizontalDragOffset = 0.0;
  bool _isHorizontalDrag = false;
  late final AnimationController _slideController;
  Animation<double>? _slideAnimation;

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
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _slideController.addListener(() {
      if (_slideAnimation != null) {
        setState(() {
          _horizontalDragOffset = _slideAnimation!.value;
        });
      }
    });
  }

  @override
  void dispose() {
    _slideController.dispose();
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
    _slideController.stop();
    _dragTotalDelta = Offset.zero;
    _horizontalDragOffset = 0.0;
    _isHorizontalDrag = false;
    _lastTapTime = null;
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    _dragTotalDelta += details.delta;

    final dx = _dragTotalDelta.dx;
    final dy = _dragTotalDelta.dy;

    // Detectar si el gesto horizontal domina
    if (!_isHorizontalDrag && dx.abs() > 10 && dx.abs() > dy.abs() * 1.1) {
      _isHorizontalDrag = true;
    }

    if (_isHorizontalDrag) {
      setState(() {
        _horizontalDragOffset = dx;
      });
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    if (!widget.enabled) return;

    final dx = _dragTotalDelta.dx;
    final dy = _dragTotalDelta.dy;
    final vx = details.velocity.pixelsPerSecond.dx;
    final vy = details.velocity.pixelsPerSecond.dy;
    final screenWidth = MediaQuery.maybeSizeOf(context)?.width ?? 400.0;

    if (_isHorizontalDrag || dx.abs() > dy.abs() * 1.2) {
      // Horizontal
      if (dx < -_horizontalThreshold || vx < -300) {
        // Deslizar hacia la izquierda -> Siguiente pista
        _animateTrackTransition(
          from: _horizontalDragOffset,
          exitTo: -screenWidth,
          entryFrom: screenWidth,
          onMidpoint: widget.onNextTrack,
        );
      } else if (dx > _horizontalThreshold || vx > 300) {
        // Deslizar hacia la derecha -> Pista anterior
        _animateTrackTransition(
          from: _horizontalDragOffset,
          exitTo: screenWidth,
          entryFrom: -screenWidth,
          onMidpoint: widget.onPreviousTrack,
        );
      } else {
        // Cancelado: volver al centro con resorte suave
        _animateSpringBack();
      }
    } else if (dy.abs() > dx.abs() * 1.2) {
      // Vertical
      if (dy > _verticalThreshold || vy > 300) {
        widget.onMinimize?.call();
      } else if (dy < -_verticalThreshold || vy < -300) {
        widget.onOpenLyrics?.call();
      }
      _animateSpringBack();
    } else {
      _animateSpringBack();
    }

    _dragTotalDelta = Offset.zero;
    _isHorizontalDrag = false;
  }

  void _animateTrackTransition({
    required double from,
    required double exitTo,
    required double entryFrom,
    required VoidCallback? onMidpoint,
  }) {
    // Fase 1: salida rápida de la pista actual
    _slideAnimation = Tween<double>(begin: from, end: exitTo).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeInQuad),
    );
    _slideController.duration = const Duration(milliseconds: 110);
    _slideController.forward(from: 0.0).then((_) {
      if (!mounted) return;
      onMidpoint?.call();

      // Fase 2: entrada fluida de la nueva pista desde el lado opuesto
      _slideAnimation = Tween<double>(begin: entryFrom, end: 0.0).animate(
        CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
      );
      _slideController.duration = const Duration(milliseconds: 220);
      _slideController.forward(from: 0.0);
    });
  }

  void _animateSpringBack() {
    if (_horizontalDragOffset == 0.0) return;
    _slideAnimation = Tween<double>(begin: _horizontalDragOffset, end: 0.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );
    _slideController.duration = const Duration(milliseconds: 180);
    _slideController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.maybeSizeOf(context)?.width ?? 400.0;
    final dragFraction = (1.0 - (_horizontalDragOffset.abs() / (screenWidth * 1.4))).clamp(0.45, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: _handleTapDown,
      onPanStart: _handlePanStart,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: _handlePanEnd,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Transform.translate(
            offset: Offset(_horizontalDragOffset, 0),
            child: Opacity(
              opacity: dragFraction,
              child: widget.child,
            ),
          ),
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
