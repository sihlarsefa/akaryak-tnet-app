import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/turkish_text.dart';
import 'bayi_json.dart';
import 'home_models.dart';

/// Sunucunun limit tonu (`ok | warn | danger | none`) → arayüz tonu (none → null).
AknTone? limitTone(String? key) => switch (key?.trim().asciiLower) {
  'ok' => AknTone.ok,
  'warn' => AknTone.warn,
  'danger' => AknTone.danger,
  _ => null,
};

/// Cariler listesi satırı (`BayiCustomerRowDto`).
@immutable
class BayiCustomerRow {
  const BayiCustomerRow({
    required this.customerId,
    required this.title,
    this.stationCustomerId,
    this.city,
    this.district,
    this.code,
    this.phone,
    this.limitUsagePct,
    this.limitTone,
    this.financeStatus,
    this.financeStatusLabel,
    this.lastOrderAt,
    this.openOrders = 0,
  });

  factory BayiCustomerRow.fromJson(JsonReader r) => BayiCustomerRow(
    customerId: r.integer('customerId'),
    stationCustomerId: r.intOrNull('stationCustomerId'),
    title: r.str('title'),
    city: r.nonEmpty('city'),
    district: r.nonEmpty('district'),
    code: r.nonEmpty('code'),
    phone: r.nonEmpty('phone'),
    limitUsagePct: r.decOrNull('limitUsagePct'),
    limitTone: r.nonEmpty('limitTone'),
    financeStatus: r.intOrNull('financeStatus') == null
        ? null
        : r.enumOf('financeStatus', FinanceProfileStatus.fromCode),
    financeStatusLabel: r.nonEmpty('financeStatusLabel'),
    lastOrderAt: r.dateTr('lastOrderAt'),
    openOrders: r.integer('openOrders'),
  );

  final int customerId;
  final int? stationCustomerId;
  final String title;
  final String? city;
  final String? district;
  final String? code;
  final String? phone;

  /// Dönem limit kullanımı (%); limitsizse null.
  final double? limitUsagePct;
  final String? limitTone;
  final FinanceProfileStatus? financeStatus;
  final String? financeStatusLabel;
  final DateTime? lastOrderAt;
  final int openOrders;

  String? get place => [?district, ?city].join(' / ').ifEmptyNull;
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}

/// Cari yetkilisi.
@immutable
class SummaryContact {
  const SummaryContact({required this.name, this.role, this.phone, this.email});

  factory SummaryContact.fromJson(JsonReader r) => SummaryContact(
    name: r.str('name'),
    role: r.nonEmpty('role'),
    phone: r.nonEmpty('phone'),
    email: r.nonEmpty('email'),
  );

  final String name;
  final String? role;
  final String? phone;
  final String? email;
}

/// Teslimat noktası (`CustomerSummaryDeliveryPointDto`).
@immutable
class SummaryDeliveryPoint {
  const SummaryDeliveryPoint({
    required this.id,
    required this.name,
    this.city,
    this.district,
    this.address,
    this.hasCoordinates = false,
    this.windowStart,
    this.windowEnd,
    this.tankCapacityLiters,
    this.contactName,
    this.contactPhone,
    this.latitude,
    this.longitude,
    this.accessNotes,
  });

  factory SummaryDeliveryPoint.fromJson(JsonReader r) => SummaryDeliveryPoint(
    id: r.integer('id'),
    name: r.str('name'),
    city: r.nonEmpty('city'),
    district: r.nonEmpty('district'),
    address: r.nonEmpty('address'),
    hasCoordinates: r.boolean('hasCoordinates'),
    windowStart: BayiJson.windowTime(r.strOrNull('windowStart')),
    windowEnd: BayiJson.windowTime(r.strOrNull('windowEnd')),
    tankCapacityLiters: r.decOrNull('tankCapacityLiters'),
    contactName: r.nonEmpty('contactName'),
    contactPhone: r.nonEmpty('contactPhone'),
    latitude: r.decOrNull('latitude'),
    longitude: r.decOrNull('longitude'),
    accessNotes: r.nonEmpty('accessNotes'),
  );

  final int id;
  final String name;
  final String? city;
  final String? district;
  final String? address;
  final bool hasCoordinates;
  final String? windowStart;
  final String? windowEnd;
  final double? tankCapacityLiters;
  final String? contactName;
  final String? contactPhone;
  final double? latitude;
  final double? longitude;
  final String? accessNotes;

