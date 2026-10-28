import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../tokens.dart';
import 'path_trim.dart';

/// Success moment (design v3 §5): a soft tone disc pops in, the ring draws
/// itself around it and the check is drawn in; the mark gives a small pop
/// and a ring of particles bursts out once (finite) — then one soft success
/// haptic. 72 px in result views; small sizes (inline chips) skip the
/// burst.
///
/// Reduce motion shows the finished check at once (haptic still fires).
class SuccessCheck extends StatefulWidget {
  const SuccessCheck({
    super.key,
    this.size = 72,
    this.tone = AknTone.ok,
    this.animate = true,
    this.haptic = true,
    this.duration = const Duration(milliseconds: 900),
    this.onCompleted,
    this.semanticLabel = 'Başarılı',
    this.burst = true,
  });

  final double size;
  final AknTone tone;
  final bool animate;
  final bool haptic;
  final Duration duration;
  final VoidCallback? onCompleted;
  final String? semanticLabel;

  /// The particle burst (drawn only from 40 px up).
  final bool burst;

  @override
  State<SuccessCheck> createState() => _SuccessCheckState();
}

class _SuccessCheckState extends State<SuccessCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.animate || AknMotion.reduced(context)) {
      _c.value = 1;
      _finish();
    } else {
      _c.forward().whenComplete(_finish);
    }
  }

  void _finish() {
    if (!mounted) return;
    if (widget.haptic) AknHaptics.success();
    widget.onCompleted?.call();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AknColors>() ?? AknColors.light;
    final tone = c.tone(widget.tone);
    final burst = widget.burst && widget.size >= 40;
    final painted = RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: SuccessCheckPainter(
            t: _c.value,
            color: tone.fg,
            fill: tone.bg,
            line: tone.line,
            particle: burst ? tone.solid : null,
            particleAlt: burst ? c.brandBright : null,
          ),
        ),
      ),
    );
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: painted);
    return Semantics(label: label, image: true, child: painted);
  }
}

/// Paints the success mark at linear progress [t] (0..1):
///
/// * 0–0.42: the [fill] disc pops in (overshoot) and its [line] rim fades in;
/// * 0.05–0.5: the [color] ring draws clockwise from 12 o'clock;
/// * 0.36–0.72: the check draws in;
/// * 0.6–0.86: the mark pops (scale 1 → 1.07 → 1);
/// * 0.52–1: [particle] / [particleAlt] dots and streaks burst outwards and
///   fade — nothing of the burst is left at `t = 1`.
class SuccessCheckPainter extends CustomPainter {
  SuccessCheckPainter({
    required this.t,
    required this.color,
    required this.fill,
    required this.line,
    this.particle,
    this.particleAlt,
  });

  /// Linear progress 0..1.
  final double t;
  final Color color;

  /// The soft disc behind the check (transparent: none).
  final Color fill;

  /// The disc's rim.
  final Color line;

  /// Burst colours; null [particle] draws no burst.
  final Color? particle;
  final Color? particleAlt;

  static double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final center = size.center(Offset.zero);
    final stroke = math.max(2.0, r * 0.075);
    final appear = _seg(t, 0, 0.42);
    final disc = appear <= 0 ? 0.0 : AknMotion.pop.transform(appear);
    final ring = AknMotion.emphasizedCurve.transform(_seg(t, 0.05, 0.5));
    final check = AknMotion.emphasizedCurve.transform(_seg(t, 0.36, 0.72));
    final pop = 1 + 0.07 * math.sin(math.pi * _seg(t, 0.6, 0.86));

    _burst(canvas, center, r);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(pop);
    canvas.translate(-center.dx, -center.dy);
    final rr = r - stroke / 2;
    // The soft disc pops in from the centre.
    if (disc > 0 && fill.a > 0) {
      final fade = _seg(t, 0, 0.18);
      canvas.drawCircle(
        center,
        rr * (0.55 + 0.45 * disc),
        Paint()..color = fill.withValues(alpha: fill.a * fade),
      );
      canvas.drawCircle(
        center,
        rr * (0.55 + 0.45 * disc),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, stroke * 0.5)
          ..color = line.withValues(alpha: line.a * fade),
      );
    }
    // The ring draws itself.
    if (ring > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: rr),
        -math.pi / 2,
        2 * math.pi * ring,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
    // Check mark.
    if (check > 0) {
      final s = r * 2;
      final path = Path()
        ..moveTo(center.dx - s * 0.19, center.dy + s * 0.01)
        ..lineTo(center.dx - s * 0.055, center.dy + s * 0.14)
        ..lineTo(center.dx + s * 0.205, center.dy - s * 0.125);
      canvas.drawPath(
        trimPath(path, check),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 1.35
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      );
    }
    canvas.restore();
  }

  void _burst(Canvas canvas, Offset center, double r) {
    final a = particle;
    if (a == null) return;
    final b = _seg(t, 0.52, 1);
    if (b <= 0 || b >= 1) return;
    final travel = Curves.easeOutCubic.transform(b);
    final fade = 1 - Curves.easeInCubic.transform(b);
    const n = 12;
    for (var i = 0; i < n; i++) {
      final odd = i.isOdd;
      final angle = -math.pi / 2 + i * 2 * math.pi / n + (odd ? 0.12 : 0);
      final dir = Offset.fromDirection(angle);
      final dist = r * (1.04 + (odd ? 0.3 : 0.44) * travel);
      final color = i % 3 == 1 ? (particleAlt ?? a) : a;
      final paint = Paint()
        ..color = color.withValues(alpha: color.a * fade)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.5, r * 0.07);
      if (odd) {
        // A small dot.
        canvas.drawCircle(
          center + dir * dist,
          math.max(1.2, r * 0.06 * (1 - 0.5 * b)),
          paint,
        );
      } else {
        // A short streak pointing outwards, shrinking as it flies.
        final len = r * 0.16 * (1 - b);
        canvas.drawLine(
          center + dir * dist,
          center + dir * (dist + len),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(SuccessCheckPainter old) =>
      old.t != t ||
      old.color != color ||
      old.fill != fill ||
      old.line != line ||
      old.particle != particle ||
      old.particleAlt != particleAlt;
}
