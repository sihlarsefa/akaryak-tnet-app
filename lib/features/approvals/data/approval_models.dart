/// Onaylarım modelleri (spec §B.8; sözleşme `Application/DTOs/Mobile/ApprovalsDtos.cs` ve
/// `Application/DTOs/ApprovalDtos.cs`). JSON anahtarları C# camelCase adlarıyla aynıdır.
///
/// Tarihler: liste satırı ve ayrıntının üst düzey tarihleri UTC'dir (yeni DTO `+00:00`, eski satır
/// ofsetsiz UTC); adım, olay ve ek tarihleri ofsetsiz UTC'dir. Hepsi [JsonReader.dateUtc] ile okunur.
library;

import 'package:flutter/foundation.dart';

import '../../../core/models/attachment.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';

/// Onaylarım sekmeleri (`scope`).
enum ApprovalScope {
  toMe(0, 'Bende', 'Bende'),
  mine(1, 'Taleplerim', 'Taleplerim'),
  decidedByMe(2, 'Kararlarım', 'Karar verdiklerim'),
  all(3, 'Tümü', 'Tümü');

  const ApprovalScope(this.code, this.shortLabel, this.label);

  final int code;

  /// Sekme etiketi (≤ 10 karakter, spec C.7).
  final String shortLabel;

  /// Tam ad (başlık, ekran okuyucu).
  final String label;
}

/// Onay adımı durumu (`ApprovalStepStatus`).
enum ApprovalStepStatus implements CodedEnum {
  waiting(0, 'Sırada'),
  pending(1, 'Karar bekliyor'),
  approved(2, 'Onaylandı'),
  rejected(3, 'Reddedildi'),
  skipped(4, 'Atlandı'),
  escalated(5, 'Üst kademeye yükseltildi'),
  cancelled(6, 'İptal edildi'),
  unknown(-1, 'Bilinmiyor');

  const ApprovalStepStatus(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static ApprovalStepStatus fromCode(int? code) {
    for (final v in values) {
      if (v.code == code && !v.isUnknown) return v;
    }
    return unknown;
  }
}

/// Onay olayı türü (`ApprovalEventType`).
enum ApprovalEventType implements CodedEnum {
  created(1, 'Oluşturuldu'),
  viewed(2, 'Görüntülendi'),
  attachmentViewed(3, 'Belge açıldı'),
  preApproved(4, 'Ön onay verildi'),
  approved(5, 'Onaylandı'),
  conditionallyApproved(6, 'Koşullu onaylandı'),
  rejected(7, 'Reddedildi'),
  infoRequested(8, 'Ek bilgi istendi'),
  infoProvided(9, 'Ek bilgi verildi'),
  reminded(10, 'Hatırlatma gönderildi'),
  escalated(11, 'Üst kademeye yükseltildi'),
  delegated(12, 'Vekâlet verildi'),
  cancelled(13, 'İptal edildi'),
  reopened(14, 'Yeniden açıldı'),
  levelsUpdated(15, 'Kademeler güncellendi'),
  unknown(-1, 'Olay');

  const ApprovalEventType(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static ApprovalEventType fromCode(int? code) {
    for (final v in values) {
      if (v.code == code && !v.isUnknown) return v;
    }
    return unknown;
  }

  /// Bir kararın günlükte bıraktığı olay (uzlaştırma: "kararım kaydedildi mi").
  static ApprovalEventType ofDecision(ApprovalDecision d) => switch (d) {
    ApprovalDecision.approve => approved,
    ApprovalDecision.conditionalApprove => conditionallyApproved,
    ApprovalDecision.requestInfo => infoRequested,
    ApprovalDecision.reject => rejected,
    ApprovalDecision.unknown => unknown,
  };
}

/// `GET approvals` satırı (`ApprovalInboxRowDto`). Cari tarafında özet, son tarih ve SLA boş gelir.
@immutable
class ApprovalRow {
  const ApprovalRow({
    required this.id,
    required this.type,
    this.typeLabel,
    required this.status,
    this.statusLabel,
    this.isMirror = false,
    this.stationId,
    this.stationTitle,
    this.customerId,
    this.customerTitle,
    this.subjectType = '',
    this.subjectId = 0,
    this.subjectNumber,
    this.title = '',
    this.summary,
    this.amount,
    this.liters,
    this.requestedByUserId,
    this.requestedByName,
    this.createdAt,
    this.dueAt,
    this.slaState = ApprovalSlaState.none,
    this.currentLevelNo = 1,
    this.levelCount = 1,
    this.canDecide = false,
  });

