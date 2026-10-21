import 'package:flutter/foundation.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';
import 'window_time.dart';

/// Belge kodları (sunucu `DocumentCodes` ile aynı).
abstract final class DocCodes {
  static String shipment(int id) => 'SVK-${id.toString().padLeft(8, '0')}';
  static String receipt(int id) => 'TT-${id.toString().padLeft(8, '0')}';
  static String quote(String orderNumber, int version) =>
      '$orderNumber-T$version';
}

// ───────────────────────── Belge arşivi (customers/me/documents) ─────────────────────────

/// Arşiv sayfası özetleri (`DocumentArchiveTotalsDto`).
@immutable
class DocumentArchiveTotals {
  const DocumentArchiveTotals({
    this.count = 0,
    this.orderCount = 0,
    this.shipmentCount = 0,
  });

  factory DocumentArchiveTotals.fromJson(JsonReader r) => DocumentArchiveTotals(
    count: r.integer('count'),
    orderCount: r.integer('orderCount'),
    shipmentCount: r.integer('shipmentCount'),
  );

  final int count;
  final int orderCount;
  final int shipmentCount;
}

/// `GET customers/me/documents?skip&take` → `{totals, items}`.
@immutable
class DocumentArchivePage {
  const DocumentArchivePage({required this.totals, required this.items});

  factory DocumentArchivePage.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return DocumentArchivePage(
      totals: DocumentArchiveTotals.fromJson(r.obj('totals')),
      items: List.unmodifiable(r.list('items', DocumentArchiveRow.fromJson)),
    );
  }

  final DocumentArchiveTotals totals;
  final List<DocumentArchiveRow> items;
}

/// Arşiv satırı: bir sipariş ve (varsa) bir sevkiyatı (`DocumentArchiveRowDto`). Tarihler Türkiye yerel.
@immutable
class DocumentArchiveRow {
  const DocumentArchiveRow({
    required this.orderId,
    required this.orderNumber,
    this.orderDate,
    required this.status,
    this.stationCode,
    this.stationTitle = '',
    this.productName = '',
    this.quantityLiters = 0,
    this.deliveryPointName,
    this.deliveryPointCity,
    this.quoteVersion,
    this.totalAmountTry,
    this.activeShipmentCount = 0,
    this.shipmentId,
    this.shipmentStatus,
    this.scheduledAt,
    this.deliveredAt,
    this.plannedLiters,
    this.deliveredLiters,
    this.vehiclePlate,
    this.deliveryDocumentNo,
    required this.canReconcile,
    required this.canReceipt,
    required this.canWaybill,
  });

  factory DocumentArchiveRow.fromJson(JsonReader r) {
    final status = r.enumOf('status', OrderStatus.fromCode);
    final shipmentId = r.intOrNull('shipmentId');
    final shipStatus = shipmentId == null
        ? null
        : r.enumOf('shipmentStatus', ShipmentStatus.fromCode);
    final active = r.integer('activeShipmentCount');
    final cancelled = shipStatus == ShipmentStatus.cancelled;
    final approved =
        status == OrderStatus.approved || status == OrderStatus.completed;
    return DocumentArchiveRow(
      orderId: r.integer('orderId'),
      orderNumber: r.str('orderNumber'),
      orderDate: r.dateTr('orderDate'),
      status: status,
      stationCode: r.nonEmpty('stationCode'),
      stationTitle: r.str('stationTitle'),
      productName: r.str('productName'),
      quantityLiters: r.dec('quantityLiters'),
      deliveryPointName: r.nonEmpty('deliveryPointName'),
      deliveryPointCity: r.nonEmpty('deliveryPointCity'),
      quoteVersion: r.intOrNull('quoteVersion'),
      totalAmountTry: r.decOrNull('totalAmountTry'),
      activeShipmentCount: active,
      shipmentId: shipmentId,
      shipmentStatus: shipStatus,
      scheduledAt: r.dateTr('scheduledAt'),
      deliveredAt: r.dateTr('deliveredAt'),
      plannedLiters: r.decOrNull('plannedLiters'),
      deliveredLiters: r.decOrNull('deliveredLiters'),
      vehiclePlate: r.nonEmpty('vehiclePlate'),
      deliveryDocumentNo: r.nonEmpty('deliveryDocumentNo'),
      // Sunucunun hesapladığı bayraklar; eski yanıtlarda aynı kural yerelde uygulanır.
      canReconcile: r.boolOrNull('canReconcile') ?? (approved && active > 0),
      canReceipt:
          r.boolOrNull('canReceipt') ?? (shipmentId != null && !cancelled),
      canWaybill: r.boolOrNull('canWaybill') ?? shipmentId != null,
    );
  }

