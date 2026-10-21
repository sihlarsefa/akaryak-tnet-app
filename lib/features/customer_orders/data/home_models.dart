import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';
import '../../../core/utils/turkish_text.dart';
import 'form_models.dart';
import 'payment_models.dart';

/// Bayide sipariş verilebilirlik (`CustomerOrderingStatusDto`; `customers/me/ordering-status`).
@immutable
class OrderingStatus {
  const OrderingStatus({
    this.stationId = 0,
    this.customerId = 0,
    this.stationCustomerId,
    this.canOrder = true,
    this.blockReason,
    this.isGrandfathered = false,
    this.profileStatus,
    this.infoRequested = false,
    this.openApprovalRequestId,
  });

  factory OrderingStatus.fromJson(JsonReader r) => OrderingStatus(
    stationId: r.integer('stationId'),
    customerId: r.integer('customerId'),
    stationCustomerId: r.intOrNull('stationCustomerId'),
    canOrder: r.boolean('canOrder', true),
    blockReason: r.nonEmpty('blockReason'),
    isGrandfathered: r.boolean('isGrandfathered'),
    profileStatus: r.has('profileStatus')
        ? r.enumOf('profileStatus', FinanceProfileStatus.fromCode)
        : null,
    infoRequested: r.boolean('infoRequested'),
    openApprovalRequestId: r.intOrNull('openApprovalRequestId'),
  );

  static OrderingStatus parse(Object? json) =>
      OrderingStatus.fromJson(JsonReader.of(json));

  final int stationId;
  final int customerId;
  final int? stationCustomerId;
  final bool canOrder;
  final String? blockReason;
  final bool isGrandfathered;
  final FinanceProfileStatus? profileStatus;

  /// Finans ek bilgi / belge istedi ("Yanıtla").
  final bool infoRequested;
  final int? openApprovalRequestId;

  JsonMap toJson() => {
    'stationId': stationId,
    'customerId': customerId,
    'stationCustomerId': stationCustomerId,
    'canOrder': canOrder,
    'blockReason': blockReason,
    'isGrandfathered': isGrandfathered,
    'profileStatus': profileStatus?.code,
    'infoRequested': infoRequested,
    'openApprovalRequestId': openApprovalRequestId,
  };
}

/// Varsayılan bayinin iletişim bilgisi (`CustomerHomeStationDto`).
@immutable
class StationContact {
  const StationContact({
    required this.id,
    required this.title,
    this.phone,
    this.gsm,
    this.email,
    this.city,
  });

  factory StationContact.fromJson(JsonReader r) => StationContact(
    id: r.integer('id'),
    title: r.str('title'),
    phone: r.nonEmpty('phone'),
    gsm: r.nonEmpty('gsm'),
    email: r.nonEmpty('email'),
    city: r.nonEmpty('city'),
  );

  final int id;
  final String title;
  final String? phone;

  /// Cep telefonu (WhatsApp).
  final String? gsm;
  final String? email;
  final String? city;

  /// Aranacak numara: sabit hat, yoksa cep.
  String? get callNumber => phone ?? gsm;

  /// WhatsApp için cep numarası (yalnızca 5XX ile başlayan cep).
  String? get whatsappNumber {
    for (final n in [gsm, phone]) {
      final d = (n ?? '').replaceAll(RegExp(r'\D'), '');
      var ten = d;
      if (d.length == 12 && d.startsWith('90')) ten = d.substring(2);
      if (d.length == 11 && d.startsWith('0')) ten = d.substring(1);
      if (ten.length == 10 && ten.startsWith('5')) return '90$ten';
    }
    return null;
  }

  JsonMap toJson() => {
    'id': id,
    'title': title,
    'phone': phone,
    'gsm': gsm,
    'email': email,
    'city': city,
  };
}

/// Bağlı bayi (`CustomerStationOptionDto`): sihirbazın bayi seçicisi.
@immutable
class StationOption {
  const StationOption({
    required this.id,
    required this.title,
    this.canOrder = true,
    this.blockReason,
  });

  factory StationOption.fromJson(JsonReader r) => StationOption(
    id: r.integer('id'),
    title: r.str('title'),
    canOrder: r.boolean('canOrder', true),
    blockReason: r.nonEmpty('blockReason'),
  );

