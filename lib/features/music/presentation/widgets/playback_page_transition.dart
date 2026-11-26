import 'package:flutter/material.dart';

const playbackPageTransitionDuration = Duration(milliseconds: 400);
const playbackPageReverseTransitionDuration = Duration(milliseconds: 340);
const playbackPageTransitionBeginOffset = Offset(0, 1.0);

/// The shared page motion used when moving into a playback-focused surface.
///
/// Expands from the mini player position (bottom) to full screen edge-to-edge
/// with morphing corner radius and subtle scale for an ultra-professional,
/// fluid transition like Spotify / Apple Music.
class PlaybackPageTransition extends StatelessWidget {
  const PlaybackPageTransition({
    required this.animation,
    required this.child,
    this.fadeKey,
    this.slideKey,
    this.repaintBoundaryKey,
    super.key,
  });

  final Animation<double> animation;
  final Widget child;
  final Key? fadeKey;
  final Key? slideKey;
  final Key? repaintBoundaryKey;

  @override
  Widget build(BuildContext context) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    final slide = Tween<Offset>(
      begin: playbackPageTransitionBeginOffset,
      end: Offset.zero,
    ).animate(curvedAnimation);

    final scale = Tween<double>(
      begin: 0.93,
      end: 1.0,
    ).animate(curvedAnimation);

    final radius = Tween<double>(
      begin: 32.0,
      end: 0.0,
    ).animate(curvedAnimation);

    final opacity = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
      reverseCurve: const Interval(0.55, 1.0, curve: Curves.easeIn),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, staticChild) {
        return SlideTransition(
          key: slideKey,
          position: slide,
          child: Transform.scale(
            scale: scale.value,
            alignment: Alignment.bottomCenter,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius.value),
              child: FadeTransition(
                key: fadeKey,
                opacity: opacity,
                child: staticChild,
              ),
            ),
          ),
        );
      },
      child: RepaintBoundary(key: repaintBoundaryKey, child: child),
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
      child: widget.child,
    );
  }
}
