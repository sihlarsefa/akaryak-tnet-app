import 'package:flutter/foundation.dart';

import 'enums.dart';
import 'json.dart';

/// Sipariş liste satırı (`OrderListItemDto`). Tarihler Türkiye yerel saati (ofsetsiz).
@immutable
class OrderListItem {
  const OrderListItem({
    required this.id,
    required this.orderNumber,
    required this.status,
    this.statusDisplay,
    required this.quantityLiters,
    this.requestedDeliveryDate,
    this.expiresAt,
    this.createdAt,
    this.productName = '',
    this.customerTitle = '',
    this.stationTitle = '',
    this.deliveryPointName = '',
    this.latestUnitPriceTry,
    this.latestTotalAmountTry,
    this.latestRevisionNote,
  });

  factory OrderListItem.fromJson(JsonReader r) => OrderListItem(
    id: r.integer('id'),
    orderNumber: r.str('orderNumber'),
    status: r.enumOf('status', OrderStatus.fromCode),
    statusDisplay: r.nonEmpty('statusDisplay'),
    quantityLiters: r.dec('quantityLiters'),
    requestedDeliveryDate: r.dateTr('requestedDeliveryDate'),
    expiresAt: r.dateTr('expiresAt'),
    createdAt: r.dateTr('createdAt'),
    productName: r.str('productName'),
    customerTitle: r.str('customerTitle'),
    stationTitle: r.str('stationTitle'),
    deliveryPointName: r.str('deliveryPointName'),
    latestUnitPriceTry: r.decOrNull('latestUnitPriceTry'),
    latestTotalAmountTry: r.decOrNull('latestTotalAmountTry'),
    latestRevisionNote: r.nonEmpty('latestRevisionNote'),
  );

  final int id;
  final String orderNumber;
  final OrderStatus status;
  final String? statusDisplay;
  final double quantityLiters;
  final DateTime? requestedDeliveryDate;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final String productName;
  final String customerTitle;
  final String stationTitle;
  final String deliveryPointName;
  final double? latestUnitPriceTry;
  final double? latestTotalAmountTry;
  final String? latestRevisionNote;

  String get statusLabel => statusDisplay ?? status.label;
}

/// Teklif (`QuoteDto`).
@immutable
class Quote {
  const Quote({
    required this.id,
    required this.version,
    required this.unitPriceTry,
    required this.totalAmountTry,
    this.deliveryDate,
    this.revisionNote,
    this.isSelected = false,
    this.createdAt,
  });

  factory Quote.fromJson(JsonReader r) => Quote(
    id: r.integer('id'),
    version: r.integer('version', 1),
    unitPriceTry: r.dec('unitPriceTry'),
    totalAmountTry: r.dec('totalAmountTry'),
    deliveryDate: r.dateTr('deliveryDate'),
    revisionNote: r.nonEmpty('revisionNote'),
    isSelected: r.boolean('isSelected'),
    createdAt: r.dateTr('createdAt'),
  );

  final int id;
  final int version;
  final double unitPriceTry;
  final double totalAmountTry;
  final DateTime? deliveryDate;
  final String? revisionNote;
  final bool isSelected;
  final DateTime? createdAt;
}

/// Sipariş ayrıntısı (`OrderDetailDto`, `GET orders/{id}`).
@immutable
class OrderDetail extends OrderListItem {
  const OrderDetail({
    required super.id,
    required super.orderNumber,
    required super.status,
    super.statusDisplay,
    required super.quantityLiters,
    super.requestedDeliveryDate,
    super.expiresAt,
    super.createdAt,
    super.productName,
    super.customerTitle,
    super.stationTitle,
    super.deliveryPointName,
    super.latestUnitPriceTry,
    super.latestTotalAmountTry,
    super.latestRevisionNote,
    required this.customerId,
    required this.stationId,
    required this.productId,
    required this.deliveryPointId,
    this.deliveryAddress = '',
    this.quotes = const [],
    this.paymentMethodCode,
    this.paymentTermDays,
    this.paymentDueDate,
    this.paymentInstallments,
    this.paymentDetailJson,
    this.paymentStatus = PaymentStatus.none,
    this.paymentGroupKey,
    this.estimatedAmount,
    this.financeStatus = OrderFinanceStatus.notRequired,
    this.financeReasons,
    this.financeApprovalRequestId,
  });

