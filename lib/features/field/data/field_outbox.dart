import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/media/attachment_api.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/outbox_op.dart';
import '../../../core/offline/outbox_providers.dart';
import '../../../core/offline/outbox_runner.dart';
import '../../../core/offline/outbox_store.dart';
import 'field_models.dart';
import 'field_repository.dart';
import 'lead_models.dart';

/// Saha bekleyen işlem türleri (spec C.4).
abstract final class FieldOps {
  /// Saha formu taslağı (yeni: POST field-orders + Idempotency-Key; mevcut: PUT field-orders/{id}).
  static const saveDraft = 'field.saveDraft';

  /// Ön kayıt taslağı (yeni: POST leads + Idempotency-Key; mevcut: PUT leads/{id}).
  static const leadSaveDraft = 'lead.saveDraft';

  /// Ön kayıt belgesi (POST attachments, sahip CustomerLead = 5). Ön kayıt kuyrukta ise ona bağlıdır.
  static const leadUpload = 'lead.upload';

  static const all = {saveDraft, leadSaveDraft, leadUpload};
  static const forms = {saveDraft};
  static const leads = {leadSaveDraft, leadUpload};
}

/// Gövde anahtarları.
abstract final class _K {
  static const formId = 'formId';
  static const request = 'request';
  static const leadId = 'leadId';
  static const body = 'body';
  static const kind = 'kind';
  static const filePath = 'filePath';
  static const fileName = 'fileName';
  static const contentType = 'contentType';
  static const title = 'title';
  static const customerTitle = 'customerTitle';
  static const liters = 'liters';
}

/// Uygulama katmanının `outboxHandlersProvider`'ına eklenen işleyiciler.
Map<String, OutboxHandler> buildFieldOutboxHandlers() => {
  FieldOps.saveDraft: _saveForm,
  FieldOps.leadSaveDraft: _saveLead,
  FieldOps.leadUpload: _uploadLead,
};

Future<JsonMap?> _saveForm(OutboxOp op, OutboxContext ctx) async {
  final repo = FieldRepository(ctx.api);
  final payload = ctx.payload;
  final request = Map<String, dynamic>.of(
    JsonReader.asMap(payload[_K.request]),
  );
  final dep = ctx.dependencyResult;
  final formId =
      JsonReader.toInt(payload[_K.formId]) ?? JsonReader.toInt(dep?[_K.formId]);
  if (formId == null) {
    request.remove('concurrencyToken');
    final form = await repo.createForm(
      request,
      idempotencyKey: op.idempotencyKey,
    );
    return _formResult(form);
  }
  var token = dep?['concurrencyToken'] as String?;
  if (ctx.isConflictRetry) {
    // Çakışma sonrası tek tekrar (çekirdek kuyruk, spec D.7): taslağın güncel belirteci okunur.
    token = (await repo.form(formId)).form.concurrencyToken;
  }
  if (token != null) request['concurrencyToken'] = token;
  try {
    final form = await repo.updateForm(formId, request);
    return _formResult(form);
  } on AppFailure catch (f) {
    // Zaman aşımından sonraki tekrar: güncelleme sunucuda işlenmiş olabilir (belirteç değişti).
    // Formun içeriği gönderdiğimizle aynıysa işlem tamamdır (spec C.4a uzlaştırma).
    if (_isConcurrency(f)) {
      final current = (await repo.form(formId)).form;
      if (_sameFormContent(current, request)) return _formResult(current);
    }
    rethrow;
  }
}

JsonMap _formResult(FieldForm f) => {
  _K.formId: f.id,
  'formNumber': f.formNumber,
  'concurrencyToken': f.concurrencyToken,
  _K.customerTitle: f.customerTitle,
};

bool _isConcurrency(AppFailure f) =>
    (f is ConflictFailure && f.isConcurrency) ||
    (f is BusinessFailure &&
        (f.message.contains('değiştirildi') ||
            f.message.contains('başka bir oturumda')));

