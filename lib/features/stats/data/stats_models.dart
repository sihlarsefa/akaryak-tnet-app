import 'package:flutter/foundation.dart';

import '../../../core/models/json.dart';
import '../../../core/utils/format.dart';

/// İstatistik dönemi (`?period=`; sunucu Türkiye yerel ay sınırlarıyla hesaplar, spec R1 §4).
enum StatsPeriod {
  month('month', 'Bu ay', 'geçen ayın aynı günlerine göre', 'geçen aya göre'),
  lastMonth('lastMonth', 'Geçen ay', 'önceki aya göre', 'önceki aya göre'),
  quarter('quarter', 'Son 3 ay', 'önceki 3 aya göre', 'önceki 3 aya göre'),
  year('year', 'Bu yıl', 'geçen yılın aynı dönemine göre', 'geçen yıla göre');

  const StatsPeriod(this.key, this.label, this.compareShort, this.compareBrief);

  /// Sorgu değeri.
  final String key;

  /// Seçici etiketi ("Bu ay").
  final String label;

  /// Fark çipinin yanındaki cümle: karşılaştırmanın adı ("geçen ayın aynı günlerine göre",
  /// tasarım v2 §10.4).
  final String compareShort;

  /// İstatistikler plakasının dönem satırındaki kısa adı ("1–29 Ekim · geçen aya göre"; v4 tur 2
  /// A11): uzun cümle fark çipinin yanında tek satıra sığmaz, "göre" alt satırda yalnız kalırdı.
  /// Ekran okuyucu [compareShort]'u duyar.
  final String compareBrief;

  /// Bilinmeyen / boş değer [month] olur.
  static StatsPeriod fromKey(String? key) {
    for (final p in values) {
      if (p.key == key) return p;
    }
    return month;
  }
}

/// Dönem bilgisi (`period`): sunucunun etiketi ve tarih aralıkları (saf tarih, Türkiye takvimi).
@immutable
class StatsPeriodInfo {
  const StatsPeriodInfo({
    required this.key,
    this.label,
    this.from,
    this.to,
    this.compareLabel,
    this.compareFrom,
    this.compareTo,
  });

  factory StatsPeriodInfo.fromJson(JsonReader r, {StatsPeriod? fallback}) =>
      StatsPeriodInfo(
        key: r.has('key')
            ? StatsPeriod.fromKey(r.strOrNull('key'))
            : (fallback ?? StatsPeriod.month),
        label: r.nonEmpty('label'),
        from: r.date('from'),
        to: r.date('to'),
        compareLabel: r.nonEmpty('compareLabel'),
        compareFrom: r.date('compareFrom'),
        compareTo: r.date('compareTo'),
      );

  final StatsPeriod key;
  final String? label;
  final DateTime? from;
  final DateTime? to;
  final String? compareLabel;
  final DateTime? compareFrom;
  final DateTime? compareTo;

  /// Ekrandaki ad (sunucu etiketi, yoksa dönemin adı).
  String get title => label ?? key.label;
}

/// Satış / harcama özeti (`sales` bayide, `spending` müşteride). Ortalama birim fiyat ₺/L.
@immutable
class StatsSummary {
  const StatsSummary({
    this.orders = 0,
    this.liters = 0,
    this.amount = 0,
    this.prevOrders = 0,
    this.prevLiters = 0,
    this.prevAmount = 0,
    this.avgUnitPrice,
    this.prevAvgUnitPrice,
    this.activeCustomers,
    this.newCustomers,
  });

  factory StatsSummary.fromJson(JsonReader r) => StatsSummary(
    orders: r.integer('orders'),
    liters: r.dec('liters'),
    amount: r.dec('amount'),
    prevOrders: r.integer('prevOrders'),
    prevLiters: r.dec('prevLiters'),
    prevAmount: r.dec('prevAmount'),
    avgUnitPrice: r.decOrNull('avgUnitPrice'),
    prevAvgUnitPrice: r.decOrNull('prevAvgUnitPrice'),
    activeCustomers: r.intOrNull('activeCustomers'),
    newCustomers: r.intOrNull('newCustomers'),
  );

  final int orders;
  final double liters;
  final double amount;
  final int prevOrders;
  final double prevLiters;
  final double prevAmount;
  final double? avgUnitPrice;
  final double? prevAvgUnitPrice;

  /// Yalnızca bayi.
  final int? activeCustomers;
  final int? newCustomers;

