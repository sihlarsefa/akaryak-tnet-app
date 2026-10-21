import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/models/models.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../copy.dart';
import '../../data/order_models.dart';
import 'order_parts.dart';

/// Teklif plakası (tasarım v2 §5.2, §7.8; pano ekran 5): ekranın tek turuncu levhası.
///
/// ```
/// [teklif] Demir Petrol teklifi                     bugün 10:05
/// 338.800,00 ₺
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/// Birim fiyat        Miktar         Teslim
/// 42,35 ₺/L          8.000 L        22 Ekim
/// ```
///
/// [stamp] her arttığında plaka "mühürlenir" (1,02 → 1, 160 ms; teklif onaylanınca). Hareket
/// azaltıldığında anında.
class QuotePlate extends StatelessWidget {
  const QuotePlate({
    super.key,
    required this.quote,
    required this.detail,
    required this.title,
    this.stamp = 0,
  });

  final Quote quote;
  final OrderDetail detail;

  /// "Demir Petrol teklifi", "Onaylanan teklif", "Revize istenen teklif" …
  final String title;
  final int stamp;

  @override
  Widget build(BuildContext context) {
    final q = quote;
    final (whole, decimals) = splitMoney(q.totalAmountTry);
    final delivery = q.deliveryDate ?? detail.requestedDeliveryDate;
    final moment = q.createdAt == null ? null : relativeMoment(q.createdAt);
    final period = [if (q.version > 1) 'v${q.version}', ?moment].join(', ');
    final plate = AknPlate(
      head: PlateHead(
        icon: Icons.request_quote_outlined,
        title: title,
        period: period.isEmpty ? null : period,
      ),
      figure: PlateFigure(
        value: whole,
        decimals: decimals,
        unit: '₺',
        semanticLabel: 'Teklif toplamı ${spokenMoney(q.totalAmountTry)}',
      ),
      below: PlateReadouts(
        items: [
          PlateReadout(
            label: 'Birim fiyat',
            value: Fmt.number(q.unitPriceTry, minFraction: 2, maxFraction: 4),
            unit: '₺/L',
            semanticLabel: 'Birim fiyat ${Fmt.unitPrice(q.unitPriceTry)}',
          ),
          PlateReadout(
            label: 'Miktar',
            value: Fmt.number(detail.quantityLiters, maxFraction: 3),
            unit: 'L',
            semanticLabel: 'Miktar ${Fmt.liters(detail.quantityLiters)}',
          ),
          PlateReadout(
            label: 'Teslim',
            value: dayMonthLong(delivery),
            semanticLabel: 'Teslim ${dayMonthWeekday(delivery)}',
          ),
        ],
      ),
    );
    return _Stamp(stamp: stamp, child: plate);
  }
}

/// Teklif gelmeden önceki tahmini tutar plakası (liste fiyatınızla; kesin tutar teklifte).
class EstimatePlate extends StatelessWidget {
  const EstimatePlate({super.key, required this.detail});

  final OrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final amount = d.estimatedAmount ?? 0;
    return AknPlate(
      head: const PlateHead(
        icon: Icons.calculate_outlined,
        title: 'Tahmini tutar',
      ),
      figure: PlateFigure(
        value: Fmt.number(amount.round()),
        unit: '₺',
        semanticLabel: 'Tahmini tutar ${Fmt.number(amount.round())} lira',
      ),
      delta: const PlateDelta(
        sentence: 'Kesin tutar bayinin teklifiyle belirlenir.',
      ),
      below: PlateReadouts(
        items: [
          PlateReadout(
            label: 'Miktar',
            value: Fmt.number(d.quantityLiters, maxFraction: 3),
            unit: 'L',
          ),
          PlateReadout(
            label: 'İstenen teslim',
            value: dayMonthLong(d.requestedDeliveryDate),
          ),
        ],
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.stamp, required this.child});

  final int stamp;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (stamp == 0) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(stamp),
      tween: Tween(begin: 1.02, end: 1),
      duration: AknMotion.of(context, AknMotion.stamp),
      curve: AknMotion.standard,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: child,
    );
  }
}

