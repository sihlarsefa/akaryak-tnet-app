import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';

/// `BayiHomeSectionKeys` (sunucu): bölüm anahtarları, JSON adlarıyla aynı.
abstract final class BayiHomeSections {
  static const desk = 'desk';
  static const shipments = 'shipments';
  static const approvals = 'approvals';
  static const collections = 'collections';
  static const finance = 'finance';
  static const leads = 'leads';
  static const field = 'field';
  static const setup = 'setup';
  static const sales = 'sales';

  static const all = [
    desk,
    shipments,
    approvals,
    collections,
    finance,
    leads,
    field,
    setup,
    sales,
  ];

  /// Yüklenemeyen bölüm başlığı ("Bu bölüm yüklenemedi" kartı): yerin adı alt menünün kelimesidir
  /// (v4 §3.2: bir yerin tek adı).
  static String title(String key) => switch (key) {
    desk => 'Teklifler',
    shipments => 'Sevkiyat',
    approvals => 'Onaylar',
    collections => 'Tahsilat',
    finance => 'Finans',
    leads => 'Ön kayıtlar',
    field => 'Saha formları',
    setup => 'Kurulum uyarıları',
    sales => 'Satış özeti',
    _ => key,
  };
}

/// `GET home/bayi` (spec B.7 `BayiHomeDto`). Yetkisiz bölüm `null` gelir ve gösterilmez; yetkisi olup
/// yüklenemeyen bölümün anahtarı [failedSections] içindedir ("Bu bölüm yüklenemedi").
@immutable
class BayiHomeData {
  const BayiHomeData({
    required this.stationId,
    required this.stationTitle,
    this.generatedAt,
    this.desk,
    this.shipments,
    this.approvals,
    this.collections,
    this.finance,
    this.leads,
    this.field,
    this.setup,
    this.sales,
    this.failedSections = const [],
    this.isFieldSales = false,
  });

  factory BayiHomeData.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final s = r.obj('sections');
    T? section<T>(String key, T Function(JsonReader r) parse) {
      final o = s.objOrNull(key);
      return o == null ? null : parse(o);
    }

    return BayiHomeData(
      stationId: r.integer('stationId'),
      stationTitle: r.str('stationTitle'),
      generatedAt: r.dateUtc('generatedAt'),
      desk: section(BayiHomeSections.desk, BayiDeskSection.fromJson),
      shipments: section(
        BayiHomeSections.shipments,
        BayiShipmentsSection.fromJson,
      ),
      approvals: section(
        BayiHomeSections.approvals,
        BayiApprovalsSection.fromJson,
      ),
      collections: section(
        BayiHomeSections.collections,
        BayiCollectionsSection.fromJson,
      ),
      finance: section(BayiHomeSections.finance, BayiFinanceSection.fromJson),
      leads: section(BayiHomeSections.leads, BayiLeadsSection.fromJson),
      field: section(BayiHomeSections.field, BayiFieldSection.fromJson),
      setup: section(BayiHomeSections.setup, BayiSetupSection.fromJson),
      sales: section(BayiHomeSections.sales, BayiSalesSection.fromJson),
      failedSections: List.unmodifiable(r.strings('failedSections')),
      isFieldSales: r.boolean('isFieldSales'),
    );
  }

  final int stationId;
  final String stationTitle;
  final DateTime? generatedAt;
  final BayiDeskSection? desk;
  final BayiShipmentsSection? shipments;
  final BayiApprovalsSection? approvals;
  final BayiCollectionsSection? collections;
  final BayiFinanceSection? finance;
  final BayiLeadsSection? leads;
  final BayiFieldSection? field;
  final BayiSetupSection? setup;
  final BayiSalesSection? sales;
  final List<String> failedSections;
  final bool isFieldSales;

  bool failed(String key) => failedSections.contains(key);

  /// Hiç bölüm yoksa (ne veri ne hata) boş ana sayfa gösterilir.
  bool get isEmpty =>
      desk == null &&
      shipments == null &&
      approvals == null &&
      collections == null &&
      finance == null &&
      leads == null &&
      field == null &&
      setup == null &&
      sales == null &&
      failedSections.isEmpty;
}