  /// Ortalama birim fiyat: sunucunun değeri, yoksa tutar / litre.
  double? get unitPrice =>
      avgUnitPrice ?? (liters > 0 && amount > 0 ? amount / liters : null);

  double? get prevUnitPrice =>
      prevAvgUnitPrice ??
      (prevLiters > 0 && prevAmount > 0 ? prevAmount / prevLiters : null);

  bool get isEmpty => orders == 0 && liters == 0 && amount == 0;
}

/// Aylık nokta (`months[]`, eskiden yeniye, boş aylar sıfır).
@immutable
class StatsMonth {
  const StatsMonth({
    required this.year,
    required this.month,
    this.label,
    this.orders = 0,
    this.liters = 0,
    this.amount = 0,
  });

  factory StatsMonth.fromJson(JsonReader r) => StatsMonth(
    year: r.integer('year'),
    month: r.integer('month').clamp(1, 12),
    label: r.nonEmpty('label'),
    orders: r.integer('orders'),
    liters: r.dec('liters'),
    amount: r.dec('amount'),
  );

  final int year;
  final int month;
  final String? label;
  final int orders;
  final double liters;
  final double amount;

  /// "Eki".
  String get shortLabel => label ?? Fmt.monthShort[month - 1];

  /// "Ekim 2026".
  String get longLabel => '${Fmt.monthNames[month - 1]} $year';

  /// Ortalama birim fiyat (litre yoksa null).
  double? get unitPrice => liters > 0 && amount > 0 ? amount / liters : null;
}

/// Ürün payı (`products[]`; tutara göre azalan, en çok 6).
@immutable
class StatsProduct {
  const StatsProduct({
    required this.productId,
    required this.name,
    this.liters = 0,
    this.amount = 0,
    this.share = 0,
  });

  factory StatsProduct.fromJson(JsonReader r) => StatsProduct(
    productId: r.integer('productId'),
    name: r.nonEmpty('name') ?? 'Ürün',
    liters: r.dec('liters'),
    amount: r.dec('amount'),
    share: r.dec('share'),
  );

  final int productId;
  final String name;
  final double liters;
  final double amount;

  /// Dönem toplamındaki pay (0..1).
  final double share;
}

/// En çok alan cari (`topCustomers[]`; tutara göre azalan, en çok 5).
@immutable
class StatsTopCustomer {
  const StatsTopCustomer({
    required this.customerId,
    required this.title,
    this.orders = 0,
    this.liters = 0,
    this.amount = 0,
    this.share = 0,
  });

  factory StatsTopCustomer.fromJson(JsonReader r) => StatsTopCustomer(
    customerId: r.integer('customerId'),
    title: r.nonEmpty('title') ?? 'Cari',
    orders: r.integer('orders'),
    liters: r.dec('liters'),
    amount: r.dec('amount'),
    share: r.dec('share'),
  );

  final int customerId;
  final String title;
  final int orders;
  final double liters;
  final double amount;
  final double share;
}

/// Sipariş hunisi: talep → teklif → onay.
@immutable
class StatsFunnel {
  const StatsFunnel({
    this.requests = 0,
    this.quoted = 0,
    this.accepted = 0,
    this.rejected = 0,
    this.expired = 0,
    this.conversionRate,
    this.avgFirstQuoteMinutes,
  });

  factory StatsFunnel.fromJson(JsonReader r) => StatsFunnel(
    requests: r.integer('requests'),
    quoted: r.integer('quoted'),
    accepted: r.integer('accepted'),
    rejected: r.integer('rejected'),
    expired: r.integer('expired'),
    conversionRate: r.decOrNull('conversionRate'),
    avgFirstQuoteMinutes: r.decOrNull('avgFirstQuoteMinutes'),
  );

  final int requests;
  final int quoted;
  final int accepted;
  final int rejected;
  final int expired;

  /// Onaylanan / talep (talep yoksa null).
  final double? conversionRate;

  /// Talepten ilk teklife ortalama dakika (yoksa null).
  final double? avgFirstQuoteMinutes;

  /// Sunucunun oranı, yoksa onay / talep.
  double? get conversion =>
      conversionRate ?? (requests > 0 ? accepted / requests : null);
}

/// Sevkiyat özeti.
@immutable
class StatsDeliveries {
  const StatsDeliveries({
    this.delivered = 0,
    this.deliveredLiters = 0,
    this.onTimeRate,
    this.inTransit = 0,
    this.planned = 0,
    this.disputes = 0,
  });