  factory ApprovalRow.fromJson(JsonReader r) => ApprovalRow(
    id: r.integer('id'),
    type: r.enumOf('type', ApprovalType.fromCode),
    typeLabel: r.nonEmpty('typeLabel'),
    status: r.enumOf('status', ApprovalStatus.fromCode),
    statusLabel: r.nonEmpty('statusLabel'),
    isMirror: r.boolean('isMirror'),
    stationId: r.intOrNull('stationId'),
    stationTitle: r.nonEmpty('stationTitle'),
    customerId: r.intOrNull('customerId'),
    customerTitle: r.nonEmpty('customerTitle'),
    subjectType: r.str('subjectType'),
    subjectId: r.integer('subjectId'),
    subjectNumber: r.nonEmpty('subjectNumber'),
    title: r.str('title'),
    // Satırda `summary` düz metindir (ayrıntıda yapılandırılmış özet, bkz. ApprovalDetail).
    summary: r['summary'] is String ? r.nonEmpty('summary') : null,
    amount: r.decOrNull('amount'),
    liters: r.decOrNull('liters'),
    requestedByUserId: r.nonEmpty('requestedByUserId'),
    requestedByName: r.nonEmpty('requestedByName'),
    createdAt: r.dateUtc('createdAt'),
    dueAt: r.dateUtc('dueAt'),
    slaState: r.enumOf('slaState', ApprovalSlaState.fromCode),
    currentLevelNo: r.integer('currentLevelNo', 1),
    levelCount: r.integer('levelCount', 1),
    canDecide: r.boolean('canDecide'),
  );

  final int id;
  final ApprovalType type;
  final String? typeLabel;
  final ApprovalStatus status;
  final String? statusLabel;
  final bool isMirror;
  final int? stationId;
  final String? stationTitle;
  final int? customerId;
  final String? customerTitle;
  final String subjectType;
  final int subjectId;
  final String? subjectNumber;
  final String title;

  /// Satırın düz metin özeti (cari tarafında boş).
  final String? summary;
  final double? amount;
  final double? liters;
  final String? requestedByUserId;
  final String? requestedByName;
  final DateTime? createdAt;
  final DateTime? dueAt;
  final ApprovalSlaState slaState;
  final int currentLevelNo;
  final int levelCount;
  final bool canDecide;

  String get displayTypeLabel => typeLabel ?? type.shortLabel;
  String get displayStatusLabel => statusLabel ?? status.label;

  /// Çok kademeli talepte "1/2" göstergesi.
  bool get hasLevels => levelCount > 1;
}

/// Onay adımı (`ApprovalStepDto`). "X adına Y": [decidedByName] = Y, [onBehalfOfName] = X.
@immutable
class ApprovalStep {
  const ApprovalStep({
    required this.id,
    required this.levelNo,
    required this.name,
    this.capabilityCode = '',
    this.minAmount,
    required this.status,
    this.statusLabel,
    this.dueAt,
    this.remindedAt,
    this.escalatedAt,
    this.decidedByUserId,
    this.decidedByName,
    this.onBehalfOfUserId,
    this.onBehalfOfName,
    this.decidedAt,
    this.note,
  });

  factory ApprovalStep.fromJson(JsonReader r) => ApprovalStep(
    id: r.integer('id'),
    levelNo: r.integer('levelNo', 1),
    name: r.str('name'),
    capabilityCode: r.str('capabilityCode'),
    minAmount: r.decOrNull('minAmount'),
    status: r.enumOf('status', ApprovalStepStatus.fromCode),
    statusLabel: r.nonEmpty('statusLabel'),
    dueAt: r.dateUtc('dueAt'),
    remindedAt: r.dateUtc('remindedAt'),
    escalatedAt: r.dateUtc('escalatedAt'),
    decidedByUserId: r.nonEmpty('decidedByUserId'),
    decidedByName: r.nonEmpty('decidedByName'),
    onBehalfOfUserId: r.nonEmpty('onBehalfOfUserId'),
    onBehalfOfName: r.nonEmpty('onBehalfOfName'),
    decidedAt: r.dateUtc('decidedAt'),
    note: r.nonEmpty('note'),
  );

