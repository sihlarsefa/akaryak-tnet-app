import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../tokens.dart';

/// Brand loader: a row of » chevrons lit one after another, like the mark
/// moving forward. Used by pull-to-refresh, buttons and full-screen waits.
///
/// Under reduce motion the chevrons stay still at full strength.
class ChevronSpinner extends StatefulWidget {
  const ChevronSpinner({
    super.key,
    this.size = 28,
    this.color,
    this.count = 3,
    this.semanticLabel = 'Yükleniyor',
  });

  /// Height of the chevrons; the row is about `size × 1.25` wide for 3.
  final double size;
  final Color? color;
  final int count;
  final String? semanticLabel;

  @override
  State<ChevronSpinner> createState() => _ChevronSpinnerState();
}

class _ChevronSpinnerState extends State<ChevronSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AknMotion.reduced(context);
    if (_reduced) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AknColors>() ?? AknColors.light;
    final color = widget.color ?? c.brandBright;
    final size = ChevronRowPainter.sizeFor(widget.size, widget.count);
    final Widget painted = _reduced
        ? CustomPaint(
            size: size,
            painter: ChevronRowPainter(
              color: color,
              count: widget.count,
              phase: null,
            ),
          )
        : AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              size: size,
              painter: ChevronRowPainter(
                color: color,
                count: widget.count,
                phase: _c.value,
              ),
            ),
          );
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: painted);
    return Semantics(label: label, liveRegion: true, child: painted);
  }
}

/// Paints [count] chevrons (») in a row.
///
/// * [phase] (0..1, looping) lights the chevrons in sequence; null = static.
/// * [progress] (0..1) draws them in from the left (pull-to-refresh drag).
class ChevronRowPainter extends CustomPainter {
  ChevronRowPainter({
    required this.color,
    this.count = 3,
    this.phase,
    this.progress = 1,
  });

  final Color color;
  final int count;
  final double? phase;
  final double progress;

  /// Chevron width relative to height, and step between chevrons.
  static const double _w = 0.5;
  static const double _step = 0.42;

  static Size sizeFor(double height, int count) =>
      Size(height * (_w + _step * (count - 1)) + height * 0.2, height);

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final stroke = h * 0.17;
    final pad = stroke / 2 + h * 0.06;
    final top = pad;
    final bottom = h - pad;
    final w = h * _w;
    for (var i = 0; i < count; i++) {
      final share = 1 / count;
      final drawn = ((progress - i * share) / share).clamp(0.0, 1.0);
      if (drawn <= 0) continue;
      double alpha;
      if (phase == null) {
        alpha = 1;
      } else {
        // A soft pulse travels left → right.
        final d = (phase! - i / count) % 1.0;
        alpha = 0.28 + 0.72 * math.pow(math.cos(d * math.pi), 2).toDouble();
        if (d > 0.5) alpha = 0.28;
      }
      final x0 = h * 0.1 + stroke / 2 + i * h * _step;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: color.a * alpha * drawn);
      final mid = Offset(x0 + w - stroke, h / 2);
      final start = Offset(x0, top);
      final end = Offset(x0, bottom);
      final path = Path()..moveTo(start.dx, start.dy);
      if (drawn >= 1) {
        path
          ..lineTo(mid.dx, mid.dy)
          ..lineTo(end.dx, end.dy);
      } else if (drawn <= 0.5) {
        final p = Offset.lerp(start, mid, drawn * 2)!;
        path.lineTo(p.dx, p.dy);
      } else {
        final p = Offset.lerp(mid, end, (drawn - 0.5) * 2)!;
        path
          ..lineTo(mid.dx, mid.dy)
          ..lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(ChevronRowPainter old) =>
      old.color != color ||
      old.count != count ||
      old.phase != phase ||
      old.progress != progress;
}
