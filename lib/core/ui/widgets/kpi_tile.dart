import 'package:flutter/material.dart';

import '../../utils/format.dart';
import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import 'skeletons.dart';
import 'triangle_glyph.dart';

/// A readout (design v2 §6.9): label 13/16 500 dim over the value in
/// `number` (Condensed 24/28 700), with an optional delta after it (a drawn
/// ▲ / ▼ and 13/18 500 text). No card, no icon box, no shadow, no count-up —
/// the final value renders at once (only the plate rolls).
///
/// The delta takes the ok / danger colour only when it is known whether a
/// rise is good for the viewer ([positiveIsGood] set); otherwise it is dim.
/// The value scales down in its column instead of wrapping mid-number.
///
/// [icon] and [tone] are kept for API stability and ignored (no icon boxes
/// in v2).
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

  /// Ignored in v2 (no icon boxes).
  final IconData? icon;

  /// Ignored in v2 (readouts carry no tint).
  final AknTone? tone;

  /// Change in percent (12.5 = +%12,5).
  final num? trend;

  /// Text after the delta ("geçen aya göre"); also the caption line.
  final String? trendLabel;

  /// Whether a rise is good for the viewer; null = unknown (dim delta).
  final bool? positiveIsGood;
  final String? caption;
  final VoidCallback? onTap;
  final bool loading;
  final String? semanticLabel;

  /// A unit after the value in `readoutUnit` (16/28): "L", "₺/L".
  final String? unit;

  /// Formats the absolute [trend] next to the value; defaults to a percent
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
    final labelStyle = t.label.copyWith(height: 16 / 13, color: c.dim);
    final valueStyle = t.number.copyWith(color: c.ink);
    final unitStyle = t.readoutUnit.copyWith(color: c.ink);
    Widget? delta;
    if (trendValue != null) {
      final up = trendValue > 0;
      final flat = trendValue == 0;
      final good = flat || positiveIsGood == null ? null : up == positiveIsGood;
      final color = good == null
          ? c.dim
          : good
          ? c.ok.fg
          : c.danger.fg;
      final style = t.label.copyWith(color: color);
      delta = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!flat) ...[
            TriangleGlyph.small(down: !up, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            flat ? 'aynı' : (trendFormat ?? Fmt.percent)(trendValue.abs()),
            style: style,
            maxLines: 1,
            softWrap: false,
          ),
        ],
      );
    }
    final valueLine = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      // The change sits at the foot of the value ("41,92 ▲ 0,38"); bottom
      // alignment puts both baselines within a pixel (Mona's metrics) and,
      // unlike baseline alignment, works inside the row's IntrinsicHeight.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text.rich(
            TextSpan(
              text: display,
              style: valueStyle,
              children: [
                if (unit != null && unit!.isNotEmpty)
                  TextSpan(text: ' $unit', style: unitStyle),
              ],
            ),
            maxLines: 1,
            softWrap: false,
          ),
          if (delta != null) ...[const SizedBox(width: 5), delta],
        ],
      ),
    );
    final note = trendLabel ?? caption;
    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: labelStyle,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        if (loading) const SkeletonBox(width: 96, height: 28) else valueLine,
        if (note != null && note.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            note,
            style: t.label.copyWith(fontWeight: FontWeight.w400, color: c.dim),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
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

/// A row of readouts (design v2 §6.9) on the Tüpraş-strip model: a top
/// hairline, then equal columns separated by 1 px vertical hairlines, 12 px
/// inner padding (no padding before the first column). Two columns per line
/// below 340 px or at text scale ≥ 1.3; at ≥ 1.6× one per line when a column
/// would be narrower than [minTileWidth], so labels wrap at word boundaries
/// instead of breaking mid-word (WCAG 1.4.10).
class KpiRow extends StatelessWidget {
  const KpiRow({
    super.key,
    required this.children,
    this.spacing = AknSpace.s12,
    this.minTileWidth = 220,
    this.topLine = true,
  });

  final List<Widget> children;

  /// Inner padding after each hairline.
  final double spacing;

  /// Below this column width at very large text, one column per line.
  final double minTileWidth;

  /// The hairline on top of the row (the strip's edge).
  final bool topLine;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
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
            final first = i == start;
            cells.add(
              Expanded(
                child: Container(
                  padding: EdgeInsetsDirectional.only(
                    start: first ? 0 : spacing,
                    top: 8,
                    end: 4,
                  ),
                  decoration: first
                      ? null
                      : BoxDecoration(
                          border: BorderDirectional(
                            start: BorderSide(color: c.line),
                          ),
                        ),
                  child: i < end ? children[i] : const SizedBox.shrink(),
                ),
              ),
            );
          }
          lines.add(
            Container(
              decoration: topLine || start > 0
                  ? BoxDecoration(
                      border: Border(top: BorderSide(color: c.line)),
                    )
                  : null,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: cells,
                ),
              ),
            ),
          );
          if (start + perLine < n) lines.add(const SizedBox(height: 8));
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
