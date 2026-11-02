/// Sipariş finans incelemesi (`summary.finance`; sunucu `ApprovalFinanceReviewDto`, mobil revizyon 3).
///
/// Yalnızca sipariş finansında (tür 4) ve bayi / merkez görünümünde gelir; cari görünümünde ve eski
/// sunucuda yoktur. Ekran yapılandırılmış bloğu tercih eder; yoksa özet satırlarından (`facts`,
/// anahtarla ya da etiketle) aynı bölümleri kurar ([OrderFinanceReview.fromFacts]). Tutarlar ₺,
/// litreler L; limit alanları limitin biriminde ([OrderFinanceLimit.unit]); takvim günleri
/// `yyyy-MM-dd` (Türkiye), anlar ofsetli.
library;

import 'package:flutter/foundation.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';

/// Özet satırlarının değişmez anahtarları (sunucu `ApprovalFactKeys`): etiket metni değişse de aynı
/// kalır; eski sunucu göndermez (null).
abstract final class FactKeys {
  static const orderNumber = 'order.number';
  static const orderStation = 'order.station';
  static const orderCustomer = 'order.customer';
  static const orderProduct = 'order.product';
  static const orderQuantity = 'order.quantity';
  static const orderDeliveryDate = 'order.deliveryDate';
  static const orderDeliveryPoint = 'order.deliveryPoint';
  static const orderQuoteAmount = 'order.quoteAmount';
  static const orderEstimatedAmount = 'order.estimatedAmount';
  static const orderStatus = 'order.status';
  static const paymentLine = 'payment.line';
  static const paymentDetail = 'payment.detail';
  static const financeStatus = 'finance.status';
  static const financeReason = 'finance.reason';
  static const cardStatus = 'card.status';
  static const cardAccess = 'card.access';
  static const cardRiskClass = 'card.riskClass';
  static const cardLimitUsage = 'card.limitUsage';
  static const cardApprovedLimit = 'card.approvedLimit';
  static const cardCollateralRatio = 'card.collateralRatio';
  static const cardOverdue = 'card.overdue';
  static const cardAllowedMethods = 'card.allowedMethods';
  static const cardMaxTerm = 'card.maxTerm';
  static const cardReview = 'card.review';
  static const cardCollaterals = 'card.collaterals';
  static const cardPricing = 'card.pricing';
  static const cardRiskReport = 'card.riskReport';
}

/// Özet satırının okunan alanları ([FactKeys] anahtarı, etiket, değer, ton); `SummaryFact` uygular.
abstract interface class FactView {
  String? get key;
  String get label;
  String get value;
  String? get tone;
}

extension FactViewMatch on FactView {
  /// Satır bu anahtarda mı; anahtarsız (eski sunucu) satırda etiketle.
  bool isFact(String factKey, List<String> labels) =>
      key == factKey || (key == null && labels.contains(label));
}

/// Finans gerekçesinin kuralı (sunucu `ApprovalFinanceReasonKinds`; finans kapısının kural sırası).
enum FinanceReasonKind {
  limitOverrun('limitOverrun'),
  paymentMethod('paymentMethod'),
  amountThreshold('amountThreshold'),
  firstOrders('firstOrders'),
  highRisk('highRisk'),
  allOrders('allOrders'),
  cardStatus('cardStatus'),
  preApproved('preApproved'),
  other('other');

  const FinanceReasonKind(this.code);

  final String code;

  static FinanceReasonKind fromCode(String? code, {String? text}) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return of(text);
  }

  /// Gerekçe metninin kuralı (sunucu `ApprovalFinanceReasonKinds.Of`; eski sunucuda metinden).
  static FinanceReasonKind of(String? reason) {
    final r = reason?.trim() ?? '';
    bool starts(String prefix) => r.startsWith(prefix);
    if (starts('Limit aşımı')) return limitOverrun;
    if (starts('Vadeli yöntem') ||
        starts('Finans onaylı yöntem') ||
        starts('Vadeli satış')) {
      return paymentMethod;
    }
    if (starts('Tutar eşiği') || starts('Tutar bilinmiyor')) {
      return amountThreshold;
    }
    if (starts('İlk ') && r.contains(' sipariş')) return firstOrders;
    if (starts('Yüksek risk')) return highRisk;
    if (starts('Tüm siparişler')) return allOrders;
    if (starts('Koşullu onaylı cari') || starts('Finans kartı askıda')) {
      return cardStatus;
    }
    if (starts('Finans önceden onaylı')) return preApproved;
    return other;
  }

  /// Kural gereği (her sipariş finansa düşer): kendi başına bir risk işareti değildir.
  bool get isRoutine => this == allOrders;

  /// Ödeme satırının zaten söylediği gerekçe (vade / yöntem): listede ve plakada tekrarlanmaz.
  bool get isPayment => this == paymentMethod;
}

