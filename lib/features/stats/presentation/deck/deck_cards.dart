import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/tr_time.dart';
import '../../copy.dart';
import '../../data/stats_models.dart';
import '../../data/stats_repository.dart';
import '../stats_format.dart';
import '../widgets/stats_atoms.dart';

/// Destedeki bir kart: kimlik (sıra korunur), başlık, dönem ve içerik. Kabuk, başlık satırı ve ⋯ menüsü
/// desteden gelir (tasarım v3 §4 hero kartı); içerik plakanın atomlarıyla çizilir ve renklerini
/// bağlamdan okur: üstteki kartta plaka paleti, arkadaki kâğıtlarda sayfa renkleri. Kart öne gelince
/// içerik yeniden kurulur: rakam döner, çubuklar yükselir, okumalar ve satırlar yerine oturur.
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
    this.summary,
    this.compactLine,
  });

  final String id;

  /// Deprecated: kartlar artık tonla renklenmez (API uyumu için duruyor).
  final AknTone tone;
  final IconData icon;

  /// `StatsCopy` sabiti ("Satış", "Bu ay harcama").
  final String title;

  /// Yalnızca dönem ("1–21 Ekim", "şu an"); sayılar okumalara taşındı.
  final String subtitle;

  /// "Nasıl hesaplanır?" metni.
  final String howTo;

  /// Başlığın altındaki içerik (rakam, fark, grafik, okumalar). Kalan yüksekliği doldurur.
  final Widget body;

  /// Ekran okuyucu özeti ("8.426.350 lira, yüzde 9,4 artış").
  final String? summary;

  /// Büyük yazı düzenindeki satır (deste, kart yüksekliğini bununla ölçer).
  final DeckLineSpec? compactLine;

  /// [subtitle] ile aynı.
  String get period => subtitle;
}

/// Büyük yazı düzeninde rakamın altındaki satırın metni: isteğe bağlı fark çipi ve cümle ya da "!" ile
/// başlayan sorun satırı. Deste kart yüksekliğini bununla ölçer (içerik kendisi kartın gövdesindedir).
@immutable
class DeckLineSpec {
  const DeckLineSpec(this.text, {this.chip, this.bang = false});

  final String text;
  final String? chip;
  final bool bang;
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

/// Desteden karta: büyük yazı düzeni, oturumun sayaç dönüşü ve fark çipinin (plaka ↔ kâğıt geçişinde)
/// renkleri. Destenin dışında (ör. testte tek kart) varsayılanlar: tam düzen, dönüş yok, plaka çipi.
class DeckCardScope extends InheritedWidget {
  const DeckCardScope({
    super.key,
    required super.child,
    this.compact = false,
    this.roll = false,
    this.onRollStart,
    this.chipFill,
    this.chipInk,
    this.chipLine,
  });

  /// 1,6× ve üstü yazı: başlık, rakam, çip ve cümle; çubuk ve okuma yok.
  final bool compact;

  /// Bu kart oturumun ilk gösteriminde plakayı yakıp rakamı döndürür (yalnızca üstteki ilk kart).
  final bool roll;

  /// Dönüş başlarken (ya da hareket azaltmada son kare çizilirken).
  final VoidCallback? onRollStart;

  /// Fark çipinin zemini, yazısı ve çerçevesi. v4 tur 2 (A11): çip sakindir — zemin yok, mürekkep
  /// ▲/▼ ve değer, ince çerçeve (plakada `plateLine`, kâğıtta `line`). Turuncu yalnızca eylem ve "sıra
  /// sizde" içindir (P5); sağlıklı bir istatistik turuncu olmaz.
  final Color? chipFill;
  final Color? chipInk;
  final Color? chipLine;

  static DeckCardScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeckCardScope>();

