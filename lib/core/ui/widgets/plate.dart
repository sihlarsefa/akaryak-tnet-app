import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import 'cards.dart' show OnHero;
import 'delta_chip.dart';
import 'rolling_figure.dart';

export 'delta_chip.dart';
export 'lamp.dart';
export 'lane_pager.dart';
export 'rolling_figure.dart';
export 'triangle_glyph.dart';

/// The plate (design v2 §5, owner decision G "F2GO kart dili"): the
/// screen's single key number on a **white card with a soft orange tint**
/// — 180° `plateTint` (#FFEDE2) → `plate` (white) at 55 %, a 1 px
/// `plateBorder` (#F8DCCB), radius 22 and a soft `0 8 20` shadow
/// ([AknColors.plateDecoration]). Ink figures; orange only as an accent:
/// the 38 × 38 icon tile of the head, the delta chip and the this-month bar.
/// A hairline (`plateLine` #F3D9C8) replaces the old heavy black rule.
///
/// **One plate per screen.** A second important number becomes a readout or
/// a row, never a second plate. The subtree is re-themed with the plate
/// palette (`AknColors.plateInk()` via [OnHero]), so text styles, icons,
/// lamps, delta chips and charts inside pick the card look by themselves.
///
/// Compose it from slots (head 38 → 12 → figure → 8 → delta → 12 → chart →
/// 10 → hairline → 8 → below):
///
/// ```dart
/// AknPlate(
///   head: PlateHead(icon: Icons.bar_chart_rounded, title: 'Satış',
///       period: '1–21 Ekim', onMore: openMenu),
///   figure: PlateFigure(value: '8.426.350', unit: '₺', animate: firstRun),
///   delta: const PlateDelta(change: '%9,4', direction: AknDeltaDirection.up,
///       sentence: 'geçen ayın aynı günlerine göre'),
///   chart: PlateBars(values: months, labels: names, projection: proj),
///   below: PlateReadouts(items: [...]),
/// )
/// ```
///
/// …or pass a free [child]. [compact] (the deck at text scale ≥ 1.6) keeps
/// only head, figure and delta. [color] paints a flat fill instead of the
/// tinted card (kept for old call sites).
class AknPlate extends StatelessWidget {
  const AknPlate({
    super.key,
    this.head,
    this.figure,
    this.delta,
    this.chart,
    this.below,
    this.child,
    this.rule,
    this.compact = false,
    this.padding = AknSpace.plate,
    this.borderRadius = AknRadius.plate,
    this.margin,
    this.color,
    this.semanticLabel,
  });

  /// Head row ([PlateHead]: icon, title, period, ⋯).
  final Widget? head;

  /// The hero figure ([PlateFigure]).
  final Widget? figure;

  /// The line under the figure ([PlateDelta], or a sentence).
  final Widget? delta;

  /// Graphic above the rule ([PlateBars], [PlateFunnel], [PlateMeter] …).
  final Widget? chart;

  /// Content below the rule ([PlateReadouts], [PlateLedger],
  /// [PlateRankedBars] …).
  final Widget? below;

  /// Free content (alone, or appended after the slots).
  final Widget? child;

  /// Draw the hairline divider; defaults to "there is something below it".
  final bool? rule;

  /// Head, figure and delta only (the deck's large-text layout).
  final bool compact;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? margin;

  /// A flat fill instead of the tinted card gradient (null: the G card,
  /// [AknColors.plateDecoration]).
  final Color? color;

  /// Read as one node by screen readers when given.
  final String? semanticLabel;

  /// True inside a plate: a hero panel ([OnHero]) or a palette printed on
  /// the plate, such as the deck's top card.
  static bool isOn(BuildContext context) => AknDeltaChip.isOnPlate(context);

  bool get _usesSlots =>
      head != null ||
      figure != null ||
      delta != null ||
      chart != null ||
      below != null;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final fill = color;
    Widget body;
    if (!_usesSlots) {
      body = Padding(
        padding: padding,
        child: OnHero(child: child ?? const SizedBox.shrink()),
      );
    } else {
      final h = head;
      final tallHead = h is PlateHead && h.hasControl;
      final items = <Widget>[];
      void add(Widget? w, double gap) {
        if (w == null) return;
        if (items.isNotEmpty) items.add(SizedBox(height: gap));
        items.add(w);
      }

      add(figure, 0);
      add(delta, 8);
      if (!compact) add(chart, 12);
      final drawRule =
          !compact &&
          (rule ?? (below != null || (child != null && chart != null)));
      if (drawRule) {
        if (items.isNotEmpty) {
          items.add(SizedBox(height: chart != null ? 10 : 12));
        }
        items.add(const PlateRule());
      }
      if (!compact) add(below, drawRule ? 8 : 12);
      add(child, 8);
      body = OnHero(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (h != null)
              Padding(
                // A head with a ⋯ control reaches 14 px into the right
                // padding, so its 48 px button is a full target while the
                // icon tile and the title keep the card's left edge.
                padding: EdgeInsets.fromLTRB(
                  padding.left,
                  padding.top,
                  tallHead ? math.max(0.0, padding.right - 14) : padding.right,
                  items.isEmpty ? 0 : 12,
                ),
                child: h,
              ),
            if (items.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  padding.left,
                  h == null ? padding.top : 0,
                  padding.right,
                  padding.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: items,
                ),
              )
            else
              SizedBox(height: padding.bottom),
          ],
        ),
      );
    }
    Widget plate = DecoratedBox(
      decoration: fill == null
          ? c.plateDecoration(borderRadius: borderRadius)
          : BoxDecoration(
              color: fill,
              borderRadius: borderRadius,
              border: Border.all(color: c.plateBorder),
            ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Material(type: MaterialType.transparency, child: body),
      ),
    );
    plate = Semantics(container: true, label: semanticLabel, child: plate);
    if (margin != null) plate = Padding(padding: margin!, child: plate);
    return plate;
  }
}

