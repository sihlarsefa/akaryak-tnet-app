import 'package:flutter/foundation.dart';

import 'enums.dart';
import 'json.dart';

/// Panel sipariş satırı (`DashboardOrderRowDto`). [msLeft] sunucuda hesaplanır (saat diliminden bağımsız).
@immutable
class DashboardOrderRow {
  const DashboardOrderRow({
    required this.orderId,
    required this.orderNumber,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.expiresAt,
    this.requestedDeliveryDate,
    required this.quantityLiters,
    this.productName,
    this.customerId = 0,
    this.customerTitle,
    this.stationId = 0,
    this.stationTitle,
    this.deliveryPointName,
    this.deliveryCity,
    this.latestVersion,
    this.latestUnitPriceTry,
    this.latestTotalAmountTry,
    this.latestDeliveryDate,
    this.revisionNote,
    this.financeStatus = OrderFinanceStatus.notRequired,
    this.msLeft = 0,
    this.receivedAt,
  });

  factory DashboardOrderRow.fromJson(JsonReader r) => DashboardOrderRow(
    orderId: r.integer('orderId'),
    orderNumber: r.str('orderNumber'),
    status: r.enumOf('status', OrderStatus.fromCode),
    createdAt: r.dateTr('createdAt'),
    updatedAt: r.dateTr('updatedAt'),
    expiresAt: r.dateTr('expiresAt'),
    requestedDeliveryDate: r.dateTr('requestedDeliveryDate'),
    quantityLiters: r.dec('quantityLiters'),
    productName: r.nonEmpty('productName'),
    customerId: r.integer('customerId'),
    customerTitle: r.nonEmpty('customerTitle'),
    stationId: r.integer('stationId'),
    stationTitle: r.nonEmpty('stationTitle'),
    deliveryPointName: r.nonEmpty('deliveryPointName'),
    deliveryCity: r.nonEmpty('deliveryCity'),
    latestVersion: r.intOrNull('latestVersion'),
    latestUnitPriceTry: r.decOrNull('latestUnitPriceTry'),
    latestTotalAmountTry: r.decOrNull('latestTotalAmountTry'),
    latestDeliveryDate: r.dateTr('latestDeliveryDate'),
    revisionNote: r.nonEmpty('revisionNote'),
    financeStatus: r.enumOf('financeStatus', OrderFinanceStatus.fromCode),
    msLeft: r.integer('msLeft'),
    receivedAt: DateTime.now().toUtc(),
  );

  final int orderId;
  final String orderNumber;
  final OrderStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? expiresAt;
  final DateTime? requestedDeliveryDate;
  final double quantityLiters;
  final String? productName;
  final int customerId;
  final String? customerTitle;
  final int stationId;
  final String? stationTitle;
  final String? deliveryPointName;
  final String? deliveryCity;
  final int? latestVersion;
  final double? latestUnitPriceTry;
  final double? latestTotalAmountTry;
  final DateTime? latestDeliveryDate;
  final String? revisionNote;

  /// Finans durumu: müşterinin teklif onayı limit aşımıyla bayinin finans onayına gittiyse sipariş
  /// "Onay bekliyor"da kalır ama karar finansındır (müşterinin değil; `OrderService`
  /// `RouteLimitOverrunToFinanceAsync`).
  final OrderFinanceStatus financeStatus;

  /// Süre sonuna kalan milisaniye (yanıt anında). ≤ 0: doldu.
  final int msLeft;

  /// Yanıtın alındığı an ([remaining] hesabı için).
  final DateTime? receivedAt;

  /// Şu an kalan süre (sunucu [msLeft] değerinden, cihaz saatine bağımlı olmadan).
  Duration remaining({DateTime? now}) {
    final start = receivedAt ?? DateTime.now().toUtc();
    final elapsed = (now ?? DateTime.now().toUtc()).difference(start);
    return Duration(milliseconds: msLeft) - elapsed;
  }
}

/// Panel sevkiyat satırı (`DashboardShipmentRowDto`).
@immutable
class DashboardShipmentRow {
  const DashboardShipmentRow({
    required this.shipmentId,
    required this.orderId,
    required this.orderNumber,
    required this.status,
    this.scheduledAt,
    required this.plannedLiters,
    this.deliveredLiters,
    this.deliveredAt,
    this.vehiclePlate,
    this.driverName,
    this.deliveryDocumentNo,
    this.disputeNote,
    this.updatedAt,
    this.customerId = 0,
    this.customerTitle,
    this.stationId = 0,
    this.stationTitle,
    this.productName,
    this.deliveryPointName,
    this.deliveryCity,
    this.isOverdue = false,
  });

  factory DashboardShipmentRow.fromJson(JsonReader r) => DashboardShipmentRow(
    shipmentId: r.integer('shipmentId'),
    orderId: r.integer('orderId'),
    orderNumber: r.str('orderNumber'),
    status: r.enumOf('status', ShipmentStatus.fromCode),
    scheduledAt: r.dateTr('scheduledAt'),
    plannedLiters: r.dec('plannedLiters'),
    deliveredLiters: r.decOrNull('deliveredLiters'),
    deliveredAt: r.dateTr('deliveredAt'),
    vehiclePlate: r.nonEmpty('vehiclePlate'),
    driverName: r.nonEmpty('driverName'),
    deliveryDocumentNo: r.nonEmpty('deliveryDocumentNo'),
    disputeNote: r.nonEmpty('disputeNote'),
    updatedAt: r.dateTr('updatedAt'),
    customerId: r.integer('customerId'),
    customerTitle: r.nonEmpty('customerTitle'),
    stationId: r.integer('stationId'),
    stationTitle: r.nonEmpty('stationTitle'),
    productName: r.nonEmpty('productName'),
    deliveryPointName: r.nonEmpty('deliveryPointName'),
    deliveryCity: r.nonEmpty('deliveryCity'),
    isOverdue: r.boolean('isOverdue'),
  );