/// "Son alımlarınızla kıyas" (§7.8): son üç kabul edilen birim fiyat (bağlam noktaları), onların
/// ortalaması (mürekkep çentik), bu teklif (turuncu nokta) ve aradaki fark ("+0,87 ₺"); altında
/// cümle. İkiden az önceki alım varsa gösterilmez ([shows]).
class PriceComparison extends StatelessWidget {
  const PriceComparison({
    super.key,
    required this.comparison,
    required this.offer,
  });

  final QuotePriceComparison comparison;

  /// Bu teklifin birim fiyatı.
  final double offer;

  static bool shows(QuotePriceComparison? c) =>
      c != null && c.previous.length >= 2;

  List<double> get _prices => [
    for (final p in comparison.previous.take(3)) p.unitPriceTry,
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final prices = _prices;
    final avg = prices.reduce((a, b) => a + b) / prices.length;
    final diff = offer - avg;
    final n = prices.length == 2 ? 'iki' : 'üç';
    final same = diff.abs() < 0.005;
    final amount =
        '${Fmt.number(diff.abs(), minFraction: 2, maxFraction: 2)} ₺';
    final sentence = same
        ? 'Bu teklif, son $n alımınızın ortalamasıyla aynı.'
        : 'Bu teklif, son $n alımınızın ortalamasından litrede $amount '
              '${diff > 0 ? 'yüksek' : 'düşük'}.';
    final style = t.body.copyWith(color: c.ink);
    return Semantics(
      container: true,
      label: sentence,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Son alımlarınızla kıyas',
                  style: t.label.copyWith(
                    color: c.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text('litre başına', style: t.bodySmall.copyWith(color: c.dim)),
            ],
          ),
          const SizedBox(height: 6),
          _DotPlot(prices: prices, average: avg, offer: offer),
          const SizedBox(height: 8),
          if (same)
            Text(sentence, style: style)
          else
            Text.rich(
              TextSpan(
                text: 'Bu teklif, son $n alımınızın ortalamasından litrede ',
                children: [
                  TextSpan(
                    text: '$amount ${diff > 0 ? 'yüksek' : 'düşük'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
              style: style,
            ),
        ],
      ),
    );
  }
}

/// Nokta grafiği: iz çizgisi, bağlam noktaları, ortalama çentiği, teklif noktası, fark parçası ve
/// etiketler (fark üstte; "son 3 alım ort." ve "bu teklif" altta).
class _DotPlot extends StatelessWidget {
  const _DotPlot({
    required this.prices,
    required this.average,
    required this.offer,
  });

  final List<double> prices;
  final double average;
  final double offer;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final scaler = MediaQuery.textScalerOf(context);
    final small = t.caption.copyWith(color: c.dim);
    final strong = t.captionStrong.copyWith(color: c.ink);
    final diff = offer - average;
    final diffText =
        '${diff >= 0 ? '+' : '−'}${Fmt.number(diff.abs(), minFraction: 2, maxFraction: 2)} ₺';
    final avgText =
        'son ${prices.length} alım ort. ${Fmt.number(average, minFraction: 2, maxFraction: 2)}';
    final offerText =
        'bu teklif ${Fmt.number(offer, minFraction: 2, maxFraction: 2)}';
    double lineH(TextStyle s) => scaler.scale(s.fontSize!) * (s.height ?? 1.3);
    final topH = lineH(strong) + 6;
    final bottomH = lineH(small) + 8;
    const plotH = 20.0;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final all = [...prices, average, offer];
        var lo = all.reduce(math.min);
        var hi = all.reduce(math.max);
        if (hi - lo < 0.01) {
          lo -= 0.5;
          hi += 0.5;
        }
        final pad = (hi - lo) * 0.18;
        lo -= pad;
        hi += pad;
        double x(double v) => (v - lo) / (hi - lo) * w;
        final ax = x(average);
        final ox = x(offer);