  @override
  bool updateShouldNotify(DeckCardScope old) =>
      compact != old.compact ||
      roll != old.roll ||
      onRollStart != old.onRollStart ||
      chipFill != old.chipFill ||
      chipInk != old.chipInk ||
      chipLine != old.chipLine;
}

/// Bayi destesi: Satış, Satılan yakıt, Sipariş hunisi, Tahsilat, Sevkiyat, En çok alan cariler, Saha
/// ekibi, Limit riski (verisi gelmeyen kart gösterilmez). Saha temsilcisinde ([own]): Portföyümde satış,
/// Satılan yakıt, En çok alan carilerim, Saha formlarım.
List<DeckCardSpec> bayiDeckCards(
  BuildContext context,
  BayiStats s, {
  required bool own,
  String? userId,
  StatsFieldSummary? fieldSummary,
}) {
  final period = _periodText(s.period);
  final compare = s.period.key.compareShort;
  // Fark çipli kartların başlığı karşılaştırmayı da söyler ("1–29 Ekim · geçen aya göre", /stats ile
  // aynı söz); rakamın altında ayrı cümle satırı yok, içerik küçülmeden sığar (v4 tur 2).
  final compared = _comparedPeriod(period, s.period.key);
  final sales = s.sales;
  final out = <DeckCardSpec>[];

  if (sales != null) {
    out.add(
      DeckCardSpec(
        id: DeckCards.sales,
        tone: AknTone.brand,
        icon: PhosphorIconsRegular.chartBar,
        title: own ? StatsCopy.cardSalesOwn : StatsCopy.cardSales,
        subtitle: compared,
        howTo: own
            ? '${StatsCopy.howSales}\n\n${StatsCopy.howSalesOwn}'
            : StatsCopy.howSales,
        summary: _moneySummary(sales.amount, sales.prevAmount),
        body: _AmountBody(
          amount: sales.amount,
          previous: sales.prevAmount,
          compare: compare,
          months: s.months,
          period: s.period,
          liters: sales.liters,
          litersLabel: StatsCopy.kpiLiters,
          unitPrice: sales.unitPrice,
          orders: sales.orders,
        ),
      ),
    );
    out.add(
      DeckCardSpec(
        id: DeckCards.fuel,
        tone: AknTone.info,
        icon: PhosphorIconsRegular.gasPump,
        title: StatsCopy.cardFuel,
        subtitle: compared,
        howTo: StatsCopy.howFuel,
        summary: _litersSummary(sales.liters, sales.prevLiters),
        body: _LitersBody(
          liters: sales.liters,
          previous: sales.prevLiters,
          compare: compare,
          products: s.products,
          months: s.months,
        ),
      ),
    );
  }

  final funnel = s.funnel;
  if (!own && funnel != null) {
    final conv = funnel.conversion;
    out.add(
      DeckCardSpec(
        id: DeckCards.funnel,
        tone: AknTone.brand,
        icon: PhosphorIconsRegular.funnel,
        title: StatsCopy.cardFunnel,
        subtitle: period,
        howTo: StatsCopy.howFunnel,
        summary: conv == null
            ? StatsCopy.funnelSentence(funnel.requests, funnel.accepted)
            : '${_spokenRate(conv)} ${StatsCopy.conversion}, '
                  '${StatsCopy.funnelSentence(funnel.requests, funnel.accepted)}',
        compactLine: DeckLineSpec(
          StatsCopy.funnelSentence(funnel.requests, funnel.accepted),
        ),
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
        icon: PhosphorIconsRegular.wallet,
        title: StatsCopy.cardCollections,
        subtitle: period,
        howTo: StatsCopy.howCollections,
        summary:
            '${StatsFmt.moneyWholeSpoken(collections.collectedAmount)}, '
            '${StatsCopy.collectedSentence(collections.collectedCount)}'
            '${collections.overdueCount > 0 ? ', ${StatsCopy.overdueLine(collections.overdueCount)}' : ''}',
        compactLine: collections.overdueCount > 0
            ? DeckLineSpec(
                StatsCopy.overdueLine(collections.overdueCount),
                bang: true,
              )
            : DeckLineSpec(
                StatsCopy.collectedSentence(collections.collectedCount),
              ),
        body: _CollectionsBody(collections: collections),
      ),
    );
  }

  final deliveries = s.deliveries;
  if (!own && deliveries != null) {
    final rate = deliveries.onTimeRate;
    out.add(
      DeckCardSpec(
        id: DeckCards.deliveries,
        tone: AknTone.info,
        icon: PhosphorIconsRegular.truck,
        title: StatsCopy.cardDeliveries,
        subtitle: period,
        howTo: StatsCopy.howDeliveries,
        summary:
            '${StatsCopy.deliveriesCount(deliveries.delivered)}'
            '${rate == null ? '' : ', ${_spokenRate(rate)} ${StatsCopy.onTime}'}',
        compactLine: rate == null
            ? null
            : DeckLineSpec(StatsCopy.onTimeSentence(StatsFmt.rate(rate))),
        body: _DeliveriesBody(deliveries: deliveries),
      ),
    );
  }

  if (s.topCustomers.isNotEmpty) {
    final top = s.topCustomers.take(5).toList();
    out.add(
      DeckCardSpec(
        id: DeckCards.topCustomers,
        tone: AknTone.brand,
        icon: PhosphorIconsRegular.usersThree,
        title: own ? StatsCopy.cardTopCustomersOwn : StatsCopy.cardTopCustomers,
        subtitle: period,
        howTo: StatsCopy.howTopCustomers,
        summary: [
          for (final r in top.take(3))
            '${r.title} ${StatsFmt.moneySpoken(r.amount)}',
        ].join(', '),
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
          icon: PhosphorIconsRegular.clipboardText,
          title: StatsCopy.cardOwnForms,
          subtitle: self != null ? period : StatsCopy.now,
          howTo: StatsCopy.howOwnForms,
          summary: self != null
              ? StatsCopy.formsSummary(self.forms, self.converted)
              : '${(fieldSummary?.drafts ?? 0) + (fieldSummary?.pending ?? 0)} '
                    'açık form',
          compactLine: self?.conversion == null
              ? null
              : DeckLineSpec(
                  StatsCopy.conversionSentence(StatsFmt.rate(self!.conversion)),
                ),
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
        icon: PhosphorIconsRegular.identificationBadge,
        title: StatsCopy.cardTeam,
        subtitle: period,
        howTo: StatsCopy.howTeam,
        summary: StatsCopy.formsSummary(forms, converted),
        body: _TeamBody(team: s.team, forms: forms, converted: converted),
      ),
    );
  }

  final risk = s.risk;
  if (!own && risk != null && risk.nearLimitCount > 0) {
    out.add(
      DeckCardSpec(
        id: DeckCards.risk,
        tone: AknTone.danger,
        icon: PhosphorIconsFill.gauge,
        title: StatsCopy.cardRisk,
        subtitle: StatsCopy.now,
        howTo: StatsCopy.howRisk,
        summary: [
          '${risk.nearLimitCount} ${StatsCopy.nearLimitWord}',
          for (final r in risk.nearLimit.take(3))
            '${r.title} ${_spokenRate(r.usageRate)}',
        ].join(', '),
        compactLine: risk.nearLimit.isEmpty
            ? null
            : DeckLineSpec(_riskLine(risk), bang: true),
        body: _RiskBody(risk: risk),
      ),
    );
  }
  return out;
}

/// Müşteri destesi: Bu ay harcama, Yakıt alımı, Ortalama birim fiyat, Limit durumu, Teslimat noktaları,
/// Sipariş durumu.
List<DeckCardSpec> customerDeckCards(BuildContext context, CustomerStats s) {
  final period = _periodText(s.period);
  final compare = s.period.key.compareShort;
  final compared = _comparedPeriod(period, s.period.key);
  final spend = s.spending;
  final out = <DeckCardSpec>[];
  if (spend != null) {
    out.add(
      DeckCardSpec(
        id: DeckCards.spend,
        tone: AknTone.brand,
        icon: PhosphorIconsRegular.money,
        title: s.period.key == StatsPeriod.month
            ? StatsCopy.cardSpend
            : StatsCopy.kpiSpending,
        subtitle: compared,
        howTo: StatsCopy.howSpend,
        summary: _moneySummary(spend.amount, spend.prevAmount),
        body: _AmountBody(
          amount: spend.amount,
          previous: spend.prevAmount,
          compare: compare,
          months: s.months,
          period: s.period,
          liters: spend.liters,
          litersLabel: StatsCopy.kpiLitersCustomer,
          unitPrice: spend.unitPrice,
          orders: spend.orders,
        ),
      ),
    );
    out.add(
      DeckCardSpec(
        id: DeckCards.purchase,
        tone: AknTone.info,
        icon: PhosphorIconsRegular.gasPump,
        title: StatsCopy.cardPurchase,
        subtitle: compared,
        howTo: StatsCopy.howPurchase,
        summary: _litersSummary(spend.liters, spend.prevLiters),
        body: _LitersBody(
          liters: spend.liters,
          previous: spend.prevLiters,
          compare: compare,
          products: s.products,
          months: s.months,
        ),
      ),
    );
    final price = spend.unitPrice;
    if (price != null) {
      out.add(
        DeckCardSpec(
          id: DeckCards.unitPrice,
          tone: AknTone.ok,
          icon: PhosphorIconsRegular.tag,
          title: StatsCopy.cardUnitPrice,
          subtitle: period,
          howTo: StatsCopy.howUnitPrice,
          summary: '${StatsFmt.price(price)} lira litre',
          compactLine: _priceLine(price, spend.prevUnitPrice),
          body: _UnitPriceBody(
            price: price,
            previous: spend.prevUnitPrice,
            compare: compare,
            months: s.months,
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
        icon: PhosphorIconsFill.gauge,
        title: StatsCopy.cardLimits,
        subtitle: StatsCopy.now,
        howTo: StatsCopy.howLimits,
        compactLine: _limitsLine(s.limits),
        body: _LimitsBody(limits: s.limits),
      ),
    );
  }
  if (s.deliveryPoints.isNotEmpty) {
    out.add(
      DeckCardSpec(
        id: DeckCards.points,
        tone: AknTone.info,
        icon: PhosphorIconsRegular.mapPin,
        title: StatsCopy.cardPoints,
        subtitle: period,
        howTo: StatsCopy.howPoints,
        summary: '${s.deliveryPoints.length} ${StatsCopy.pointsWord}',
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
        icon: PhosphorIconsRegular.receipt,
        title: StatsCopy.cardOrderStatus,
        subtitle: StatsCopy.now,
        howTo: StatsCopy.howOrderStatus,
        summary:
            '${orders.open} ${StatsCopy.openOrders}'
            '${orders.awaitingDecision > 0 ? ', ${StatsCopy.decisionsWaiting(orders.awaitingDecision)}' : ''}',
        compactLine: orders.awaitingDecision > 0
            ? DeckLineSpec(StatsCopy.decisionsWaiting(orders.awaitingDecision))
            : null,
        body: _OrderStatusBody(orders: orders),
      ),
    );
  }
  return out;
}

// ============================================================== yardımcılar

String _periodText(StatsPeriodInfo p) =>
    p.from == null ? p.title : StatsFmt.rangeShort(p.from, p.to);

/// Fark çipli kartın başlık satırı: dönem ve karşılaştırmanın kısa adı ("1–29 Ekim · geçen aya
/// göre"; v4 tur 2, /stats plakasıyla aynı söz). Ekran okuyucu çipte uzun cümleyi duyar.
String _comparedPeriod(String period, StatsPeriod key) =>
    period.isEmpty ? key.compareBrief : '$period · ${key.compareBrief}';

DeckLineSpec? _priceLine(double price, double? previous) {
  if (previous == null) return null;
  final diff = price - previous;
  final flat = diff.abs() < 0.005;
  return DeckLineSpec(
    StatsCopy.priceShort(cheaper: flat ? null : diff < 0),
    chip: StatsFmt.priceDelta(diff),
  );
}

String _riskLine(StatsRisk risk) {
  final rows = [...risk.nearLimit]
    ..sort((a, b) => b.usageRate.compareTo(a.usageRate));
  return '${rows.first.title} ${StatsFmt.rate(rows.first.usageRate)}';
}

/// Limit kartının satırı ([_LimitsBody] ile aynı hesap).
DeckLineSpec? _limitsLine(List<StatsLimit> limits) {
  final money = limits.where((l) => !l.isUnlimited && !l.isLiters).toList();
  final litre = limits.where((l) => !l.isUnlimited && l.isLiters).toList();
  final set = money.isNotEmpty ? money : litre;
  if (set.isEmpty) return null;
  final limit = set.fold<double>(0, (a, l) => a + (l.limit ?? 0));
  final used = set.fold<double>(0, (a, l) => a + l.used);
  final rate = limit <= 0 ? 0.0 : used / limit;
  return DeckLineSpec(StatsCopy.availableAt(set.length), bang: rate >= 0.8);
}

String _spokenRate(double rate) =>
    'yüzde ${StatsFmt.rate(rate).replaceFirst('%', '')}';

String _moneySummary(double amount, double previous) {
  final pct = StatsFmt.change(amount, previous);
  return [
    StatsFmt.moneyWholeSpoken(amount),
    if (pct != null) StatsFmt.deltaSpoken(pct),
  ].join(', ');
}

String _litersSummary(double liters, double previous) {
  final pct = StatsFmt.change(liters, previous);
  return [
    StatsFmt.litersSpoken(liters),
    if (pct != null) StatsFmt.deltaSpoken(pct),
  ].join(', ');
}

/// Bu ayın ay sonu tahmini (tasarım v3 §4): yalnızca "Bu ay" döneminde ve ayın 5'inden sonra.
double? deckMonthEndProjection(StatsPeriodInfo period, double monthToDate) {
  if (period.key != StatsPeriod.month || monthToDate <= 0) return null;
  final w = TrTime.wall(period.to ?? TrTime.now());
  return plateMonthEndProjection(monthToDate, DateTime(w.year, w.month, w.day));
}

/// Çubukların yükselişi sayacın son 300 ms'sinde başlar (tasarım v3 §5 "ana sayfa anı").
Duration get _barsDelay =>
    AknMotion.plateLight + AknMotion.plateRoll - AknMotion.barsRise;

/// Rakamın altındaki cümlenin yazısı (tasarım v3 §4: 13/18 500, soluk) — fark çipinin yanındaki
/// karşılaştırma ve kısa durum cümleleri. Deste büyük yazı yüksekliğini de bununla ölçer.
TextStyle deckSentenceStyle(BuildContext context) => context.aknText.label
    .copyWith(fontWeight: FontWeight.w500, color: context.akn.dim);

/// Fark çipinin yazısı (13/24 700, tabular); renk desteden gelir.
TextStyle deckChipStyle(BuildContext context) =>
    context.aknText.bodySmall.copyWith(
      fontSize: 13,
      height: 24 / 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      fontFeatures: AknNumerals.tabular,
    );

/// Plakadaki satır yazısı (14/20 500, mürekkep) ve değeri (15/20 700, tabular).
TextStyle _lineStyle(BuildContext context) => context.aknText.bodySmall
    .copyWith(color: context.akn.ink, fontWeight: FontWeight.w500);

TextStyle _valueStyle(BuildContext context) =>
    context.aknText.bodySmall.copyWith(
      fontSize: 15,
      height: 20 / 15,
      fontWeight: FontWeight.w700,
      color: context.akn.ink,
      fontFeatures: AknNumerals.tabular,
    );

/// [rowExtent] yüksekliğindeki satırlardan [maxHeight]'a kaç tanesi sığar (en az 1, en çok [max]).
int _fitRows(double maxHeight, double rowExtent, {int max = 3}) {
  if (!maxHeight.isFinite) return max;
  return ((maxHeight + 0.5) / rowExtent).floor().clamp(1, max);
}

/// Sıralı çubuk satırının yüksekliği (14/20 satır + 5 + 8 çubuk + 9).
double _rankedExtent(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(20) + 22;

/// Satırların sırayla belirmesi: [i]. satır, kart öne geldikten [base] + 90 ms × i sonra.
Duration _rowDelay(int i, {int base = 220}) =>
    Duration(milliseconds: base + 90 * i);

/// Çubuklarla kural ve kuralla okumalar arası (destede).
const double _deckBarsGap = 8;
const double _deckRuleGap = 6;

/// Çubukların altındaki ay adlarının yeri ([PlateBars]: 4 + 12/16 etiket).
double _barsLabelExtent(BuildContext context) =>
    4 + MediaQuery.textScalerOf(context).scale(12) * 16 / 12;

/// Destede çubuk alanının yüksekliği (24–44): [maxHeight]'tan ay adları, kural ve okumalar (12/16
/// etiket + 24/30 değer) düşülür; kalan çubuklarındır. Yazı küçülmez, çubuklar kısalır (v4 tur 2).
double _deckBarsHeight(BuildContext context, double maxHeight) {
  if (!maxHeight.isFinite) return 44;
  final scaler = MediaQuery.textScalerOf(context);
  final readouts = scaler.scale(12) * 16 / 12 + 2 + scaler.scale(24) * 30 / 24;
  final rest =
      _barsLabelExtent(context) + _deckBarsGap + 1 + _deckRuleGap + readouts;
  return (maxHeight - rest).clamp(24.0, 44.0).toDouble();
}

// ============================================================== içerik düzeni

/// Kart içeriği (tasarım v3 §4 hero kartı): üstte rakam ve fark satırı, ardından üste yaslı ayrıntı
/// ([detailTop]: huni, ölçer) ve kartın altına yaslı ayrıntı ([detail]: kural ve okumalar). Liste
/// içerikleri ([topAligned]) yukarıdan akar. Ayrıntı sığmazsa küçülür, asla taşmaz. Büyük yazı
/// düzeninde ([DeckCardScope.compact]) yalnızca rakam ve cümle kalır (tam bilgi `/stats` sayfasında).
class DeckBody extends StatelessWidget {
  const DeckBody({
    super.key,
    required this.figure,
    this.line,
    this.compactLine,
    this.detailTop,
    this.detail,
    this.detailBuilder,
    this.topAligned = false,
    this.gap = 10,
  });

  final Widget figure;

  /// Rakamın altındaki satır (fark çipi ve cümlesi ya da kısa cümle).
  final Widget? line;

  /// Büyük yazı düzeninde [line] yerine.
  final Widget? compactLine;

  /// Rakamın hemen altındaki ayrıntı (üste yaslı).
  final Widget? detailTop;

  /// Alttaki ayrıntı (kartın altına yaslı; [topAligned] ise üste).
  final Widget? detail;

  /// Kalan yüksekliğe göre kurulan ayrıntı (satır sayısı sığana göre).
  final Widget Function(BuildContext context, double maxHeight)? detailBuilder;

  /// Ayrıntı yukarıdan akar (sıralı listeler).
  final bool topAligned;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final compact = DeckCardScope.maybeOf(context)?.compact ?? false;
    final l = compact ? (compactLine ?? line) : line;
    // Karşılaştırması başlıkta olan fark satırı yer kaplamaz (yalnızca çipi başlığa bırakır).
    final inHead =
        l is _DeckDelta && l.inHead && DeckHeadChip.of(context) != null;
    final top = <Widget>[
      figure,
      if (l != null) ...[if (!inHead) const SizedBox(height: 8), l],
    ];
    final build = detailBuilder;
    final hasDetail =
        !compact && (detail != null || build != null || detailTop != null);
    if (!hasDetail) {
      return _ScaleDown(
        alignment: AlignmentDirectional.topStart,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: top,
        ),
      );
    }
    final dt = detailTop;
    // Küçülmesi gerekirse baştan (sol kenar) hizalı küçülür: ayrıntının sol kenarı başlıkla ve
    // rakamla aynı çizgide kalır (v4 tur 2; ortalı küçülme yapıştırılmış küçük resim gibi duruyordu).
    final align = topAligned
        ? AlignmentDirectional.topStart
        : AlignmentDirectional.bottomStart;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...top,
        if (dt != null) ...[SizedBox(height: gap + 2), dt],
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: gap),
            child: detail == null && build == null
                ? const SizedBox.shrink()
                : LayoutBuilder(
                    builder: (context, cons) => _ScaleDown(
                      alignment: align,
                      child: build != null
                          ? build(context, cons.maxHeight)
                          : detail!,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// İçerik sığmazsa orantılı küçülür (genişlik korunur, taşma olmaz).
class _ScaleDown extends StatelessWidget {
  const _ScaleDown({required this.child, required this.alignment});

  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, cons) => Align(
      alignment: alignment,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: SizedBox(width: cons.maxWidth, child: child),
      ),
    ),
  );
}

/// Plaka rakamı: oturumun ilk üst kartında sayaç gibi döner.
class _DeckFigure extends StatelessWidget {
  const _DeckFigure({
    required this.value,
    this.unit,
    this.word,
    this.semantics,
  });

  final String value;
  final String? unit;
  final String? word;
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    final scope = DeckCardScope.maybeOf(context);
    return PlateFigure(
      value: value,
      unit: unit,
      word: word,
      animate: scope?.roll ?? false,
      delay: AknMotion.plateLight,
      onRollStart: scope?.onRollStart,
      semanticLabel: semantics,
    );
  }
}

/// The head's chip slot of one deck card; it knows when it is disposed
/// (late frame callbacks of the body leave it alone then).
class DeckChipSlot extends ValueNotifier<Widget?> {
  DeckChipSlot() : super(null);

