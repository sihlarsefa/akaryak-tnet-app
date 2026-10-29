import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';
import 'cards.dart' show OnHero;
import 'delta_chip.dart';
import 'rolling_figure.dart';

export 'delta_chip.dart';
export 'lamp.dart';
export 'lane_pager.dart';
export 'rolling_figure.dart';
export 'triangle_glyph.dart';

/// The plate (design v3 §4 "Hero card", owner decision G): the screen's
/// single key number on a **white card with a warm wash** — 180°
/// `plateTint` → `plate` (white) at 55 %, a 1 px `plateBorder`, radius 26
/// and the warm `AknShadows.plate` ([AknColors.plateDecoration]). Ink
/// figures (tabular); orange only as an accent: the 40 × 40 icon tile of the
/// head, the delta chip, the current bar and the meters. Dividers are
/// `plateLine` hairlines.
///
/// It comes alive when it appears (design v3 §5): the head's glyph pops,
/// the figure rolls like an odometer ([RollingFigure]), the bars grow on a
/// springy stagger, the readouts roll up, the rule draws in, meters and
/// bars fill, the line chart draws itself — every one of them once, finite,
/// settled ~1.1 s after the first frame (the deck's full roll ~1.4 s), and
/// static under reduce motion. The current month's bar glow breathes three
/// times inside the page's loop budget (v4 §6: it waits while the home's
/// lead halo runs). On a home it also rises onto the band
/// (`AknBandOverlap`).
///
/// **One plate per screen.** A second important number becomes a readout or
/// a row, never a second plate. The subtree is re-themed with the plate
/// palette (`AknColors.plateInk()` via [OnHero]), so text styles, icons,
/// lamps, delta chips and charts inside pick the card look by themselves.
///
/// Compose it from slots (head 40 → 12 → figure → 8 → delta → 14 → chart →
/// 12 → hairline → 10 → below):
///
/// ```dart
/// AknPlate(
///   head: PlateHead(icon: PhosphorIconsRegular.chartBar, title: 'Satış',
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
/// washed card (kept for old call sites).
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
    this.raised = true,
  });

  /// Head row ([PlateHead]: title · period, trailing).
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

  /// A flat fill instead of the washed card gradient (null: the hero card,
  /// [AknColors.plateDecoration]).
  final Color? color;

  /// Read as one node by screen readers when given.
  final String? semanticLabel;

  /// v4: false gives a flat white card with the light `plateBehind` shadow
  /// (a plate that is not the hero, e.g. the deck under "Sıra sizde").
  final bool raised;

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
      if (!compact) add(chart, 14);
      final drawRule =
          !compact &&
          (rule ?? (below != null || (child != null && chart != null)));
      if (drawRule) {
        if (items.isNotEmpty) {
          items.add(SizedBox(height: chart != null ? 12 : 14));
        }
        items.add(const PlateRule());
      }
      if (!compact) add(below, drawRule ? 10 : 14);
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
      decoration: fill == null && raised
          ? c.plateDecoration(borderRadius: borderRadius)
          : BoxDecoration(
              color: fill ?? c.plate,
              borderRadius: borderRadius,
              border: Border.all(color: c.isDark ? c.line : c.plateBorder),
              boxShadow: raised
                  ? AknShadows.plate(c)
                  : AknShadows.plateBehind(c),
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

/// The plate's head row (design v4 §4): the [title] 16/20 700 and the
/// [period] 13/18 dim on ONE baseline ("Harcama  1–28 Ekim"; wraps at large
/// text), then a [trailing] widget at its natural width — a countdown or
/// the delta chip — and an optional ⋯ ([onMore], 48 px target). v4 homes
/// and stats pass no [icon]; an [icon] (old call sites) still draws the
/// 40 × 40 tile, and [leading] (the driver's ADR plate) replaces it.
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

  /// The glyph of the 40 × 40 icon tile (v4 homes and stats: none).
  final IconData? icon;

  /// Replaces the icon tile (e.g. an `AdrPlate` for the driver's stop plate).
  final Widget? leading;

  /// After the title on its baseline ("1–21 Ekim", "bugün 10:05").
  final String? period;

  /// v4: a widget at the end at its natural width (a countdown, the delta
  /// chip).
  final Widget? trailing;

  /// Shows a ⋯ button (`dotsThree`, 48 px target).
  final VoidCallback? onMore;
  final String moreTooltip;

  /// True when the head carries the ⋯ button (it reaches into the plate's
  /// right padding).
  bool get hasControl => onMore != null;

  /// The icon tile's side at 1.0× text.
  static const double tileSize = 40;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final titleStyle = t.headline.copyWith(
      fontSize: 16,
      height: 20 / 16,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
      color: c.ink,
    );
    final periodStyle = t.label.copyWith(
      fontWeight: FontWeight.w500,
      color: c.dim,
      fontFeatures: AknNumerals.tabular,
    );
    Widget? more;
    if (onMore != null) {
      more = IconButton(
        onPressed: onMore,
        tooltip: moreTooltip,
        icon: Icon(PhosphorIconsRegular.dotsThree, size: 22, color: c.ink),
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
                    borderRadius: BorderRadius.circular(AknRadius.sm),
                  ),
                  child: _PopIn(
                    delay: const Duration(milliseconds: 140),
                    from: 0.4,
                    child: Icon(
                      icon,
                      size: 22 * math.min(scale, 1.3),
                      color: c.plateAccent,
                    ),
                  ),
                ),
              ));
    final p = period;
    final hasPeriod = p != null && p.isNotEmpty;
    final titleText = Semantics(
      header: true,
      child: Text(
        title,
        style: titleStyle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
    // The title and the period share one baseline when both fit; otherwise
    // the period goes under the title (nothing is cut).
    final heading = !hasPeriod
        ? titleText
        : LayoutBuilder(
            builder: (context, box) {
              final scaler = MediaQuery.textScalerOf(context);
              double width(String text, TextStyle style) {
                final tp = TextPainter(
                  text: TextSpan(text: text, style: style),
                  textDirection: TextDirection.ltr,
                  textScaler: scaler,
                  maxLines: 1,
                )..layout();
                final w = tp.width;
                tp.dispose();
                return w;
              }

              final periodText = Text(
                p,
                style: periodStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              );
              final fits =
                  !box.hasBoundedWidth ||
                  width(title, titleStyle) + 8 + width(p, periodStyle) <=
                      box.maxWidth;
              if (fits) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(child: titleText),
                    const SizedBox(width: 8),
                    periodText,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [titleText, const SizedBox(height: 1), periodText],
              );
            },
          );
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: lead == null ? 24 : tile),
      child: Row(
        children: [
          if (lead != null) ...[lead, const SizedBox(width: 12)],
          Expanded(child: heading),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          if (more != null) ...[
            const SizedBox(width: 2),
            SizedBox(
              width: 48,
              height: 40,
              child: OverflowBox(
                maxWidth: 48,
                maxHeight: 48,
                child: Center(child: more),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The plate's hero figure (§1, §5): `plateFigure` (46/52 800, tabular)
/// with its unit in `plateUnit` after a 6 px gap, or a [word] in
/// `figureWord` ("dönüşüm", "teslimat"). Decimals (",00") follow the figure
/// in the unit style. Clamped at 1.3× text and scaled down to fit (never
/// wraps). It rolls in like an odometer on its first build and rolls
/// between values when it changes; with [animate] it plays the full
/// home-moment roll ([RollingFigure]).
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
            unitGap: w == null ? AknNumerals.plateUnitGap : 8,
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

/// The line under the figure (§4): a delta chip ("▲ %12,8"; on the plate
/// `deltaFill` with `brandInk` 13 w700, radius 8) and, 8 px after it on the
/// same line, the sentence naming the comparison ("geçen ayın aynı
/// günlerine göre"), 13/18 500 dim — one line on a phone at 1.0×. A
/// sentence too long for its line wraps in its own column beside the chip
/// (never a lone word under the chip); at large text (≥ 1.6×) the sentence
/// moves under the chip. It fades in with the chip's arrow.
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

  /// Colours the chip on white only (the plate is neutral).
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
    final chip = chg == null
        ? null
        : AknDeltaChip(
            label: chg,
            direction: direction,
            goodForViewer: goodForViewer,
          );
    final words = s == null || s.isEmpty
        ? null
        : _Appear(
            delay: const Duration(milliseconds: 200),
            child: Text(s, style: style),
          );
    final large = MediaQuery.textScalerOf(context).scale(10) >= 16;
    final Widget content;
    if (chip == null || words == null) {
      content = Align(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: 1,
        child: chip ?? words ?? const SizedBox.shrink(),
      );
    } else if (large) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [chip, const SizedBox(height: 6), words],
      );
    } else {
      content = Row(
        children: [
          chip,
          const SizedBox(width: 8),
          Flexible(child: words),
        ],
      );
    }
    if (semanticLabel == null) return content;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: content,
    );
  }
}

