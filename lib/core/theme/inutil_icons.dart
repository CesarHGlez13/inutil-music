import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Bespoke geometric vector glyphs exclusive to Inútil Music.
///
/// Each glyph renders cleanly on a 24×24 coordinate space in two distinct
/// optical weights:
/// - `filled == false`: refined `1.85 px` round-cap outline for resting states.
/// - `filled == true`: solid / duotone silhouette with inner negative-space
///   cutouts for active navigation items and emphasized badges.
enum InutilGlyph {
  home,
  search,
  local,
  library,
  settings,
  player,
  devices,
  profile,
  refresh,
  sleepTimer,
  queue,
  lyrics,
  equalizer,
  globe,
  palette,
  sparkles,
  trash,
  dataSaver,
  storage,
  filter,
  sources,
  link,
  live,
  info,
  tag,
  heart,
  code,
  update,
}

class InutilIcon extends StatelessWidget {
  const InutilIcon(
    this.glyph, {
    this.size = 24,
    this.color,
    this.filled = false,
    this.strokeWidth = 1.85,
    super.key,
  });

  final InutilGlyph glyph;
  final double size;
  final Color? color;
  final bool filled;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _InutilGlyphPainter(
            glyph: glyph,
            color: resolvedColor,
            filled: filled,
            strokeWidth: strokeWidth,
          ),
        ),
      ),
    );
  }
}

class _InutilGlyphPainter extends CustomPainter {
  const _InutilGlyphPainter({
    required this.glyph,
    required this.color,
    required this.filled,
    required this.strokeWidth,
  });

