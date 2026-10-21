import 'package:flutter/widgets.dart';

import '../theme.dart';

/// ▲ / ▼ drawn as a filled triangle (design v2 §3.3, §6.19): Mona Sans has no
/// U+25B2 / U+25BC, so the arrow of a delta is painted, never typed.
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

  /// The 8 × 7 glyph used next to 13 px text (Tüpraş strip, readout deltas).
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

/// Paints a filled isosceles triangle filling its box, apex up or down.
class TrianglePainter extends CustomPainter {
  const TrianglePainter({required this.down, required this.color});

  final bool down;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = down
        ? (Path()
            ..moveTo(0, 0)
            ..lineTo(w, 0)
            ..lineTo(w / 2, h)
            ..close())
        : (Path()
            ..moveTo(w / 2, 0)
            ..lineTo(w, h)
            ..lineTo(0, h)
            ..close());
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(TrianglePainter old) =>
      old.down != down || old.color != color;
}
