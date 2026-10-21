import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../copy.dart';
import '../../data/stats_models.dart';
import '../../data/stats_repository.dart';
import '../charts/bar_chart.dart';
import '../charts/line_chart.dart';
import '../charts/mix_chart.dart';
import '../stats_format.dart';
import '../widgets/stats_atoms.dart';
import '../widgets/stats_palette.dart';

/// Destedeki bir kart: kimlik (sıra korunur), ton, başlık ve içerik. Kabuk, başlık ve menü desteden gelir.
@immutable
class DeckCardSpec {
  const DeckCardSpec({
    required this.id,
    required this.tone,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.howTo,
    required this.body,
  });

  final String id;
  final AknTone tone;
  final IconData icon;
  final String title;
  final String subtitle;

  /// "Nasıl hesaplanır?" metni.
  final String howTo;

  /// Başlığın altındaki içerik (rakam, fark, grafik). Kalan yüksekliği doldurur.
  final Widget body;
}

/// Kart kimlikleri (sıra spec R1 §3.2).
abstract final class DeckCards {
  static const sales = 'sales';
  static const fuel = 'fuel';
  static const funnel = 'funnel';
  static const collections = 'collections';
  static const deliveries = 'deliveries';
  static const topCustomers = 'topCustomers';
  static const team = 'team';
  static const risk = 'risk';
  static const ownForms = 'ownForms';
  static const spend = 'spend';
  static const purchase = 'purchase';
  static const unitPrice = 'unitPrice';
  static const limits = 'limits';
  static const points = 'points';
  static const orderStatus = 'orderStatus';
}

