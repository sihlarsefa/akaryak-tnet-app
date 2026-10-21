import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// Sıralı çubuk satırı (beyaz sayfa, tasarım v2 §6.20): ad solda, değer ve pay sağda, altında 8 px
/// çubuk. Tek seri: mürekkep dolgu `chartTrack` izinde. İki seride ([track] < 1) iz `chartTrack`,
/// ilk seri `chartContext`, sonuç mürekkep. Kategori rengi yok; ürüne renk atanmaz.
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

  /// Dolgu rengi (varsayılan mürekkep; limit satırında ton rengi).
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
/// Dokunulabilir satır tam genişlikte basılı görünür (48 dp en az).
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in items) _RankedRow(item: item, threshold: threshold),
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
                          width: 12,
                          height: 8,
                          decoration: BoxDecoration(
                            color: l.filled ? c.ink : c.chartContext,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            l.label,
                            style: t.label.copyWith(color: c.dim),
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
  const _RankedRow({required this.item, this.threshold});

  final RankedItem item;
  final double? threshold;

  @override
  State<_RankedRow> createState() => _RankedRowState();
}

class _RankedRowState extends State<_RankedRow> {
  bool _pressed = false;

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
      fontWeight: FontWeight.w600,
      color: c.ink,
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
                fontWeight: FontWeight.w400,
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
    final bar = SizedBox(
      height: 8,
      child: CustomPaint(
        painter: _BarPainter(
          fraction: item.fraction.isNaN ? 0 : item.fraction.clamp(0.0, 1.0),
          track: item.track.clamp(0.0, 1.0),
          fill: item.color ?? c.ink,
          trackColor: c.chartTrack,
          first: c.chartContext,
          threshold: widget.threshold,
          tick: c.ink,
        ),
      ),
    );
    Widget row = Padding(
      padding: const EdgeInsets.fromLTRB(20, 7, 20, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          head,
          const SizedBox(height: 6),
          bar,
          if (item.status != null) ...[const SizedBox(height: 6), item.status!],
        ],
      ),
    );
    row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AknSpace.minTap),
      child: row,
    );
    final spoken =
        item.semanticLabel ?? [item.label, item.value, ?note].join(', ');
    final tap = item.onTap;
    if (tap == null) {
      return Semantics(label: spoken, excludeSemantics: true, child: row);
    }
    return Semantics(
      label: spoken,
      button: true,
      excludeSemantics: true,
      onTap: tap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () {
          AknHaptics.selection();
          tap();
        },
        child: AnimatedContainer(
          duration: AknMotion.of(
            context,
            _pressed ? AknMotion.press : AknMotion.pressOut,
          ),
          color: _pressed ? c.surfaceAlt : c.surfaceAlt.withValues(alpha: 0),
          child: row,
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter({
    required this.fraction,
    required this.track,
    required this.fill,
    required this.trackColor,
    required this.first,
    required this.threshold,
    required this.tick,
  });

  final double fraction;
  final double track;
  final Color fill;
  final Color trackColor;
  final Color first;
  final double? threshold;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    RRect bar(double w) => RRect.fromRectAndCorners(
      Rect.fromLTWH(0, 0, w, h),
      topRight: Radius.circular(h / 2),
      bottomRight: Radius.circular(h / 2),
    );
    canvas.drawRRect(bar(size.width), Paint()..color = trackColor);
    if (track < 1 && track > 0) {
      canvas.drawRRect(bar(size.width * track), Paint()..color = first);
    }
    if (fraction > 0) {
      canvas.drawRRect(
        bar(size.width * fraction < h / 2 ? h / 2 : size.width * fraction),
        Paint()..color = fill,
      );
    }
    final th = threshold;
    if (th != null) {
      final x = (size.width * th).clamp(1.0, size.width - 1);
      canvas.drawRect(
        Rect.fromLTRB(x - 1, -4, x + 1, h + 4),
        Paint()..color = tick,
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.fraction != fraction ||
      old.track != track ||
      old.fill != fill ||
      old.trackColor != trackColor ||
      old.first != first ||
      old.threshold != threshold ||
      old.tick != tick;
}