/// Teklif KPI'ları (`BayiDeskSectionDto`).
@immutable
class BayiDeskSection {
  const BayiDeskSection({
    this.awaitingQuote = 0,
    this.revisionRequested = 0,
    this.expiringSoon,
    this.awaitingCustomer = 0,
    this.expiringWindowMinutes = 60,
    this.expiring = const [],
    this.awaitingQuoteList = const [],
    this.expiryEnabled = false,
    this.financeHeld = 0,
  });

  factory BayiDeskSection.fromJson(JsonReader r) => BayiDeskSection(
    awaitingQuote: r.integer('awaitingQuote'),
    revisionRequested: r.integer('revisionRequested'),
    expiringSoon: r.intOrNull('expiringSoon'),
    awaitingCustomer: r.integer('awaitingCustomer'),
    expiringWindowMinutes: r.integer('expiringWindowMinutes', 60),
    expiring: List.unmodifiable(r.list('expiring', DashboardOrderRow.fromJson)),
    awaitingQuoteList: List.unmodifiable(
      r.list('awaitingQuoteList', DashboardOrderRow.fromJson),
    ),
    expiryEnabled: r.boolean('expiryEnabled'),
    financeHeld: r.integer('financeHeld'),
  );

  final int awaitingQuote;
  final int revisionRequested;

  /// Süre dolumu kapalıyken null.
  final int? expiringSoon;
  final int awaitingCustomer;
  final int expiringWindowMinutes;
  final List<DashboardOrderRow> expiring;
  final List<DashboardOrderRow> awaitingQuoteList;
  final bool expiryEnabled;
  final int financeHeld;

  int get openForQuote => awaitingQuote + revisionRequested;
}

/// Bugünün sevkiyatları ve itirazlar (`BayiShipmentsSectionDto`).
@immutable
class BayiShipmentsSection {
  const BayiShipmentsSection({
    this.plannedDue = 0,
    this.planned = 0,
    this.inTransit = 0,
    this.reported = 0,
    this.disputes = 0,
    this.today = const [],
    this.disputeList = const [],
    this.unassignedDriver = 0,
  });

  factory BayiShipmentsSection.fromJson(JsonReader r) => BayiShipmentsSection(
    plannedDue: r.integer('plannedDue'),
    planned: r.integer('planned'),
    inTransit: r.integer('inTransit'),
    reported: r.integer('reported'),
    disputes: r.integer('disputes'),
    today: List.unmodifiable(r.list('today', DashboardShipmentRow.fromJson)),
    disputeList: List.unmodifiable(
      r.list('disputeList', DashboardShipmentRow.fromJson),
    ),
    unassignedDriver: r.integer('unassignedDriver'),
  );

  /// Bugün ya da geçmiş tarihli planlı (yola çıkmamış).
  final int plannedDue;
  final int planned;
  final int inTransit;
  final int reported;
  final int disputes;
  final List<DashboardShipmentRow> today;
  final List<DashboardShipmentRow> disputeList;

  /// Uygulama şoförü atanmamış planlı sevkiyat.
  final int unassignedDriver;
}

/// Onaylarım rozeti.
@immutable
class BayiApprovalsSection {
  const BayiApprovalsSection({this.toMe = 0, this.overdue = 0});

  factory BayiApprovalsSection.fromJson(JsonReader r) => BayiApprovalsSection(
    toMe: r.integer('toMe'),
    overdue: r.integer('overdue'),
  );

  final int toMe;
  final int overdue;
}

/// Vadesi geçen ödeme satırı (`PaymentListItemDto`; tarihler Türkiye yerel).
@immutable
class BayiPaymentRow {
  const BayiPaymentRow({
    required this.orderId,
    required this.orderNumber,
    this.customerTitle = '',
    this.methodName,
    this.dueDate,
    this.paymentStatus = PaymentStatus.none,
    this.amount,
    this.isOverdue = false,
  });

  factory BayiPaymentRow.fromJson(JsonReader r) => BayiPaymentRow(
    orderId: r.integer('orderId'),
    orderNumber: r.str('orderNumber'),
    customerTitle: r.str('customerTitle'),
    methodName: r.nonEmpty('methodName'),
    dueDate: r.dateTr('dueDate'),
    paymentStatus: r.enumOf('paymentStatus', PaymentStatus.fromCode),
    amount: r.decOrNull('amount') ?? r.decOrNull('estimatedAmount'),
    isOverdue: r.boolean('isOverdue'),
  );

