import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../tokens.dart';

/// Tiny trend line (spending, KPI trend). Draws itself in once
/// (slow 400 ms); the last point gets a dot.
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
  final Color? color;
  final bool fill;

  /// Describe the trend for screen readers ("Son 6 ay harcama, artışta").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AknColors>() ?? AknColors.light;
    final color = this.color ?? c.brand;
    return Semantics(
      label: semanticLabel,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: AknMotion.of(context, AknMotion.slow),
          curve: AknMotion.emphasizedCurve,
          builder: (context, t, _) => CustomPaint(
            painter: SparklinePainter(
              values: values,
              color: color,
              progress: t,
              fill: fill,
              surface: c.surface,
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
  });

  final List<double> values;
  final Color color;
  final double progress;
  final bool fill;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = (maxV - minV).abs() < 1e-9 ? 1.0 : maxV - minV;
    const pad = 4.0;
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
    if (fill) {
      final area = Path.from(line)
        ..lineTo(at(values.length - 1).dx, size.height)
        ..lineTo(at(0).dx, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );
    }
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
      canvas.drawCircle(last, 4, Paint()..color = surface);
      canvas.drawCircle(last, 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(SparklinePainter old) =>
      old.values != values ||
      old.color != color ||
      old.progress != progress ||
      old.fill != fill ||
      old.surface != surface;
}
