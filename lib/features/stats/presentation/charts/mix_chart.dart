import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../widgets/stats_atoms.dart';

/// Sıralı çubuk satırı (tasarım v3 §4–5, kartın içinde): ad solda, değer (tabular) ve pay sağda,
/// altında 10 px tam yuvarlak çubuk. Tek seri, vurgu biçimi: ilk sıradaki satır turuncu degrade ve
/// yumuşak ışıma, diğerleri `chartContext`; iz `chartTrack`. İki seride ([track] < 1) iz
/// `chartTrack`, ilk seri `chartContext`, sonuç mürekkep. [color] verilirse (limit kullanımı) o
/// tonun degradesi. Kategori rengi yok; ürüne renk atanmaz.
@immutable
class RankedItem {
  const RankedItem({
    required this.label,
    required this.value,
    required this.fraction,
    this.note,
    this.track = 1,
    this.color,
    this.onTap,
    this.semanticLabel,
    this.status,
  });

  final String label;

  /// "154.800 L", "1.524.380 ₺".
  final String value;

  /// Değerin yanında soluk not ("%78").
  final String? note;

  /// Dolu kısım (0–1, tam genişliğe göre).
  final double fraction;

  /// İki seri: ilk serinin boyu (0–1); 1 = tek seri.
  final double track;

  /// Dolgu rengi (varsayılan vurgu biçimi; limit satırında ton rengi).
  final Color? color;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Çubuğun altında isteğe bağlı durum satırı (lamba).
  final Widget? status;
}

/// Lejant maddesi (yalnızca iki seride).
@immutable
class RankedLegend {
  const RankedLegend(this.label, {this.filled = true});

  final String label;
  final bool filled;
}

/// Sıralı çubuklar listesi (ürün dağılımı, en çok alan cariler, saha ekibi, bayiler, noktalar).
/// Çubuklar ilk görünüşte satır satır büyür. Dokunulabilir satır basılınca yumuşak kuyuya döner ve
/// hafifçe küçülür (48 dp en az).
class StatsRankedList extends StatelessWidget {
  const StatsRankedList({
    super.key,
    required this.items,
    this.legend = const [],
    this.threshold,
  });

  final List<RankedItem> items;
  final List<RankedLegend> legend;