/// Sunucudaki form, kuyruktaki istekle aynı mı (satır içerikleri).
bool _sameFormContent(FieldForm f, JsonMap request) {
  final r = JsonReader(request);
  if (r.integer('customerId') != f.customerId) return false;
  if (r.integer('paymentTermDays') != f.paymentTermDays) return false;
  if ((r.nonEmpty('note') ?? '') != (f.note ?? '')) return false;
  final lines = r.list('lines', (l) => l);
  if (lines.length != f.lines.length) return false;
  for (var i = 0; i < lines.length; i++) {
    final a = lines[i];
    final b = f.lines[i];
    if (a.integer('productId') != b.productId ||
        a.integer('deliveryPointId') != b.deliveryPointId ||
        (a.dec('quantityLiters') - b.quantityLiters).abs() > 0.0005 ||
        (a.dec('proposedUnitPrice') - b.proposedUnitPrice).abs() > 0.00005) {
      return false;
    }
  }
  return true;
}

Future<JsonMap?> _saveLead(OutboxOp op, OutboxContext ctx) async {
  final repo = FieldRepository(ctx.api);
  final payload = ctx.payload;
  final body = Map<String, dynamic>.of(JsonReader.asMap(payload[_K.body]));
  final dep = ctx.dependencyResult;
  final leadId =
      JsonReader.toInt(payload[_K.leadId]) ?? JsonReader.toInt(dep?[_K.leadId]);
  if (leadId == null || leadId <= 0) {
    body['id'] = 0;
    final saved = await repo.createLead(
      body,
      idempotencyKey: op.idempotencyKey,
    );
    return _leadResult(saved);
  }
  body['id'] = leadId;
  var token = dep?['concurrencyToken'] as String?;
  if (ctx.isConflictRetry) {
    token = (await repo.lead(leadId)).draft.concurrencyToken ?? token;
  }
  if (token != null) body['concurrencyToken'] = token;
  try {
    final saved = await repo.updateLead(leadId, body);
    return _leadResult(saved);
  } on AppFailure catch (f) {
    if (_isConcurrency(f)) {
      final current = await repo.lead(leadId);
      if (_sameLeadContent(current.draft, body)) {
        return {
          _K.leadId: current.id,
          'leadNumber': current.leadNumber,
          'concurrencyToken': current.draft.concurrencyToken,
        };
      }
    }
    rethrow;
  }
}

JsonMap _leadResult(LeadSaveResult r) => {
  _K.leadId: r.id,
  'leadNumber': r.leadNumber,
  'concurrencyToken': r.concurrencyToken,
};

bool _sameLeadContent(LeadDraft d, JsonMap body) {
  final r = JsonReader(body);
  return r.str('companyTitle') == d.companyTitle &&
      r.str('taxNumber') == d.taxNumber &&
      (r.nonEmpty('city') ?? '') == (d.city ?? '') &&
      r.boolean('kvkkConsent') == d.kvkkConsent &&
      r.list('contacts', (c) => c).length ==
          d.contacts.where((c) => !c.isEmpty).length;
}

Future<JsonMap?> _uploadLead(OutboxOp op, OutboxContext ctx) async {
  final payload = ctx.payload;
  final leadId =
      JsonReader.toInt(payload[_K.leadId]) ??
      JsonReader.toInt(ctx.dependencyResult?[_K.leadId]);
  if (leadId == null || leadId <= 0) {
    throw const BusinessFailure(
      'Belge yüklenemedi: ön kayıt henüz kaydedilmedi.',
    );
  }
  final path = payload[_K.filePath] as String?;
  if (path == null || !File(path).existsSync()) {
    throw const BusinessFailure(
      'Belge dosyası cihazda bulunamadı; belgeyi yeniden ekleyin.',
    );
  }
  final result = await AttachmentApi(ctx.api).upload(
    ownerType: AttachmentOwnerType.customerLead,
    ownerId: leadId,
    kind: AttachmentKind.fromCode(JsonReader.toInt(payload[_K.kind])),
    filePath: path,
    fileName: payload[_K.fileName] as String?,
    contentType: payload[_K.contentType] as String?,
    idempotencyKey: op.idempotencyKey,
  );
  return {_K.leadId: leadId, 'publicId': result.attachment.publicId};
}

// ═══════════════════════════════════════════════════════════════════ Kuyruğa ekleme

/// Saha bekleyen işlemlerini kuyruğa ekler ve okur.
class FieldOutbox {
  FieldOutbox(this._runner, this._ref);

  final OutboxRunner _runner;
  final Ref _ref;

