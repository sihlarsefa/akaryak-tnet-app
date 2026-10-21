import 'package:flutter/material.dart';

import '../tokens.dart';

/// Deprecated: how the old hero laid out its gradient. v2 has no gradient,
/// no watermark and no header strip (§1 rule 4, §11); both styles paint the
/// same flat plate.
enum AknHeroStyle { panel, strip }

/// Deprecated: v2 has no gradients anywhere. Kept so old call sites compile;
/// every "gradient" is the flat plate colour.
abstract final class AknHeroGradient {
  /// = [AknColors.plate].
  static Color deep(AknColors c) => c.plate;

  /// A flat (single-colour) gradient in [AknColors.plate].
  static LinearGradient of(
    AknColors c, {
    AknHeroStyle style = AknHeroStyle.panel,
  }) => LinearGradient(colors: [c.plate, c.plate]);
}

/// Deprecated hero background: fills its box with the flat plate colour —
/// no gradient, no highlight, no depth, no » watermark (design v2 §11). The
/// flags are accepted and ignored.
class HeroBackdropPainter extends CustomPainter {
  HeroBackdropPainter({
    required this.colors,
    this.style = AknHeroStyle.panel,
    this.watermark = true,
    this.highlight = true,
    this.depth = false,
    this.light = Colors.white,
  });

  final AknColors colors;
  final AknHeroStyle style;
  final bool watermark;
  final bool highlight;
  final bool depth;
  final Color light;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (rect.isEmpty) return;
    canvas.drawRect(rect, Paint()..color = colors.plate);
  }

  @override
  bool shouldRepaint(HeroBackdropPainter old) => old.colors != colors;
}

/// Deprecated: paints the flat plate behind [child] (or fills its box). New
/// code uses the plate widget instead.
class AknHeroBackground extends StatelessWidget {
  const AknHeroBackground({
    super.key,
    this.child,
    this.style = AknHeroStyle.panel,
    this.watermark = true,
    this.highlight = true,
    this.depth = false,
  });

  final Widget? child;
  final AknHeroStyle style;
  final bool watermark;
  final bool highlight;
  final bool depth;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AknColors>() ?? AknColors.light;
    final paint = CustomPaint(
      painter: HeroBackdropPainter(colors: c, style: style),
      child: child == null ? const SizedBox.expand() : null,
    );
    if (child == null) return paint;
    return Stack(
      children: [
        Positioned.fill(child: paint),
        child!,
      ],
    );
  }
}