/// Bayi destesi: Satış · Satılan yakıt · Sipariş hunisi · Tahsilat · Sevkiyat · En çok alan cariler ·
/// Saha ekibi · Limit riski (verisi gelmeyen kart gösterilmez). Saha temsilcisinde ([own]): Satış
/// (portföyüm) · Satılan yakıt · En çok alan carilerim · Saha formlarım.
List<DeckCardSpec> bayiDeckCards(
  BuildContext context,
  BayiStats s, {
  required bool own,
  String? userId,
  StatsFieldSummary? fieldSummary,
}) {
  final c = context.akn;
  final period = s.period.title;
  final compare = s.period.key.compareShort;
  final sales = s.sales;
  final out = <DeckCardSpec>[];

  if (sales != null) {
    out.add(
      DeckCardSpec(
        id: DeckCards.sales,
        tone: AknTone.brand,
        icon: Icons.payments_rounded,
        title: own ? StatsCopy.cardSalesOwn : StatsCopy.cardSales,
        subtitle: '$period · ${StatsCopy.ordersCount(sales.orders)}',
        howTo: own
            ? '${StatsCopy.howSales}\n\n${StatsCopy.howSalesOwn}'
            : StatsCopy.howSales,
        body: _AmountBody(
          amount: sales.amount,
          previous: sales.prevAmount,
          compare: compare,
          months: s.months,
          color: StatsHue.of(c, AknTone.brand).mark,
          noun: 'satış',
          emptyHint: StatsCopy.noSales,
        ),
      ),
    );
    out.add(
      DeckCardSpec(
        id: DeckCards.fuel,
        tone: AknTone.info,
        icon: Icons.local_gas_station_rounded,
        title: StatsCopy.cardFuel,
        subtitle: sales.activeCustomers == null
            ? period
            : '$period · ${sales.activeCustomers} aktif cari',
        howTo: StatsCopy.howFuel,
        body: _LitersBody(
          liters: sales.liters,
          previous: sales.prevLiters,
          compare: compare,
          products: s.products,
          months: s.months,
          color: StatsHue.of(c, AknTone.info).mark,
          noun: 'satılan yakıt',
        ),
      ),
    );
  }

  final funnel = s.funnel;
  if (!own && funnel != null) {
    out.add(
      DeckCardSpec(
        id: DeckCards.funnel,
        tone: AknTone.brand,
        icon: Icons.filter_alt_rounded,
        title: StatsCopy.cardFunnel,
        subtitle: '$period · talepten onaya',
        howTo: StatsCopy.howFunnel,
        body: _FunnelBody(funnel: funnel),
      ),
    );
  }

  final collections = s.collections;
  if (!own && collections != null) {
    out.add(
      DeckCardSpec(
        id: DeckCards.collections,
        tone: AknTone.ok,
        icon: Icons.account_balance_wallet_rounded,
        title: StatsCopy.cardCollections,
        subtitle:
            '$period · ${StatsCopy.paymentsCount(collections.collectedCount)}',
        howTo: StatsCopy.howCollections,
        body: _CollectionsBody(collections: collections),
      ),
    );
  }

  final deliveries = s.deliveries;
  if (!own && deliveries != null) {
    out.add(
      DeckCardSpec(
        id: DeckCards.deliveries,
        tone: AknTone.info,
        icon: Icons.local_shipping_rounded,
        title: StatsCopy.cardDeliveries,
        subtitle:
            '$period · ${StatsFmt.litersCompact(deliveries.deliveredLiters)} teslim',
        howTo: StatsCopy.howDeliveries,
        body: _DeliveriesBody(deliveries: deliveries),
      ),
    );
  }

  if (s.topCustomers.isNotEmpty) {
    final top = s.topCustomers.take(5).toList();
    final share = top.fold<double>(0, (a, x) => a + x.share);
    out.add(
      DeckCardSpec(
        id: DeckCards.topCustomers,
        tone: AknTone.brand,
        icon: Icons.workspace_premium_rounded,
        title: own ? StatsCopy.cardTopCustomersOwn : StatsCopy.cardTopCustomers,
        subtitle: share <= 0
            ? period
            : share >= 0.995
            ? '$period · ${top.length} cari'
            : '$period · ilk ${top.length} cari ${StatsFmt.rate(share)}',
        howTo: StatsCopy.howTopCustomers,
        body: _TopCustomersBody(rows: top),
      ),
    );
  }

  if (own) {
    StatsTeamMember? self;
    for (final m in s.team) {
      if (userId != null && m.userId == userId) self = m;
    }
    if (self == null && s.team.length == 1) self = s.team.first;
    if (self != null || (fieldSummary != null && fieldSummary.total > 0)) {
      out.add(
        DeckCardSpec(
          id: DeckCards.ownForms,
          tone: AknTone.ok,
          icon: Icons.assignment_turned_in_rounded,
          title: StatsCopy.cardOwnForms,
          subtitle: self != null ? period : 'Açık ve sonuçlanan formlar',
          howTo: StatsCopy.howOwnForms,
          body: _OwnFormsBody(self: self, summary: fieldSummary),
        ),
      );
    }
  } else if (s.team.isNotEmpty) {
    final forms = s.team.fold<int>(0, (a, m) => a + m.forms);
    final converted = s.team.fold<int>(0, (a, m) => a + m.converted);
    out.add(
      DeckCardSpec(
        id: DeckCards.team,
        tone: AknTone.ok,
        icon: Icons.groups_rounded,
        title: StatsCopy.cardTeam,
        subtitle: forms > 0
            ? '$period · ${StatsFmt.rate(converted / forms)} dönüşüm'
            : period,
        howTo: StatsCopy.howTeam,
        body: _TeamBody(team: s.team, forms: forms),
      ),
    );
  }

  final risk = s.risk;
  if (!own && risk != null && risk.nearLimitCount > 0) {
    out.add(
      DeckCardSpec(
        id: DeckCards.risk,
        tone: AknTone.danger,
        icon: Icons.speed_rounded,
        title: StatsCopy.cardRisk,
        subtitle: 'Limitinin %80 ve üzerini kullananlar',
        howTo: StatsCopy.howRisk,
        body: _RiskBody(risk: risk),
      ),
    );
  }
  return out;
}