  bool _disposed = false;
  bool get disposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Bir kartın başlığındaki fark çipi yeri (v4): kartın içeriğindeki fark satırı çipini buraya
/// bırakır, kendisi yalnızca cümleyi çizer.
class DeckHeadChip extends InheritedWidget {
  const DeckHeadChip({super.key, required this.sink, required super.child});

  final DeckChipSlot sink;

  static DeckChipSlot? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DeckHeadChip>()?.sink;

  @override
  bool updateShouldNotify(DeckHeadChip old) => old.sink != sink;
}

/// Fark çipi ve karşılaştırma cümlesi ("▲ %9,4 geçen ayın aynı günlerine göre"); cümle sığmazsa çipin
/// yanından sözcük sözcük alta akar. Çip (tasarım v3 §4; v4 tur 2 A11): r8, 24 px, 13 w700 tabular;
/// sakin — zemin yok, mürekkep ▲/▼ ve değer, ince çerçeve (plakada `plateLine`, kâğıtta `line`).
/// Renkler desteden ([DeckCardScope]) gelir ki kart plakayı devralırken çip de yumuşakça geçsin.
/// İyi / kötü rengi yoktur; cümle 13/18 500 soluk. Kart öne gelince çip "pop" ile oturur, oku
/// yönünde kayarak girer ve cümle hafifçe yükselerek belirir.
class _DeckDelta extends StatefulWidget {
  const _DeckDelta({
    required this.label,
    required this.direction,
    required this.sentence,
    required this.spoken,
    this.inHead = false,
  });

