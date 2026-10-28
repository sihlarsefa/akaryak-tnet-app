import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../tokens.dart';

/// Tiny trend line (design v3 §4): a smooth 2.5 px curve in the chart
/// highlight (orange on white; the plate's accent on the hero card) over a
/// soft gradient area that fades to nothing, ending in a dot with a surface
/// ring and a faint halo. It draws itself in from the left when first shown
/// (the end dot pops in last); reduce motion shows it at once.
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

  /// Line colour (`chartHighlight` by default — the plate accent on the
  /// plate card).
  final Color? color;

  /// The gradient area under the line.
  final bool fill;

  /// Describe the trend for screen readers ("Son 6 ay harcama, artışta").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AknColors>() ?? AknColors.light;
    final line = color ?? c.chartHighlight;
    return Semantics(
      label: semanticLabel,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: AknMotion.of(context, const Duration(milliseconds: 900)),
          curve: AknMotion.emphasizedCurve,
          builder: (context, progress, _) => CustomPaint(
            painter: SparklinePainter(
              values: values,
              color: line,
              progress: progress,
              fill: fill,
              surface: c.surface,
              dot: line,
            ),
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

  /// The gradient area under the line ([color] 22 % → 0 %).
  final bool fill;
  final Color surface;

  /// End dot colour (defaults to [color]).
  final Color? dot;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.isEmpty) return;
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = (maxV - minV).abs() < 1e-9 ? 1.0 : maxV - minV;
    const pad = 7.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    Offset at(int i) => Offset(
      pad + w * i / (values.length - 1),
      pad + h - h * (values[i] - minV) / span,
    );

    // Smooth curve: horizontal tangents at every point never overshoot.
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p0 = at(i - 1);
      final p1 = at(i);
      final mx = (p0.dx + p1.dx) / 2;
      line.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
    }
    final p = progress.clamp(0.0, 1.0);
    final reveal = pad + w * p;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, reveal + 2, size.height));
    if (fill) {
      final last = at(values.length - 1);
      final area = Path.from(line)
        ..lineTo(last.dx, size.height)
        ..lineTo(at(0).dx, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: color.a * 0.22),
              color.withValues(alpha: 0),
            ],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    canvas.restore();
    // The end dot pops in over the last 15 % of the draw-in.
    final pop = ((p - 0.85) / 0.15).clamp(0.0, 1.0);
    if (pop > 0) {
      final s = Curves.easeOutBack.transform(pop);
      final last = at(values.length - 1);
      final d = dot ?? color;
      canvas.drawCircle(
        last,
        10 * s,
        Paint()..color = d.withValues(alpha: d.a * 0.16),
      );
      canvas.drawCircle(last, 6.5 * s, Paint()..color = surface);
      canvas.drawCircle(last, 4.5 * s, Paint()..color = d);
    }
  }

  @override
  bool shouldRepaint(SparklinePainter old) =>
      old.values != values ||
      old.color != color ||
      old.progress != progress ||
      old.fill != fill ||
      old.surface != surface ||
      old.dot != dot;
}