  final int orderId;
  final String orderNumber;
  final DateTime? orderDate;
  final OrderStatus status;
  final String? stationCode;
  final String stationTitle;
  final String productName;
  final double quantityLiters;
  final String? deliveryPointName;
  final String? deliveryPointCity;
  final int? quoteVersion;
  final double? totalAmountTry;
  final int activeShipmentCount;
  final int? shipmentId;
  final ShipmentStatus? shipmentStatus;
  final DateTime? scheduledAt;
  final DateTime? deliveredAt;
  final double? plannedLiters;
  final double? deliveredLiters;
  final String? vehiclePlate;
  final String? deliveryDocumentNo;

  /// Teslimat mutabakatı (onaylı/tamamlanmış ve en az bir iptal edilmemiş sevkiyat).
  final bool canReconcile;

  /// Teslim tutanağı (iptal edilmemiş sevkiyat).
  final bool canReceipt;

  /// Sevk belgesi (her sevkiyat).
  final bool canWaybill;

  bool get hasQuote => quoteVersion != null;
  bool get hasShipment => shipmentId != null;
  String? get shipmentCode =>
      shipmentId == null ? null : DocCodes.shipment(shipmentId!);
  String? get receiptCode => canReceipt ? DocCodes.receipt(shipmentId!) : null;

  /// Kararlı satır anahtarı (sipariş × sevkiyat).
  String get key => '$orderId:${shipmentId ?? 0}';
}

// ───────────────────────── Belge verisi (documents/orders, documents/shipments) ─────────────────────────

/// Belgede taraf kartı (`DocPartyDto`).
@immutable
class DocParty {
  const DocParty({
    this.title = '',
    this.legalTitle,
    this.code,
    this.taxNumber,
    this.taxOffice,
    this.epdkLicenseNo,
    this.address,
    this.district,
    this.city,
    this.phone,
    this.email,
    this.contactName,
    this.erpCode,
    this.note,
  });

  factory DocParty.fromJson(JsonReader r) => DocParty(
    title: r.str('title'),
    legalTitle: r.nonEmpty('legalTitle'),
    code: r.nonEmpty('code'),
    taxNumber: r.nonEmpty('taxNumber'),
    taxOffice: r.nonEmpty('taxOffice'),
    epdkLicenseNo: r.nonEmpty('epdkLicenseNo'),
    address: r.nonEmpty('address'),
    district: r.nonEmpty('district'),
    city: r.nonEmpty('city'),
    phone: r.nonEmpty('phone'),
    email: r.nonEmpty('email'),
    contactName: r.nonEmpty('contactName'),
    erpCode: r.nonEmpty('erpCode'),
    note: r.nonEmpty('note'),
  );

  final String title;
  final String? legalTitle;
  final String? code;
  final String? taxNumber;
  final String? taxOffice;
  final String? epdkLicenseNo;
  final String? address;
  final String? district;
  final String? city;
  final String? phone;
  final String? email;
  final String? contactName;
  final String? erpCode;
  final String? note;

  String get displayTitle => legalTitle ?? title;

  /// "Pendik / İstanbul".
  String get cityDistrict => joinNonEmpty(' / ', [district, city]);
}

/// Teklif sürümü (`DocQuoteDto`). Tarihler Türkiye yerel.
@immutable
class DocQuote {
  const DocQuote({
    required this.id,
    required this.version,
    required this.unitPriceTry,
    required this.totalAmountTry,
    this.deliveryDate,
    this.revisionNote,
    this.isSelected = false,
    this.createdAt,
    this.unitPriceDelta,
  });

  factory DocQuote.fromJson(JsonReader r) => DocQuote(
    id: r.integer('id'),
    version: r.integer('version', 1),
    unitPriceTry: r.dec('unitPriceTry'),
    totalAmountTry: r.dec('totalAmountTry'),
    deliveryDate: r.dateTr('deliveryDate'),
    revisionNote: r.nonEmpty('revisionNote'),
    isSelected: r.boolean('isSelected'),
    createdAt: r.dateTr('createdAt'),
    unitPriceDelta: r.decOrNull('unitPriceDelta'),
  );