  factory _DeckDelta.percent(
    double pct, {
    required String sentence,
    bool inHead = false,
  }) {
    final flat = pct.abs() < StatsFmt.flatThreshold;
    return _DeckDelta(
      label: StatsFmt.deltaPercent(pct),
      direction: flat
          ? AknDeltaDirection.flat
          : pct > 0
          ? AknDeltaDirection.up
          : AknDeltaDirection.down,
      sentence: sentence,
      spoken: '${StatsFmt.deltaSpoken(pct)}, $sentence',
      inHead: inHead,
    );
  }

  final String label;
  final AknDeltaDirection direction;
  final String sentence;
  final String spoken;

  /// Destede karşılaştırma başlığın dönem satırındadır ("1–29 Ekim · geçen aya göre", v4 tur 2):
  /// çip başlığa gider, rakamın altında cümle satırı çizilmez (ekran okuyucu yine tam cümleyi duyar).
  final bool inHead;

  @override
  State<_DeckDelta> createState() => _DeckDeltaState();
}

/// v4: inside a deck card the chip moves to the card's head ([DeckHeadChip])
/// and the line keeps the sentence.
class _DeckDeltaState extends State<_DeckDelta> {
  DeckChipSlot? _sink;
  Widget? _published;

  Widget _chip(BuildContext context) {
    final c = context.akn;
    final scope = DeckCardScope.maybeOf(context);
    final fill = scope?.chipFill;
    final ink = scope?.chipInk ?? c.ink;
    final line = scope?.chipLine ?? c.plateLine;
    final direction = widget.direction;
    final arrow =
        direction == AknDeltaDirection.up ||
        direction == AknDeltaDirection.down;
    final down = direction == AknDeltaDirection.down;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: line),
        borderRadius: AknRadius.tag,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (arrow) ...[
            _ArrowIn(
              down: down,
              child: TriangleGlyph(down: down, color: ink),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            widget.label,
            maxLines: 1,
            softWrap: false,
            style: deckChipStyle(context).copyWith(color: ink),
          ),
        ],
      ),
    );
  }

  void _publish(Widget chip) {
    final sink = _sink;
    if (sink == null) return;
    _published = chip;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || sink.disposed || !identical(_published, chip)) return;
      sink.value = MediaQuery.withNoTextScaling(child: _PopIn(child: chip));
    });
  }

  @override
  void dispose() {
    final sink = _sink;
    if (sink != null && _published != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!sink.disposed && sink.value != null) sink.value = null;
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _sink = DeckHeadChip.of(context);
    final chip = _chip(context);
    if (_sink != null && widget.inHead) {
      _publish(chip);
      return Semantics(
        label: widget.spoken,
        excludeSemantics: true,
        child: const SizedBox(width: double.infinity),
      );
    }
    if (_sink != null) {
      _publish(chip);
      return Semantics(
        label: widget.spoken,
        excludeSemantics: true,
        child: StatsRise(
          delay: const Duration(milliseconds: 160),
          offset: 6,
          child: Text(widget.sentence, style: deckSentenceStyle(context)),
        ),
      );
    }
    return Semantics(
      label: widget.spoken,
      excludeSemantics: true,
      child: StatsRise(
        delay: const Duration(milliseconds: 160),
        offset: 6,
        child: Text.rich(
          TextSpan(
            children: [
              // Satır içi öğeyi metin ölçeği bir kez büyütür; çipin kendi yazısı ölçeksiz çizilir.
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: MediaQuery.withNoTextScaling(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 10),
                    child: _PopIn(child: chip),
                  ),
                ),
              ),
              TextSpan(text: widget.sentence),
            ],
          ),
          style: deckSentenceStyle(context),
        ),
      ),
    );
  }
}

/// Çip ilk görünüşünde küçükten "pop" ile oturur (hareket azaltmada hemen).
class _PopIn extends StatelessWidget {
  const _PopIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = AknMotion.of(context, const Duration(milliseconds: 620));
    if (d == Duration.zero) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: d,
      // İlk 200 ms bekler, sonra taşarak oturur.
      curve: const Interval(0.32, 1, curve: AknMotion.pop),
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.6 + 0.4 * v, child: child),
      ),
    );
  }
}

/// Fark okunun girişi: yönünde birkaç piksel kayarak belirir.
class _ArrowIn extends StatelessWidget {
  const _ArrowIn({required this.down, required this.child});

  final bool down;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = AknMotion.of(context, const Duration(milliseconds: 760));
    if (d == Duration.zero) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: d,
      curve: const Interval(0.45, 1, curve: AknMotion.spring),
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (down ? -5 : 5) * (1 - v)),
          child: child,
        ),
      ),
    );
  }
}