  final int id;
  final int levelNo;
  final String name;
  final String capabilityCode;
  final double? minAmount;
  final ApprovalStepStatus status;
  final String? statusLabel;
  final DateTime? dueAt;
  final DateTime? remindedAt;
  final DateTime? escalatedAt;
  final String? decidedByUserId;
  final String? decidedByName;
  final String? onBehalfOfUserId;
  final String? onBehalfOfName;
  final DateTime? decidedAt;
  final String? note;

  String get displayStatusLabel => statusLabel ?? status.label;

  /// "Ayşe Kaya adına Can Öztürk" ya da karar verenin adı.
  String? get deciderText {
    final by = decidedByName;
    if (by == null) return null;
    final behalf = onBehalfOfName;
    return behalf == null ? by : '$behalf adına $by';
  }
}

/// Olay günlüğü satırı (`ApprovalEventDto`).
@immutable
class ApprovalEvent {
  const ApprovalEvent({
    required this.id,
    required this.eventType,
    this.label,
    this.stepId,
    this.userId,
    this.userName,
    this.onBehalfOfUserId,
    this.onBehalfOfName,
    this.attachmentPublicId,
    this.attachmentFileName,
    this.note,
    this.occurredAt,
  });

  factory ApprovalEvent.fromJson(JsonReader r) => ApprovalEvent(
    id: r.integer('id'),
    eventType: r.enumOf('eventType', ApprovalEventType.fromCode),
    label: r.nonEmpty('label'),
    stepId: r.intOrNull('stepId'),
    userId: r.nonEmpty('userId'),
    userName: r.nonEmpty('userName'),
    onBehalfOfUserId: r.nonEmpty('onBehalfOfUserId'),
    onBehalfOfName: r.nonEmpty('onBehalfOfName'),
    attachmentPublicId: r.nonEmpty('attachmentPublicId'),
    attachmentFileName: r.nonEmpty('attachmentFileName'),
    note: r.nonEmpty('note'),
    occurredAt: r.dateUtc('occurredAt'),
  );

  final int id;
  final ApprovalEventType eventType;
  final String? label;
  final int? stepId;
  final String? userId;
  final String? userName;
  final String? onBehalfOfUserId;
  final String? onBehalfOfName;
  final String? attachmentPublicId;
  final String? attachmentFileName;
  final String? note;
  final DateTime? occurredAt;

  String get displayLabel => label ?? eventType.label;

  /// "Can Öztürk (Ayşe Kaya adına)".
  String? get actorText {
    final by = userName;
    if (by == null) return null;
    final behalf = onBehalfOfName;
    return behalf == null ? by : '$by ($behalf adına)';
  }
}

/// Özet satırı (etiket – değer; değer sunucuda Türkçe biçimlenmiştir).
@immutable
class SummaryFact {
  const SummaryFact({required this.label, required this.value, this.tone});

  factory SummaryFact.fromJson(JsonReader r) => SummaryFact(
    label: r.str('label'),
    value: r.str('value'),
    tone: r.nonEmpty('tone'),
  );

  final String label;
  final String value;

  /// ok / warn / danger / info / neutral / brand.
  final String? tone;
}

/// Özet kalemi.
@immutable
class SummaryLine {
  const SummaryLine({required this.title, this.subtitle, this.value});

  factory SummaryLine.fromJson(JsonReader r) => SummaryLine(
    title: r.str('title'),
    subtitle: r.nonEmpty('subtitle'),
    value: r.nonEmpty('value'),
  );

  final String title;
  final String? subtitle;
  final String? value;
}

/// Renk bandı (barem bandı, risk sınıfı).
@immutable
class SummaryBand {
  const SummaryBand({required this.key, required this.label, this.tone});

  factory SummaryBand.fromJson(JsonReader r) => SummaryBand(
    key: r.str('key'),
    label: r.str('label'),
    tone: r.nonEmpty('tone'),
  );

