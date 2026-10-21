/// Finans modelleri (spec §B.8; sözleşme `Application/DTOs/FinanceDtos.cs` ve `ApprovalsDtos.cs`
/// `FinanceCustomerCardDto`). Eski DTO'lar ofsetsiz tarih gönderir: gözden geçirme ve teminat
/// geçerlilik tarihleri Türkiye takvim günü, karar / rapor zamanları UTC'dir.
library;

import 'package:flutter/foundation.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';
import '../../../core/utils/turkish_text.dart';

/// Teminat türü (`CollateralKind`).
enum CollateralKind implements CodedEnum {
  letterOfGuarantee(1, 'Teminat mektubu'),
  dbs(2, 'DBS'),
  mortgage(3, 'İpotek'),
  cheque(4, 'Çek'),
  cash(5, 'Nakit teminat'),
  other(9, 'Diğer'),
  unknown(-1, 'Teminat');

  const CollateralKind(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static CollateralKind fromCode(int? code) {
    for (final v in values) {
      if (v.code == code && !v.isUnknown) return v;
    }
    return unknown;
  }
}

/// Teminat durumu (`CollateralStatus`).
enum CollateralStatus implements CodedEnum {
  active(1, 'Geçerli'),
  expired(2, 'Süresi doldu'),
  returned(3, 'İade edildi'),
  unknown(-1, 'Bilinmiyor');

  const CollateralStatus(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static CollateralStatus fromCode(int? code) {
    for (final v in values) {
      if (v.code == code && !v.isUnknown) return v;
    }
    return unknown;
  }
}

/// Finans karar kaydı (`FinanceDecision`).
enum FinanceDecisionKind implements CodedEnum {
  approved(1, 'Onaylandı'),
  conditionallyApproved(2, 'Koşullu onaylandı'),
  infoRequested(3, 'Ek bilgi istendi'),
  rejected(4, 'Reddedildi'),
  unknown(-1, 'Karar');

  const FinanceDecisionKind(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static FinanceDecisionKind fromCode(int? code) {
    for (final v in values) {
      if (v.code == code && !v.isUnknown) return v;
    }
    return unknown;
  }
}

/// `GET finance/customers` satırı (`CustomerFinanceListItemDto`).
@immutable
class FinanceListItem {
  const FinanceListItem({
    required this.stationCustomerId,
    this.profileId,
    required this.customerId,
    required this.customerTitle,
    this.taxNumber,
    this.status,
    this.isGrandfathered = false,
    this.riskClass = RiskClass.none,
    this.limitAmount,
    this.limitUsed,
    this.limitUnit,
    this.nextReviewDate,
    this.isStrategicPricing = false,
    this.hasBouncedCheque = false,
    this.hasProtestedNote = false,
    this.overdueAmount,
  });

  factory FinanceListItem.fromJson(JsonReader r) {
    final status = r.intOrNull('status');
    return FinanceListItem(
      stationCustomerId: r.integer('stationCustomerId'),
      profileId: r.intOrNull('profileId'),
      customerId: r.integer('customerId'),
      customerTitle: r.str('customerTitle'),
      taxNumber: r.nonEmpty('taxNumber'),
      status: status == null ? null : FinanceProfileStatus.fromCode(status),
      isGrandfathered: r.boolean('isGrandfathered'),
      riskClass: r.enumOf('riskClass', RiskClass.fromCode),
      limitAmount: r.decOrNull('limitAmount'),
      limitUsed: r.decOrNull('limitUsed'),
      limitUnit: r.nonEmpty('limitUnit'),
      nextReviewDate: r.dateTr('nextReviewDate'),
      isStrategicPricing: r.boolean('isStrategicPricing'),
      hasBouncedCheque: r.boolean('hasBouncedCheque'),
      hasProtestedNote: r.boolean('hasProtestedNote'),
      overdueAmount: r.decOrNull('overdueAmount'),
    );
  }

  final int stationCustomerId;
  final int? profileId;
  final int customerId;
  final String customerTitle;
  final String? taxNumber;

  /// Kartı olmayan (özellikten önce bağlanmış) caride boş.
  final FinanceProfileStatus? status;
  final bool isGrandfathered;
  final RiskClass riskClass;
  final double? limitAmount;
  final double? limitUsed;

  /// "TL" ya da "L".
  final String? limitUnit;
  final DateTime? nextReviewDate;
  final bool isStrategicPricing;
  final bool hasBouncedCheque;
  final bool hasProtestedNote;
  final double? overdueAmount;

  /// Kullanım oranı (0..1+); limit yoksa null.
  double? get usage {
    final l = limitAmount;
    if (l == null || l <= 0) return null;
    return (limitUsed ?? 0) / l;
  }

  bool reviewOverdue(DateTime today) =>
      nextReviewDate != null && nextReviewDate!.isBefore(today);
}

/// Bağlantının limit değerlendirmesi (`CommercialLimitEvaluation`).
@immutable
class LimitUsage {
  const LimitUsage({
    this.hasLimit = false,
    this.limitType,
    this.limitPeriod,
    this.limitAmount,
    this.used = 0,
    this.available,
    this.unit = '',
  });