  final int id;
  final int version;
  final double unitPriceTry;
  final double totalAmountTry;
  final DateTime? deliveryDate;
  final String? revisionNote;
  final bool isSelected;
  final DateTime? createdAt;
  final double? unitPriceDelta;
}

/// Durum geçmişi satırı (`DocTimelineItemDto`).
@immutable
class DocTimelineItem {
  const DocTimelineItem({
    required this.fromStatus,
    required this.toStatus,
    this.note,
    this.changedAt,
    this.changedByDisplay = '',
  });

  factory DocTimelineItem.fromJson(JsonReader r) => DocTimelineItem(
    fromStatus: r.enumOf('fromStatus', OrderStatus.fromCode),
    toStatus: r.enumOf('toStatus', OrderStatus.fromCode),
    note: r.nonEmpty('note'),
    changedAt: r.dateTr('changedAt'),
    changedByDisplay: r.str('changedByDisplay'),
  );

  final OrderStatus fromStatus;
  final OrderStatus toStatus;
  final String? note;
  final DateTime? changedAt;
  final String changedByDisplay;
}

/// Belgedeki sevkiyat (`DocShipmentDto`).
@immutable
class DocShipment {
  const DocShipment({
    required this.id,
    this.orderId = 0,
    this.seq = 0,
    this.seqCount = 0,
    required this.plannedLiters,
    this.deliveredLiters,
    this.scheduledAt,
    this.deliveredAt,
    this.acceptedAt,
    this.vehiclePlate = '',
    this.driverName = '',
    this.deliveryDocumentNo,
    required this.status,
    this.createdByDisplay = '',
    this.acceptedByDisplay,
    this.disputeNote,
  });

  factory DocShipment.fromJson(JsonReader r) => DocShipment(
    id: r.integer('id'),
    orderId: r.integer('orderId'),
    seq: r.integer('seq'),
    seqCount: r.integer('seqCount'),
    plannedLiters: r.dec('plannedLiters'),
    deliveredLiters: r.decOrNull('deliveredLiters'),
    scheduledAt: r.dateTr('scheduledAt'),
    deliveredAt: r.dateTr('deliveredAt'),
    acceptedAt: r.dateTr('acceptedAt'),
    vehiclePlate: r.str('vehiclePlate'),
    driverName: r.str('driverName'),
    deliveryDocumentNo: r.nonEmpty('deliveryDocumentNo'),
    status: r.enumOf('status', ShipmentStatus.fromCode),
    createdByDisplay: r.str('createdByDisplay'),
    acceptedByDisplay: r.nonEmpty('acceptedByDisplay'),
    disputeNote: r.nonEmpty('disputeNote'),
  );

  final int id;
  final int orderId;
  final int seq;
  final int seqCount;
  final double plannedLiters;
  final double? deliveredLiters;
  final DateTime? scheduledAt;
  final DateTime? deliveredAt;
  final DateTime? acceptedAt;
  final String vehiclePlate;
  final String driverName;
  final String? deliveryDocumentNo;
  final ShipmentStatus status;
  final String createdByDisplay;
  final String? acceptedByDisplay;
  final String? disputeNote;

  String get code => DocCodes.shipment(id);
  String get receiptCode => DocCodes.receipt(id);
  bool get isCancelled => status == ShipmentStatus.cancelled;
  bool get isDelivered =>
      deliveredLiters != null &&
      (status == ShipmentStatus.reported ||
          status == ShipmentStatus.accepted ||
          status == ShipmentStatus.disputed);
  double? get differenceLiters =>
      deliveredLiters == null ? null : deliveredLiters! - plannedLiters;
}

