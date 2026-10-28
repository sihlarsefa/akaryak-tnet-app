import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../status.dart';
import '../theme.dart';
import '../tokens.dart';

/// Pill sizes: medium = 26 px high, 8 px dot; small = 22 px high, 6 px dot.
/// Both set the label in 12/16 700.
enum AknLampSize { small, medium }

/// Status as a tinted pill (design v3 §4 "Status chips / lamps"): the tone's
/// soft well (`ToneColors.bg`) with the Turkish label in the tone's text
/// colour (12/16 700) and a leading 8 px dot in the tone's solid colour
/// inside a 3 px halo. Status is never colour alone — the word always
/// carries it.
///
/// Tone → look:
/// * `brand` ("your move"): orange dot whose halo breathes (`AknAmbient`,
///   `AknMotion.breathe`), Pas label on the soft orange well.
/// * `info` (in progress, someone else's move): ink dot, ink label, grey
///   well.
/// * `ok` / `warn` / `danger`: the tone's dot, label and well.
/// * `neutral` (closed, cancelled): a hollow ring, dim label.
///
/// [solid] (terminal successes such as "Tamamlandı") swaps the dot for a
/// small check disc. When the status changes the well's colour glides and
/// the new mark pops in. On the orange band the pill turns to white glass.
/// The label wraps instead of being cut (unless [maxLines] is set); the
/// pill grows with the text size.
///
/// ```dart
/// AknLamp.style(order.status.statusStyle.withLabel(order.statusLabel))
/// AknLamp.status(AknStatus.lampFor(order, viewer))
/// ```
class AknLamp extends StatelessWidget {
  const AknLamp({
    super.key,
    required this.label,
    required this.tone,
    this.solid = false,
    this.size = AknLampSize.medium,
    this.maxLines,
    this.semanticLabel,
    this.style,
  });

  /// A lamp for a generic [StatusStyle] (`order.status.statusStyle`).
  AknLamp.style(
    StatusStyle status, {
    super.key,
    this.size = AknLampSize.medium,
    this.maxLines,
    this.semanticLabel,
    this.style,
  }) : label = status.label,
       tone = status.tone,
       solid = status.solid;

  /// A lamp for a viewer-aware [StatusLamp] (`AknStatus.lampFor`).
  AknLamp.status(
    StatusLamp lamp, {
    super.key,
    this.size = AknLampSize.medium,
    this.maxLines,
    this.semanticLabel,
    this.style,
  }) : label = lamp.label,
       tone = lamp.tone,
       solid = lamp.solid;

  final String label;
  final AknTone tone;

  /// Terminal success: a check disc instead of the dot.
  final bool solid;
  final AknLampSize size;

  /// Null lets the label wrap (nothing is cut at large text).
  final int? maxLines;

  /// Screen-reader text (defaults to [label]).
  final String? semanticLabel;

  /// Overrides the label style (size, weight); the colour stays the tone's.
  final TextStyle? style;

