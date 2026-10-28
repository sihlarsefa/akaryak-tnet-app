import 'dart:async';

import 'package:flutter/material.dart';

import '../../utils/format.dart';
import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';
import 'animated_number.dart';
import 'cards.dart';
import 'skeletons.dart';

/// A KPI tile (design v3 §4 "KPI tiles"): a white card (radius 20, the soft
/// card shadow) with the label in `caption` dim over the value in `number`
/// (24/30 800, tabular) that counts up when it appears ([AnimatedNumber]),
/// an optional unit (`readoutUnit`) and a delta chip under it (a drawn ▲ /
/// ▼ and the change, 12/16 700) that pops in after the count.
///
/// The delta takes the ok / danger colours only when it is known whether a
/// rise is good for the viewer ([positiveIsGood] set); otherwise it is a
/// neutral chip. On a card, a sheet or the hero card the tile is a quiet
/// well instead of a card; inside a [KpiRow] the row draws the cell. The
/// value scales down in its column instead of wrapping mid-number.
///
/// [icon] and [tone] are kept for API stability and ignored.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    this.format,
    this.icon,
    this.tone,
    this.trend,
    this.trendLabel,
    this.positiveIsGood,
    this.caption,
    this.onTap,
    this.loading = false,
    this.semanticLabel,
    this.unit,
    this.trendFormat,
  });

  final String label;

  /// Null shows "—".
  final num? value;

  /// Value formatter; defaults to `Fmt.integer` (`12.500`). Use `Fmt.money`,
  /// `Fmt.moneyCompact`, `Fmt.liters`.
  final String Function(num value)? format;

  /// Ignored (no icon boxes on KPI tiles).
  final IconData? icon;

  /// Ignored (KPI tiles carry no tint).
  final AknTone? tone;

  /// Change in percent (12.5 = +%12,5).
  final num? trend;

  /// Text after the delta ("geçen aya göre"); also the caption line.
  final String? trendLabel;

  /// Whether a rise is good for the viewer; null = unknown (neutral delta).
  final bool? positiveIsGood;
  final String? caption;
  final VoidCallback? onTap;
  final bool loading;
  final String? semanticLabel;

  /// A unit after the value in `readoutUnit` (14/30 700): "L", "₺/L".
  final String? unit;

  /// Formats the absolute [trend] in the delta chip; defaults to a percent
  /// ("%12,5"). The Tüpraş strip shows lira: `(v) => Fmt.number(v,
  /// minFraction: 2, maxFraction: 2)` → "▲ 0,38". A zero change reads
  /// "aynı".
  final String Function(num change)? trendFormat;

  String _fmt(num v) => (format ?? Fmt.integer)(v);

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final v = value;
    final display = v == null ? Fmt.dash : _fmt(v);
    final trendValue = trend;
    final inRow = _KpiCellScope.isOn(context);
    final well = inRow
        ? _KpiCellScope.wellOf(context)
        : AknCardScope.onSurface(context);
    final labelStyle = t.caption.copyWith(color: c.dim);
    final valueStyle = t.number.copyWith(color: c.ink);
    final unitStyle = t.readoutUnit.copyWith(
      height: 1.2,
      color: c.dim,
      fontWeight: FontWeight.w700,
    );
    Widget? delta;
    if (trendValue != null) {
      final up = trendValue > 0;
      final flat = trendValue == 0;
      final good = flat || positiveIsGood == null ? null : up == positiveIsGood;
      final onPlate = OnHero.isOn(context);
      final (Color bg, Color fg) = good == null
          ? onPlate
                ? (c.plateIconFill, c.brandInk)
                : (well ? c.surface : c.surfaceAlt, flat ? c.dim : c.ink)
          : good
          ? (c.ok.bg, c.ok.fg)
          : (c.danger.bg, c.danger.fg);
      final style = t.captionStrong.copyWith(
        color: fg,
        fontFeatures: AknNumerals.tabular,
      );
      delta = _PopIn(
        delay: AknMotion.count * 0.6,
        handoff: ('KpiTile.delta', label, trendValue),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 2, 7, 2),
          decoration: BoxDecoration(color: bg, borderRadius: AknRadius.tag),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!flat) ...[
                TriangleGlyph.small(down: !up, color: fg),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  flat
                      ? 'aynı'
                      : (trendFormat ?? Fmt.percent)(trendValue.abs()),
                  style: style,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final hasUnit = v != null && unit != null && unit!.isNotEmpty;
    final valueLine = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (v == null)
            Text(display, style: valueStyle, maxLines: 1, softWrap: false)
          else
            AnimatedNumber(
              value: v,
              format: _fmt,
              style: valueStyle,
              semanticsLabel: display,
            ),
          if (hasUnit) ...[
            const SizedBox(width: AknNumerals.readoutUnitGap),
            Text(unit!, style: unitStyle, maxLines: 1, softWrap: false),
          ],
        ],
      ),
    );
    final note = trendLabel ?? caption;
    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: labelStyle,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        if (loading)
          const SkeletonBox(width: 72, height: 28, radius: 8)
        else
          valueLine,
        if (delta != null && !loading) ...[const SizedBox(height: 8), delta],
        if (note != null && note.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            note,
            style: t.caption.copyWith(color: c.dim),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
    if (!inRow) body = _KpiCell(well: well, child: body);
    final trendText = trendValue == null
        ? ''
        : trendValue == 0
        ? ', değişim yok'
        : ', değişim ${trendValue > 0 ? 'artı' : 'eksi'} '
              '${(trendFormat ?? Fmt.percent)(trendValue.abs())}';
    final unitText = unit == null || v == null ? '' : ' $unit';
    final semantics = semanticLabel ?? '$label: $display$unitText$trendText';
    if (onTap == null) {
      return Semantics(label: semantics, excludeSemantics: true, child: body);
    }
    return Semantics(
      label: semantics,
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AknHaptics.selection();
          onTap!();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AknSpace.minTap),
          child: PressScale(child: body),
        ),
      ),
    );
  }
}