/// Sipariş belgeleri (sipariş formu, teklif, mutabakat) ve sevkiyat belgelerinin ortak başlığı
/// (`OrderDocumentDto`). Hesaplanan alanlar sunucudan okunur; yoksa aynı kural yerelde uygulanır.
@immutable
class OrderDocument {
  const OrderDocument({
    required this.id,
    required this.orderNumber,
    required this.status,
    this.statusLabel,
    required this.quantityLiters,
    this.requestedDeliveryDate,
    this.createdAt,
    this.expiresAt,
    this.expiryEnabled = false,
    this.productCode = '',
    this.productName = '',
    this.station = const DocParty(),
    this.customer = const DocParty(),
    this.distributorBrand = '',
    this.deliveryPointName = '',
    this.deliveryPointCity = '',
    this.deliveryPointDistrict = '',
    this.deliveryAddress = '',
    this.deliveryPointContactName,
    this.deliveryPointContactPhone,
    this.deliveryWindowStart,
    this.deliveryWindowEnd,
    this.deliveryPointTankLiters,
    this.deliveryPointLatitude,
    this.deliveryPointLongitude,
    this.deliveryPointAccessNotes,
    this.pricesLoaded = false,
    this.quotes = const [],
    this.selectedQuote,
    this.shipments = const [],
    this.acceptedLiters = 0,
    this.inProcessLiters = 0,
    this.timeline = const [],
    this.approvedEvent,
    this.printedAt,
    this.printedBy = '',
    this.paymentLine = 'Belirtilmemiş',
    this.paymentStatusText,
    this.hasPayment = false,
    this.paymentDueDate,
    this.paymentDetails = const [],
  });