  final int id;
  final String title;
  final bool canOrder;
  final String? blockReason;
}

/// Bayi başına limit kullanımı (`CustomerLimitDto`; Limitlerim).
@immutable
class CustomerLimit {
  const CustomerLimit({
    required this.stationId,
    required this.stationTitle,
    this.type,
    this.period,
    this.periodLabel = '',
    this.amount,
    this.used = 0,
    this.remaining,
    this.usedPct = 0,
    this.unit = 'TL',
    this.hasLimit = false,
  });

  factory CustomerLimit.fromJson(JsonReader r) => CustomerLimit(
    stationId: r.integer('stationId'),
    stationTitle: r.str('stationTitle'),
    type: r.nonEmpty('type'),
    period: r.nonEmpty('period'),
    periodLabel: r.str('periodLabel'),
    amount: r.decOrNull('amount'),
    used: r.dec('used'),
    remaining: r.decOrNull('remaining'),
    usedPct: r.dec('usedPct'),
    unit: r.str('unit', 'TL'),
    hasLimit: r.boolean('hasLimit'),
  );

  final int stationId;
  final String stationTitle;

  /// "Tutar" / "Litre".
  final String? type;
  final String? period;
  final String periodLabel;
  final double? amount;
  final double used;
  final double? remaining;

  /// Kırpılmamış yüzde (≥ 100 limit dolu).
  final double usedPct;

  /// "TL" ya da "L".
  final String unit;
  final bool hasLimit;

  bool get isLiters => unit.trim().asciiUpper == 'L';
}

/// Şirket içi onay kuralı (`CustomerCompanyApprovalDto`; yalnızca Talep eden).
@immutable
class CompanyApprovalRule {
  const CompanyApprovalRule({
    this.required = false,
    this.aboveLitres,
    this.aboveAmount,
    this.text = '',
  });

  factory CompanyApprovalRule.fromJson(JsonReader r) => CompanyApprovalRule(
    required: r.boolean('required'),
    aboveLitres: r.decOrNull('aboveLitres'),
    aboveAmount: r.decOrNull('aboveAmount'),
    text: r.str('text'),
  );

  final bool required;
  final double? aboveLitres;
  final double? aboveAmount;
  final String text;

  /// Sunucu kuralının portu (`CustomerApprovalRules.RequiresApproval`): litre eşiği aşılırsa onay;
  /// tutar eşiği varsa tahmini tutar aşılırsa onay; tutar bilinmiyorsa ve litre eşiği yoksa
  /// güvenli taraf (onay).
  bool predicts({required double totalLiters, double? estimatedAmount}) {
    if (!required) return false;
    final litres = aboveLitres;
    if (litres != null && totalLiters > litres) return true;
    final amount = aboveAmount;
    if (amount != null) {
      if (estimatedAmount != null) return estimatedAmount > amount;
      return litres == null;
    }
    return false;
  }
}

/// Yüklenmesi beklenen ödeme belgesi (`CustomerPendingPaymentDocumentDto`).
@immutable
class PendingPaymentDocument {
  const PendingPaymentDocument({
    required this.orderId,
    required this.orderNumber,
    this.stationTitle,
    this.methodCode,
    this.methodName,
    this.kind = AttachmentKind.unknown,
    this.kindLabel,
    this.required = false,
    required this.target,
  });

  factory PendingPaymentDocument.fromJson(JsonReader r) =>
      PendingPaymentDocument(
        orderId: r.integer('orderId'),
        orderNumber: r.str('orderNumber'),
        stationTitle: r.nonEmpty('stationTitle'),
        methodCode: r.nonEmpty('methodCode'),
        methodName: r.nonEmpty('methodName'),
        kind: r.enumOf('kind', AttachmentKind.fromCode),
        kindLabel: r.nonEmpty('kindLabel'),
        required: r.boolean('required'),
        target: PaymentUploadTarget.fromJson(r.obj('target')),
      );

  final int orderId;
  final String orderNumber;
  final String? stationTitle;
  final String? methodCode;
  final String? methodName;
  final AttachmentKind kind;
  final String? kindLabel;
  final bool required;
  final PaymentUploadTarget target;