/// The plate's divider (§4): a 1 px hairline in `line` (`plateLine` on the
/// plate) that draws itself in from the start edge when it first appears.
/// [thickness] is kept for old call sites.
class PlateRule extends StatefulWidget {
  const PlateRule({super.key, this.thickness = 1});

  final double thickness;

  @override
  State<PlateRule> createState() => _PlateRuleState();
}

class _PlateRuleState extends State<PlateRule>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  );
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _timer = Timer(const Duration(milliseconds: 160), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: widget.thickness,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => Transform.scale(
          scaleX: _c.value >= 1
              ? 1.0
              : AknMotion.emphasizedCurve.transform(_c.value),
          alignment: AlignmentDirectional.centerStart.resolve(
            Directionality.of(context),
          ),
          child: child,
        ),
        child: ColoredBox(color: context.akn.line),
      ),
    ),
  );
}

/// A red "!" disc (18 px) that marks a problem line (the plate card is
/// white, so the danger tone reads there too); it pops in once.
/// Decorative: the bold words next to it carry the meaning.
class PlateBang extends StatelessWidget {
  const PlateBang({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final s =
        size * math.min(MediaQuery.textScalerOf(context).scale(10) / 10, 1.6);
    return ExcludeSemantics(
      child: _PopIn(
        delay: const Duration(milliseconds: 220),
        from: 0.3,
        child: Container(
          width: s,
          height: s,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.danger.solid,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: c.danger.solid.withValues(alpha: 0.28),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            '!',
            textScaler: TextScaler.noScaling,
            style: context.aknText.label.copyWith(
              fontSize: s * 2 / 3,
              height: 1,
              fontWeight: FontWeight.w800,
              color: c.danger.onSolid,
            ),
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

  /// "L", "₺/L", "mn ₺" (14/30 after a space).
  final String? unit;

  /// The 10 px dashed swatch that ties the label to the dashed projection
  /// bar ("Ay sonu tahmini").
  final bool dashed;
  final String? semanticLabel;
}

/// Readouts under the rule (§4): one row of 2 or 3 columns, left-aligned,
/// gap 10 — the label in `caption` (12/16 w600 dim) over the value in
/// `number` (24/30 800, tabular) with its unit (`readoutUnit`). The values
/// roll up into place one column after another ([RollingText]) and have all
/// landed ~1 s after the first frame. A value never wraps mid-number (it
/// scales down in its column). Only at large text (≥ 1.6×), in a plate too
/// narrow for columns (< [minColumnWidth] each) or at enlarged text whose
/// values cannot share the row, the readouts become label / value lines.
class PlateReadouts extends StatelessWidget {
  const PlateReadouts({super.key, required this.items, this.gap = 10});

  final List<PlateReadout> items;
  final double gap;

  /// The narrowest column the row layout accepts (a 360 dp phone gives
  /// three columns of ~87 px on the plate).
  static const double minColumnWidth = 64;

  /// When the readout at [i] starts rolling (while the card rises), and
  /// how long its roll takes: the third has landed ~0.95 s after the first
  /// frame.
  static Duration _delay(int i) => Duration(milliseconds: 180 + 80 * i);
  static const Duration _roll = Duration(milliseconds: 620);

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final labelStyle = t.caption.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      color: c.dim,
    );
    final valueStyle = t.number.copyWith(color: c.ink);
    final unitStyle = t.readoutUnit.copyWith(color: c.ink);
    final scaler = MediaQuery.textScalerOf(context);
    final large = scaler.scale(10) >= 16;
    // [k] < 1: the row's values share one smaller size (they never shrink
    // one by one).
    InlineSpan valueSpan(PlateReadout r, [double k = 1]) {
      TextStyle sized(TextStyle s) =>
          k == 1 ? s : s.copyWith(fontSize: (s.fontSize ?? 14) * k);
      return TextSpan(
        text: r.value,
        style: sized(valueStyle),
        children: [
          if (r.unit != null && r.unit!.isNotEmpty)
            TextSpan(text: ' ${r.unit}', style: sized(unitStyle)),
        ],
      );
    }

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
        Widget stacked() => Column(
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
                    delay: _delay(i),
                  ),
                ),
              ),
          ],
        );
        if (large || col < minColumnWidth) return stacked();
        // Columns like a CSS grid (`repeat(n, 1fr)` with unbreakable
        // labels): equal shares, but a column never gets less than its
        // content ("⬚ Ay sonu tahmini" takes what it needs and the others
        // share the rest). When the contents do not fit side by side, the
        // values first shrink together (to 75 %) with every label on one
        // line — the row stays one tidy line, and a deck never has to scale
        // its detail down — then labels may take two lines; only then do the
        // columns go equal and each value scales into its own.
        TextPainter painter(
          InlineSpan span, {
          int? maxLines = 1,
          double maxWidth = double.infinity,
        }) => TextPainter(
          text: span,
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: maxLines,
        )..layout(maxWidth: maxWidth);
        double measure(InlineSpan span) {
          final tp = painter(span);
          final w = tp.width;
          tp.dispose();
          return w.ceilToDouble();
        }

