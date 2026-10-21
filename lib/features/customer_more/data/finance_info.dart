import 'package:flutter/foundation.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';

/// Bayi bağlantısında sipariş verilebilirlik (`CustomerOrderingStatusDto`).
@immutable
class OrderingStatus {
  const OrderingStatus({
    this.stationId = 0,
    this.canOrder = true,
    this.blockReason,
    this.isGrandfathered = false,
    this.profileStatus,
    this.infoRequested = false,
    this.openApprovalRequestId,
  });

  factory OrderingStatus.fromJson(JsonReader r) => OrderingStatus(
    stationId: r.integer('stationId'),
    canOrder: r.boolean('canOrder', true),
    blockReason: r.nonEmpty('blockReason'),
    isGrandfathered: r.boolean('isGrandfathered'),
    profileStatus: r.has('profileStatus')
        ? r.enumOf('profileStatus', FinanceProfileStatus.fromCode)
        : null,
    infoRequested: r.boolean('infoRequested'),
    openApprovalRequestId: r.intOrNull('openApprovalRequestId'),
  );

  final int stationId;
  final bool canOrder;
  final String? blockReason;
  final bool isGrandfathered;
  final FinanceProfileStatus? profileStatus;
  final bool infoRequested;
  final int? openApprovalRequestId;
}

/// Bir bayideki finans durumu (`CustomerFinanceInfoItemDto`).
@immutable
class FinanceInfoLink {
  const FinanceInfoLink({
    required this.stationId,
    required this.stationTitle,
    this.status = const OrderingStatus(),
    this.requestId,
    this.requestStatus,
    this.requestStatusLabel,
    this.infoNote,
    this.requiredKind,
    this.requiredKindLabel,
    this.requestedAt,
    this.canReply = false,
  });

  factory FinanceInfoLink.fromJson(JsonReader r) => FinanceInfoLink(
    stationId: r.integer('stationId'),
    stationTitle: r.str('stationTitle'),
    status: OrderingStatus.fromJson(r.obj('status')),
    requestId: r.intOrNull('requestId'),
    requestStatus: r.has('requestStatus')
        ? r.enumOf('requestStatus', ApprovalStatus.fromCode)
        : null,
    requestStatusLabel: r.nonEmpty('requestStatusLabel'),
    infoNote: r.nonEmpty('infoNote'),
    requiredKind: r.has('requiredKind')
        ? r.enumOf('requiredKind', AttachmentKind.fromCode)
        : null,
    requiredKindLabel: r.nonEmpty('requiredKindLabel'),
    requestedAt: r.dateUtc('requestedAt'),
    canReply: r.boolean('canReply'),
  );

  final int stationId;
  final String stationTitle;
  final OrderingStatus status;
  final int? requestId;
  final ApprovalStatus? requestStatus;
  final String? requestStatusLabel;
  final String? infoNote;
  final AttachmentKind? requiredKind;
  final String? requiredKindLabel;
  final DateTime? requestedAt;
  final bool canReply;

  /// Finans yanıt bekliyor (ek bilgi istendi).
  bool get needsReply =>
      canReply ||
      requestStatus == ApprovalStatus.infoRequested ||
      status.infoRequested;

  /// Finans inceliyor (karar bekleniyor).
  bool get inReview =>
      !needsReply &&
      (requestStatus == ApprovalStatus.pending ||
          status.profileStatus == FinanceProfileStatus.pending);

  String? get kindLabel => requiredKindLabel ?? requiredKind?.label;
}

/// Finansın ek bilgi istediği sipariş (`CustomerFinanceInfoOrderDto`).
@immutable
class FinanceInfoOrder {
  const FinanceInfoOrder({
    required this.orderId,
    required this.orderNumber,
    this.stationTitle = '',
    required this.requestId,
    this.infoNote,
    this.requiredKind,
    this.requiredKindLabel,
    this.createdAt,
  });

  factory FinanceInfoOrder.fromJson(JsonReader r) => FinanceInfoOrder(
    orderId: r.integer('orderId'),
    orderNumber: r.str('orderNumber'),
    stationTitle: r.str('stationTitle'),
    requestId: r.integer('requestId'),
    infoNote: r.nonEmpty('infoNote'),
    requiredKind: r.has('requiredKind')
        ? r.enumOf('requiredKind', AttachmentKind.fromCode)
        : null,
    requiredKindLabel: r.nonEmpty('requiredKindLabel'),
    createdAt: r.dateTr('createdAt'),
  );

  final int orderId;
  final String orderNumber;
  final String stationTitle;
  final int requestId;
  final String? infoNote;
  final AttachmentKind? requiredKind;
  final String? requiredKindLabel;
  final DateTime? createdAt;

  String? get kindLabel => requiredKindLabel ?? requiredKind?.label;
}

/// `GET customers/me/finance-info` → `{links, orders}`.
@immutable
class FinanceInfo {
  const FinanceInfo({this.links = const [], this.orders = const []});

  factory FinanceInfo.fromJson(Object? json) {
    // Aşama 0 iskeleti dizi döndürüyordu (yalnızca bağlantılar).
    if (json is List) {
      return FinanceInfo(
        links: List.unmodifiable(
          JsonReader.parseList(json, FinanceInfoLink.fromJson),
        ),
      );
    }
    final r = JsonReader.of(json);
    return FinanceInfo(
      links: List.unmodifiable(r.list('links', FinanceInfoLink.fromJson)),
      orders: List.unmodifiable(r.list('orders', FinanceInfoOrder.fromJson)),
    );
  }

  final List<FinanceInfoLink> links;
  final List<FinanceInfoOrder> orders;

  int get pendingReplies =>
      links.where((l) => l.needsReply).length + orders.length;
}