  final int orderId;
  final String orderNumber;
  final String customerTitle;
  final String? methodName;
  final DateTime? dueDate;
  final PaymentStatus paymentStatus;
  final double? amount;
  final bool isOverdue;
}

/// Portföydeki çek / senet satırı (`PaymentInstrumentDto`).
@immutable
class BayiInstrumentRow {
  const BayiInstrumentRow({
    required this.id,
    this.customerTitle = '',
    this.orderId,
    this.orderNumber,
    this.kind = InstrumentKind.unknown,
    this.serialNo,
    this.bankName,
    this.amount = 0,
    this.dueDate,
    this.status = InstrumentStatus.unknown,
  });

  factory BayiInstrumentRow.fromJson(JsonReader r) => BayiInstrumentRow(
    id: r.integer('id'),
    customerTitle: r.str('customerTitle'),
    orderId: r.intOrNull('orderId'),
    orderNumber: r.nonEmpty('orderNumber'),
    kind: r.enumOf('kind', InstrumentKind.fromCode),
    serialNo: r.nonEmpty('serialNo'),
    bankName: r.nonEmpty('bankName'),
    amount: r.dec('amount'),
    dueDate: r.dateTr('dueDate'),
    status: r.enumOf('status', InstrumentStatus.fromCode),
  );

  final int id;
  final String customerTitle;
  final int? orderId;
  final String? orderNumber;
  final InstrumentKind kind;
  final String? serialNo;
  final String? bankName;
  final double amount;
  final DateTime? dueDate;
  final InstrumentStatus status;
}

/// Tahsilat özeti (`BayiCollectionsSectionDto`).
@immutable
class BayiCollectionsSection {
  const BayiCollectionsSection({
    this.overdueCount = 0,
    this.overdueAmount = 0,
    this.overdue = const [],
    this.instrumentsDueSoonCount = 0,
    this.instrumentsDueSoonAmount = 0,
    this.instrumentsDueSoon = const [],
    this.dueSoonDays = 7,
    this.documentsAwaitingCheck = 0,
    this.bounced30d = 0,
  });

  factory BayiCollectionsSection.fromJson(JsonReader r) =>
      BayiCollectionsSection(
        overdueCount: r.integer('overdueCount'),
        overdueAmount: r.dec('overdueAmount'),
        overdue: List.unmodifiable(r.list('overdue', BayiPaymentRow.fromJson)),
        instrumentsDueSoonCount: r.integer('instrumentsDueSoonCount'),
        instrumentsDueSoonAmount: r.dec('instrumentsDueSoonAmount'),
        instrumentsDueSoon: List.unmodifiable(
          r.list('instrumentsDueSoon', BayiInstrumentRow.fromJson),
        ),
        dueSoonDays: r.integer('dueSoonDays', 7),
        documentsAwaitingCheck: r.integer('documentsAwaitingCheck'),
        bounced30d: r.integer('bounced30d'),
      );

  final int overdueCount;
  final double overdueAmount;
  final List<BayiPaymentRow> overdue;
  final int instrumentsDueSoonCount;
  final double instrumentsDueSoonAmount;
  final List<BayiInstrumentRow> instrumentsDueSoon;
  final int dueSoonDays;
  final int documentsAwaitingCheck;
  final int bounced30d;
}

/// Finans kartı kuyruğu satırı (`CustomerFinanceListItemDto`).
@immutable
class BayiFinanceRow {
  const BayiFinanceRow({
    required this.stationCustomerId,
    required this.customerId,
    required this.customerTitle,
    this.status,
    this.riskClass = RiskClass.none,
    this.nextReviewDate,
    this.hasBouncedCheque = false,
    this.hasProtestedNote = false,
    this.overdueAmount,
  });

  factory BayiFinanceRow.fromJson(JsonReader r) => BayiFinanceRow(
    stationCustomerId: r.integer('stationCustomerId'),
    customerId: r.integer('customerId'),
    customerTitle: r.str('customerTitle'),
    status: r.intOrNull('status') == null
        ? null
        : r.enumOf('status', FinanceProfileStatus.fromCode),
    riskClass: r.enumOf('riskClass', RiskClass.fromCode),
    nextReviewDate: r.dateTr('nextReviewDate'),
    hasBouncedCheque: r.boolean('hasBouncedCheque'),
    hasProtestedNote: r.boolean('hasProtestedNote'),
    overdueAmount: r.decOrNull('overdueAmount'),
  );

