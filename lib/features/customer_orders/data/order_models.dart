import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';

/// Siparişlerim bölümleri (`CustomerOrderSegments`).
enum OrderSegment {
  decision('decision', 'Karar bekleyen'),
  active('active', 'Aktif'),
  history('history', 'Geçmiş');

  const OrderSegment(this.code, this.label);
  final String code;
  final String label;

  static OrderSegment parse(String? v) => switch (v) {
    'decision' => decision,
    'history' => history,
    _ => active,
  };
}

/// Siparişlerim satırı (`CustomerOrderRowDto`). Tarihler Türkiye yerel (+03:00).
@immutable
class CustomerOrderRow {
  const CustomerOrderRow({
    required this.id,
    required this.orderNumber,
    required this.status,
    this.statusLabel,
    this.stationId = 0,
    this.stationTitle,
    this.productName,
    this.quantityLiters = 0,
    this.deliveryPointName,
    this.requestedDeliveryDate,
    this.expiresAt,
    this.quotedUnitPrice,
    this.quotedTotal,
    this.financeStatus = OrderFinanceStatus.notRequired,
    this.financeLabel,
    this.paymentMethodCode,
    this.paymentMethodName,
    this.paymentStatus = PaymentStatus.none,
    this.paymentStatusLabel,
    this.activeShipmentStatus,
    this.activeShipmentStatusLabel,
    this.createdAt,
    this.paymentDueDate,
    this.paymentDocumentMissing = false,
  });

  factory CustomerOrderRow.fromJson(JsonReader r) => CustomerOrderRow(
    id: r.integer('id'),
    orderNumber: r.str('orderNumber'),
    status: r.enumOf('status', OrderStatus.fromCode),
    statusLabel: r.nonEmpty('statusLabel'),
    stationId: r.integer('stationId'),
    stationTitle: r.nonEmpty('stationTitle'),
    productName: r.nonEmpty('productName'),
    quantityLiters: r.dec('quantityLiters'),
    deliveryPointName: r.nonEmpty('deliveryPointName'),
    requestedDeliveryDate: r.dateTr('requestedDeliveryDate'),
    expiresAt: r.dateTr('expiresAt'),
    quotedUnitPrice: r.decOrNull('quotedUnitPrice'),
    quotedTotal: r.decOrNull('quotedTotal'),
    financeStatus: r.enumOf('financeStatus', OrderFinanceStatus.fromCode),
    financeLabel: r.nonEmpty('financeLabel'),
    paymentMethodCode: r.nonEmpty('paymentMethodCode'),
    paymentMethodName: r.nonEmpty('paymentMethodName'),
    paymentStatus: r.enumOf('paymentStatus', PaymentStatus.fromCode),
    paymentStatusLabel: r.nonEmpty('paymentStatusLabel'),
    activeShipmentStatus: r.intOrNull('activeShipmentStatus') == null
        ? null
        : r.enumOf('activeShipmentStatus', ShipmentStatus.fromCode),
    activeShipmentStatusLabel: r.nonEmpty('activeShipmentStatusLabel'),
    createdAt: r.dateTr('createdAt'),
    paymentDueDate: r.dateTr('paymentDueDate'),
    paymentDocumentMissing: r.boolean('paymentDocumentMissing'),
  );

  final int id;
  final String orderNumber;
  final OrderStatus status;
  final String? statusLabel;
  final int stationId;
  final String? stationTitle;
  final String? productName;
  final double quantityLiters;
  final String? deliveryPointName;
  final DateTime? requestedDeliveryDate;

  /// Teklif / karar süresinin sonu (süre kapalıysa null).
  final DateTime? expiresAt;
  final double? quotedUnitPrice;
  final double? quotedTotal;
  final OrderFinanceStatus financeStatus;
  final String? financeLabel;
  final String? paymentMethodCode;
  final String? paymentMethodName;
  final PaymentStatus paymentStatus;
  final String? paymentStatusLabel;
  final ShipmentStatus? activeShipmentStatus;
  final String? activeShipmentStatusLabel;
  final DateTime? createdAt;
  final DateTime? paymentDueDate;

  /// Zorunlu çek / senet görseli eksik (teklif onaylanamaz).
  final bool paymentDocumentMissing;

  String get displayStatus => statusLabel ?? status.label;
}

/// Takip adımının durumu (`TrackingStepState`).
enum TrackingState {
  pending(0),
  current(1),
  done(2),
  failed(3);

  const TrackingState(this.code);
  final int code;

  static TrackingState fromCode(int? c) => switch (c) {
    1 => current,
    2 => done,
    3 => failed,
    _ => pending,
  };
}

