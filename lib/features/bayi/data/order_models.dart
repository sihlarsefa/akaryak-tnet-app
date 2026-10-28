import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';
import '../../../core/utils/turkish_text.dart';
import 'bayi_json.dart';

/// Sipariş segment çipleri (`BayiOrderSegments`; `GET bayi/orders/counts` anahtarları).
enum BayiOrderSegment {
  awaitingQuote('awaitingQuote', 'Teklif bekleyen'),
  revisionRequested('revisionRequested', 'Revize istenen'),
  awaitingCustomer('awaitingCustomer', 'Cari kararında'),
  financeHeld('financeHeld', 'Finans onayında'),
  toPlan('toPlan', 'Planlanacak'),
  inTransit('inTransit', 'Yolda'),
  reported('reported', 'Kabul bekleyen'),
  disputed('disputed', 'İtirazlı'),
  paymentPending('paymentPending', 'Tahsilat bekleyen');

  const BayiOrderSegment(this.key, this.label);

  /// Sorgu / JSON anahtarı.
  final String key;
  final String label;

  static BayiOrderSegment? fromKey(String? key) {
    final k = key?.trim().asciiLower;
    for (final s in values) {
      if (s.key.asciiLower == k) return s;
    }
    return null;
  }
}

/// Segment sayıları (`BayiOrderCountsDto`).
@immutable
class BayiOrderCounts {
  const BayiOrderCounts(this.values);

  static const empty = BayiOrderCounts({});

  factory BayiOrderCounts.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return BayiOrderCounts({
      for (final s in BayiOrderSegment.values) s: r.integer(s.key),
    });
  }

  final Map<BayiOrderSegment, int> values;

  int of(BayiOrderSegment s) => values[s] ?? 0;
}

/// Siparişin sevkiyat özeti (`BayiShipmentStates`).
enum BayiShipmentState {
  none('none', 'Sevkiyat yok'),
  planned('planned', 'Planlandı'),
  inTransit('inTransit', 'Yolda'),
  reported('reported', 'Kabul bekliyor'),
  disputed('disputed', 'İtirazlı'),
  partial('partial', 'Kısmi teslim'),
  delivered('delivered', 'Teslim alındı');

  const BayiShipmentState(this.key, this.label);
  final String key;
  final String label;

  static BayiShipmentState fromKey(String? key) {
    final k = key?.trim().asciiLower;
    for (final s in values) {
      if (s.key.asciiLower == k) return s;
    }
    return none;
  }
}

/// Bayi sipariş listesi satırı (`BayiOrderRowDto`; tarihler +03:00).
@immutable
class BayiOrderRow {
  const BayiOrderRow({
    required this.id,
    required this.orderNumber,
    required this.status,
    this.statusLabel,
    this.customerId = 0,
    this.customerTitle,
    this.productId = 0,
    this.productName,
    this.quantityLiters = 0,
    this.requestedDeliveryDate,
    this.expiresAt,
    this.unitPrice,
    this.totalAmount,
    this.paymentMethodCode,
    this.paymentMethodName,
    this.paymentStatus = PaymentStatus.none,
    this.paymentStatusLabel,
    this.financeStatus = OrderFinanceStatus.notRequired,
    this.financeLabel,
    this.shipmentState = BayiShipmentState.none,
    this.shipmentStateLabel,
    this.createdAt,
    this.deliveryPointName,
    this.deliveryCity,
    this.quoteVersion,
    this.paymentDueDate,
    this.acceptedLiters = 0,
    this.remainingLiters = 0,
  });

