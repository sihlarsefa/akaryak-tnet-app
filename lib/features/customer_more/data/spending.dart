import 'package:flutter/foundation.dart';

import '../../../core/models/json.dart';
import '../../../core/utils/format.dart';

/// Harcama raporunda bir ay (`SpendingMonthDto`; boş aylar sunucuda sıfırla doldurulur).
@immutable
class SpendingMonth {
  const SpendingMonth({
    required this.year,
    required this.month,
    this.orderCount = 0,
    this.liters = 0,
    this.amount = 0,
    this.avgUnitPrice,
    this.shortLabel,
    this.longLabel,
  });

  factory SpendingMonth.fromJson(JsonReader r) => SpendingMonth(
    year: r.integer('year'),
    month: r.integer('month', 1),
    orderCount: r.integer('orderCount'),
    liters: r.dec('liters'),
    amount: r.dec('amount'),
    avgUnitPrice: r.decOrNull('avgUnitPrice'),
    shortLabel: r.nonEmpty('shortLabel'),
    longLabel: r.nonEmpty('longLabel'),
  );

  final int year;
  final int month;
  final int orderCount;
  final double liters;
  final double amount;
  final double? avgUnitPrice;
  final String? shortLabel;
  final String? longLabel;

  bool get _validMonth => month >= 1 && month <= 12;

  /// Eksen kısaltması: `Eki`.
  String get abbrev => _validMonth ? Fmt.monthShort[month - 1] : '';

  /// `Ekim 2026`.
  String get label =>
      longLabel ?? (_validMonth ? '${Fmt.monthNames[month - 1]} $year' : '');
}

/// Ürün / teslimat noktası / bayi kırılımında bir satır (`SpendingBucketDto`).
@immutable
class SpendingBucket {
  const SpendingBucket({
    required this.id,
    required this.name,
    this.extra,
    this.orderCount = 0,
    this.liters = 0,
    this.amount = 0,
    this.amountShare = 0,
    this.avgUnitPrice,
  });

  factory SpendingBucket.fromJson(JsonReader r) => SpendingBucket(
    id: r.integer('id'),
    name: r.nonEmpty('name') ?? Fmt.dash,
    extra: r.nonEmpty('extra'),
    orderCount: r.integer('orderCount'),
    liters: r.dec('liters'),
    amount: r.dec('amount'),
    amountShare: r.dec('amountShare'),
    avgUnitPrice: r.decOrNull('avgUnitPrice'),
  );

  final int id;
  final String name;

  /// Kod ya da il (ikincil metin).
  final String? extra;
  final int orderCount;
  final double liters;
  final double amount;

  /// Tutar payı (%), sunucudan.
  final double amountShare;
  final double? avgUnitPrice;
}

/// `GET customers/me/spending` (`SpendingReportDto`). Yalnızca sunucu toplamları gösterilir.
@immutable
class SpendingReport {
  const SpendingReport({
    this.fromDate,
    this.toDate,
    this.months = const [],
    this.byProduct = const [],
    this.byDeliveryPoint = const [],
    this.byStation = const [],
    this.truncated = false,
    this.totalOrders = 0,
    this.totalLiters = 0,
    this.totalAmount = 0,
    this.avgUnitPrice,
  });

  factory SpendingReport.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return SpendingReport(
      fromDate: r.date('fromDate'),
      toDate: r.date('toDate'),
      months: List.unmodifiable(r.list('months', SpendingMonth.fromJson)),
      byProduct: List.unmodifiable(
        r.list('byProduct', SpendingBucket.fromJson),
      ),
      byDeliveryPoint: List.unmodifiable(
        r.list('byDeliveryPoint', SpendingBucket.fromJson),
      ),
      byStation: List.unmodifiable(
        r.list('byStation', SpendingBucket.fromJson),
      ),
      truncated: r.boolean('truncated'),
      totalOrders: r.integer('totalOrders'),
      totalLiters: r.dec('totalLiters'),
      totalAmount: r.dec('totalAmount'),
      avgUnitPrice: r.decOrNull('avgUnitPrice'),
    );
  }

  final DateTime? fromDate;
  final DateTime? toDate;
  final List<SpendingMonth> months;
  final List<SpendingBucket> byProduct;
  final List<SpendingBucket> byDeliveryPoint;
  final List<SpendingBucket> byStation;
  final bool truncated;
  final int totalOrders;
  final double totalLiters;
  final double totalAmount;
  final double? avgUnitPrice;

  bool get isEmpty => totalOrders == 0;
}

/// Grafik dilimleri: en fazla [limit] kırılım + "Diğer" (kalanların sunucu değerleri toplanır).
List<SpendingBucket> topBuckets(List<SpendingBucket> all, {int limit = 5}) {
  if (all.length <= limit + 1) return all;
  final head = all.take(limit).toList();
  final rest = all.skip(limit);
  var orders = 0;
  var liters = 0.0;
  var amount = 0.0;
  var share = 0.0;
  for (final b in rest) {
    orders += b.orderCount;
    liters += b.liters;
    amount += b.amount;
    share += b.amountShare;
  }
  return [
    ...head,
    SpendingBucket(
      id: -1,
      name: 'Diğer',
      extra: '${rest.length} kalem',
      orderCount: orders,
      liters: liters,
      amount: amount,
      amountShare: double.parse(share.toStringAsFixed(1)),
      avgUnitPrice: liters > 0
          ? double.parse((amount / liters).toStringAsFixed(4))
          : null,
    ),
  ];
}
