import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../stats_format.dart';

/// Sayaç: değer 0'dan (değişince önceki değerden) hedefe sayar, 750 ms easeOutCubic. Hareket azaltma
/// açıkken doğrudan son değer yazılır. Ekran okuyucu yalnızca son değeri okur.
class StatsCountUp extends StatelessWidget {
  const StatsCountUp({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.duration = const Duration(milliseconds: 750),
    this.semanticsLabel,
    this.textAlign,
  });

  final num value;

  /// Ara karelerde de kullanılır (tamsayılar yuvarlanarak gelir).
  final String Function(num value) format;
  final TextStyle? style;
  final Duration duration;
  final String? semanticsLabel;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final target = value.toDouble();
    final finalText = format(value);
    final Widget text;
    if (AknMotion.reduced(context) || target == 0 || !target.isFinite) {
      text = Text(finalText, style: style, maxLines: 1, textAlign: textAlign);
    } else {
      text = TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: target),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (context, x, _) => Text(
          x == target ? finalText : format(value is int ? x.round() : x),
          style: style,
          maxLines: 1,
          textAlign: textAlign,
        ),
      );
    }
    return Semantics(
      label: semanticsLabel ?? finalText,
      excludeSemantics: true,
      child: text,
    );
  }
}

/// Kartın büyük rakamı: sığmazsa küçülür, asla taşmaz (F2GO `_Rakam`); yanında kısa açıklama.
class StatsFigure extends StatelessWidget {
  const StatsFigure({
    super.key,
    required this.value,
    required this.format,
    this.suffix,
    this.size = 30,
    this.color,
    this.semanticsLabel,
  });