  /// İnce eşik çizgisi (0–1; limit satırlarında %80).
  final double? threshold;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final twoSeries = items.any((i) => i.track < 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++)
          _RankedRow(
            item: items[i],
            index: i,
            lead: i == 0 && !twoSeries && items.length > 1,
            twoSeries: twoSeries,
            threshold: threshold,
          ),
        if (legend.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: ExcludeSemantics(
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  for (final l in legend)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 14,
                          height: 8,
                          decoration: BoxDecoration(
                            color: l.filled ? c.ink : c.chartContext,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            l.label,
                            style: t.caption.copyWith(color: c.dim),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RankedRow extends StatefulWidget {
  const _RankedRow({
    required this.item,
    required this.index,
    required this.lead,
    required this.twoSeries,
    this.threshold,
  });

  final RankedItem item;
  final int index;

  /// Tek seride ilk sıradaki satır (turuncu vurgu).
  final bool lead;

  /// Listenin iki serili olduğu (form + siparişe dönüşen).
  final bool twoSeries;
  final double? threshold;

  @override
  State<_RankedRow> createState() => _RankedRowState();
}

class _RankedRowState extends State<_RankedRow> {
  bool _pressed = false;

  void _press(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final item = widget.item;
    final labelStyle = t.body.copyWith(
      height: 20 / 15,
      fontWeight: FontWeight.w500,
      color: c.ink,
    );
    final valueStyle = t.body.copyWith(
      height: 20 / 15,
      fontWeight: FontWeight.w700,
      color: c.ink,
      fontFeatures: AknNumerals.tabular,
    );
    final note = item.note;
    final value = Text.rich(
      TextSpan(
        text: item.value,
        style: valueStyle,
        children: [
          if (note != null && note.isNotEmpty)
            TextSpan(
              text: ' $note',
              style: valueStyle.copyWith(
                fontWeight: FontWeight.w500,
                color: c.dim,
              ),
            ),
        ],
      ),
      maxLines: 1,
      softWrap: false,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final large = scaler.scale(10) >= 13;
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

    final head = LayoutBuilder(
      builder: (context, cons) {
        // Dar ekranda, büyük yazıda ya da ad ile değer yan yana sığmadığında değer adın altına
        // iner (QA BO-01 / SC-02: geniş değer + not satırı taşırıyordu).
        final valueW = measure(value.textSpan!);
        final labelMin = math.min(
          measure(TextSpan(text: item.label, style: labelStyle)),
          cons.maxWidth * 0.45,
        );
        if (large ||
            cons.maxWidth < 300 ||
            labelMin + 12 + valueW > cons.maxWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.label, style: labelStyle),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: value,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                item.label,
                style: labelStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            // Ölçüldü ve sığıyor; yuvarlama payına karşı yine de satırdan geniş olamaz.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.max(0, cons.maxWidth - 12 - labelMin),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: value,
              ),
            ),
          ],
        );
      },
    );
    final custom = item.color;
    final (leadStart, leadEnd) = statsAccentRamp(c);
    final twoSeries = widget.twoSeries;
    final Color fill;
    final Color fillStart;
    if (custom != null) {
      fill = custom;
      fillStart = Color.lerp(custom, c.surface, 0.25)!;
    } else if (twoSeries) {
      fill = c.ink;
      fillStart = c.ink;
    } else if (widget.lead) {
      fill = leadEnd;
      fillStart = leadStart;
    } else {
      fill = c.chartContext;
      fillStart = c.chartContext;
    }
    final bar = StatsGrowBar(
      height: 10,
      fraction: item.fraction.isNaN ? 0 : item.fraction.clamp(0.0, 1.0),
      track: item.track.clamp(0.0, 1.0),
      trackColor: c.chartTrack,
      trackFill: twoSeries ? c.chartContext : null,
      fill: fill,
      fillStart: fillStart,
      glow: widget.lead && custom == null,
      threshold: widget.threshold,
      tick: c.ink,
      delay: Duration(
        milliseconds:
            120 + 70 * math.min(widget.index, AknMotion.staggerMaxItems),
      ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        head,
        const SizedBox(height: 8),
        bar,
        if (item.status != null) ...[const SizedBox(height: 8), item.status!],
      ],
    );
    final spoken =
        item.semanticLabel ?? [item.label, item.value, ?note].join(', ');
    final tap = item.onTap;
    if (tap == null) {
      return Semantics(
        label: spoken,
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AknSpace.minTap),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: content,
          ),
        ),
      );
    }
    // Dokunulabilir satır: basılınca kartın kenarından 6 px içeride yumuşak kuyu ve hafif küçülme
    // (kaydırma dokunuşu devralınca bırakılır).
    final reduced = AknMotion.reduced(context);
    final motion = _pressed ? AknMotion.press : AknMotion.pressOut;
    return Semantics(
      label: spoken,
      button: true,
      excludeSemantics: true,
      onTap: tap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapCancel: () => _press(false),
        onTapUp: (_) => _press(false),
        onTap: () {
          AknHaptics.selection();
          tap();
        },
        child: AnimatedScale(
          scale: _pressed && !reduced ? 0.98 : 1,
          duration: motion,
          curve: _pressed ? AknMotion.standard : AknMotion.spring,
          child: AnimatedContainer(
            duration: AknMotion.of(context, motion),
            curve: AknMotion.standard,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            constraints: const BoxConstraints(minHeight: AknSpace.minTap),
            decoration: BoxDecoration(
              color: _pressed
                  ? c.surfaceAlt
                  : c.surfaceAlt.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(16),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