  String? get window => BayiJson.windowLabel(windowStart, windowEnd);
  bool get canOpenMap => latitude != null && longitude != null;
}

/// Bu bayideki limit ve kullanım.
@immutable
class SummaryLimit {
  const SummaryLimit({
    this.amount,
    this.used = 0,
    this.period,
    this.periodLabel,
    this.usagePct,
    this.unit = 'TL',
    this.remaining,
    this.limitType,
    this.tone,
  });

  factory SummaryLimit.fromJson(JsonReader r) => SummaryLimit(
    amount: r.decOrNull('amount'),
    used: r.dec('used'),
    period: r.nonEmpty('period'),
    periodLabel: r.nonEmpty('periodLabel'),
    usagePct: r.decOrNull('usagePct'),
    unit: r.str('unit', 'TL'),
    remaining: r.decOrNull('remaining'),
    limitType: r.nonEmpty('limitType'),
    tone: r.nonEmpty('tone'),
  );

  /// Dönem limiti; null = limitsiz.
  final double? amount;
  final double used;
  final String? period;
  final String? periodLabel;
  final double? usagePct;

  /// `TL` ya da `L`.
  final String unit;
  final double? remaining;
  final String? limitType;
  final String? tone;

  bool get isUnlimited => amount == null;
  bool get isLiters => unit.asciiUpper == 'L';
}

/// Sipariş verilebilirlik özeti.
@immutable
class SummaryFinance {
  const SummaryFinance({
    this.status,
    this.label = '',
    this.canOrder = true,
    this.blockReason,
  });

  factory SummaryFinance.fromJson(JsonReader r) => SummaryFinance(
    status: r.intOrNull('status') == null
        ? null
        : r.enumOf('status', FinanceProfileStatus.fromCode),
    label: r.str('label'),
    canOrder: r.boolean('canOrder', true),
    blockReason: r.nonEmpty('blockReason'),
  );

  final FinanceProfileStatus? status;
  final String label;
  final bool canOrder;
  final String? blockReason;
}

/// Cari kartındaki sipariş satırı.
@immutable
class SummaryOrder {
  const SummaryOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    this.statusLabel,
    this.productName,
    this.quantityLiters = 0,
    this.totalAmount,
    this.createdAt,
  });

  factory SummaryOrder.fromJson(JsonReader r) => SummaryOrder(
    id: r.integer('id'),
    orderNumber: r.str('orderNumber'),
    status: r.enumOf('status', OrderStatus.fromCode),
    statusLabel: r.nonEmpty('statusLabel'),
    productName: r.nonEmpty('productName'),
    quantityLiters: r.dec('quantityLiters'),
    totalAmount: r.decOrNull('totalAmount'),
    createdAt: r.dateTr('createdAt'),
  );

  final int id;
  final String orderNumber;
  final OrderStatus status;
  final String? statusLabel;
  final String? productName;
  final double quantityLiters;
  final double? totalAmount;
  final DateTime? createdAt;
}

/// Görüşme notu (`CustomerNoteDto`; tarih UTC).
@immutable
class CustomerNote {
  const CustomerNote({
    required this.id,
    required this.body,
    this.createdAt,
    this.createdByDisplay = '',
    this.canDelete = false,
  });

  factory CustomerNote.fromJson(JsonReader r) => CustomerNote(
    id: r.integer('id'),
    body: r.str('body'),
    createdAt: r.dateUtc('createdAt'),
    createdByDisplay: r.str('createdByDisplay'),
    canDelete: r.boolean('canDelete'),
  );

  final int id;
  final String body;
  final DateTime? createdAt;
  final String createdByDisplay;
  final bool canDelete;
}

/// Kartın eylem bayrakları (`CustomerSummaryActionsDto`; sunucu yine denetler).
@immutable
class SummaryActions {
  const SummaryActions({
    this.canAddNote = false,
    this.canRequestLimit = false,
    this.canCreateFieldForm = false,
    this.canQuote = false,
    this.canViewNotes = false,
  });

  factory SummaryActions.fromJson(JsonReader r) => SummaryActions(
    canAddNote: r.boolean('canAddNote'),
    canRequestLimit: r.boolean('canRequestLimit'),
    canCreateFieldForm: r.boolean('canCreateFieldForm'),
    canQuote: r.boolean('canQuote'),
    canViewNotes: r.boolean('canViewNotes'),
  );

