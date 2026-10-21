import 'package:flutter/material.dart';

import '../../utils/format.dart';
import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import 'cards.dart';
import 'skeletons.dart';

/// KPI tile: label, counting-up value (tabular figures), optional icon,
/// trend chip and caption. Counts up from 0 on first show and from the old
/// value on change (emphasized 600 ms); reduce motion shows the value.
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
    this.positiveIsGood = true,
    this.caption,
    this.onTap,
    this.loading = false,
    this.semanticLabel,
  });

  final String label;

  /// Null shows "—".
  final num? value;

  /// Value formatter; defaults to `Fmt.integer` (`12.500`). Use `Fmt.money`,
  /// `Fmt.moneyCompact`, `Fmt.liters`.
  final String Function(num value)? format;
  final IconData? icon;

  /// Tints the icon box.
  final AknTone? tone;

  /// Change in percent (12.5 = +%12,5).
  final num? trend;
  final String? trendLabel;
  final bool positiveIsGood;
  final String? caption;
  final VoidCallback? onTap;
  final bool loading;
  final String? semanticLabel;

  String _fmt(num v) => (format ?? Fmt.integer)(v);

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final v = value;
    final display = v == null ? Fmt.dash : _fmt(v);
    final trendValue = trend;
    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: t.captionStrong,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 8),
              AknIconBox(icon: icon!, tone: tone, size: 30, iconSize: 17),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (loading)
          const SkeletonBox(width: 96, height: 28)
        else if (v == null)
          Text(display, style: t.amountLarge)
        else
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: v.toDouble()),
            duration: AknMotion.of(context, AknMotion.emphasized),
            curve: AknMotion.emphasizedCurve,
            builder: (context, x, _) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                // Integers count in whole steps; decimals keep the format.
                _fmt(v is int ? x.round() : x),
                style: t.amountLarge,
                maxLines: 1,
              ),
            ),
          ),
        if (trendValue != null || caption != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              if (trendValue != null) ...[
                _TrendChip(
                  trend: trendValue,
                  positiveIsGood: positiveIsGood,
                  colors: c,
                ),
                const SizedBox(width: 6),
              ],
              if (caption != null || trendLabel != null)
                Expanded(
                  child: Text(
                    trendLabel ?? caption!,
                    style: t.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
    final trendText = trendValue == null
        ? ''
        : ', değişim ${trendValue >= 0 ? 'artı' : 'eksi'} '
              '${Fmt.percent(trendValue.abs())}';
    return Semantics(
      label: semanticLabel ?? '$label: $display$trendText',
      button: onTap != null,
      excludeSemantics: true,
      child: AknCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: body,
      ),
    );
  }
}

class _TrendChip extends StatelessWidget {
  const _TrendChip({
    required this.trend,
    required this.positiveIsGood,
    required this.colors,
  });

  final num trend;
  final bool positiveIsGood;
  final AknColors colors;

  @override
  Widget build(BuildContext context) {
    final up = trend > 0;
    final flat = trend == 0;
    final good = flat ? null : up == positiveIsGood;
    final tc = colors.tone(
      good == null
          ? AknTone.neutral
          : good
          ? AknTone.ok
          : AknTone.danger,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 1, 6, 1),
      decoration: BoxDecoration(color: tc.bg, borderRadius: AknRadius.pillAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            flat
                ? Icons.remove_rounded
                : up
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: 12,
            color: tc.fg,
          ),
          const SizedBox(width: 2),
          Text(
            Fmt.percent(trend.abs()),
            style: TextStyle(
              color: tc.fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of [KpiTile]s with equal widths and equal heights (12 px gaps).
///
/// Reflows to one tile per line when the text is large (≥ 1.6×) and a tile
/// would be narrower than [minTileWidth]: labels such as "Planlanacak" then
/// wrap at word boundaries instead of breaking mid-word (WCAG 1.4.10).
class KpiRow extends StatelessWidget {
  const KpiRow({
    super.key,
    required this.children,
    this.spacing = AknSpace.s12,
    this.minTileWidth = 220,
  });

  final List<Widget> children;
  final double spacing;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(10) >= 16;
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = children.length;
        final perTile = n == 0
            ? constraints.maxWidth
            : (constraints.maxWidth - spacing * (n - 1)) / n;
        if (large && n > 1 && perTile < minTileWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                children[i],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) SizedBox(width: spacing),
                Expanded(child: children[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}