  factory StatsDeliveries.fromJson(JsonReader r) => StatsDeliveries(
    delivered: r.integer('delivered'),
    deliveredLiters: r.dec('deliveredLiters'),
    onTimeRate: r.decOrNull('onTimeRate'),
    inTransit: r.integer('inTransit'),
    planned: r.integer('planned'),
    disputes: r.integer('disputes'),
  );

  final int delivered;
  final double deliveredLiters;

  /// Zamanında teslim oranı (teslim yoksa null).
  final double? onTimeRate;
  final int inTransit;
  final int planned;
  final int disputes;
}

/// Tahsilat özeti (yalnızca ödemeleri görebilen kullanıcıya gelir).
@immutable
class StatsCollections {
  const StatsCollections({
    this.collectedAmount = 0,
    this.collectedCount = 0,
    this.overdueAmount = 0,
    this.overdueCount = 0,
    this.dueSoonAmount = 0,
    this.dueSoonCount = 0,
    this.dueSoonDays = 7,
  });

  factory StatsCollections.fromJson(JsonReader r) => StatsCollections(
    collectedAmount: r.dec('collectedAmount'),
    collectedCount: r.integer('collectedCount'),
    overdueAmount: r.dec('overdueAmount'),
    overdueCount: r.integer('overdueCount'),
    dueSoonAmount: r.dec('dueSoonAmount'),
    dueSoonCount: r.integer('dueSoonCount'),
    dueSoonDays: r.integer('dueSoonDays', 7),
  );

  final double collectedAmount;
  final int collectedCount;
  final double overdueAmount;
  final int overdueCount;
  final double dueSoonAmount;
  final int dueSoonCount;
  final int dueSoonDays;
}

/// Saha ekibi satırı (sahip / müdür / satış müdürü; saha temsilcisi yalnızca kendi satırını alır).
@immutable
class StatsTeamMember {
  const StatsTeamMember({
    this.userId,
    required this.name,
    this.forms = 0,
    this.converted = 0,
    this.liters = 0,
  });

  factory StatsTeamMember.fromJson(JsonReader r) => StatsTeamMember(
    userId: r.nonEmpty('userId'),
    name: r.nonEmpty('name') ?? 'Temsilci',
    forms: r.integer('forms'),
    converted: r.integer('converted'),
    liters: r.dec('liters'),
  );

  /// Kullanıcı kimliği (sunucuda metin; sayı gelirse metne çevrilir).
  final String? userId;
  final String name;
  final int forms;
  final int converted;
  final double liters;

  /// Siparişe dönüşen / form (form yoksa null).
  double? get conversion => forms > 0 ? converted / forms : null;
}

/// Limitine yaklaşan cari.
@immutable
class StatsNearLimit {
  const StatsNearLimit({
    required this.customerId,
    required this.title,
    this.usageRate = 0,
  });

  factory StatsNearLimit.fromJson(JsonReader r) => StatsNearLimit(
    customerId: r.integer('customerId'),
    title: r.nonEmpty('title') ?? 'Cari',
    usageRate: r.dec('usageRate'),
  );

  final int customerId;
  final String title;
  final double usageRate;
}

/// Limit riski (yalnızca carileri görebilen kullanıcıya gelir).
@immutable
class StatsRisk {
  const StatsRisk({this.nearLimitCount = 0, this.nearLimit = const []});

  factory StatsRisk.fromJson(JsonReader r) {
    final rows = List<StatsNearLimit>.unmodifiable(
      r.list('nearLimit', StatsNearLimit.fromJson),
    );
    return StatsRisk(
      nearLimitCount: r.intOrNull('nearLimitCount') ?? rows.length,
      nearLimit: rows,
    );
  }

  final int nearLimitCount;
  final List<StatsNearLimit> nearLimit;
}

/// Bayi bölüm anahtarları (`failedSections` ile aynı adlar).
abstract final class StatsSections {
  static const sales = 'sales';
  static const spending = 'spending';
  static const months = 'months';
  static const products = 'products';
  static const topCustomers = 'topCustomers';
  static const funnel = 'funnel';
  static const deliveries = 'deliveries';
  static const collections = 'collections';
  static const team = 'team';
  static const risk = 'risk';
  static const stations = 'stations';
  static const deliveryPoints = 'deliveryPoints';
  static const orders = 'orders';
  static const limits = 'limits';
}