  final bool canAddNote;
  final bool canRequestLimit;
  final bool canCreateFieldForm;
  final bool canQuote;
  final bool canViewNotes;
}

/// Tahsilat özeti (yalnızca StationPayments Görür).
@immutable
class SummaryCollections {
  const SummaryCollections({
    this.overdueCount = 0,
    this.overdueAmount = 0,
    this.openInstruments = 0,
    this.nextInstrumentDue,
    this.advanceBalance,
  });

  factory SummaryCollections.fromJson(JsonReader r) => SummaryCollections(
    overdueCount: r.integer('overdueCount'),
    overdueAmount: r.dec('overdueAmount'),
    openInstruments: r.integer('openInstruments'),
    nextInstrumentDue: r.date('nextInstrumentDue'),
    advanceBalance: r.decOrNull('advanceBalance'),
  );

  final int overdueCount;
  final double overdueAmount;
  final int openInstruments;
  final DateTime? nextInstrumentDue;
  final double? advanceBalance;
}

/// Finans kartı özeti (yalnızca StationFinance Görür).
@immutable
class SummaryFinanceCard {
  const SummaryFinanceCard({
    required this.stationCustomerId,
    this.status,
    this.statusLabel,
    this.riskClass = RiskClass.none,
    this.riskClassLabel,
    this.nextReviewDate,
    this.hasBouncedCheque = false,
    this.hasProtestedNote = false,
    this.hasProfile = false,
    this.isGrandfathered = false,
  });

  factory SummaryFinanceCard.fromJson(JsonReader r) => SummaryFinanceCard(
    stationCustomerId: r.integer('stationCustomerId'),
    status: r.intOrNull('status') == null
        ? null
        : r.enumOf('status', FinanceProfileStatus.fromCode),
    statusLabel: r.nonEmpty('statusLabel'),
    riskClass: r.enumOf('riskClass', RiskClass.fromCode),
    riskClassLabel: r.nonEmpty('riskClassLabel'),
    nextReviewDate: r.date('nextReviewDate'),
    hasBouncedCheque: r.boolean('hasBouncedCheque'),
    hasProtestedNote: r.boolean('hasProtestedNote'),
    hasProfile: r.boolean('hasProfile'),
    isGrandfathered: r.boolean('isGrandfathered'),
  );

  final int stationCustomerId;
  final FinanceProfileStatus? status;
  final String? statusLabel;
  final RiskClass riskClass;
  final String? riskClassLabel;
  final DateTime? nextReviewDate;
  final bool hasBouncedCheque;
  final bool hasProtestedNote;
  final bool hasProfile;
  final bool isGrandfathered;
}

/// Bekleyen limit talebi (merkez onayında).
@immutable
class SummaryLimitRequest {
  const SummaryLimitRequest({
    required this.id,
    this.limitType,
    this.period,
    this.amount,
    this.createdAt,
  });

  factory SummaryLimitRequest.fromJson(JsonReader r) => SummaryLimitRequest(
    id: r.integer('id'),
    limitType: r.nonEmpty('limitType'),
    period: r.nonEmpty('period'),
    amount: r.decOrNull('amount'),
    createdAt: r.dateUtc('createdAt'),
  );

  final int id;
  final String? limitType;
  final String? period;
  final double? amount;
  final DateTime? createdAt;
}

/// `GET bayi/customers/{customerId}/summary` — cari 360-lite kartı (spec B.7 `CustomerSummaryDto`).
@immutable
class CustomerSummary {
  const CustomerSummary({
    required this.customerId,
    required this.title,
    this.stationCustomerId,
    this.taxNumberMasked,
    this.city,
    this.district,
    this.contacts = const [],
    this.deliveryPoints = const [],
    this.limit,
    this.finance = const SummaryFinance(),
    this.openOrders = const [],
    this.lastOrders = const [],
    this.openForms = const [],
    this.notes = const [],
    this.actions = const SummaryActions(),
    this.collections,
    this.financeCard,
    this.pendingLimitRequest,
    this.isPortfolioView = false,
    this.code,
    this.isActive = true,
  });