/// Takip adımı (`OrderTrackingStepDto`). `key`: received | quote | approval | dispatch | delivered.
@immutable
class TrackingStep {
  const TrackingStep({
    required this.key,
    required this.label,
    this.state = TrackingState.pending,
    this.at,
    this.atIsDateOnly = false,
    this.detail,
  });

  factory TrackingStep.fromJson(JsonReader r) => TrackingStep(
    key: r.str('key'),
    label: r.str('label'),
    state: TrackingState.fromCode(r.intOrNull('state')),
    at: r.dateTr('at'),
    atIsDateOnly: r.boolean('atIsDateOnly'),
    detail: r.nonEmpty('detail'),
  );

  final String key;
  final String label;
  final TrackingState state;
  final DateTime? at;
  final bool atIsDateOnly;
  final String? detail;
}

/// Takip sayfasındaki sevkiyat (`OrderTrackingShipmentDto`; zamanlar Türkiye yerel).
@immutable
class TrackingShipment {
  const TrackingShipment({
    required this.id,
    required this.plannedLiters,
    required this.status,
    this.code,
    this.deliveredLiters,
    this.vehiclePlate = '',
    this.driverName = '',
    this.scheduledAt,
    this.deliveryDocumentNo,
    this.disputeNote,
    this.plannedAt,
    this.dispatchedAt,
    this.deliveredAt,
    this.acceptedAt,
    this.disputedAt,
    this.cancelledAt,
  });

  factory TrackingShipment.fromJson(JsonReader r) => TrackingShipment(
    id: r.integer('id'),
    code: r.nonEmpty('code'),
    plannedLiters: r.dec('plannedLiters'),
    deliveredLiters: r.decOrNull('deliveredLiters'),
    vehiclePlate: r.str('vehiclePlate'),
    driverName: r.str('driverName'),
    scheduledAt: r.dateTr('scheduledAt'),
    status: r.enumOf('status', ShipmentStatus.fromCode),
    deliveryDocumentNo: r.nonEmpty('deliveryDocumentNo'),
    disputeNote: r.nonEmpty('disputeNote'),
    plannedAt: r.dateTr('plannedAt'),
    dispatchedAt: r.dateTr('dispatchedAt'),
    deliveredAt: r.dateTr('deliveredAt'),
    acceptedAt: r.dateTr('acceptedAt'),
    disputedAt: r.dateTr('disputedAt'),
    cancelledAt: r.dateTr('cancelledAt'),
  );

  final int id;
  final String? code;
  final double plannedLiters;
  final double? deliveredLiters;
  final String vehiclePlate;
  final String driverName;
  final DateTime? scheduledAt;
  final ShipmentStatus status;
  final String? deliveryDocumentNo;
  final String? disputeNote;
  final DateTime? plannedAt;
  final DateTime? dispatchedAt;
  final DateTime? deliveredAt;
  final DateTime? acceptedAt;
  final DateTime? disputedAt;
  final DateTime? cancelledAt;

  String get displayCode => code ?? 'SVK-${id.toString().padLeft(8, '0')}';

  bool get isDispatched =>
      status == ShipmentStatus.inTransit ||
      status == ShipmentStatus.reported ||
      status == ShipmentStatus.accepted ||
      status == ShipmentStatus.disputed;
}

/// Zaman çizelgesi olayı (`OrderTrackingEventDto`; tone: ok | warn | danger | info | muted).
@immutable
class TrackingEvent {
  const TrackingEvent({
    required this.title,
    this.at,
    this.note,
    this.tone = 'info',
  });

  factory TrackingEvent.fromJson(JsonReader r) => TrackingEvent(
    at: r.dateTr('at'),
    title: r.str('title'),
    note: r.nonEmpty('note'),
    tone: r.str('tone', 'info'),
  );

  final DateTime? at;
  final String title;
  final String? note;
  final String tone;
}

/// Aynı ürünün önceki alımı (`PreviousPurchasePriceDto`).
@immutable
class PreviousPurchase {
  const PreviousPurchase({
    required this.orderId,
    required this.orderNumber,
    required this.unitPriceTry,
    this.orderedAt,
    this.stationTitle = '',
    this.quantityLiters = 0,
    this.diffPercent,
  });

  factory PreviousPurchase.fromJson(JsonReader r) => PreviousPurchase(
    orderId: r.integer('orderId'),
    orderNumber: r.str('orderNumber'),
    orderedAt: r.dateTr('orderedAt'),
    stationTitle: r.str('stationTitle'),
    quantityLiters: r.dec('quantityLiters'),
    unitPriceTry: r.dec('unitPriceTry'),
    diffPercent: r.decOrNull('diffPercent'),
  );