/// `GET stats/bayi` (spec R1 §4.1). Eksik ya da null bölüm null / boş liste olur; bilinmeyen anahtarlar
/// yok sayılır. Kapsam: `station` (bayi geneli) ya da `own` (saha temsilcisinin portföyü).
@immutable
class BayiStats {
  const BayiStats({
    this.stationId,
    this.stationTitle,
    this.scope = 'station',
    this.generatedAt,
    required this.period,
    this.sales,
    this.months = const [],
    this.products = const [],
    this.topCustomers = const [],
    this.funnel,
    this.deliveries,
    this.collections,
    this.team = const [],
    this.risk,
    this.failedSections = const {},
  });

  factory BayiStats.fromJson(Object? json, {StatsPeriod? period}) {
    final r = JsonReader.of(json);
    return BayiStats(
      stationId: r.intOrNull('stationId'),
      stationTitle: r.nonEmpty('stationTitle'),
      scope: r.nonEmpty('scope') ?? 'station',
      generatedAt: r.dateUtc('generatedAt'),
      period: StatsPeriodInfo.fromJson(r.obj('period'), fallback: period),
      sales: r.objOrNull('sales') == null
          ? null
          : StatsSummary.fromJson(r.obj('sales')),
      months: List.unmodifiable(r.list('months', StatsMonth.fromJson)),
      products: List.unmodifiable(r.list('products', StatsProduct.fromJson)),
      topCustomers: List.unmodifiable(
        r.list('topCustomers', StatsTopCustomer.fromJson),
      ),
      funnel: r.objOrNull('funnel') == null
          ? null
          : StatsFunnel.fromJson(r.obj('funnel')),
      deliveries: r.objOrNull('deliveries') == null
          ? null
          : StatsDeliveries.fromJson(r.obj('deliveries')),
      collections: r.objOrNull('collections') == null
          ? null
          : StatsCollections.fromJson(r.obj('collections')),
      team: List.unmodifiable(r.list('team', StatsTeamMember.fromJson)),
      risk: r.objOrNull('risk') == null
          ? null
          : StatsRisk.fromJson(r.obj('risk')),
      failedSections: Set.unmodifiable(r.strings('failedSections')),
    );
  }

  final int? stationId;
  final String? stationTitle;

  /// `station` ya da `own`.
  final String scope;
  final DateTime? generatedAt;
  final StatsPeriodInfo period;
  final StatsSummary? sales;
  final List<StatsMonth> months;
  final List<StatsProduct> products;
  final List<StatsTopCustomer> topCustomers;
  final StatsFunnel? funnel;
  final StatsDeliveries? deliveries;
  final StatsCollections? collections;
  final List<StatsTeamMember> team;
  final StatsRisk? risk;
  final Set<String> failedSections;

  /// Saha temsilcisinin kendi portföyü.
  bool get isOwn => scope == 'own';

  /// Gösterilecek hiçbir bölüm yok.
  bool get isBlank =>
      sales == null &&
      months.isEmpty &&
      products.isEmpty &&
      topCustomers.isEmpty &&
      funnel == null &&
      deliveries == null &&
      collections == null &&
      team.isEmpty &&
      risk == null;
}

/// Bayi payı (müşteri: hangi bayiden ne kadar).
@immutable
class StatsStationShare {
  const StatsStationShare({
    required this.stationId,
    required this.title,
    this.liters = 0,
    this.amount = 0,
    this.share = 0,
  });

  factory StatsStationShare.fromJson(JsonReader r) => StatsStationShare(
    stationId: r.integer('stationId'),
    title: r.nonEmpty('title') ?? r.nonEmpty('stationTitle') ?? 'Bayi',
    liters: r.dec('liters'),
    amount: r.dec('amount'),
    share: r.dec('share'),
  );

  final int stationId;
  final String title;
  final double liters;
  final double amount;
  final double share;
}

/// Teslimat noktası payı.
@immutable
class StatsDeliveryPoint {
  const StatsDeliveryPoint({
    required this.deliveryPointId,
    required this.name,
    this.city,
    this.liters = 0,
    this.amount = 0,
    this.share = 0,
  });

  factory StatsDeliveryPoint.fromJson(JsonReader r) => StatsDeliveryPoint(
    deliveryPointId: r.integer('deliveryPointId'),
    name: r.nonEmpty('name') ?? 'Teslimat noktası',
    city: r.nonEmpty('city'),
    liters: r.dec('liters'),
    amount: r.dec('amount'),
    share: r.dec('share'),
  );

  final int deliveryPointId;
  final String name;
  final String? city;
  final double liters;
  final double amount;
  final double share;
}

