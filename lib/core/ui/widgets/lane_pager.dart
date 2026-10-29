import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../motion.dart';
import '../theme.dart';

/// The lane pager under the stats deck and the onboarding pages (design v3
/// §4 "Pager dots"): 6 × 6 dots in `lineStrong` (3:1 on the page), the active lane a
/// 20 × 6 capsule in the logo orange (gap 10). When the lane changes the
/// capsule hands over on [AknMotion.spring] — the old one shrinks into a dot
/// while the new dot stretches and warms to orange. v4: a 40 dp row and no
/// "1 / 6" text (its semantics stay). Right-aligned, an optional link
/// ("İstatistikler ›", 14/20 w600 ink with a 16 px caret) presses in.
///
/// * The dot strip is one 48 px tall tap target: a tap jumps to the nearest
///   lane ([onSelect]). Screen readers move with the deck's own custom
///   actions, so the strip itself is not announced.
/// * The position is a button when [onPositionTap] is set (the deck's
///   "Sonraki kart"); [positionSemanticLabel] is what it announces.
/// * The link steps aside when the row has no room (large text); the deck's
///   ⋯ menu still offers "Detaylı istatistikler".
/// * Text clamps at [maxTextScale] (1.6, like the deck).
class LanePager extends StatefulWidget {
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

  /// Jump to a lane (tap on the dot strip).
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

  static const double _dash = 6;
  static const double _active = 20;
  static const double _gap = 10;

  /// Width of the dot strip for [count] lanes.
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
  State<LanePager> createState() => _LanePagerState();
}

class _LanePagerState extends State<LanePager>
    with SingleTickerProviderStateMixin {
  /// The hand-over from [_from] to the current lane (1 = settled).
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: AknMotion.needle,
    value: 1,
  );
  int? _from;

  int get _active {
    final n = math.max(0, widget.count);
    return n == 0 ? 0 : widget.index.clamp(0, n - 1);
  }

  @override
  void didUpdateWidget(LanePager old) {
    super.didUpdateWidget(old);
    final n = math.max(0, widget.count);
    final before = n == 0 ? 0 : old.index.clamp(0, n - 1);
    if (before != _active && old.count == widget.count) {
      if (AknMotion.reduced(context)) {
        _from = null;
        _move.value = 1;
      } else {
        _from = before;
        _move.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: widget.maxTextScale,
      child: Builder(builder: _build),
    );
  }

  Widget _build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final n = math.max(0, widget.count);
    final active = _active;
    final linkStyle = t.label.copyWith(
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w600,
      color: c.ink,
    );
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

    final onSelect = widget.onSelect;
    final strip = SizedBox(
      width: LanePager.stripWidth(n),
      height: 40,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // A pointer shortcut only: screen readers move through the deck with
        // the position button and the cards' own actions (an unlabeled tap
        // node here failed the labeled-tap-target guideline).
        excludeFromSemantics: true,
        onTapUp: onSelect == null || n == 0
            ? null
            : (d) {
                final i = LanePager.laneAt(d.localPosition.dx, n, active);
                if (i != active) AknHaptics.selection();
                onSelect(i);
              },
        child: ExcludeSemantics(
          child: CustomPaint(
            painter: _LanePainter(
              count: n,
              active: active,
              from: _from,
              move: _move,
              // Full control-border grey: 3.18:1 on the page (non-text AA).
              dot: c.lineStrong,
              lit: c.logo,
              rtl: Directionality.of(context) == TextDirection.rtl,
            ),
          ),
        ),
      ),
    );

    Widget? position;
    // v4 (§4): "1 / N" is not drawn any more; its label stays for screen
    // readers ("6 karttan 1."). Moving between lanes is the deck's own
    // custom actions ("Sonraki kart", "Önceki kart"); a hidden button here
    // would be an invisible tap target.
    if (widget.showPosition && n > 0) {
      position = Semantics(
        label: widget.positionSemanticLabel ?? '$n karttan ${active + 1}.',
        excludeSemantics: true,
        child: const SizedBox(width: 1, height: 40),
      );
    }

    final caret = scaler.scale(16);
    return Padding(
      padding: widget.padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final used = LanePager.stripWidth(n) + (position == null ? 0 : 1);
          final link = widget.actionLabel;
          final onAction = widget.onAction;
          final linkWidth = link == null
              ? 0.0
              : measure(link, linkStyle) + 4 + caret + 12;
          final showLink =
              link != null &&
              onAction != null &&
              used + linkWidth <= constraints.maxWidth;
          // v4: a 40 dp row; the link keeps a 48 dp target that reaches
          // 4 dp past the row.
          return SizedBox(
            height: 40,
            child: Row(
              children: [
                strip,
                ?position,
                const Spacer(),
                if (showLink)
                  Semantics(
                    button: true,
                    label: link,
                    excludeSemantics: true,
                    onTap: onAction,
                    child: PressScale(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          AknHaptics.selection();
                          onAction();
                        },
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 40),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(link, style: linkStyle, maxLines: 1),
                              const SizedBox(width: 4),
                              Icon(
                                PhosphorIconsRegular.caretRight,
                                size: caret,
                                color: c.ink,
                              ),
                            ],
                          ),
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

/// The dots and the capsule. Every lane is a dot whose width and colour
/// follow how "active" it is: the current lane 1, the lane it is taking
/// over from 0 → … on the spring, the others 0. The widths always add up to
/// [LanePager.stripWidth], so the strip never jumps.
class _LanePainter extends CustomPainter {
  _LanePainter({
    required this.count,
    required this.active,
    required this.from,
    required this.move,
    required this.dot,
    required this.lit,
    required this.rtl,
  }) : super(repaint: move);

  final int count;
  final int active;
  final int? from;
  final Animation<double> move;
  final Color dot;
  final Color lit;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    if (count <= 0) return;
    final v = move.value;
    final settled = v >= 1 || from == null || from == active;
    final s = settled ? 1.0 : AknMotion.spring.transform(v);
    const h = LanePager._dash;
    final top = (size.height - h) / 2;
    var x = 0.0;
    for (var i = 0; i < count; i++) {
      final double on;
      if (i == active) {
        on = s;
      } else if (!settled && i == from) {
        on = 1 - s;
      } else {
        on = 0;
      }
      final w = math.max(
        4.0,
        LanePager._dash + (LanePager._active - LanePager._dash) * on,
      );
      final left = rtl ? size.width - x - w : x;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, w, h),
          const Radius.circular(h / 2),
        ),
        Paint()..color = Color.lerp(dot, lit, on.clamp(0.0, 1.0))!,
      );
      x += w + LanePager._gap;
    }
  }

  @override
  bool shouldRepaint(_LanePainter old) =>
      old.count != count ||
      old.active != active ||
      old.from != from ||
      old.move != move ||
      old.dot != dot ||
      old.lit != lit ||
      old.rtl != rtl;
}
