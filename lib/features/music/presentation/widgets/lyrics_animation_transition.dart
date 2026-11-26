import 'package:flutter/material.dart';

import '../../../../core/platform/app_platform.dart';
import '../providers/lyrics_animation_style.dart';

// Keep lyric changes long enough to read as one continuous movement, while
// finishing quickly enough that a short line does not lag behind playback.
const _kLyricsSmoothDuration = Duration(milliseconds: 580);
const _kLyricsSlideDuration = Duration(milliseconds: 550);
const _kLyricsHighlightDuration = Duration(milliseconds: 570);
const _kLyricsKaraokeDuration = Duration(milliseconds: 540);
const _kLyricsCinematicDuration = Duration(milliseconds: 620);
const _kLyricsZoomDuration = Duration(milliseconds: 560);
const _kLyricsExitDuration = Duration(milliseconds: 460);

const _kLyricsSmoothInactiveScale = 0.965;
const _kLyricsSmoothInactiveOpacity = 0.58;

const _kLyricsSlideOffsetPx = 34.0;
const _kLyricsSlideInactiveOpacity = 0.65;

const _kLyricsHighlightActiveBackgroundAlpha = 0.12;
const _kLyricsHighlightActiveShadowAlpha = 0.22;
const _kLyricsHighlightActiveScale = 1.01;
const _kLyricsHighlightInactiveScale = 0.98;

const _kLyricsKaraokeActiveScale = 1.035;
const _kLyricsKaraokeInactiveScale = 0.945;
const _kLyricsKaraokeInactiveOpacity = 0.50;

const _kLyricsCinematicActiveScale = 1.04;
const _kLyricsCinematicInactiveScale = 0.935;
const _kLyricsCinematicInactiveOpacity = 0.42;

const _kLyricsZoomActiveScale = 1.045;
const _kLyricsZoomInactiveScale = 0.80;
const _kLyricsZoomInactiveOpacity = 0.34;

class LyricsAnimationTransition extends StatefulWidget {
  const LyricsAnimationTransition({
    required this.style,
    required this.active,
    required this.accent,
    required this.child,
    this.alignment = Alignment.centerLeft,
    super.key,
  });

  final LyricsAnimationStyle style;
  final bool active;
  final Color accent;
  final Widget child;
  final Alignment alignment;

  @override
  State<LyricsAnimationTransition> createState() =>
      _LyricsAnimationTransitionState();
}

