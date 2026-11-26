import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/firebase/listening_room_service.dart';
import '../providers/listening_room_providers.dart';

/// Single floating emoji particle instance with organic physics (sway, pop-in,
/// upwards velocity, wobble rotation and smooth fade-out).
class _FloatingParticle {
  _FloatingParticle({
    required this.id,
    required this.emoji,
    required this.senderName,
    required this.startX,
    required this.swaySpeed,
    required this.swayAmplitude,
    required this.size,
    required this.rotationSpeed,
    required this.maxHeight,
    required this.startTime,
    required this.durationMs,
  });

  final String id;
  final String emoji;
  final String? senderName;
  final double startX; // normalized horizontal spawn origin [0.0 - 1.0]
  final double swaySpeed; // oscillation frequency
  final double swayAmplitude; // max horizontal drift in logical pixels
  final double size; // font size
  final double rotationSpeed;
  final double maxHeight; // total vertical travel distance
  final DateTime startTime;
  final int durationMs;
}

/// Global controller to spawn instant live reaction bursts from any child button.
class LiveFloatingReactionsController {
  _LiveFloatingReactionsOverlayState? _state;

  void _attach(_LiveFloatingReactionsOverlayState state) {
    _state = state;
  }

  void _detach() {
    _state = null;
  }

  /// Spawns an organic burst of floating emoji particles (TikTok LIVE / Instagram Stories style).
  void spawnBurst(
    String emoji, {
    String? senderName,
    int count = 5,
    double? originX,
  }) {
    _state?.spawnBurst(
      emoji,
      senderName: senderName,
      count: count,
      originX: originX,
    );
  }
}

/// Overlay that renders physics-based flying emoji reaction particles.
/// Automatically listens to room reactions from [listeningRoomServiceProvider]
/// and renders them live for all participants.
class LiveFloatingReactionsOverlay extends ConsumerStatefulWidget {
  const LiveFloatingReactionsOverlay({
    this.controller,
    this.child,
    this.bottomOffset = 80.0,
    this.maxTravelHeight = 420.0,
    this.autoListenRoom = true,
    super.key,
  });

  final LiveFloatingReactionsController? controller;
  final Widget? child;
  final double bottomOffset;
  final double maxTravelHeight;
  final bool autoListenRoom;

  @override
  ConsumerState<LiveFloatingReactionsOverlay> createState() =>
      _LiveFloatingReactionsOverlayState();
}