/// A row of KPI tiles (design v3 §4): equal columns [spacing] (12) apart,
/// each cell a white card (radius 20, the soft card shadow; dark: a 1 px
/// `line`) — or, on a card, a sheet or the hero card, a quiet well
/// (`surfaceAlt`, radius 16) — with equal heights per line. Two cells per
/// line below 340 px or at text scale ≥ 1.3 (with more than two); at ≥ 1.6×
/// one per line when a cell would be narrower than [minTileWidth], so
/// labels wrap at word boundaries instead of breaking mid-word (WCAG
/// 1.4.10).
///
/// Any widget can be a cell; [KpiTile]s inside draw no card of their own.
class KpiRow extends StatelessWidget {
  const KpiRow({
    super.key,
    required this.children,
    this.spacing = AknSpace.s12,
    this.minTileWidth = 220,
    this.topLine = true,
  });

  final List<Widget> children;

  /// The gap between two cells (and two lines).
  final double spacing;

  /// Below this cell width at very large text, one cell per line.
  final double minTileWidth;

  /// Ignored (the cells are cards; there is no strip edge any more).
  final bool topLine;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final well = AknCardScope.onSurface(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = children.length;
        if (n == 0) return const SizedBox.shrink();
        final w = constraints.maxWidth;
        var perLine = n;
        if (n > 2 && (w < 340 || scale >= 1.3)) perLine = 2;
        if (perLine > 1 &&
            scale >= 1.6 &&
            (w - spacing * (perLine - 1)) / perLine < minTileWidth) {
          perLine = 1;
        }
        final lines = <Widget>[];
        for (var start = 0; start < n; start += perLine) {
          final end = (start + perLine).clamp(0, n);
          final cells = <Widget>[];
          for (var i = start; i < start + perLine; i++) {
            if (i > start) cells.add(SizedBox(width: spacing));
            cells.add(
              Expanded(
                child: i < end
                    ? _KpiCellScope(
                        well: well,
                        child: _KpiCell(well: well, child: children[i]),
                      )
                    : const SizedBox.shrink(),
              ),
            );
          }
          if (start > 0) lines.add(SizedBox(height: spacing));
          lines.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cells,
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: lines,
        );
      },
    );
  }
}

/// Tells a [KpiTile] that its [KpiRow] draws the cell.
class _KpiCellScope extends InheritedWidget {
  const _KpiCellScope({required this.well, required super.child});

  final bool well;

  static bool isOn(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_KpiCellScope>() != null;

  static bool wellOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_KpiCellScope>()?.well ?? false;

  @override
  bool updateShouldNotify(_KpiCellScope old) => old.well != well;
}

/// One KPI cell: a white card on the page, a quiet well on a surface.
class _KpiCell extends StatelessWidget {
  const _KpiCell({required this.well, required this.child});

  final bool well;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return DecoratedBox(
      decoration: well
          ? BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: const BorderRadius.all(Radius.circular(16)),
            )
          : BoxDecoration(
              color: c.surface,
              borderRadius: AknRadius.card,
              border: c.isDark ? Border.all(color: c.line) : null,
              boxShadow: AknShadows.card(c),
            ),
      child: AknCardScope(
        child: Padding(
          padding: well
              ? const EdgeInsets.fromLTRB(12, 10, 10, 12)
              : const EdgeInsets.fromLTRB(14, 12, 12, 14),
          child: child,
        ),
      ),
    );
  }
}

/// Pops its child in once (fade + scale from 0.6 on the pop curve) after
/// [delay]; static under reduce motion. The structure never changes, so
/// the child keeps its state.
class _PopIn extends StatefulWidget {
  const _PopIn({
    required this.child,
    required this.handoff,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  /// Names the content for [AknEntranceHandoff].
  final Object handoff;

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final handed = AknEntranceHandoff.take(widget.handoff);
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else if (handed != null && handed > 0) {
      _c.value = handed;
      if (handed < 1) _c.forward();
    } else if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void deactivate() {
    AknEntranceHandoff.put(widget.handoff, _c.value);
    super.deactivate();
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
      final s = 0.6 + 0.4 * AknMotion.pop.transform(v);
      return Opacity(
        opacity: Curves.easeOut.transform(v),
        child: Transform.scale(
          scale: s,
          alignment: AlignmentDirectional.centerStart.resolve(
            Directionality.of(context),
          ),
          child: child,
        ),
      );
    },
  );
}