/// Rakamın altındaki kısa cümle ("31 ödeme tahsil edildi", 13/18 500 soluk); vurgulu ya da sorun
/// satırı ("!" + kalın mürekkep). Kart öne gelince hafifçe yükselerek belirir.
class _DeckLine extends StatelessWidget {
  const _DeckLine(this.text, {this.bold = false, this.bang = false});

  final String text;
  final bool bold;
  final bool bang;

  @override
  Widget build(BuildContext context) {
    final style = deckSentenceStyle(context);
    return StatsRise(
      delay: const Duration(milliseconds: 160),
      offset: 6,
      child: Row(
        children: [
          if (bang) ...[const PlateBang(), const SizedBox(width: 8)],
          Flexible(
            child: Text(
              text,
              style: bold || bang
                  ? style.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.akn.ink,
                    )
                  : style,
            ),
          ),
        ],
      ),
    );
  }
}

/// Plakada oran satırı: "%94 zamanında ……… hedef %90" (oran 15/20 700 tabular, sayaç gibi döner;
/// hedef soluk).
class _RateRow extends StatelessWidget {
  const _RateRow({required this.rate, required this.label, this.trailing});

  final String rate;
  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final style = _lineStyle(context);
    return ExcludeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: RollingText(
              TextSpan(
                children: [
                  TextSpan(text: rate, style: _valueStyle(context)),
                  TextSpan(text: ' $label', style: style),
                ],
              ),
              delay: const Duration(milliseconds: 200),
              maxLines: 2,
              softWrap: true,
            ),
          ),
          if (trailing != null)
            Text(trailing!, style: style.copyWith(color: context.akn.dim)),
        ],
      ),
    );
  }
}

/// Plakadaki sıralı çubuklar (tasarım v3 §4): ad solda (14/20 500, tek satır), değer sağda (15/20
/// 700 tabular; dar ekranda büyük yazıda küçülür, taşmaz), altında 8 px tam yuvarlak çubuk. Plakada
/// dolgu turuncu rampa (`heroStart` → `plateAccent`) ve yumuşak ışıma, iz `chartTrack`; kâğıtta
/// mürekkep. İki seride iz formun boyu (`chartContext`). Kart öne gelince çubuklar satır satır
/// büyür. İki seride iki maddelik lejant.
class _RankedRows extends StatelessWidget {
  const _RankedRows({required this.rows, this.legend = const []});

