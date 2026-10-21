import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';
import '../../../core/utils/tr_time.dart';
import 'payment_models.dart';

/// `PlaceOrderRequest.lines[]`: ürün + litre; nokta ve tarih satır bazında isteğe bağlı.
@immutable
class PlaceOrderLine {
  const PlaceOrderLine({
    required this.productId,
    required this.quantityLiters,
    this.deliveryPointId,
    this.requestedDeliveryDate,
  });

  factory PlaceOrderLine.fromJson(JsonReader r) => PlaceOrderLine(
    productId: r.integer('productId'),
    quantityLiters: r.dec('quantityLiters'),
    deliveryPointId: r.intOrNull('deliveryPointId'),
    requestedDeliveryDate: r.date('requestedDeliveryDate'),
  );

  final int productId;
  final double quantityLiters;
  final int? deliveryPointId;

  /// Türkiye gece yarısı (an); `yyyy-MM-dd` gider.
  final DateTime? requestedDeliveryDate;

  JsonMap toJson() => {
    'productId': productId,
    'quantityLiters': quantityLiters,
    'deliveryPointId': ?deliveryPointId,
    if (requestedDeliveryDate != null)
      'requestedDeliveryDate': TrTime.isoDate(requestedDeliveryDate!),
  };
}

/// `POST orders/place` gövdesi (spec B.6).
@immutable
class PlaceOrderRequest {
  const PlaceOrderRequest({
    required this.stationId,
    required this.deliveryPointId,
    required this.requestedDeliveryDate,
    required this.lines,
    this.payment,
    this.paymentGroupKey,
    this.note,
    this.templateId,
  });

  factory PlaceOrderRequest.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return PlaceOrderRequest(
      stationId: r.integer('stationId'),
      deliveryPointId: r.integer('deliveryPointId'),
      requestedDeliveryDate:
          r.date('requestedDeliveryDate') ?? TrTime.todayStart(),
      lines: List.unmodifiable(r.list('lines', PlaceOrderLine.fromJson)),
      payment: r.objOrNull('payment') == null
          ? null
          : PaymentSelection.fromJson(r.obj('payment')),
      paymentGroupKey: r.nonEmpty('paymentGroupKey'),
      note: r.nonEmpty('note'),
      templateId: r.intOrNull('templateId'),
    );
  }

  final int stationId;
  final int deliveryPointId;
  final DateTime requestedDeliveryDate;
  final List<PlaceOrderLine> lines;
  final PaymentSelection? payment;

  /// Kısmi hatadan sonra kalan satırlar aynı grupla (tek çek / senet).
  final String? paymentGroupKey;

  /// "Onaylayana not" (yalnızca şirket içi talepte kullanılır).
  final String? note;
  final int? templateId;

  double get totalLiters => lines.fold(0, (s, l) => s + l.quantityLiters);

  JsonMap toJson() => {
    'stationId': stationId,
    'deliveryPointId': deliveryPointId,
    'requestedDeliveryDate': TrTime.isoDate(requestedDeliveryDate),
    'lines': [for (final l in lines) l.toJson()],
    'payment': payment?.toJson(),
    'paymentGroupKey': ?paymentGroupKey,
    if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
    'templateId': ?templateId,
  };

  PlaceOrderRequest copyWith({
    List<PlaceOrderLine>? lines,
    String? paymentGroupKey,
    bool clearNote = false,
    bool clearTemplate = false,
  }) => PlaceOrderRequest(
    stationId: stationId,
    deliveryPointId: deliveryPointId,
    requestedDeliveryDate: requestedDeliveryDate,
    lines: lines ?? this.lines,
    payment: payment,
    paymentGroupKey: paymentGroupKey ?? this.paymentGroupKey,
    note: clearNote ? null : note,
    templateId: clearTemplate ? null : templateId,
  );
}

/// Şirket içi onaya gönderilen talep (`PlaceOrderCompanyRequestDto`).
@immutable
class CompanyRequestRef {
  const CompanyRequestRef({required this.id, this.message = ''});

  factory CompanyRequestRef.fromJson(JsonReader r) =>
      CompanyRequestRef(id: r.integer('id'), message: r.str('message'));

  final int id;
  final String message;

  JsonMap toJson() => {'id': id, 'message': message};
}

/// `PlaceOrderResultDto`.
@immutable
class PlaceOrderResult {
  const PlaceOrderResult({
    this.kind = PlaceOrderResult.kindOrders,
    this.orders = const [],
    this.paymentGroupKey,
    this.financePendingCount = 0,
    this.companyRequest,
    this.paymentDocument,
    this.partialError,
    this.message = '',
    this.failedLineIndex,
    this.replayed = false,
  });

  static const kindOrders = 'orders';
  static const kindCompanyRequest = 'companyRequest';

  factory PlaceOrderResult.fromJson(Object? json, {bool replayed = false}) {
    final r = JsonReader.of(json);
    return PlaceOrderResult(
      kind: r.str('kind', kindOrders),
      orders: List.unmodifiable(r.list('orders', CreateOrderResult.fromJson)),
      paymentGroupKey: r.nonEmpty('paymentGroupKey'),
      financePendingCount: r.integer('financePendingCount'),
      companyRequest: r.objOrNull('companyRequest') == null
          ? null
          : CompanyRequestRef.fromJson(r.obj('companyRequest')),
      paymentDocument: PaymentUploadTarget.tryParse(r['paymentDocument']),
      partialError: r.nonEmpty('partialError'),
      message: r.str('message'),
      failedLineIndex: r.intOrNull('failedLineIndex'),
      replayed: replayed,
    );
  }

  final String kind;
  final List<CreateOrderResult> orders;
  final String? paymentGroupKey;
  final int financePendingCount;
  final CompanyRequestRef? companyRequest;
  final PaymentUploadTarget? paymentDocument;

  /// İlk başarısız satırın hatası (sonraki satırlar gönderilmedi).
  final String? partialError;
  final String message;

  /// İlk gönderilmeyen satırın sırası (0'dan).
  final int? failedLineIndex;

  /// Yanıt aynı anahtarın tekrarıydı (`Idempotent-Replay`); bilgi amaçlı.
  final bool replayed;

  bool get isCompanyRequest => kind == kindCompanyRequest;
  bool get isPartial => partialError != null && failedLineIndex != null;

  JsonMap toJson() => {
    'kind': kind,
    'orders': [
      for (final o in orders)
        {
          'orderId': o.orderId,
          'orderNumber': o.orderNumber,
          'expiresAt': o.expiresAt == null
              ? null
              : TrTime.isoLocal(o.expiresAt!),
          'financeStatus': o.financeStatus.code,
          'financeReasons': o.financeReasons,
          'paymentMethodCode': o.paymentMethodCode,
          'paymentDueDate': o.paymentDueDate == null
              ? null
              : TrTime.isoLocal(o.paymentDueDate!),
          'estimatedAmount': o.estimatedAmount,
          'paymentGroupKey': o.paymentGroupKey,
        },
    ],
    'paymentGroupKey': paymentGroupKey,
    'financePendingCount': financePendingCount,
    'companyRequest': companyRequest?.toJson(),
    'paymentDocument': paymentDocument?.toJson(),
    'partialError': partialError,
    'message': message,
    'failedLineIndex': failedLineIndex,
  };
}