/// Müşteri destesi: Bu ay harcama · Yakıt alımı · Ortalama birim fiyat · Limit durumu · Teslimat
/// noktaları · Sipariş durumu.
List<DeckCardSpec> customerDeckCards(BuildContext context, CustomerStats s) {
  final c = context.akn;
  final period = s.period.title;
  final compare = s.period.key.compareShort;
  final spend = s.spending;
  final out = <DeckCardSpec>[];
  if (spend != null) {
    out.add(
      DeckCardSpec(
        id: DeckCards.spend,
        tone: AknTone.brand,
        icon: Icons.payments_rounded,
        title: s.period.key == StatsPeriod.month
            ? StatsCopy.cardSpend
            : 'Harcama',
        subtitle: '$period · ${StatsCopy.ordersCount(spend.orders)}',
        howTo: StatsCopy.howSpend,
        body: _AmountBody(
          amount: spend.amount,
          previous: spend.prevAmount,
          compare: compare,
          months: s.months,
          color: StatsHue.of(c, AknTone.brand).mark,
          noun: 'harcama',
          emptyHint: StatsCopy.noSpend,
        ),
      ),
    );
    out.add(
      DeckCardSpec(
        id: DeckCards.purchase,
        tone: AknTone.info,
        icon: Icons.local_gas_station_rounded,
        title: StatsCopy.cardPurchase,
        subtitle: period,
        howTo: StatsCopy.howPurchase,
        body: _LitersBody(
          liters: spend.liters,
          previous: spend.prevLiters,
          compare: compare,
          products: s.products,
          months: s.months,
          color: StatsHue.of(c, AknTone.info).mark,
          noun: 'yakıt alımı',
        ),
      ),
    );
    final price = spend.unitPrice;
    if (price != null) {
      out.add(
        DeckCardSpec(
          id: DeckCards.unitPrice,
          tone: AknTone.ok,
          icon: Icons.sell_rounded,
          title: StatsCopy.cardUnitPrice,
          subtitle: '$period · litre başına',
          howTo: StatsCopy.howUnitPrice,
          body: _UnitPriceBody(
            price: price,
            previous: spend.prevUnitPrice,
            compare: compare,
            months: s.months,
            color: StatsHue.of(c, AknTone.ok).mark,
          ),
        ),
      );
    }
  }
  if (s.limits.isNotEmpty) {
    out.add(
      DeckCardSpec(
        id: DeckCards.limits,
        tone: AknTone.warn,
        icon: Icons.speed_rounded,
        title: StatsCopy.cardLimits,
        subtitle: s.limits.length == 1
            ? s.limits.first.stationTitle
            : '${s.limits.length} bayi',
        howTo: StatsCopy.howLimits,
        body: _LimitsBody(limits: s.limits),
      ),
    );
  }
  if (s.deliveryPoints.isNotEmpty) {
    out.add(
      DeckCardSpec(
        id: DeckCards.points,
        tone: AknTone.info,
        icon: Icons.place_rounded,
        title: StatsCopy.cardPoints,
        subtitle: '$period · litreye göre',
        howTo: StatsCopy.howPoints,
        body: _PointsBody(points: s.deliveryPoints),
      ),
    );
  }
  final orders = s.orders;
  if (orders != null) {
    out.add(
      DeckCardSpec(
        id: DeckCards.orderStatus,
        tone: AknTone.brand,
        icon: Icons.receipt_long_rounded,
        title: StatsCopy.cardOrderStatus,
        subtitle: 'Şu anki durum · teslimler: ${TurkishText.lower(period)}',
        howTo: StatsCopy.howOrderStatus,
        body: _OrderStatusBody(orders: orders),
      ),
    );
  }
  return out;
}

// ============================================================== içerikler

List<ChartBar> _bars(List<StatsMonth> months, double Function(StatsMonth) v) =>
    [
      for (final m in months)
        ChartBar(label: m.shortLabel, longLabel: m.longLabel, value: v(m)),
    ];

/// Tutar: büyük rakam + fark + aylık sütunlar (ay yoksa önceki dönemle iki satır).
class _AmountBody extends StatelessWidget {
  const _AmountBody({
    required this.amount,
    required this.previous,
    required this.compare,
    required this.months,
    required this.color,
    required this.noun,
    required this.emptyHint,
  });

  final double amount;
  final double previous;
  final String compare;
  final List<StatsMonth> months;
  final Color color;
  final String noun;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatsFigure(
          value: amount,
          format: (v) => StatsFmt.moneyCompactAt(v, amount),
          semanticsLabel: StatsFmt.moneySpoken(amount),
        ),
        const SizedBox(height: 4),
        DeltaChip(current: amount, previous: previous, compareLabel: compare),
        const SizedBox(height: 6),
        Expanded(
          child: months.isEmpty
              ? _CompareRows(
                  current: amount,
                  previous: previous,
                  format: StatsFmt.moneyCompact,
                  color: color,
                )
              : StatsBarChart(
                  bars: _bars(months, (m) => m.amount),
                  color: color,
                  valueLabel: StatsFmt.moneyCompact,
                  spoken: (b) =>
                      '${b.longLabel} $noun ${StatsFmt.moneySpoken(b.value)}',
                  emptyHint: emptyHint,
                ),
        ),
      ],
    );
  }
}

/// Litre: büyük rakam + fark + ürün dağılımı çubuğu ve ilk 3 ürün (ürün yoksa aylık sütunlar).
class _LitersBody extends StatelessWidget {
  const _LitersBody({
    required this.liters,
    required this.previous,
    required this.compare,
    required this.products,
    required this.months,
    required this.color,
    required this.noun,
  });

