import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

const playbackPageTransitionDuration = Duration(milliseconds: 420);
const playbackPageReverseTransitionDuration = Duration(milliseconds: 360);
const playbackPageTransitionBeginOffset = Offset(0, 0.14);

/// The shared page motion used when moving into a playback-focused surface.
///
/// When [enableCapsuleMorph] is true (mobile), the full-screen player morphs
/// directly out of the Mini Player capsule's exact bounding box and corner
/// radius to full screen on open, and folds smoothly back down into the Mini
/// Player capsule on collapse — without re-laying out the player subtree.
class PlaybackPageTransition extends StatelessWidget {
  const PlaybackPageTransition({
    required this.animation,
    required this.child,
    this.fadeKey,
    this.slideKey,
    this.repaintBoundaryKey,
    this.enableCapsuleMorph = false,
    this.morphOriginHeight = 72.0,
    this.morphOriginBottomOffset = 82.0,
    this.morphOriginHorizontalInset = 8.0,
    this.morphOriginBorderRadius = 32.0,
    super.key,
  });

  final Animation<double> animation;
  final Widget child;
  final Key? fadeKey;
  final Key? slideKey;
  final Key? repaintBoundaryKey;
  final bool enableCapsuleMorph;
  final double morphOriginHeight;
  final double morphOriginBottomOffset;
  final double morphOriginHorizontalInset;
  final double morphOriginBorderRadius;

  @override
  Widget build(BuildContext context) {
    final morphCurve = CurvedAnimation(
      parent: animation,
      curve: const Cubic(0.18, 0.92, 0.22, 1.0),
      reverseCurve: const Cubic(0.28, 0.0, 0.20, 1.0),
    );

    final slide = Tween<Offset>(
      begin: enableCapsuleMorph
          ? playbackPageTransitionBeginOffset
          : const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(morphCurve);

    final opacity = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.34, curve: Curves.easeOut),
      reverseCurve: const Interval(0.06, 0.48, curve: Curves.easeIn),
    );

    final boundaryChild = RepaintBoundary(
      key: repaintBoundaryKey,
      child: child,
    );

    return AnimatedBuilder(
      animation: animation,
      child: boundaryChild,
      builder: (context, staticChild) {
        final t = morphCurve.value.clamp(0.0, 1.0);
        final contentScale = enableCapsuleMorph
            ? lerpDouble(0.92, 1.0, t)!
            : lerpDouble(0.96, 1.0, t)!;

        final innerContent = SlideTransition(
          key: slideKey,
          position: slide,
          child: Transform.scale(
            scale: contentScale,
            alignment: const Alignment(0.0, 0.84),
            child: FadeTransition(
              key: fadeKey,
              opacity: opacity,
              child: staticChild,
            ),
          ),
        );

        if (!enableCapsuleMorph || t >= 0.999) {
          return innerContent;
        }

        return CustomPaint(
          foregroundPainter: t > 0.005
              ? _CapsuleMorphBorderPainter(
                  progress: t,
                  originHeight: morphOriginHeight,
                  originBottomOffset: morphOriginBottomOffset,
                  originHorizontalInset: morphOriginHorizontalInset,
                  originBorderRadius: morphOriginBorderRadius,
                )
              : null,
          child: ClipPath(
            clipper: _CapsuleMorphClipper(
              progress: t,
              originHeight: morphOriginHeight,
              originBottomOffset: morphOriginBottomOffset,
              originHorizontalInset: morphOriginHorizontalInset,
              originBorderRadius: morphOriginBorderRadius,
            ),
            child: innerContent,
          ),
        );
      },
    );
  }
}

RRect _computeMorphRRect({
  required Size size,
  required double progress,
  required double originHeight,
  required double originBottomOffset,
  required double originHorizontalInset,
  required double originBorderRadius,
}) {
  final safeHeight = originHeight.clamp(48.0, size.height);
  final safeInset = originHorizontalInset.clamp(0.0, size.width * 0.35);
  final safeBottom = originBottomOffset.clamp(
    0.0,
    (size.height - safeHeight).clamp(0.0, size.height),
  );
  final originRect = Rect.fromLTWH(
    safeInset,
    (size.height - safeBottom - safeHeight).clamp(0.0, size.height),
    (size.width - safeInset * 2).clamp(1.0, size.width),
    safeHeight,
  );
  final fullRect = Offset.zero & size;
  final currentRect = Rect.lerp(originRect, fullRect, progress) ?? fullRect;
  final currentRadius = lerpDouble(originBorderRadius, 0.0, progress) ?? 0.0;
  return RRect.fromRectAndRadius(currentRect, Radius.circular(currentRadius));
}

class _CapsuleMorphClipper extends CustomClipper<Path> {
  const _CapsuleMorphClipper({
    required this.progress,
    required this.originHeight,
    required this.originBottomOffset,
    required this.originHorizontalInset,
    required this.originBorderRadius,
  });

