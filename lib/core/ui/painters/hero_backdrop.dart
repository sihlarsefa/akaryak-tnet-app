import 'package:flutter/material.dart';

import 'logo_mark.dart';

/// Navy hero background: a subtle diagonal light from the top-left and a
/// faint » watermark on the right. Calm; no glow, no motion.
class HeroBackdropPainter extends CustomPainter {
  HeroBackdropPainter({
    required this.navy,
    this.light = const Color(0xFFFFFFFF),
    this.watermark = true,
  });

  final Color navy;
  final Color light;
  final bool watermark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = navy);
    // Diagonal light band.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            light.withValues(alpha: 0.075),
            light.withValues(alpha: 0.02),
            light.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 0.8],
        ).createShader(rect),
    );
    // Fade the light out towards the top edge, so a hero placed right under
    // a flat navy app bar shows no seam.
    final fade = (size.height * 0.3).clamp(0.0, 48.0);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, fade),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [navy, navy.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, fade)),
    );
    if (!watermark || size.height < 40) return;
    // » watermark, cropped by the right edge.
    final h = size.height * 1.1;
    final s = h / 80;
    canvas.save();
    canvas.clipRect(rect);
    canvas.translate(size.width - h * 0.62, size.height / 2 - h / 2);
    canvas.scale(s);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = light.withValues(alpha: 0.045);
    canvas.drawPath(LogoMarkPainter.chevronPath(0), stroke);
    canvas.drawPath(LogoMarkPainter.chevronPath(1), stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(HeroBackdropPainter old) =>
      old.navy != navy || old.light != light || old.watermark != watermark;
}