  /// The label weight: 700 for every tone in v3 (hierarchy comes from the
  /// tinted well, not from weight).
  static FontWeight weightFor(AknTone tone, {bool solid = false}) =>
      FontWeight.w700;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final tc = c.tone(tone);
    final small = size == AknLampSize.small;
    final glass = c.isBandPalette;
    final fg = glass ? c.onHero : tc.fg;
    final textStyle = t.captionStrong
        .copyWith(
          fontSize: 12,
          height: 16 / 12,
          letterSpacing: 0.1,
          fontWeight: weightFor(tone, solid: solid),
        )
        .merge(style)
        .copyWith(color: fg);
    final minHeight = small ? 22.0 : 26.0;
    final scaler = MediaQuery.textScalerOf(context);
    // The dot grows a little with large text so it keeps its weight beside
    // the label (8 px at 1×, 12 px at 2×).
    final grow = (scaler.scale(12) / 12).clamp(1.0, 1.5);
    final dot = (small ? 6.0 : 8.0) * grow;
    final fontSize = textStyle.fontSize ?? 12;
    final lineHeight = scaler.scale(fontSize) * (textStyle.height ?? 16 / 12);
    final hollow = tone == AknTone.neutral && !solid;
    final dotColor = glass && (tone == AknTone.brand || tone == AknTone.info)
        ? c.onHero
        : tc.solid;
    final halo = glass
        ? c.onHero.withValues(alpha: 0.28)
        : Color.alphaBlend(tc.solid.withValues(alpha: 0.2), tc.bg);
    Widget mark = CustomPaint(
      size: Size.square(dot),
      painter: LampDotPainter(
        color: dotColor,
        halo: hollow ? null : halo,
        hollow: hollow,
        check: solid,
        checkColor: glass ? c.heroMid : tc.onSolid,
      ),
    );
    if (tone == AknTone.brand && !solid) {
      // "Your move" breathes: the halo swells and fades, the dot lifts a
      // touch. Ambient (off in tests and under reduce motion).
      mark = RepaintBoundary(
        child: AknAmbient(
          period: AknMotion.breathe,
          reverse: true,
          builder: (context, b, _) => CustomPaint(
            size: Size.square(dot),
            painter: LampDotPainter(color: dotColor, halo: halo, breath: b),
          ),
        ),
      );
    }
    final pill = AnimatedContainer(
      duration: AknMotion.of(context, AknMotion.base),
      curve: AknMotion.standard,
      constraints: BoxConstraints(minHeight: minHeight),
      // Vertical padding centres one 16 px line in the 26 (22) px pill.
      padding: EdgeInsetsDirectional.fromSTEB(
        small ? 7 : 9,
        (minHeight - 16) / 2,
        small ? 8 : 10,
        (minHeight - 16) / 2,
      ),
      decoration: BoxDecoration(
        color: glass ? c.navyRaised : tc.bg,
        borderRadius: BorderRadius.circular(minHeight / 2),
        border: glass
            ? Border.all(color: c.onHero.withValues(alpha: 0.28))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: math.max(lineHeight, dot),
            // A new state pops its mark in (the check of "Teslim alındı",
            // the orange dot of "your move"); the old one shrinks away.
            child: Center(
              child: AnimatedSwitcher(
                duration: AknMotion.of(
                  context,
                  const Duration(milliseconds: 360),
                ),
                switchInCurve: AknMotion.pop,
                switchOutCurve: AknMotion.exit,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: KeyedSubtree(
                  key: ValueKey((tone, solid, glass)),
                  child: mark,
                ),
              ),
            ),
          ),
          SizedBox(width: small ? 5 : 7),
          Flexible(
            child: Text(
              label,
              style: textStyle,
              maxLines: maxLines,
              overflow: maxLines == null ? null : TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label: semanticLabel ?? label,
      excludeSemantics: true,
      // The pill hugs its label even where the parent stretches it (a
      // row's status slot, a stretched column).
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: 1,
        heightFactor: 1,
        child: pill,
      ),
    );
  }
}

/// Paints a lamp's mark (design v3 §4): a dot in [color] with a 3 px
/// [halo] ring, a hollow ring ([hollow], closed states) or a check disc
/// ([check], terminal success). [breath] (0–1) swells the halo for the
/// breathing "your move" lamp. It may paint past its box (the halo).
class LampDotPainter extends CustomPainter {
  const LampDotPainter({
    required this.color,
    this.halo,
    this.hollow = false,
    this.check = false,
    this.checkColor = Colors.white,
    this.breath = 0,
  });

  final Color color;
  final Color? halo;
  final bool hollow;
  final bool check;
  final Color checkColor;
  final double breath;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    if (check) {
      final disc = r + 2.5;
      canvas.drawCircle(center, disc, Paint()..color = color);
      final s = disc * 0.5;
      final path = Path()
        ..moveTo(center.dx - s * 0.95, center.dy + s * 0.02)
        ..lineTo(center.dx - s * 0.25, center.dy + s * 0.7)
        ..lineTo(center.dx + s, center.dy - s * 0.65);
      canvas.drawPath(
        path,
        Paint()
          ..color = checkColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, disc * 0.28)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      return;
    }
    if (hollow) {
      canvas.drawCircle(
        center,
        r - 0.75,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      return;
    }
    final h = halo;
    if (h != null) {
      final b = breath.clamp(0.0, 1.0);
      final spread = 3 + 2.5 * b;
      final alpha = h.a * (1 - 0.45 * b);
      canvas.drawCircle(
        center,
        r + spread,
        Paint()..color = h.withValues(alpha: alpha),
      );
    }
    canvas.drawCircle(center, r * (1 + 0.08 * breath), Paint()..color = color);
  }

  @override
  bool shouldRepaint(LampDotPainter old) =>
      old.color != color ||
      old.halo != halo ||
      old.hollow != hollow ||
      old.check != check ||
      old.checkColor != checkColor ||
      old.breath != breath;
}
