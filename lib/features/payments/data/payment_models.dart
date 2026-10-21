/// Tahsilat modelleri (spec §B.8; sözleşme `ApprovalsDtos.cs` `PaymentListItemMobileDto`,
/// `PaymentMobileDetailDto`, `PaymentInstrumentMobileDto`). Ödeme tarihi ve oluşturma zamanı eski
/// DTO'daki gibi ofsetsiz Türkiye yerelidir; `*Utc` alanları ofsetlidir.
library;

import 'package:flutter/foundation.dart';

import '../../../core/models/attachment.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';

/// `GET payments` satırı.
@immutable
class PaymentRow {
  const PaymentRow({
    required this.orderId,
    required this.orderNumber,
    this.stationTitle,
    required this.customerId,
    required this.customerTitle,
    this.orderStatus = OrderStatus.unknown,
    this.methodCode,
    this.methodName,
    this.termDays,
    this.dueDate,
    this.installments,
    required this.paymentStatus,
    this.financeStatus = OrderFinanceStatus.notRequired,
    this.estimatedAmount,
    this.amount,
    this.isOverdue = false,
    this.createdAt,
    this.paymentStatusLabel,
    this.financeLabel,
    this.orderStatusLabel,
    this.paymentLine = '',
    this.dueHint,
    this.overdueDays = 0,
  });

  factory PaymentRow.fromJson(JsonReader r) => PaymentRow(
    orderId: r.integer('orderId'),
    orderNumber: r.str('orderNumber'),
    stationTitle: r.nonEmpty('stationTitle'),
    customerId: r.integer('customerId'),
    customerTitle: r.str('customerTitle'),
    orderStatus: r.enumOf('orderStatus', OrderStatus.fromCode),
    methodCode: r.nonEmpty('methodCode'),
    methodName: r.nonEmpty('methodName'),
    termDays: r.intOrNull('termDays'),
    dueDate: r.dateTr('dueDate'),
    installments: r.intOrNull('installments'),
    paymentStatus: r.enumOf('paymentStatus', PaymentStatus.fromCode),
    financeStatus: r.enumOf('financeStatus', OrderFinanceStatus.fromCode),
    estimatedAmount: r.decOrNull('estimatedAmount'),
    amount: r.decOrNull('amount'),
    isOverdue: r.boolean('isOverdue'),
    createdAt: r.dateTr('createdAt'),
    paymentStatusLabel: r.nonEmpty('paymentStatusLabel'),
    financeLabel: r.nonEmpty('financeLabel'),
    orderStatusLabel: r.nonEmpty('orderStatusLabel'),
    paymentLine: r.str('paymentLine'),
    dueHint: r.nonEmpty('dueHint'),
    overdueDays: r.integer('overdueDays'),
  );

  final int orderId;
  final String orderNumber;
  final String? stationTitle;
  final int customerId;
  final String customerTitle;
  final OrderStatus orderStatus;
  final String? methodCode;
  final String? methodName;
  final int? termDays;
  final DateTime? dueDate;
  final int? installments;
  final PaymentStatus paymentStatus;
  final OrderFinanceStatus financeStatus;
  final double? estimatedAmount;

  /// Son teklif toplamı (yoksa tahmini tutar gösterilir).
  final double? amount;
  final bool isOverdue;
  final DateTime? createdAt;
  final String? paymentStatusLabel;
  final String? financeLabel;
  final String? orderStatusLabel;

  /// Sunucunun özet satırı (eski biçim "Çek · 90 gün · vade 20.07.2026"); arayüz satırı alanlardan
  /// kurar (tasarım v2 §10.1: " · " yok).
  final String paymentLine;

  /// "bugün", "3 gün kaldı", "5 gün gecikti".
  final String? dueHint;
  final int overdueDays;

  double? get displayAmount => amount ?? estimatedAmount;
  bool get isEstimate => amount == null && estimatedAmount != null;
  String get displayStatusLabel => paymentStatusLabel ?? paymentStatus.label;
}

/// Yöntem alanı satırı.
@immutable
class LabelValue {
  const LabelValue(this.label, this.value);

  factory LabelValue.fromJson(JsonReader r) =>
      LabelValue(r.str('label'), r.str('value'));

  final String label;
  final String value;
}

/// Ödeme durumu geçmişi satırı (`PaymentHistoryMobileDto`).
@immutable
class PaymentHistoryEntry {
  const PaymentHistoryEntry({
    required this.fromStatus,
    required this.toStatus,
    this.fromStatusLabel,
    this.toStatusLabel,
    this.note,
    this.attachmentPublicId,
    this.changedByDisplay,
    this.changedAt,
  });