  final int shipmentId;
  final int orderId;
  final String orderNumber;
  final ShipmentStatus status;
  final DateTime? scheduledAt;
  final double plannedLiters;
  final double? deliveredLiters;
  final DateTime? deliveredAt;
  final String? vehiclePlate;
  final String? driverName;
  final String? deliveryDocumentNo;
  final String? disputeNote;
  final DateTime? updatedAt;
  final int customerId;
  final String? customerTitle;
  final int stationId;
  final String? stationTitle;
  final String? productName;
  final String? deliveryPointName;
  final String? deliveryCity;

  /// Planlı ama planlanan gün geçmiş (yola çıkmamış).
  final bool isOverdue;
}

/// Günlük toplam (`DashboardDayDto`).
@immutable
class DashboardDay {
  const DashboardDay({
    required this.day,
    this.orders = 0,
    this.liters = 0,
    this.amount = 0,
  });

  factory DashboardDay.fromJson(JsonReader r) => DashboardDay(
    day: r.dateTr('day') ?? DateTime.now().toUtc(),
    orders: r.integer('orders'),
    liters: r.dec('liters'),
    amount: r.dec('amount'),
  );

  final DateTime day;
  final int orders;
  final double liters;
  final double amount;
}

/// En çok alan cari (`DashboardTopCustomerDto`).
@immutable
class DashboardTopCustomer {
  const DashboardTopCustomer({
    required this.customerId,
    required this.customerTitle,
    this.orders = 0,
    this.liters = 0,
    this.amount = 0,
  });

  factory DashboardTopCustomer.fromJson(JsonReader r) => DashboardTopCustomer(
    customerId: r.integer('customerId'),
    customerTitle: r.str('customerTitle'),
    orders: r.integer('orders'),
    liters: r.dec('liters'),
    amount: r.dec('amount'),
  );

  final int customerId;
  final String customerTitle;
  final int orders;
  final double liters;
  final double amount;
}

/// Son sipariş (`DashboardLastOrderDto`), hızlı tekrar sipariş için.
@immutable
class DashboardLastOrder {
  const DashboardLastOrder({
    required this.orderId,
    required this.orderNumber,
    required this.status,
    this.createdAt,
    required this.quantityLiters,
    this.productName,
    this.stationTitle,
    this.deliveryPointName,
  });

  factory DashboardLastOrder.fromJson(JsonReader r) => DashboardLastOrder(
    orderId: r.integer('orderId'),
    orderNumber: r.str('orderNumber'),
    status: r.enumOf('status', OrderStatus.fromCode),
    createdAt: r.dateTr('createdAt'),
    quantityLiters: r.dec('quantityLiters'),
    productName: r.nonEmpty('productName'),
    stationTitle: r.nonEmpty('stationTitle'),
    deliveryPointName: r.nonEmpty('deliveryPointName'),
  );

  final int orderId;
  final String orderNumber;
  final OrderStatus status;
  final DateTime? createdAt;
  final double quantityLiters;
  final String? productName;
  final String? stationTitle;
  final String? deliveryPointName;
}

/// Bayi–cari limit kullanımı (`DashboardLimitUsageDto`).
@immutable
class DashboardLimitUsage {
  const DashboardLimitUsage({
    required this.linkId,
    this.stationId = 0,
    this.stationTitle = '',
    this.customerId = 0,
    this.customerTitle = '',
    this.limitType,
    this.limitPeriod,
    this.limitAmount,
    this.hasLimit = false,
    this.isUnlimited = false,
    this.unit = 'TL',
    this.used = 0,
    this.remaining,
    this.usedPercent = 0,
    this.periodLabel = '',
  });

  factory DashboardLimitUsage.fromJson(JsonReader r) => DashboardLimitUsage(
    linkId: r.integer('linkId'),
    stationId: r.integer('stationId'),
    stationTitle: r.str('stationTitle'),
    customerId: r.integer('customerId'),
    customerTitle: r.str('customerTitle'),
    limitType: r.nonEmpty('limitType'),
    limitPeriod: r.nonEmpty('limitPeriod'),
    limitAmount: r.decOrNull('limitAmount'),
    hasLimit: r.boolean('hasLimit'),
    isUnlimited: r.boolean('isUnlimited'),
    unit: r.str('unit', 'TL'),
    used: r.dec('used'),
    remaining: r.decOrNull('remaining'),
    usedPercent: r.dec('usedPercent'),
    periodLabel: r.str('periodLabel'),
  );

  final int linkId;
  final int stationId;
  final String stationTitle;
  final int customerId;
  final String customerTitle;
  final String? limitType;
  final String? limitPeriod;
  final double? limitAmount;
  final bool hasLimit;
  final bool isUnlimited;

  /// `L` ya da `TL`.
  final String unit;
  final double used;
  final double? remaining;

  /// Kırpılmamış yüzde (≥ 100 limit dolu).
  final double usedPercent;
  final String periodLabel;
}
