import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../tokens.dart';

/// Circular progress (upload progress, limit usage), design v3 §4: an
/// orange arc with rounded caps that brightens along its sweep (a light
/// orange tail → the logo orange head, with a soft glow at the head) on the
/// chart track. Changes of [value] glide on the emphasized curve; reduce
/// motion jumps.
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
    this.duration = AknMotion.count,
    this.semanticLabel,
    this.semanticValue,
  });

  /// 0..1 (clamped).
  final double value;
  final double size;
  final double strokeWidth;

  /// The head colour of the arc (logo orange by default); the tail is a
  /// lighter tint of it.
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
    final head = color ?? c.brandBright;
    return Semantics(
      label: semanticLabel,
      value: semanticValue ?? '%${(v * 100).round()}',
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: animateFromZero ? 0 : v, end: v),
        duration: AknMotion.of(context, duration),
        curve: AknMotion.emphasizedCurve,
        builder: (context, animated, child) => CustomPaint(
          painter: ProgressRingPainter(
            value: animated,
            strokeWidth: strokeWidth,
            color: head,
            trackColor: trackColor ?? c.chartTrack,
            tailColor: color == null
                ? c.brandFillStart
                : Color.lerp(head, const Color(0xFFFFFFFF), 0.3),
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

/// Paints the track and a rounded-cap arc from 12 o'clock that runs from
/// [tailColor] (at the start) to [color] (at the head), with a soft glow
/// under the head.
class ProgressRingPainter extends CustomPainter {
  ProgressRingPainter({
    required this.value,
    required this.strokeWidth,
    required this.color,
    required this.trackColor,
    this.tailColor,
  });

  final double value;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  /// The arc's start colour (null: solid [color]).
  final Color? tailColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor,
    );
    if (value <= 0) return;
    final sweep = 2 * math.pi * value;
    final tail = tailColor;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    if (tail == null || value < 0.02) {
      arc.color = color;
    } else {
      // The gradient starts half a stroke before 12 o'clock so the tail's
      // round cap keeps the tail colour (angles past the head clamp to it).
      final cap = strokeWidth / 2 / radius;
      arc.shader = SweepGradient(
        colors: [tail, color],
        endAngle: math.min(2 * math.pi, sweep + 2 * cap),
        transform: GradientRotation(-math.pi / 2 - cap),
      ).createShader(rect);
    }
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc);
    // A soft glow under the head (not on hairline rings).
    if (strokeWidth >= 3 && value < 1) {
      final head = center + Offset.fromDirection(-math.pi / 2 + sweep, radius);
      canvas.drawCircle(
        head,
        strokeWidth * 0.9,
        Paint()
          ..color = color.withValues(alpha: color.a * 0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeWidth * 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(ProgressRingPainter old) =>
      old.value != value ||
      old.strokeWidth != strokeWidth ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.tailColor != tailColor;
}