  factory BayiOrderRow.fromJson(JsonReader r) => BayiOrderRow(
    id: r.integer('id'),
    orderNumber: r.str('orderNumber'),
    status: r.enumOf('status', OrderStatus.fromCode),
    statusLabel: r.nonEmpty('statusLabel'),
    customerId: r.integer('customerId'),
    customerTitle: r.nonEmpty('customerTitle'),
    productId: r.integer('productId'),
    productName: r.nonEmpty('productName'),
    quantityLiters: r.dec('quantityLiters'),
    requestedDeliveryDate: r.dateTr('requestedDeliveryDate'),
    expiresAt: r.dateTr('expiresAt'),
    unitPrice: r.decOrNull('unitPrice'),
    totalAmount: r.decOrNull('totalAmount'),
    paymentMethodCode: r.nonEmpty('paymentMethodCode'),
    paymentMethodName: r.nonEmpty('paymentMethodName'),
    paymentStatus: r.enumOf('paymentStatus', PaymentStatus.fromCode),
    paymentStatusLabel: r.nonEmpty('paymentStatusLabel'),
    financeStatus: r.enumOf('financeStatus', OrderFinanceStatus.fromCode),
    financeLabel: r.nonEmpty('financeLabel'),
    shipmentState: BayiShipmentState.fromKey(r.strOrNull('shipmentState')),
    shipmentStateLabel: r.nonEmpty('shipmentStateLabel'),
    createdAt: r.dateTr('createdAt'),
    deliveryPointName: r.nonEmpty('deliveryPointName'),
    deliveryCity: r.nonEmpty('deliveryCity'),
    quoteVersion: r.intOrNull('quoteVersion'),
    paymentDueDate: r.dateTr('paymentDueDate'),
    acceptedLiters: r.dec('acceptedLiters'),
    remainingLiters: r.dec('remainingLiters'),
  );

  final int id;
  final String orderNumber;
  final OrderStatus status;
  final String? statusLabel;
  final int customerId;
  final String? customerTitle;
  final int productId;
  final String? productName;
  final double quantityLiters;
  final DateTime? requestedDeliveryDate;

  /// Süre dolumu kapalıyken ya da kapanmış siparişte null.
  final DateTime? expiresAt;
  final double? unitPrice;
  final double? totalAmount;
  final String? paymentMethodCode;
  final String? paymentMethodName;
  final PaymentStatus paymentStatus;
  final String? paymentStatusLabel;
  final OrderFinanceStatus financeStatus;
  final String? financeLabel;
  final BayiShipmentState shipmentState;
  final String? shipmentStateLabel;
  final DateTime? createdAt;
  final String? deliveryPointName;
  final String? deliveryCity;
  final int? quoteVersion;
  final DateTime? paymentDueDate;
  final double acceptedLiters;

  /// Planlanabilir kalan litre (yalnızca Onaylandı'da > 0).
  final double remainingLiters;
}

/// Sipariş sıralaması (`BayiOrderSorts`).
enum BayiOrderSort {
  created('created', 'En yeni'),
  expiry('expiry', 'Süre sonu yakın'),
  requested('requested', 'Teslim günü yakın');

  const BayiOrderSort(this.key, this.label);
  final String key;
  final String label;
}

/// `GET bayi/orders` süzgeçleri. Tarih aralıkları Türkiye yerel günleri (bitiş dahil).
@immutable
class BayiOrdersFilter {
  const BayiOrdersFilter({
    this.segment,
    this.q = '',
    this.statuses = const {},
    this.paymentStatus,
    this.financeStatus,
    this.customerId,
    this.customerTitle,
    this.createdFrom,
    this.createdTo,
    this.requestedFrom,
    this.requestedTo,
    this.sort = BayiOrderSort.created,
  });

  final BayiOrderSegment? segment;
  final String q;
  final Set<OrderStatus> statuses;
  final PaymentStatus? paymentStatus;
  final OrderFinanceStatus? financeStatus;
  final int? customerId;

  /// Yalnızca ekranda gösterim (seçilen carinin adı).
  final String? customerTitle;
  final DateTime? createdFrom;
  final DateTime? createdTo;
  final DateTime? requestedFrom;
  final DateTime? requestedTo;
  final BayiOrderSort sort;

  /// Filtre sayfasındaki (segment ve arama dışındaki) etkin süzgeç sayısı.
  int get advancedCount =>
      (statuses.isEmpty ? 0 : 1) +
      (paymentStatus == null ? 0 : 1) +
      (financeStatus == null ? 0 : 1) +
      (customerId == null ? 0 : 1) +
      (createdFrom == null && createdTo == null ? 0 : 1) +
      (requestedFrom == null && requestedTo == null ? 0 : 1) +
      (sort == BayiOrderSort.created ? 0 : 1);

