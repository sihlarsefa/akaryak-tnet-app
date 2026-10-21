import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../tokens.dart';

/// A fuel drop that fills by [fill] (delivered / planned litres). The level
/// rises smoothly when [fill] changes; with [flowing] a slow, shallow wave
/// moves on the surface (off under reduce motion).
///
/// Ported from F2GO's `_DolanDamlaBoyayici`, recoloured to the brand.
class FuelDrop extends StatefulWidget {
  const FuelDrop({
    super.key,
    required this.fill,
    this.size = 40,
    this.color,
    this.flowing = false,
    this.semanticLabel,
  });

  /// 0..1 (clamped).
  final double fill;

  /// Height; width is 80 % of it.
  final double size;
  final Color? color;
  final bool flowing;
  final String? semanticLabel;

  @override
  State<FuelDrop> createState() => _FuelDropState();
}

class _FuelDropState extends State<FuelDrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(FuelDrop old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.flowing && !AknMotion.reduced(context);
    if (run && !_wave.isAnimating) {
      _wave.repeat();
    } else if (!run && _wave.isAnimating) {
      _wave.stop();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AknColors>() ?? AknColors.light;
    final color = widget.color ?? c.brandBright;
    final f = widget.fill.isNaN ? 0.0 : widget.fill.clamp(0.0, 1.0);
    final size = Size(widget.size * 0.8, widget.size);
    return Semantics(
      label: widget.semanticLabel,
      value: '%${(f * 100).round()}',
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: f),
        duration: AknMotion.of(context, AknMotion.emphasized),
        curve: AknMotion.emphasizedCurve,
        builder: (context, level, _) => AnimatedBuilder(
          animation: _wave,
          builder: (context, _) => CustomPaint(
            size: size,
            painter: FuelDropPainter(
              fill: level,
              color: color,
              wavePhase: widget.flowing ? _wave.value : null,
            ),
          ),
        ),
      ),
    );
  }
}

class FuelDropPainter extends CustomPainter {
  FuelDropPainter({required this.fill, required this.color, this.wavePhase});

  final double fill;
  final Color color;
  final double? wavePhase;

  static Path dropPath(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w / 2, 0)
      ..quadraticBezierTo(w, h * 0.42, w, h * 0.64)
      ..arcToPoint(
        Offset(0, h * 0.64),
        radius: Radius.circular(w / 2),
        clockwise: true,
      )
      ..quadraticBezierTo(0, h * 0.42, w / 2, 0)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final drop = dropPath(size);
    canvas.drawPath(drop, Paint()..color = color.withValues(alpha: 0.12));
    if (fill > 0) {
      canvas.save();
      canvas.clipPath(drop);
      final level = h * (1 - fill);
      final surface = Path()..moveTo(0, h);
      if (wavePhase == null || fill >= 1) {
        surface.lineTo(0, level);
        surface.lineTo(w, level);
      } else {
        final amp = math.min(h * 0.035, 2.2);
        surface.lineTo(0, level);
        for (var x = 0.0; x <= w; x += w / 12) {
          final y =
              level +
              amp * math.sin((x / w) * 2 * math.pi + wavePhase! * 2 * math.pi);
          surface.lineTo(x, y);
        }
      }
      surface
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(surface, Paint()..color = color);
      canvas.restore();
    }
    canvas.drawPath(
      drop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, h * 0.035)
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(FuelDropPainter old) =>
      old.fill != fill || old.color != color || old.wavePhase != wavePhase;
}