/// The plate's head row (owner decision G): a 38 × 38 icon tile
/// (`plateIconFill` #FFE6D6, `plateAccent` #E8590C glyph, radius 12), the
/// title (15.5/20 w700 ink) over the period (12/16 w500 dim, "1–21 Ekim,
/// 3 sipariş") and an optional ⋯ control (48 px target). At large text the
/// title wraps to two lines; nothing is cut.
class PlateHead extends StatelessWidget {
  const PlateHead({
    super.key,
    required this.title,
    this.icon,
    this.leading,
    this.period,
    this.trailing,
    this.onMore,
    this.moreTooltip = 'Diğer seçenekler',
  });

  final String title;

  /// The glyph of the 38 × 38 icon tile.
  final IconData? icon;

  /// Replaces the icon tile (e.g. an `AdrPlate` for the driver's stop plate).
  final Widget? leading;

  /// The line under the title ("1–21 Ekim", "bugün 10:05", "şu an").
  final String? period;

  /// A custom control at the end (a `PopupMenuButton`); wins over [onMore].
  final Widget? trailing;

  /// Shows a ⋯ button (`more_horiz_rounded`, 48 px target). A custom
  /// [trailing] control should be 48 × 48 too (tap-target guideline).
  final VoidCallback? onMore;
  final String moreTooltip;

  bool get hasControl => trailing != null || onMore != null;

  /// The icon tile's side at 1.0× text.
  static const double tileSize = 38;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final titleStyle = t.headline.copyWith(
      fontSize: 15.5,
      height: 20 / 15.5,
      fontWeight: FontWeight.w700,
      color: c.ink,
    );
    final periodStyle = t.label.copyWith(
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
      color: c.dim,
    );
    Widget? control = trailing;
    if (control == null && onMore != null) {
      control = IconButton(
        onPressed: onMore,
        tooltip: moreTooltip,
        icon: Icon(Icons.more_horiz_rounded, size: 22, color: c.ink),
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          fixedSize: const Size(48, 48),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }
    final tile = tileSize * math.min(scale, 1.3);
    final Widget? lead =
        leading ??
        (icon == null
            ? null
            : ExcludeSemantics(
                child: Container(
                  width: tile,
                  height: tile,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.plateIconFill,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 20 * math.min(scale, 1.3),
                    color: c.plateAccent,
                  ),
                ),
              ));
    final p = period;
    final large = scale >= 1.6;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: lead == null ? 24 : tile),
      child: Row(
        children: [
          if (lead != null) ...[lead, const SizedBox(width: 11)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: titleStyle,
                    maxLines: large ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (p != null && p.isNotEmpty)
                  Text(
                    p,
                    style: periodStyle,
                    maxLines: large ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (control != null) ...[
            const SizedBox(width: 2),
            SizedBox(
              width: 48,
              height: 40,
              child: OverflowBox(
                maxWidth: 48,
                maxHeight: 48,
                child: Center(child: control),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The plate's hero figure (§5.1): `plateFigure` (Condensed 58/58 800) with
/// its unit in `plateUnit` after a 6 px gap, or a [word] in `figureWord`
/// ("dönüşüm", "teslimat"). Decimals (",00") follow the figure in the unit
/// style. Clamped at 1.3× text and scaled down to fit (never wraps). With
/// [animate] it rolls in once ([RollingFigure]).
class PlateFigure extends StatelessWidget {
  const PlateFigure({
    super.key,
    required this.value,
    this.unit,
    this.decimals,
    this.word,
    this.animate = false,
    this.delay = Duration.zero,
    this.onRollStart,
    this.onRollEnd,
    this.semanticLabel,
    this.style,
    this.unitStyle,
    this.maxTextScale = 1.3,
  });

  /// Formatted figure: "1.524.380", "42,34", "%72", "38".
  final String value;
  final String? unit;
  final String? decimals;

  /// A word after the figure instead of a unit ("dönüşüm").
  final String? word;
  final bool animate;
  final Duration delay;
  final VoidCallback? onRollStart;
  final VoidCallback? onRollEnd;
  final String? semanticLabel;
  final TextStyle? style;
  final TextStyle? unitStyle;
  final double maxTextScale;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final w = word;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxTextScale,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: RollingFigure(
            value: value,
            style: style,
            decimals: decimals,
            unit: w == null ? unit : null,
            unitStyle: unitStyle,
            unitSpan: w == null
                ? null
                : TextSpan(
                    text: w,
                    style: t.figureWord.copyWith(color: context.akn.ink),
                  ),
            unitGap: w == null ? 6 : 8,
            animate: animate,
            delay: delay,
            onRollStart: onRollStart,
            onRollEnd: onRollEnd,
            semanticLabel: semanticLabel,
          ),
        ),
      ),
    );
  }
}

/// The line under the figure (§5.1): a delta chip ("▲ %12,8"; on the plate
/// `deltaFill` #FFF1E8 with Pas #C2410C) and the sentence naming the
/// comparison ("geçen ayın aynı günlerine göre"), 13/18 500 dim. At large
/// text the sentence moves under the chip.
class PlateDelta extends StatelessWidget {
  const PlateDelta({
    super.key,
    this.change,
    this.direction,
    this.goodForViewer,
    this.sentence,
    this.semanticLabel,
  });

  /// The chip text ("%12,8", "4 puan"); null shows the sentence alone.
  final String? change;
  final AknDeltaDirection? direction;

  /// Colours the arrow on white only (the plate is neutral).
  final bool? goodForViewer;
  final String? sentence;

  /// Reads chip and sentence as one ("yüzde 12,8 artış, geçen ayın …").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final style = t.bodySmall.copyWith(
      fontSize: 13,
      height: 18 / 13,
      color: c.dim,
      fontWeight: FontWeight.w500,
    );
    final chg = change;
    final s = sentence;
    final content = Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (chg != null)
          AknDeltaChip(
            label: chg,
            direction: direction,
            goodForViewer: goodForViewer,
          ),
        if (s != null && s.isNotEmpty) Text(s, style: style),
      ],
    );
    if (semanticLabel == null) return content;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: content,
    );
  }
}