  factory OrderDocument.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final snapshot = r.nonEmpty('deliveryAddressSnapshot');
    final quotes = r.list('quotes', DocQuote.fromJson)
      ..sort((a, b) => a.version.compareTo(b.version));
    return OrderDocument(
      id: r.integer('id'),
      orderNumber: r.str('orderNumber'),
      status: r.enumOf('status', OrderStatus.fromCode),
      statusLabel: r.nonEmpty('statusLabel'),
      quantityLiters: r.dec('quantityLiters'),
      requestedDeliveryDate: r.dateTr('requestedDeliveryDate'),
      createdAt: r.dateTr('createdAt'),
      expiresAt: r.dateTr('expiresAt'),
      expiryEnabled: r.boolean('expiryEnabled'),
      productCode: r.str('productCode'),
      productName: r.str('productName'),
      station: DocParty.fromJson(r.obj('station')),
      customer: DocParty.fromJson(r.obj('customer')),
      distributorBrand: r.str('distributorBrand'),
      deliveryPointName: r.str('deliveryPointName'),
      deliveryPointCity: r.str('deliveryPointCity'),
      deliveryPointDistrict: r.str('deliveryPointDistrict'),
      deliveryAddress:
          r.nonEmpty('deliveryAddress') ??
          snapshot ??
          r.str('deliveryPointAddress'),
      deliveryPointContactName: r.nonEmpty('deliveryPointContactName'),
      deliveryPointContactPhone: r.nonEmpty('deliveryPointContactPhone'),
      deliveryWindowStart: WindowTime.tryParse(r['deliveryWindowStart']),
      deliveryWindowEnd: WindowTime.tryParse(r['deliveryWindowEnd']),
      deliveryPointTankLiters: r.decOrNull('deliveryPointTankLiters'),
      deliveryPointLatitude: r.decOrNull('deliveryPointLatitude'),
      deliveryPointLongitude: r.decOrNull('deliveryPointLongitude'),
      deliveryPointAccessNotes: r.nonEmpty('deliveryPointAccessNotes'),
      pricesLoaded: r.boolean('pricesLoaded'),
      quotes: List.unmodifiable(quotes),
      selectedQuote: r.objOrNull('selectedQuote') == null
          ? null
          : DocQuote.fromJson(r.obj('selectedQuote')),
      shipments: List.unmodifiable(
        r.list('shipments', DocShipment.fromJson)
          ..sort((a, b) => a.id.compareTo(b.id)),
      ),
      acceptedLiters: r.dec('acceptedLiters'),
      inProcessLiters: r.dec('inProcessLiters'),
      timeline: List.unmodifiable(r.list('timeline', DocTimelineItem.fromJson)),
      approvedEvent: r.objOrNull('approvedEvent') == null
          ? null
          : DocTimelineItem.fromJson(r.obj('approvedEvent')),
      printedAt: r.dateTr('printedAt'),
      printedBy: r.str('printedBy'),
      paymentLine: r.nonEmpty('paymentLine') ?? 'Belirtilmemiş',
      paymentStatusText: r.nonEmpty('paymentStatusText'),
      hasPayment:
          r.boolOrNull('hasPayment') ?? r.nonEmpty('paymentMethodCode') != null,
      paymentDueDate: r.dateTr('paymentDueDate'),
      paymentDetails: List.unmodifiable(
        r.list(
          'paymentDetails',
          (e) => (label: e.str('key'), value: e.str('value')),
        ),
      ),
    );
  }

  final int id;
  final String orderNumber;
  final OrderStatus status;
  final String? statusLabel;
  final double quantityLiters;
  final DateTime? requestedDeliveryDate;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  /// Teklif geçerlilik tarihi yalnızca açıkken basılır.
  final bool expiryEnabled;
  final String productCode;
  final String productName;
  final DocParty station;
  final DocParty customer;
  final String distributorBrand;
  final String deliveryPointName;
  final String deliveryPointCity;
  final String deliveryPointDistrict;

  /// Sipariş anındaki adres (yoksa noktanın güncel adresi).
  final String deliveryAddress;
  final String? deliveryPointContactName;
  final String? deliveryPointContactPhone;
  final WindowTime? deliveryWindowStart;
  final WindowTime? deliveryWindowEnd;
  final double? deliveryPointTankLiters;
  final double? deliveryPointLatitude;
  final double? deliveryPointLongitude;
  final String? deliveryPointAccessNotes;

  /// false ise fiyat verisi hiç yüklenmemiştir (sevk belgesi, tutanak).
  final bool pricesLoaded;

  /// Sürüm sırasıyla (v1, v2, …).
  final List<DocQuote> quotes;
  final DocQuote? selectedQuote;

  /// Id sırasıyla tüm sevkiyatlar (iptaller dahil).
  final List<DocShipment> shipments;
  final double acceptedLiters;
  final double inProcessLiters;
  final List<DocTimelineItem> timeline;
  final DocTimelineItem? approvedEvent;
  final DateTime? printedAt;
  final String printedBy;

  /// "Çek · 90 gün · vade 20.07.2026"; eski sipariş "Belirtilmemiş".
  final String paymentLine;
  final String? paymentStatusText;
  final bool hasPayment;
  final DateTime? paymentDueDate;

  /// Ödeme yöntemi ayrıntıları (fiyatsız belgelerde basılmaz).
  final List<({String label, String value})> paymentDetails;

  bool get isApproved =>
      status == OrderStatus.approved || status == OrderStatus.completed;
  bool get isVoid =>
      status == OrderStatus.rejected || status == OrderStatus.expired;
  bool get isBeforeApproval =>
      status == OrderStatus.created ||
      status == OrderStatus.awaitingQuote ||
      status == OrderStatus.awaitingApproval ||
      status == OrderStatus.revisionRequested;

  List<DocShipment> get activeShipments =>
      shipments.where((s) => !s.isCancelled).toList();
  int get activeShipmentCount => activeShipments.length;
  bool get canReconcile => isApproved && activeShipmentCount > 0;
  double get remainingLiters =>
      (quantityLiters - acceptedLiters).clamp(0, double.infinity).toDouble();
  double get unplannedLiters =>
      (quantityLiters - acceptedLiters - inProcessLiters)
          .clamp(0, double.infinity)
          .toDouble();

  /// Kabul edilen litre × seçili birim fiyat (mutabakat).
  double? get acceptedAmountTry {
    final q = selectedQuote;
    if (q == null) return null;
    return (acceptedLiters * q.unitPriceTry * 100).roundToDouble() / 100;
  }

  String get displayStatus => statusLabel ?? status.label;
}

/// `GET documents/shipments/{id}` (`ShipmentDocumentDto`): sevkiyat + fiyatsız sipariş başlığı.
@immutable
class ShipmentDocument {
  const ShipmentDocument({required this.shipment, required this.order});

  factory ShipmentDocument.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return ShipmentDocument(
      shipment: DocShipment.fromJson(r.obj('shipment')),
      order: OrderDocument.fromJson(r.map('order')),
    );
  }

  final DocShipment shipment;
  final OrderDocument order;
}

/// Boş olmayan parçaları birleştirir (sunucu `DocumentText.JoinNonEmpty`).
String joinNonEmpty(String separator, Iterable<String?> parts) => parts
    .where((p) => p != null && p.trim().isNotEmpty)
    .map((p) => p!.trim())
    .join(separator);