  final InutilGlyph glyph;
  final Color color;
  final bool filled;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / 24.0;
    canvas.save();
    canvas.translate(
      (size.width - 24.0 * scale) / 2,
      (size.height - 24.0 * scale) / 2,
    );
    canvas.scale(scale, scale);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final softFill = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    switch (glyph) {
      case InutilGlyph.home:
        _paintHome(canvas, stroke, fill, softFill);
      case InutilGlyph.search:
        _paintSearch(canvas, stroke, fill, softFill);
      case InutilGlyph.local:
        _paintLocal(canvas, stroke, fill, softFill);
      case InutilGlyph.library:
        _paintLibrary(canvas, stroke, fill, softFill);
      case InutilGlyph.settings:
        _paintSettings(canvas, stroke, fill, softFill);
      case InutilGlyph.player:
        _paintPlayer(canvas, stroke, fill);
      case InutilGlyph.devices:
        _paintDevices(canvas, stroke, fill, softFill);
      case InutilGlyph.profile:
        _paintProfile(canvas, stroke, fill, softFill);
      case InutilGlyph.refresh:
        _paintRefresh(canvas, stroke);
      case InutilGlyph.sleepTimer:
        _paintSleepTimer(canvas, stroke, fill, softFill);
      case InutilGlyph.queue:
        _paintQueue(canvas, stroke, fill);
      case InutilGlyph.lyrics:
        _paintLyrics(canvas, stroke, fill, softFill);
      case InutilGlyph.equalizer:
        _paintEqualizer(canvas, stroke, fill);
      case InutilGlyph.globe:
        _paintGlobe(canvas, stroke, softFill);
      case InutilGlyph.palette:
        _paintPalette(canvas, stroke, fill, softFill);
      case InutilGlyph.sparkles:
        _paintSparkles(canvas, stroke, fill, softFill);
      case InutilGlyph.trash:
        _paintTrash(canvas, stroke, softFill);
      case InutilGlyph.dataSaver:
        _paintDataSaver(canvas, stroke, fill, softFill);
      case InutilGlyph.storage:
        _paintStorage(canvas, stroke, softFill);
      case InutilGlyph.filter:
        _paintFilter(canvas, stroke, fill);
      case InutilGlyph.sources:
        _paintSources(canvas, stroke, fill, softFill);
      case InutilGlyph.link:
        _paintLink(canvas, stroke);
      case InutilGlyph.live:
        _paintLive(canvas, stroke, fill);
      case InutilGlyph.info:
        _paintInfo(canvas, stroke, fill, softFill);
      case InutilGlyph.tag:
        _paintTag(canvas, stroke, fill, softFill);
      case InutilGlyph.heart:
        _paintHeart(canvas, stroke, fill, softFill);
      case InutilGlyph.code:
        _paintCode(canvas, stroke);
      case InutilGlyph.update:
        _paintUpdate(canvas, stroke, softFill);
    }
    canvas.restore();
  }

  void _paintHome(Canvas canvas, Paint stroke, Paint fill, Paint softFill) {
    final house = Path()
      ..moveTo(3.5, 10.6)
      ..quadraticBezierTo(3.5, 9.4, 4.4, 8.7)
      ..lineTo(10.8, 3.8)
      ..quadraticBezierTo(12.0, 2.9, 13.2, 3.8)
      ..lineTo(19.6, 8.7)
      ..quadraticBezierTo(20.5, 9.4, 20.5, 10.6)
      ..lineTo(20.5, 18.2)
      ..quadraticBezierTo(20.5, 20.4, 18.3, 20.4)
      ..lineTo(5.7, 20.4)
      ..quadraticBezierTo(3.5, 20.4, 3.5, 18.2)
      ..close();

    if (filled) {
      final cutout = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(9.4, 14.3, 5.2, 2.2),
            const Radius.circular(1.1),
          ),
        );
      final combined = Path.combine(PathOperation.difference, house, cutout);
      canvas.drawPath(combined, fill);
    } else {
      canvas.drawPath(house, stroke);
      canvas.drawLine(const Offset(9.5, 16.0), const Offset(14.5, 16.0), stroke);
    }
  }

  void _paintSearch(Canvas canvas, Paint stroke, Paint fill, Paint softFill) {
    const center = Offset(10.8, 10.8);
    if (filled) {
      canvas.drawCircle(center, 6.9, softFill);
      canvas.drawCircle(
        center,
        6.9,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.35
          ..isAntiAlias = true,
      );
      canvas.drawCircle(center, 2.1, fill);
      canvas.drawLine(
        const Offset(16.0, 16.0),
        const Offset(20.5, 20.5),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    } else {
      canvas.drawCircle(center, 6.8, stroke);
      canvas.drawLine(
        const Offset(15.9, 15.9),
        const Offset(20.3, 20.3),
        stroke,
      );
    }
  }

  void _paintLocal(Canvas canvas, Paint stroke, Paint fill, Paint softFill) {
    final folder = Path()
      ..moveTo(3.2, 7.2)
      ..quadraticBezierTo(3.2, 5.2, 5.2, 5.2)
      ..lineTo(9.1, 5.2)
      ..quadraticBezierTo(10.2, 5.2, 10.9, 6.1)
      ..lineTo(11.9, 7.4)
      ..lineTo(18.8, 7.4)
      ..quadraticBezierTo(20.8, 7.4, 20.8, 9.4)
      ..lineTo(20.8, 17.6)
      ..quadraticBezierTo(20.8, 19.6, 18.8, 19.6)
      ..lineTo(5.2, 19.6)
      ..quadraticBezierTo(3.2, 19.6, 3.2, 17.6)
      ..close();

    if (filled) {
      final bar1 = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(8.2, 12.6, 1.8, 3.6),
            const Radius.circular(0.9),
          ),
        );
      final bar2 = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(11.1, 10.6, 1.8, 5.6),
            const Radius.circular(0.9),
          ),
        );
      final bar3 = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(14.0, 12.0, 1.8, 4.2),
            const Radius.circular(0.9),
          ),
        );
      var result = Path.combine(PathOperation.difference, folder, bar1);
      result = Path.combine(PathOperation.difference, result, bar2);
      result = Path.combine(PathOperation.difference, result, bar3);
      canvas.drawPath(result, fill);
    } else {
      canvas.drawPath(folder, stroke);
      canvas.drawLine(const Offset(9.0, 15.8), const Offset(9.0, 13.0), stroke);
      canvas.drawLine(const Offset(12.0, 15.8), const Offset(12.0, 11.2), stroke);
      canvas.drawLine(const Offset(15.0, 15.8), const Offset(15.0, 12.6), stroke);
    }
  }

  void _paintLibrary(Canvas canvas, Paint stroke, Paint fill, Paint softFill) {
    // Sleek overlapping album sleeve + vinyl disc emerging on the right.
    final sleeveRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(3.2, 4.8, 12.2, 14.4),
      const Radius.circular(3.0),
    );
    if (filled) {
      canvas.drawRRect(sleeveRect, fill);
      // Vinyl disc peeking from behind sleeve
      final disc = Path()
        ..addArc(
          const Rect.fromLTWH(10.6, 6.2, 10.6, 11.6),
          -math.pi / 2,
          math.pi,
        )
        ..close();
      canvas.drawPath(disc, softFill);
      canvas.drawArc(
        const Rect.fromLTWH(11.2, 6.6, 9.6, 10.8),
        -math.pi * 0.42,
        math.pi * 0.84,
        false,
        stroke,
      );
      canvas.drawCircle(const Offset(17.5, 12.0), 1.4, fill);
    } else {
      canvas.drawRRect(sleeveRect, stroke);
      canvas.drawArc(
        const Rect.fromLTWH(11.0, 6.6, 9.8, 10.8),
        -math.pi * 0.44,
        math.pi * 0.88,
        false,
        stroke,
      );
      canvas.drawCircle(const Offset(17.3, 12.0), 1.25, fill);
      canvas.drawLine(const Offset(6.8, 10.2), const Offset(11.8, 10.2), stroke);
      canvas.drawLine(const Offset(6.8, 13.8), const Offset(10.4, 13.8), stroke);
    }
  }

  void _paintSettings(Canvas canvas, Paint stroke, Paint fill, Paint softFill) {
    // Minimalist 3-band audio mixer sliders (musical & ultra-refined).
    const ys = [6.6, 12.0, 17.4];
    const knobX = [9.2, 15.2, 10.4];
    for (var i = 0; i < 3; i++) {
      final y = ys[i];
      final kx = knobX[i];
      canvas.drawLine(Offset(3.6, y), Offset(kx - 2.4, y), stroke);
      canvas.drawLine(Offset(kx + 2.4, y), Offset(20.4, y), stroke);
      if (filled) {
        canvas.drawCircle(Offset(kx, y), 2.6, fill);
      } else {
        canvas.drawCircle(Offset(kx, y), 2.2, stroke);
      }
    }
  }

  void _paintPlayer(Canvas canvas, Paint stroke, Paint fill) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = filled ? 2.5 : 2.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawLine(const Offset(4.8, 10.0), const Offset(4.8, 14.0), p);
    canvas.drawLine(const Offset(9.6, 5.6), const Offset(9.6, 18.4), p);
    canvas.drawLine(const Offset(14.4, 8.2), const Offset(14.4, 15.8), p);
    canvas.drawLine(const Offset(19.2, 10.4), const Offset(19.2, 13.6), p);
  }

  void _paintDevices(Canvas canvas, Paint stroke, Paint fill, Paint softFill) {
    final speaker = RRect.fromRectAndRadius(
      const Rect.fromLTWH(3.6, 4.4, 10.4, 15.2),
      const Radius.circular(2.6),
    );
    if (filled) {
      canvas.drawRRect(speaker, softFill);
    }
    canvas.drawRRect(speaker, stroke);
    canvas.drawCircle(const Offset(8.8, 8.2), 1.0, fill);
    canvas.drawCircle(const Offset(8.8, 14.4), 2.5, stroke);
    // Wireless arcs
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(15.2, 12.0), radius: 3.4),
      -math.pi * 0.32,
      math.pi * 0.64,
      false,
      stroke,
    );
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(15.2, 12.0), radius: 6.0),
      -math.pi * 0.34,
      math.pi * 0.68,
      false,
      stroke,
    );
  }

  void _paintProfile(Canvas canvas, Paint stroke, Paint fill, Paint softFill) {
    if (filled) {
      canvas.drawCircle(const Offset(12, 12), 9.2, softFill);
    }
    canvas.drawCircle(const Offset(12, 12), 9.0, stroke);
    canvas.drawCircle(const Offset(12, 9.4), 2.8, filled ? fill : stroke);
    final shoulders = Path()
      ..moveTo(6.8, 18.2)
      ..quadraticBezierTo(12.0, 14.0, 17.2, 18.2);
    canvas.drawPath(shoulders, stroke);
  }

  void _paintRefresh(Canvas canvas, Paint stroke) {
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(12, 12), radius: 7.4),
      -math.pi * 0.72,
      math.pi * 1.58,
      false,
      stroke,
    );
    final arrow = Path()
      ..moveTo(16.6, 4.5)
      ..lineTo(18.6, 8.0)
      ..lineTo(14.7, 8.3);
    canvas.drawPath(arrow, stroke);
  }

  void _paintSleepTimer(Canvas canvas, Paint stroke, Paint fill, Paint softFill) {
    // Sleek moon-crescent + precision timer top stem
    final moon = Path()
      ..moveTo(13.6, 4.6)
      ..arcToPoint(
        const Offset(19.4, 15.2),
        radius: const Radius.circular(7.8),
        largeArc: true,
        clockwise: false,
      )
      ..arcToPoint(
        const Offset(13.6, 4.6),
        radius: const Radius.circular(6.1),
        largeArc: false,
        clockwise: true,
      )
      ..close();
    if (filled) {
      canvas.drawPath(moon, fill);
      canvas.drawCircle(const Offset(17.6, 7.0), 1.35, fill);
    } else {
      canvas.drawPath(moon, stroke);
      canvas.drawLine(const Offset(17.5, 5.2), const Offset(17.5, 8.4), stroke);
      canvas.drawLine(const Offset(15.9, 6.8), const Offset(19.1, 6.8), stroke);
    }
  }

  void _paintQueue(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawLine(const Offset(3.8, 6.6), const Offset(19.8, 6.6), stroke);
    canvas.drawLine(const Offset(3.8, 11.8), const Offset(15.2, 11.8), stroke);
    canvas.drawLine(const Offset(3.8, 17.0), const Offset(11.6, 17.0), stroke);
    final play = Path()
      ..moveTo(15.6, 14.2)
      ..lineTo(20.4, 16.8)
      ..lineTo(15.6, 19.4)
      ..close();
    canvas.drawPath(play, fill);
  }

  void _paintLyrics(Canvas canvas, Paint stroke, Paint fill, Paint softFill) {
    final bubble = RRect.fromRectAndRadius(
      const Rect.fromLTWH(3.4, 4.2, 17.2, 13.4),
      const Radius.circular(4.0),
    );
    if (filled) canvas.drawRRect(bubble, softFill);
    canvas.drawRRect(bubble, stroke);
    canvas.drawLine(const Offset(7.2, 9.0), const Offset(16.8, 9.0), stroke);
    canvas.drawLine(const Offset(7.2, 12.8), const Offset(13.4, 12.8), stroke);
    canvas.drawLine(const Offset(8.0, 17.6), const Offset(6.0, 20.2), stroke);
  }

  void _paintEqualizer(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawLine(const Offset(5.4, 19.0), const Offset(5.4, 11.2), stroke);
    canvas.drawLine(const Offset(10.0, 19.0), const Offset(10.0, 5.6), stroke);
    canvas.drawLine(const Offset(14.6, 19.0), const Offset(14.6, 9.2), stroke);
    canvas.drawLine(const Offset(19.2, 19.0), const Offset(19.2, 13.4), stroke);
    if (filled) {
      canvas.drawCircle(const Offset(5.4, 11.2), 1.5, fill);
      canvas.drawCircle(const Offset(10.0, 5.6), 1.5, fill);
      canvas.drawCircle(const Offset(14.6, 9.2), 1.5, fill);
      canvas.drawCircle(const Offset(19.2, 13.4), 1.5, fill);
    }
  }

  void _paintGlobe(Canvas canvas, Paint stroke, Paint softFill) {
    if (filled) canvas.drawCircle(const Offset(12, 12), 8.6, softFill);
    canvas.drawCircle(const Offset(12, 12), 8.6, stroke);
    canvas.drawOval(const Rect.fromLTWH(8.0, 3.4, 8.0, 17.2), stroke);
    canvas.drawLine(const Offset(3.8, 12.0), const Offset(20.2, 12.0), stroke);
  }

  void _paintPalette(Canvas canvas, Paint stroke, Paint fill, Paint softFill) {
    // Editorial layered droplet + sparkle dot
    final drop = Path()
      ..moveTo(12.0, 3.4)
      ..cubicTo(16.6, 8.4, 19.2, 11.8, 19.2, 14.8)
      ..arcToPoint(
        const Offset(4.8, 14.8),
        radius: const Radius.circular(7.2),
        clockwise: true,
      )
      ..cubicTo(4.8, 11.8, 7.4, 8.4, 12.0, 3.4)
      ..close();
    canvas.drawPath(drop, softFill);
    canvas.drawPath(drop, stroke);
    canvas.drawCircle(const Offset(10.0, 15.0), 1.5, fill);
    canvas.drawCircle(const Offset(14.2, 13.8), 1.1, fill);
  }

  void _paintSparkles(Canvas canvas, Paint stroke, Paint fill, Paint softFill) {
    final star = Path()
      ..moveTo(11.0, 3.5)
      ..quadraticBezierTo(11.4, 10.6, 18.5, 11.0)
      ..quadraticBezierTo(11.4, 11.4, 11.0, 18.5)
      ..quadraticBezierTo(10.6, 11.4, 3.5, 11.0)
      ..quadraticBezierTo(10.6, 10.6, 11.0, 3.5)
      ..close();
    canvas.drawPath(star, softFill);
    canvas.drawPath(star, stroke);
    canvas.drawCircle(const Offset(18.2, 17.8), 1.5, fill);
  }

  void _paintTrash(Canvas canvas, Paint stroke, Paint softFill) {
    canvas.drawLine(const Offset(4.5, 7.0), const Offset(19.5, 7.0), stroke);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(9.2, 4.0, 5.6, 3.0),
        const Radius.circular(1.2),
      ),
      stroke,
    );
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(6.2, 7.0, 11.6, 12.8),
      const Radius.circular(2.6),
    );
    canvas.drawRRect(body, softFill);
    canvas.drawRRect(body, stroke);
    canvas.drawLine(const Offset(10.2, 10.6), const Offset(10.2, 16.0), stroke);
    canvas.drawLine(const Offset(13.8, 10.6), const Offset(13.8, 16.0), stroke);
  }

  void _paintDataSaver(Canvas canvas, Paint stroke, Paint fill, Paint softFill) {
    canvas.drawCircle(const Offset(12, 12), 8.6, softFill);
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(12, 12), radius: 8.4),
      math.pi * 0.75,
      math.pi * 1.5,
      false,
      stroke,
    );
    canvas.drawLine(const Offset(12, 12), const Offset(16.2, 8.2), stroke);
    canvas.drawCircle(const Offset(12, 12), 1.6, fill);
  }

  void _paintStorage(Canvas canvas, Paint stroke, Paint softFill) {
    final top = const Rect.fromLTWH(4.4, 4.4, 15.2, 5.0);
    canvas.drawOval(top, softFill);
    canvas.drawOval(top, stroke);
    canvas.drawLine(const Offset(4.4, 6.9), const Offset(4.4, 17.0), stroke);
    canvas.drawLine(const Offset(19.6, 6.9), const Offset(19.6, 17.0), stroke);
    canvas.drawArc(
      const Rect.fromLTWH(4.4, 9.6, 15.2, 5.0),
      0,
      math.pi,
      false,
      stroke,
    );
    canvas.drawArc(
      const Rect.fromLTWH(4.4, 14.5, 15.2, 5.0),
      0,
      math.pi,
      false,
      stroke,
    );
  }

  void _paintFilter(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawLine(const Offset(4.2, 7.0), const Offset(19.8, 7.0), stroke);
    canvas.drawLine(const Offset(6.8, 12.0), const Offset(17.2, 12.0), stroke);
    canvas.drawLine(const Offset(9.8, 17.0), const Offset(14.2, 17.0), stroke);
  }

  void _paintSources(Canvas canvas, Paint stroke, Paint fill, Paint softFill) {
    canvas.drawCircle(const Offset(12, 12), 8.5, softFill);
    canvas.drawCircle(const Offset(12, 12), 8.5, stroke);
    canvas.drawCircle(const Offset(12, 12), 2.4, fill);
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(12, 12), radius: 5.4),
      -math.pi * 0.7,
      math.pi * 0.55,
      false,
      stroke,
    );
  }

  void _paintLink(Canvas canvas, Paint stroke) {
    canvas.save();
    canvas.translate(12, 12);
    canvas.rotate(-math.pi / 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-8.6, -3.2, 9.2, 6.4),
        const Radius.circular(3.2),
      ),
      stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-0.6, -3.2, 9.2, 6.4),
        const Radius.circular(3.2),
      ),
      stroke,
    );
    canvas.restore();
  }

  void _paintLive(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawCircle(const Offset(12, 12), 2.2, fill);
    for (final r in [5.4, 8.6]) {
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(12, 12), radius: r),
        -math.pi * 0.34,
        math.pi * 0.68,
        false,
        stroke,
      );
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(12, 12), radius: r),
        math.pi * 0.66,
        math.pi * 0.68,
        false,
        stroke,
      );
    }
  }

  void _paintInfo(Canvas canvas, Paint stroke, Paint fill, Paint softFill) {
    canvas.drawCircle(const Offset(12, 12), 8.6, softFill);
    canvas.drawCircle(const Offset(12, 12), 8.6, stroke);
    canvas.drawCircle(const Offset(12, 8.2), 1.1, fill);
    canvas.drawLine(const Offset(12, 11.2), const Offset(12, 16.0), stroke);
  }

  void _paintTag(Canvas canvas, Paint stroke, Paint fill, Paint softFill) {
    final tag = Path()
      ..moveTo(4.6, 12.2)
      ..lineTo(12.2, 4.6)
      ..lineTo(18.6, 4.6)
      ..quadraticBezierTo(19.4, 4.6, 19.4, 5.4)
      ..lineTo(19.4, 11.8)
      ..lineTo(11.8, 19.4)
      ..quadraticBezierTo(11.0, 20.2, 10.2, 19.4)
      ..lineTo(4.6, 13.8)
      ..quadraticBezierTo(3.8, 13.0, 4.6, 12.2)
      ..close();
    canvas.drawPath(tag, softFill);
    canvas.drawPath(tag, stroke);
    canvas.drawCircle(const Offset(15.4, 8.6), 1.2, fill);
  }

  void _paintHeart(Canvas canvas, Paint stroke, Paint fill, Paint softFill) {
    final heart = Path()
      ..moveTo(12.0, 19.4)
      ..cubicTo(6.2, 15.2, 4.0, 12.2, 4.0, 8.9)
      ..cubicTo(4.0, 6.2, 6.1, 4.4, 8.5, 4.4)
      ..cubicTo(10.1, 4.4, 11.4, 5.3, 12.0, 6.6)
      ..cubicTo(12.6, 5.3, 13.9, 4.4, 15.5, 4.4)
      ..cubicTo(17.9, 4.4, 20.0, 6.2, 20.0, 8.9)
      ..cubicTo(20.0, 12.2, 17.8, 15.2, 12.0, 19.4)
      ..close();
    canvas.drawPath(heart, filled ? fill : softFill);
    if (!filled) canvas.drawPath(heart, stroke);
  }

  void _paintCode(Canvas canvas, Paint stroke) {
    final left = Path()
      ..moveTo(8.4, 7.6)
      ..lineTo(4.2, 12.0)
      ..lineTo(8.4, 16.4);
    final right = Path()
      ..moveTo(15.6, 7.6)
      ..lineTo(19.8, 12.0)
      ..lineTo(15.6, 16.4);
    canvas.drawPath(left, stroke);
    canvas.drawPath(right, stroke);
    canvas.drawLine(const Offset(13.2, 6.4), const Offset(10.8, 17.6), stroke);
  }

  void _paintUpdate(Canvas canvas, Paint stroke, Paint softFill) {
    final box = RRect.fromRectAndRadius(
      const Rect.fromLTWH(4.0, 4.0, 16.0, 16.0),
      const Radius.circular(4.4),
    );
    canvas.drawRRect(box, softFill);
    canvas.drawRRect(box, stroke);
    canvas.drawLine(const Offset(12.0, 7.8), const Offset(12.0, 15.6), stroke);
    final chevron = Path()
      ..moveTo(8.8, 12.8)
      ..lineTo(12.0, 16.0)
      ..lineTo(15.2, 12.8);
    canvas.drawPath(chevron, stroke);
  }

  @override
  bool shouldRepaint(_InutilGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.color != color ||
      oldDelegate.filled != filled ||
      oldDelegate.strokeWidth != strokeWidth;
}
