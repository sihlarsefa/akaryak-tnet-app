import 'package:flutter/foundation.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';

/// Talep satırı ve onay sonucu (`CustomerOrderRequestLineDto`): oluşan sipariş ya da hata nedeni.
@immutable
class OrderRequestLine {
  const OrderRequestLine({
    this.stationId = 0,
    this.productId = 0,
    this.deliveryPointId = 0,
    required this.quantityLiters,
    this.requestedDeliveryDate,
    this.estimatedUnitPrice,
    this.orderId,
    this.orderNumber,
    this.error,
    this.stationTitle = '',
    this.productName = '',
    this.deliveryPointName = '',
  });

  factory OrderRequestLine.fromJson(JsonReader r) => OrderRequestLine(
    stationId: r.integer('stationId'),
    productId: r.integer('productId'),
    deliveryPointId: r.integer('deliveryPointId'),
    quantityLiters: r.dec('quantityLiters'),
    requestedDeliveryDate: r.dateTr('requestedDeliveryDate'),
    estimatedUnitPrice: r.decOrNull('estimatedUnitPrice'),
    orderId: r.intOrNull('orderId'),
    orderNumber: r.nonEmpty('orderNumber'),
    error: r.nonEmpty('error'),
    stationTitle: r.str('stationTitle'),
    productName: r.str('productName'),
    deliveryPointName: r.str('deliveryPointName'),
  );

  final int stationId;
  final int productId;
  final int deliveryPointId;
  final double quantityLiters;
  final DateTime? requestedDeliveryDate;
  final double? estimatedUnitPrice;
  final int? orderId;
  final String? orderNumber;
  final String? error;
  final String stationTitle;
  final String productName;
  final String deliveryPointName;

  bool get hasOrder => orderId != null && orderId! > 0;
  bool get failed => !hasOrder && error != null;
}

/// Şirket içi sipariş talebi (`CustomerOrderRequestDto`). `createdAt`, `decidedAt` UTC.
@immutable
class OrderRequest {
  const OrderRequest({
    required this.id,
    this.concurrencyToken,
    this.requestedByUserId = '',
    this.requestedByName = '',
    required this.status,
    this.statusLabel,
    this.totalLiters = 0,
    this.estimatedAmount,
    this.note,
    this.decidedByName,
    this.decidedAt,
    this.decisionNote,
    this.createdOrderIds = const [],
    this.createdAt,
    this.lines = const [],
    this.canDecide = false,
    this.canCancel = false,
    this.paymentMethodCode,
    this.paymentMethodName,
    this.paymentTermDays,
    this.paymentInstallments,
    this.paymentDisplay,
    this.paymentDetails = const [],
  });

  factory OrderRequest.fromJson(JsonReader r) => OrderRequest(
    id: r.integer('id'),
    concurrencyToken: r.nonEmpty('concurrencyToken'),
    requestedByUserId: r.str('requestedByUserId'),
    requestedByName: r.str('requestedByName'),
    status: r.enumOf('status', CustomerOrderRequestStatus.fromCode),
    statusLabel: r.nonEmpty('statusLabel'),
    totalLiters: r.dec('totalLiters'),
    estimatedAmount: r.decOrNull('estimatedAmount'),
    note: r.nonEmpty('note'),
    decidedByName: r.nonEmpty('decidedByName'),
    decidedAt: r.dateUtc('decidedAt'),
    decisionNote: r.nonEmpty('decisionNote'),
    createdOrderIds: List.unmodifiable(r.ints('createdOrderIds')),
    createdAt: r.dateUtc('createdAt'),
    lines: List.unmodifiable(r.list('lines', OrderRequestLine.fromJson)),
    canDecide: r.boolean('canDecide'),
    canCancel: r.boolean('canCancel'),
    paymentMethodCode: r.nonEmpty('paymentMethodCode'),
    paymentMethodName: r.nonEmpty('paymentMethodName'),
    paymentTermDays: r.intOrNull('paymentTermDays'),
    paymentInstallments: r.intOrNull('paymentInstallments'),
    paymentDisplay: r.nonEmpty('paymentDisplay'),
    paymentDetails: List.unmodifiable(
      r.list(
        'paymentDetails',
        (e) => (label: e.str('key'), value: e.str('value')),
      ),
    ),
  );