  final String key;
  final String label;
  final String? tone;
}

/// İlgili kayıtlar (erişim varsa ilgili ekrana gidilir).
@immutable
class SummaryLinks {
  const SummaryLinks({
    this.orderId,
    this.fieldOrderId,
    this.leadId,
    this.customerId,
    this.stationCustomerId,
    this.limitRequestId,
    this.companyRequestId,
  });

  factory SummaryLinks.fromJson(JsonReader r) => SummaryLinks(
    orderId: r.intOrNull('orderId'),
    fieldOrderId: r.intOrNull('fieldOrderId'),
    leadId: r.intOrNull('leadId'),
    customerId: r.intOrNull('customerId'),
    stationCustomerId: r.intOrNull('stationCustomerId'),
    limitRequestId: r.intOrNull('limitRequestId'),
    companyRequestId: r.intOrNull('companyRequestId'),
  );

  final int? orderId;
  final int? fieldOrderId;
  final int? leadId;
  final int? customerId;
  final int? stationCustomerId;
  final int? limitRequestId;
  final int? companyRequestId;

  bool get isEmpty =>
      orderId == null &&
      fieldOrderId == null &&
      leadId == null &&
      customerId == null &&
      stationCustomerId == null &&
      companyRequestId == null;
}

/// Türe özel sunucu özeti (`ApprovalSummaryDto`): uygulama türe özel ekran yazmadan bunu çizer.
@immutable
class ApprovalSummary {
  const ApprovalSummary({
    this.headline = '',
    this.subline,
    this.amount,
    this.liters,
    this.facts = const [],
    this.lines = const [],
    this.warnings = const [],
    this.band,
    this.links = const SummaryLinks(),
  });

  factory ApprovalSummary.fromJson(JsonReader r) => ApprovalSummary(
    headline: r.str('headline'),
    subline: r.nonEmpty('subline'),
    amount: r.decOrNull('amount'),
    liters: r.decOrNull('liters'),
    facts: List.unmodifiable(r.list('facts', SummaryFact.fromJson)),
    lines: List.unmodifiable(r.list('lines', SummaryLine.fromJson)),
    warnings: List.unmodifiable(
      r.strings('warnings').where((w) => w.trim().isNotEmpty),
    ),
    band: r.objOrNull('band') == null
        ? null
        : SummaryBand.fromJson(r.obj('band')),
    links: SummaryLinks.fromJson(r.obj('links')),
  );

  final String headline;
  final String? subline;
  final double? amount;
  final double? liters;
  final List<SummaryFact> facts;
  final List<SummaryLine> lines;
  final List<String> warnings;
  final SummaryBand? band;
  final SummaryLinks links;
}

/// Bekleyen ek bilgi isteği (`ApprovalInfoRequestDto`).
@immutable
class ApprovalInfoRequest {
  const ApprovalInfoRequest({
    this.note,
    this.requiredAttachmentKind,
    this.requiredKindLabel,
    this.requestedAt,
    this.requiredKindUploaded = false,
  });

  factory ApprovalInfoRequest.fromJson(JsonReader r) {
    final kind = r.intOrNull('requiredAttachmentKind');
    return ApprovalInfoRequest(
      note: r.nonEmpty('note'),
      requiredAttachmentKind: kind == null
          ? null
          : AttachmentKind.fromCode(kind),
      requiredKindLabel: r.nonEmpty('requiredKindLabel'),
      requestedAt: r.dateUtc('requestedAt'),
      requiredKindUploaded: r.boolean('requiredKindUploaded'),
    );
  }

  final String? note;

  /// İstenen belge türü (yoksa yanıt belgesi "Diğer" olarak yüklenir).
  final AttachmentKind? requiredAttachmentKind;
  final String? requiredKindLabel;
  final DateTime? requestedAt;

  /// İstenen türde belge istekten sonra eklendi mi.
  final bool requiredKindUploaded;

  /// Yanıt belgelerinin türü (spec A.4: `requiredAttachmentKind ?? Other`).
  AttachmentKind get uploadKind =>
      requiredAttachmentKind == null || requiredAttachmentKind!.isUnknown
      ? AttachmentKind.other
      : requiredAttachmentKind!;

