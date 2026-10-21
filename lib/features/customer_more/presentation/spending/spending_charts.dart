import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/spending_controller.dart';
import '../../data/spending.dart';
import '../cm_widgets.dart';

/// Eksen üst sınırı: değeri kapsayan yuvarlak sayı (1, 2, 2,5, 5, 10 × 10^n; sunucu `NiceMax`).
double niceMax(double value) {
  if (value <= 0) return 1;
  final exp = (math.log(value) / math.ln10).floor();
  final pow = math.pow(10, exp).toDouble();
  for (final step in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (step * pow >= value) return step * pow;
  }
  return 10 * pow;
}

/// Kısa eksen sayısı: 1.250.000 → "1,25 Mn", 12.500 → "12,5 B".
String compactNumber(double v) {
  final a = v.abs();
  if (a >= 1e9) return '${Fmt.number(v / 1e9, maxFraction: 2)} Mr';
  if (a >= 1e6) return '${Fmt.number(v / 1e6, maxFraction: 2)} Mn';
  if (a >= 1e3) return '${Fmt.number(v / 1e3, maxFraction: 1)} B';
  return Fmt.number(v, maxFraction: 0);
}

/// Seçili ölçüde değer metni.
String metricText(
  SpendingMetric m, {
  required double amount,
  required double liters,
}) => m == SpendingMetric.amount ? Fmt.money(amount) : Fmt.liters(liters);

/// Aylık sütun grafiği (tasarım v2 §6.20): tek seri vurgu — seçili ay (yoksa son ay)
/// `chartHighlight`, diğerleri `chartContext`; sütunlar 16 geniş, üstte 4 yuvarlak, 1 px taban
/// çizgisinde düz; ızgara ve eksen yok. Seçili sütunun değeri üstünde yazar. Her sütun 48 dp dokunma
/// alanıdır; ekran okuyucu "Ekim 2026: 12.500 L" duyurur. Çok ayda yatay kaydırılır (son aylar
/// görünür). Altında seçili ayın ayrıntısı.
class MonthBarChart extends StatefulWidget {
  const MonthBarChart({
    super.key,
    required this.months,
    required this.metric,
    this.height = 160,
  });

  final List<SpendingMonth> months;
  final SpendingMetric metric;
  final double height;

  @override
  State<MonthBarChart> createState() => _MonthBarChartState();
}

class _MonthBarChartState extends State<MonthBarChart> {
  final _scroll = ScrollController();
  int? _selected;

