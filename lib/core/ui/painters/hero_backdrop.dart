import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../tokens.dart';

/// Deprecated: how the old hero laid out its gradient. Both styles paint the
/// same v3 band.
enum AknHeroStyle { panel, strip }

/// The header band's gradient (owner decision G, design v3 §4).
abstract final class AknHeroGradient {
  /// The band's deepest colour ([AknColors.heroEnd]).
  static Color deep(AknColors c) => c.heroEnd;

  /// The header band gradient ([AknColors.bandGradient], owner decision G).
  static LinearGradient of(
    AknColors c, {
    AknHeroStyle style = AknHeroStyle.panel,
  }) => c.bandGradient;

  /// The CSS-exact 135° band gradient over a box of [size]: the colour
  /// lines run at 45° whatever the box's aspect ratio (`AknBand` lays it
  /// over the screen width so the band and its tail join without a seam).
  static LinearGradient anchored(AknColors c, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return c.bandGradient;
    final ax = (w + h) / (2 * w);
    final ay = (w + h) / (2 * h);
    return LinearGradient(
      begin: Alignment(-ax, -ay),
      end: Alignment(ax, ay),
      colors: [c.heroStart, c.heroMid, c.heroEnd],
      stops: const [0, 0.5, 1],
    );
  }
}

/// The luminous orange band of design v3 "Akış" (§4): the 135° band
/// gradient (`heroStart` → `heroMid` → `heroEnd`) lit by soft, layered
/// lights — a `heroGlow` light (55 %) at the top-left, a warm white one
/// (10 %) at the bottom-right and a faint diagonal sheen. With [phase]
/// (0–1 over [AknMotion.bandDrift]) the two lights drift on slow ellipses
/// in opposite directions and, once per cycle, a soft light sweeps across
/// the band; phase 0 is the resting frame. No blue, no navy.
///
/// [highlight] false paints the plain gradient; [depth] deepens the bottom
/// edge; [light] tints the warm light and the sheen (white). [reference] is
/// the box the gradient and the lights are laid over (default: the canvas)
/// — `AknBandFill` anchors it to the screen. [style] and [watermark] are
/// accepted and ignored.
class HeroBackdropPainter extends CustomPainter {
  HeroBackdropPainter({
    required this.colors,
    this.style = AknHeroStyle.panel,
    this.watermark = true,
    this.highlight = true,
    this.depth = false,
    this.light = Colors.white,
    this.phase = 0,
    this.reference,
  });

  final AknColors colors;
  final AknHeroStyle style;
  final bool watermark;

  /// Paint the lights (glow, warm light, sheen) over the gradient.
  final bool highlight;

  /// A soft `heroEnd` shade along the bottom edge.
  final bool depth;

  /// Colour of the warm lower light and the sheen.
  final Color light;

  /// Ambient drift position, 0–1 over [AknMotion.bandDrift] (0 = rest).
  final double phase;

  /// The gradient's box in the canvas's coordinates (default: the canvas).
  final Rect? reference;

  /// Where in the drift cycle the light sweep runs (fractions of a cycle).
  static const double _sweepStart = 0.56;
  static const double _sweepEnd = 0.84;

