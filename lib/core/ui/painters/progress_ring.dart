import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../tokens.dart';

/// Circular progress (quote expiry countdown, limit usage, step progress).
/// Changes of [value] animate (base 250 ms); reduce motion jumps.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 44,
    this.strokeWidth = 4,
    this.color,
    this.trackColor,
    this.child,
    this.animateFromZero = false,
    this.duration = AknMotion.base,
    this.semanticLabel,
    this.semanticValue,
  });

  /// 0..1 (clamped).
  final double value;
  final double size;
  final double strokeWidth;
  final Color? color;
  final Color? trackColor;
  final Widget? child;

  /// Animate from empty on first build (KPI reveal).
  final bool animateFromZero;
  final Duration duration;
  final String? semanticLabel;

  /// Defaults to the percentage ("%45").
  final String? semanticValue;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AknColors>() ?? AknColors.light;
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: semanticValue ?? '%${(v * 100).round()}',
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: animateFromZero ? 0 : v, end: v),
        duration: AknMotion.of(context, duration),
        curve: AknMotion.standard,
        builder: (context, animated, child) => CustomPaint(
          painter: ProgressRingPainter(
            value: animated,
            strokeWidth: strokeWidth,
            color: color ?? c.brand,
            trackColor: trackColor ?? c.lineSoft,
          ),
          child: child,
        ),
        child: SizedBox.square(
          dimension: size,
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
  }
}

class ProgressRingPainter extends CustomPainter {
  ProgressRingPainter({
    required this.value,
    required this.strokeWidth,
    required this.color,
    required this.trackColor,
  });

  final double value;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - strokeWidth) / 2,
    );
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor,
    );
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(ProgressRingPainter old) =>
      old.value != value ||
      old.strokeWidth != strokeWidth ||
      old.color != color ||
      old.trackColor != trackColor;
}