  factory LimitUsage.fromJson(JsonReader r) => LimitUsage(
    hasLimit: r.boolean('hasLimit'),
    limitType: r.nonEmpty('limitType'),
    limitPeriod: r.nonEmpty('limitPeriod'),
    limitAmount: r.decOrNull('limitAmount'),
    used: r.dec('used'),
    available: r.decOrNull('available'),
    unit: r.str('unit'),
  );

  final bool hasLimit;
  final String? limitType;
  final String? limitPeriod;
  final double? limitAmount;
  final double used;
  final double? available;

  /// "TL" ya da "L".
  final String unit;

  bool get isLiters => const {'L', 'l'}.contains(unit.trim());

  double? get ratio {
    final l = limitAmount;
    if (!hasLimit || l == null || l <= 0) return null;
    return used / l;
  }
}

/// Teminat (`CollateralDto`).
@immutable
class Collateral {
  const Collateral({
    required this.id,
    required this.kind,
    this.bankName,
    this.amount = 0,
    this.validUntil,
    required this.status,
    this.note,
  });

  factory Collateral.fromJson(JsonReader r) => Collateral(
    id: r.integer('id'),
    kind: r.enumOf('kind', CollateralKind.fromCode),
    bankName: r.nonEmpty('bankName'),
    amount: r.dec('amount'),
    validUntil: r.dateTr('validUntil'),
    status: r.enumOf('status', CollateralStatus.fromCode),
    note: r.nonEmpty('note'),
  );

  final int id;
  final CollateralKind kind;
  final String? bankName;
  final double amount;
  final DateTime? validUntil;
  final CollateralStatus status;
  final String? note;
}

/// Cari finans kartı (`CustomerFinanceProfileDto`).
@immutable
class FinanceProfile {
  const FinanceProfile({
    required this.stationCustomerId,
    required this.customerId,
    required this.customerTitle,
    this.taxNumber,
    required this.status,
    this.isGrandfathered = false,
    this.riskClass = RiskClass.none,
    this.approvedLimitAmount,
    this.limitUsage,
    this.allowedMethodCodes = const [],
    this.maxTermDays,
    this.collateralRatioPercent = 0,
    this.suggestedCollateralRatioPercent,
    this.isStrategicPricing = false,
    this.firstNOrdersRequireFinance,
    this.openBalance,
    this.overdueAmount,
    this.hasBouncedCheque = false,
    this.hasProtestedNote = false,
    this.nextReviewDate,
    this.notes,
    this.decidedAt,
    this.collaterals = const [],
  });

  factory FinanceProfile.fromJson(JsonReader r) => FinanceProfile(
    stationCustomerId: r.integer('stationCustomerId'),
    customerId: r.integer('customerId'),
    customerTitle: r.str('customerTitle'),
    taxNumber: r.nonEmpty('taxNumber'),
    status: r.enumOf('status', FinanceProfileStatus.fromCode),
    isGrandfathered: r.boolean('isGrandfathered'),
    riskClass: r.enumOf('riskClass', RiskClass.fromCode),
    approvedLimitAmount: r.decOrNull('approvedLimitAmount'),
    limitUsage: r.objOrNull('limitUsage') == null
        ? null
        : LimitUsage.fromJson(r.obj('limitUsage')),
    allowedMethodCodes: List.unmodifiable(r.strings('allowedMethodCodes')),
    maxTermDays: r.intOrNull('maxTermDays'),
    collateralRatioPercent: r.dec('collateralRatioPercent'),
    suggestedCollateralRatioPercent: r.decOrNull(
      'suggestedCollateralRatioPercent',
    ),
    isStrategicPricing: r.boolean('isStrategicPricing'),
    firstNOrdersRequireFinance: r.intOrNull('firstNOrdersRequireFinance'),
    openBalance: r.decOrNull('openBalance'),
    overdueAmount: r.decOrNull('overdueAmount'),
    hasBouncedCheque: r.boolean('hasBouncedCheque'),
    hasProtestedNote: r.boolean('hasProtestedNote'),
    nextReviewDate: r.dateTr('nextReviewDate'),
    notes: r.nonEmpty('notes'),
    decidedAt: r.dateUtc('decidedAt'),
    collaterals: List.unmodifiable(r.list('collaterals', Collateral.fromJson)),
  );

  final int stationCustomerId;
  final int customerId;
  final String customerTitle;
  final String? taxNumber;
  final FinanceProfileStatus status;
  final bool isGrandfathered;
  final RiskClass riskClass;
  final double? approvedLimitAmount;
  final LimitUsage? limitUsage;
  final List<String> allowedMethodCodes;
  final int? maxTermDays;
  final double collateralRatioPercent;
  final double? suggestedCollateralRatioPercent;
  final bool isStrategicPricing;
  final int? firstNOrdersRequireFinance;
  final double? openBalance;
  final double? overdueAmount;
  final bool hasBouncedCheque;
  final bool hasProtestedNote;
  final DateTime? nextReviewDate;
  final String? notes;
  final DateTime? decidedAt;
  final List<Collateral> collaterals;
}

/// Finans karar / gözden geçirme kaydı (`FinanceReviewDto`).
@immutable
class FinanceReview {
  const FinanceReview({
    required this.id,
    required this.decision,
    this.conditionsJson,
    this.note,
    this.decidedByDisplay,
    this.decidedAt,
  });