/// Finans gerekçesi (`ApprovalFinanceReasonDto`): metin, kural ve ton (limit aşımı danger, vadeli
/// yöntem warn, diğerleri info).
@immutable
class FinanceReason {
  const FinanceReason({required this.text, required this.kind, this.tone});

  factory FinanceReason.fromJson(JsonReader r) {
    final text = r.str('text');
    return FinanceReason(
      text: text,
      kind: FinanceReasonKind.fromCode(r.nonEmpty('kind'), text: text),
      tone: r.nonEmpty('tone') ?? toneOf(text),
    );
  }

  /// Eski sunucunun "Gerekçe" satırından.
  factory FinanceReason.fromText(String text, {String? tone}) => FinanceReason(
    text: text.trim(),
    kind: FinanceReasonKind.of(text),
    tone: tone ?? toneOf(text),
  );

  /// Sunucu `ApprovalText.ReasonTone`: limit aşımı tehlike, vadeli uyarı, diğerleri bilgi.
  static String toneOf(String text) {
    final t = text.trim();
    if (t.startsWith('Limit aşımı')) return 'danger';
    if (t.startsWith('Vadeli')) return 'warn';
    return 'info';
  }

  final String text;
  final FinanceReasonKind kind;

  /// ok / warn / danger / info / neutral.
  final String? tone;
}

/// Siparişin ödemesi (`ApprovalFinancePaymentDto`).
@immutable
class OrderFinancePayment {
  const OrderFinancePayment({
    this.methodCode,
    this.methodName = '',
    this.isDeferred = false,
    this.termDays,
    this.dueDate,
    this.installments,
    this.status = PaymentStatus.none,
    this.statusLabel,
    this.documentKind,
    this.documentLabel,
    this.documentRequired = false,
    this.documentMissing = false,
    this.line,
  });

  factory OrderFinancePayment.fromJson(JsonReader r) {
    final kind = r.intOrNull('documentKind');
    return OrderFinancePayment(
      methodCode: r.nonEmpty('methodCode'),
      methodName: r.str('methodName'),
      isDeferred: r.boolean('isDeferred'),
      termDays: r.intOrNull('termDays'),
      dueDate: r.date('dueDate'),
      installments: r.intOrNull('installments'),
      status: r.enumOf('status', PaymentStatus.fromCode),
      statusLabel: r.nonEmpty('statusLabel'),
      documentKind: kind == null ? null : AttachmentKind.fromCode(kind),
      documentLabel: r.nonEmpty('documentLabel'),
      documentRequired: r.boolean('documentRequired'),
      documentMissing: r.boolean('documentMissing'),
    );
  }

  /// Eski sunucu: "Ödeme" satırı ("Çek · 60 gün · vade 02.01.2027 · Bekliyor"); yöntem ilk parça,
  /// vade "N gün" parçası.
  factory OrderFinancePayment.fromLine(String line) {
    final parts = [
      for (final p in line.split(' · '))
        if (p.trim().isNotEmpty) p.trim(),
    ];
    int? term;
    for (final p in parts.skip(1)) {
      final m = RegExp(r'^(\d+)\s*gün$').firstMatch(p);
      if (m != null) term = int.tryParse(m[1]!);
    }
    return OrderFinancePayment(
      methodName: parts.isEmpty ? '' : parts.first,
      termDays: term,
      isDeferred: (term ?? 0) > 0,
      line: line,
    );
  }

  final String? methodCode;

  /// Kısa yöntem adı ("Çek"; yöntem yoksa "Belirtilmemiş").
  final String methodName;
  final bool isDeferred;
  final int? termDays;