  String get label => kindLabel ?? kind.label;
}

/// Müşteri paneli istatistikleri (`CustomerDashboardStatsDto`).
@immutable
class CustomerDashboardStats {
  const CustomerDashboardStats({
    this.monthOrders = 0,
    this.monthLiters = 0,
    this.monthAmount = 0,
    this.prevMonthOrders = 0,
    this.prevMonthLiters = 0,
    this.prevMonthAmount = 0,
    this.limits = const [],
  });

  factory CustomerDashboardStats.fromJson(JsonReader r) =>
      CustomerDashboardStats(
        monthOrders: r.integer('monthOrders'),
        monthLiters: r.dec('monthLiters'),
        monthAmount: r.dec('monthAmount'),
        prevMonthOrders: r.integer('prevMonthOrders'),
        prevMonthLiters: r.dec('prevMonthLiters'),
        prevMonthAmount: r.dec('prevMonthAmount'),
        limits: List.unmodifiable(
          r.list('limits', DashboardLimitUsage.fromJson),
        ),
      );

  final int monthOrders;
  final double monthLiters;
  final double monthAmount;
  final int prevMonthOrders;
  final double prevMonthLiters;
  final double prevMonthAmount;
  final List<DashboardLimitUsage> limits;
}

/// Müşteri paneli (`CustomerDashboardDto`; bölümler kullanıcının sayfa yetkisine göre dolar).
@immutable
class CustomerDashboard {
  const CustomerDashboard({
    this.customerIsActive = true,
    this.canPurchaseFuel = true,
    this.expiryEnabled = true,
    this.pendingDecisions = const [],
    this.pendingDecisionTotal = 0,
    this.pendingDecisionExpiringTotal = 0,
    this.awaitingStation = const [],
    this.awaitingQuoteTotal = 0,
    this.revisionRequestedTotal = 0,
    this.shipments = const [],
    this.plannedShipmentTotal = 0,
    this.inTransitShipmentTotal = 0,
    this.reportedShipmentTotal = 0,
    this.disputedShipmentTotal = 0,
    this.lastOrder,
    this.stats,
    this.statsFailed = false,
  });

  factory CustomerDashboard.fromJson(JsonReader r) => CustomerDashboard(
    customerIsActive: r.boolean('customerIsActive', true),
    canPurchaseFuel: r.boolean('canPurchaseFuel', true),
    expiryEnabled: r.boolean('expiryEnabled', true),
    pendingDecisions: List.unmodifiable(
      r.list('pendingDecisions', DashboardOrderRow.fromJson),
    ),
    pendingDecisionTotal: r.integer('pendingDecisionTotal'),
    pendingDecisionExpiringTotal: r.integer('pendingDecisionExpiringTotal'),
    awaitingStation: List.unmodifiable(
      r.list('awaitingStation', DashboardOrderRow.fromJson),
    ),
    awaitingQuoteTotal: r.integer('awaitingQuoteTotal'),
    revisionRequestedTotal: r.integer('revisionRequestedTotal'),
    shipments: List.unmodifiable(
      r.list('shipments', DashboardShipmentRow.fromJson),
    ),
    plannedShipmentTotal: r.integer('plannedShipmentTotal'),
    inTransitShipmentTotal: r.integer('inTransitShipmentTotal'),
    reportedShipmentTotal: r.integer('reportedShipmentTotal'),
    disputedShipmentTotal: r.integer('disputedShipmentTotal'),
    lastOrder: r.objOrNull('lastOrder') == null
        ? null
        : DashboardLastOrder.fromJson(r.obj('lastOrder')),
    stats: r.objOrNull('stats') == null
        ? null
        : CustomerDashboardStats.fromJson(r.obj('stats')),
    statsFailed: r.boolean('statsFailed'),
  );

  final bool customerIsActive;
  final bool canPurchaseFuel;
  final bool expiryEnabled;
  final List<DashboardOrderRow> pendingDecisions;
  final int pendingDecisionTotal;
  final int pendingDecisionExpiringTotal;
  final List<DashboardOrderRow> awaitingStation;
  final int awaitingQuoteTotal;
  final int revisionRequestedTotal;
  final List<DashboardShipmentRow> shipments;
  final int plannedShipmentTotal;
  final int inTransitShipmentTotal;
  final int reportedShipmentTotal;
  final int disputedShipmentTotal;
  final DashboardLastOrder? lastOrder;
  final CustomerDashboardStats? stats;
  final bool statsFailed;