  factory FinanceReview.fromJson(JsonReader r) => FinanceReview(
    id: r.integer('id'),
    decision: r.enumOf('decision', FinanceDecisionKind.fromCode),
    conditionsJson: r.nonEmpty('conditionsJson'),
    note: r.nonEmpty('note'),
    decidedByDisplay: r.nonEmpty('decidedByDisplay'),
    decidedAt: r.dateUtc('decidedAt'),
  );

  final int id;
  final FinanceDecisionKind decision;
  final String? conditionsJson;
  final String? note;
  final String? decidedByDisplay;
  final DateTime? decidedAt;
}

/// Risk raporundaki banka satırı.
@immutable
class RiskBankLine {
  const RiskBankLine({
    required this.bankName,
    this.limit,
    this.risk,
    this.overdue,
  });

  factory RiskBankLine.fromJson(JsonReader r) => RiskBankLine(
    bankName: r.str('bankName'),
    limit: r.decOrNull('limit'),
    risk: r.decOrNull('risk'),
    overdue: r.decOrNull('overdue'),
  );

  final String bankName;
  final double? limit;
  final double? risk;
  final double? overdue;
}

/// Risk raporu (`RiskReportDto`).
@immutable
class RiskReport {
  const RiskReport({
    required this.id,
    this.provider = '',
    this.success = false,
    this.score,
    this.suggestedRiskClass = RiskClass.none,
    this.totalBankLimit,
    this.totalBankRisk,
    this.overdueAmount,
    this.overdueCount,
    this.bouncedChequeCount,
    this.protestedNoteCount,
    this.lines = const [],
    this.pdfAttachmentPublicId,
    this.errorMessage,
    this.requestedAt,
  });

  factory RiskReport.fromJson(JsonReader r) => RiskReport(
    id: r.integer('id'),
    provider: r.str('provider'),
    success: r.boolean('success'),
    score: r.intOrNull('score'),
    suggestedRiskClass: r.enumOf('suggestedRiskClass', RiskClass.fromCode),
    totalBankLimit: r.decOrNull('totalBankLimit'),
    totalBankRisk: r.decOrNull('totalBankRisk'),
    overdueAmount: r.decOrNull('overdueAmount'),
    overdueCount: r.intOrNull('overdueCount'),
    bouncedChequeCount: r.intOrNull('bouncedChequeCount'),
    protestedNoteCount: r.intOrNull('protestedNoteCount'),
    lines: List.unmodifiable(r.list('lines', RiskBankLine.fromJson)),
    pdfAttachmentPublicId: r.nonEmpty('pdfAttachmentPublicId'),
    errorMessage: r.nonEmpty('errorMessage'),
    requestedAt: r.dateUtc('requestedAt'),
  );

  final int id;
  final String provider;
  final bool success;
  final int? score;
  final RiskClass suggestedRiskClass;
  final double? totalBankLimit;
  final double? totalBankRisk;
  final double? overdueAmount;
  final int? overdueCount;
  final int? bouncedChequeCount;
  final int? protestedNoteCount;
  final List<RiskBankLine> lines;
  final String? pdfAttachmentPublicId;
  final String? errorMessage;
  final DateTime? requestedAt;

  /// Deneme sağlayıcısı (örnek veri; karta yazılmaz).
  bool get isMock => TurkishText.searchKey(provider).contains('mock');
}

/// `GET finance/customers/{stationCustomerId}` (`FinanceCustomerCardDto`).
@immutable
class FinanceCard {
  const FinanceCard({
    required this.profile,
    this.reviews = const [],
    this.riskReports = const [],
  });

  factory FinanceCard.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return FinanceCard(
      profile: FinanceProfile.fromJson(r.obj('profile')),
      reviews: List.unmodifiable(r.list('reviews', FinanceReview.fromJson)),
      riskReports: List.unmodifiable(
        r.list('riskReports', RiskReport.fromJson),
      ),
    );
  }

  final FinanceProfile profile;
  final List<FinanceReview> reviews;
  final List<RiskReport> riskReports;
}

/// Ödeme yöntemi kodunun Türkçe adı (finans kartı ve koşullar).
String paymentMethodName(String code) => switch (code.trim()) {
  'NAKIT' => 'Nakit',
  'HAVALE' => 'Havale / EFT',
  'KART' => 'Kredi / banka kartı',
  'DBS' => 'DBS',
  'CEK' => 'Çek',
  'SENET' => 'Senet',
  'ACIK_HESAP' => 'Açık hesap',
  'TEMINAT' => 'Teminat mektubu',
  'UTTS' => 'Taşıt tanıma (UTTS)',
  'AVANS' => 'Ön ödemeli bakiye',
  _ => code,
};