  final int stationCustomerId;
  final int customerId;
  final String customerTitle;
  final FinanceProfileStatus? status;
  final RiskClass riskClass;
  final DateTime? nextReviewDate;
  final bool hasBouncedCheque;
  final bool hasProtestedNote;
  final double? overdueAmount;
}

/// Finans kartı kuyruğu (`BayiFinanceSectionDto`).
@immutable
class BayiFinanceSection {
  const BayiFinanceSection({
    this.pending = 0,
    this.infoRequested = 0,
    this.reviewOverdue = 0,
    this.flagged = 0,
    this.attention = const [],
  });

  factory BayiFinanceSection.fromJson(JsonReader r) => BayiFinanceSection(
    pending: r.integer('pending'),
    infoRequested: r.integer('infoRequested'),
    reviewOverdue: r.integer('reviewOverdue'),
    flagged: r.integer('flagged'),
    attention: List.unmodifiable(r.list('attention', BayiFinanceRow.fromJson)),
  );

  final int pending;
  final int infoRequested;
  final int reviewOverdue;
  final int flagged;
  final List<BayiFinanceRow> attention;
}

/// Ön kayıt istatistikleri (`LeadStatsDto`).
@immutable
class BayiLeadStats {
  const BayiLeadStats({
    this.total = 0,
    this.submitted = 0,
    this.converted = 0,
    this.rejected = 0,
    this.draft = 0,
    this.inFinance = 0,
    this.cancelled = 0,
    this.conversionRatePercent,
  });

  factory BayiLeadStats.fromJson(JsonReader r) => BayiLeadStats(
    total: r.integer('total'),
    submitted: r.integer('submitted'),
    converted: r.integer('converted'),
    rejected: r.integer('rejected'),
    draft: r.integer('draft'),
    inFinance: r.integer('inFinance'),
    cancelled: r.integer('cancelled'),
    conversionRatePercent: r.decOrNull('conversionRatePercent'),
  );

  final int total;
  final int submitted;
  final int converted;
  final int rejected;
  final int draft;
  final int inFinance;
  final int cancelled;
  final double? conversionRatePercent;
}

/// Ön kayıt bölümü (`BayiLeadsSectionDto`).
@immutable
class BayiLeadsSection {
  const BayiLeadsSection({this.periodLabel = '', required this.stats});

  factory BayiLeadsSection.fromJson(JsonReader r) => BayiLeadsSection(
    periodLabel: r.str('periodLabel'),
    stats: BayiLeadStats.fromJson(r.obj('stats')),
  );

  final String periodLabel;
  final BayiLeadStats stats;
}

/// Saha formu kısa satırı (`BayiFieldFormRowDto`; maliyet yok).
@immutable
class BayiFieldFormRow {
  const BayiFieldFormRow({
    required this.id,
    required this.formNumber,
    this.customerTitle,
    this.status = FieldOrderFormStatus.unknown,
    this.statusLabel,
    this.totalLiters = 0,
    this.totalAmount,
    this.createdAt,
  });

  factory BayiFieldFormRow.fromJson(JsonReader r) => BayiFieldFormRow(
    id: r.integer('id'),
    formNumber: r.str('formNumber'),
    customerTitle: r.nonEmpty('customerTitle'),
    status: r.enumOf('status', FieldOrderFormStatus.fromCode),
    statusLabel: r.nonEmpty('statusLabel'),
    totalLiters: r.dec('totalLiters'),
    totalAmount: r.decOrNull('totalAmount'),
    createdAt: r.dateUtc('createdAt'),
  );

  final int id;
  final String formNumber;
  final String? customerTitle;
  final FieldOrderFormStatus status;
  final String? statusLabel;
  final double totalLiters;
  final double? totalAmount;
  final DateTime? createdAt;
}

/// Saha formu özeti (`BayiFieldSectionDto`).
@immutable
class BayiFieldSection {
  const BayiFieldSection({
    this.drafts = 0,
    this.pending = 0,
    this.rejected = 0,
    this.converted = 0,
    this.approvalsToMe = 0,
    this.portfolioCount = 0,
    this.recent = const [],
  });