  /// Saha formu taslağı. [chainAfter]: aynı taslağın henüz gönderilmemiş önceki işlemi (düzenleme).
  Future<OutboxOp> queueFormSave({
    required JsonMap request,
    required String idempotencyKey,
    int? formId,
    String? chainAfter,
    String? customerTitle,
    String? formNumber,
    double? liters,
  }) => _runner.enqueue(
    type: FieldOps.saveDraft,
    payload: {
      _K.formId: formId,
      _K.request: request,
      _K.customerTitle: customerTitle,
      _K.liters: liters,
      _K.title: formNumber,
    },
    dependsOn: chainAfter,
    idempotencyKey: idempotencyKey,
    label: formNumber != null
        ? '$formNumber taslağı'
        : 'Saha formu taslağı${customerTitle == null ? '' : ', $customerTitle'}',
  );

  /// Ön kayıt taslağı.
  Future<OutboxOp> queueLeadSave({
    required JsonMap body,
    required String idempotencyKey,
    int? leadId,
    String? chainAfter,
    String? leadNumber,
    String? companyTitle,
  }) => _runner.enqueue(
    type: FieldOps.leadSaveDraft,
    payload: {
      _K.leadId: leadId,
      _K.body: body,
      _K.title: leadNumber,
      _K.customerTitle: companyTitle,
    },
    dependsOn: chainAfter,
    idempotencyKey: idempotencyKey,
    label: leadNumber != null
        ? '$leadNumber ön kaydı'
        : 'Ön kayıt${(companyTitle ?? '').isEmpty ? '' : ', $companyTitle'}',
  );

  /// Ön kayıt belgesi. [filePath] kalıcı klasörde olmalıdır (`OutboxFiles.persist`).
  Future<OutboxOp> queueLeadUpload({
    required AttachmentKind kind,
    required String filePath,
    required String fileName,
    required String contentType,
    int? leadId,
    String? dependsOn,
    String? companyTitle,
  }) => _runner.enqueue(
    type: FieldOps.leadUpload,
    payload: {
      _K.leadId: leadId,
      _K.kind: kind.code,
      _K.filePath: filePath,
      _K.fileName: fileName,
      _K.contentType: contentType,
      _K.customerTitle: companyTitle,
    },
    files: [filePath],
    dependsOn: dependsOn,
    label:
        '${kind.label}${(companyTitle ?? '').isEmpty ? '' : ', $companyTitle'}',
  );

  /// Vazgeç: kayıt işleminde aynı taslağın gönderilmemiş tüm halkaları ve onlara bağlı işlemler (ör.
  /// ön kaydın belgeleri) silinir; belge işleminde yalnızca o belge.
  Future<void> discardChain(String opId) async {
    // Depodan okunur: akış sağlayıcısı henüz yayın yapmamış olabilir (zincirin bir kısmı kalmasın).
    final uid = _ref.read(currentUserIdProvider);
    final ops = uid == null
        ? const <OutboxOp>[]
        : await _ref.read(outboxStoreProvider).list(uid);
    final ids = fieldChainIds(ops, opId);
    for (final id in ids) {
      await _runner.discard(id);
    }
  }

  Future<void> retry(String opId) => _runner.retry(opId);
}

final fieldOutboxProvider = Provider<FieldOutbox>(
  (ref) => FieldOutbox(ref.watch(outboxRunnerProvider), ref),
);

/// [opId] ile birlikte vazgeçilecek işlemler (bkz. [FieldOutbox.discardChain]).
Set<String> fieldChainIds(List<OutboxOp> ops, String opId) {
  final byId = {for (final o in ops) o.id: o};
  final start = byId[opId];
  if (start == null) return {opId};
  if (start.type == FieldOps.leadUpload) return {opId};
  final ids = <String>{};
  // Geriye: aynı türden, henüz gönderilmemiş halkalar.
  OutboxOp? cur = start;
  var guard = 0;
  while (cur != null && guard++ < 50) {
    if (cur.status == OutboxStatus.done || cur.type != start.type) break;
    ids.add(cur.id);
    final dep = cur.dependsOn;
    cur = dep == null ? null : byId[dep];
  }
  // İleriye: bunlara bağlı her işlem.
  var grew = true;
  while (grew) {
    grew = false;
    for (final o in ops) {
      if (o.status == OutboxStatus.done || ids.contains(o.id)) continue;
      final dep = o.dependsOn;
      if (dep != null && ids.contains(dep)) {
        ids.add(o.id);
        grew = true;
      }
    }
  }
  return ids;
}

// ═══════════════════════════════════════════════════════════════════ Görünüm

/// Kullanıcıya gösterilen bekleyen saha işlemi (zincirin son halkası).
class FieldQueuedItem {
  FieldQueuedItem(this.op, {required this.chain});