  /// Ödeme tarihi (o günün Türkiye gece yarısı).
  final DateTime? dueDate;
  final int? installments;
  final PaymentStatus status;
  final String? statusLabel;

  /// Sipariş anında istenen belge (çek / senet görseli zorunlu, havale dekontu isteğe bağlı).
  final AttachmentKind? documentKind;
  final String? documentLabel;
  final bool documentRequired;

  /// Zorunlu belge eksik: "Ek bilgi iste" bu türle önerilir.
  final bool documentMissing;

  /// Eski sunucunun "Ödeme" satırı (yapılandırılmış alanlar yokken gösterilir).
  final String? line;

  String? get displayStatusLabel =>
      statusLabel ?? (status.isUnknown ? null : status.label);
}

/// Bağlantı limiti bu siparişle (`ApprovalFinanceLimitDto`). Tüm tutarlar [unit] biriminde.
@immutable
class OrderFinanceLimit {
  const OrderFinanceLimit({
    this.hasLimit = false,
    this.type,
    this.period,
    this.unit = '',
    this.limitAmount,
    this.usedByOthers = 0,
    this.thisOrder = 0,
    this.unpricedOthers = 0,
    this.available,
    this.availableAfter,
    this.usagePercentAfter,
    this.wouldExceed = false,
    this.overrunAmount = 0,
    this.invalidReason,
    this.includesThisOrder = true,
    this.text,
  });

  factory OrderFinanceLimit.fromJson(JsonReader r) => OrderFinanceLimit(
    hasLimit: r.boolean('hasLimit'),
    type: r.nonEmpty('type'),
    period: r.nonEmpty('period'),
    unit: r.str('unit'),
    limitAmount: r.decOrNull('limitAmount'),
    usedByOthers: r.dec('usedByOthers'),
    thisOrder: r.dec('thisOrder'),
    unpricedOthers: r.dec('unpricedOthers'),
    available: r.decOrNull('available'),
    availableAfter: r.decOrNull('availableAfter'),
    usagePercentAfter: r.intOrNull('usagePercentAfter'),
    wouldExceed: r.boolean('wouldExceed'),
    overrunAmount: r.dec('overrunAmount'),
    invalidReason: r.nonEmpty('invalidReason'),
  );

  /// Eski sunucunun "Limit kullanımı" satırı: "940.000 ₺ / 1.000.000 ₺ (%94)" (kullanım; Tutar
  /// limitinde teklifsiz bu sipariş girmez: [includesThisOrder] false), "%92 → %131" (önce → bu
  /// siparişle) ya da "Limit yok". Tanınmayan biçim metin olarak kalır ([text]).
  static OrderFinanceLimit? fromUsageText(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    if (t == 'Limit yok') {
      return const OrderFinanceLimit(includesThisOrder: false);
    }
    final arrow = RegExp(r'^%(\d+)\s*→\s*%(\d+)$').firstMatch(t);
    if (arrow != null) {
      return OrderFinanceLimit(
        hasLimit: true,
        usagePercentAfter: int.tryParse(arrow[2]!),
        wouldExceed: (int.tryParse(arrow[2]!) ?? 0) > 100,
        text: t,
      );
    }
    final m = RegExp(
      r'^([\d.,]+)\s*(₺|TL|L)\s*/\s*([\d.,]+)\s*(₺|TL|L)(?:\s*\(%(\d+)\))?',
    ).firstMatch(t);
    double? number(String s) =>
        double.tryParse(s.replaceAll('.', '').replaceAll(',', '.'));
    if (m == null) {
      return OrderFinanceLimit(
        hasLimit: true,
        includesThisOrder: false,
        text: t,
      );
    }
    final used = number(m[1]!);
    final limit = number(m[3]!);
    if (used == null || limit == null) {
      return OrderFinanceLimit(
        hasLimit: true,
        includesThisOrder: false,
        text: t,
      );
    }
    final unit = m[4] == 'L' ? 'L' : 'TL';
    final percent =
        int.tryParse(m[5] ?? '') ??
        (limit <= 0 ? null : (used / limit * 100).round());
    final available = limit - used < 0 ? 0.0 : limit - used;
    return OrderFinanceLimit(
      hasLimit: true,
      unit: unit,
      type: unit == 'L' ? 'Litre' : 'Tutar',
      limitAmount: limit,
      usedByOthers: used,
      available: available,
      usagePercentAfter: percent,
      includesThisOrder: false,
    );
  }