        final swatch = 10.0 * math.min(scaler.scale(10) / 10, 1.6) + 5;
        double extra(PlateReadout r) => r.dashed ? swatch : 0;
        final values = [for (final r in items) measure(valueSpan(r))];
        final lines = [
          for (final r in items)
            measure(TextSpan(text: r.label, style: labelStyle)) + extra(r),
        ];
        final words = [
          for (final r in items)
            r.label
                    .split(' ')
                    .map((w) => measure(TextSpan(text: w, style: labelStyle)))
                    .fold<double>(0, math.max) +
                extra(r),
        ];
        final avail = constraints.maxWidth - gap * (n - 1);
        List<double>? fit(List<double> labels, double k) {
          final mins = [
            for (var i = 0; i < n; i++) math.max(values[i] * k, labels[i]),
          ];
          if (mins.fold<double>(0, (a, b) => a + b) > avail) return null;
          return _gridColumns(mins, avail);
        }

        var k = 1.0;
        List<double>? widths;
        for (var step = 0; widths == null && step <= 10; step++) {
          k = 1 - 0.025 * step;
          widths = fit(lines, k);
        }
        for (var step = 0; widths == null && step <= 10; step++) {
          k = 1 - 0.025 * step;
          widths = fit(words, k);
        }
        // Enlarged text whose values cannot share the row: label / value
        // lines read better than squeezed figures. At 1.0× the row stays.
        if (widths == null && scaler.scale(10) > 11.5) return stacked();
        widths ??= List.filled(n, avail / n);
        // Every label area is as tall as the tallest label, its label at
        // the bottom: the values share one baseline.
        var labelBox = 0.0;
        for (var i = 0; i < n; i++) {
          final tp = painter(
            TextSpan(text: items[i].label, style: labelStyle),
            maxLines: 2,
            maxWidth: math.max(1.0, widths[i] - extra(items[i])),
          );
          labelBox = math.max(labelBox, tp.height);
          tp.dispose();
        }
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
                      ConstrainedBox(
                        constraints: BoxConstraints(minHeight: labelBox),
                        child: Align(
                          alignment: AlignmentDirectional.bottomStart,
                          child: label(items[i], maxLines: 2),
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: RollingText(
                          valueSpan(items[i], k),
                          delay: _delay(i),
                          duration: _roll,
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
      painter: _DashedRectPainter(color: context.akn.chartHighlight),
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
      const Radius.circular(2.5),
    );
    _drawDashed(canvas, Path()..addRRect(r), color, 1.5, 2.2, 1.6);
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) => old.color != color;
}

/// Strokes [path] dashed ([on] / [off] px), up to [progress] of its length.
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
    ..strokeCap = StrokeCap.round
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

/// Chart neutrals printed on the plate (v4 §9 "no muddy tinted slabs at
/// night"). By day the plate's warm context (`plateContext`, orange 24 %)
/// and track (`plateIconFill`) read as a soft peach on white; at night the
/// same orange tints read brown on graphite, so the past bars, segments and
/// tracks turn a neutral graphite there (the current bar keeps its orange
/// ramp). Off the plate these are the palette's own chart colours. Token
/// values are unchanged.
extension AknPlateChartColors on AknColors {
  /// Past months, upcoming segments, context steps.
  Color get plateChartContext =>
      isDark && isPlatePalette ? Color.lerp(surface, dim, 0.36)! : chartContext;

