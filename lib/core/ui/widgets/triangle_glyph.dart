import 'package:flutter/widgets.dart';

import '../theme.dart';

/// ▲ / ▼ drawn as a solid triangle with softly rounded corners (design v3
/// §4, the delta chip's direction arrow): a painted glyph, never a typed
/// character, so it is crisp at every size and matches the rounded Phosphor
/// icons around it.
///
/// 9 × 8 by default ([TriangleGlyph.small] is 8 × 7), in the current text
/// colour unless [color] is given. It grows with the text scale so it keeps
/// its proportion to the label beside it. Decorative: the label next to it
/// carries the meaning ("artış", "düşüş"), so it is hidden from screen
/// readers.
class TriangleGlyph extends StatelessWidget {
  const TriangleGlyph({
    super.key,
    this.down = false,
    this.width = 9,
    this.height = 8,
    this.color,
    this.scaleWithText = true,
  });

  /// The 8 × 7 glyph used next to 13 px text (Tüpraş strip, readout deltas,
  /// the delta chip).
  const TriangleGlyph.small({
    super.key,
    this.down = false,
    this.color,
    this.scaleWithText = true,
  }) : width = 8,
       height = 7;

  /// Points down (▼) instead of up (▲).
  final bool down;
  final double width;
  final double height;

  /// Defaults to the ambient `DefaultTextStyle` colour.
  final Color? color;

  /// Grow with `MediaQuery.textScalerOf` (on by default).
  final bool scaleWithText;

  @override
  Widget build(BuildContext context) {
    final s = scaleWithText
        ? MediaQuery.textScalerOf(context).scale(14) / 14
        : 1.0;
    final fill =
        color ?? DefaultTextStyle.of(context).style.color ?? context.akn.ink;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(width * s, height * s),
        painter: TrianglePainter(down: down, color: fill),
      ),
    );
  }
}

/// Paints a solid isosceles triangle filling its box, apex up or down, its
/// corners rounded by [cornerRadius] (a share of the box's shorter side).
class TrianglePainter extends CustomPainter {
  const TrianglePainter({
    required this.down,
    required this.color,
    this.cornerRadius = 0.14,
  });

  final bool down;
  final Color color;

  /// Corner rounding as a fraction of the shorter side (0 = sharp).
  final double cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;
    final apex = down ? Offset(w / 2, h) : Offset(w / 2, 0);
    final left = down ? Offset.zero : Offset(0, h);
    final right = down ? Offset(w, 0) : Offset(w, h);
    // Round the corners without growing the glyph: shrink the triangle
    // towards its incentre by the corner radius, then fill it and stroke it
    // with round joins as wide as twice the radius.
    final a = (right - left).distance; // opposite the apex
    final b = (apex - right).distance; // opposite the left corner
    final c = (left - apex).distance; // opposite the right corner
    final perimeter = a + b + c;
    final area = w * h / 2;
    final inradius = 2 * area / perimeter;
    final r = (size.shortestSide * cornerRadius).clamp(0.0, inradius * 0.8);
    final centre = (apex * a + left * b + right * c) / perimeter;
    final k = r <= 0 ? 1.0 : (inradius - r) / inradius;
    Offset shrink(Offset p) => centre + (p - centre) * k;
    final path = Path()
      ..moveTo(shrink(apex).dx, shrink(apex).dy)
      ..lineTo(shrink(right).dx, shrink(right).dy)
      ..lineTo(shrink(left).dx, shrink(left).dy)
      ..close();
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    canvas.drawPath(path, paint);
    if (r > 0) {
      canvas.drawPath(
        path,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 2
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(TrianglePainter old) =>
      old.down != down ||
      old.color != color ||
      old.cornerRadius != cornerRadius;
}