  String? get displayKindLabel =>
      requiredKindLabel ?? requiredAttachmentKind?.label;
}

/// Koşullu onay alanı türleri (`ApprovalConditionFieldTypes`).
abstract final class ConditionFieldTypes {
  static const method = 'method';
  static const integer = 'int';
  static const money = 'money';
  static const period = 'period';
  static const riskClass = 'riskClass';
  static const percent = 'percent';
  static const date = 'date';
  static const methods = 'methods';
}

/// Koşullu onay alanı (`ApprovalConditionFieldDto`). [current] / [suggestion] gönderilecek biçimdedir.
@immutable
class ConditionField {
  const ConditionField({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.min,
    this.max,
    this.current,
    this.currentLabel,
    this.suggestion,
    this.suggestionLabel,
    this.hint,
  });

  factory ConditionField.fromJson(JsonReader r) => ConditionField(
    key: r.str('key'),
    label: r.str('label'),
    type: r.str('type', ConditionFieldTypes.integer),
    required: r.boolean('required'),
    min: r.decOrNull('min'),
    max: r.decOrNull('max'),
    current: r.nonEmpty('current'),
    currentLabel: r.nonEmpty('currentLabel'),
    suggestion: r.nonEmpty('suggestion'),
    suggestionLabel: r.nonEmpty('suggestionLabel'),
    hint: r.nonEmpty('hint'),
  );

  final String key;
  final String label;
  final String type;
  final bool required;
  final double? min;
  final double? max;
  final String? current;
  final String? currentLabel;
  final String? suggestion;
  final String? suggestionLabel;
  final String? hint;
}

/// Ödeme yöntemi seçeneği (`ApprovalMethodOptionDto`).
@immutable
class ConditionMethodOption {
  const ConditionMethodOption({
    required this.code,
    required this.name,
    this.isDeferred = false,
    this.minTermDays,
    this.maxTermDays,
  });

  factory ConditionMethodOption.fromJson(JsonReader r) => ConditionMethodOption(
    code: r.str('code'),
    name: r.str('name', r.str('code')),
    isDeferred: r.boolean('isDeferred'),
    minTermDays: r.intOrNull('minTermDays'),
    maxTermDays: r.intOrNull('maxTermDays'),
  );

  final String code;
  final String name;
  final bool isDeferred;
  final int? minTermDays;
  final int? maxTermDays;
}

/// Kod + etiket (dönem, risk sınıfı seçenekleri).
@immutable
class CodeLabel {
  const CodeLabel(this.code, this.label);

  factory CodeLabel.fromJson(JsonReader r) =>
      CodeLabel(r.str('code'), r.str('label', r.str('code')));

  final String code;
  final String label;
}

/// Koşullu onay formu (`ApprovalConditionFormDto`). Alanlar türe göre değişir; karar isteğinin
/// `conditions` nesnesinde yalnızca bu alanların anahtarları gönderilir.
@immutable
class ConditionForm {
  const ConditionForm({
    this.fields = const [],
    this.methodOptions = const [],
    this.periodOptions = const [],
    this.riskClassOptions = const [],
    this.hint,
  });

  factory ConditionForm.fromJson(JsonReader r) => ConditionForm(
    fields: List.unmodifiable(r.list('fields', ConditionField.fromJson)),
    methodOptions: List.unmodifiable(
      r.list('methodOptions', ConditionMethodOption.fromJson),
    ),
    periodOptions: List.unmodifiable(
      r.list('periodOptions', CodeLabel.fromJson),
    ),
    riskClassOptions: List.unmodifiable(
      r.list('riskClassOptions', CodeLabel.fromJson),
    ),
    hint: r.nonEmpty('hint'),
  );

  final List<ConditionField> fields;
  final List<ConditionMethodOption> methodOptions;
  final List<CodeLabel> periodOptions;
  final List<CodeLabel> riskClassOptions;
  final String? hint;

  /// Formun anahtarları (gönderilebilecek tek anahtarlar).
  Set<String> get keys => {for (final f in fields) f.key};