  /// Meter and bar tracks.
  Color get plateChartTrack =>
      isDark && isPlatePalette ? Color.lerp(surface, dim, 0.14)! : chartTrack;
}

/// The orange ramp of the current bar, the meters and the result step
/// (light → deep): on the plate `heroStart` → `plateAccent` (dark:
/// `plateAccent` → the logo orange), elsewhere a lighter shade of the
/// highlight → the highlight.
(Color, Color) _accentRamp(AknColors c) {
  if (c.isPlatePalette) {
    return c.isDark
        ? (c.chartHighlight, c.brand)
        : (c.heroStart, c.chartHighlight);
  }
  return (Color.lerp(c.chartHighlight, Colors.white, 0.22)!, c.chartHighlight);
}

/// The plate's mini bars (§4): past months in the context colour
/// (`plateContext`, orange 24 % on the plate), the current month-to-date as
/// an orange vertical gradient (`heroStart` → `plateAccent`) with a soft
/// glow, and a 1.5 px dashed outline from its top up to the month-end
/// [projection]. Bars are up to 24 wide in 44 px columns spaced evenly
/// over a 44 px tall area, rounded 8 on top and 3 at the baseline; month
/// labels 12/16 dim under them (the current one 700 ink).
///
/// The bars grow in on a springy stagger when they first appear — after
/// [delay] when [animate] is set (the deck's choreography), right away
/// otherwise — and the projection outline draws in last; the whole rise has
/// landed ~1.4 s after the first frame at the latest (a longer [delay] is
/// shortened), and reduce motion shows them risen. Tap a bar to see its
/// value in a small inverse bubble that pops up for 2 s; every bar is a
/// screen-reader node ([semanticLabels], e.g. "Ekim, 1.524.380 lira, ay
/// sonu tahmini 2,25 milyon lira").
class PlateBars extends StatefulWidget {
  const PlateBars({
    super.key,
    required this.values,
    required this.labels,
    this.currentIndex,
    this.projection,
    this.valueLabels,
    this.semanticLabels,
    this.height = 44,
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

  /// Bar area height (44).
  final double height;

  /// Grow after [delay] (the deck's choreography) instead of at once.
  final bool animate;
  final Duration delay;

  @override
  State<PlateBars> createState() => _PlateBarsState();
}

class _PlateBarsState extends State<PlateBars>
    with SingleTickerProviderStateMixin {
  /// One bar's growth (on [AknMotion.spring]) and the step between two bars
  /// ([AknMotion.barsStagger]).
  static const int _growMs = 480;
  static final int _stepMs = AknMotion.barsStagger.inMilliseconds;

  /// The projection outline draws in over this, starting before the last
  /// bar has quite landed.
  static final int _drawMs = AknMotion.projectionDraw.inMilliseconds;

  /// Without [PlateBars.animate] the bars wait this long (the card rises).
  static const Duration _restDelay = Duration(milliseconds: 140);

  /// The latest the rise starts, so that the bars (like every roll on the
  /// card) have landed ~1.4 s after the first frame.
  static const Duration _latestStart = Duration(milliseconds: 560);

  AnimationController? _rise;
  Timer? _delay;
  Timer? _bubbleTimer;
  int? _bubble;
  int _bubbleSerial = 0;
  bool _scheduled = false;

  int get _riseMs =>
      _growMs +
      _stepMs * math.max<int>(0, widget.values.length - 1) +
      _drawMs ~/ 2;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    if (AknMotion.reduced(context)) return;
    final c = _rise = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _riseMs),
    );
    final wait = widget.animate
        ? (widget.delay > _latestStart ? _latestStart : widget.delay)
        : _restDelay;
    if (wait <= Duration.zero) {
      c.forward();
    } else {
      _delay = Timer(wait, () {
        if (mounted) c.forward();
      });
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
    setState(() {
      _bubble = i;
      _bubbleSerial++;
    });
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
    final (highlightTop, highlight) = _accentRamp(c);
    final values = widget.values.take(n).toList();
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
                  // The current month is live: its glow breathes softly —
                  // inside the page's loop budget (v4 §6): it waits while
                  // the home's lead halo holds the one focus loop, then
                  // breathes three times and rests (still in tests and
                  // under reduce motion).
                  child: RepaintBoundary(
                    child: AknAmbient(
                      period: AknMotion.breathe,
                      reverse: true,
                      restValue: 0.5,
                      role: AknAmbientRole.focus,
                      cycles: 3,
                      builder: (context, breath, _) => CustomPaint(
                        painter: _BarsPainter(
                          values: values,
                          current: current,
                          selected: bubble,
                          projection: widget.projection,
                          context: c.plateChartContext,
                          highlight: highlight,
                          highlightTop: highlightTop,
                          outline: c.chartHighlight,
                          geometry: geo,
                          rise: _rise,
                          riseMs: _riseMs,
                          breath: breath,
                        ),
                      ),
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
                  key: ValueKey<int>(_bubbleSerial),
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
    required this.selected,
    required this.projection,
    required this.context,
    required this.highlight,
    required this.highlightTop,
    required this.outline,
    required this.geometry,
    required this.rise,
    required this.riseMs,
    this.breath = 0.5,
  }) : super(repaint: rise);

  final List<double> values;
  final int current;
  final int? selected;
  final double? projection;
  final Color context;
  final Color highlight;
  final Color highlightTop;
  final Color outline;
  final _BarsGeometry geometry;
  final Animation<double>? rise;
  final int riseMs;

  /// The current bar's glow breathing (0–1; 0.5 at rest).
  final double breath;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final max = [...values, ?projection].fold<double>(0, math.max);
    if (max <= 0) return;
    final h = size.height;
    final barW = math.max(4.0, math.min(24.0, geometry.column - 8));
    final elapsed = rise == null ? double.infinity : rise!.value * riseMs;
    double grow(int i) {
      if (rise == null) return 1;
      final start = (_PlateBarsState._stepMs * i).toDouble();
      final p = ((elapsed - start) / _PlateBarsState._growMs).clamp(0.0, 1.0);
      return AknMotion.spring.transform(p);
    }

    for (var i = 0; i < n; i++) {
      final v = values[i].clamp(0, max).toDouble();
      final g = grow(i);
      final bh = v / max * h * g;
      if (bh <= 0.5) continue;
      final cx = geometry.center(i);
      final rect = Rect.fromLTWH(cx - barW / 2, h - bh, barW, bh);
      final r = math.min(math.min(8.0, barW / 2), bh);
      final rb = math.min(3.0, bh / 2);
      final shape = RRect.fromRectAndCorners(
        rect,
        topLeft: Radius.circular(r),
        topRight: Radius.circular(r),
        bottomLeft: Radius.circular(rb),
        bottomRight: Radius.circular(rb),
      );
      if (i == current) {
        // A soft glow under the current bar; it breathes while the month
        // runs (0.24–0.40, 0.32 at rest).
        canvas.drawRRect(
          shape.shift(const Offset(0, 3)),
          Paint()
            ..color = highlight.withValues(
              alpha: (0.24 + 0.16 * breath) * g.clamp(0.0, 1.0) * highlight.a,
            )
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 + 2 * breath),
        );
        canvas.drawRRect(
          shape,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [highlightTop, highlight],
            ).createShader(Rect.fromLTWH(rect.left, h - v / max * h, barW, h)),
        );
      } else {
        canvas.drawRRect(
          shape,
          Paint()
            ..color = i == selected
                ? Color.lerp(context, highlight, 0.4)!
                : context,
        );
      }
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
        final rad = math.min(7.0, (r - l) / 2);
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
      old.selected != selected ||
      old.projection != projection ||
      old.context != context ||
      old.highlight != highlight ||
      old.highlightTop != highlightTop ||
      old.outline != outline ||
      old.geometry.width != geometry.width ||
      old.rise != rise ||
      old.breath != breath;
}

/// The small inverse bubble above a tapped bar: it pops up from the bar.
class _BarBubble extends StatelessWidget {
  const _BarBubble({
    super.key,
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
      fontFeatures: AknNumerals.tabular,
    );
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = tp.width + 16;
    final h = tp.height + 10;
    tp.dispose();
    final left = (centerX - w / 2)
        .clamp(0.0, math.max(0.0, maxWidth - w))
        .toDouble();
    // The bubble grows from the point above its bar.
    final origin = Alignment(
      w <= 0 ? 0 : ((centerX - left) / w * 2 - 1).clamp(-1.0, 1.0),
      1,
    );
    return Positioned(
      left: left,
      top: top - h - 6,
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: AknMotion.of(context, const Duration(milliseconds: 280)),
          builder: (context, v, child) => Opacity(
            opacity: (v * 2.5).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: v >= 1 ? 1.0 : 0.55 + 0.45 * AknMotion.pop.transform(v),
              alignment: origin,
              child: child,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: c.inverse,
              borderRadius: AknRadius.tag,
              boxShadow: AknShadows.raised(c),
            ),
            child: Text(text, style: style, maxLines: 1, softWrap: false),
          ),
        ),
      ),
    );
  }
}