  final List<PlateRankedBar> rows;
  final List<PlateLegendItem> legend;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final label = _lineStyle(context);
    final value = _valueStyle(context);
    final plate = c.isPlatePalette;
    final (start, end) = statsAccentRamp(c);
    final fill = plate ? end : c.ink;
    final fillStart = plate ? start : c.ink;
    final twoSeries = legend.isNotEmpty || rows.any((r) => r.track < 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++)
          Semantics(
            label:
                rows[i].semanticLabel ?? '${rows[i].label}: ${rows[i].value}',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (context, cons) => Row(
                    children: [
                      Expanded(
                        child: Text(
                          rows[i].label,
                          style: label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: cons.maxWidth * 0.62,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(
                            rows[i].value,
                            style: value,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                StatsGrowBar(
                  height: 8,
                  fraction: rows[i].track <= 0
                      ? 0
                      : rows[i].fraction.clamp(0.0, rows[i].track),
                  track: rows[i].track.clamp(0.0, 1.0),
                  trackColor: c.plateChartTrack,
                  trackFill: twoSeries ? c.plateChartContext : null,
                  fill: fill,
                  fillStart: fillStart,
                  glow: plate && !twoSeries,
                  delay: _rowDelay(i),
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
                          gradient: l.filled
                              ? LinearGradient(colors: [fillStart, fill])
                              : null,
                          color: l.filled ? null : c.plateChartContext,
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
      ],
    );
  }
}

// ============================================================== içerikler

/// Satış / Bu ay harcama: rakam, fark, 6 aylık çubuklar (bu ay turuncu degrade, ay sonu tahmini kesikli), kural ve
/// okumalar (litre, ortalama birim fiyat, ay sonu tahmini — ayın 5'inden önce sipariş sayısı). Büyük
/// yazıda okuma etiketleri kısalır ("Yakıt", "Ay sonu") ki rakamlar aynı hizada kalsın.
class _AmountBody extends StatelessWidget {
  const _AmountBody({
    required this.amount,
    required this.previous,
    required this.compare,
    required this.months,
    required this.period,
    required this.liters,
    required this.litersLabel,
    required this.unitPrice,
    required this.orders,
  });

  final double amount;
  final double previous;
  final String compare;
  final List<StatsMonth> months;
  final StatsPeriodInfo period;
  final double liters;
  final String litersLabel;
  final double? unitPrice;
  final int orders;

  @override
  Widget build(BuildContext context) {
    final scope = DeckCardScope.maybeOf(context);
    final tight = MediaQuery.textScalerOf(context).scale(10) > 11.5;
    final pct = StatsFmt.change(amount, previous);
    final proj = deckMonthEndProjection(period, amount);
    final current = months.length - 1;
    PlateReadout third;
    if (proj == null) {
      third = PlateReadout(
        label: StatsCopy.kpiOrders,
        value: StatsFmt.count(orders),
      );
    } else {
      final (v, u) = StatsFmt.moneyReadout(proj);
      third = PlateReadout(
        label: tight ? 'Ay sonu' : StatsCopy.readoutProjection,
        value: v,
        unit: u,
        dashed: true,
        semanticLabel:
            '${StatsCopy.readoutProjection}: ${StatsFmt.moneySpoken(proj)}',
      );
    }
    return DeckBody(
      figure: _DeckFigure(
        value: StatsFmt.count(amount),
        unit: '₺',
        semantics: StatsFmt.moneyWholeSpoken(amount),
      ),
      line: pct == null
          ? null
          : _DeckDelta.percent(pct, sentence: compare, inHead: true),
      // Çubuklar kalan yüksekliğe göre boylanır; okumalar ve ay adları tam boyda kalır (v4 tur 2:
      // ayrıntı küçülüp okumalar 9 dp'ye inmesin).
      detailBuilder: (context, maxHeight) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (months.isNotEmpty) ...[
            PlateBars(
              height: _deckBarsHeight(context, maxHeight),
              values: [for (final m in months) m.amount],
              labels: [for (final m in months) m.shortLabel],
              projection: proj,
              valueLabels: [
                for (final m in months) StatsFmt.moneyCompact(m.amount),
              ],
              semanticLabels: [
                for (var i = 0; i < months.length; i++)
                  [
                    months[i].longLabel,
                    StatsFmt.moneySpoken(months[i].amount),
                    if (i == current && proj != null)
                      StatsCopy.projectionLegend(StatsFmt.moneySpoken(proj)),
                  ].join(', '),
              ],
              animate: scope?.roll ?? false,
              delay: _barsDelay,
            ),
            const SizedBox(height: _deckBarsGap),
          ],
          const PlateRule(),
          const SizedBox(height: _deckRuleGap),
          PlateReadouts(
            items: [
              PlateReadout(
                label: tight ? 'Yakıt' : litersLabel,
                value: StatsFmt.count(liters),
                unit: 'L',
                semanticLabel: '$litersLabel: ${StatsFmt.litersSpoken(liters)}',
              ),
              PlateReadout(
                label: StatsCopy.readoutAverage,
                value: StatsFmt.price(unitPrice),
                unit: unitPrice == null ? null : '₺/L',
                semanticLabel: unitPrice == null
                    ? '${StatsCopy.kpiUnitPrice}: veri yok'
                    : '${StatsCopy.kpiUnitPrice}: ${StatsFmt.price(unitPrice)} lira litre',
              ),
              third,
            ],
          ),
        ],
      ),
    );
  }
}

/// Satılan yakıt / Yakıt alımı: litre, fark, kural ve ilk üç ürün (litre payı; tek seri, renk yok).
class _LitersBody extends StatelessWidget {
  const _LitersBody({
    required this.liters,
    required this.previous,
    required this.compare,
    required this.products,
    required this.months,
  });

  final double liters;
  final double previous;
  final String compare;
  final List<StatsProduct> products;
  final List<StatsMonth> months;

  @override
  Widget build(BuildContext context) {
    final pct = StatsFmt.change(liters, previous);
    final total = products.fold<double>(0, (a, p) => a + p.liters);
    final shares = products.fold<double>(0, (a, p) => a + p.share);
    double frac(StatsProduct p) =>
        total > 0 ? p.liters / total : (shares > 0 ? p.share / shares : 0);
    final sorted = [...products]..sort((a, b) => frac(b).compareTo(frac(a)));
    return DeckBody(
      figure: _DeckFigure(
        value: StatsFmt.count(liters),
        unit: 'L',
        semantics: StatsFmt.litersSpoken(liters),
      ),
      line: pct == null
          ? null
          : _DeckDelta.percent(pct, sentence: compare, inHead: true),
      detailBuilder: (context, maxHeight) {
        if (sorted.isEmpty) {
          if (months.isEmpty) return const SizedBox.shrink();
          return PlateBars(
            height: math.min(
              44,
              math.max(24, maxHeight - _barsLabelExtent(context)),
            ),
            values: [for (final m in months) m.liters],
            labels: [for (final m in months) m.shortLabel],
            valueLabels: [
              for (final m in months) StatsFmt.litersCompact(m.liters),
            ],
            semanticLabels: [
              for (final m in months)
                '${m.longLabel}, ${StatsFmt.litersSpoken(m.liters)}',
            ],
          );
        }
        final n = _fitRows(maxHeight - 11, _rankedExtent(context));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const PlateRule(),
            const SizedBox(height: 8),
            _RankedRows(
              rows: [
                for (final p in sorted.take(n))
                  PlateRankedBar(
                    label: p.name,
                    value: StatsFmt.liters(p.liters),
                    fraction: frac(p),
                    semanticLabel:
                        '${p.name}: ${StatsFmt.litersSpoken(p.liters)}, '
                        'payı ${StatsFmt.rate(frac(p))}',
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Sipariş hunisi: dönüşüm (%72 dönüşüm), Talep / Teklif / Onay çubukları (sonuç turuncu), kural ve ilk
/// teklif süresi (kartın altında).
class _FunnelBody extends StatelessWidget {
  const _FunnelBody({required this.funnel});

  final StatsFunnel funnel;

  @override
  Widget build(BuildContext context) {
    final f = funnel;
    final conv = f.conversion;
    final top = math.max(f.requests, math.max(f.quoted, f.accepted));
    double frac(int v) => top <= 0 ? 0 : v / top;
    final minutes = f.avgFirstQuoteMinutes;
    return DeckBody(
      figure: conv == null
          ? _DeckFigure(value: StatsFmt.count(f.requests), word: 'talep')
          : _DeckFigure(
              value: StatsFmt.rate(conv),
              word: StatsCopy.conversion,
              semantics: '${_spokenRate(conv)} ${StatsCopy.conversion}',
            ),
      compactLine: _DeckLine(StatsCopy.funnelSentence(f.requests, f.accepted)),
      detailTop: PlateFunnel(
        steps: [
          PlateFunnelStep(
            label: StatsCopy.funnelRequests,
            value: StatsFmt.count(f.requests),
            fraction: frac(f.requests),
          ),
          PlateFunnelStep(
            label: StatsCopy.funnelQuoted,
            value: StatsFmt.count(f.quoted),
            fraction: frac(f.quoted),
          ),
          PlateFunnelStep(
            label: StatsCopy.funnelAccepted,
            value: StatsFmt.count(f.accepted),
            fraction: frac(f.accepted),
            highlight: true,
          ),
        ],
      ),
      detail: minutes == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const PlateRule(),
                PlateLedger(
                  lines: [
                    PlateLedgerLine(
                      label: StatsCopy.firstQuoteLine,
                      value: StatsFmt.minutes(minutes),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// Tahsilat: tahsil edilen tutar, "31 ödeme tahsil edildi", kural ve defter (gecikme ilk satırda, "!"
/// ve kalın; plakada kırmızı yok).
class _CollectionsBody extends StatelessWidget {
  const _CollectionsBody({required this.collections});

  final StatsCollections collections;

  @override
  Widget build(BuildContext context) {
    final x = collections;
    return DeckBody(
      figure: _DeckFigure(
        value: StatsFmt.count(x.collectedAmount),
        unit: '₺',
        semantics: StatsFmt.moneyWholeSpoken(x.collectedAmount),
      ),
      line: _DeckLine(StatsCopy.collectedSentence(x.collectedCount)),
      compactLine: x.overdueCount > 0
          ? _DeckLine(StatsCopy.overdueLine(x.overdueCount), bang: true)
          : _DeckLine(StatsCopy.collectedSentence(x.collectedCount)),
      detail: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const PlateRule(),
          const SizedBox(height: 2),
          PlateLedger(
            lines: [
              PlateLedgerLine(
                label: StatsCopy.overdueLine(x.overdueCount),
                value: StatsFmt.money(x.overdueAmount),
                problem: x.overdueCount > 0,
              ),
              PlateLedgerLine(
                label: StatsCopy.dueSoonLine(x.dueSoonDays, x.dueSoonCount),
                value: StatsFmt.money(x.dueSoonAmount),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sevkiyat: teslimat sayısı, zamanında oranı ölçerde (hedef %90 ince çizgi), kural ve anlık durumlar.
class _DeliveriesBody extends StatelessWidget {
  const _DeliveriesBody({required this.deliveries});

  final StatsDeliveries deliveries;

  @override
  Widget build(BuildContext context) {
    final d = deliveries;
    final rate = d.onTimeRate;
    return DeckBody(
      figure: _DeckFigure(
        value: StatsFmt.count(d.delivered),
        word: StatsCopy.delivered,
      ),
      compactLine: rate == null
          ? null
          : _DeckLine(StatsCopy.onTimeSentence(StatsFmt.rate(rate))),
      detailTop: rate == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _RateRow(
                  rate: StatsFmt.rate(rate),
                  label: StatsCopy.onTime,
                  trailing: StatsCopy.onTimeTarget,
                ),
                const SizedBox(height: 12),
                PlateMeter(
                  value: rate,
                  threshold: StatsCopy.onTimeGoal,
                  semanticLabel: 'Zamanında teslim, hedef yüzde 90',
                ),
              ],
            ),
      detail: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const PlateRule(),
          const SizedBox(height: 8),
          PlateReadouts(
            items: [
              PlateReadout(
                label: StatsCopy.inTransit,
                value: StatsFmt.count(d.inTransit),
              ),
              PlateReadout(
                label: StatsCopy.planned,
                value: StatsFmt.count(d.planned),
              ),
              PlateReadout(
                label: StatsCopy.disputes,
                value: StatsFmt.count(d.disputes),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// En çok alan cariler: ilk carilerin payı ("%51 ilk 4 cari"; liste tüm carileri kapsıyorsa ilk üçün
/// payı) ve ilk üç cari (çubuk ilk sıradakine göre).
class _TopCustomersBody extends StatelessWidget {
  const _TopCustomersBody({required this.rows});

  final List<StatsTopCustomer> rows;

  @override
  Widget build(BuildContext context) {
    final all = rows.fold<double>(0, (a, r) => a + r.share);
    final top = rows.fold<double>(0, (m, r) => math.max(m, r.amount));
    // Liste tüm satışı kapsıyorsa (%100) ilk üçün payı anlamlıdır; üç ya da daha az cari varsa sayı.
    final covers = all >= 0.995;
    final n = covers ? math.min(3, rows.length) : rows.length;
    final share = covers
        ? rows.take(n).fold<double>(0, (a, r) => a + r.share)
        : all;
    final useShare = share > 0 && !(covers && rows.length <= 3);
    final word = StatsCopy.topShareWord(n, all: false);
    return DeckBody(
      figure: useShare
          ? _DeckFigure(
              value: StatsFmt.rate(share),
              word: word,
              semantics: '${_spokenRate(share)}, $word',
            )
          : _DeckFigure(value: StatsFmt.count(rows.length), word: 'cari'),
      detailBuilder: (context, maxHeight) {
        final fit = _fitRows(maxHeight, _rankedExtent(context));
        return _RankedRows(
          rows: [
            for (final r in rows.take(fit))
              PlateRankedBar(
                label: r.title,
                value: StatsFmt.moneyCompactAt(r.amount, top),
                fraction: top <= 0 ? 0 : r.amount / top,
                semanticLabel:
                    '${r.title}: ${StatsFmt.moneySpoken(r.amount)}, '
                    'payı ${StatsFmt.rate(r.share)}',
              ),
          ],
        );
      },
    );
  }
}

/// Saha ekibi: form ve sipariş toplamı, ilk üç temsilci (açık form, turuncu siparişe dönüşen) ve iki
/// maddelik lejant.
class _TeamBody extends StatelessWidget {
  const _TeamBody({
    required this.team,
    required this.forms,
    required this.converted,
  });

  final List<StatsTeamMember> team;
  final int forms;
  final int converted;

  @override
  Widget build(BuildContext context) {
    final sorted = [...team]
      ..sort((a, b) {
        final x = b.converted.compareTo(a.converted);
        return x != 0 ? x : b.forms.compareTo(a.forms);
      });
    final most = sorted.fold<int>(
      0,
      (m, r) => math.max(m, math.max(r.forms, r.converted)),
    );
    return DeckBody(
      figure: _DeckFigure(
        value: StatsFmt.count(forms),
        word: StatsCopy.formsWord(converted),
        semantics: StatsCopy.formsSummary(forms, converted),
      ),
      detailBuilder: (context, maxHeight) {
        final legend = MediaQuery.textScalerOf(context).scale(18) + 2;
        final n = _fitRows(maxHeight - legend, _rankedExtent(context));
        return _RankedRows(
          rows: [
            for (final m in sorted.take(n))
              PlateRankedBar(
                label: m.name,
                value: StatsCopy.formsSummary(m.forms, m.converted),
                track: most <= 0 ? 0 : m.forms / most,
                fraction: most <= 0 ? 0 : m.converted / most,
                semanticLabel:
                    '${m.name}: ${StatsCopy.formsSummary(m.forms, m.converted)}, '
                    '${StatsFmt.litersSpoken(m.liters)}',
              ),
          ],
          legend: const [
            PlateLegendItem(StatsCopy.legendConverted),
            PlateLegendItem(StatsCopy.legendForms, filled: false),
          ],
        );
      },
    );
  }
}

/// Limit riski: limitine yakın cari sayısı ve en riskli satırlar ("!" + kalın ad, turuncu ölçer, %80
/// eşik çizgisi); plakada sarı / kırmızı yok. Ölçer %100'de durur.
class _RiskBody extends StatelessWidget {
  const _RiskBody({required this.risk});

  final StatsRisk risk;

  @override
  Widget build(BuildContext context) {
    final rows = [...risk.nearLimit]
      ..sort((a, b) => b.usageRate.compareTo(a.usageRate));
    return DeckBody(
      figure: _DeckFigure(
        value: StatsFmt.count(risk.nearLimitCount),
        word: StatsCopy.nearLimitWord,
      ),
      compactLine: rows.isEmpty
          ? null
          : _DeckLine(
              '${rows.first.title} ${StatsFmt.rate(rows.first.usageRate)}',
              bang: true,
            ),
      detailBuilder: (context, maxHeight) {
        final s = MediaQuery.textScalerOf(context);
        final caption = s.scale(20) + 10;
        final n = rows.isEmpty
            ? 0
            : math.min(
                rows.length,
                _fitRows(maxHeight - caption, s.scale(20) + 38),
              );
        final style = _lineStyle(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              Semantics(
                label:
                    'Dikkat, ${rows[i].title}: limit kullanımı ${StatsFmt.rate(rows[i].usageRate)}',
                excludeSemantics: true,
                child: StatsRise(
                  delay: _rowDelay(i),
                  offset: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const PlateBang(),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              rows[i].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            StatsFmt.rate(rows[i].usageRate),
                            style: _valueStyle(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      PlateMeter(
                        value: math.min(1, rows[i].usageRate),
                        threshold: StatsCopy.warnLevel,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(StatsCopy.warnThreshold, style: style),
            ),
          ],
        );
      },
    );
  }
}

/// Saha formlarım (temsilcinin kendi destesi): form ve sipariş, dönüşüm ölçeri ve okumalar; ekip satırı
/// gelmezse açık / sonuçlanan form sayıları.
class _OwnFormsBody extends StatelessWidget {
  const _OwnFormsBody({required this.self, required this.summary});

  final StatsTeamMember? self;
  final StatsFieldSummary? summary;

  @override
  Widget build(BuildContext context) {
    final me = self;
    if (me != null) {
      final conv = me.conversion;
      return DeckBody(
        figure: _DeckFigure(
          value: StatsFmt.count(me.forms),
          word: StatsCopy.formsWord(me.converted),
          semantics: StatsCopy.formsSummary(me.forms, me.converted),
        ),
        line: conv == null
            ? null
            : _DeckLine(StatsCopy.conversionSentence(StatsFmt.rate(conv))),
        detailTop: conv == null
            ? null
            : PlateMeter(value: conv, semanticLabel: StatsCopy.converted),
        detail: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const PlateRule(),
            const SizedBox(height: 8),
            PlateReadouts(
              items: [
                PlateReadout(
                  label: StatsCopy.readoutConverted,
                  value: StatsFmt.count(me.converted),
                ),
                PlateReadout(
                  label: StatsCopy.kpiLiters,
                  value: StatsFmt.count(me.liters),
                  unit: 'L',
                ),
              ],
            ),
          ],
        ),
      );
    }
    final s = summary ?? const StatsFieldSummary();
    return DeckBody(
      figure: _DeckFigure(
        value: StatsFmt.count(s.drafts + s.pending),
        word: 'açık form',
      ),
      detail: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const PlateRule(),
          const SizedBox(height: 8),
          PlateReadouts(
            items: [
              PlateReadout(
                label: StatsCopy.drafts,
                value: StatsFmt.count(s.drafts),
              ),
              PlateReadout(
                label: StatsCopy.pendingApproval,
                value: StatsFmt.count(s.pending),
              ),
            ],
          ),
          const SizedBox(height: 8),
          PlateReadouts(
            items: [
              PlateReadout(
                label: StatsCopy.rejectedForms,
                value: StatsFmt.count(s.rejected),
              ),
              PlateReadout(
                label: StatsCopy.convertedForms,
                value: StatsFmt.count(s.converted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ortalama birim fiyat: ₺/L, mutlak fark çipi ve cümlesi ("geçen ayın aynı günlerine göre daha
/// ucuz" — düşüş müşteri için iyidir; cümle söyler, renk söylemez) ve kendini çizen 6 aylık çizgi
/// ([PlateLine]: vurgu renginde çizgi, yumuşak dolgu, sonunda halkalı nokta).
class _UnitPriceBody extends StatelessWidget {
  const _UnitPriceBody({
    required this.price,
    required this.previous,
    required this.compare,
    required this.months,
  });

  final double price;
  final double? previous;
  final String compare;
  final List<StatsMonth> months;

  @override
  Widget build(BuildContext context) {
    final prev = previous;
    final diff = prev == null ? null : price - prev;
    final flat = diff != null && diff.abs() < 0.005;
    final priced = [
      for (final m in months)
        if (m.unitPrice != null) m,
    ];
    Widget? line;
    if (diff != null) {
      final cheaper = flat ? null : diff < 0;
      final sentence = StatsCopy.priceSentence(compare, cheaper: cheaper);
      final amount = StatsFmt.priceDelta(diff).replaceAll(' ₺', ' lira');
      line = _DeckDelta(
        label: StatsFmt.priceDelta(diff),
        direction: flat
            ? AknDeltaDirection.flat
            : diff > 0
            ? AknDeltaDirection.up
            : AknDeltaDirection.down,
        sentence: sentence,
        spoken: flat
            ? 'değişim yok, $sentence'
            : 'litrede $amount ${diff > 0 ? 'artış' : 'düşüş'}, $sentence',
      );
    }
    Widget? compactLine;
    if (diff != null) {
      final cheaper = flat ? null : diff < 0;
      compactLine = _DeckDelta(
        label: StatsFmt.priceDelta(diff),
        direction: flat
            ? AknDeltaDirection.flat
            : diff > 0
            ? AknDeltaDirection.up
            : AknDeltaDirection.down,
        sentence: StatsCopy.priceShort(cheaper: cheaper),
        spoken: StatsCopy.priceSentence(compare, cheaper: cheaper),
      );
    }
    return DeckBody(
      figure: _DeckFigure(
        value: StatsFmt.price(price),
        unit: '₺/L',
        semantics: '${StatsFmt.price(price)} lira litre',
      ),
      line: line,
      compactLine: compactLine,
      detailBuilder: priced.length < 2
          ? null
          : (context, maxHeight) => PlateLine(
              values: [for (final m in priced) m.unitPrice!],
              labels: [for (final m in priced) m.shortLabel],
              endLabel: StatsFmt.price(priced.last.unitPrice),
              height: maxHeight.isFinite
                  ? maxHeight.clamp(74.0, 120.0).toDouble()
                  : 74,
              semanticLabel: [
                'Aylara göre ortalama birim fiyat',
                for (final m in priced)
                  '${m.longLabel} ${StatsFmt.unitPrice(m.unitPrice)}',
              ].join(', '),
            ),
    );
  }
}

/// Limit durumu: kullanılabilir tutar, kullanım ölçeri, kural ve okumalar (kullanılan / limit).
/// Ölçer %100'de durur; kullanım %80'i geçince cümle "!" ile başlar.
class _LimitsBody extends StatelessWidget {
  const _LimitsBody({required this.limits});

  final List<StatsLimit> limits;

  @override
  Widget build(BuildContext context) {
    final money = limits.where((l) => !l.isUnlimited && !l.isLiters).toList();
    final litre = limits.where((l) => !l.isUnlimited && l.isLiters).toList();
    final set = money.isNotEmpty ? money : litre;
    if (set.isEmpty) {
      return DeckBody(
        figure: _DeckFigure(
          value: StatsFmt.count(limits.length),
          word: StatsCopy.unlimitedAt(limits.length),
        ),
      );
    }
    final isLiters = money.isEmpty;
    final unit = isLiters ? 'L' : '₺';
    final limit = set.fold<double>(0, (a, l) => a + (l.limit ?? 0));
    final used = set.fold<double>(0, (a, l) => a + l.used);
    final available = set.fold<double>(
      0,
      (a, l) => a + (l.available ?? math.max(0.0, (l.limit ?? 0) - l.used)),
    );
    final rate = limit <= 0 ? 0.0 : used / limit;
    String spoken(double v) =>
        isLiters ? StatsFmt.litersSpoken(v) : StatsFmt.moneySpoken(v);
    return DeckBody(
      figure: _DeckFigure(
        value: StatsFmt.count(available),
        unit: unit,
        semantics: '${spoken(available)} ${StatsCopy.available}',
      ),
      line: _DeckLine(StatsCopy.availableAt(set.length), bang: rate >= 0.8),
      detailTop: PlateMeter(
        value: math.min(1, rate),
        threshold: StatsCopy.warnLevel,
        semanticLabel: 'Limit kullanımı',
        semanticValue: StatsFmt.rate(rate),
      ),
      detail: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const PlateRule(),
          const SizedBox(height: 8),
          PlateReadouts(
            items: [
              PlateReadout(
                label: StatsCopy.readoutUsed,
                value: StatsFmt.count(used),
                unit: unit,
                semanticLabel: '${StatsCopy.readoutUsed}: ${spoken(used)}',
              ),
              PlateReadout(
                label: StatsCopy.readoutLimit,
                value: StatsFmt.count(limit),
                unit: unit,
                semanticLabel: '${StatsCopy.readoutLimit}: ${spoken(limit)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Teslimat noktaları: nokta sayısı ve litreye göre ilk üç nokta.
class _PointsBody extends StatelessWidget {
  const _PointsBody({required this.points});

  final List<StatsDeliveryPoint> points;

  @override
  Widget build(BuildContext context) {
    final rows = [...points]..sort((a, b) => b.liters.compareTo(a.liters));
    final total = rows.fold<double>(0, (a, p) => a + p.liters);
    return DeckBody(
      figure: _DeckFigure(
        value: StatsFmt.count(rows.length),
        word: StatsCopy.pointsWord,
      ),
      detailBuilder: (context, maxHeight) {
        final n = _fitRows(maxHeight - 11, _rankedExtent(context));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const PlateRule(),
            const SizedBox(height: 8),
            _RankedRows(
              rows: [
                for (final p in rows.take(n))
                  PlateRankedBar(
                    label: p.name,
                    value: StatsFmt.liters(p.liters),
                    fraction: total <= 0 ? 0 : p.liters / total,
                    semanticLabel:
                        '${p.name}${p.city == null ? '' : ', ${p.city}'}: '
                        '${StatsFmt.litersSpoken(p.liters)}',
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Sipariş durumu: açık sipariş sayısı, kararınızı bekleyen teklifler ve durum okumaları.
class _OrderStatusBody extends StatelessWidget {
  const _OrderStatusBody({required this.orders});

  final StatsOrderStatus orders;

  @override
  Widget build(BuildContext context) {
    final o = orders;
    PlateReadout r(String label, String spoken, int v) => PlateReadout(
      label: label,
      value: StatsFmt.count(v),
      semanticLabel: '$spoken: $v',
    );
    return DeckBody(
      figure: _DeckFigure(
        value: StatsFmt.count(o.open),
        word: StatsCopy.openOrders,
      ),
      line: o.awaitingDecision > 0
          ? _DeckLine(
              StatsCopy.decisionsWaiting(o.awaitingDecision),
              bold: true,
            )
          : null,
      detail: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const PlateRule(),
          const SizedBox(height: 8),
          PlateReadouts(
            items: [
              r('Teklif', StatsCopy.awaitingQuote, o.awaitingQuote),
              r('Kararınızda', StatsCopy.awaitingDecision, o.awaitingDecision),
              r(
                'Şirket onayı',
                StatsCopy.awaitingCompanyApproval,
                o.awaitingCompanyApproval,
              ),
            ],
          ),
          const SizedBox(height: 8),
          PlateReadouts(
            items: [
              r(StatsCopy.inTransit, StatsCopy.inTransit, o.inTransit),
              r('Teslim', StatsCopy.deliveredStatus, o.delivered),
              r(StatsCopy.disputedStatus, StatsCopy.disputedStatus, o.disputed),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================== kullanım tonu (beyaz sayfa)

/// Limit kullanımının tonu (beyaz sayfada; plakada ton yok): %95 ve üstü kırmızı, %80 ve üstü
/// koyu sarı, altı nötr.
AknTone usageTone(double rate) => rate >= 0.95
    ? AknTone.danger
    : rate >= 0.8
    ? AknTone.warn
    : AknTone.neutral;

/// Kullanım çubuğunun rengi: tonun dolu rengi, nötrde mürekkep.
Color usageColor(AknColors c, double rate) {
  final tone = usageTone(rate);
  return tone == AknTone.neutral ? c.ink : c.tone(tone).solid;
}