  final bool hasLimit;

  /// "Tutar" | "Litre".
  final String? type;

  /// "Aylık" | "Haftalık" | "Günlük" (limitsizde "Limitsiz").
  final String? period;

  /// "TL" | "L".
  final String unit;
  final double? limitAmount;

  /// Dönemde diğer siparişlerin kullandığı (bu sipariş hariç).
  final double usedByOthers;

  /// Bu siparişin limitten düştüğü (Tutar limitinde teklif, yoksa tahmini tutar).
  final double thisOrder;

  /// Teklifi henüz verilmemiş diğer açık siparişlerin tahmini tutarı (yalnızca Tutar limitinde).
  final double unpricedOthers;

  /// Bu siparişten önce / sonra kalan (en az 0).
  final double? available;
  final double? availableAfter;

  /// Bu siparişle kullanım yüzdesi (0–999).
  final int? usagePercentAfter;
  final bool wouldExceed;
  final double overrunAmount;
  final String? invalidReason;

  /// Kullanım bu siparişi içeriyor mu (yapılandırılmış blok: evet; eski sunucunun satırı: hayır).
  final bool includesThisOrder;

  /// Eski sunucunun satırı (tutarlar okunamadıysa gösterilir).
  final String? text;

  bool get isLiters => unit == 'L' || type == 'Litre';

  /// Ölçerin değeri (0–9,99; 1 = limit dolu).
  double? get ratio {
    final p = usagePercentAfter;
    if (p != null) return p / 100;
    final limit = limitAmount;
    if (limit == null || limit <= 0) return null;
    return (usedByOthers + (includesThisOrder ? thisOrder : 0)) / limit;
  }
}

/// Carinin bu bayideki finans kartı (`ApprovalFinanceProfileDto`).
@immutable
class OrderFinanceCard {
  const OrderFinanceCard({
    this.status = FinanceProfileStatus.unknown,
    this.statusLabel,
    this.hasCard = false,
    this.isGrandfathered = false,
    this.canOrder = true,
    this.blockReason,
    this.riskClass = RiskClass.none,
    this.riskLabel,
    this.approvedLimitAmount,
    this.openBalance,
    this.overdueAmount,
    this.collateralRatioPercent = 0,
    this.suggestedCollateralRatioPercent,
    this.activeCollateralCount = 0,
    this.activeCollateralAmount = 0,
    this.maxTermDays,
    this.allowedMethodCodes = const [],
    this.nextReviewDate,
    this.reviewOverdue = false,
    this.hasBouncedCheque = false,
    this.hasProtestedNote = false,
    this.isStrategicPricing = false,
  });

  factory OrderFinanceCard.fromJson(JsonReader r) => OrderFinanceCard(
    status: r.enumOf('status', FinanceProfileStatus.fromCode),
    statusLabel: r.nonEmpty('statusLabel'),
    hasCard: r.boolean('hasCard'),
    isGrandfathered: r.boolean('isGrandfathered'),
    canOrder: r.boolean('canOrder', true),
    blockReason: r.nonEmpty('blockReason'),
    riskClass: r.enumOf('riskClass', RiskClass.fromCode),
    riskLabel: r.nonEmpty('riskLabel'),
    approvedLimitAmount: r.decOrNull('approvedLimitAmount'),
    openBalance: r.decOrNull('openBalance'),
    overdueAmount: r.decOrNull('overdueAmount'),
    collateralRatioPercent: r.dec('collateralRatioPercent'),
    suggestedCollateralRatioPercent: r.decOrNull(
      'suggestedCollateralRatioPercent',
    ),
    activeCollateralCount: r.integer('activeCollateralCount'),
    activeCollateralAmount: r.dec('activeCollateralAmount'),
    maxTermDays: r.intOrNull('maxTermDays'),
    allowedMethodCodes: List.unmodifiable(r.strings('allowedMethodCodes')),
    nextReviewDate: r.date('nextReviewDate'),
    reviewOverdue: r.boolean('reviewOverdue'),
    hasBouncedCheque: r.boolean('hasBouncedCheque'),
    hasProtestedNote: r.boolean('hasProtestedNote'),
    isStrategicPricing: r.boolean('isStrategicPricing'),
  );