  final num value;
  final String Function(num value) format;
  final String? suffix;
  final double size;
  final Color? color;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: StatsCountUp(
              value: value,
              format: format,
              semanticsLabel: semanticsLabel == null
                  ? null
                  : '$semanticsLabel${suffix == null ? '' : ' $suffix'}',
              style: t.amountLarge.copyWith(
                fontSize: size,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1.1,
                color: color ?? c.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        if (suffix != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: ExcludeSemantics(
              excluding: semanticsLabel != null,
              child: Text(
                suffix!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.label.copyWith(color: c.dim, fontSize: 13),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Önceki döneme göre fark: "▲ %8,6" çipi (iyiyse yeşil, kötüyse kırmızı; birim fiyatta düşüş iyidir)
/// + "geçen aya göre". Önceki değer yoksa ya da sıfırsa hiçbir şey çizilmez.
class DeltaChip extends StatelessWidget {
  const DeltaChip({
    super.key,
    required this.current,
    required this.previous,
    required this.compareLabel,
    this.lowerIsBetter = false,
  });

  final num? current;
  final num? previous;
  final String compareLabel;
  final bool lowerIsBetter;

  @override
  Widget build(BuildContext context) {
    final pct = StatsFmt.change(current, previous);
    if (pct == null) return const SizedBox.shrink();
    final c = context.akn;
    final t = context.aknText;
    final good = StatsFmt.deltaIsGood(pct, lowerIsBetter: lowerIsBetter);
    final tc = c.tone(
      good == null
          ? AknTone.neutral
          : good
          ? AknTone.ok
          : AknTone.danger,
    );
    return Semantics(
      label: '$compareLabel ${StatsFmt.deltaSpoken(pct)}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            key: const ValueKey('stats-delta'),
            padding: const EdgeInsets.fromLTRB(2, 1, 8, 1),
            decoration: BoxDecoration(
              color: tc.bg,
              borderRadius: AknRadius.pillAll,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ▲ / ▼ simge olarak (glif her yazı tipinde bulunmaz).
                Icon(
                  good == null
                      ? Icons.remove_rounded
                      : pct > 0
                      ? Icons.arrow_drop_up_rounded
                      : Icons.arrow_drop_down_rounded,
                  size: good == null ? 14 : 20,
                  color: tc.fg,
                ),
                Text(
                  StatsFmt.deltaPercent(pct),
                  style: t.captionStrong.copyWith(
                    color: tc.fg,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              compareLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.caption.copyWith(color: c.dim),
            ),
          ),
        ],
      ),
    );
  }
}

/// Küçük etiket çipi (tonlu zemin + ikon + metin): "Gecikmiş 820 B ₺ · 4".
class StatsTag extends StatelessWidget {
  const StatsTag({
    super.key,
    required this.label,
    this.tone = AknTone.neutral,
    this.icon,
  });

  final String label;
  final AknTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final tc = c.tone(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: tc.bg, borderRadius: AknRadius.pillAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tc.fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.captionStrong.copyWith(
                color: tc.fg,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Yatay pay çubuğu: dolu kısım [color], iz aynı rengin açık tonu; dolgu 0'dan büyür.
class ShareBar extends StatelessWidget {
  const ShareBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 6,
    this.delay = Duration.zero,
  });

  /// 0..1.
  final double value;
  final Color color;
  final double height;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final reduced = AknMotion.reduced(context);
    return ClipRRect(
      borderRadius: AknRadius.pillAll,
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: color.withValues(alpha: 0.14)),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: reduced ? v : 0, end: v),
              duration: reduced
                  ? Duration.zero
                  : const Duration(milliseconds: 700) + delay,
              curve: reduced
                  ? Curves.linear
                  : Interval(
                      delay.inMilliseconds /
                          (700 + delay.inMilliseconds).toDouble(),
                      1,
                      curve: Curves.easeOutCubic,
                    ),
              builder: (context, f, _) => FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: f,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: AknRadius.pillAll,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Başlık + sondaki değerler satırı, hiçbir yazı ölçeğinde taşmaz: [leading] (ikon, sıra, nokta) doğal
/// genişliğinde, [title] kalan yeri alır (kendisi kısalır), [trailing] (tutar, yüzde) doğal genişliğinde
/// durur; satırın [trailingShare] kadarından genişse orantılı küçülür.
class StatsLineRow extends StatelessWidget {
  const StatsLineRow({
    super.key,
    required this.title,
    required this.trailing,
    this.leading,
    this.gap = 8,
    this.trailingShare = 0.62,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final Widget? leading;
  final Widget title;
  final Widget trailing;
  final double gap;
  final double trailingShare;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) => Row(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          ?leading,
          Expanded(child: title),
          SizedBox(width: gap),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: cons.maxWidth.isFinite
                  ? cons.maxWidth * trailingShare
                  : double.infinity,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: trailing,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sıralı satır: "1  Anadolu Lojistik ……… 5,1 Mn ₺" + pay çubuğu (+ alt satır).
class ShareRow extends StatelessWidget {
  const ShareRow({
    super.key,
    required this.title,
    required this.value,
    required this.share,
    required this.color,
    this.rank,
    this.subtitle,
    this.trailingNote,
    this.index = 0,
    this.semanticsLabel,
    this.showBar = true,
  });

  final String title;
  final String value;

  /// 0..1 (çubuk).
  final double share;

  /// Pay çubuğu (oranı anlamsız satırda, ör. limitsiz bayi, gizlenir).
  final bool showBar;
  final Color color;
  final int? rank;
  final String? subtitle;

  /// Değerin yanında küçük not ("%23").
  final String? trailingNote;

  /// Sıra (çubuklar sırayla büyür).
  final int index;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    // Sıra sütunu iki haneye yeter ve yazıyla büyür (1–10 hizalı kalır).
    final rankW = rank == null
        ? 0.0
        : MediaQuery.textScalerOf(context).scale(20);
    return Semantics(
      label:
          semanticsLabel ?? [title, value, ?trailingNote, ?subtitle].join(', '),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          StatsLineRow(
            leading: rank == null
                ? null
                : SizedBox(
                    width: rankW,
                    child: Text(
                      '$rank',
                      maxLines: 1,
                      softWrap: false,
                      style: t.captionStrong.copyWith(
                        color: c.dim,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.label.copyWith(
                color: c.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: t.label.copyWith(
                    color: c.ink,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (trailingNote != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    trailingNote!,
                    style: t.caption.copyWith(
                      color: c.dim,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showBar) ...[
            const SizedBox(height: 5),
            Padding(
              padding: EdgeInsetsDirectional.only(start: rankW),
              child: ShareBar(
                value: share,
                color: color,
                delay: Duration(milliseconds: 60 * index),
              ),
            ),
          ],
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Padding(
              padding: EdgeInsetsDirectional.only(start: rankW),
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.caption.copyWith(color: c.dim),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Huni satırları: etiket · çubuk · sayı (çubuklar ilk satıra göre oranlanır, sırayla büyür).
class FunnelBars extends StatelessWidget {
  const FunnelBars({
    super.key,
    required this.rows,
    this.barHeight = 10,
    this.labelWidth = 58,
  });

  final List<FunnelRow> rows;
  final double barHeight;

  /// Etiket sütununun genişliği (yazı ölçeğiyle büyür).
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final max = rows.isEmpty
        ? 0
        : rows.map((r) => r.value).reduce((a, b) => a > b ? a : b);
    final labelW = MediaQuery.textScalerOf(context).scale(labelWidth);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 7),
          Semantics(
            label: '${rows[i].label}: ${StatsFmt.count(rows[i].value)}',
            excludeSemantics: true,
            child: Row(
              children: [
                SizedBox(
                  width: labelW,
                  child: Text(
                    rows[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.caption.copyWith(
                      color: c.dim,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: ShareBar(
                    value: max <= 0 ? 0 : rows[i].value / max,
                    color: rows[i].color,
                    height: barHeight,
                    delay: Duration(milliseconds: 90 * i),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 28),
                  child: Text(
                    StatsFmt.count(rows[i].value),
                    textAlign: TextAlign.end,
                    style: t.label.copyWith(
                      color: c.ink,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

@immutable
class FunnelRow {
  const FunnelRow(this.label, this.value, this.color);
  final String label;
  final num value;
  final Color color;
}
