import 'package:flutter/material.dart';

/// Indicador visual animado estilo YouTube / Spotify que aparece al hacer
/// doble toque rápido en los laterales del reproductor para saltar ±10s.
class DoubleTapSeekRipple extends StatefulWidget {
  const DoubleTapSeekRipple({
    super.key,
    required this.isForward,
    required this.seconds,
    required this.onAnimationComplete,
  });

  final bool isForward;
  final int seconds;
  final VoidCallback onAnimationComplete;

  @override
  State<DoubleTapSeekRipple> createState() => _DoubleTapSeekRippleState();
}

class _DoubleTapSeekRippleState extends State<DoubleTapSeekRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  static const Color _cyanNeon = Color(0xFF00E5FF);
  static const Color _purpleNeon = Color(0xFF7C4DFF);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.0),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 30,
      ),
    ]).animate(_controller);

    _controller.forward().then((_) {
      if (mounted) widget.onAnimationComplete();
    });
  }

  @override
  void didUpdateWidget(covariant DoubleTapSeekRipple oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seconds != widget.seconds) {
      _controller.forward(from: 0.2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isForward = widget.isForward;
    final text = '${isForward ? "+" : "-"}${widget.seconds}s';

    return Align(
      alignment: isForward ? Alignment.centerRight : Alignment.centerLeft,
      child: FadeTransition(
        opacity: _opacityAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            width: 140,
            height: 220,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  (isForward ? _cyanNeon : _purpleNeon).withValues(alpha: 0.22),
                  Colors.transparent,
                ],
                radius: 0.8,
              ),
              borderRadius: BorderRadius.horizontal(
                left: isForward ? const Radius.circular(100) : Radius.zero,
                right: isForward ? Radius.zero : const Radius.circular(100),
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isForward
                        ? Icons.fast_forward_rounded
                        : Icons.fast_rewind_rounded,
                    color: isForward ? _cyanNeon : _purpleNeon,
                    size: 38,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    text,
                    style: TextStyle(
                      color: isForward ? _cyanNeon : _purpleNeon,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: 0.5,
                      shadows: [
                        Shadow(
                          color: (isForward ? _cyanNeon : _purpleNeon)
                              .withValues(alpha: 0.6),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