/// A plate meter (§4): 12 px, fully rounded, track `chartTrack`
/// (`plateIconFill` on the plate), a fill that grows to [value] when it
/// first appears (and glides to new values) — an orange gradient on the
/// plate, ink on white — an optional [threshold] tick (2 px, 5 px beyond
/// both edges) that fades in once the fill has landed, and a dashed
/// [projection] tick. Values cap at 100 %.
class PlateMeter extends StatefulWidget {
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
  State<PlateMeter> createState() => _PlateMeterState();
}

class _PlateMeterState extends State<PlateMeter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );
  Timer? _timer;
  bool _started = false;
  double _from = 0;

  double get _value => widget.value.isNaN ? 0.0 : widget.value.clamp(0.0, 1.0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _timer = Timer(const Duration(milliseconds: 140), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void didUpdateWidget(PlateMeter old) {
    super.didUpdateWidget(old);
    final before = old.value.isNaN ? 0.0 : old.value.clamp(0.0, 1.0);
    if (before != _value) {
      _from = _shown(before);
      if (AknMotion.reduced(context)) {
        _c.value = 1;
      } else if (!(_timer?.isActive ?? false)) {
        _c.forward(from: 0);
      }
    }
  }

  /// The fill drawn now when heading to [target].
  double _shown(double target) =>
      _from + (target - _from) * AknMotion.emphasizedCurve.transform(_c.value);

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final v = _value;
    final plate = c.isPlatePalette;
    final (start, end) = _accentRamp(c);
    return Semantics(
      label: widget.semanticLabel,
      value: widget.semanticValue ?? '%${(v * 100).round()}',
      excludeSemantics: true,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _MeterPainter(
            progress: _c,
            from: _from,
            value: v,
            threshold: widget.threshold?.clamp(0.0, 1.0),
            projection: widget.projection?.clamp(0.0, 1.0),
            track: c.plateChartTrack,
            fill: plate ? end : c.ink,
            fillStart: plate ? start : c.ink,
            mark: c.ink,
            rtl: Directionality.of(context) == TextDirection.rtl,
          ),
        ),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  _MeterPainter({
    required this.progress,
    required this.from,
    required this.value,
    required this.threshold,
    required this.projection,
    required this.track,
    required this.fill,
    required this.fillStart,
    required this.mark,
    required this.rtl,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final double from;
  final double value;
  final double? threshold;
  final double? projection;
  final Color track;
  final Color fill;
  final Color fillStart;
  final Color mark;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final shown =
        from + (value - from) * AknMotion.emphasizedCurve.transform(t);
    if (rtl) {
      canvas.save();
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, r),
      Paint()..color = track,
    );
    if (shown > 0.001) {
      final w = math.max(size.height, size.width * shown);
      final rect = Rect.fromLTWH(0, 0, w, size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, r),
        Paint()
          ..shader = LinearGradient(
            colors: [fillStart, fill],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }
    // The marks arrive once the fill has (nearly) landed.
    final marks = ((t - 0.55) / 0.35).clamp(0.0, 1.0);
    final th = threshold;
    if (th != null && marks > 0) {
      final x = (size.width * th).clamp(1.0, size.width - 1);
      final reach = 5 * Curves.easeOutBack.transform(marks);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x - 1, -reach, x + 1, size.height + reach),
          const Radius.circular(1),
        ),
        Paint()..color = mark.withValues(alpha: mark.a * marks),
      );
    }
    final pr = projection;
    if (pr != null && marks > 0) {
      final x = (size.width * pr).clamp(1.0, size.width - 1);
      _drawDashed(
        canvas,
        Path()
          ..moveTo(x, -5)
          ..lineTo(x, size.height + 5),
        mark.withValues(alpha: mark.a * marks),
        2,
        3,
        2.5,
      );
    }
    if (rtl) canvas.restore();
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.progress != progress ||
      old.from != from ||
      old.value != value ||
      old.threshold != threshold ||
      old.projection != projection ||
      old.track != track ||
      old.fill != fill ||
      old.fillStart != fillStart ||
      old.mark != mark ||
      old.rtl != rtl;
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

/// The plate ledger (§4): lines 14/20 500 with values 15/20 700 (tabular)
/// right, separated by `plateLine` hairlines; the lines slide in one after
/// another when the ledger appears. A problem line starts with the red "!"
/// and is bold red.
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
      fontFeatures: AknNumerals.tabular,
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
              child: _Appear(
                delay: Duration(milliseconds: 160 + 70 * i),
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

/// Ranked bars (§4): label 14/20 500 left, value 15/20 700 (tabular) right,
/// then an 8 px rounded bar (an orange gradient on the plate, ink on white;
/// `chartTrack` track) that grows in, row after row, when it first appears.
/// The deck shows at most three rows; the full list is on `/stats`. Two
/// series get a small [legend].
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
      fontFeatures: AknNumerals.tabular,
    );
    final plate = c.isPlatePalette;
    final (start, end) = _accentRamp(c);
    final fillColor = plate ? end : c.ink;
    final fillStart = plate ? start : c.ink;
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
                const SizedBox(height: 5),
                _GrowBar(
                  height: 8,
                  fraction: rows[i].track <= 0
                      ? 0
                      : rows[i].fraction.clamp(0.0, rows[i].track),
                  track: rows[i].track.clamp(0.0, 1.0),
                  trackColor: c.plateChartTrack,
                  fill: fillColor,
                  fillStart: fillStart,
                  delay: Duration(milliseconds: 140 + 60 * i),
                ),
                const SizedBox(height: 9),
              ],
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
                          color: l.filled ? fillColor : c.plateChartTrack,
                          borderRadius: BorderRadius.circular(4),
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

  /// The result step (the orange accent).
  final bool highlight;
}