  factory PaymentHistoryEntry.fromJson(JsonReader r) => PaymentHistoryEntry(
    fromStatus: r.enumOf('fromStatus', PaymentStatus.fromCode),
    toStatus: r.enumOf('toStatus', PaymentStatus.fromCode),
    fromStatusLabel: r.nonEmpty('fromStatusLabel'),
    toStatusLabel: r.nonEmpty('toStatusLabel'),
    note: r.nonEmpty('note'),
    attachmentPublicId: r.nonEmpty('attachmentPublicId'),
    changedByDisplay: r.nonEmpty('changedByDisplay'),
    changedAt: r.dateUtc('changedAtUtc') ?? r.dateUtc('changedAt'),
  );

  final PaymentStatus fromStatus;
  final PaymentStatus toStatus;
  final String? fromStatusLabel;
  final String? toStatusLabel;
  final String? note;
  final String? attachmentPublicId;
  final String? changedByDisplay;
  final DateTime? changedAt;

  /// Yeni durum ("Tahsil edildi"); önceki durum [fromTitle].
  String get title => toStatusLabel ?? toStatus.label;

  /// Önceki durum ("Bekliyor").
  String get fromTitle => fromStatusLabel ?? fromStatus.label;
}

/// Çek / senet / teminat mektubu (`PaymentInstrumentMobileDto`).
@immutable
class Instrument {
  const Instrument({
    required this.id,
    required this.customerId,
    required this.customerTitle,
    this.orderId,
    this.orderNumber,
    required this.kind,
    this.kindLabel,
    this.serialNo,
    this.bankName,
    this.branchName,
    this.drawerName,
    this.debtorName,
    this.guarantorName,
    this.amount = 0,
    this.dueDate,
    required this.status,
    this.statusLabel,
    this.note,
    this.allowedTransitions = const [],
    this.noteRequiredFor = const [],
    this.isOverdue = false,
    this.dueHint,
    this.createdAt,
  });

  factory Instrument.fromJson(JsonReader r) => Instrument(
    id: r.integer('id'),
    customerId: r.integer('customerId'),
    customerTitle: r.str('customerTitle'),
    orderId: r.intOrNull('orderId'),
    orderNumber: r.nonEmpty('orderNumber'),
    kind: r.enumOf('kind', InstrumentKind.fromCode),
    kindLabel: r.nonEmpty('kindLabel'),
    serialNo: r.nonEmpty('serialNo'),
    bankName: r.nonEmpty('bankName'),
    branchName: r.nonEmpty('branchName'),
    drawerName: r.nonEmpty('drawerName'),
    debtorName: r.nonEmpty('debtorName'),
    guarantorName: r.nonEmpty('guarantorName'),
    amount: r.dec('amount'),
    dueDate: r.dateTr('dueDate'),
    status: r.enumOf('status', InstrumentStatus.fromCode),
    statusLabel: r.nonEmpty('statusLabel'),
    note: r.nonEmpty('note'),
    allowedTransitions: List.unmodifiable(
      r
          .ints('allowedTransitions')
          .map(InstrumentStatus.fromCode)
          .where((s) => !s.isUnknown),
    ),
    noteRequiredFor: List.unmodifiable(
      r
          .ints('noteRequiredFor')
          .map(InstrumentStatus.fromCode)
          .where((s) => !s.isUnknown),
    ),
    isOverdue: r.boolean('isOverdue'),
    dueHint: r.nonEmpty('dueHint'),
    createdAt: r.dateUtc('createdAtUtc') ?? r.dateUtc('createdAt'),
  );

  final int id;
  final int customerId;
  final String customerTitle;
  final int? orderId;
  final String? orderNumber;
  final InstrumentKind kind;
  final String? kindLabel;
  final String? serialNo;
  final String? bankName;
  final String? branchName;
  final String? drawerName;
  final String? debtorName;
  final String? guarantorName;
  final double amount;
  final DateTime? dueDate;
  final InstrumentStatus status;
  final String? statusLabel;
  final String? note;

  /// Kullanıcının geçebileceği durumlar (yetkisi yoksa boş).
  final List<InstrumentStatus> allowedTransitions;

  /// Açıklama zorunlu geçişler (karşılıksız, iade, protesto).
  final List<InstrumentStatus> noteRequiredFor;
  final bool isOverdue;
  final String? dueHint;
  final DateTime? createdAt;

  String get displayKindLabel => kindLabel ?? kind.label;
  String get displayStatusLabel => statusLabel ?? status.label;