/// The plate's divider (owner decision G): a 1 px hairline in `line`
/// (`plateLine` #F3D9C8 on the plate) — no heavy black rule. [thickness] is
/// kept for old call sites.
class PlateRule extends StatelessWidget {
  const PlateRule({super.key, this.thickness = 1});

  final double thickness;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: thickness,
      width: double.infinity,
      child: ColoredBox(color: context.akn.line),
    ),
  );
}

/// A red "!" disc (18 px) that marks a problem line (the plate card is
/// white, so the danger tone reads there too). Decorative: the bold words
/// next to it carry the meaning.
class PlateBang extends StatelessWidget {
  const PlateBang({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final s =
        size * math.min(MediaQuery.textScalerOf(context).scale(10) / 10, 1.6);
    return ExcludeSemantics(
      child: Container(
        width: s,
        height: s,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.danger.solid,
          shape: BoxShape.circle,
        ),
        child: Text(
          '!',
          textScaler: TextScaler.noScaling,
          style: context.aknText.label.copyWith(
            fontSize: s * 2 / 3,
            height: 1,
            fontWeight: FontWeight.w700,
            color: c.danger.onSolid,
          ),
        ),
      ),
    );
  }
}

/// One readout: label over a `number` value with its unit.
@immutable
class PlateReadout {
  const PlateReadout({
    required this.label,
    required this.value,
    this.unit,
    this.dashed = false,
    this.semanticLabel,
  });

  /// "Alınan yakıt", "Ortalama", "Ay sonu tahmini".
  final String label;

  /// "36.000", "42,34", "2,25", "22 Ekim".
  final String value;

  /// "L", "₺/L", "mn ₺" (16/28 after a 3 px gap).
  final String? unit;

  /// The 10 px dashed swatch that ties the label to the dashed projection
  /// bar ("Ay sonu tahmini").
  final bool dashed;
  final String? semanticLabel;
}

/// Pump-display readouts under the rule (§5.1): 2 or 3 equal columns,
/// left-aligned, gap 10 — label 13/16 500 over the value in `number`
/// (Condensed 24/28 700) with its unit (16/28). A value never wraps mid-
/// number (it scales down in its column). At large text (≥ 1.6×) or in a
/// narrow plate the readouts become label / value lines.
class PlateReadouts extends StatelessWidget {
  const PlateReadouts({super.key, required this.items, this.gap = 10});