  /// Paints the band into [rect]: the gradient and its lights are laid over
  /// [reference] (default [rect]) so pieces of one band painted separately
  /// match. [phase] places the drifting lights (see [HeroBackdropPainter]).
  static void paintBand(
    Canvas canvas,
    Rect rect,
    AknColors colors, {
    Rect? reference,
    double phase = 0,
    bool lights = true,
    bool depth = false,
    Color light = const Color(0xFFFFFFFF),
  }) {
    if (rect.isEmpty) return;
    final ref = reference ?? rect;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = AknHeroGradient.anchored(colors, ref.size).createShader(ref),
    );
    if (lights && !ref.isEmpty) {
      _paintLights(canvas, rect, ref, colors, phase, light);
    }
    if (depth) {
      final shade = Rect.fromLTRB(
        ref.left,
        ref.bottom - ref.height * 0.35,
        ref.right,
        ref.bottom,
      );
      canvas.drawRect(
        rect.intersect(shade),
        Paint()
          ..shader = ui.Gradient.linear(shade.topCenter, shade.bottomCenter, [
            colors.heroEnd.withValues(alpha: 0),
            colors.heroEnd.withValues(alpha: 0.35),
          ]),
      );
    }
  }

  static void _paintLights(
    Canvas canvas,
    Rect rect,
    Rect ref,
    AknColors c,
    double phase,
    Color light,
  ) {
    final w = ref.width;
    final h = ref.height;
    final span = math.max(w, h);
    final a = phase * 2 * math.pi;

    // 1. The glow: heroGlow at 55 % in the top-left corner, drifting on a
    //    slow ellipse; it fades out before the greeting's second half.
    final glow = Offset(
      ref.left + w * (0.06 + 0.05 * math.cos(a)),
      ref.top + h * (0.0 + 0.12 * math.sin(a)),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          glow,
          span * 0.58,
          [
            c.heroGlow.withValues(alpha: 0.55),
            c.heroGlow.withValues(alpha: 0.2),
            c.heroGlow.withValues(alpha: 0),
          ],
          const [0, 0.42, 1],
        ),
    );

    // 2. The warm light: white 10 % at the bottom-right, drifting the other
    //    way round.
    final warm = Offset(
      ref.left + w * (0.92 - 0.06 * math.cos(a)),
      ref.top + h * (1.0 - 0.14 * math.sin(a)),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          warm,
          span * 0.52,
          [
            light.withValues(alpha: 0.1),
            light.withValues(alpha: 0.035),
            light.withValues(alpha: 0),
          ],
          const [0, 0.5, 1],
        ),
    );

    // 3. The sheen: a wide, faint diagonal band of light across the middle.
    final from = ref.topLeft;
    final to = Offset(ref.left + span * 0.9, ref.top + span * 0.9);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          from,
          to,
          [
            light.withValues(alpha: 0),
            light.withValues(alpha: 0.05),
            light.withValues(alpha: 0),
          ],
          const [0.2, 0.36, 0.52],
        ),
    );

    // 4. The sweep: once per drift cycle a soft streak of light crosses the
    //    band from left to right (never at rest, phase 0).
    if (phase > _sweepStart && phase < _sweepEnd) {
      final u = Curves.easeInOut.transform(
        (phase - _sweepStart) / (_sweepEnd - _sweepStart),
      );
      final centre = -0.25 + 1.5 * u;
      const half = 0.12;
      final fade = math.sin(u * math.pi);
      final axisEnd = Offset(ref.left + w, ref.top + w * 0.6);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            ref.topLeft,
            axisEnd,
            [
              light.withValues(alpha: 0),
              light.withValues(alpha: 0.13 * fade),
              light.withValues(alpha: 0),
            ],
            [
              (centre - half).clamp(0.0, 1.0),
              centre.clamp(0.0, 1.0),
              (centre + half).clamp(0.0, 1.0),
            ],
          ),
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) => paintBand(
    canvas,
    Offset.zero & size,
    colors,
    reference: reference,
    phase: phase,
    lights: highlight,
    depth: depth,
    light: light,
  );

  @override
  bool shouldRepaint(HeroBackdropPainter old) =>
      old.colors != colors ||
      old.phase != phase ||
      old.reference != reference ||
      old.highlight != highlight ||
      old.depth != depth ||
      old.light != light;
}

/// The v3 band behind [child] (or filling its box): [HeroBackdropPainter]
/// with its lights drifting through [AknAmbient] (at rest in tests and under
/// reduce motion). New code uses `AknBand`, which anchors the band to the
/// screen.
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

  /// Paint the band's lights (and let them drift).
  final bool highlight;

  /// Deepen the bottom edge.
  final bool depth;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AknColors>() ?? AknColors.light;
    final paint = RepaintBoundary(
      child: AknAmbient(
        period: AknMotion.bandDrift,
        curve: Curves.linear,
        builder: (context, t, _) => CustomPaint(
          painter: HeroBackdropPainter(
            colors: c,
            style: style,
            highlight: highlight,
            depth: depth,
            phase: highlight ? t : 0,
          ),
          child: child == null ? const SizedBox.expand() : null,
        ),
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
