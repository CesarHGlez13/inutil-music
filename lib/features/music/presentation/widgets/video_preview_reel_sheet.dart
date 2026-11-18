import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../services/video_preview/video_preview_resolver.dart';
import 'source_image.dart';

/// Full-screen Spotify-style vertical Video Preview Clips reel for artists,
/// albums, and tracks (story progress bars, hashtags, artist header, mute/unmute
/// toggle, and bottom glass track card).
class VideoPreviewReelSheet extends StatefulWidget {
  const VideoPreviewReelSheet({
    required this.clips,
    required this.artistName,
    this.artistAvatarUrl,
    this.artistSubtitle,
    this.initialIndex = 0,
    this.onPlayClip,
    super.key,
  });

  final List<VideoPreviewClip> clips;
  final String artistName;
  final String? artistAvatarUrl;
  final String? artistSubtitle;
  final int initialIndex;
  final ValueChanged<VideoPreviewClip>? onPlayClip;

  static Future<void> show(
    BuildContext context, {
    required List<VideoPreviewClip> clips,
    required String artistName,
    String? artistAvatarUrl,
    String? artistSubtitle,
    int initialIndex = 0,
    ValueChanged<VideoPreviewClip>? onPlayClip,
  }) {
    if (clips.isEmpty) return Future<void>.value();
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) => VideoPreviewReelSheet(
          clips: clips,
          artistName: artistName,
          artistAvatarUrl: artistAvatarUrl,
          artistSubtitle: artistSubtitle,
          initialIndex: initialIndex.clamp(0, clips.length - 1),
          onPlayClip: onPlayClip,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<VideoPreviewReelSheet> createState() => _VideoPreviewReelSheetState();
}

class _VideoPreviewReelSheetState extends State<VideoPreviewReelSheet> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.clips.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _stepClip(int delta) {
    final target = _currentIndex + delta;
    if (target < 0 || target >= widget.clips.length) return;
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final activeClip = widget.clips[_currentIndex];
    final primaryTag = activeClip.tags.isNotEmpty
        ? activeClip.tags.first
        : '#video preview';

    return Scaffold(
      key: const ValueKey('video-preview-reel-sheet'),
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: widget.clips.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) => _VideoPreviewReelPage(
              clip: widget.clips[index],
              isActive: index == _currentIndex,
              muted: _muted,
              onTapLeft: () => _stepClip(-1),
              onTapRight: () => _stepClip(1),
            ),
          ),