  final List<PlateReadout> items;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final labelStyle = t.label.copyWith(height: 16 / 13, color: c.dim);
    final valueStyle = t.number.copyWith(color: c.ink);
    final unitStyle = t.readoutUnit.copyWith(color: c.ink);
    final large = MediaQuery.textScalerOf(context).scale(10) >= 16;
    InlineSpan valueSpan(PlateReadout r) => TextSpan(
      text: r.value,
      style: valueStyle,
      children: [
        if (r.unit != null && r.unit!.isNotEmpty)
          TextSpan(text: ' ${r.unit}', style: unitStyle),
      ],
    );
    Widget label(PlateReadout r, {int? maxLines}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (r.dashed) ...[const _DashedSwatch(), const SizedBox(width: 5)],
        Flexible(
          child: Text(
            r.label,
            style: labelStyle,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    String spoken(PlateReadout r) =>
        r.semanticLabel ??
        '${r.label}: ${r.value}${r.unit == null ? '' : ' ${r.unit}'}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final n = items.length;
        final col = n == 0
            ? constraints.maxWidth
            : (constraints.maxWidth - gap * (n - 1)) / n;
        if (large || col < 88) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < n; i++)
                Semantics(
                  label: spoken(items[i]),
                  excludeSemantics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: i == 0
                        ? null
                        : BoxDecoration(
                            border: Border(top: BorderSide(color: c.line)),
                          ),
                    child: _StackedReadout(
                      label: label(items[i]),
                      labelSpan: TextSpan(
                        text: items[i].label,
                        style: labelStyle,
                      ),
                      valueSpan: valueSpan(items[i]),
                    ),
                  ),
                ),
            ],
          );
        }
        // Columns like the board's CSS grid (`repeat(n, 1fr)` with
        // unbreakable labels): equal shares, but a column never gets less
        // than its content ("⬚ Ay sonu tahmini" takes what it needs and the
        // others share the rest). When the contents do not fit side by side
        // the shares stay equal and labels wrap / values scale down.
        final scaler = MediaQuery.textScalerOf(context);
        double measure(InlineSpan span) {
          final tp = TextPainter(
            text: span,
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final w = tp.width;
          tp.dispose();
          return w.ceilToDouble();
        }

        final swatch = 10.0 * math.min(scaler.scale(10) / 10, 1.6) + 5;
        final mins = [
          for (final r in items)
            math.max(
              measure(TextSpan(text: r.label, style: labelStyle)) +
                  (r.dashed ? swatch : 0),
              measure(valueSpan(r)),
            ),
        ];
        final widths = _gridColumns(
          mins,
          constraints.maxWidth - gap * math.max(0, n - 1),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) SizedBox(width: gap),
              SizedBox(
                width: widths[i],
                child: Semantics(
                  label: spoken(items[i]),
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      label(items[i], maxLines: 2),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text.rich(
                          valueSpan(items[i]),
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// CSS-grid `1fr` columns with a content minimum: equal shares of [avail],
/// except that a column whose content ([mins]) is wider keeps its content
/// width and the others share what is left. If the contents cannot all fit,
/// the shares are equal.
List<double> _gridColumns(List<double> mins, double avail) {
  final n = mins.length;
  if (n == 0) return const [];
  final total = mins.fold<double>(0, (a, b) => a + b);
  if (total > avail) return List.filled(n, avail / n);
  final frozen = List<bool>.filled(n, false);
  var room = avail;
  var free = n;
  var changed = true;
  while (changed && free > 0) {
    changed = false;
    final share = room / free;
    for (var i = 0; i < n; i++) {
      if (!frozen[i] && mins[i] > share) {
        frozen[i] = true;
        room -= mins[i];
        free--;
        changed = true;
      }
    }
  }
  final share = free == 0 ? 0.0 : room / free;
  return [for (var i = 0; i < n; i++) frozen[i] ? mins[i] : share];
}

/// The 10 px dashed square of the projection readout.
class _DashedSwatch extends StatelessWidget {
  const _DashedSwatch();

  @override
  Widget build(BuildContext context) {
    final s =
        10.0 * math.min(MediaQuery.textScalerOf(context).scale(10) / 10, 1.6);
    return CustomPaint(
      size: Size.square(s),
      painter: _DashedRectPainter(color: context.akn.ink),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.75),
      const Radius.circular(2),
    );
    _drawDashed(canvas, Path()..addRRect(r), color, 1.5, 2.2, 1.6);
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) => old.color != color;
}

/// Strokes [path] dashed ([on] / [off] px).
void _drawDashed(
  Canvas canvas,
  Path path,
  Color color,
  double width,
  double on,
  double off, {
  double progress = 1,
}) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width;
  for (final metric in path.computeMetrics()) {
    final end = metric.length * progress.clamp(0.0, 1.0);
    var d = 0.0;
    while (d < end) {
      final next = math.min(d + on, end);
      canvas.drawPath(metric.extractPath(d, next), paint);
      d += on + off;
    }
  }
}

/// The month-end projection of a month-to-date value (§5.1): MTD ÷ elapsed
/// days × days in the month, computed on the device. Null before the 5th
/// (too early to say — the third readout then shows the order count and no
/// dashed outline is drawn).
double? plateMonthEndProjection(num monthToDate, DateTime today) {
  if (today.day < 5) return null;
  final days = DateTime(today.year, today.month + 1, 0).day;
  return monthToDate / today.day * days;
}

/// The plate's mini bars (§5.1, `PlateBars`): past months in the context
/// colour (#F05A12 at 30 % on the plate), the current month-to-date in the
/// highlight colour (#E8590C on the plate) and a 1.5 px dashed outline from
/// its top up to the month-end [projection]. Bars are up to 24 wide in 44 px
/// columns spaced evenly, rounded 5 on top and 2 at the baseline; month
/// labels 12/16 dim under them (the current one 700 ink).
///
/// Tap a bar to see its value in a small inverse bubble for 2 s; every bar
/// is a screen-reader node ([semanticLabels], e.g. "Ekim, 1.524.380 lira,
/// ay sonu tahmini 2,25 milyon lira"). With [animate] the bars rise
/// ([AknMotion.barsRise], 40 ms stagger) after [delay] and the projection
/// outline draws in last; reduce motion shows them risen.
class PlateBars extends StatefulWidget {
  const PlateBars({
    super.key,
    required this.values,
    required this.labels,
    this.currentIndex,
    this.projection,
    this.valueLabels,
    this.semanticLabels,
    this.height = 38,
    this.animate = false,
    this.delay = Duration.zero,
  });

  /// One value per month (oldest first); the current month is month-to-date.
  final List<double> values;

  /// Month labels ("May", "Haz", … "Eki").
  final List<String> labels;

  /// The current bar (default: the last).
  final int? currentIndex;

  /// Month-end projection of the current bar (same unit as [values]).
  final double? projection;

  /// Bubble text per bar ("8,43 mn ₺"); without it a tap does nothing.
  final List<String>? valueLabels;
  final List<String>? semanticLabels;

  /// Bar area height (38).
  final double height;
  final bool animate;
  final Duration delay;

  @override
  State<PlateBars> createState() => _PlateBarsState();
}

class _PlateBarsState extends State<PlateBars>
    with SingleTickerProviderStateMixin {
  AnimationController? _rise;
  Timer? _delay;
  Timer? _bubbleTimer;
  int? _bubble;
  bool _scheduled = false;

  Duration get _riseTotal =>
      AknMotion.barsRise +
      AknMotion.barDelay(math.max(0, widget.values.length - 1)) +
      AknMotion.projectionDraw;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    if (widget.animate && !AknMotion.reduced(context)) {
      final c = _rise = AnimationController(vsync: this, duration: _riseTotal);
      if (widget.delay <= Duration.zero) {
        c.forward();
      } else {
        _delay = Timer(widget.delay, () {
          if (mounted) c.forward();
        });
      }
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _bubbleTimer?.cancel();
    _rise?.dispose();
    super.dispose();
  }

  void _tap(int i) {
    final labels = widget.valueLabels;
    if (labels == null || i >= labels.length) return;
    AknHaptics.selection();
    setState(() => _bubble = i);
    _bubbleTimer?.cancel();
    _bubbleTimer = Timer(AknMotion.bubbleHold, () {
      if (mounted) setState(() => _bubble = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final n = math.min(widget.values.length, widget.labels.length);
    final current = widget.currentIndex ?? n - 1;
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = t.caption.copyWith(
      fontWeight: FontWeight.w500,
      color: c.dim,
      letterSpacing: 0,
    );
    final labelHeight = scaler.scale(12) * 16 / 12;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final geo = _BarsGeometry(width: w, count: n);
        final bubble = _bubble;
        return SizedBox(
          height: widget.height + 4 + labelHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: widget.height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _tap(geo.nearest(d.localPosition.dx)),
                  child: _rise == null
                      ? CustomPaint(
                          painter: _BarsPainter(
                            values: widget.values.take(n).toList(),
                            current: current,
                            projection: widget.projection,
                            context: c.chartContext,
                            highlight: c.chartHighlight,
                            outline: c.chartHighlight,
                            geometry: geo,
                            rise: null,
                          ),
                        )
                      : CustomPaint(
                          painter: _BarsPainter(
                            values: widget.values.take(n).toList(),
                            current: current,
                            projection: widget.projection,
                            context: c.chartContext,
                            highlight: c.chartHighlight,
                            outline: c.chartHighlight,
                            geometry: geo,
                            rise: _rise,
                            riseMs: _riseTotal.inMilliseconds,
                          ),
                        ),
                ),
              ),
              for (var i = 0; i < n; i++)
                Positioned(
                  left: geo.columnLeft(i),
                  width: geo.column,
                  top: widget.height + 4,
                  height: labelHeight,
                  child: ExcludeSemantics(
                    child: Text(
                      widget.labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: i == current
                          ? labelStyle.copyWith(
                              color: c.ink,
                              fontWeight: FontWeight.w700,
                            )
                          : labelStyle,
                    ),
                  ),
                ),
              // One screen-reader node per bar (label + value).
              for (var i = 0; i < n; i++)
                Positioned(
                  left: geo.columnLeft(i),
                  width: geo.column,
                  top: 0,
                  height: widget.height + 4 + labelHeight,
                  child: Semantics(
                    container: true,
                    label:
                        widget.semanticLabels != null &&
                            i < widget.semanticLabels!.length
                        ? widget.semanticLabels![i]
                        : [
                            widget.labels[i],
                            if (widget.valueLabels != null &&
                                i < widget.valueLabels!.length)
                              widget.valueLabels![i],
                          ].join(', '),
                    child: const SizedBox.expand(),
                  ),
                ),
              if (bubble != null &&
                  widget.valueLabels != null &&
                  bubble < widget.valueLabels!.length)
                _BarBubble(
                  centerX: geo.center(bubble),
                  top:
                      widget.height -
                      _barHeight(
                        widget.values,
                        bubble,
                        widget.projection,
                        current,
                        widget.height,
                      ),
                  text: widget.valueLabels![bubble],
                  maxWidth: w,
                ),
            ],
          ),
        );
      },
    );
  }

  static double _barHeight(
    List<double> values,
    int i,
    double? projection,
    int current,
    double height,
  ) {
    final max = [...values, ?projection].fold<double>(0, math.max);
    if (max <= 0 || i >= values.length) return 0;
    return (values[i].clamp(0, max) / max) * height;
  }
}