  factory OrderDetail.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final base = OrderListItem.fromJson(r);
    return OrderDetail(
      id: base.id,
      orderNumber: base.orderNumber,
      status: base.status,
      statusDisplay: base.statusDisplay,
      quantityLiters: base.quantityLiters,
      requestedDeliveryDate: base.requestedDeliveryDate,
      expiresAt: base.expiresAt,
      createdAt: base.createdAt,
      productName: base.productName,
      customerTitle: base.customerTitle,
      stationTitle: base.stationTitle,
      deliveryPointName: base.deliveryPointName,
      latestUnitPriceTry: base.latestUnitPriceTry,
      latestTotalAmountTry: base.latestTotalAmountTry,
      latestRevisionNote: base.latestRevisionNote,
      customerId: r.integer('customerId'),
      stationId: r.integer('stationId'),
      productId: r.integer('productId'),
      deliveryPointId: r.integer('deliveryPointId'),
      deliveryAddress: r.str('deliveryAddress'),
      quotes: List.unmodifiable(r.list('quotes', Quote.fromJson)),
      paymentMethodCode: r.nonEmpty('paymentMethodCode'),
      paymentTermDays: r.intOrNull('paymentTermDays'),
      paymentDueDate: r.dateTr('paymentDueDate'),
      paymentInstallments: r.intOrNull('paymentInstallments'),
      paymentDetailJson: r.nonEmpty('paymentDetailJson'),
      paymentStatus: r.enumOf('paymentStatus', PaymentStatus.fromCode),
      paymentGroupKey: r.nonEmpty('paymentGroupKey'),
      estimatedAmount: r.decOrNull('estimatedAmount'),
      financeStatus: r.enumOf('financeStatus', OrderFinanceStatus.fromCode),
      financeReasons: r.nonEmpty('financeReasons'),
      financeApprovalRequestId: r.intOrNull('financeApprovalRequestId'),
    );
  }

  final int customerId;
  final int stationId;
  final int productId;
  final int deliveryPointId;
  final String deliveryAddress;
  final List<Quote> quotes;
  final String? paymentMethodCode;
  final int? paymentTermDays;
  final DateTime? paymentDueDate;
  final int? paymentInstallments;
  final String? paymentDetailJson;
  final PaymentStatus paymentStatus;
  final String? paymentGroupKey;
  final double? estimatedAmount;
  final OrderFinanceStatus financeStatus;
  final String? financeReasons;
  final int? financeApprovalRequestId;

  /// Geçerli (seçili ya da en son) teklif.
  Quote? get currentQuote {
    if (quotes.isEmpty) return null;
    for (final q in quotes) {
      if (q.isSelected) return q;
    }
    return quotes.reduce((a, b) => a.version >= b.version ? a : b);
  }
}

/// Sipariş durum geçmişi (`OrderTimelineItemDto`).
@immutable
class OrderTimelineItem {
  const OrderTimelineItem({
    required this.fromStatus,
    required this.toStatus,
    this.note,
    this.changedAt,
  });

  factory OrderTimelineItem.fromJson(JsonReader r) => OrderTimelineItem(
    fromStatus: r.enumOf('fromStatus', OrderStatus.fromCode),
    toStatus: r.enumOf('toStatus', OrderStatus.fromCode),
    note: r.nonEmpty('note'),
    changedAt: r.dateTr('changedAt'),
  );

  final OrderStatus fromStatus;
  final OrderStatus toStatus;
  final String? note;
  final DateTime? changedAt;
}

/// Sipariş oluşturma sonucu (`CreateOrderResultDto`).
@immutable
class CreateOrderResult {
  const CreateOrderResult({
    required this.orderId,
    required this.orderNumber,
    this.expiresAt,
    this.financeStatus = OrderFinanceStatus.notRequired,
    this.financeReasons,
    this.paymentMethodCode,
    this.paymentDueDate,
    this.estimatedAmount,
    this.paymentGroupKey,
  });

  factory CreateOrderResult.fromJson(JsonReader r) => CreateOrderResult(
    orderId: r.integer('orderId'),
    orderNumber: r.str('orderNumber'),
    expiresAt: r.dateTr('expiresAt'),
    financeStatus: r.enumOf('financeStatus', OrderFinanceStatus.fromCode),
    financeReasons: r.nonEmpty('financeReasons'),
    paymentMethodCode: r.nonEmpty('paymentMethodCode'),
    paymentDueDate: r.dateTr('paymentDueDate'),
    estimatedAmount: r.decOrNull('estimatedAmount'),
    paymentGroupKey: r.nonEmpty('paymentGroupKey'),
  );

  final int orderId;
  final String orderNumber;
  final DateTime? expiresAt;
  final OrderFinanceStatus financeStatus;
  final String? financeReasons;
  final String? paymentMethodCode;
  final DateTime? paymentDueDate;
  final double? estimatedAmount;
  final String? paymentGroupKey;
}
