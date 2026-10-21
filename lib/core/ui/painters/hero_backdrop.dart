import 'package:flutter/material.dart';

import '../tokens.dart';
import 'logo_mark.dart';

/// How a hero surface lays out its orange gradient.
enum AknHeroStyle {
  /// Hero panels (cards, 24 radius): the light comes from the top-right
  /// corner (with a soft white highlight and the » watermark) and the colour
  /// deepens toward the bottom-left, where text starts.
  panel,

  /// The full-width header strip (`AppScaffold(hero: true)` app bar +
  /// `AknHeroHeader`): light at the right edge, deep at the left where the
  /// title and greeting sit. Purely horizontal, so the app bar and the header
  /// block below it join without a seam.
  strip,
}

/// The hero gradient (single source of truth for every orange surface).
///
/// AA by construction: in light mode the vivid [AknColors.heroStart] only
/// fills the first third of the gradient (top-right corner of a panel, right
/// edge of the strip); everywhere text can start the colour is
/// [AknColors.heroEnd] or deeper, where white text keeps ≥ 4.5:1. Dark mode
/// uses the spec gradient (#C2410C → #8F3307), safe everywhere.
abstract final class AknHeroGradient {
  /// [AknColors.heroEnd] deepened by 8 % (light mode's far end).
  static Color deep(AknColors c) =>
      Color.lerp(c.heroEnd, const Color(0xFF000000), 0.08)!;

  static LinearGradient of(
    AknColors c, {
    AknHeroStyle style = AknHeroStyle.panel,
  }) {
    final (begin, end) = switch (style) {
      AknHeroStyle.panel => (Alignment.topRight, Alignment.bottomLeft),
      AknHeroStyle.strip => (Alignment.centerRight, Alignment.centerLeft),
    };
    if (c.isDark) {
      return LinearGradient(
        begin: begin,
        end: end,
        colors: [c.heroStart, c.heroEnd],
      );
    }
    return LinearGradient(
      begin: begin,
      end: end,
      colors: [c.heroStart, c.heroEnd, deep(c)],
      stops: style == AknHeroStyle.panel
          ? const [0, 0.32, 1]
          : const [0, 0.4, 1],
    );
  }
}

/// Orange hero background: the [AknHeroGradient], an optional soft white
/// highlight in the top-right corner (panels), an optional vertical depth
/// (header block) and a faint » watermark that fades out toward the text.
/// Calm; no glow animation, no motion.
class HeroBackdropPainter extends CustomPainter {
  HeroBackdropPainter({
    required this.colors,
    this.style = AknHeroStyle.panel,
    this.watermark = true,
    this.highlight = true,
    this.depth = false,
    this.light = const Color(0xFFFFFFFF),
  });

  final AknColors colors;
  final AknHeroStyle style;
  final bool watermark;

  /// Soft white radial light in the top-right corner (panels only; text is
  /// not expected there).
  final bool highlight;

  /// Darkens the lower part slightly (header block under the app bar): the
  /// top edge stays untouched so it meets the app bar seamlessly.
  final bool depth;
  final Color light;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (rect.isEmpty) return;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = AknHeroGradient.of(colors, style: style).createShader(rect),
    );
    if (depth) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0x10000000)],
          ).createShader(rect),
      );
    }
    if (highlight && style == AknHeroStyle.panel) {
      final radius = (size.height * 0.9).clamp(96.0, 220.0);
      final center = Offset(size.width - radius * 0.1, -radius * 0.25);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              light.withValues(alpha: colors.isDark ? 0.10 : 0.16),
              light.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
    if (!watermark || size.height < 40) return;
    _watermark(canvas, size, rect);
  }

  /// » cropped by the right edge; strongest in the light corner, fading to
  /// nothing toward the text.
  void _watermark(Canvas canvas, Size size, Rect rect) {
    final h = (style == AknHeroStyle.strip ? size.height * 1.25 : size.height)
        .clamp(60.0, 260.0);
    final s = h / 80;
    canvas.saveLayer(rect, Paint());
    canvas.save();
    canvas.translate(size.width - h * 0.66, size.height / 2 - h / 2);
    canvas.scale(s);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = light.withValues(alpha: colors.isDark ? 0.07 : 0.09);
    canvas.drawPath(LogoMarkPainter.chevronPath(0), stroke);
    canvas.drawPath(LogoMarkPainter.chevronPath(1), stroke);
    canvas.restore();
    // Fade mask: full at the light edge, gone where text lives.
    final (begin, end) = style == AknHeroStyle.panel
        ? (Alignment.topRight, Alignment.bottomLeft)
        : (Alignment.centerRight, Alignment.centerLeft);
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = LinearGradient(
          begin: begin,
          end: end,
          colors: const [
            Color(0xFFFFFFFF),
            Color(0x99FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: const [0, 0.3, 0.6],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(HeroBackdropPainter old) =>
      old.colors != colors ||
      old.style != style ||
      old.watermark != watermark ||
      old.highlight != highlight ||
      old.depth != depth ||
      old.light != light;
}

/// Paints the hero background behind [child] (or fills its box) in its own
/// repaint layer, so animated content on the hero never repaints the
/// gradient.
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
    final paint = RepaintBoundary(
      child: CustomPaint(
        painter: HeroBackdropPainter(
          colors: c,
          style: style,
          watermark: watermark,
          highlight: highlight,
          depth: depth,
        ),
        child: child == null ? const SizedBox.expand() : null,
      ),
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