  static const columnWidth = 48.0;
  static const barWidth = 16.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _toEnd());
  }

  @override
  void didUpdateWidget(MonthBarChart old) {
    super.didUpdateWidget(old);
    if (old.months.length != widget.months.length) {
      _selected = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _toEnd());
    }
  }

  void _toEnd() {
    if (mounted && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double _value(SpendingMonth m) =>
      widget.metric == SpendingMetric.amount ? m.amount : m.liters;

  String _text(SpendingMonth m) =>
      metricText(widget.metric, amount: m.amount, liters: m.liters);

  String _short(SpendingMonth m) {
    if (widget.metric == SpendingMetric.amount) {
      return Fmt.moneyCompact(m.amount);
    }
    final l = m.liters;
    if (l >= 1e6) return '${Fmt.number(l / 1e6, maxFraction: 1)} mn L';
    if (l >= 1e4) return '${Fmt.number(l / 1e3, maxFraction: 0)} bin L';
    return Fmt.liters(l);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final months = widget.months;
    final maxV = months.fold<double>(0, (a, m) => math.max(a, _value(m)));
    final plotH = widget.height;
    final duration = AknMotion.of(context, AknMotion.slow);
    final current = _selected != null && _selected! < months.length
        ? _selected!
        : months.length - 1;
    final selected = _selected == null || _selected! >= months.length
        ? null
        : months[_selected!];
    // Ay etiketleri en çok 1,3 kat büyür (değerler semantikte ve alttaki panelde tam boyutta).
    final chart = MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: SizedBox(
        // Değer etiketi 22 + çubuk + 7 + ay ve yıl satırları (yazı en çok 1,3×).
        height: plotH + 29 + 2 * (12 * 1.3 * 16 / 12) + 2,
        child: Stack(
          children: [
            // Taban çizgisi.
            Positioned(
              left: 0,
              right: 0,
              top: 22 + plotH,
              child: Container(height: 1, color: c.line),
            ),
            ListView.builder(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              itemCount: months.length,
              itemExtent: columnWidth,
              itemBuilder: (context, i) {
                final m = months[i];
                final v = _value(m);
                final isCur = i == current;
                final h = maxV <= 0 ? 0.0 : (v / maxV) * plotH;
                final showYear = i == 0 || m.month == 1;
                return Semantics(
                  button: true,
                  selected: _selected == i,
                  label: '${m.label}: ${_text(m)}',
                  excludeSemantics: true,
                  onTap: () => setState(() => _selected = i),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      AknHaptics.selection();
                      setState(() => _selected = _selected == i ? null : i);
                    },
                    child: Column(
                      children: [
                        SizedBox(
                          height: 22,
                          child: isCur && v > 0
                              ? OverflowBox(
                                  maxWidth: columnWidth * 2,
                                  child: Text(
                                    _short(m),
                                    maxLines: 1,
                                    textAlign: TextAlign.center,
                                    style: t.captionStrong.copyWith(
                                      color: c.ink,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        SizedBox(
                          height: plotH,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: h),
                              duration: duration,
                              curve: AknMotion.emphasizedCurve,
                              builder: (context, value, _) => Container(
                                width: barWidth,
                                height: v <= 0 ? 0 : math.max(3, value),
                                decoration: BoxDecoration(
                                  color: isCur
                                      ? c.chartHighlight
                                      : c.chartContext,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            m.abbrev,
                            style: t.caption.copyWith(
                              color: isCur ? c.ink : c.dim,
                              fontWeight: isCur ? FontWeight.w700 : null,
                            ),
                          ),
                        ),
                        if (showYear)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${m.year}',
                              style: t.caption.copyWith(color: c.dim),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        chart,
        AnimatedSize(
          duration: AknMotion.of(context, AknMotion.base),
          curve: AknMotion.emphasizedCurve,
          alignment: Alignment.topCenter,
          child: selected == null
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Ayrıntı için bir aya dokunun.',
                    style: t.bodySmall.copyWith(color: c.dim),
                  ),
                )
              : Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: AknRadius.card,
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          selected.label,
                          style: t.bodyStrong.copyWith(color: c.ink),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 16,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.end,
                          children: [
                            Text(
                              Fmt.money(selected.amount),
                              style: t.amount.copyWith(color: c.ink),
                            ),
                            Text(
                              Fmt.liters(selected.liters),
                              style: t.amount.copyWith(color: c.ink),
                            ),
                            Text(
                              'ortalama ${Fmt.unitPrice(selected.avgUnitPrice)}',
                              style: t.bodySmall.copyWith(color: c.dim),
                            ),
                            Text(
                              '${selected.orderCount} sipariş',
                              style: t.bodySmall.copyWith(color: c.dim),
                            ),
                          ],
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

/// Kırılım çubukları (tasarım v2 §6.20 "ranked bars"; en fazla 5 + "Diğer"): ad solda, değer ve pay
/// sağda, altında 8 px mürekkep çubuk (`chartTrack` üstünde; "Diğer" bağlam renginde) ve ortalama
/// ₺/L. Dokununca ayrıntı.
class BucketBars extends StatelessWidget {
  const BucketBars({
    super.key,
    required this.buckets,
    required this.metric,
    this.onTap,
  });

  final List<SpendingBucket> buckets;
  final SpendingMetric metric;
  final void Function(SpendingBucket b)? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final shown = topBuckets(buckets);
    double value(SpendingBucket b) =>
        metric == SpendingMetric.amount ? b.amount : b.liters;
    final maxV = shown.fold<double>(0, (a, b) => math.max(a, value(b)));
    final duration = AknMotion.of(context, AknMotion.slow);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++)
          () {
            final b = shown[i];
            final v = value(b);
            final f = maxV <= 0 ? 0.0 : (v / maxV).clamp(0.0, 1.0);
            final valueText = metricText(
              metric,
              amount: b.amount,
              liters: b.liters,
            );
            final share = '%${Fmt.number(b.amountShare, maxFraction: 1)}';
            final other = b.id < 0;
            final tappable = onTap != null && !other;
            return Semantics(
              button: tappable,
              label:
                  '${b.name}: $valueText, payı $share, ${b.orderCount} sipariş',
              excludeSemantics: true,
              onTap: tappable ? () => onTap!(b) : null,
              child: InkWell(
                onTap: tappable ? () => onTap!(b) : null,
                borderRadius: AknRadius.chip,
                highlightColor: c.surfaceAlt,
                splashFactory: NoSplash.splashFactory,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CmHeadRow(
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b.name,
                              style: t.bodyStrong.copyWith(color: c.ink),
                            ),
                            if (b.extra != null)
                              Text(
                                b.extra!,
                                style: t.bodySmall.copyWith(color: c.dim),
                              ),
                          ],
                        ),
                        trailing: Text.rich(
                          TextSpan(
                            text: valueText,
                            style: t.amount.copyWith(color: c.ink),
                            children: [
                              TextSpan(
                                text: '  $share',
                                style: t.bodySmall.copyWith(color: c.dim),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(4),
                        ),
                        child: SizedBox(
                          height: 8,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ColoredBox(color: c.chartTrack),
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: f, end: f),
                                duration: duration,
                                curve: AknMotion.emphasizedCurve,
                                builder: (context, w, _) =>
                                    FractionallySizedBox(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      widthFactor: w,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: other ? c.chartContext : c.ink,
                                          borderRadius:
                                              const BorderRadius.horizontal(
                                                right: Radius.circular(4),
                                              ),
                                        ),
                                      ),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${b.orderCount} sipariş, ortalama ${Fmt.unitPrice(b.avgUnitPrice)}',
                        style: t.bodySmall.copyWith(color: c.dim),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }(),
      ],
    );
  }
}