          // Top & bottom cinematic readability gradients.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.62),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.88),
                  ],
                  stops: const [0.0, 0.24, 0.56, 1.0],
                ),
              ),
            ),
          ),

          // Top bar: Back, Story progress dots/pills, Primary tag, Mute toggle.
          Positioned(
            top: topPad + 10,
            left: 14,
            right: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _CircleGlassButton(
                      key: const ValueKey('video-preview-reel-close'),
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Cerrar',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < widget.clips.length; i++)
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  height: 4,
                                  width: i == _currentIndex ? 24 : 7,
                                  decoration: BoxDecoration(
                                    color: i == _currentIndex
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.38),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            primaryTag,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _CircleGlassButton(
                      key: const ValueKey('video-preview-reel-mute'),
                      icon: _muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      tooltip: _muted ? 'Activar sonido' : 'Silenciar',
                      onTap: () => setState(() => _muted = !_muted),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom overlay: Artist row, hashtag chips, and Track Play card.
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomPad + 18,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipOval(
                      child: SizedBox.square(
                        dimension: 40,
                        child: ProportionalArtwork(
                          source: widget.artistAvatarUrl ?? activeClip.artworkUrl,
                          cacheWidth: 160,
                          fallback: const ColoredBox(
                            color: Color(0xFF202530),
                            child: Icon(Icons.person_rounded, color: Colors.white70),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.artistName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (widget.artistSubtitle?.trim().isNotEmpty == true)
                            Text(
                              widget.artistSubtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 12.5,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                      child: const Text(
                        'Video Preview',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (activeClip.tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final tag in activeClip.tags.take(4))
                        Text(
                          tag,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Material(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: widget.onPlayClip == null
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            widget.onPlayClip!(activeClip);
                          },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox.square(
                              dimension: 50,
                              child: ProportionalArtwork(
                                source:
                                    activeClip.artworkUrl ??
                                    widget.artistAvatarUrl,
                                cacheWidth: 160,
                                fallback: const ColoredBox(
                                  color: Color(0xFF1F2430),
                                  child: Icon(
                                    Icons.music_note_rounded,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activeClip.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  activeClip.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.78),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.black,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoPreviewReelPage extends StatefulWidget {
  const _VideoPreviewReelPage({
    required this.clip,
    required this.isActive,
    required this.muted,
    required this.onTapLeft,
    required this.onTapRight,
  });

  final VideoPreviewClip clip;
  final bool isActive;
  final bool muted;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;

  @override
  State<_VideoPreviewReelPage> createState() => _VideoPreviewReelPageState();
}

class _VideoPreviewReelPageState extends State<_VideoPreviewReelPage> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initController());
  }

  @override
  void didUpdateWidget(covariant _VideoPreviewReelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip.videoUrl != widget.clip.videoUrl) {
      unawaited(_initController());
      return;
    }
    final ctrl = _controller;
    if (ctrl != null && ctrl.value.isInitialized) {
      if (oldWidget.muted != widget.muted) {
        unawaited(ctrl.setVolume(widget.muted ? 0 : 1));
      }
      if (oldWidget.isActive != widget.isActive) {
        if (widget.isActive) {
          unawaited(ctrl.play());
        } else {
          unawaited(ctrl.pause());
        }
      }
    }
  }

  Future<void> _initController() async {
    final prev = _controller;
    _controller = null;
    if (mounted) setState(() => _ready = false);
    if (prev != null) unawaited(prev.dispose());

    final ctrl = VideoPlayerController.networkUrl(
      widget.clip.videoUrl,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = ctrl;
    try {
      await ctrl.initialize().timeout(const Duration(seconds: 10));
      if (!mounted || !identical(_controller, ctrl)) {
        await ctrl.dispose();
        return;
      }
      await ctrl.setLooping(true);
      await ctrl.setVolume(widget.muted ? 0 : 1);
      if (widget.isActive) {
        await ctrl.play();
      }
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (identical(_controller, ctrl)) {
        _controller = null;
        if (mounted) setState(() => _ready = false);
      }
      unawaited(ctrl.dispose());
    }
  }

  @override
  void dispose() {
    final ctrl = _controller;
    _controller = null;
    if (ctrl != null) unawaited(ctrl.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    final size = ctrl?.value.size ?? Size.zero;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final width = MediaQuery.sizeOf(context).width;
        if (details.localPosition.dx < width * 0.35) {
          widget.onTapLeft();
        } else {
          widget.onTapRight();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Instant cover backdrop while video buffers.
          ProportionalArtwork(
            source: widget.clip.artworkUrl,
            cacheWidth: 640,
            fallback: const ColoredBox(color: Color(0xFF0B0E14)),
          ),
          if (_ready && ctrl != null && !size.isEmpty)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 280),
              opacity: _ready ? 1 : 0,
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: VideoPlayer(ctrl),
                ),
              ),
            ),
          if (!_ready)
            const Center(
              child: SizedBox.square(
                dimension: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: Colors.white70,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CircleGlassButton extends StatelessWidget {
  const _CircleGlassButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.42),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Compact Spotify-style horizontal strip of vertical 9:14 video preview cards
/// shown on Artist profiles and Album pages.
class VideoPreviewClipsStrip extends StatelessWidget {
  const VideoPreviewClipsStrip({
    required this.clips,
    required this.onTapClip,
    super.key,
  });

  final List<VideoPreviewClip> clips;
  final ValueChanged<int> onTapClip;

  @override
  Widget build(BuildContext context) {
    if (clips.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 176,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        itemCount: clips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final clip = clips[index];
          return GestureDetector(
            key: ValueKey('video-preview-card-$index'),
            onTap: () => onTapClip(index),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 118,
                height: 176,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ProportionalArtwork(
                      source: clip.artworkUrl,
                      cacheWidth: 320,
                      fallback: const ColoredBox(color: Color(0xFF1A1F2B)),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.18),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.85),
                          ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.58),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.play_circle_filled_rounded,
                              color: Colors.white,
                              size: 13,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'CLIP',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Text(
                        clip.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