/// Column layout shared by the bars, labels and hit testing.
class _BarsGeometry {
  _BarsGeometry({required this.width, required this.count})
    : column = count <= 0 ? 44 : math.min(44, (width - 8) / count);

  final double width;
  final int count;
  final double column;

  double columnLeft(int i) {
    if (count <= 1) return (width - column) / 2;
    return 4 + i * (width - 8 - column) / (count - 1);
  }

  double center(int i) => columnLeft(i) + column / 2;

  int nearest(double x) {
    var best = 0;
    var d = double.infinity;
    for (var i = 0; i < count; i++) {
      final dd = (center(i) - x).abs();
      if (dd < d) {
        d = dd;
        best = i;
      }
    }
    return best;
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.current,
    required this.projection,
    required this.context,
    required this.highlight,
    required this.outline,
    required this.geometry,
    required this.rise,
    this.riseMs = 1,
  }) : super(repaint: rise);

  final List<double> values;
  final int current;
  final double? projection;
  final Color context;
  final Color highlight;
  final Color outline;
  final _BarsGeometry geometry;
  final Animation<double>? rise;
  final int riseMs;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final max = [...values, ?projection].fold<double>(0, math.max);
    if (max <= 0) return;
    final h = size.height;
    final barW = math.max(4.0, math.min(24.0, geometry.column - 8));
    final elapsed = rise == null ? double.infinity : rise!.value * riseMs;
    final riseMs0 = AknMotion.barsRise.inMilliseconds.toDouble();
    double grow(int i) {
      if (rise == null) return 1;
      final start = AknMotion.barDelay(i).inMilliseconds.toDouble();
      final p = ((elapsed - start) / riseMs0).clamp(0.0, 1.0);
      return AknMotion.standard.transform(p);
    }

    for (var i = 0; i < n; i++) {
      final v = values[i].clamp(0, max).toDouble();
      final bh = v / max * h * grow(i);
      if (bh <= 0) continue;
      final cx = geometry.center(i);
      final rect = Rect.fromLTWH(cx - barW / 2, h - bh, barW, bh);
      final r = math.min(5.0, bh);
      final rb = math.min(2.0, bh / 2);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: Radius.circular(r),
          topRight: Radius.circular(r),
          bottomLeft: Radius.circular(rb),
          bottomRight: Radius.circular(rb),
        ),
        Paint()..color = i == current ? highlight : context,
      );
    }

    // The dashed month-end projection over the current bar.
    final p = projection;
    if (p != null && current >= 0 && current < n && p > values[current]) {
      final mtd = values[current].clamp(0, max).toDouble() / max * h;
      final top = h - p.clamp(0, max) / max * h;
      final cx = geometry.center(current);
      final l = cx - barW / 2 + 0.75;
      final r = cx + barW / 2 - 0.75;
      final bottom = h - mtd;
      if (bottom - top > 1) {
        const rad = 4.0;
        final path = Path()
          ..moveTo(l, bottom)
          ..lineTo(l, top + rad)
          ..quadraticBezierTo(l, top, l + rad, top)
          ..lineTo(r - rad, top)
          ..quadraticBezierTo(r, top, r, top + rad)
          ..lineTo(r, bottom);
        final drawMs = AknMotion.projectionDraw.inMilliseconds.toDouble();
        final progress = rise == null
            ? 1.0
            : ((elapsed - (riseMs - drawMs)) / drawMs).clamp(0.0, 1.0);
        if (progress > 0) {
          _drawDashed(canvas, path, outline, 1.5, 3, 2.5, progress: progress);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values ||
      old.current != current ||
      old.projection != projection ||
      old.context != context ||
      old.highlight != highlight ||
      old.outline != outline ||
      old.geometry.width != geometry.width ||
      old.rise != rise;
}

/// The small inverse bubble above a tapped bar.
class _BarBubble extends StatelessWidget {
  const _BarBubble({
    required this.centerX,
    required this.top,
    required this.text,
    required this.maxWidth,
  });

  final double centerX;
  final double top;
  final String text;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final style = t.captionStrong.copyWith(
      color: c.onInverse,
      letterSpacing: 0,
    );
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = tp.width + 12;
    final h = tp.height + 8;
    tp.dispose();
    final left = (centerX - w / 2)
        .clamp(0.0, math.max(0.0, maxWidth - w))
        .toDouble();
    return Positioned(
      left: left,
      top: top - h - 4,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: c.inverse,
            borderRadius: AknRadius.tag,
          ),
          child: Text(text, style: style, maxLines: 1, softWrap: false),
        ),
      ),
    );
  }
}