  final FinanceProfileStatus status;
  final String? statusLabel;
  final bool hasCard;
  final bool isGrandfathered;

  /// Cari bu bayiden sipariş verebilir; veremiyorsa nedeni.
  final bool canOrder;
  final String? blockReason;
  final RiskClass riskClass;
  final String? riskLabel;
  final double? approvedLimitAmount;
  final double? openBalance;

  /// Kartta elle girilen gecikmiş tutar (Tahsilat'tan hesaplanan gecikme [OrderFinanceHistory]'de).
  final double? overdueAmount;
  final double collateralRatioPercent;
  final double? suggestedCollateralRatioPercent;
  final int activeCollateralCount;
  final double activeCollateralAmount;

  /// En uzun vade (null = sınır yok).
  final int? maxTermDays;

  /// İzinli yöntem kodları (boş = bayide açık tümü).
  final List<String> allowedMethodCodes;
  final DateTime? nextReviewDate;
  final bool reviewOverdue;
  final bool hasBouncedCheque;
  final bool hasProtestedNote;
  final bool isStrategicPricing;

  String get displayStatusLabel => statusLabel ?? status.label;

  /// Kısa risk ("C"; bilinmiyorsa null).
  String? get riskShort => switch (riskClass) {
    RiskClass.a => 'A',
    RiskClass.b => 'B',
    RiskClass.c => 'C',
    RiskClass.d => 'D',
    _ => null,
  };
}

/// Son risk raporu (`ApprovalFinanceRiskReportDto`).
@immutable
class OrderFinanceRiskReport {
  const OrderFinanceRiskReport({
    this.id = 0,
    this.success = true,
    this.score,
    this.riskClass = RiskClass.none,
    this.bouncedChequeCount,
    this.protestedNoteCount,
    this.overdueAmount,
    this.overdueCount,
    this.requestedAt,
    this.providerLabel = '',
    this.isMock = false,
    this.errorMessage,
  });

  factory OrderFinanceRiskReport.fromJson(JsonReader r) =>
      OrderFinanceRiskReport(
        id: r.integer('id'),
        success: r.boolean('success', true),
        score: r.intOrNull('score'),
        riskClass: r.enumOf('riskClass', RiskClass.fromCode),
        bouncedChequeCount: r.intOrNull('bouncedChequeCount'),
        protestedNoteCount: r.intOrNull('protestedNoteCount'),
        overdueAmount: r.decOrNull('overdueAmount'),
        overdueCount: r.intOrNull('overdueCount'),
        requestedAt: r.dateUtc('requestedAt'),
        providerLabel: r.str('providerLabel'),
        isMock: r.boolean('isMock'),
        errorMessage: r.nonEmpty('errorMessage'),
      );

  final int id;
  final bool success;
  final int? score;
  final RiskClass riskClass;
  final int? bouncedChequeCount;
  final int? protestedNoteCount;

  /// Bankaların bildirdiği gecikmiş tutar ve sayı.
  final double? overdueAmount;
  final int? overdueCount;
  final DateTime? requestedAt;
  final String providerLabel;

  /// Deneme sağlayıcısı: skor örnek veridir.
  final bool isMock;
  final String? errorMessage;
}

/// Carinin bu bayideki sipariş ve tahsilat geçmişi (`ApprovalFinanceHistoryDto`; bu sipariş hariç).
@immutable
class OrderFinanceHistory {
  const OrderFinanceHistory({
    this.orderCount = 0,
    this.completedCount = 0,
    this.lastOrderAt,
    this.lastOrderNumber,
    this.openFinanceCount = 0,
    this.financeRejectedCount = 0,
    this.overdueCount = 0,
    this.overdueAmount = 0,
    this.maxOverdueDays,
    this.bouncedCount = 0,
  });