  int get awaitingStationTotal => awaitingQuoteTotal + revisionRequestedTotal;
  int get openShipmentTotal =>
      plannedShipmentTotal +
      inTransitShipmentTotal +
      reportedShipmentTotal +
      disputedShipmentTotal;

  /// Ana sayfanın "teslimat" kartı: yolda olan, yoksa kabul bekleyen, yoksa planlı sevkiyat.
  DashboardShipmentRow? get activeShipment {
    for (final s in [
      ShipmentStatus.inTransit,
      ShipmentStatus.reported,
      ShipmentStatus.disputed,
      ShipmentStatus.planned,
    ]) {
      for (final row in shipments) {
        if (row.status == s) return row;
      }
    }
    return null;
  }
}

/// `GET home/customer` (`CustomerHomeDto`, spec B.6).
@immutable
class CustomerHomeData {
  const CustomerHomeData({
    required this.customerId,
    required this.customerTitle,
    this.stationId,
    this.stationTitle,
    this.ordering,
    this.dashboard = const CustomerDashboard(),
    this.companyApprovalsWaiting = 0,
    this.financeInfoRequests = 0,
    this.templates = const [],
    this.station,
    this.stations = const [],
    this.limits = const [],
    this.companyApproval,
    this.suggestedDeliveryDate,
    this.minDeliveryDate,
    this.pendingPaymentDocuments = const [],
  });

  factory CustomerHomeData.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return CustomerHomeData(
      customerId: r.integer('customerId'),
      customerTitle: r.str('customerTitle'),
      stationId: r.intOrNull('stationId'),
      stationTitle: r.nonEmpty('stationTitle'),
      ordering: r.objOrNull('ordering') == null
          ? null
          : OrderingStatus.fromJson(r.obj('ordering')),
      dashboard: CustomerDashboard.fromJson(r.obj('dashboard')),
      companyApprovalsWaiting: r.integer('companyApprovalsWaiting'),
      financeInfoRequests: r.integer('financeInfoRequests'),
      templates: List.unmodifiable(
        r.list('templates', TemplateListItem.fromJson),
      ),
      station: r.objOrNull('station') == null
          ? null
          : StationContact.fromJson(r.obj('station')),
      stations: List.unmodifiable(r.list('stations', StationOption.fromJson)),
      limits: List.unmodifiable(r.list('limits', CustomerLimit.fromJson)),
      companyApproval: r.objOrNull('companyApproval') == null
          ? null
          : CompanyApprovalRule.fromJson(r.obj('companyApproval')),
      suggestedDeliveryDate: r.date('suggestedDeliveryDate'),
      minDeliveryDate: r.date('minDeliveryDate'),
      pendingPaymentDocuments: List.unmodifiable(
        r.list('pendingPaymentDocuments', PendingPaymentDocument.fromJson),
      ),
    );
  }

  final int customerId;
  final String customerTitle;

  /// Varsayılan bayi (ilk aktif bağlantı).
  final int? stationId;
  final String? stationTitle;
  final OrderingStatus? ordering;
  final CustomerDashboard dashboard;
  final int companyApprovalsWaiting;
  final int financeInfoRequests;
  final List<TemplateListItem> templates;
  final StationContact? station;
  final List<StationOption> stations;
  final List<CustomerLimit> limits;
  final CompanyApprovalRule? companyApproval;

  /// Türkiye gece yarısı (an).
  final DateTime? suggestedDeliveryDate;
  final DateTime? minDeliveryDate;
  final List<PendingPaymentDocument> pendingPaymentDocuments;

  bool get hasStations => stations.isNotEmpty;

  /// Varsayılan bayide sipariş verilebilir mi.
  bool get canOrder => ordering?.canOrder ?? hasStations;

  StationOption? stationById(int? id) {
    if (id == null) return null;
    for (final s in stations) {
      if (s.id == id) return s;
    }
    return null;
  }
}