/// A plate meter (§5.1): 12 px, r6, track `chartTrack` (#FFE6D6 on the
/// plate), fill in the orange accent on the plate (ink on white), an
/// optional [threshold] tick (2 px, 5 px beyond both edges) and a dashed
/// [projection] tick. Values cap at 100 %.
class PlateMeter extends StatelessWidget {
  const PlateMeter({
    super.key,
    required this.value,
    this.threshold,
    this.projection,
    this.height = 12,
    this.semanticLabel,
    this.semanticValue,
  });

  /// 0–1 (capped).
  final double value;

  /// 0–1: the target / warning line ("hedef %90", "uyarı sınırı %80").
  final double? threshold;

  /// 0–1: a dashed month-end tick.
  final double? projection;
  final double height;
  final String? semanticLabel;

  /// Defaults to "%NN".
  final String? semanticValue;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: semanticValue ?? '%${(v * 100).round()}',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _MeterPainter(
            value: v,
            threshold: threshold?.clamp(0.0, 1.0),
            projection: projection?.clamp(0.0, 1.0),
            track: c.chartTrack,
            fill: c.isPlatePalette ? c.chartHighlight : c.ink,
          ),
        ),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  const _MeterPainter({
    required this.value,
    required this.threshold,
    required this.projection,
    required this.track,
    required this.fill,
  });

  final double value;
  final double? threshold;
  final double? projection;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, r),
      Paint()..color = track,
    );
    if (value > 0) {
      final w = math.max(size.height, size.width * value);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), r),
        Paint()..color = fill,
      );
    }
    final th = threshold;
    if (th != null) {
      final x = (size.width * th).clamp(1.0, size.width - 1);
      canvas.drawRect(
        Rect.fromLTRB(x - 1, -5, x + 1, size.height + 5),
        Paint()..color = fill,
      );
    }
    final pr = projection;
    if (pr != null) {
      final x = (size.width * pr).clamp(1.0, size.width - 1);
      _drawDashed(
        canvas,
        Path()
          ..moveTo(x, -5)
          ..lineTo(x, size.height + 5),
        fill,
        2,
        3,
        2.5,
      );
    }
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.value != value ||
      old.threshold != threshold ||
      old.projection != projection ||
      old.track != track ||
      old.fill != fill;
}

/// One plate ledger line (Tahsilat card).
@immutable
class PlateLedgerLine {
  const PlateLedgerLine({
    required this.label,
    required this.value,
    this.problem = false,
    this.semanticLabel,
  });

  final String label;
  final String value;

  /// Starts with a [PlateBang] and prints bold (red on white).
  final bool problem;
  final String? semanticLabel;
}

/// The plate ledger (§5.1): lines 14/20 500 with values 15/20 700 right,
/// separated by hairlines (`plateLine` on the plate). A problem line starts
/// with the red "!" and is bold red.
class PlateLedger extends StatelessWidget {
  const PlateLedger({super.key, required this.lines});