class _LyricsAnimationTransitionState extends State<LyricsAnimationTransition>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _slideController;
  late final AnimationController _shimmerController;
  late Animation<double> _animation;
  bool _disableAnimations = false;

  AnimationBehavior get _behavior => AppPlatform.isFlutterTest
      ? AnimationBehavior.normal
      : AnimationBehavior.preserve;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _durationFor(widget.style),
      reverseDuration: _kLyricsExitDuration,
      animationBehavior: _behavior,
    );
    _slideController = AnimationController(
      vsync: this,
      duration: _kLyricsSlideDuration,
      value: 1,
      animationBehavior: _behavior,
    );
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
      animationBehavior: _behavior,
    );
    _animation = _buildTween(widget.style);
    if (widget.active) {
      _controller.value = 1;
      _syncShimmer();
    }
  }

  void _syncShimmer() {
    final shouldShimmer =
        !_disableAnimations &&
        widget.active &&
        widget.style == LyricsAnimationStyle.karaoke;
    if (shouldShimmer) {
      if (!_shimmerController.isAnimating) {
        _shimmerController.repeat();
      }
    } else if (_shimmerController.isAnimating) {
      _shimmerController.stop();
      _shimmerController.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations =
        AppPlatform.isFlutterTest && MediaQuery.disableAnimationsOf(context);
    if (_disableAnimations == disableAnimations) {
      return;
    }
    _disableAnimations = disableAnimations;
    _controller.stop();
    _slideController.stop();
    _controller.value = widget.active ? 1 : 0;
    _slideController.value = 1;
    _syncShimmer();
  }

  @override
  void didUpdateWidget(covariant LyricsAnimationTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final styleChanged = oldWidget.style != widget.style;
    final wasPartiallyVisible = _controller.value > 0;
    if (styleChanged) {
      _controller.duration = _durationFor(widget.style);
      _controller.reverseDuration = _kLyricsExitDuration;
      _animation = _buildTween(widget.style);
    }
    if (_disableAnimations) {
      _controller.stop();
      _slideController.stop();
      _controller.value = widget.active ? 1 : 0;
      _slideController.value = 1;
      _syncShimmer();
      return;
    }
    if (widget.active != oldWidget.active || styleChanged) {
      _controller.stop();
      if (widget.active) {
        if (styleChanged) {
          _controller.forward(from: 0);
        } else {
          // Preserve the current value when playback quickly crosses a line
          // boundary in either direction. Retargeting the animation avoids a
          // visible opacity/scale snap during seeks and short lyric lines.
          _controller.forward();
        }
      } else if (styleChanged) {
        _controller.value = 0;
      } else {
        _controller.reverse();
      }
    }
    if (widget.style == LyricsAnimationStyle.slide) {
      if (widget.active && (!oldWidget.active || styleChanged)) {
        if (wasPartiallyVisible && !styleChanged) {
          _slideController.forward();
        } else {
          _slideController.forward(from: 0);
        }
      } else if (!widget.active) {
        // If a short line deactivates before finishing its entrance, keep
        // moving toward the resting position instead of snapping to it.
        _slideController.forward();
      }
    } else {
      _slideController
        ..stop()
        ..value = 1;
    }
    _syncShimmer();
  }

  @override
  void dispose() {
    _controller.dispose();
    _slideController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  static Duration _durationFor(LyricsAnimationStyle style) {
    return switch (style) {
      LyricsAnimationStyle.smooth => _kLyricsSmoothDuration,
      LyricsAnimationStyle.slide => _kLyricsSlideDuration,
      LyricsAnimationStyle.highlight => _kLyricsHighlightDuration,
      LyricsAnimationStyle.karaoke => _kLyricsKaraokeDuration,
      LyricsAnimationStyle.cinematic => _kLyricsCinematicDuration,
      LyricsAnimationStyle.zoom => _kLyricsZoomDuration,
    };
  }

  Animation<double> _buildTween(LyricsAnimationStyle style) {
    return CurvedAnimation(
      parent: _controller,
      curve: switch (style) {
        LyricsAnimationStyle.karaoke => const Cubic(0.22, 1.0, 0.32, 1.0),
        LyricsAnimationStyle.cinematic => Curves.easeOutQuart,
        LyricsAnimationStyle.zoom => const Cubic(0.20, 1.12, 0.30, 1.0),
        _ => Curves.easeOutCubic,
      },
      reverseCurve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (AppPlatform.isFlutterTest && MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    final alignment = widget.alignment;
    final accent = widget.accent;
    return AnimatedBuilder(
      animation: Listenable.merge([
        _animation,
        _slideController,
        _shimmerController,
      ]),
      builder: (context, child) {
        final value = _animation.value;
        return switch (widget.style) {
          LyricsAnimationStyle.smooth => Opacity(
            opacity: lerpDouble(_kLyricsSmoothInactiveOpacity, 1, value),
            child: Transform.translate(
              offset: Offset(0, lerpDouble(4.0, 0.0, value)),
              child: Transform.scale(
                scale: lerpDouble(_kLyricsSmoothInactiveScale, 1.015, value),
                alignment: alignment,
                child: child,
              ),
            ),
          ),
          LyricsAnimationStyle.slide => Opacity(
            opacity: lerpDouble(_kLyricsSlideInactiveOpacity, 1, value),
            child: Transform.translate(
              offset: Offset(
                0,
                _kLyricsSlideOffsetPx * (1 - _slideController.value),
              ),
              child: child,
            ),
          ),
          LyricsAnimationStyle.highlight => DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withValues(
                alpha: _kLyricsHighlightActiveBackgroundAlpha * value,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: value == 0
                  ? null
                  : [
                      BoxShadow(
                        color: accent.withValues(
                          alpha: _kLyricsHighlightActiveShadowAlpha * value,
                        ),
                        blurRadius: 20 * value,
                        spreadRadius: value,
                      ),
                    ],
            ),
            child: Transform.scale(
              scale: lerpDouble(
                _kLyricsHighlightInactiveScale,
                _kLyricsHighlightActiveScale,
                value,
              ),
              alignment: alignment,
              child: child,
            ),
          ),
          LyricsAnimationStyle.karaoke => Opacity(
            opacity: lerpDouble(_kLyricsKaraokeInactiveOpacity, 1.0, value),
            child: Transform.translate(
              offset: Offset(0, lerpDouble(8.0, -2.0, value)),
              child: Transform.scale(
                scale: lerpDouble(
                  _kLyricsKaraokeInactiveScale,
                  _kLyricsKaraokeActiveScale,
                  value,
                ),
                alignment: alignment,
                child: value > 0.35
                    ? ShaderMask(
                        blendMode: BlendMode.srcATop,
                        shaderCallback: (bounds) {
                          final sweep = (_shimmerController.value * 2.4) - 0.7;
                          return LinearGradient(
                            begin: Alignment(sweep - 0.5, -0.2),
                            end: Alignment(sweep + 0.5, 0.2),
                            colors: [
                              Colors.transparent,
                              Color.alphaBlend(
                                Colors.white.withValues(alpha: 0.55),
                                accent,
                              ).withValues(alpha: 0.42 * value),
                              Colors.transparent,
                            ],
                          ).createShader(bounds);
                        },
                        child: child,
                      )
                    : child,
              ),
            ),
          ),
          LyricsAnimationStyle.cinematic => Opacity(
            opacity: lerpDouble(_kLyricsCinematicInactiveOpacity, 1.0, value),
            child: Transform.translate(
              offset: Offset(0, lerpDouble(6.0, -3.0, value)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: value > 0.15
                      ? Border.all(
                          color: Colors.white.withValues(alpha: 0.14 * value),
                          width: 0.8,
                        )
                      : null,
                  gradient: value > 0.1
                      ? LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            accent.withValues(alpha: 0.16 * value),
                            Colors.white.withValues(alpha: 0.05 * value),
                            Colors.transparent,
                          ],
                        )
                      : null,
                ),
                child: Transform.scale(
                  scale: lerpDouble(
                    _kLyricsCinematicInactiveScale,
                    _kLyricsCinematicActiveScale,
                    value,
                  ),
                  alignment: alignment,
                  child: child,
                ),
              ),
            ),
          ),
          LyricsAnimationStyle.zoom => Opacity(
            opacity: lerpDouble(
              _kLyricsZoomInactiveOpacity,
              1.0,
              value.clamp(0.0, 1.0),
            ),
            child: Transform.translate(
              offset: Offset(0, lerpDouble(6.0, -3.0, value)),
              child: Transform.scale(
                scale: lerpDouble(
                  _kLyricsZoomInactiveScale,
                  _kLyricsZoomActiveScale,
                  value,
                ),
                alignment: alignment,
                child: child,
              ),
            ),
          ),
        };
      },
      child: widget.child,
    );
  }
}

