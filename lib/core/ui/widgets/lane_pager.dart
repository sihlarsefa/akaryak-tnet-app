import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';

/// The lane pager under the stats deck and the onboarding pages (design v2
/// §5.3): lane dashes (10 × 4, r2, `faint`; the active one 24 × 4 in the
/// logo orange, gap 6), then the position ("1 / 8", Condensed 600 15/20
/// dim) and, right-aligned, an optional link ("İstatistikler ›", ink
/// 15/20 600).
///
/// * The dash strip is one 48 px tall tap target: a tap jumps to the
///   nearest dash ([onSelect]). Screen readers move with the deck's own
///   custom actions, so the strip itself is not announced.
/// * The position is a button when [onPositionTap] is set (the deck's
///   "Sonraki kart"); [positionSemanticLabel] is what it announces.
/// * The link steps aside when the row has no room (large text); the deck's
///   ⋯ menu still offers "Detaylı istatistikler".
/// * Text clamps at [maxTextScale] (1.6, like the deck).
class LanePager extends StatelessWidget {
  const LanePager({
    super.key,
    required this.count,
    required this.index,
    this.onSelect,
    this.showPosition = true,
    this.onPositionTap,
    this.positionSemanticLabel,
    this.positionSemanticHint,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.maxTextScale = 1.6,
  });

  final int count;

  /// The active lane (0-based).
  final int index;

  /// Jump to a lane (tap on the dash strip).
  final ValueChanged<int>? onSelect;
  final bool showPosition;

  /// Tap on "1 / 8" (the deck: next card).
  final VoidCallback? onPositionTap;
  final String? positionSemanticLabel;
  final String? positionSemanticHint;

  /// The right-aligned link ("İstatistikler").
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;
  final double maxTextScale;

  static const double _dash = 10;
  static const double _active = 24;
  static const double _gap = 6;

  /// Width of the dash strip for [count] lanes.
  static double stripWidth(int count) =>
      count <= 0 ? 0 : _active + (count - 1) * (_dash + _gap);

  /// The lane nearest to [x] (strip coordinates) for an [active] lane.
  static int laneAt(double x, int count, int active) {
    var best = 0;
    var d = double.infinity;
    var left = 0.0;
    for (var i = 0; i < count; i++) {
      final w = i == active ? _active : _dash;
      final dd = (left + w / 2 - x).abs();
      if (dd < d) {
        d = dd;
        best = i;
      }
      left += w + _gap;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxTextScale,
      child: Builder(builder: _build),
    );
  }

  Widget _build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final n = math.max(0, count);
    final active = n == 0 ? 0 : index.clamp(0, n - 1);
    final duration = AknMotion.of(context, AknMotion.deckStep);
    final posStyle = t.number.copyWith(
      fontSize: 15,
      height: 20 / 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      color: c.dim,
    );
    final linkStyle = t.bodyStrong.copyWith(height: 20 / 15, color: c.ink);
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String s, TextStyle st) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: st),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = tp.width;
      tp.dispose();
      return w;
    }

    final strip = SizedBox(
      width: stripWidth(n),
      height: 48,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: onSelect == null || n == 0
            ? null
            : (d) {
                final i = laneAt(d.localPosition.dx, n, active);
                if (i != active) AknHaptics.selection();
                onSelect!(i);
              },
        child: ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                AnimatedContainer(
                  duration: duration,
                  curve: AknMotion.standard,
                  width: i == active ? _active : _dash,
                  height: 4,
                  decoration: BoxDecoration(
                    color: i == active ? c.logo : c.faint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final posText = '${n == 0 ? 0 : active + 1} / $n';
    Widget? position;
    if (showPosition && n > 0) {
      final label = Text(
        posText,
        style: posStyle,
        maxLines: 1,
        softWrap: false,
      );
      position = onPositionTap == null
          ? Semantics(
              label: positionSemanticLabel ?? '$n karttan ${active + 1}.',
              excludeSemantics: true,
              child: label,
            )
          : Semantics(
              button: true,
              label: positionSemanticLabel ?? posText,
              hint: positionSemanticHint,
              excludeSemantics: true,
              onTap: onPositionTap,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  AknHaptics.selection();
                  onPositionTap!();
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  // The label starts 12 after the strip (board); the 48 px
                  // target extends to its right.
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: 1,
                    child: label,
                  ),
                ),
              ),
            );
    }

    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final used =
              stripWidth(n) +
              (position == null
                  ? 0
                  : 12 + math.max(48, measure(posText, posStyle)));
          final link = actionLabel;
          final linkWidth = link == null
              ? 0.0
              : measure(link, linkStyle) + scaler.scale(20) - 6 + 12;
          final showLink =
              link != null &&
              onAction != null &&
              used + linkWidth <= constraints.maxWidth;
          return SizedBox(
            height: 48,
            child: Row(
              children: [
                strip,
                if (position != null) ...[const SizedBox(width: 12), position],
                const Spacer(),
                if (showLink)
                  Semantics(
                    button: true,
                    label: link,
                    excludeSemantics: true,
                    onTap: onAction,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        AknHaptics.selection();
                        onAction!();
                      },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(link, style: linkStyle, maxLines: 1),
                            Transform.translate(
                              offset: const Offset(6, 0),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: scaler.scale(20),
                                color: c.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