  factory OrderFinanceHistory.fromJson(JsonReader r) => OrderFinanceHistory(
    orderCount: r.integer('orderCount'),
    completedCount: r.integer('completedCount'),
    lastOrderAt: r.dateTr('lastOrderAt'),
    lastOrderNumber: r.nonEmpty('lastOrderNumber'),
    openFinanceCount: r.integer('openFinanceCount'),
    financeRejectedCount: r.integer('financeRejectedCount'),
    overdueCount: r.integer('overdueCount'),
    overdueAmount: r.dec('overdueAmount'),
    maxOverdueDays: r.intOrNull('maxOverdueDays'),
    bouncedCount: r.integer('bouncedCount'),
  );

  /// Diğer siparişler (reddedilen ve süresi dolanlar hariç) ve tamamlananlar.
  final int orderCount;
  final int completedCount;
  final DateTime? lastOrderAt;
  final String? lastOrderNumber;

  /// Finans kararı bekleyen diğer siparişler.
  final int openFinanceCount;
  final int financeRejectedCount;

  /// Geciken tahsilat (Tahsilat'ın "Geciken" kuralı): sipariş sayısı, tutar, en uzun gecikme.
  final int overdueCount;
  final double overdueAmount;
  final int? maxOverdueDays;

  /// Ödemesi karşılıksız çıkan siparişler.
  final int bouncedCount;

  bool get isFirstOrder => orderCount == 0;
}

/// Aynı ödeme grubundaki diğer sipariş (`ApprovalFinanceGroupOrderDto`; her birinin kendi onayı var).
@immutable
class OrderFinanceGroupLine {
  const OrderFinanceGroupLine({
    required this.orderId,
    this.orderNumber = '',
    this.productName,
    this.quantityLiters = 0,
    this.amount,
    this.financeStatus = OrderFinanceStatus.unknown,
    this.financeLabel,
    this.approvalRequestId,
  });

  factory OrderFinanceGroupLine.fromJson(JsonReader r) => OrderFinanceGroupLine(
    orderId: r.integer('orderId'),
    orderNumber: r.str('orderNumber'),
    productName: r.nonEmpty('productName'),
    quantityLiters: r.dec('quantityLiters'),
    amount: r.decOrNull('amount'),
    financeStatus: r.enumOf('financeStatus', OrderFinanceStatus.fromCode),
    financeLabel: r.nonEmpty('financeLabel'),
    approvalRequestId: r.intOrNull('approvalRequestId'),
  );

  final int orderId;
  final String orderNumber;
  final String? productName;
  final double quantityLiters;
  final double? amount;
  final OrderFinanceStatus financeStatus;
  final String? financeLabel;
  final int? approvalRequestId;

  String get displayFinanceLabel => financeLabel ?? financeStatus.label;
}

/// `summary.finance`: sipariş finans onayının yapılandırılmış inceleme verisi.
@immutable
class OrderFinanceReview {
  const OrderFinanceReview({
    this.financeStatus = OrderFinanceStatus.unknown,
    this.financeStatusLabel,
    this.amountIsEstimate = false,
    this.estimatedAmount,
    this.quotedAmount,
    this.reasons = const [],
    this.payment = const OrderFinancePayment(),
    this.limit,
    this.card,
    this.riskReport,
    this.history,
    this.paymentGroup = const [],
    this.structured = true,
    bool? quoted,
  }) : _quoted = quoted;

  factory OrderFinanceReview.fromJson(JsonReader r) {
    final limit = r.objOrNull('limit');
    final profile = r.objOrNull('profile');
    final risk = r.objOrNull('riskReport');
    final history = r.objOrNull('history');
    final payment = r.objOrNull('payment');
    return OrderFinanceReview(
      financeStatus: r.enumOf('financeStatus', OrderFinanceStatus.fromCode),
      financeStatusLabel: r.nonEmpty('financeStatusLabel'),
      amountIsEstimate: r.boolean('amountIsEstimate'),
      estimatedAmount: r.decOrNull('estimatedAmount'),
      quotedAmount: r.decOrNull('quotedAmount'),
      reasons: List.unmodifiable(
        r
            .list('reasons', FinanceReason.fromJson)
            .where((x) => x.text.trim().isNotEmpty),
      ),
      payment: payment == null
          ? const OrderFinancePayment()
          : OrderFinancePayment.fromJson(payment),
      limit: limit == null ? null : OrderFinanceLimit.fromJson(limit),
      card: profile == null ? null : OrderFinanceCard.fromJson(profile),
      riskReport: risk == null ? null : OrderFinanceRiskReport.fromJson(risk),
      history: history == null ? null : OrderFinanceHistory.fromJson(history),
      paymentGroup: List.unmodifiable(
        r.list('paymentGroup', OrderFinanceGroupLine.fromJson),
      ),
    );
  }