  factory BayiFieldSection.fromJson(JsonReader r) => BayiFieldSection(
    drafts: r.integer('drafts'),
    pending: r.integer('pending'),
    rejected: r.integer('rejected'),
    converted: r.integer('converted'),
    approvalsToMe: r.integer('approvalsToMe'),
    portfolioCount: r.integer('portfolioCount'),
    recent: List.unmodifiable(r.list('recent', BayiFieldFormRow.fromJson)),
  );

  final int drafts;
  final int pending;
  final int rejected;
  final int converted;
  final int approvalsToMe;
  final int portfolioCount;
  final List<BayiFieldFormRow> recent;
}

/// Kurulum kalemi durumu (`SetupCheckState`).
enum SetupCheckState {
  ok(0),
  info(1),
  warning(2),
  missing(3);

  const SetupCheckState(this.code);
  final int code;

  static SetupCheckState fromCode(int? code) => switch (code) {
    1 => info,
    2 => warning,
    3 => missing,
    _ => ok,
  };
}

/// Kurulum kalemi (`BayiSetupCheckDto`): düzeltme web portalında yapılır ([portalPath]).
@immutable
class BayiSetupCheck {
  const BayiSetupCheck({
    required this.key,
    required this.title,
    this.state = SetupCheckState.ok,
    this.stateLabel,
    this.count = 0,
    this.summary = '',
    this.hint,
    this.details = const [],
    this.isOpen = false,
    this.portalPath,
    this.portalLabel,
  });

  factory BayiSetupCheck.fromJson(JsonReader r) => BayiSetupCheck(
    key: r.str('key'),
    title: r.str('title'),
    state: SetupCheckState.fromCode(r.intOrNull('state')),
    stateLabel: r.nonEmpty('stateLabel'),
    count: r.integer('count'),
    summary: r.str('summary'),
    hint: r.nonEmpty('hint'),
    details: List.unmodifiable(r.strings('details')),
    isOpen: r.boolean('isOpen'),
    portalPath: r.nonEmpty('portalPath'),
    portalLabel: r.nonEmpty('portalLabel'),
  );

  final String key;
  final String title;
  final SetupCheckState state;
  final String? stateLabel;
  final int count;
  final String summary;
  final String? hint;
  final List<String> details;
  final bool isOpen;

  /// Portal kökü göreli yol (`/StationStaff/Index?tab=roller`); kullanıcı açamıyorsa null.
  final String? portalPath;
  final String? portalLabel;
}

/// Kurulum uyarıları (`BayiSetupSectionDto`).
@immutable
class BayiSetupSection {
  const BayiSetupSection({
    this.openCount = 0,
    this.tuprasMissingToday = false,
    this.checks = const [],
  });

  factory BayiSetupSection.fromJson(JsonReader r) => BayiSetupSection(
    openCount: r.integer('openCount'),
    tuprasMissingToday: r.boolean('tuprasMissingToday'),
    checks: List.unmodifiable(r.list('checks', BayiSetupCheck.fromJson)),
  );

  final int openCount;
  final bool tuprasMissingToday;
  final List<BayiSetupCheck> checks;
}

/// Satış özeti (`BayiSalesSectionDto`).
@immutable
class BayiSalesSection {
  const BayiSalesSection({
    this.days = const [],
    this.windowDays = 7,
    this.windowOrders = 0,
    this.windowLiters = 0,
    this.windowAmount = 0,
    this.topCustomers = const [],
    this.nearLimit = const [],
    this.nearLimitTotal = 0,
  });

  factory BayiSalesSection.fromJson(JsonReader r) => BayiSalesSection(
    days: List.unmodifiable(r.list('days', DashboardDay.fromJson)),
    windowDays: r.integer('windowDays', 7),
    windowOrders: r.integer('windowOrders'),
    windowLiters: r.dec('windowLiters'),
    windowAmount: r.dec('windowAmount'),
    topCustomers: List.unmodifiable(
      r.list('topCustomers', DashboardTopCustomer.fromJson),
    ),
    nearLimit: List.unmodifiable(
      r.list('nearLimit', DashboardLimitUsage.fromJson),
    ),
    nearLimitTotal: r.integer('nearLimitTotal'),
  );

  final List<DashboardDay> days;
  final int windowDays;
  final int windowOrders;
  final double windowLiters;
  final double windowAmount;
  final List<DashboardTopCustomer> topCustomers;
  final List<DashboardLimitUsage> nearLimit;
  final int nearLimitTotal;
}