class _LiveFloatingReactionsOverlayState
    extends ConsumerState<LiveFloatingReactionsOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  final List<_FloatingParticle> _particles = <_FloatingParticle>[];
  final Set<String> _seenNetworkReactionIds = <String>{};
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_onTick);
  }

  @override
  void didUpdateWidget(covariant LiveFloatingReactionsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach();
    _ticker.removeListener(_onTick);
    _ticker.dispose();
    _particles.clear();
    super.dispose();
  }

  void _onTick() {
    if (!mounted || _particles.isEmpty) {
      if (_ticker.isAnimating && _particles.isEmpty) {
        _ticker.stop();
      }
      return;
    }
    final now = DateTime.now();
    _particles.removeWhere(
      (p) => now.difference(p.startTime).inMilliseconds >= p.durationMs,
    );
    if (_particles.isEmpty && _ticker.isAnimating) {
      _ticker.stop();
    }
    setState(() {});
  }

  void spawnBurst(
    String emoji, {
    String? senderName,
    int count = 5,
    double? originX,
  }) {
    final now = DateTime.now();
    final cleanEmoji = emoji.trim();
    if (cleanEmoji.isEmpty) return;

    final baseOriginX = originX ?? (0.75 + (_random.nextDouble() * 0.15));

    for (var i = 0; i < count; i++) {
      // Slight stagger and random horizontal offset per particle in burst
      final jitterX = (_random.nextDouble() - 0.5) * 0.12;
      final particleOriginX = (baseOriginX + jitterX).clamp(0.08, 0.92);
      final duration = 1800 + _random.nextInt(700); // 1.8s - 2.5s
      final particle = _FloatingParticle(
        id: '${now.microsecondsSinceEpoch}_${_random.nextInt(99999)}',
        emoji: cleanEmoji,
        senderName: i == 0 ? senderName : null,
        startX: particleOriginX,
        swaySpeed: 2.5 + (_random.nextDouble() * 3.5),
        swayAmplitude: 18.0 + (_random.nextDouble() * 30.0),
        size: 26.0 + (_random.nextDouble() * 12.0),
        rotationSpeed: (_random.nextDouble() - 0.5) * 0.8,
        maxHeight: widget.maxTravelHeight * (0.75 + _random.nextDouble() * 0.35),
        startTime: now.add(Duration(milliseconds: i * 75)),
        durationMs: duration,
      );
      _particles.add(particle);
    }

    if (!_ticker.isAnimating) {
      _ticker.repeat();
    }
    setState(() {});
  }

  void _checkIncomingRoomReactions(ListeningRoomService service) {
    if (!widget.autoListenRoom) return;
    final burstList = service.recentBurstReactions;
    for (final reaction in burstList) {
      if (_seenNetworkReactionIds.add(reaction.id)) {
        // If not sender or sender matches, spawn floating reaction
        spawnBurst(
          reaction.emoji,
          senderName: reaction.senderName,
          count: 4,
          originX: 0.70 + (_random.nextDouble() * 0.20),
        );
      }
    }
    if (_seenNetworkReactionIds.length > 100) {
      _seenNetworkReactionIds.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.autoListenRoom) {
      final service = ref.watch(listeningRoomServiceProvider);
      // Synchronize with incoming bursts from the room
      _checkIncomingRoomReactions(service);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (widget.child != null) widget.child!,
        if (_particles.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FloatingReactionsPainter(
                  particles: _particles,
                  bottomOffset: widget.bottomOffset,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FloatingReactionsPainter extends CustomPainter {
  _FloatingReactionsPainter({
    required this.particles,
    required this.bottomOffset,
  });

  final List<_FloatingParticle> particles;
  final double bottomOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();

    for (final particle in particles) {
      final elapsedMs = now.difference(particle.startTime).inMilliseconds;
      if (elapsedMs <= 0) continue;
      final progress = (elapsedMs / particle.durationMs).clamp(0.0, 1.0);
      if (progress >= 1.0) continue;

      // Vertical position (ease out upwards)
      // Curved travel: faster at bottom, decelerates slightly near top
      final curvedY = math.pow(progress, 0.85).toDouble();
      final y = size.height - bottomOffset - (curvedY * particle.maxHeight);

      // Horizontal position: base origin + sinusoidal sway
      final sway = math.sin(progress * particle.swaySpeed * math.pi * 2) *
          particle.swayAmplitude;
      final x = (particle.startX * size.width) + sway;

      // Scale: quick pop-in bounce (0.0 -> 1.35 -> 1.0)
      double scale = 1.0;
      if (progress < 0.15) {
        scale = (progress / 0.15) * 1.35;
      } else if (progress < 0.28) {
        final t = (progress - 0.15) / 0.13;
        scale = 1.35 - (t * 0.35);
      } else if (progress > 0.70) {
        // Subtle shrinkage at the very top
        final t = (progress - 0.70) / 0.30;
        scale = 1.0 - (t * 0.25);
      }

      // Opacity: stays solid, then fades out smoothly in the last 35% of flight
      double opacity = 1.0;
      if (progress > 0.65) {
        opacity = ((1.0 - progress) / 0.35).clamp(0.0, 1.0);
      }

      canvas.save();
      canvas.translate(x, y);

      // Rotation sway
      final rotation = math.sin(progress * math.pi * 2) * particle.rotationSpeed;
      canvas.rotate(rotation);
      canvas.scale(scale);

      // Draw Emoji
      final textPainter = TextPainter(
        text: TextSpan(
          text: particle.emoji,
          style: TextStyle(
            fontSize: particle.size,
            color: Colors.white.withValues(alpha: opacity),
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.35 * opacity),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final emojiOffset = Offset(-textPainter.width / 2, -textPainter.height / 2);
      textPainter.paint(canvas, emojiOffset);

      // If particle has sender name, draw a miniature TikTok-style pill badge above it
      if (particle.senderName != null && particle.senderName!.isNotEmpty && progress < 0.80) {
        final badgeOpacity = opacity * (1.0 - (progress / 0.80)).clamp(0.0, 1.0);
        final badgePainter = TextPainter(
          text: TextSpan(
            text: particle.senderName!,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: badgeOpacity),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final badgeRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(0, emojiOffset.dy - 12),
            width: badgePainter.width + 12,
            height: badgePainter.height + 6,
          ),
          const Radius.circular(999),
        );

        final bgPaint = Paint()
          ..color = Colors.black.withValues(alpha: 0.65 * badgeOpacity);
        canvas.drawRRect(badgeRect, bgPaint);

        badgePainter.paint(
          canvas,
          Offset(-badgePainter.width / 2, emojiOffset.dy - 12 - (badgePainter.height / 2)),
        );
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FloatingReactionsPainter oldDelegate) => true;
}