  final int orderId;
  final String orderNumber;
  final DateTime? orderedAt;
  final String stationTitle;
  final double quantityLiters;
  final double unitPriceTry;

  /// Güncel teklifin bu alıma göre farkı (%); pozitif = güncel teklif daha pahalı.
  final double? diffPercent;
}

/// Teklif karşılaştırması (`QuotePriceComparisonDto`).
@immutable
class QuotePriceComparison {
  const QuotePriceComparison({
    required this.currentUnitPriceTry,
    this.previous = const [],
    this.lastUnitPriceTry,
    this.lastDiffPercent,
    this.averageUnitPriceTry,
    this.averageDiffPercent,
    this.minUnitPriceTry,
    this.maxUnitPriceTry,
  });

  factory QuotePriceComparison.fromJson(JsonReader r) => QuotePriceComparison(
    currentUnitPriceTry: r.dec('currentUnitPriceTry'),
    previous: List.unmodifiable(r.list('previous', PreviousPurchase.fromJson)),
    lastUnitPriceTry: r.decOrNull('lastUnitPriceTry'),
    lastDiffPercent: r.decOrNull('lastDiffPercent'),
    averageUnitPriceTry: r.decOrNull('averageUnitPriceTry'),
    averageDiffPercent: r.decOrNull('averageDiffPercent'),
    minUnitPriceTry: r.decOrNull('minUnitPriceTry'),
    maxUnitPriceTry: r.decOrNull('maxUnitPriceTry'),
  );

  final double currentUnitPriceTry;
  final List<PreviousPurchase> previous;
  final double? lastUnitPriceTry;
  final double? lastDiffPercent;
  final double? averageUnitPriceTry;
  final double? averageDiffPercent;
  final double? minUnitPriceTry;
  final double? maxUnitPriceTry;

  bool get hasHistory => previous.isNotEmpty;
}

/// `GET orders/{id}/tracking` (`OrderTrackingDto`).
@immutable
class OrderTracking {
  const OrderTracking({
    required this.orderId,
    this.status = OrderStatus.unknown,
    this.steps = const [],
    this.shipments = const [],
    this.events = const [],
    this.orderedLiters = 0,
    this.acceptedLiters = 0,
    this.inProcessLiters = 0,
    this.awaitingAcceptanceCount = 0,
    this.canAcceptDeliveries = false,
    this.expiryEnabled = true,
    this.priceComparison,
  });

  factory OrderTracking.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return OrderTracking(
      orderId: r.integer('orderId'),
      status: r.enumOf('status', OrderStatus.fromCode),
      steps: List.unmodifiable(r.list('steps', TrackingStep.fromJson)),
      shipments: List.unmodifiable(
        r.list('shipments', TrackingShipment.fromJson),
      ),
      events: List.unmodifiable(r.list('events', TrackingEvent.fromJson)),
      orderedLiters: r.dec('orderedLiters'),
      acceptedLiters: r.dec('acceptedLiters'),
      inProcessLiters: r.dec('inProcessLiters'),
      awaitingAcceptanceCount: r.integer('awaitingAcceptanceCount'),
      canAcceptDeliveries: r.boolean('canAcceptDeliveries'),
      expiryEnabled: r.boolean('expiryEnabled', true),
      priceComparison: r.objOrNull('priceComparison') == null
          ? null
          : QuotePriceComparison.fromJson(r.obj('priceComparison')),
    );
  }

  final int orderId;
  final OrderStatus status;
  final List<TrackingStep> steps;

  /// En yeni önce; iptal edilenler dahil.
  final List<TrackingShipment> shipments;
  final List<TrackingEvent> events;
  final double orderedLiters;
  final double acceptedLiters;
  final double inProcessLiters;
  final int awaitingAcceptanceCount;
  final bool canAcceptDeliveries;
  final bool expiryEnabled;
  final QuotePriceComparison? priceComparison;

  /// Yolda, yoksa kabul bekleyen / itirazlı, yoksa planlı sevkiyat (sunucu `ActiveShipment`).
  TrackingShipment? get activeShipment {
    for (final s in shipments) {
      if (s.status == ShipmentStatus.inTransit) return s;
    }
    for (final s in shipments) {
      if (s.status == ShipmentStatus.reported ||
          s.status == ShipmentStatus.disputed) {
        return s;
      }
    }
    for (final s in shipments) {
      if (s.status == ShipmentStatus.planned) return s;
    }
    return null;
  }

  bool get hasInTransit =>
      shipments.any((s) => s.status == ShipmentStatus.inTransit);

  bool get hasReported =>
      shipments.any((s) => s.status == ShipmentStatus.reported);
}