        TextPainter measure(String s, TextStyle st) => TextPainter(
          text: TextSpan(text: s, style: st),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        double place(double center, double width) =>
            (center - width / 2).clamp(0.0, math.max(0.0, w - width));

        final avgP = measure(avgText, small);
        final offP = measure(offerText, strong);
        final diffP = measure(diffText, strong);
        // Alt etiketler çakışırsa ortalama etiketi sola / sağa itilir.
        var avgLeft = place(ax, avgP.width);
        final offLeft = place(ox, offP.width);
        if (ox >= ax && avgLeft + avgP.width + 8 > offLeft) {
          avgLeft = math.max(0, offLeft - 8 - avgP.width);
        } else if (ox < ax && offLeft + offP.width + 8 > avgLeft) {
          avgLeft = math.min(w - avgP.width, offLeft + offP.width + 8);
        }
        final overlap =
            (avgLeft < offLeft + offP.width && offLeft < avgLeft + avgP.width);
        final diffLeft = place((ax + ox) / 2, diffP.width);
        avgP.dispose();
        offP.dispose();
        diffP.dispose();
        return SizedBox(
          height: topH + plotH + bottomH * (overlap ? 2 : 1),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: diffLeft,
                top: 0,
                child: Text(diffText, style: strong, maxLines: 1),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: topH,
                height: plotH,
                child: CustomPaint(
                  painter: _DotPlotPainter(
                    xs: [for (final p in prices) x(p)],
                    avgX: ax,
                    offerX: ox,
                    track: c.chartTrack,
                    context: c.chartContext,
                    ink: c.ink,
                    highlight: c.chartHighlight,
                    ring: c.bg,
                  ),
                ),
              ),
              Positioned(
                left: avgLeft,
                top: topH + plotH + 4,
                child: Text(avgText, style: small, maxLines: 1),
              ),
              Positioned(
                left: offLeft,
                top: topH + plotH + 4 + (overlap ? bottomH : 0),
                child: Text(offerText, style: strong, maxLines: 1),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DotPlotPainter extends CustomPainter {
  const _DotPlotPainter({
    required this.xs,
    required this.avgX,
    required this.offerX,
    required this.track,
    required this.context,
    required this.ink,
    required this.highlight,
    required this.ring,
  });

  final List<double> xs;
  final double avgX;
  final double offerX;
  final Color track;
  final Color context;
  final Color ink;
  final Color highlight;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final line = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), line..color = track);
    canvas.drawLine(Offset(avgX, cy), Offset(offerX, cy), line..color = ink);
    final dot = Paint();
    for (final x in xs) {
      canvas.drawCircle(Offset(x, cy), 4, dot..color = context);
    }
    // Ortalama çentiği.
    canvas.drawLine(
      Offset(avgX, cy - 8),
      Offset(avgX, cy + 8),
      Paint()
        ..color = ink
        ..strokeWidth = 2,
    );
    canvas.drawCircle(Offset(offerX, cy), 8, dot..color = ring);
    canvas.drawCircle(Offset(offerX, cy), 6, dot..color = highlight);
  }

  @override
  bool shouldRepaint(_DotPlotPainter old) =>
      old.xs != xs ||
      old.avgX != avgX ||
      old.offerX != offerX ||
      old.track != track ||
      old.context != context ||
      old.ink != ink ||
      old.highlight != highlight;
}

/// "Teklif sürümleri" (birden çok sürüm varsa): yeni önce, ₺/L ve bir öncekine göre fark.
class QuoteVersions extends StatelessWidget {
  const QuoteVersions({super.key, required this.versions});

  /// Yeni önce.
  final List<Quote> versions;

  @override
  Widget build(BuildContext context) => AknLedger(
    children: [
      for (var i = 0; i < versions.length; i++)
        () {
          final v = versions[i];
          final older = i + 1 < versions.length ? versions[i + 1] : null;
          final delta = older == null
              ? null
              : v.unitPriceTry - older.unitPriceTry;
          final deltaText = delta == null || delta.abs() < 0.00005
              ? null
              : '${delta > 0 ? '+' : '−'}${Fmt.unitPrice(delta.abs())} önceki sürüme göre';
          return AknListTile(
            dense: true,
            title: 'Sürüm ${v.version}',
            subtitle: [
              if (v.createdAt != null) relativeMoment(v.createdAt),
              ?deltaText,
              if (v.revisionNote != null) 'Revize notunuz: ${v.revisionNote}',
            ].join('\n'),
            subtitleMaxLines: 4,
            amount: Fmt.unitPrice(v.unitPriceTry),
            amountMeta: Fmt.money(v.totalAmountTry),
          );
        }(),
    ],
  );
}