  bool get isFiltered =>
      segment != null || q.trim().isNotEmpty || advancedCount > 0;

  BayiOrdersFilter copyWith({
    Object? segment = _keep,
    String? q,
    Set<OrderStatus>? statuses,
    Object? paymentStatus = _keep,
    Object? financeStatus = _keep,
    Object? customerId = _keep,
    Object? customerTitle = _keep,
    Object? createdFrom = _keep,
    Object? createdTo = _keep,
    Object? requestedFrom = _keep,
    Object? requestedTo = _keep,
    BayiOrderSort? sort,
  }) => BayiOrdersFilter(
    segment: segment == _keep ? this.segment : segment as BayiOrderSegment?,
    q: q ?? this.q,
    statuses: statuses ?? this.statuses,
    paymentStatus: paymentStatus == _keep
        ? this.paymentStatus
        : paymentStatus as PaymentStatus?,
    financeStatus: financeStatus == _keep
        ? this.financeStatus
        : financeStatus as OrderFinanceStatus?,
    customerId: customerId == _keep ? this.customerId : customerId as int?,
    customerTitle: customerTitle == _keep
        ? this.customerTitle
        : customerTitle as String?,
    createdFrom: createdFrom == _keep
        ? this.createdFrom
        : createdFrom as DateTime?,
    createdTo: createdTo == _keep ? this.createdTo : createdTo as DateTime?,
    requestedFrom: requestedFrom == _keep
        ? this.requestedFrom
        : requestedFrom as DateTime?,
    requestedTo: requestedTo == _keep
        ? this.requestedTo
        : requestedTo as DateTime?,
    sort: sort ?? this.sort,
  );

  /// Segment ve arama korunur, gelişmiş süzgeçler temizlenir.
  BayiOrdersFilter clearAdvanced() => BayiOrdersFilter(segment: segment, q: q);

  Map<String, dynamic> toQuery({required int page, required int pageSize}) => {
    'page': page,
    'pageSize': pageSize,
    'segment': segment?.key,
    'q': q.trim(),
    'statuses': [for (final s in statuses) s.code],
    'paymentStatus': paymentStatus?.code,
    'financeStatus': financeStatus?.code,
    'customerId': customerId,
    'createdFrom': createdFrom == null ? null : BayiJson.isoDate(createdFrom!),
    'createdTo': createdTo == null ? null : BayiJson.isoDate(createdTo!),
    'requestedFrom': requestedFrom == null
        ? null
        : BayiJson.isoDate(requestedFrom!),
    'requestedTo': requestedTo == null ? null : BayiJson.isoDate(requestedTo!),
    'sort': sort == BayiOrderSort.created ? null : sort.key,
  };

  @override
  bool operator ==(Object other) =>
      other is BayiOrdersFilter &&
      other.segment == segment &&
      other.q == q &&
      setEquals(other.statuses, statuses) &&
      other.paymentStatus == paymentStatus &&
      other.financeStatus == financeStatus &&
      other.customerId == customerId &&
      other.createdFrom == createdFrom &&
      other.createdTo == createdTo &&
      other.requestedFrom == requestedFrom &&
      other.requestedTo == requestedTo &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
    segment,
    q,
    Object.hashAllUnordered(statuses),
    paymentStatus,
    financeStatus,
    customerId,
    createdFrom,
    createdTo,
    requestedFrom,
    requestedTo,
    sort,
  );
}

const Object _keep = Object();

/// Sipariş ayrıntısı paketi: `orders/{id}` + `orders/{id}/timeline` + `shipments/order/{id}`.
@immutable
class BayiOrderBundle {
  const BayiOrderBundle({
    required this.order,
    this.timeline = const [],
    this.fulfillment,
    this.timelineFailed = false,
    this.fulfillmentFailed = false,
  });

  final OrderDetail order;
  final List<OrderTimelineItem> timeline;
  final Fulfillment? fulfillment;