double lerpDouble(double begin, double end, double t) {
  return begin + (end - begin) * t;
}

class LyricsAnimationPreviewTransition extends StatelessWidget {
  const LyricsAnimationPreviewTransition({
    required this.style,
    required this.accent,
    required this.child,
    this.alignment = Alignment.centerLeft,
    super.key,
  });

  final LyricsAnimationStyle style;
  final Color accent;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (AppPlatform.isFlutterTest && MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: _kDurationForPreview(style),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return switch (style) {
          LyricsAnimationStyle.smooth => Opacity(
            opacity: value,
            child: Transform.scale(
              scale:
                  _kLyricsSmoothInactiveScale +
                  ((1 - _kLyricsSmoothInactiveScale) * value),
              alignment: alignment,
              child: child,
            ),
          ),
          LyricsAnimationStyle.slide => Opacity(
            opacity: lerpDouble(_kLyricsSlideInactiveOpacity, 1, value),
            child: Transform.translate(
              offset: Offset(0, _kLyricsSlideOffsetPx * (1 - value)),
              child: child,
            ),
          ),
          LyricsAnimationStyle.highlight => DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withValues(
                alpha: _kLyricsHighlightActiveBackgroundAlpha * value,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: value == 0
                  ? null
                  : [
                      BoxShadow(
                        color: accent.withValues(
                          alpha: _kLyricsHighlightActiveShadowAlpha * value,
                        ),
                        blurRadius: 18 * value,
                        spreadRadius: value,
                      ),
                    ],
            ),
            child: Transform.scale(
              scale:
                  _kLyricsHighlightInactiveScale +
                  ((_kLyricsHighlightActiveScale -
                          _kLyricsHighlightInactiveScale) *
                      value),
              alignment: alignment,
              child: child,
            ),
          ),
          LyricsAnimationStyle.karaoke => Opacity(
            opacity: lerpDouble(_kLyricsKaraokeInactiveOpacity, 1, value),
            child: Transform.translate(
              offset: Offset(0, lerpDouble(8.0, -2.0, value)),
              child: Transform.scale(
                scale: lerpDouble(
                  _kLyricsKaraokeInactiveScale,
                  _kLyricsKaraokeActiveScale,
                  value,
                ),
                alignment: alignment,
                child: child,
              ),
            ),
          ),
          LyricsAnimationStyle.cinematic => Opacity(
            opacity: lerpDouble(_kLyricsCinematicInactiveOpacity, 1, value),
            child: Transform.translate(
              offset: Offset(0, lerpDouble(6.0, -3.0, value)),
              child: Transform.scale(
                scale: lerpDouble(
                  _kLyricsCinematicInactiveScale,
                  _kLyricsCinematicActiveScale,
                  value,
                ),
                alignment: alignment,
                child: child,
              ),
            ),
          ),
          LyricsAnimationStyle.zoom => Opacity(
            opacity: lerpDouble(
              _kLyricsZoomInactiveOpacity,
              1,
              value.clamp(0.0, 1.0),
            ),
            child: Transform.translate(
              offset: Offset(0, lerpDouble(6.0, -3.0, value)),
              child: Transform.scale(
                scale: lerpDouble(0.76, 1.14, value),
                alignment: alignment,
                child: child,
              ),
            ),
          ),
        };
      },
      child: child,
    );
  }

  static Duration _kDurationForPreview(LyricsAnimationStyle style) {
    return switch (style) {
      LyricsAnimationStyle.smooth => _kLyricsSmoothDuration,
      LyricsAnimationStyle.slide => _kLyricsSlideDuration,
      LyricsAnimationStyle.highlight => _kLyricsHighlightDuration,
      LyricsAnimationStyle.karaoke => _kLyricsKaraokeDuration,
      LyricsAnimationStyle.cinematic => _kLyricsCinematicDuration,
      LyricsAnimationStyle.zoom => _kLyricsZoomDuration,
    };
  }
}