/// The plate funnel (§4): a label column (58 px), 18 px bars (radius 8) that
/// grow in step after step (context colour; the result in the highlight
/// gradient) and the value 15/20 700 (tabular) on the right.
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
      fontFeatures: AknNumerals.tabular,
    );
    final (highlightStart, highlightEnd) = _accentRamp(c);
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
                          child: _GrowBar(
                            height: 18,
                            radius: 8,
                            fraction: steps[i].fraction.clamp(0.0, 1.0),
                            fill: steps[i].highlight
                                ? highlightEnd
                                : c.plateChartContext,
                            fillStart: steps[i].highlight
                                ? highlightStart
                                : c.plateChartContext,
                            delay: Duration(milliseconds: 140 + 60 * i),
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

/// A rounded bar that grows from the start edge to [fraction] of its width
/// when it first appears (and glides to new values): an optional track
/// ([trackColor] over [track] of the width) and a [fillStart] → [fill]
/// gradient. Decorative (its row carries the words).
class _GrowBar extends StatefulWidget {
  const _GrowBar({
    required this.height,
    required this.fraction,
    required this.fill,
    required this.fillStart,
    this.track = 1,
    this.trackColor,
    this.radius,
    this.delay = Duration.zero,
  });

  final double height;
  final double fraction;
  final Color fill;
  final Color fillStart;
  final double track;
  final Color? trackColor;
  final double? radius;
  final Duration delay;

  @override
  State<_GrowBar> createState() => _GrowBarState();
}

class _GrowBarState extends State<_GrowBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  );
  Timer? _timer;
  bool _started = false;
  double _from = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else if (widget.delay <= Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void didUpdateWidget(_GrowBar old) {
    super.didUpdateWidget(old);
    if (old.fraction != widget.fraction) {
      _from =
          _from +
          (old.fraction - _from) *
              AknMotion.emphasizedCurve.transform(_c.value);
      if (AknMotion.reduced(context)) {
        _c.value = 1;
      } else if (!(_timer?.isActive ?? false)) {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: widget.height,
      width: double.infinity,
      child: CustomPaint(
        painter: _GrowBarPainter(
          progress: _c,
          from: _from,
          fraction: widget.fraction,
          track: widget.track,
          trackColor: widget.trackColor,
          fill: widget.fill,
          fillStart: widget.fillStart,
          radius: widget.radius ?? widget.height / 2,
          rtl: Directionality.of(context) == TextDirection.rtl,
        ),
      ),
    ),
  );
}

class _GrowBarPainter extends CustomPainter {
  _GrowBarPainter({
    required this.progress,
    required this.from,
    required this.fraction,
    required this.track,
    required this.trackColor,
    required this.fill,
    required this.fillStart,
    required this.radius,
    required this.rtl,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final double from;
  final double fraction;
  final double track;
  final Color? trackColor;
  final Color fill;
  final Color fillStart;
  final double radius;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    if (rtl) {
      canvas.save();
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final r = Radius.circular(math.min(radius, size.height / 2));
    final tc = trackColor;
    if (tc != null && track > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width * track, size.height),
          r,
        ),
        Paint()..color = tc,
      );
    }
    final t = AknMotion.emphasizedCurve.transform(progress.value);
    final shown = from + (fraction - from) * t;
    if (shown > 0.001) {
      final w = math.max(size.height, size.width * shown);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), r),
        Paint()
          ..shader = LinearGradient(
            colors: [fillStart, fill],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }
    if (rtl) canvas.restore();
  }

  @override
  bool shouldRepaint(_GrowBarPainter old) =>
      old.progress != progress ||
      old.from != from ||
      old.fraction != fraction ||
      old.track != track ||
      old.trackColor != trackColor ||
      old.fill != fill ||
      old.fillStart != fillStart ||
      old.radius != radius ||
      old.rtl != rtl;
}