/// Siparişlerin şu anki durumu (teslim edilen dönemlik).
@immutable
class StatsOrderStatus {
  const StatsOrderStatus({
    this.awaitingQuote = 0,
    this.awaitingDecision = 0,
    this.awaitingCompanyApproval = 0,
    this.inTransit = 0,
    this.delivered = 0,
    this.disputed = 0,
  });

  factory StatsOrderStatus.fromJson(JsonReader r) => StatsOrderStatus(
    awaitingQuote: r.integer('awaitingQuote'),
    awaitingDecision: r.integer('awaitingDecision'),
    awaitingCompanyApproval: r.integer('awaitingCompanyApproval'),
    inTransit: r.integer('inTransit'),
    delivered: r.integer('delivered'),
    disputed: r.integer('disputed'),
  );

  final int awaitingQuote;
  final int awaitingDecision;
  final int awaitingCompanyApproval;
  final int inTransit;
  final int delivered;
  final int disputed;

  /// Açık siparişler (teklif, karar, şirket onayı, yolda).
  int get open =>
      awaitingQuote + awaitingDecision + awaitingCompanyApproval + inTransit;
}

/// Bayideki limit kullanımı. [limit] null = limitsiz.
@immutable
class StatsLimit {
  const StatsLimit({
    required this.stationId,
    required this.stationTitle,
    this.limit,
    this.used = 0,
    this.available,
    this.usageRate,
    this.unit,
  });

  factory StatsLimit.fromJson(JsonReader r) {
    final limit = r.decOrNull('limit');
    final used = r.dec('used');
    return StatsLimit(
      stationId: r.integer('stationId'),
      stationTitle: r.nonEmpty('stationTitle') ?? r.nonEmpty('title') ?? 'Bayi',
      limit: limit,
      used: used,
      available:
          r.decOrNull('available') ??
          (limit == null ? null : (limit - used).clamp(0.0, double.infinity)),
      usageRate:
          r.decOrNull('usageRate') ??
          (limit == null || limit <= 0 ? null : used / limit),
      unit: r.nonEmpty('unit'),
    );
  }

  final int stationId;
  final String stationTitle;
  final double? limit;
  final double used;
  final double? available;
  final double? usageRate;

  /// `L` ise litre limiti (yoksa tutar).
  final String? unit;

  bool get isUnlimited => limit == null;
  bool get isLiters => unit == 'L';
}

/// `GET stats/customer` (spec R1 §4.2).
@immutable
class CustomerStats {
  const CustomerStats({
    this.customerId,
    this.customerTitle,
    this.generatedAt,
    required this.period,
    this.spending,
    this.months = const [],
    this.products = const [],
    this.stations = const [],
    this.deliveryPoints = const [],
    this.orders,
    this.limits = const [],
    this.failedSections = const {},
  });

  factory CustomerStats.fromJson(Object? json, {StatsPeriod? period}) {
    final r = JsonReader.of(json);
    return CustomerStats(
      customerId: r.intOrNull('customerId'),
      customerTitle: r.nonEmpty('customerTitle'),
      generatedAt: r.dateUtc('generatedAt'),
      period: StatsPeriodInfo.fromJson(r.obj('period'), fallback: period),
      spending: r.objOrNull('spending') == null
          ? null
          : StatsSummary.fromJson(r.obj('spending')),
      months: List.unmodifiable(r.list('months', StatsMonth.fromJson)),
      products: List.unmodifiable(r.list('products', StatsProduct.fromJson)),
      stations: List.unmodifiable(
        r.list('stations', StatsStationShare.fromJson),
      ),
      deliveryPoints: List.unmodifiable(
        r.list('deliveryPoints', StatsDeliveryPoint.fromJson),
      ),
      orders: r.objOrNull('orders') == null
          ? null
          : StatsOrderStatus.fromJson(r.obj('orders')),
      limits: List.unmodifiable(r.list('limits', StatsLimit.fromJson)),
      failedSections: Set.unmodifiable(r.strings('failedSections')),
    );
  }

  final int? customerId;
  final String? customerTitle;
  final DateTime? generatedAt;
  final StatsPeriodInfo period;
  final StatsSummary? spending;
  final List<StatsMonth> months;
  final List<StatsProduct> products;
  final List<StatsStationShare> stations;
  final List<StatsDeliveryPoint> deliveryPoints;
  final StatsOrderStatus? orders;
  final List<StatsLimit> limits;
  final Set<String> failedSections;

  bool get isBlank =>
      spending == null &&
      months.isEmpty &&
      products.isEmpty &&
      stations.isEmpty &&
      deliveryPoints.isEmpty &&
      orders == null &&
      limits.isEmpty;
}