  final double liters;
  final double previous;
  final String compare;
  final List<StatsProduct> products;
  final List<StatsMonth> months;
  final Color color;
  final String noun;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final slices = productSlices(
      c,
      products,
      max: 3,
      otherLabel: StatsCopy.other,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatsFigure(
          value: liters,
          format: (v) => StatsFmt.litersCompactAt(v, liters),
          semanticsLabel: StatsFmt.litersSpoken(liters),
        ),
        const SizedBox(height: 4),
        DeltaChip(current: liters, previous: previous, compareLabel: compare),
        const SizedBox(height: 10),
        if (slices.isNotEmpty)
          // Dağılım kartın altına yaslanır (diğer kartların ayrıntıları gibi); sığmayan satır gösterilmez.
          Expanded(
            child: _FitColumn(
              alignment: Alignment.bottomCenter,
              rowExtent: (s) => s.scale(12) * 1.34 + 6,
              gap: 7,
              children: [
                MixBar(slices: slices),
                for (final sl in slices.take(3))
                  MixLegendRow(
                    slice: sl,
                    detail: StatsFmt.litersCompact(sl.liters),
                  ),
              ],
            ),
          )
        else
          Expanded(
            child: months.isEmpty
                ? Center(
                    child: Text(
                      StatsCopy.noProducts,
                      style: context.aknText.caption.copyWith(color: c.dim),
                    ),
                  )
                : StatsBarChart(
                    bars: _bars(months, (m) => m.liters),
                    color: color,
                    valueLabel: StatsFmt.litersCompact,
                    spoken: (b) =>
                        '${b.longLabel} $noun ${StatsFmt.litersSpoken(b.value)}',
                    emptyHint: StatsCopy.noProducts,
                  ),
          ),
      ],
    );
  }
}

/// Önceki dönemle iki satırlık karşılaştırma (aylık seri gelmediğinde).
class _CompareRows extends StatelessWidget {
  const _CompareRows({
    required this.current,
    required this.previous,
    required this.format,
    required this.color,
  });

  final double current;
  final double previous;
  final String Function(num) format;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final top = math.max(current, previous);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ShareRow(
          title: 'Bu dönem',
          value: format(current),
          share: top <= 0 ? 0 : current / top,
          color: color,
        ),
        const SizedBox(height: 8),
        ShareRow(
          title: 'Önceki dönem',
          value: format(previous),
          share: top <= 0 ? 0 : previous / top,
          color: color.withValues(alpha: 0.5),
          index: 1,
        ),
      ],
    );
  }
}

class _FunnelBody extends StatelessWidget {
  const _FunnelBody({required this.funnel});

  final StatsFunnel funnel;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final mark = StatsHue.of(c, AknTone.brand).mark;
    final conv = funnel.conversion;
    final minutes = funnel.avgFirstQuoteMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatsFigure(
          value: funnel.accepted,
          format: (v) =>
              '${StatsFmt.count(v)} / ${StatsFmt.count(funnel.requests)}',
          suffix: 'onaylandı',
          semanticsLabel:
              '${funnel.requests} talepten ${funnel.accepted} sipariş onaylandı',
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (conv != null)
              StatsTag(
                label: '${StatsFmt.rate(conv)} ${StatsCopy.conversion}',
                tone: AknTone.brand,
                icon: Icons.trending_up_rounded,
              ),
            if (minutes != null)
              Text(
                StatsCopy.firstQuote(StatsFmt.minutes(minutes)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.caption.copyWith(color: c.dim),
              ),
          ],
        ),
        const Spacer(),
        FunnelBars(
          rows: [
            FunnelRow(
              StatsCopy.funnelRequests,
              funnel.requests,
              mark.withValues(alpha: 0.5),
            ),
            FunnelRow(
              StatsCopy.funnelQuoted,
              funnel.quoted,
              mark.withValues(alpha: 0.75),
            ),
            FunnelRow(StatsCopy.funnelAccepted, funnel.accepted, mark),
          ],
        ),
      ],
    );
  }
}

/// Tonlu bilgi satırı: ikon · etiket · değer.
class _FactLine extends StatelessWidget {
  const _FactLine({
    required this.icon,
    required this.label,
    required this.value,
    this.tone = AknTone.neutral,
    this.note,
  });