  String methodName(String code) {
    for (final m in methodOptions) {
      if (m.code == code) return m.name;
    }
    return code;
  }
}

/// `GET approvals/{id}` (`ApprovalMobileDetailDto`).
@immutable
class ApprovalDetail {
  const ApprovalDetail({
    required this.row,
    this.summaryText,
    required this.concurrencyToken,
    this.contextJson,
    this.decidedAt,
    this.decidedByUserId,
    this.decidedByName,
    this.decisionNote,
    this.steps = const [],
    this.events = const [],
    this.attachments = const [],
    this.modes = const [],
    this.modeLabels = const [],
    this.onBehalfOfUserId,
    this.onBehalfOfName,
    this.canProvideInfo = false,
    this.canResumeInfo = false,
    this.summary = const ApprovalSummary(),
    this.customerView = false,
    this.infoRequest,
    this.conditionForm,
    this.decisionHint,
  });

  factory ApprovalDetail.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final summary = r.objOrNull('summary');
    return ApprovalDetail(
      row: ApprovalRow.fromJson(r),
      summaryText: r.nonEmpty('summaryText'),
      concurrencyToken: r.str('concurrencyToken'),
      contextJson: r.nonEmpty('contextJson'),
      decidedAt: r.dateUtc('decidedAt'),
      decidedByUserId: r.nonEmpty('decidedByUserId'),
      decidedByName: r.nonEmpty('decidedByName'),
      decisionNote: r.nonEmpty('decisionNote'),
      steps: List.unmodifiable(
        r.list<ApprovalStep>('steps', ApprovalStep.fromJson)
          ..sort((a, b) => a.levelNo.compareTo(b.levelNo)),
      ),
      events: List.unmodifiable(
        r.list<ApprovalEvent>('events', ApprovalEvent.fromJson)..sort(_byTime),
      ),
      attachments: List.unmodifiable(
        r.list('attachments', Attachment.fromJson).where((a) => a.isActive),
      ),
      modes: List.unmodifiable(
        r
            .ints('modes')
            .map(ApprovalDecision.fromCode)
            .where((m) => !m.isUnknown),
      ),
      modeLabels: List.unmodifiable(r.strings('modeLabels')),
      onBehalfOfUserId: r.nonEmpty('onBehalfOfUserId'),
      onBehalfOfName: r.nonEmpty('onBehalfOfName'),
      canProvideInfo: r.boolean('canProvideInfo'),
      canResumeInfo: r.boolean('canResumeInfo'),
      summary: summary == null
          ? const ApprovalSummary()
          : ApprovalSummary.fromJson(summary),
      customerView: r.boolean('customerView'),
      infoRequest: r.objOrNull('infoRequest') == null
          ? null
          : ApprovalInfoRequest.fromJson(r.obj('infoRequest')),
      conditionForm: r.objOrNull('conditionForm') == null
          ? null
          : ConditionForm.fromJson(r.obj('conditionForm')),
      decisionHint: r.nonEmpty('decisionHint'),
    );
  }