  final double progress;
  final double originHeight;
  final double originBottomOffset;
  final double originHorizontalInset;
  final double originBorderRadius;

  @override
  Path getClip(Size size) {
    final rrect = _computeMorphRRect(
      size: size,
      progress: progress,
      originHeight: originHeight,
      originBottomOffset: originBottomOffset,
      originHorizontalInset: originHorizontalInset,
      originBorderRadius: originBorderRadius,
    );
    return Path()..addRRect(rrect);
  }

  @override
  bool shouldReclip(covariant _CapsuleMorphClipper oldClipper) =>
      progress != oldClipper.progress ||
      originHeight != oldClipper.originHeight ||
      originBottomOffset != oldClipper.originBottomOffset ||
      originHorizontalInset != oldClipper.originHorizontalInset ||
      originBorderRadius != oldClipper.originBorderRadius;
}

class _CapsuleMorphBorderPainter extends CustomPainter {
  const _CapsuleMorphBorderPainter({
    required this.progress,
    required this.originHeight,
    required this.originBottomOffset,
    required this.originHorizontalInset,
    required this.originBorderRadius,
  });

  final double progress;
  final double originHeight;
  final double originBottomOffset;
  final double originHorizontalInset;
  final double originBorderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = _computeMorphRRect(
      size: size,
      progress: progress,
      originHeight: originHeight,
      originBottomOffset: originBottomOffset,
      originHorizontalInset: originHorizontalInset,
      originBorderRadius: originBorderRadius,
    );
    final rimAlpha = ((1.0 - progress) * 0.28).clamp(0.0, 0.28);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: rimAlpha);
    canvas.drawRRect(rrect.deflate(0.5), paint);
  }

  @override
  bool shouldRepaint(covariant _CapsuleMorphBorderPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      originHeight != oldDelegate.originHeight ||
      originBottomOffset != oldDelegate.originBottomOffset ||
      originHorizontalInset != oldDelegate.originHorizontalInset ||
      originBorderRadius != oldDelegate.originBorderRadius;
}

/// Drives [PlaybackPageTransition] while keeping its child mounted between
/// visits. This mirrors a maintained page route without rebuilding playback.
class PlaybackPageVisibilityTransition extends StatefulWidget {
  const PlaybackPageVisibilityTransition({
    required this.visible,
    required this.child,
    this.duration = playbackPageTransitionDuration,
    this.reverseDuration = playbackPageReverseTransitionDuration,
    this.animateInitialEntry = true,
    this.fadeKey,
    this.slideKey,
    this.repaintBoundaryKey,
    this.enableCapsuleMorph = false,
    this.morphOriginHeight = 72.0,
    this.morphOriginBottomOffset = 82.0,
    this.morphOriginHorizontalInset = 8.0,
    this.morphOriginBorderRadius = 32.0,
    super.key,
  });

  final bool visible;
  final Widget child;
  final Duration duration;
  final Duration reverseDuration;
  final bool animateInitialEntry;
  final Key? fadeKey;
  final Key? slideKey;
  final Key? repaintBoundaryKey;
  final bool enableCapsuleMorph;
  final double morphOriginHeight;
  final double morphOriginBottomOffset;
  final double morphOriginHorizontalInset;
  final double morphOriginBorderRadius;

  @override
  State<PlaybackPageVisibilityTransition> createState() =>
      _PlaybackPageVisibilityTransitionState();
}

class _PlaybackPageVisibilityTransitionState
    extends State<PlaybackPageVisibilityTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final startsVisible = widget.visible && !widget.animateInitialEntry;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: widget.reverseDuration,
      value: startsVisible ? 1 : 0,
    );
    if (widget.visible && !startsVisible) {
      _show();
    }
  }

  @override
  void didUpdateWidget(covariant PlaybackPageVisibilityTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.reverseDuration != oldWidget.reverseDuration) {
      _controller.reverseDuration = widget.reverseDuration;
    }
    if (widget.visible != oldWidget.visible) {
      widget.visible ? _show() : _hide();
    }
  }

  void _show() {
    if (widget.duration == Duration.zero) {
      _controller.value = 1;
      return;
    }
    _controller.forward();
  }

  void _hide() {
    if (widget.reverseDuration == Duration.zero) {
      _controller.value = 0;
      return;
    }
    _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlaybackPageTransition(
      animation: _controller,
      fadeKey: widget.fadeKey,
      slideKey: widget.slideKey,
      repaintBoundaryKey: widget.repaintBoundaryKey,
      enableCapsuleMorph: widget.enableCapsuleMorph,
      morphOriginHeight: widget.morphOriginHeight,
      morphOriginBottomOffset: widget.morphOriginBottomOffset,
      morphOriginHorizontalInset: widget.morphOriginHorizontalInset,
      morphOriginBorderRadius: widget.morphOriginBorderRadius,
      child: widget.child,
    );
  }
}