/// A line on the plate (§4, "Ortalama birim fiyat"): a 2.5 px line in the
/// highlight colour over a soft wash of it, a 10 px end dot with a 2 px
/// surface ring and a halo, the end value label 12/16 700 (tabular), a
/// baseline hairline and month labels (the last one 700). It draws itself
/// from left to right when it first appears, then the dot pops.
class PlateLine extends StatefulWidget {
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
  State<PlateLine> createState() => _PlateLineState();
}

class _PlateLineState extends State<PlateLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _timer = Timer(const Duration(milliseconds: 100), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Semantics(
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel != null,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _LinePainter(
            progress: _c,
            values: widget.values,
            labels: widget.labels,
            endLabel: widget.endLabel,
            line: c.chartHighlight,
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
              fontFeatures: AknNumerals.tabular,
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
    required this.progress,
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
  }) : super(repaint: progress);

  final Animation<double> progress;
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
    final v = progress.value;
    // The line draws over the first 72 %, the dot pops after it, the end
    // label fades in last.
    final draw = AknMotion.emphasizedCurve.transform(
      (v / 0.72).clamp(0.0, 1.0),
    );
    final pop = ((v - 0.62) / 0.3).clamp(0.0, 1.0);
    final label = ((v - 0.78) / 0.22).clamp(0.0, 1.0);
    final n = values.length;
    final labelH = labels.isEmpty ? 0.0 : scaler.scale(12) * 16 / 12;
    final baseY = size.height - labelH;
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
      for (var i = 0; i < labels.length; i++) {
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
    if (draw > 0) {
      final metrics = path.computeMetrics().toList();
      final length = metrics.fold<double>(0, (a, m) => a + m.length);
      final shown = Path();
      var left0 = length * draw;
      Offset head = Offset(x(0), y(0));
      for (final m in metrics) {
        if (left0 <= 0) break;
        final take = math.min(left0, m.length);
        shown.addPath(m.extractPath(0, take), Offset.zero);
        head = m.getTangentForOffset(take)?.position ?? head;
        left0 -= take;
      }
      // A soft wash under the line, up to its drawing head.
      final area = Path.from(shown)
        ..lineTo(head.dx, baseY - 1)
        ..lineTo(x(0), baseY - 1)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              line.withValues(alpha: 0.18 * line.a),
              line.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromLTRB(0, top, size.width, baseY)),
      );
      canvas.drawPath(
        shown,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    if (pop > 0) {
      final end = Offset(x(n - 1), y(n - 1));
      final s = AknMotion.pop.transform(pop);
      canvas.drawCircle(
        end,
        11 * s,
        Paint()..color = dot.withValues(alpha: 0.18 * dot.a * pop),
      );
      canvas.drawCircle(end, 7 * s, Paint()..color = ring);
      canvas.drawCircle(end, 5 * s, Paint()..color = dot);
      final el = endLabel;
      if (el != null && label > 0) {
        final tp = _tp(
          el,
          strongStyle.copyWith(
            color: strongStyle.color?.withValues(
              alpha: (strongStyle.color?.a ?? 1) * label,
            ),
          ),
        );
        final lx = (end.dx - 10 - tp.width).clamp(0.0, size.width - tp.width);
        final ly = (end.dy - 8 - tp.height + 4 * (1 - label)).clamp(
          0.0,
          size.height,
        );
        tp.paint(canvas, Offset(lx, ly));
        tp.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.progress != progress ||
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
/// of overflowing) and rolls up into place after [delay].
class _StackedReadout extends StatelessWidget {
  const _StackedReadout({
    required this.label,
    required this.labelSpan,
    required this.valueSpan,
    required this.delay,
  });

  final Widget label;
  final InlineSpan labelSpan;
  final InlineSpan valueSpan;
  final Duration delay;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final max = constraints.maxWidth;
      final valueW = _spanWidth(context, valueSpan);
      final labelMin = math.min(_spanWidth(context, labelSpan), max * 0.4);
      final value = RollingText(
        valueSpan,
        delay: delay,
        duration: PlateReadouts._roll,
      );
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

/// Pops its child in once (fade + scale from [from] on [AknMotion.pop])
/// after [delay]; static under reduce motion. Its wrappers stay in the tree
/// afterwards (identity), so the child is never remounted.
class _PopIn extends StatefulWidget {
  const _PopIn({
    required this.child,
    this.delay = Duration.zero,
    this.from = 0.6,
  });

  final Widget child;
  final Duration delay;
  final double from;

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else if (widget.delay <= Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      final v = _c.value;
      return Opacity(
        opacity: (v * 2.2).clamp(0.0, 1.0),
        alwaysIncludeSemantics: true,
        child: Transform.scale(
          scale: v >= 1
              ? 1.0
              : widget.from + (1 - widget.from) * AknMotion.pop.transform(v),
          child: child,
        ),
      );
    },
  );
}

/// Fades its child in once, rising 6 px, after [delay] (a ledger line);
/// the wrappers stay in the tree afterwards. Static under reduce motion.
class _Appear extends StatefulWidget {
  const _Appear({required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else if (widget.delay <= Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      final v = _c.value >= 1 ? 1.0 : AknMotion.standard.transform(_c.value);
      return Opacity(
        opacity: v,
        alwaysIncludeSemantics: true,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - v)),
          child: child,
        ),
      );
    },
  );
}