  static int _byTime(ApprovalEvent a, ApprovalEvent b) {
    final x = a.occurredAt;
    final y = b.occurredAt;
    if (x == null || y == null) return a.id.compareTo(b.id);
    final c = x.compareTo(y);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  /// Liste satırı alanları.
  final ApprovalRow row;
  final String? summaryText;

  /// Karar isteğinde aynen geri gönderilir (değiştiyse 409).
  final String concurrencyToken;
  final String? contextJson;
  final DateTime? decidedAt;
  final String? decidedByUserId;
  final String? decidedByName;
  final String? decisionNote;
  final List<ApprovalStep> steps;

  /// Eskiden yeniye.
  final List<ApprovalEvent> events;
  final List<Attachment> attachments;

  /// Kullanıcının verebileceği kararlar (karar çubuğu yalnızca bunları gösterir).
  final List<ApprovalDecision> modes;
  final List<String> modeLabels;
  final String? onBehalfOfUserId;
  final String? onBehalfOfName;

  /// Talep eden tarafı ek bilgi yanıtı verebilir ("Yanıtla").
  final bool canProvideInfo;

  /// Onaylayan tarafı "Bilgi alındı" ile incelemeye geri alabilir.
  final bool canResumeInfo;
  final ApprovalSummary summary;

  /// Cari kullanıcısı bayi tarafındaki bir talebe bakıyor: SLA ve kademe ayrıntısı gösterilmez.
  final bool customerView;
  final ApprovalInfoRequest? infoRequest;
  final ConditionForm? conditionForm;
  final String? decisionHint;

  int get id => row.id;
  ApprovalType get type => row.type;
  ApprovalStatus get status => row.status;
  bool get isOpen => row.status.isOpen;

  bool can(ApprovalDecision d) => modes.contains(d);

  /// Kararın etiketi (sunucu etiketi tercih edilir).
  String modeLabel(ApprovalDecision d) {
    final i = modes.indexOf(d);
    if (i >= 0 && i < modeLabels.length && modeLabels[i].trim().isNotEmpty) {
      return modeLabels[i];
    }
    return d.label;
  }

  /// Ret gerekçesinin en kısa uzunluğu (sunucu kuralı; bkz. [ApprovalType.minRejectNoteLength]).
  int get minRejectNoteLength =>
      type.minRejectNoteLength(isMirror: row.isMirror);

  /// Koşullu onaylandı mı (olay günlüğünden).
  bool get isConditionallyApproved =>
      status == ApprovalStatus.approved &&
      events.any((e) => e.eventType == ApprovalEventType.conditionallyApproved);

  /// Ek bilgi isteği cariye yöneltilen türler (sipariş finansı, yeni cari; web `IsCustomerAddressed`).
  bool get isCustomerAddressed =>
      type == ApprovalType.orderFinance ||
      type == ApprovalType.customerOnboarding;

  /// Ön kaydın kimliği (LeadFinance).
  int? get leadId =>
      summary.links.leadId ??
      (row.subjectType == 'CustomerLead' && row.subjectId > 0
          ? row.subjectId
          : null);

  /// Şirket içi sipariş talebinin kimliği (CompanyOrderRequest).
  int? get companyRequestId =>
      summary.links.companyRequestId ??
      (type == ApprovalType.companyOrderRequest && row.subjectId > 0
          ? row.subjectId
          : null);

  /// Kullanıcının bu talepteki son kararı bu andan sonra kaydedildi mi (belirsiz sonuçta uzlaştırma).
  bool hasEventBy(String userId, ApprovalEventType type, DateTime since) =>
      events.any(
        (e) =>
            e.userId == userId &&
            e.eventType == type &&
            (e.occurredAt == null || !e.occurredAt!.isBefore(since)),
      );
}

/// `GET approvals/badge`.
@immutable
class ApprovalBadge {
  const ApprovalBadge({this.toMe = 0, this.overdue = 0});

  static const zero = ApprovalBadge();

  factory ApprovalBadge.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return ApprovalBadge(
      toMe: r.integer('toMe'),
      overdue: r.integer('overdue'),
    );
  }

  final int toMe;
  final int overdue;
}

/// `POST approvals/{id}/decide` yanıtı (`ApprovalDecisionResult`).
@immutable
class ApprovalDecisionResult {
  const ApprovalDecisionResult({
    required this.requestId,
    required this.status,
    this.isFinal = false,
    this.currentLevelNo = 1,
    this.message = '',
    this.concurrencyToken,
  });

  factory ApprovalDecisionResult.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return ApprovalDecisionResult(
      requestId: r.integer('requestId'),
      status: r.enumOf('status', ApprovalStatus.fromCode),
      isFinal: r.boolean('isFinal'),
      currentLevelNo: r.integer('currentLevelNo', 1),
      message: r.str('message'),
      concurrencyToken: r.nonEmpty('concurrencyToken'),
    );
  }

  final int requestId;
  final ApprovalStatus status;
  final bool isFinal;
  final int currentLevelNo;
  final String message;
  final String? concurrencyToken;
}

/// Şirket içi sipariş talebi satırı (`CustomerOrderRequestLineDto`): onaydan sonra oluşan sipariş ya da hata.
@immutable
class CompanyRequestLine {
  const CompanyRequestLine({
    this.stationId,
    this.productId,
    this.deliveryPointId,
    this.quantityLiters = 0,
    this.requestedDeliveryDate,
    this.estimatedUnitPrice,
    this.orderId,
    this.orderNumber,
    this.error,
    this.stationTitle,
    this.productName,
    this.deliveryPointName,
  });