  final IconData icon;
  final String label;
  final String value;
  final AknTone tone;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final tc = c.tone(tone);
    return Semantics(
      label: '$label: $value${note == null ? '' : ', $note'}',
      excludeSemantics: true,
      child: StatsLineRow(
        leading: Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: tc.bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: tc.fg),
          ),
        ),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.caption.copyWith(color: c.text, fontWeight: FontWeight.w600),
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
            if (note != null) ...[
              const SizedBox(width: 6),
              Text(
                note!,
                style: t.caption.copyWith(
                  color: c.dim,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CollectionsBody extends StatelessWidget {
  const _CollectionsBody({required this.collections});

  final StatsCollections collections;

  @override
  Widget build(BuildContext context) {
    final x = collections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatsFigure(
          value: x.collectedAmount,
          format: (v) => StatsFmt.moneyCompactAt(v, x.collectedAmount),
          suffix: StatsCopy.collected,
          semanticsLabel: StatsFmt.moneySpoken(x.collectedAmount),
        ),
        const SizedBox(height: 6),
        if (x.overdueCount > 0)
          StatsTag(
            label:
                'Gecikmiş ${StatsFmt.moneyCompact(x.overdueAmount)} · ${x.overdueCount}',
            tone: AknTone.danger,
            icon: Icons.error_outline_rounded,
          )
        else
          const StatsTag(
            label: StatsCopy.noOverdue,
            tone: AknTone.ok,
            icon: Icons.check_circle_outline_rounded,
          ),
        const Spacer(),
        _FactLine(
          icon: Icons.check_rounded,
          label: 'Tahsil edilen',
          value: StatsFmt.moneyCompact(x.collectedAmount),
          note: '${x.collectedCount}',
          tone: AknTone.ok,
        ),
        const SizedBox(height: 7),
        _FactLine(
          icon: Icons.error_outline_rounded,
          label: StatsCopy.overdue,
          value: StatsFmt.moneyCompact(x.overdueAmount),
          note: '${x.overdueCount}',
          tone: x.overdueCount > 0 ? AknTone.danger : AknTone.neutral,
        ),
        const SizedBox(height: 7),
        _FactLine(
          icon: Icons.schedule_rounded,
          label: StatsCopy.dueSoon(x.dueSoonDays),
          value: StatsFmt.moneyCompact(x.dueSoonAmount),
          note: '${x.dueSoonCount}',
          tone: x.dueSoonCount > 0 ? AknTone.warn : AknTone.neutral,
        ),
      ],
    );
  }
}

class _DeliveriesBody extends StatelessWidget {
  const _DeliveriesBody({required this.deliveries});

  final StatsDeliveries deliveries;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final d = deliveries;
    final rate = d.onTimeRate;
    final ringTone = rate == null
        ? AknTone.neutral
        : rate >= 0.9
        ? AknTone.ok
        : rate >= 0.75
        ? AknTone.warn
        : AknTone.danger;
    final ringSize = MediaQuery.textScalerOf(
      context,
    ).scale(80).clamp(80.0, 100.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatsFigure(
          value: d.delivered,
          format: StatsFmt.count,
          suffix: StatsCopy.delivered,
          semanticsLabel: '${d.delivered}',
        ),
        const Spacer(),
        Row(
          children: [
            ProgressRing(
              value: rate ?? 0,
              size: ringSize,
              strokeWidth: 8,
              color: rate == null ? c.line : c.tone(ringTone).fg,
              trackColor: c.lineSoft,
              animateFromZero: true,
              duration: AknMotion.emphasized,
              semanticLabel: 'Zamanında teslim',
              semanticValue: rate == null ? 'veri yok' : StatsFmt.rate(rate),
              // İçerik halkanın içine çizilen kareye sığar.
              child: Padding(
                padding: EdgeInsets.all(_ringInset(ringSize, 8)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        rate == null ? StatsFmt.dash : StatsFmt.rate(rate),
                        style: t.bodyStrong.copyWith(
                          fontWeight: FontWeight.w800,
                          color: c.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        StatsCopy.onTime,
                        style: t.caption.copyWith(fontSize: 10, color: c.dim),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FactLine(
                    icon: Icons.local_shipping_rounded,
                    label: StatsCopy.inTransit,
                    value: '${d.inTransit}',
                    tone: AknTone.brand,
                  ),
                  const SizedBox(height: 6),
                  _FactLine(
                    icon: Icons.event_rounded,
                    label: StatsCopy.planned,
                    value: '${d.planned}',
                    tone: AknTone.info,
                  ),
                  const SizedBox(height: 6),
                  _FactLine(
                    icon: Icons.report_problem_rounded,
                    label: StatsCopy.disputes,
                    value: '${d.disputes}',
                    tone: d.disputes > 0 ? AknTone.danger : AknTone.neutral,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TopCustomersBody extends StatelessWidget {
  const _TopCustomersBody({required this.rows});

  final List<StatsTopCustomer> rows;

  @override
  Widget build(BuildContext context) {
    final mark = StatsHue.of(context.akn, AknTone.brand).mark;
    final top = rows.fold<double>(0, (m, r) => math.max(m, r.share));
    return _FitColumn(
      rowExtent: (s) => s.scale(13) * 1.4 + 11,
      gap: 8,
      children: [
        for (var i = 0; i < rows.length; i++)
          ShareRow(
            rank: i + 1,
            title: rows[i].title,
            value: StatsFmt.moneyCompact(rows[i].amount),
            trailingNote: StatsFmt.rate(rows[i].share),
            // Çubuk ilk sıradakine göre (en büyük pay tam dolu).
            share: top <= 0 ? 0 : rows[i].share / top,
            color: mark,
            index: i,
            semanticsLabel:
                '${i + 1}. ${rows[i].title}, ${StatsFmt.moneySpoken(rows[i].amount)}, '
                'payı ${StatsFmt.rate(rows[i].share)}',
          ),
      ],
    );
  }
}

class _TeamBody extends StatelessWidget {
  const _TeamBody({required this.team, required this.forms});

  final List<StatsTeamMember> team;
  final int forms;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final sorted = [...team]
      ..sort((a, b) {
        final x = b.converted.compareTo(a.converted);
        return x != 0 ? x : b.forms.compareTo(a.forms);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatsFigure(
          value: forms,
          format: StatsFmt.count,
          suffix: 'saha formu',
          semanticsLabel: '$forms',
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _FitColumn(
            rowExtent: (s) =>
                math.max(32, s.scale(13) * 1.4 + s.scale(12) * 1.3),
            gap: 8,
            children: [
              for (final m in sorted)
                Semantics(
                  label:
                      '${m.name}: ${m.forms} form, ${m.converted} sipariş, '
                      '${StatsFmt.litersSpoken(m.liters)}',
                  excludeSemantics: true,
                  child: StatsLineRow(
                    trailingShare: 0.45,
                    leading: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 10),
                      child: AknAvatar(name: m.name, size: 30),
                    ),
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          m.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.label.copyWith(
                            color: c.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          StatsCopy.formsSummary(m.forms, m.converted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.caption.copyWith(color: c.dim),
                        ),
                      ],
                    ),
                    trailing: Text(
                      StatsFmt.litersCompact(m.liters),
                      style: t.label.copyWith(
                        color: c.ink,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Halka içeriğinin kenar boşluğu: içerik, halkanın iç çemberine çizilen kareye sığar.
double _ringInset(double size, double stroke) =>
    (size - (size - 2 * stroke) * 0.7071) / 2;

/// Kullanım oranının tonu: %100 ve üstü kırmızı, %80 ve üstü sarı, altı turuncu.
AknTone usageTone(double rate) => rate >= 1
    ? AknTone.danger
    : rate >= 0.8
    ? AknTone.warn
    : AknTone.brand;

Color usageColor(AknColors c, double rate) {
  final tone = usageTone(rate);
  return tone == AknTone.brand ? c.logo : c.tone(tone).fg;
}

class _RiskBody extends StatelessWidget {
  const _RiskBody({required this.risk});

  final StatsRisk risk;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final rows = [...risk.nearLimit]
      ..sort((a, b) => b.usageRate.compareTo(a.usageRate));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatsFigure(
          value: risk.nearLimitCount,
          format: StatsFmt.count,
          suffix: 'cari limitine yakın',
          semanticsLabel: '${risk.nearLimitCount}',
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _FitColumn(
            rowExtent: (s) => s.scale(13) * 1.4 + 11,
            gap: 8,
            children: [
              for (var i = 0; i < rows.length; i++)
                ShareRow(
                  title: rows[i].title,
                  value: StatsFmt.rate(rows[i].usageRate),
                  share: rows[i].usageRate,
                  color: usageColor(c, rows[i].usageRate),
                  index: i,
                  semanticsLabel:
                      '${rows[i].title}, limit kullanımı ${StatsFmt.rate(rows[i].usageRate)}',
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OwnFormsBody extends StatelessWidget {
  const _OwnFormsBody({required this.self, required this.summary});

  final StatsTeamMember? self;
  final StatsFieldSummary? summary;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final me = self;
    if (me != null) {
      final mark = StatsHue.of(c, AknTone.ok).mark;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatsFigure(
            value: me.forms,
            format: StatsFmt.count,
            suffix: StatsCopy.forms,
            semanticsLabel: '${me.forms}',
          ),
          const SizedBox(height: 6),
          if (me.conversion != null)
            StatsTag(
              label: '${StatsFmt.rate(me.conversion)} ${StatsCopy.converted}',
              tone: AknTone.ok,
              icon: Icons.trending_up_rounded,
            ),
          const Spacer(),
          FunnelBars(
            rows: [
              FunnelRow('Form', me.forms, mark.withValues(alpha: 0.55)),
              FunnelRow('Sipariş', me.converted, mark),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${StatsFmt.litersCompact(me.liters)} satışa dönüştü',
            style: t.caption.copyWith(color: c.dim),
          ),
        ],
      );
    }
    final s = summary ?? const StatsFieldSummary();
    final cells = [
      (StatsCopy.drafts, s.drafts, AknTone.neutral, Icons.edit_note_rounded),
      (
        StatsCopy.pendingApproval,
        s.pending,
        AknTone.warn,
        Icons.hourglass_top_rounded,
      ),
      (
        StatsCopy.rejectedForms,
        s.rejected,
        AknTone.danger,
        Icons.block_rounded,
      ),
      (
        StatsCopy.convertedForms,
        s.converted,
        AknTone.ok,
        Icons.task_alt_rounded,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatsFigure(
          value: s.drafts + s.pending,
          format: StatsFmt.count,
          suffix: 'açık form',
          semanticsLabel: '${s.drafts + s.pending}',
        ),
        const Spacer(),
        _StatGrid(cells: cells),
      ],
    );
  }
}

/// İki sütunlu küçük sayı ızgarası (etiket · sayı, tonlu ikon).
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.cells});

  final List<(String, int, AknTone, IconData)> cells;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        final w = (cons.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final (label, value, tone, icon) in cells)
              SizedBox(
                width: w,
                child: _FactLine(
                  icon: icon,
                  label: label,
                  value: '$value',
                  tone: value > 0 ? tone : AknTone.neutral,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _UnitPriceBody extends StatelessWidget {
  const _UnitPriceBody({
    required this.price,
    required this.previous,
    required this.compare,
    required this.months,
    required this.color,
  });

  final double price;
  final double? previous;
  final String compare;
  final List<StatsMonth> months;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatsFigure(
          value: price,
          format: StatsFmt.unitPrice,
          semanticsLabel:
              '${StatsFmt.unitPrice(price).replaceAll('₺/L', '')}lira litre',
        ),
        const SizedBox(height: 4),
        DeltaChip(
          current: price,
          previous: previous,
          compareLabel: compare,
          lowerIsBetter: true,
        ),
        const SizedBox(height: 6),
        Expanded(
          child: StatsLineChart(
            points: [
              for (final m in months)
                LinePoint(label: m.shortLabel, value: m.unitPrice),
            ],
            color: color,
            valueLabel: (v) => StatsFmt.unitPrice(v).replaceAll(' ₺/L', ''),
            semanticsLabel: [
              'Aylara göre ortalama birim fiyat',
              for (final m in months)
                if (m.unitPrice != null)
                  '${m.longLabel} ${StatsFmt.unitPrice(m.unitPrice)}',
            ].join(', '),
            emptyHint: StatsCopy.noPrice,
          ),
        ),
      ],
    );
  }
}

class _LimitsBody extends StatelessWidget {
  const _LimitsBody({required this.limits});

  final List<StatsLimit> limits;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final limited = limits.where((l) => !l.isUnlimited && !l.isLiters).toList();
    final available = limited.fold<double>(0, (a, l) => a + (l.available ?? 0));
    final rows = [...limits]
      ..sort((a, b) => (b.usageRate ?? -1).compareTo(a.usageRate ?? -1));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (limited.isNotEmpty)
          StatsFigure(
            value: available,
            format: (v) => StatsFmt.moneyCompactAt(v, available),
            suffix: StatsCopy.available,
            semanticsLabel: StatsFmt.moneySpoken(available),
          )
        else
          StatsFigure(
            value: rows.length,
            format: StatsFmt.count,
            suffix: 'bayide limitsiz',
            semanticsLabel: '${rows.length}',
          ),
        const SizedBox(height: 10),
        Expanded(
          child: _FitColumn(
            rowExtent: (s) => s.scale(13) * 1.4 + s.scale(12) * 1.3 + 14,
            gap: 8,
            children: [
              for (var i = 0; i < rows.length; i++) _limitRow(c, rows[i], i),
            ],
          ),
        ),
      ],
    );
  }

  Widget _limitRow(AknColors c, StatsLimit l, int i) {
    String fmt(num? v) =>
        l.isLiters ? StatsFmt.litersCompact(v) : StatsFmt.moneyCompact(v);
    if (l.isUnlimited) {
      return ShareRow(
        title: l.stationTitle,
        value: StatsCopy.unlimited,
        share: 0,
        color: c.line,
        index: i,
        showBar: false,
      );
    }
    final rate = l.usageRate ?? 0;
    return ShareRow(
      title: l.stationTitle,
      value: StatsFmt.rate(rate),
      share: rate,
      color: usageColor(c, rate),
      index: i,
      subtitle: 'Kullanılabilir ${fmt(l.available)} · limit ${fmt(l.limit)}',
      semanticsLabel:
          '${l.stationTitle}, limit kullanımı ${StatsFmt.rate(rate)}, '
          'kullanılabilir ${fmt(l.available)}',
    );
  }
}

class _PointsBody extends StatelessWidget {
  const _PointsBody({required this.points});

  final List<StatsDeliveryPoint> points;

  @override
  Widget build(BuildContext context) {
    final mark = StatsHue.of(context.akn, AknTone.info).mark;
    final rows = [...points]..sort((a, b) => b.liters.compareTo(a.liters));
    final top = rows.isEmpty ? 0.0 : rows.first.liters;
    final total = rows.fold<double>(0, (a, p) => a + p.liters);
    return _FitColumn(
      rowExtent: (s) => s.scale(13) * 1.4 + s.scale(12) * 1.3 + 14,
      gap: 8,
      children: [
        for (var i = 0; i < rows.length; i++)
          ShareRow(
            title: rows[i].name,
            subtitle: rows[i].city,
            value: StatsFmt.litersCompact(rows[i].liters),
            trailingNote: total <= 0
                ? null
                : StatsFmt.rate(rows[i].liters / total),
            share: top <= 0 ? 0 : rows[i].liters / top,
            color: mark,
            index: i,
          ),
      ],
    );
  }
}

class _OrderStatusBody extends StatelessWidget {
  const _OrderStatusBody({required this.orders});

  final StatsOrderStatus orders;

  @override
  Widget build(BuildContext context) {
    final o = orders;
    final cells = [
      (
        StatsCopy.awaitingQuote,
        o.awaitingQuote,
        AknTone.info,
        Icons.hourglass_empty_rounded,
      ),
      (
        StatsCopy.awaitingDecision,
        o.awaitingDecision,
        AknTone.warn,
        Icons.gavel_rounded,
      ),
      (
        StatsCopy.awaitingCompanyApproval,
        o.awaitingCompanyApproval,
        AknTone.info,
        Icons.how_to_reg_rounded,
      ),
      (
        StatsCopy.inTransit,
        o.inTransit,
        AknTone.brand,
        Icons.local_shipping_rounded,
      ),
      (
        StatsCopy.deliveredStatus,
        o.delivered,
        AknTone.ok,
        Icons.task_alt_rounded,
      ),
      (
        StatsCopy.disputedStatus,
        o.disputed,
        AknTone.danger,
        Icons.report_problem_rounded,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatsFigure(
          value: o.open,
          format: StatsFmt.count,
          suffix: StatsCopy.openOrders,
          semanticsLabel: '${o.open}',
        ),
        const Spacer(),
        _StatGrid(cells: cells),
      ],
    );
  }
}

/// Satırları sığdığı kadar gösterir (taşma yok): yükseklik [rowExtent] tahminiyle bölünür.
class _FitColumn extends StatelessWidget {
  const _FitColumn({
    required this.children,
    required this.rowExtent,
    this.gap = 6,
    this.alignment = Alignment.topCenter,
  });

  final List<Widget> children;
  final double Function(TextScaler scaler) rowExtent;
  final double gap;

  /// Satırlar üste (liste) ya da alta (kartın altına yaslanan ayrıntı) dizilir.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final extent = rowExtent(scaler);
    return LayoutBuilder(
      builder: (context, cons) {
        final fit = cons.maxHeight.isFinite
            ? ((cons.maxHeight + gap) / (extent + gap)).floor()
            : children.length;
        final n = math.max(1, math.min(children.length, fit));
        return ClipRect(
          child: OverflowBox(
            alignment: alignment,
            minHeight: 0,
            maxHeight: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < n; i++) ...[
                  if (i > 0) SizedBox(height: gap),
                  children[i],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
