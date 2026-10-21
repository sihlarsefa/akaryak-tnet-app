import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../tokens.dart';
import 'path_trim.dart';

/// Success moment: a ring draws itself, the disc fills softly and a check is
/// drawn in (600 ms, emphasized), with one soft haptic at the end.
///
/// Reduce motion shows the finished check at once (haptic still fires).
class SuccessCheck extends StatefulWidget {
  const SuccessCheck({
    super.key,
    this.size = 88,
    this.tone = AknTone.ok,
    this.animate = true,
    this.haptic = true,
    this.duration = AknMotion.emphasized,
    this.onCompleted,
    this.semanticLabel = 'Başarılı',
  });

  final double size;
  final AknTone tone;
  final bool animate;
  final bool haptic;
  final Duration duration;
  final VoidCallback? onCompleted;
  final String? semanticLabel;

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
    final painted = AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: SuccessCheckPainter(
          t: _c.value,
          color: tone.fg,
          fill: tone.bg,
          line: tone.line,
        ),
      ),
    );
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: painted);
    return Semantics(label: label, image: true, child: painted);
  }
}

class SuccessCheckPainter extends CustomPainter {
  SuccessCheckPainter({
    required this.t,
    required this.color,
    required this.fill,
    required this.line,
  });

  /// Linear progress 0..1.
  final double t;
  final Color color;
  final Color fill;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final center = size.center(Offset.zero);
    final stroke = math.max(2.5, r * 0.09);
    final ring = AknMotion.emphasizedCurve.transform(
      (t / 0.55).clamp(0.0, 1.0),
    );
    final disc = Curves.easeOut.transform(((t - 0.25) / 0.45).clamp(0.0, 1.0));
    final check = AknMotion.emphasizedCurve.transform(
      ((t - 0.45) / 0.55).clamp(0.0, 1.0),
    );

    // Soft disc grows from the centre.
    if (disc > 0) {
      canvas.drawCircle(
        center,
        (r - stroke / 2) * (0.6 + 0.4 * disc),
        Paint()..color = fill.withValues(alpha: fill.a * disc),
      );
    }
    // Ring track + drawn ring.
    final rect = Rect.fromCircle(center: center, radius: r - stroke / 2);
    canvas.drawCircle(
      center,
      r - stroke / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = line.withValues(alpha: line.a * ring),
    );
    if (ring > 0) {
      canvas.drawArc(
        rect,
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
        ..moveTo(center.dx - s * 0.2, center.dy + s * 0.01)
        ..lineTo(center.dx - s * 0.06, center.dy + s * 0.15)
        ..lineTo(center.dx + s * 0.22, center.dy - s * 0.14);
      final partial = trimPath(path, check);
      canvas.drawPath(
        partial,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 1.25
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(SuccessCheckPainter old) =>
      old.t != t || old.color != color || old.fill != fill || old.line != line;
}