  factory CompanyRequestLine.fromJson(JsonReader r) => CompanyRequestLine(
    stationId: r.intOrNull('stationId'),
    productId: r.intOrNull('productId'),
    deliveryPointId: r.intOrNull('deliveryPointId'),
    quantityLiters: r.dec('quantityLiters'),
    requestedDeliveryDate: r.dateTr('requestedDeliveryDate'),
    estimatedUnitPrice: r.decOrNull('estimatedUnitPrice'),
    orderId: r.intOrNull('orderId'),
    orderNumber: r.nonEmpty('orderNumber'),
    error: r.nonEmpty('error'),
    stationTitle: r.nonEmpty('stationTitle'),
    productName: r.nonEmpty('productName'),
    deliveryPointName: r.nonEmpty('deliveryPointName'),
  );

  final int? stationId;
  final int? productId;
  final int? deliveryPointId;
  final double quantityLiters;
  final DateTime? requestedDeliveryDate;
  final double? estimatedUnitPrice;
  final int? orderId;
  final String? orderNumber;
  final String? error;
  final String? stationTitle;
  final String? productName;
  final String? deliveryPointName;

  bool get created => orderId != null;
  bool get failed => orderId == null && error != null;
}

/// `GET customers/me/order-requests/{id}` (`CustomerOrderRequestDto`; yalnızca kullanılan alanlar).
@immutable
class CompanyRequest {
  const CompanyRequest({
    required this.id,
    required this.status,
    this.statusLabel,
    this.requestedByName,
    this.totalLiters = 0,
    this.estimatedAmount,
    this.note,
    this.decidedByName,
    this.decidedAt,
    this.decisionNote,
    this.createdOrderIds = const [],
    this.createdAt,
    this.lines = const [],
    this.paymentDisplay,
  });

  factory CompanyRequest.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return CompanyRequest(
      id: r.integer('id'),
      status: r.enumOf('status', CustomerOrderRequestStatus.fromCode),
      statusLabel: r.nonEmpty('statusLabel'),
      requestedByName: r.nonEmpty('requestedByName'),
      totalLiters: r.dec('totalLiters'),
      estimatedAmount: r.decOrNull('estimatedAmount'),
      note: r.nonEmpty('note'),
      decidedByName: r.nonEmpty('decidedByName'),
      decidedAt: r.dateUtc('decidedAt'),
      decisionNote: r.nonEmpty('decisionNote'),
      createdOrderIds: List.unmodifiable(r.ints('createdOrderIds')),
      createdAt: r.dateUtc('createdAt'),
      lines: List.unmodifiable(r.list('lines', CompanyRequestLine.fromJson)),
      paymentDisplay: r.nonEmpty('paymentDisplay'),
    );
  }

  final int id;
  final CustomerOrderRequestStatus status;
  final String? statusLabel;
  final String? requestedByName;
  final double totalLiters;
  final double? estimatedAmount;
  final String? note;
  final String? decidedByName;
  final DateTime? decidedAt;
  final String? decisionNote;
  final List<int> createdOrderIds;
  final DateTime? createdAt;
  final List<CompanyRequestLine> lines;
  final String? paymentDisplay;

  int get createdCount => lines.where((l) => l.created).length;
  int get failedCount => lines.where((l) => l.failed).length;
  bool get hasFailures => failedCount > 0;
  String get displayStatusLabel => statusLabel ?? status.label;
}

/// `GET leads/{id}` (yalnızca "Merkeze ilet" için gereken alanlar; sahibi A6/B6).
@immutable
class LeadForwardInfo {
  const LeadForwardInfo({
    required this.id,
    required this.status,
    this.canForwardToHq = false,
    this.isForwardedToHq = false,
    this.existsElsewhere = false,
  });

  factory LeadForwardInfo.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return LeadForwardInfo(
      id: r.integer('id'),
      status: r.enumOf('status', LeadStatus.fromCode),
      canForwardToHq: r.boolean('canForwardToHq'),
      isForwardedToHq: r.boolean('isForwardedToHq'),
      existsElsewhere: r.boolean('existsElsewhere'),
    );
  }

  final int id;
  final LeadStatus status;
  final bool canForwardToHq;
  final bool isForwardedToHq;
  final bool existsElsewhere;

  /// Finans onayı bekliyor (spec A.4: "Merkeze ilet" yalnızca Submitted / InReview).
  bool get awaitingFinance =>
      status == LeadStatus.submitted || status == LeadStatus.inReview;
}