  /// Açık (sonuçlanmamış) belge.
  bool get isOpen =>
      status == InstrumentStatus.received ||
      status == InstrumentStatus.inPortfolio ||
      status == InstrumentStatus.deposited;

  /// Başlık: seri no ya da borçlu / banka.
  String get headline =>
      serialNo ?? debtorName ?? bankName ?? '$displayKindLabel #$id';
}

/// `GET payments/{orderId}` (`PaymentMobileDetailDto`).
@immutable
class PaymentDetail {
  const PaymentDetail({
    required this.row,
    this.paymentGroupKey,
    this.details = const {},
    this.detailLines = const [],
    this.history = const [],
    this.instrument,
    this.allowedTransitions = const [],
    this.noteRequiredFor = const [],
    required this.concurrencyToken,
    this.canEditInstrument = false,
    this.documents = const [],
    this.documentKind,
    this.documentKindLabel,
    this.documentRequired = false,
    this.notice,
  });

  factory PaymentDetail.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final docKind = r.intOrNull('documentKind');
    return PaymentDetail(
      row: PaymentRow.fromJson(r),
      paymentGroupKey: r.nonEmpty('paymentGroupKey'),
      details: {for (final e in r.map('details').entries) e.key: '${e.value}'},
      detailLines: List.unmodifiable(
        r.list('detailLines', LabelValue.fromJson),
      ),
      history: List.unmodifiable(
        r.list('history', PaymentHistoryEntry.fromJson),
      ),
      instrument: r.objOrNull('instrument') == null
          ? null
          : Instrument.fromJson(r.obj('instrument')),
      allowedTransitions: List.unmodifiable(
        r
            .ints('allowedTransitions')
            .map(PaymentStatus.fromCode)
            .where((s) => !s.isUnknown && s != PaymentStatus.none),
      ),
      noteRequiredFor: List.unmodifiable(
        r
            .ints('noteRequiredFor')
            .map(PaymentStatus.fromCode)
            .where((s) => !s.isUnknown),
      ),
      concurrencyToken: r.str('concurrencyToken'),
      canEditInstrument: r.boolean('canEditInstrument'),
      documents: List.unmodifiable(
        r.list('documents', Attachment.fromJson).where((a) => a.isActive),
      ),
      documentKind: docKind == null ? null : AttachmentKind.fromCode(docKind),
      documentKindLabel: r.nonEmpty('documentKindLabel'),
      documentRequired: r.boolean('documentRequired'),
      notice: r.nonEmpty('notice'),
    );
  }

  final PaymentRow row;
  final String? paymentGroupKey;
  final Map<String, String> details;
  final List<LabelValue> detailLines;
  final List<PaymentHistoryEntry> history;
  final Instrument? instrument;

  /// Durum sayfası yalnızca bunları gösterir.
  final List<PaymentStatus> allowedTransitions;

  /// Gerekçe (en az 3 karakter) isteyenler: karşılıksız, iade, iptal.
  final List<PaymentStatus> noteRequiredFor;

  /// Durum isteğinde aynen geri gönderilir (değiştiyse 409).
  final String concurrencyToken;
  final bool canEditInstrument;

  /// Siparişin ve çek / senet kaydının belgeleri (yeni önce).
  final List<Attachment> documents;

  /// Yöntemin belgesi ("Dekont ekle" bu türle siparişe yükler).
  final AttachmentKind? documentKind;
  final String? documentKindLabel;
  final bool documentRequired;
  final String? notice;

  int get orderId => row.orderId;

  /// "Dekont ekle" yükleme türü.
  AttachmentKind get uploadKind =>
      documentKind == null || documentKind!.isUnknown
      ? AttachmentKind.transferReceipt
      : documentKind!;

  /// Yöntemin zorunlu belgesi henüz yok mu.
  bool get missingRequiredDocument =>
      documentRequired &&
      documentKind != null &&
      !documents.any((a) => a.kind == documentKind);
}

/// Cari süzgeci seçeneği (`bayi/customers` satırının gereken alanları).
@immutable
class CustomerOption {
  const CustomerOption({
    required this.customerId,
    required this.title,
    this.city,
  });

  factory CustomerOption.fromJson(JsonReader r) => CustomerOption(
    customerId: r.integer('customerId'),
    title: r.str('title'),
    city: r.nonEmpty('city'),
  );

  final int customerId;
  final String title;
  final String? city;

  @override
  bool operator ==(Object other) =>
      other is CustomerOption && other.customerId == customerId;

  @override
  int get hashCode => customerId.hashCode;
}
