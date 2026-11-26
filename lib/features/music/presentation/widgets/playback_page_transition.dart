import 'package:flutter/material.dart';

import '../../../../core/platform/app_platform.dart';

const playbackPageTransitionDuration = Duration(milliseconds: 320);
const playbackPageReverseTransitionDuration = Duration(milliseconds: 320);
const playbackPageTransitionBeginOffset = Offset(0, 0.08);

/// The shared page motion used when moving into a playback-focused surface.
///
/// Uses pure hardware-composited [SlideTransition] and [FadeTransition] layers
/// around a single [RepaintBoundary] without per-frame [ClipPath] stencil passes
/// so 1080p/1440p Canvas video and shaders composite at locked 120fps.
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
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
    );

    final slide = Tween<Offset>(
      begin: playbackPageTransitionBeginOffset,
      end: Offset.zero,
    ).animate(curved);

    return SlideTransition(
      key: slideKey,
      position: slide,
      child: FadeTransition(
        key: fadeKey,
        opacity: curved,
        child: RepaintBoundary(
          key: repaintBoundaryKey,
          child: child,
        ),
      ),
    );
  }
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
      animationBehavior: AppPlatform.isFlutterTest
          ? AnimationBehavior.normal
          : AnimationBehavior.preserve,
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