/// Revize isteği sayfası: web ön ayar çipleri + açıklama; "Revize iste" not döndürür.
/// Ret sayfası: neden çipleri + isteğe bağlı açıklama; kırmızı "Teklifi reddet".
Future<String?> showDecisionNoteSheet(
  BuildContext context, {
  required bool revise,
}) => showAppSheet<String>(
  context: context,
  title: revise ? 'Revize isteyin' : 'Teklifi reddedin',
  subtitle: revise ? OrdersCopy.reviseHint : OrdersCopy.rejectHint,
  builder: (ctx) => _DecisionNoteSheet(revise: revise),
);

class _DecisionNoteSheet extends StatefulWidget {
  const _DecisionNoteSheet({required this.revise});

  final bool revise;

  @override
  State<_DecisionNoteSheet> createState() => _DecisionNoteSheetState();
}

class _DecisionNoteSheetState extends State<_DecisionNoteSheet> {
  final _text = TextEditingController();
  final Set<String> _presets = {};
  bool _tried = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  List<String> get _options => widget.revise
      ? QuoteDecisionPresets.revisionReasons
      : QuoteDecisionPresets.rejectReasons;

  String get _note => [
    for (final o in _options)
      if (_presets.contains(o)) o,
    _text.text.trim(),
  ].where((s) => s.isNotEmpty).join('. ');

  void _submit() {
    final note = _note;
    if (widget.revise && note.isEmpty) {
      setState(() => _tried = true);
      return;
    }
    Navigator.of(context).pop(note);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final missing = widget.revise && _tried && _note.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Hazır nedenler', style: t.label.copyWith(color: c.ink)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final o in _options)
              AknChip(
                label: o,
                selected: _presets.contains(o),
                onTap: () => setState(() {
                  if (!_presets.remove(o)) _presets.add(o);
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        AknTextField(
          controller: _text,
          label: OrdersCopy.reasonLabel,
          hint: widget.revise
              ? 'Örneğin 41,90 ₺/L olursa onaylıyoruz'
              : 'İsteğe bağlı',
          maxLines: 4,
          minLines: 2,
          maxLength: 900,
          textCapitalization: TextCapitalization.sentences,
          errorText: missing
              ? 'Revize için bir neden seçin ya da yazın.'
              : null,
          onChanged: (_) {
            if (_tried) setState(() {});
          },
        ),
        const SizedBox(height: 16),
        if (widget.revise)
          AknButton(label: OrdersCopy.revise, expand: true, onPressed: _submit)
        else
          DestructiveButton(label: OrdersCopy.rejectQuote, onPressed: _submit),
      ],
    );
  }
}

/// Onay özeti: toplam, litre ve teslim; altında ürün, birim fiyat ve ödeme.
Future<bool> showApproveRecap(
  BuildContext context, {
  required Quote quote,
  required OrderDetail order,
  String? paymentLine,
}) {
  final t = context.aknText;
  final c = context.akn;
  final delivery = quote.deliveryDate ?? order.requestedDeliveryDate;
  final recap =
      '${Fmt.money(quote.totalAmountTry)}, ${Fmt.liters(order.quantityLiters)}, teslim ${dayMonthWeekday(delivery)}';
  return showConfirmSheet(
    context,
    title: 'Teklifi onaylıyor musunuz?',
    message: 'Onayladığınızda bayi sevkiyatı planlar.',
    confirmLabel: OrdersCopy.approve,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: recap,
          excludeSemantics: true,
          child: Text(recap, style: t.headline.copyWith(color: c.ink)),
        ),
        const SizedBox(height: 6),
        Text(
          '${order.productName}, ${Fmt.unitPrice(quote.unitPriceTry)}'
          '${paymentLine == null ? '' : '\n$paymentLine'}',
          style: t.bodySmall.copyWith(color: c.dim),
        ),
      ],
    ),
  );
}
