import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// Tiny trend line (design v2 §6.20 line chart, small): a 2 px ink line and
/// an end dot (10 px `chartHighlight` with a 2 px surface ring). No area
/// fill, no gradient, no draw-in (only the plate's counter roll animates on
/// its own).
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.height = 40,
    this.color,
    this.fill = true,
    this.semanticLabel,
  });

  final List<double> values;
  final double height;

  /// Line colour (ink by default; black on the plate).
  final Color? color;

  /// Deprecated: v2 draws no area under the line; ignored.
  final bool fill;

  /// Describe the trend for screen readers ("Son 6 ay harcama, artışta").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AknColors>() ?? AknColors.light;
    return Semantics(
      label: semanticLabel,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: SparklinePainter(
            values: values,
            color: color ?? c.ink,
            progress: 1,
            fill: false,
            surface: c.surface,
            dot: c.chartHighlight,
          ),
        ),
      ),
    );
  }
}

class SparklinePainter extends CustomPainter {
  SparklinePainter({
    required this.values,
    required this.color,
    required this.progress,
    required this.fill,
    required this.surface,
    this.dot,
  });

  final List<double> values;
  final Color color;

  /// Drawn share of the line (0..1).
  final double progress;

  /// Deprecated: ignored (no area fill in v2).
  final bool fill;
  final Color surface;

  /// End dot colour (defaults to [color]).
  final Color? dot;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = (maxV - minV).abs() < 1e-9 ? 1.0 : maxV - minV;
    const pad = 6.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    Offset at(int i) => Offset(
      pad + w * i / (values.length - 1),
      pad + h - h * (values[i] - minV) / span,
    );

    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p0 = at(i - 1);
      final p1 = at(i);
      final mx = (p0.dx + p1.dx) / 2;
      line.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, pad + w * progress + pad, size.height));
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    canvas.restore();
    if (progress >= 1) {
      final last = at(values.length - 1);
      canvas.drawCircle(last, 7, Paint()..color = surface);
      canvas.drawCircle(last, 5, Paint()..color = dot ?? color);
    }
  }

  @override
  bool shouldRepaint(SparklinePainter old) =>
      old.values != values ||
      old.color != color ||
      old.progress != progress ||
      old.surface != surface ||
      old.dot != dot;
}
