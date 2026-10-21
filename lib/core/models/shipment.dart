import 'package:flutter/foundation.dart';

import 'enums.dart';
import 'json.dart';

/// Sevkiyat (`ShipmentDto`, sipariş teslimat özetinde).
@immutable
class Shipment {
  const Shipment({
    required this.id,
    required this.plannedLiters,
    this.deliveredLiters,
    this.vehiclePlate = '',
    this.driverName = '',
    this.scheduledAt,
    this.deliveryDocumentNo,
    required this.status,
    this.disputeNote,
  });

  factory Shipment.fromJson(JsonReader r) => Shipment(
    id: r.integer('id'),
    plannedLiters: r.dec('plannedLiters'),
    deliveredLiters: r.decOrNull('deliveredLiters'),
    vehiclePlate: r.str('vehiclePlate'),
    driverName: r.str('driverName'),
    scheduledAt: r.dateTr('scheduledAt'),
    deliveryDocumentNo: r.nonEmpty('deliveryDocumentNo'),
    status: r.enumOf('status', ShipmentStatus.fromCode),
    disputeNote: r.nonEmpty('disputeNote'),
  );

  final int id;
  final double plannedLiters;
  final double? deliveredLiters;
  final String vehiclePlate;
  final String driverName;
  final DateTime? scheduledAt;
  final String? deliveryDocumentNo;
  final ShipmentStatus status;
  final String? disputeNote;

  /// Sevkiyat no: `SVK-00001234`.
  String get code => 'SVK-${id.toString().padLeft(8, '0')}';
}

/// Siparişin teslimat özeti (`FulfillmentDto`, `GET shipments/order/{orderId}`).
@immutable
class Fulfillment {
  const Fulfillment({
    required this.orderId,
    required this.orderNumber,
    this.deliveryAddress = '',
    required this.orderedLiters,
    required this.acceptedLiters,
    this.canManage = false,
    this.canAccept = false,
    this.isOpen = false,
    this.shipments = const [],
  });

  factory Fulfillment.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return Fulfillment(
      orderId: r.integer('orderId'),
      orderNumber: r.str('orderNumber'),
      deliveryAddress: r.str('deliveryAddress'),
      orderedLiters: r.dec('orderedLiters'),
      acceptedLiters: r.dec('acceptedLiters'),
      canManage: r.boolean('canManage'),
      canAccept: r.boolean('canAccept'),
      isOpen: r.boolean('isOpen'),
      shipments: List.unmodifiable(r.list('shipments', Shipment.fromJson)),
    );
  }

  final int orderId;
  final String orderNumber;
  final String deliveryAddress;
  final double orderedLiters;
  final double acceptedLiters;
  final bool canManage;
  final bool canAccept;
  final bool isOpen;
  final List<Shipment> shipments;

  /// Planlanmamış (kalan) litre: sipariş − (iptal dışındaki planlar).
  double get remainingToPlan {
    final planned = shipments
        .where((s) => s.status != ShipmentStatus.cancelled)
        .fold<double>(
          0,
          (sum, s) => sum + (s.deliveredLiters ?? s.plannedLiters),
        );
    final rest = orderedLiters - planned;
    return rest < 0 ? 0 : rest;
  }
}

/// Sevkiyat listesi satırı (`ShipmentListItemDto`). `createdAt` UTC; diğer tarihler Türkiye yerel saati.
@immutable
class ShipmentListItem {
  const ShipmentListItem({
    required this.id,
    required this.orderId,
    required this.orderNumber,
    this.stationId = 0,
    this.stationName = '',
    this.customerId = 0,
    this.customerName = '',
    this.customerCity = '',
    this.productId = 0,
    this.productName = '',
    required this.plannedLiters,
    this.deliveredLiters,
    this.vehiclePlate = '',
    this.driverName = '',
    this.driverUserId,
    this.scheduledAt,
    this.deliveredAt,
    this.acceptedAt,
    this.createdAt,
    this.deliveryDocumentNo,
    required this.status,
    this.disputeNote,
    this.orderStatus = OrderStatus.unknown,
    this.deliveryAddress,
    this.deliveryPointName,
    this.deliveryCity,
    this.deliveryDistrict,
    this.requestedDeliveryDate,
  });

  factory ShipmentListItem.fromJson(JsonReader r) => ShipmentListItem(
    id: r.integer('id'),
    orderId: r.integer('orderId'),
    orderNumber: r.str('orderNumber'),
    stationId: r.integer('stationId'),
    stationName: r.str('stationName'),
    customerId: r.integer('customerId'),
    customerName: r.str('customerName'),
    customerCity: r.str('customerCity'),
    productId: r.integer('productId'),
    productName: r.str('productName'),
    plannedLiters: r.dec('plannedLiters'),
    deliveredLiters: r.decOrNull('deliveredLiters'),
    vehiclePlate: r.str('vehiclePlate'),
    driverName: r.str('driverName'),
    driverUserId: r.nonEmpty('driverUserId'),
    scheduledAt: r.dateTr('scheduledAt'),
    deliveredAt: r.dateTr('deliveredAt'),
    acceptedAt: r.dateTr('acceptedAt'),
    createdAt: r.dateUtc('createdAt'),
    deliveryDocumentNo: r.nonEmpty('deliveryDocumentNo'),
    status: r.enumOf('status', ShipmentStatus.fromCode),
    disputeNote: r.nonEmpty('disputeNote'),
    orderStatus: r.enumOf('orderStatus', OrderStatus.fromCode),
    deliveryAddress: r.nonEmpty('deliveryAddress'),
    deliveryPointName: r.nonEmpty('deliveryPointName'),
    deliveryCity: r.nonEmpty('deliveryCity'),
    deliveryDistrict: r.nonEmpty('deliveryDistrict'),
    requestedDeliveryDate: r.dateTr('requestedDeliveryDate'),
  );

  final int id;
  final int orderId;
  final String orderNumber;
  final int stationId;
  final String stationName;
  final int customerId;
  final String customerName;
  final String customerCity;
  final int productId;
  final String productName;
  final double plannedLiters;
  final double? deliveredLiters;
  final String vehiclePlate;
  final String driverName;
  final String? driverUserId;
  final DateTime? scheduledAt;
  final DateTime? deliveredAt;
  final DateTime? acceptedAt;
  final DateTime? createdAt;
  final String? deliveryDocumentNo;
  final ShipmentStatus status;
  final String? disputeNote;
  final OrderStatus orderStatus;
  final String? deliveryAddress;
  final String? deliveryPointName;
  final String? deliveryCity;
  final String? deliveryDistrict;
  final DateTime? requestedDeliveryDate;

  /// Sevkiyat no: `SVK-00001234`.
  String get code => 'SVK-${id.toString().padLeft(8, '0')}';

  /// Teslim edilen − planlanan (L).
  double? get differenceLiters =>
      deliveredLiters == null ? null : deliveredLiters! - plannedLiters;
}

/// Sevkiyat sayaçları (`ShipmentStatsDto`).
@immutable
class ShipmentStats {
  const ShipmentStats({
    this.planned = 0,
    this.inTransit = 0,
    this.reported = 0,
    this.accepted = 0,
    this.disputed = 0,
  });

  factory ShipmentStats.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return ShipmentStats(
      planned: r.integer('planned'),
      inTransit: r.integer('inTransit'),
      reported: r.integer('reported'),
      accepted: r.integer('accepted'),
      disputed: r.integer('disputed'),
    );
  }

  final int planned;
  final int inTransit;
  final int reported;
  final int accepted;
  final int disputed;

  int get active => planned + inTransit + reported + disputed;
}