  /// Yan kaynaklardan biri yüklenemedi (ana kayıt gösterilir; bölümde uyarı).
  final bool timelineFailed;
  final bool fulfillmentFailed;

  /// Sunucunun plan kontrolüyle aynı: kabul edilende teslim, diğer iptal dışı sevkiyatlarda plan litresi.
  double get allocatedLiters {
    final f = fulfillment;
    if (f == null) return 0;
    var sum = 0.0;
    for (final s in f.shipments) {
      if (s.status == ShipmentStatus.cancelled) continue;
      sum += s.status == ShipmentStatus.accepted
          ? (s.deliveredLiters ?? s.plannedLiters)
          : s.plannedLiters;
    }
    return sum;
  }

  /// Planlanabilir kalan litre (yalnızca onaylı siparişte anlamlı).
  double get remainingLiters {
    final rest = order.quantityLiters - allocatedLiters;
    return rest < 0.0005 ? 0 : double.parse(rest.toStringAsFixed(3));
  }

  /// Carinin teslim aldığı litre.
  double get acceptedLiters => fulfillment?.acceptedLiters ?? 0;

  /// Sipariş "Tamamla" ile kapatılabilir mi ve neden (null: kapatılamaz). Sunucunun kuralı
  /// (`OrderCompletionRules.CanComplete`; `orders/{id}/complete` aynı kuralla doğrular), API'nin
  /// gösterdiği kadarıyla:
  /// - tüm litre teslim alındı;
  /// - açık sevkiyat yok ve kabul edilen litre teslim toleransı içinde: tolerans değeri istemcide
  ///   yok, sunucu `completionHint` ile "Tamamla"ya çağırır ([Fulfillment.invitesCompletion]);
  /// - sevkiyat kaydı tutulmamış eski sipariş: hiç (iptal dışı) sevkiyat ve teklif kaydı yok.
  ///   Teklifli eski siparişler (kabul edilen teklif kaydından önce) istemcide yenilerinden
  ///   ayrılamaz; onlar web panelinden kapatılır.
  /// Yetki ([BayiGrants.completeOrder]) ayrıca denetlenir.
  BayiCompletion? get completion {
    final f = fulfillment;
    if (order.status != OrderStatus.approved || f == null || !f.isOpen) {
      return null;
    }
    if (f.acceptedLiters + 0.0005 >= order.quantityLiters) {
      return BayiCompletion.fullyAccepted;
    }
    final active = f.shipments.where(
      (s) => s.status != ShipmentStatus.cancelled,
    );
    if (active.isEmpty) {
      return order.quotes.isEmpty ? BayiCompletion.noShipments : null;
    }
    if (!f.hasOpenShipments && f.acceptedLiters > 0 && f.invitesCompletion) {
      return BayiCompletion.withinTolerance;
    }
    return null;
  }
}

/// Siparişin "Tamamla" ile kapatılabilme nedeni ([BayiOrderBundle.completion]).
enum BayiCompletion {
  /// Tüm litre teslim alındı.
  fullyAccepted,

  /// Açık sevkiyat yok; kabul edilen litre teslim toleransı içinde (eksik teslim).
  withinTolerance,

  /// Sevkiyat kaydı tutulmamış, teklifsiz eski sipariş.
  noShipments,
}

/// Ödeme yöntemi kodunun varsayılan adı (`PaymentMethodCodes.DefaultName`).
String paymentMethodName(String? code) => switch (code) {
  null => 'Belirtilmemiş',
  'NAKIT' => 'Nakit (peşin)',
  'HAVALE' => 'Havale / EFT (peşin)',
  'KART' => 'Kredi / banka kartı (POS)',
  'DBS' => 'DBS',
  'CEK' => 'Çek',
  'SENET' => 'Senet',
  'ACIK_HESAP' => 'Açık hesap (cari vadeli)',
  'TEMINAT' => 'Teminat mektubu karşılığı',
  'UTTS' => 'Taşıt tanıma / filo kartı',
  'AVANS' => 'Ön ödemeli bakiye',
  _ => code,
};