  final OutboxOp op;

  /// Zincirdeki gönderilmemiş tüm işlemler (baştan sona).
  final List<OutboxOp> chain;

  String get type => op.type;
  bool get isForm => op.type == FieldOps.saveDraft;
  bool get isLead => op.type == FieldOps.leadSaveDraft;
  bool get isUpload => op.type == FieldOps.leadUpload;

  /// En kötü durum (ilgilenilmesi gereken öne çıkar).
  OutboxStatus get status {
    if (chain.any((o) => o.status == OutboxStatus.needsAttention)) {
      return OutboxStatus.needsAttention;
    }
    if (chain.any((o) => o.status == OutboxStatus.sending)) {
      return OutboxStatus.sending;
    }
    if (chain.any((o) => o.status == OutboxStatus.failed)) {
      return OutboxStatus.failed;
    }
    return op.status;
  }

  String? get lastError {
    for (final o in chain.reversed) {
      if (o.status == OutboxStatus.needsAttention && o.lastError != null) {
        return o.lastError;
      }
    }
    return op.lastError;
  }

  DateTime? get nextAttemptAt => op.nextAttemptAt;

  String get title => op.label ?? 'Bekleyen işlem';

  String? get customerTitle => op.payload[_K.customerTitle] as String?;

  double? get liters => JsonReader.toDouble(op.payload[_K.liters]);

  /// Düzenlenebilir taslak isteği (saha formu).
  JsonMap? get formRequest =>
      isForm ? JsonReader.asMap(op.payload[_K.request]) : null;

  int? get formId => JsonReader.toInt(op.payload[_K.formId]);

  /// Ön kayıt gövdesi.
  JsonMap? get leadBody =>
      isLead ? JsonReader.asMap(op.payload[_K.body]) : null;

  int? get leadId => JsonReader.toInt(op.payload[_K.leadId]);

  String? get uploadKindLabel => isUpload
      ? AttachmentKind.fromCode(JsonReader.toInt(op.payload[_K.kind])).label
      : null;

  /// Zincirin başı (ilk işlem).
  OutboxOp get head => chain.first;
}

/// Kullanıcının gönderilmemiş saha işlemleri, zincir başına bir öğe (ön kayıt belgeleri kendi ön kaydının
/// zincirine katılmaz; ayrı öğe olarak görünür).
List<FieldQueuedItem> groupFieldOps(List<OutboxOp> all, {Set<String>? types}) {
  final open = [
    for (final o in all)
      if (FieldOps.all.contains(o.type) && o.status != OutboxStatus.done) o,
  ];
  final byId = {for (final o in all) o.id: o};
  // Kayıt işlemlerinin zincir kuyruğu: başka bir aynı tür işlemin bağlı olduğu işlem kuyruk değildir.
  final referenced = <String>{
    for (final o in open)
      if (o.dependsOn != null &&
          byId[o.dependsOn]?.type == o.type &&
          o.type != FieldOps.leadUpload)
        o.dependsOn!,
  };
  final out = <FieldQueuedItem>[];
  for (final o in open) {
    if (types != null && !types.contains(o.type)) continue;
    if (referenced.contains(o.id)) continue;
    final chain = <OutboxOp>[o];
    var dep = o.dependsOn;
    var guard = 0;
    while (dep != null && guard++ < 20 && o.type != FieldOps.leadUpload) {
      final d = byId[dep];
      if (d == null || d.status == OutboxStatus.done || d.type != o.type) break;
      chain.insert(0, d);
      dep = d.dependsOn;
    }
    out.add(FieldQueuedItem(o, chain: chain));
  }
  return out;
}

/// Kullanıcının bekleyen saha işlemleri (değişince yenilenir).
final fieldQueuedItemsProvider = Provider<List<FieldQueuedItem>>((ref) {
  ref.watch(currentUserIdProvider);
  final ops = ref.watch(outboxOpsProvider).valueOrNull ?? const <OutboxOp>[];
  return groupFieldOps(ops);
});

/// Bir işlemin anlık hâli (kuyruk sonucu ekranı izler).
final fieldOpProvider = Provider.family<OutboxOp?, String>((ref, id) {
  final ops = ref.watch(outboxOpsProvider).valueOrNull ?? const <OutboxOp>[];
  for (final o in ops) {
    if (o.id == id) return o;
  }
  return null;
});