  final int id;
  final String? concurrencyToken;
  final String requestedByUserId;
  final String requestedByName;
  final CustomerOrderRequestStatus status;
  final String? statusLabel;
  final double totalLiters;
  final double? estimatedAmount;
  final String? note;
  final String? decidedByName;
  final DateTime? decidedAt;
  final String? decisionNote;
  final List<int> createdOrderIds;
  final DateTime? createdAt;
  final List<OrderRequestLine> lines;
  final bool canDecide;
  final bool canCancel;
  final String? paymentMethodCode;
  final String? paymentMethodName;
  final int? paymentTermDays;
  final int? paymentInstallments;
  final String? paymentDisplay;
  final List<({String label, String value})> paymentDetails;

  /// "Talep #31" (sunucu ve web ile aynı yazım).
  String get number => 'Talep #$id';

  String get displayStatus => statusLabel ?? status.label;

  /// Onaylanmış ve sipariş oluşmuş.
  bool get hasOrders => createdOrderIds.isNotEmpty;

  int get failedLineCount => lines.where((l) => l.failed).length;

  /// Ürün özetleri ("Motorin, Kurşunsuz 95").
  String get productsSummary {
    final names = <String>{
      for (final l in lines)
        if (l.productName.trim().isNotEmpty) l.productName.trim(),
    };
    return names.isEmpty ? '—' : names.join(', ');
  }
}

/// Ödeme belgesinin yükleneceği yer (`PaymentUploadTargetDto`, `GET orders/payment-document-target`;
/// 204 = belge gerekmiyor).
@immutable
class PaymentUploadTarget {
  const PaymentUploadTarget({
    required this.ownerType,
    required this.ownerId,
    required this.kind,
    this.kindLabel,
    this.required = false,
    this.canUpload = false,
    this.message,
    this.orderId,
  });

  factory PaymentUploadTarget.fromJson(JsonReader r) => PaymentUploadTarget(
    ownerType: r.enumOf('ownerType', AttachmentOwnerType.fromCode),
    ownerId: r.integer('ownerId'),
    kind: r.enumOf('kind', AttachmentKind.fromCode),
    kindLabel: r.nonEmpty('kindLabel'),
    required: r.boolean('required'),
    canUpload: r.boolean('canUpload'),
    message: r.nonEmpty('message'),
    orderId: r.intOrNull('orderId'),
  );

  /// Yanıt gövdesi yoksa (204) ya da hedef geçersizse null.
  static PaymentUploadTarget? tryParse(Object? json) {
    if (json is! Map) return null;
    final t = PaymentUploadTarget.fromJson(JsonReader.of(json));
    return t.ownerType.isUnknown || t.ownerId <= 0 ? null : t;
  }

  final AttachmentOwnerType ownerType;
  final int ownerId;
  final AttachmentKind kind;
  final String? kindLabel;
  final bool required;
  final bool canUpload;
  final String? message;
  final int? orderId;

  String get label => kindLabel ?? kind.label;
}

/// Siparişler oluştuktan sonra ödeme belgesinin durumu (talep ayrıntısı).
@immutable
class PaymentDocumentState {
  const PaymentDocumentState({
    required this.target,
    required this.uploaded,
    this.fromFallback = false,
  });

  final PaymentUploadTarget target;

  /// Bu türde etkin bir belge yüklenmiş.
  final bool uploaded;

  /// Sunucu hedef ucu yanıt vermedi; hedef yöntem kodundan çıkarıldı.
  final bool fromFallback;
}