  factory CustomerSummary.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final limit = r.objOrNull('limit');
    final collections = r.objOrNull('collections');
    final card = r.objOrNull('financeCard');
    final pending = r.objOrNull('pendingLimitRequest');
    return CustomerSummary(
      customerId: r.integer('customerId'),
      stationCustomerId: r.intOrNull('stationCustomerId'),
      title: r.str('title'),
      taxNumberMasked: r.nonEmpty('taxNumberMasked'),
      city: r.nonEmpty('city'),
      district: r.nonEmpty('district'),
      contacts: List.unmodifiable(r.list('contacts', SummaryContact.fromJson)),
      deliveryPoints: List.unmodifiable(
        r.list('deliveryPoints', SummaryDeliveryPoint.fromJson),
      ),
      limit: limit == null ? null : SummaryLimit.fromJson(limit),
      finance: SummaryFinance.fromJson(r.obj('finance')),
      openOrders: List.unmodifiable(
        r.list('openOrders', SummaryOrder.fromJson),
      ),
      lastOrders: List.unmodifiable(
        r.list('lastOrders', SummaryOrder.fromJson),
      ),
      openForms: List.unmodifiable(
        r.list('openForms', BayiFieldFormRow.fromJson),
      ),
      notes: List.unmodifiable(r.list('notes', CustomerNote.fromJson)),
      actions: SummaryActions.fromJson(r.obj('actions')),
      collections: collections == null
          ? null
          : SummaryCollections.fromJson(collections),
      financeCard: card == null ? null : SummaryFinanceCard.fromJson(card),
      pendingLimitRequest: pending == null
          ? null
          : SummaryLimitRequest.fromJson(pending),
      isPortfolioView: r.boolean('isPortfolioView'),
      code: r.nonEmpty('code'),
      isActive: r.boolean('isActive', true),
    );
  }

  final int customerId;
  final int? stationCustomerId;
  final String title;
  final String? taxNumberMasked;
  final String? city;
  final String? district;
  final List<SummaryContact> contacts;
  final List<SummaryDeliveryPoint> deliveryPoints;
  final SummaryLimit? limit;
  final SummaryFinance finance;
  final List<SummaryOrder> openOrders;
  final List<SummaryOrder> lastOrders;
  final List<BayiFieldFormRow> openForms;
  final List<CustomerNote> notes;
  final SummaryActions actions;
  final SummaryCollections? collections;
  final SummaryFinanceCard? financeCard;
  final SummaryLimitRequest? pendingLimitRequest;
  final bool isPortfolioView;
  final String? code;
  final bool isActive;

  String? get place => [?district, ?city].join(' / ').ifEmptyNull;

  CustomerSummary withNotes(List<CustomerNote> next) => CustomerSummary(
    customerId: customerId,
    title: title,
    stationCustomerId: stationCustomerId,
    taxNumberMasked: taxNumberMasked,
    city: city,
    district: district,
    contacts: contacts,
    deliveryPoints: deliveryPoints,
    limit: limit,
    finance: finance,
    openOrders: openOrders,
    lastOrders: lastOrders,
    openForms: openForms,
    notes: List.unmodifiable(next),
    actions: actions,
    collections: collections,
    financeCard: financeCard,
    pendingLimitRequest: pendingLimitRequest,
    isPortfolioView: isPortfolioView,
    code: code,
    isActive: isActive,
  );
}

/// Limit talebi seçenekleri (`StationCustomerLimitRules`).
abstract final class LimitOptions {
  static const types = ['Tutar', 'Litre'];
  static const periods = ['Günlük', 'Haftalık', 'Aylık', 'Limitli', 'Limitsiz'];
  static const unlimited = 'Limitsiz';
  static const reasonMax = 1000;
}

/// `POST stations/me/customers/{id}/limit-requests` gövdesi (`CreateLimitChangeRequest`).
@immutable
class LimitRequestDraft {
  const LimitRequestDraft({
    required this.limitPeriod,
    this.limitType,
    this.limitAmount,
    required this.reason,
  });

  final String limitPeriod;
  final String? limitType;
  final double? limitAmount;
  final String reason;

  bool get isUnlimited => limitPeriod == LimitOptions.unlimited;

  JsonMap toJson() => {
    'limitPeriod': limitPeriod,
    'limitType': isUnlimited ? null : limitType,
    'limitAmount': isUnlimited ? null : limitAmount,
    'reason': reason.trim(),
  };
}