  final List<PlateLedgerLine> lines;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final base = t.bodySmall.copyWith(
      color: c.ink,
      fontWeight: FontWeight.w500,
    );
    final valueBase = t.bodySmall.copyWith(
      fontSize: 15,
      height: 20 / 15,
      fontWeight: FontWeight.w700,
      color: c.ink,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < lines.length; i++)
          Semantics(
            label:
                lines[i].semanticLabel ??
                '${lines[i].problem ? 'Dikkat, ' : ''}${lines[i].label}: ${lines[i].value}',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: i == 0
                  ? null
                  : BoxDecoration(
                      border: Border(top: BorderSide(color: c.line)),
                    ),
              child: Row(
                children: [
                  if (lines[i].problem) ...[
                    const PlateBang(),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      lines[i].label,
                      style: lines[i].problem
                          ? base.copyWith(
                              fontWeight: FontWeight.w700,
                              color: c.danger.fg,
                            )
                          : base,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    lines[i].value,
                    maxLines: 1,
                    softWrap: false,
                    style: lines[i].problem
                        ? valueBase.copyWith(color: c.danger.fg)
                        : valueBase,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One ranked bar: label and value on a line, then an 8 px bar.
@immutable
class PlateRankedBar {
  const PlateRankedBar({
    required this.label,
    required this.value,
    required this.fraction,
    this.track = 1,
    this.problem = false,
    this.semanticLabel,
  });

  final String label;

  /// Right-aligned value ("1,52 mn ₺", "9 form, 4 sipariş").
  final String value;

  /// Filled share of the full width (0–1).
  final double fraction;

  /// Track share of the full width (two-series rows: the form total;
  /// [fraction] is then the converted part). Default 1 (full width).
  final double track;

  /// Starts with a [PlateBang] and prints bold.
  final bool problem;
  final String? semanticLabel;
}

/// A legend entry for two-series ranked bars ("siparişe dönüşen", "form").
@immutable
class PlateLegendItem {
  const PlateLegendItem(this.label, {this.filled = true});

  final String label;

  /// Ink swatch (the filled series) or a track swatch (the remainder).
  final bool filled;
}

/// Ranked bars (§5.1): label 14/20 500 left, value 15/20 700 right, then an
/// 8 px bar (orange-accent fill on the plate, ink on white; `chartTrack`
/// track; square at the start, round at the end). The deck shows at most three rows; the full list is on
/// `/stats`. Two series get a small [legend].
class PlateRankedBars extends StatelessWidget {
  const PlateRankedBars({
    super.key,
    required this.rows,
    this.legend = const [],
  });

  final List<PlateRankedBar> rows;
  final List<PlateLegendItem> legend;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final labelStyle = t.bodySmall.copyWith(
      color: c.ink,
      fontWeight: FontWeight.w500,
    );
    final valueStyle = t.bodySmall.copyWith(
      fontSize: 15,
      height: 20 / 15,
      fontWeight: FontWeight.w700,
      color: c.ink,
    );
    const end = BorderRadius.horizontal(right: Radius.circular(4));
    final fillColor = c.isPlatePalette ? c.chartHighlight : c.ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++)
          Semantics(
            label:
                rows[i].semanticLabel ??
                '${rows[i].problem ? 'Dikkat, ' : ''}${rows[i].label}: ${rows[i].value}',
            excludeSemantics: true,
            child: Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      if (rows[i].problem) ...[
                        const PlateBang(),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          rows[i].label,
                          style: rows[i].problem
                              ? labelStyle.copyWith(fontWeight: FontWeight.w700)
                              : labelStyle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        rows[i].value,
                        style: valueStyle,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 8,
                    child: FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: rows[i].track.clamp(0.0, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.chartTrack,
                          borderRadius: end,
                        ),
                        child: FractionallySizedBox(
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor: rows[i].track <= 0
                              ? 0
                              : (rows[i].fraction / rows[i].track).clamp(
                                  0.0,
                                  1.0,
                                ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: fillColor,
                              borderRadius: end,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                ],
              ),
            ),
          ),
        if (legend.isNotEmpty)
          ExcludeSemantics(
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                for (final l in legend)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 8,
                        decoration: BoxDecoration(
                          color: l.filled ? fillColor : c.chartTrack,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(l.label, style: t.label.copyWith(color: c.ink)),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One funnel step.
@immutable
class PlateFunnelStep {
  const PlateFunnelStep({
    required this.label,
    required this.value,
    required this.fraction,
    this.highlight = false,
  });

  final String label;
  final String value;

  /// Bar length (0–1).
  final double fraction;

  /// The result step (black on the plate; the highlight on white).
  final bool highlight;
}

/// The plate funnel (§5.1): a label column (58 px), 18 px bars (context
/// colour; the result in the highlight colour) and the value 15/20 700 on
/// the right.
class PlateFunnel extends StatelessWidget {
  const PlateFunnel({super.key, required this.steps});

  final List<PlateFunnelStep> steps;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final labelStyle = t.bodySmall.copyWith(
      color: c.ink,
      fontWeight: FontWeight.w500,
    );
    final valueStyle = t.bodySmall.copyWith(
      fontSize: 15,
      height: 20 / 15,
      fontWeight: FontWeight.w700,
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

    var labelW = 58.0;
    var valueW = 30.0;
    for (final s in steps) {
      labelW = math.max(labelW, measure(s.label, labelStyle).ceilToDouble());
      valueW = math.max(valueW, measure(s.value, valueStyle).ceilToDouble());
    }
    const end = BorderRadius.horizontal(right: Radius.circular(4));
    // QA BO-02: at large text the measured label + value columns could be
    // wider than the plate. Then each label gets its own line above the bar
    // and the value column is capped (it scales down instead of overflowing).
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final stacked = labelW + valueW + 16 + 48 > maxW;
        final valueCol = stacked ? math.min(valueW, maxW * 0.45) : valueW;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              Semantics(
                label: '${steps[i].label}: ${steps[i].value}',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (stacked)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(steps[i].label, style: labelStyle),
                      ),
                    Row(
                      children: [
                        if (!stacked) ...[
                          SizedBox(
                            width: labelW,
                            child: Text(
                              steps[i].label,
                              style: labelStyle,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: SizedBox(
                            height: 18,
                            child: FractionallySizedBox(
                              alignment: AlignmentDirectional.centerStart,
                              widthFactor: steps[i].fraction.clamp(0.0, 1.0),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: steps[i].highlight
                                      ? c.chartHighlight
                                      : c.chartContext,
                                  borderRadius: end,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: valueCol,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              steps[i].value,
                              style: valueStyle,
                              textAlign: TextAlign.end,
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A line on the plate (§5.1, "Ortalama birim fiyat"): a 2 px ink line, a
/// 10 px end dot in the highlight colour with a 2 px surface ring, the end
/// value label 12/16 700, a baseline hairline and month labels (the last
/// one 700).
class PlateLine extends StatelessWidget {
  const PlateLine({
    super.key,
    required this.values,
    this.labels = const [],
    this.endLabel,
    this.height = 74,
    this.semanticLabel,
  });

  final List<double> values;
  final List<String> labels;

  /// "42,34" next to the last point.
  final String? endLabel;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _LinePainter(
            values: values,
            labels: labels,
            endLabel: endLabel,
            line: c.ink,
            dot: c.chartHighlight,
            ring: c.surface,
            base: c.line,
            labelStyle: t.caption.copyWith(
              color: c.dim,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
            strongStyle: t.caption.copyWith(
              color: c.ink,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
            scaler: MediaQuery.textScalerOf(context),
          ),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.labels,
    required this.endLabel,
    required this.line,
    required this.dot,
    required this.ring,
    required this.base,
    required this.labelStyle,
    required this.strongStyle,
    required this.scaler,
  });

  final List<double> values;
  final List<String> labels;
  final String? endLabel;
  final Color line;
  final Color dot;
  final Color ring;
  final Color base;
  final TextStyle labelStyle;
  final TextStyle strongStyle;
  final TextScaler scaler;

  TextPainter _tp(String s, TextStyle st) => TextPainter(
    text: TextSpan(text: s, style: st),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    final labelH = labels.isEmpty ? 0.0 : scaler.scale(12) * 16 / 12;
    final baseY = size.height - labelH - (labels.isEmpty ? 0 : 0);
    canvas.drawLine(
      Offset(0, baseY - 0.5),
      Offset(size.width, baseY - 0.5),
      Paint()
        ..color = base
        ..strokeWidth = 1,
    );
    const left = 22.0;
    final right = size.width - 24;
    double x(int i) =>
        n <= 1 ? (left + right) / 2 : left + i * (right - left) / (n - 1);
    if (labels.isNotEmpty) {
      final m = math.min(labels.length, math.max(n, labels.length));
      for (var i = 0; i < m; i++) {
        final lx = labels.length == n
            ? x(i)
            : left + i * (right - left) / math.max(1, labels.length - 1);
        final tp = _tp(
          labels[i],
          i == labels.length - 1 ? strongStyle : labelStyle,
        );
        tp.paint(canvas, Offset(lx - tp.width / 2, size.height - tp.height));
        tp.dispose();
      }
    }
    if (n == 0) return;
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final span = hi - lo;
    const top = 12.0;
    final bottom = baseY - 12;
    double y(int i) => span <= 0
        ? (top + bottom) / 2
        : bottom - (values[i] - lo) / span * (bottom - top);
    final path = Path()..moveTo(x(0), y(0));
    for (var i = 1; i < n; i++) {
      path.lineTo(x(i), y(i));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final end = Offset(x(n - 1), y(n - 1));
    canvas.drawCircle(end, 6, Paint()..color = ring);
    canvas.drawCircle(end, 5, Paint()..color = dot);
    final el = endLabel;
    if (el != null) {
      final tp = _tp(el, strongStyle);
      final lx = (end.dx - 8 - tp.width).clamp(0.0, size.width - tp.width);
      final ly = (end.dy - 6 - tp.height).clamp(0.0, size.height);
      tp.paint(canvas, Offset(lx, ly));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values ||
      old.labels != labels ||
      old.endLabel != endLabel ||
      old.line != line ||
      old.dot != dot ||
      old.ring != ring ||
      old.base != base ||
      old.labelStyle != labelStyle ||
      old.scaler != scaler;
}

/// Width of [span] at the context's text scale (one line).
double _spanWidth(BuildContext context, InlineSpan span) {
  final tp = TextPainter(
    text: span,
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final w = tp.width.ceilToDouble();
  tp.dispose();
  return w;
}

/// A large-text readout line (QA C-01 / BO-02): label and value side by side
/// when they fit (the value at the end), otherwise the value drops under the
/// label. The value never gets wider than the line (it scales down instead
/// of overflowing).
class _StackedReadout extends StatelessWidget {
  const _StackedReadout({
    required this.label,
    required this.labelSpan,
    required this.valueSpan,
  });

  final Widget label;
  final InlineSpan labelSpan;
  final InlineSpan valueSpan;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final max = constraints.maxWidth;
      final valueW = _spanWidth(context, valueSpan);
      final labelMin = math.min(_spanWidth(context, labelSpan), max * 0.4);
      final value = Text.rich(valueSpan, maxLines: 1, softWrap: false);
      if (labelMin + 12 + valueW <= max) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: label),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.max(0, max - 12 - labelMin),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: value,
              ),
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          label,
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: value,
          ),
        ],
      );
    },
  );
}