  /// Eski sunucu (`summary.finance` yok): özet satırlarından kurulur — "Gerekçe" satırları, "Ödeme",
  /// "Limit kullanımı", "Tahmini tutar" / "Teklif tutarı" (anahtarla, anahtar yoksa etiketle). Kart,
  /// rapor ve geçmiş yapılandırılmış olarak yoktur: ekran kart satırlarını olduğu gibi gösterir.
  factory OrderFinanceReview.fromFacts(Iterable<FactView> facts) {
    final reasons = <FinanceReason>[];
    String? payment;
    String? usage;
    var quoted = false;
    var estimate = false;
    for (final f in facts) {
      if (f.isFact(FactKeys.financeReason, const [
        'Gerekçe',
        'Finans gerekçesi',
      ])) {
        if (f.value.trim().isNotEmpty) {
          reasons.add(FinanceReason.fromText(f.value, tone: f.tone));
        }
      } else if (f.isFact(FactKeys.paymentLine, const ['Ödeme'])) {
        payment ??= f.value;
      } else if (f.isFact(FactKeys.cardLimitUsage, const ['Limit kullanımı'])) {
        usage ??= f.value;
      } else if (f.isFact(FactKeys.orderQuoteAmount, const ['Teklif tutarı'])) {
        quoted = true;
      } else if (f.isFact(FactKeys.orderEstimatedAmount, const [
        'Tahmini tutar',
      ])) {
        estimate = true;
      }
    }
    return OrderFinanceReview(
      amountIsEstimate: !quoted && estimate,
      reasons: List.unmodifiable(reasons),
      payment: payment == null
          ? const OrderFinancePayment()
          : OrderFinancePayment.fromLine(payment),
      limit: usage == null ? null : OrderFinanceLimit.fromUsageText(usage),
      structured: false,
      quoted: quoted,
    );
  }

  final OrderFinanceStatus financeStatus;
  final String? financeStatusLabel;

  /// Özet tutarı teklif öncesi tahmin mi ("Tahmini tutar").
  final bool amountIsEstimate;
  final double? estimatedAmount;
  final double? quotedAmount;
  final List<FinanceReason> reasons;
  final OrderFinancePayment payment;
  final OrderFinanceLimit? limit;

  /// Finans kartı (`profile`); kullanıcı kartı göremiyorsa null.
  final OrderFinanceCard? card;
  final OrderFinanceRiskReport? riskReport;
  final OrderFinanceHistory? history;
  final List<OrderFinanceGroupLine> paymentGroup;

  /// Sunucunun yapılandırılmış bloğundan mı (false: eski sunucu, özet satırlarından).
  final bool structured;

  final bool? _quoted;

  /// Tutar teklif tutarı (teklif verildi).
  bool get isQuoted => _quoted ?? quotedAmount != null;

  /// Yalnızca genel kural ("Tüm siparişler finans onayından geçer"): başka gerekçe yok.
  bool get isRoutine =>
      reasons.isNotEmpty && reasons.every((r) => r.kind.isRoutine);

  /// Ödeme satırının söylemediği istisnalar (limit, risk, kart, tutar, ilk N …).
  List<FinanceReason> get exceptions => [
    for (final r in reasons)
      if (!r.kind.isRoutine && !r.kind.isPayment) r,
  ];

  FinanceReason? get limitOverrun {
    for (final r in reasons) {
      if (r.kind == FinanceReasonKind.limitOverrun) return r;
    }
    return null;
  }

  /// Siparişin vadesi kartın en uzun vadesini aşıyor.
  bool get termExceedsCard {
    final max = card?.maxTermDays;
    final term = payment.termDays;
    return max != null && term != null && term > max;
  }

  /// Yöntem kartta izinli değil (kart yöntem sınırlıyorsa).
  bool get methodNotAllowed {
    final codes = card?.allowedMethodCodes ?? const <String>[];
    final code = payment.methodCode;
    return codes.isNotEmpty && code != null && !codes.contains(code);
  }
}
