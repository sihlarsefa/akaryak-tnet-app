import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/media/attachment_api.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/idempotency.dart';
import '../../../core/offline/cache_store.dart';
import '../../../core/offline/connectivity.dart';
import '../../../core/offline/outbox_files.dart';
import '../../../core/offline/outbox_op.dart';
import '../../../core/offline/outbox_store.dart';
import '../../../core/storage/user_drafts.dart';
import '../../../core/utils/debouncer.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../../../core/utils/validators.dart';
import '../data/field_location.dart';
import '../data/field_outbox.dart';
import '../data/field_repository.dart';
import '../data/lead_models.dart';
import 'field_lists.dart';
import 'uncertain.dart';

/// Ön kayıt sihirbazı adımları (spec A.3 L1).
enum LeadWizardStep {
  company('Firma'),
  fleet('Filo / depo'),
  needs('İhtiyaç'),
  payment('Ödeme talebi'),
  visit('Ziyaret'),
  contacts('Yetkililer'),
  delivery('Teslimat noktası'),
  kvkk('KVKK'),
  documents('Belgeler');

  const LeadWizardStep(this.title);
  final String title;
}

/// Kalıcı dosya deposu (bekleyen işlem dosyaları; testler sahte verir).
abstract interface class FieldFileStore {
  /// Geçici dosyayı uygulama klasörüne kopyalar.
  Future<String> persist(String path);

  Future<void> delete(String path);
}

class _OutboxFileStore implements FieldFileStore {
  const _OutboxFileStore();

  @override
  Future<String> persist(String path) => OutboxFiles.persist(path);

  @override
  Future<void> delete(String path) async {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

final fieldFileStoreProvider = Provider<FieldFileStore>(
  (ref) => const _OutboxFileStore(),
);

/// Sihirbaza eklenen belge (kamera / galeri).
@immutable
class LeadDocInput {
  const LeadDocInput({
    required this.kind,
    required this.path,
    required this.fileName,
    this.contentType = 'image/jpeg',
    this.sizeBytes = 0,
  });

  final AttachmentKind kind;
  final String path;
  final String fileName;
  final String contentType;
  final int sizeBytes;
}

enum LeadDocState { pending, uploading, failed, queued }

/// Henüz sunucuda olmayan belge.
@immutable
class LeadLocalDoc {
  const LeadLocalDoc({
    required this.localId,
    required this.input,
    this.state = LeadDocState.pending,
    this.progress,
    this.error,
    this.opId,
  });

  final String localId;
  final LeadDocInput input;
  final LeadDocState state;
  final double? progress;
  final String? error;

  /// Kuyruktaki yükleme işlemi.
  final String? opId;

  LeadLocalDoc copyWith({
    LeadDocState? state,
    double? progress,
    String? error,
    String? opId,
  }) => LeadLocalDoc(
    localId: localId,
    input: input,
    state: state ?? this.state,
    progress: progress,
    error: error,
    opId: opId ?? this.opId,
  );
}

sealed class LeadWizardOutcome {
  const LeadWizardOutcome();
}

class LeadSaved extends LeadWizardOutcome {
  const LeadSaved(this.result);
  final LeadSaveResult result;
}

class LeadQueued extends LeadWizardOutcome {
  const LeadQueued(this.opId, {this.submitRequested = false});
  final String opId;
  final bool submitRequested;
}

class LeadSubmitted extends LeadWizardOutcome {
  const LeadSubmitted({
    required this.leadId,
    required this.leadNumber,
    required this.message,
  });
  final int leadId;
  final String leadNumber;
  final String message;
}

@immutable
class LeadWizardArgs {
  const LeadWizardArgs({this.leadId, this.queuedOpId});

  final int? leadId;
  final String? queuedOpId;

  String get storageKey => leadId != null
      ? '${UserDrafts.fieldWizardPrefix}lead.$leadId'
      : queuedOpId != null
      ? '${UserDrafts.fieldWizardPrefix}leadop.$queuedOpId'
      : '${UserDrafts.fieldWizardPrefix}lead.new';

  @override
  bool operator ==(Object other) =>
      other is LeadWizardArgs &&
      other.leadId == leadId &&
      other.queuedOpId == queuedOpId;

  @override
  int get hashCode => Object.hash(leadId, queuedOpId);
}

@immutable
class LeadWizardState {
  const LeadWizardState({
    this.draft = const LeadDraft(),
    this.step = LeadWizardStep.company,
    this.loading = false,
    this.loadError,
    this.options,
    this.optionsError,
    this.dup,
    this.dupChecking = false,
    this.serverDocs = const [],
    this.docsLoading = false,
    this.localDocs = const [],
    this.leadNumber,
    this.status,
    this.decisionNote,
    this.busy = false,
    this.busyLabel,
    this.banner,
    this.conflict = false,
    this.errors = const {},
    this.missing = const [],
    this.baseFingerprint = '',
    this.outcome,
    this.resumeCandidate,
    this.resumeSavedAt,
    this.queuedOpId,
  });

  final LeadDraft draft;
  final LeadWizardStep step;
  final bool loading;
  final AppFailure? loadError;
  final LeadOptions? options;
  final AppFailure? optionsError;
  final LeadDuplicateCheck? dup;
  final bool dupChecking;
  final List<Attachment> serverDocs;
  final bool docsLoading;
  final List<LeadLocalDoc> localDocs;
  final String? leadNumber;
  final LeadStatus? status;

  /// Finans ek bilgi istediyse notu.
  final String? decisionNote;
  final bool busy;
  final String? busyLabel;
  final String? banner;
  final bool conflict;
  final Map<String, String> errors;

  /// Son gönderim denemesinde eksik kalanlar (sunucu ile aynı metinler).
  final List<String> missing;
  final String baseFingerprint;
  final LeadWizardOutcome? outcome;
  final LeadDraft? resumeCandidate;
  final DateTime? resumeSavedAt;
  final String? queuedOpId;

  bool get dirty => draft.fingerprint != baseFingerprint;
  LeadOptions get effectiveOptions => options ?? const LeadOptions();

  /// Vergi levhası yüklendi ya da yüklenmek üzere (sırada / yükleniyor).
  bool get taxPlateReady =>
      serverDocs.any((a) => a.kind == AttachmentKind.taxPlate && a.isActive) ||
      localDocs.any((d) => d.input.kind == AttachmentKind.taxPlate);

  /// Vergi levhası sunucuda (gönderim şartı).
  bool get taxPlateUploaded =>
      serverDocs.any((a) => a.kind == AttachmentKind.taxPlate && a.isActive);

  List<String> get missingNow => LeadRules.missingForSubmit(
    draft,
    taxPlateReady: taxPlateReady,
    taxNumberError: Validators.taxNumber,
  );

  bool get kvkkReady =>
      draft.kvkkConsent && (draft.kvkkConsentMethod ?? '').trim().isNotEmpty;

  static const _unset = Object();

  LeadWizardState copyWith({
    LeadDraft? draft,
    LeadWizardStep? step,
    bool? loading,
    Object? loadError = _unset,
    Object? options = _unset,
    Object? optionsError = _unset,
    Object? dup = _unset,
    bool? dupChecking,
    List<Attachment>? serverDocs,
    bool? docsLoading,
    List<LeadLocalDoc>? localDocs,
    Object? leadNumber = _unset,
    Object? status = _unset,
    Object? decisionNote = _unset,
    bool? busy,
    Object? busyLabel = _unset,
    Object? banner = _unset,
    bool? conflict,
    Map<String, String>? errors,
    List<String>? missing,
    String? baseFingerprint,
    Object? outcome = _unset,
    Object? resumeCandidate = _unset,
    Object? resumeSavedAt = _unset,
    Object? queuedOpId = _unset,
  }) {
    T pick<T>(Object? v, T current) => identical(v, _unset) ? current : v as T;
    return LeadWizardState(
      draft: draft ?? this.draft,
      step: step ?? this.step,
      loading: loading ?? this.loading,
      loadError: pick<AppFailure?>(loadError, this.loadError),
      options: pick<LeadOptions?>(options, this.options),
      optionsError: pick<AppFailure?>(optionsError, this.optionsError),
      dup: pick<LeadDuplicateCheck?>(dup, this.dup),
      dupChecking: dupChecking ?? this.dupChecking,
      serverDocs: serverDocs ?? this.serverDocs,
      docsLoading: docsLoading ?? this.docsLoading,
      localDocs: localDocs ?? this.localDocs,
      leadNumber: pick<String?>(leadNumber, this.leadNumber),
      status: pick<LeadStatus?>(status, this.status),
      decisionNote: pick<String?>(decisionNote, this.decisionNote),
      busy: busy ?? this.busy,
      busyLabel: pick<String?>(busyLabel, this.busyLabel),
      banner: pick<String?>(banner, this.banner),
      conflict: conflict ?? this.conflict,
      errors: errors ?? this.errors,
      missing: missing ?? this.missing,
      baseFingerprint: baseFingerprint ?? this.baseFingerprint,
      outcome: pick<LeadWizardOutcome?>(outcome, this.outcome),
      resumeCandidate: pick<LeadDraft?>(resumeCandidate, this.resumeCandidate),
      resumeSavedAt: pick<DateTime?>(resumeSavedAt, this.resumeSavedAt),
      queuedOpId: pick<String?>(queuedOpId, this.queuedOpId),
    );
  }
}

final leadWizardProvider = NotifierProvider.autoDispose
    .family<LeadWizardController, LeadWizardState, LeadWizardArgs>(
      LeadWizardController.new,
    );

/// Ön kayıt sihirbazı (spec A.3 L1–L2): canlı VKN kontrolü, ziyaret konumu (doğrulukla), KVKK açık
/// rızası, belgeler (vergi levhası zorunlu). Kayıt çevrimdışı güvenlidir; "Finansa gönder" bağlantı ister.
class LeadWizardController
    extends AutoDisposeFamilyNotifier<LeadWizardState, LeadWizardArgs> {
  static const _resumeLifetime = Duration(hours: 24);

  late final Debouncer _dupDebounce = Debouncer(
    const Duration(milliseconds: 500),
  );
  late final Debouncer _autosaveDebounce = Debouncer(
    const Duration(milliseconds: 800),
  );
  int _dupEpoch = 0;
  String? _createKey;
  String? _createKeyFingerprint;
  int _docSeq = 0;

  FieldRepository get _repo => ref.read(fieldRepositoryProvider);

  @override
  LeadWizardState build(LeadWizardArgs arg) {
    ref.onDispose(() {
      _dupDebounce.dispose();
      _autosaveDebounce.dispose();
    });
    final stationId = ref.read(accessPolicyProvider).access?.stationId ?? 0;
    final initial = LeadDraft(
      stationId: stationId,
      visitAt: TrTime.todayStart(),
      contacts: const [LeadContact(isPrimary: true, isInviteRecipient: true)],
    );
    Future.microtask(_init);
    return LeadWizardState(
      draft: initial,
      baseFingerprint: initial.fingerprint,
      loading: arg.leadId != null || arg.queuedOpId != null,
    );
  }

  Future<void> _init() async {
    unawaited(_loadOptions());
    final id = arg.leadId;
    final opId = arg.queuedOpId;
    if (id != null) {
      await _openExisting(id);
    } else if (opId != null) {
      await _openQueued(opId);
    } else {
      await _checkResume();
    }
  }

  Future<void> _loadOptions() async {
    try {
      final o = await _repo.leadOptions();
      var draft = state.draft;
      // Her ürün için bir ihtiyaç satırı (web `ProductRows`): girilen litreler korunur.
      final existing = {for (final p in draft.products) p.productId: p};
      final products = <LeadProductNeed>[
        for (final p in o.products)
          if (int.tryParse(p.value) case final pid?)
            existing[pid] ??
                LeadProductNeed(productId: pid, productName: p.text),
      ];
      for (final p in draft.products) {
        if (!products.any((x) => x.productId == p.productId)) products.add(p);
      }
      final wasBase = state.baseFingerprint == draft.fingerprint;
      draft = draft.copyWith(products: products);
      state = state.copyWith(
        options: o,
        optionsError: null,
        draft: draft,
        baseFingerprint: wasBase ? draft.fingerprint : state.baseFingerprint,
      );
    } catch (e) {
      state = state.copyWith(optionsError: AppFailure.from(e));
    }
  }

  Future<void> _openExisting(int id) async {
    try {
      final d = await _repo.lead(id);
      var draft = d.draft;
      if (draft.contacts.isEmpty) {
        draft = draft.copyWith(
          contacts: const [
            LeadContact(isPrimary: true, isInviteRecipient: true),
          ],
        );
      }
      final merged = _mergeProducts(draft);
      state = state.copyWith(
        loading: false,
        draft: merged,
        baseFingerprint: merged.fingerprint,
        leadNumber: d.leadNumber,
        status: d.status,
        decisionNote: d.status == LeadStatus.infoRequested
            ? d.decisionNote
            : null,
        dup: d.existsElsewhere
            ? const LeadDuplicateCheck(existsElsewhere: true)
            : null,
      );
      await _checkResume();
      await loadDocs();
    } catch (e) {
      state = state.copyWith(loading: false, loadError: AppFailure.from(e));
    }
  }

  LeadDraft _mergeProducts(LeadDraft draft) {
    final o = state.options;
    if (o == null) return draft;
    final existing = {for (final p in draft.products) p.productId: p};
    final products = <LeadProductNeed>[
      for (final p in o.products)
        if (int.tryParse(p.value) case final pid?)
          existing[pid] ?? LeadProductNeed(productId: pid, productName: p.text),
    ];
    for (final p in draft.products) {
      if (!products.any((x) => x.productId == p.productId)) products.add(p);
    }
    return draft.copyWith(products: products);
  }

  Future<void> _openQueued(String opId) async {
    final op = await ref.read(outboxStoreProvider).get(opId);
    if (op == null || op.type != FieldOps.leadSaveDraft) {
      state = state.copyWith(
        loading: false,
        loadError: const NotFoundFailure(
          message: 'Bu ön kayıt artık bekleyen işlemlerde değil.',
        ),
      );
      return;
    }
    final item = FieldQueuedItem(op, chain: [op]);
    final draft = _mergeProducts(
      LeadDraft.fromJson(item.leadBody).copyWith(id: item.leadId ?? 0),
    );
    state = state.copyWith(
      loading: false,
      draft: draft,
      baseFingerprint: draft.fingerprint,
      queuedOpId: opId,
    );
  }

  String? get _autosaveKey {
    final uid = ref.read(currentUserIdProvider);
    return uid == null ? null : CacheKeys.user(uid, arg.storageKey);
  }

  Future<void> _checkResume() async {
    final key = _autosaveKey;
    if (key == null) return;
    final entry = await ref.read(cacheStoreProvider).read(key);
    if (entry == null) return;
    if (entry.age > _resumeLifetime) {
      await ref.read(cacheStoreProvider).remove(key);
      return;
    }
    try {
      final raw = JsonReader.asMap(entry.value);
      final draft = LeadDraft.fromJson(raw['draft']);
      if (draft.fingerprint == state.draft.fingerprint || !draft.canSaveDraft) {
        return;
      }
      _createKey = raw['createKey'] as String?;
      _createKeyFingerprint = raw['createKeyFor'] as String?;
      state = state.copyWith(
        resumeCandidate: draft,
        resumeSavedAt: entry.storedAt,
      );
    } catch (_) {
      await ref.read(cacheStoreProvider).remove(key);
    }
  }

  void resume() {
    final d = state.resumeCandidate;
    if (d == null) return;
    state = state.copyWith(
      draft: _mergeProducts(d),
      resumeCandidate: null,
      resumeSavedAt: null,
    );
    if (d.taxNumber.isNotEmpty) checkTaxNumber(d.taxNumber);
  }

  Future<void> discardResume() async {
    state = state.copyWith(resumeCandidate: null, resumeSavedAt: null);
    _createKey = null;
    final key = _autosaveKey;
    if (key != null) await ref.read(cacheStoreProvider).remove(key);
  }

  // ─────────────────────────────────────────────────────────── Düzenleme

  void update(
    LeadDraft Function(LeadDraft d) change, {
    Set<String> clears = const {},
  }) {
    final errors = Map<String, String>.of(state.errors)
      ..removeWhere((k, _) => clears.contains(k));
    state = state.copyWith(
      draft: change(state.draft),
      errors: errors,
      banner: null,
    );
    _autosaveDebounce(() => unawaited(_autosave()));
  }

  void setProductLiters(
    int productId, {
    double? monthly,
    double? committed,
    bool setMonthly = false,
    bool setCommitted = false,
  }) {
    update(
      (d) => d.copyWith(
        products: [
          for (final p in d.products)
            p.productId == productId
                ? LeadProductNeed(
                    productId: p.productId,
                    productName: p.productName,
                    monthlyLiters: setMonthly
                        ? (monthly ?? 0)
                        : p.monthlyLiters,
                    committedMonthlyLiters: setCommitted
                        ? committed
                        : p.committedMonthlyLiters,
                  )
                : p,
        ],
      ),
      clears: {'product:$productId'},
    );
  }

  void updateContact(int index, LeadContact Function(LeadContact c) change) {
    update(
      (d) => d.copyWith(
        contacts: [
          for (var i = 0; i < d.contacts.length; i++)
            i == index ? change(d.contacts[i]) : d.contacts[i],
        ],
      ),
      clears: {'contact:$index'},
    );
  }

  void addContact() {
    if (state.draft.contacts.length >= LeadRules.maxContacts) return;
    update(
      (d) => d.copyWith(
        contacts: [
          ...d.contacts,
          LeadContact(
            isPrimary: d.contacts.isEmpty,
            isInviteRecipient: d.contacts.isEmpty,
          ),
        ],
      ),
    );
  }

  void removeContact(int index) {
    update((d) {
      final list = [...d.contacts]..removeAt(index);
      if (list.isNotEmpty && !list.any((c) => c.isInviteRecipient)) {
        list[0] = list[0].copyWith(isInviteRecipient: true);
      }
      if (list.isNotEmpty && !list.any((c) => c.isPrimary)) {
        list[0] = list[0].copyWith(isPrimary: true);
      }
      return d.copyWith(contacts: list);
    });
  }

  void setInviteRecipient(int index) {
    update(
      (d) => d.copyWith(
        contacts: [
          for (var i = 0; i < d.contacts.length; i++)
            d.contacts[i].copyWith(isInviteRecipient: i == index),
        ],
      ),
    );
  }

  /// "Firma adresiyle aynı".
  void copyCompanyAddressToDelivery() {
    update(
      (d) => d.copyWith(
        deliveryPointCity: d.city,
        deliveryPointDistrict: d.district,
        deliveryPointAddress: d.address,
        deliveryPointName: (d.deliveryPointName ?? '').isEmpty
            ? 'Merkez'
            : d.deliveryPointName,
      ),
    );
  }

  void setVisitLocation(FieldLocationFix fix) {
    double round(double v, int digits) {
      final f = pow(10, digits).toDouble();
      return (v * f).roundToDouble() / f;
    }

    update(
      (d) => d.copyWith(
        visitLatitude: round(fix.latitude, 6),
        visitLongitude: round(fix.longitude, 6),
        visitAccuracyMeters: round(
          fix.accuracyMeters.clamp(0, 1000000).toDouble(),
          2,
        ),
      ),
    );
  }

  void clearVisitLocation() => update(
    (d) => d.copyWith(
      visitLatitude: null,
      visitLongitude: null,
      visitAccuracyMeters: null,
    ),
  );

  // ─────────────────────────────────────────────────────────── VKN kontrolü

  /// Canlı VKN / TCKN kontrolü: biçim hemen, tekrar kaydı 500 ms sonra sunucudan.
  void checkTaxNumber(String raw) {
    final digits = Validators.digitsOnly(raw);
    final format = digits.isEmpty ? null : Validators.taxNumber(digits);
    _dupDebounce.cancel();
    final epoch = ++_dupEpoch;
    if (digits.isEmpty) {
      state = state.copyWith(dup: null, dupChecking: false);
      return;
    }
    if (format != null) {
      state = state.copyWith(
        dup: LeadDuplicateCheck(
          formatError: digits.length < 10 ? null : format,
        ),
        dupChecking: false,
      );
      return;
    }
    state = state.copyWith(dupChecking: true);
    _dupDebounce(() async {
      try {
        final r = await _repo.checkDuplicate(digits, excludeId: state.draft.id);
        if (epoch != _dupEpoch) return;
        state = state.copyWith(dup: r, dupChecking: false);
      } catch (_) {
        if (epoch != _dupEpoch) return;
        // Kontrol yapılamadı: gönderimde sunucu yeniden denetler.
        state = state.copyWith(dupChecking: false);
      }
    });
  }

  // ─────────────────────────────────────────────────────────── Adımlar

  /// Biçim hataları (engelleyici); zorunlu alan eksikleri gönderimde listelenir.
  Map<String, String> validateStep(LeadWizardStep step) {
    final d = state.draft;
    final errors = <String, String>{};
    switch (step) {
      case LeadWizardStep.company:
        final digits = Validators.digitsOnly(d.taxNumber);
        if (digits.isNotEmpty) {
          final e = Validators.taxNumber(digits);
          if (e != null) errors['taxNumber'] = e;
        }
        if ((d.email ?? '').isNotEmpty && !LeadRules.isEmail(d.email)) {
          errors['email'] = 'Geçerli bir e-posta adresi girin.';
        }
        final y = d.foundedYear;
        if (y != null && (y < 1800 || y > TrTime.wall(TrTime.now()).year)) {
          errors['foundedYear'] =
              'Faaliyet yılı 1800–${TrTime.wall(TrTime.now()).year} arasında olmalı.';
        }
      case LeadWizardStep.fleet:
        if ((d.vehicleCount ?? 0) < 0) {
          errors['vehicleCount'] = 'Araç sayısı negatif olamaz.';
        }
      case LeadWizardStep.needs:
        for (final p in d.products) {
          final c = p.committedMonthlyLiters;
          if (c != null && c > p.monthlyLiters) {
            errors['product:${p.productId}'] =
                'Taahhüt edilen litre aylık ihtiyaçtan büyük olamaz.';
          }
        }
        if ((d.contractMonths ?? 0) > 240) {
          errors['contractMonths'] = 'Sözleşme süresi en çok 240 ay olabilir.';
        }
      case LeadWizardStep.payment:
        final t = d.requestedTermDays;
        if (t != null && (t < 0 || t > 365)) {
          errors['requestedTermDays'] = 'Vade 0–365 gün arasında olmalı.';
        }
        final r = d.collateralRatioPercent;
        if (r != null && (r < 0 || r > 500)) {
          errors['collateralRatioPercent'] =
              'Teminat oranı %0–%500 arasında olmalı.';
        }
      case LeadWizardStep.visit:
        break;
      case LeadWizardStep.contacts:
        for (var i = 0; i < d.contacts.length; i++) {
          final c = d.contacts[i];
          if (c.isEmpty) continue;
          if ((c.email ?? '').isNotEmpty && !LeadRules.isEmail(c.email)) {
            errors['contact:$i'] =
                'Yetkili ${i + 1}: geçerli bir e-posta girin.';
          }
        }
      case LeadWizardStep.delivery:
      case LeadWizardStep.kvkk:
      case LeadWizardStep.documents:
        break;
    }
    return errors;
  }

  bool next() {
    final errors = validateStep(state.step);
    if (errors.isNotEmpty) {
      state = state.copyWith(errors: {...state.errors, ...errors});
      return false;
    }
    if (state.step.index < LeadWizardStep.values.length - 1) {
      state = state.copyWith(step: LeadWizardStep.values[state.step.index + 1]);
      if (state.step == LeadWizardStep.documents) {
        unawaited(_prepareDocuments());
      }
    }
    return true;
  }

  void back() {
    if (state.step.index == 0) return;
    state = state.copyWith(step: LeadWizardStep.values[state.step.index - 1]);
  }

  void goTo(LeadWizardStep step) {
    state = state.copyWith(step: step);
    if (step == LeadWizardStep.documents) unawaited(_prepareDocuments());
  }

  /// Eksik maddenin bulunduğu adım.
  static LeadWizardStep stepOfMissing(String item) {
    if (item.startsWith('Firma') ||
        item.startsWith('VKN') ||
        item.startsWith('TCKN') ||
        item.startsWith('Vergi dairesi') ||
        item == 'İl' ||
        item == 'İlçe') {
      return LeadWizardStep.company;
    }
    if (item.contains('yetkili') || item.startsWith('Yetkili')) {
      return LeadWizardStep.contacts;
    }
    if (item.contains('aylık litre')) return LeadWizardStep.needs;
    if (item.startsWith('KVKK')) return LeadWizardStep.kvkk;
    if (item.startsWith('Vergi levhası')) return LeadWizardStep.documents;
    return LeadWizardStep.company;
  }

  // ─────────────────────────────────────────────────────────── Belgeler

  Future<void> loadDocs() async {
    final id = state.draft.id;
    if (id <= 0) return;
    state = state.copyWith(docsLoading: true);
    try {
      final list = await ref
          .read(attachmentApiProvider)
          .list(AttachmentOwnerType.customerLead, id);
      state = state.copyWith(serverDocs: list, docsLoading: false);
    } catch (_) {
      state = state.copyWith(docsLoading: false);
    }
  }

  /// Belgeler adımına gelince: çevrimiçiyse taslak kaydedilir (yüklemeler hemen gitsin; web ile aynı).
  Future<void> _prepareDocuments() async {
    if (state.draft.id > 0) {
      if (state.serverDocs.isEmpty) await loadDocs();
      return;
    }
    if (!state.draft.canSaveDraft || state.queuedOpId != null) return;
    if (!ref.read(isOnlineProvider)) return;
    await _saveDirect(showOutcome: false);
  }

  /// Belge ekler: kalıcı klasöre kopyalanır; ön kayıt sunucudaysa hemen yüklenir, değilse kayıtla birlikte.
  Future<void> addDocument(LeadDocInput input) async {
    final path = await ref.read(fieldFileStoreProvider).persist(input.path);
    final doc = LeadLocalDoc(
      localId: 'd${_docSeq++}${DateTime.now().microsecondsSinceEpoch}',
      input: LeadDocInput(
        kind: input.kind,
        path: path,
        fileName: input.fileName,
        contentType: input.contentType,
        sizeBytes: input.sizeBytes,
      ),
    );
    state = state.copyWith(localDocs: [...state.localDocs, doc], banner: null);
    if (state.draft.id > 0 && ref.read(isOnlineProvider)) {
      await _uploadNow(doc.localId);
    }
  }

  Future<void> retryDocument(String localId) => _uploadNow(localId);

  Future<bool> _uploadNow(String localId) async {
    final doc = state.localDocs.where((d) => d.localId == localId).firstOrNull;
    final id = state.draft.id;
    if (doc == null || id <= 0) return false;
    _setDoc(
      localId,
      (d) => d.copyWith(state: LeadDocState.uploading, progress: 0),
    );
    try {
      final result = await ref
          .read(attachmentApiProvider)
          .upload(
            ownerType: AttachmentOwnerType.customerLead,
            ownerId: id,
            kind: doc.input.kind,
            filePath: doc.input.path,
            fileName: doc.input.fileName,
            contentType: doc.input.contentType,
            idempotencyKey: _docKey(localId),
            onProgress: (p) => _setDoc(
              localId,
              (d) => d.copyWith(state: LeadDocState.uploading, progress: p),
            ),
          );
      await ref.read(fieldFileStoreProvider).delete(doc.input.path);
      state = state.copyWith(
        serverDocs: [...state.serverDocs, result.attachment],
        localDocs: [
          for (final d in state.localDocs)
            if (d.localId != localId) d,
        ],
      );
      return true;
    } on AppFailure catch (f) {
      if (f is OfflineFailure || f.isUncertain) {
        await _queueDoc(localId, leadId: id);
        return false;
      }
      _setDoc(
        localId,
        (d) => d.copyWith(state: LeadDocState.failed, error: f.message),
      );
      return false;
    }
  }

  final Map<String, String> _docKeys = {};
  String _docKey(String localId) =>
      _docKeys.putIfAbsent(localId, newIdempotencyKey);

  Future<void> _queueDoc(
    String localId, {
    int? leadId,
    String? dependsOn,
  }) async {
    final doc = state.localDocs.where((d) => d.localId == localId).firstOrNull;
    if (doc == null || doc.state == LeadDocState.queued) return;
    final op = await ref
        .read(fieldOutboxProvider)
        .queueLeadUpload(
          kind: doc.input.kind,
          filePath: doc.input.path,
          fileName: doc.input.fileName,
          contentType: doc.input.contentType,
          leadId: leadId,
          dependsOn: dependsOn,
          companyTitle: state.draft.companyTitle,
        );
    _setDoc(
      localId,
      (d) => d.copyWith(state: LeadDocState.queued, opId: op.id),
    );
  }

  void _setDoc(String localId, LeadLocalDoc Function(LeadLocalDoc d) change) {
    state = state.copyWith(
      localDocs: [
        for (final d in state.localDocs) d.localId == localId ? change(d) : d,
      ],
    );
  }

  /// Sunucudaki belgeyi siler (yükleyen) ya da cihazdakini kaldırır.
  Future<void> removeServerDocument(Attachment a) async {
    try {
      await ref.read(attachmentApiProvider).delete(a.publicId);
      state = state.copyWith(
        serverDocs: [
          for (final d in state.serverDocs)
            if (d.publicId != a.publicId) d,
        ],
      );
    } on AppFailure catch (f) {
      state = state.copyWith(banner: f.message);
    }
  }

  Future<void> removeLocalDocument(String localId) async {
    final doc = state.localDocs.where((d) => d.localId == localId).firstOrNull;
    if (doc == null) return;
    final opId = doc.opId;
    if (opId != null) {
      await ref.read(fieldOutboxProvider).discardChain(opId);
    } else {
      await ref.read(fieldFileStoreProvider).delete(doc.input.path);
    }
    state = state.copyWith(
      localDocs: [
        for (final d in state.localDocs)
          if (d.localId != localId) d,
      ],
    );
  }

  // ─────────────────────────────────────────────────────────── Cihaza yazma

  Future<void> _autosave() async {
    final key = _autosaveKey;
    if (key == null || state.outcome != null || !state.dirty) return;
    if (!state.draft.canSaveDraft) return;
    await ref
        .read(cacheStoreProvider)
        .write(
          key,
          {
            'draft': state.draft.toJson(),
            'createKey': _createKey,
            'createKeyFor': _createKeyFingerprint,
          },
          ttl: _resumeLifetime,
          userId: ref.read(currentUserIdProvider),
        );
  }

  Future<void> _clearAutosave() async {
    _autosaveDebounce.cancel();
    final key = _autosaveKey;
    if (key != null) await ref.read(cacheStoreProvider).remove(key);
  }

  // ─────────────────────────────────────────────────────────── Kaydet

  String _keyFor(JsonMap body) {
    final fp = body.toString();
    if (_createKey == null || _createKeyFingerprint != fp) {
      _createKey = newIdempotencyKey();
      _createKeyFingerprint = fp;
    }
    return _createKey!;
  }

  /// Taslağı kaydet (çevrimdışı güvenli).
  Future<void> saveDraft() async {
    if (state.busy) return;
    if (!state.draft.canSaveDraft) {
      state = state.copyWith(
        step: LeadWizardStep.company,
        errors: {
          ...state.errors,
          'companyTitle':
              'Taslağı kaydetmek için en az firma ünvanı ya da VKN / TCKN girin.',
        },
      );
      return;
    }
    final formatErrors = <String, String>{
      for (final s in LeadWizardStep.values) ...validateStep(s),
    };
    if (formatErrors.isNotEmpty) {
      final first = LeadWizardStep.values.firstWhere(
        (s) => validateStep(s).isNotEmpty,
      );
      state = state.copyWith(errors: formatErrors, step: first);
      return;
    }
    if (state.queuedOpId != null || !ref.read(isOnlineProvider)) {
      await _queueSave();
      return;
    }
    await _saveDirect(showOutcome: true);
  }

  /// Doğrudan kayıt. [showOutcome] false: belgeler adımından önceki sessiz kayıt.
  Future<LeadSaveResult?> _saveDirect({required bool showOutcome}) async {
    final body = state.draft.toSaveJson();
    final isNew = state.draft.isNew;
    final key = isNew ? _keyFor(body) : null;
    state = state.copyWith(
      busy: true,
      busyLabel: 'Kaydediliyor',
      banner: null,
      conflict: false,
    );
    try {
      final result = isNew
          ? await _repo.createLead(body, idempotencyKey: key!)
          : await _repo.updateLead(state.draft.id, body);
      _createKey = null;
      final draft = state.draft.copyWith(
        id: result.id,
        concurrencyToken: result.concurrencyToken,
      );
      state = state.copyWith(
        busy: false,
        busyLabel: null,
        draft: draft,
        baseFingerprint: draft.fingerprint,
        leadNumber: result.leadNumber,
        status: result.status,
        banner: result.warnings.isEmpty ? null : result.warnings.join(' '),
      );
      // Cihazda bekleyen belgeler şimdi yüklenir.
      for (final d in [...state.localDocs]) {
        if (d.state == LeadDocState.pending || d.state == LeadDocState.failed) {
          await _uploadNow(d.localId);
        }
      }
      ref.read(fieldSyncTickProvider.notifier).bump();
      if (showOutcome) {
        await _clearAutosave();
        state = state.copyWith(outcome: LeadSaved(result));
      }
      return result;
    } on AppFailure catch (f) {
      state = state.copyWith(busy: false, busyLabel: null);
      if (f is OfflineFailure || f.isUncertain) {
        if (showOutcome) await _queueSave(key: key);
        return null;
      }
      _showFailure(f);
      return null;
    }
  }

  Future<void> _queueSave({String? key, bool submitRequested = false}) async {
    final outbox = ref.read(fieldOutboxProvider);
    final body = state.draft.toSaveJson();
    var previous = state.queuedOpId;
    if (previous != null) {
      final prev = await ref.read(outboxStoreProvider).get(previous);
      if (prev == null) {
        previous = null;
      } else if (prev.status == OutboxStatus.needsAttention) {
        await outbox.discardChain(previous);
        previous = null;
      }
    }
    final op = await outbox.queueLeadSave(
      body: body,
      idempotencyKey: previous != null
          ? newIdempotencyKey()
          : (key ?? (state.draft.isNew ? _keyFor(body) : newIdempotencyKey())),
      leadId: state.draft.isNew ? null : state.draft.id,
      chainAfter: previous,
      leadNumber: state.leadNumber,
      companyTitle: state.draft.companyTitle,
    );
    // Cihazdaki belgeler kayda bağlı olarak sıraya girer.
    final head = previous ?? op.id;
    for (final d in [...state.localDocs]) {
      if (d.state != LeadDocState.queued && d.state != LeadDocState.uploading) {
        await _queueDoc(
          d.localId,
          leadId: state.draft.isNew ? null : state.draft.id,
          dependsOn: state.draft.isNew ? head : null,
        );
      }
    }
    _createKey = null;
    await _clearAutosave();
    state = state.copyWith(
      baseFingerprint: state.draft.fingerprint,
      outcome: LeadQueued(op.id, submitRequested: submitRequested),
    );
  }

  void _showFailure(AppFailure f) {
    if (f is ValidationFailure) {
      final mapped = <String, String>{};
      f.fieldErrors.forEach((k, v) {
        if (v.isEmpty || k.isEmpty) return;
        mapped[k[0].asciiLower + k.substring(1)] = v.first;
      });
      state = state.copyWith(
        errors: {...state.errors, ...mapped},
        banner: f.message,
      );
      return;
    }
    final concurrency =
        (f is ConflictFailure && f.isConcurrency) ||
        f.message.contains('başka bir oturumda');
    state = state.copyWith(conflict: concurrency, banner: f.message);
  }

  /// Çakışma sonrası "Yenile": güncel belirteç alınır, girilenler korunur.
  Future<void> reloadAfterConflict() async {
    final id = state.draft.id;
    if (id <= 0) {
      state = state.copyWith(conflict: false, banner: null);
      return;
    }
    try {
      final d = await _repo.lead(id);
      state = state.copyWith(
        conflict: false,
        banner: d.status.isEditable
            ? null
            : 'Ön kayıt artık düzenlenemez (${d.displayStatus}).',
        draft: state.draft.copyWith(concurrencyToken: d.draft.concurrencyToken),
        status: d.status,
        baseFingerprint: d.draft.fingerprint,
      );
    } on AppFailure catch (f) {
      state = state.copyWith(banner: f.message);
    }
  }

  // ─────────────────────────────────────────────────────────── Finansa gönder

  /// Finansa gönder (bağlantı gerekir). Eksik varsa hiçbir istek atılmaz; eksikler listelenir.
  Future<void> submit() async {
    if (state.busy) return;
    final missing = state.missingNow;
    if (state.dup?.blocksSubmit ?? false) {
      final dup = state.dup!;
      missing.insert(
        0,
        dup.openLeadNumber != null
            ? 'Açık ön kayıt var: ${dup.openLeadNumber}'
            : 'Bu VKN ile cari bayinizde kayıtlı (${dup.existingCustomerCode ?? '—'})',
      );
    }
    if (missing.isNotEmpty) {
      state = state.copyWith(
        missing: missing,
        banner: 'Finansa göndermek için eksik: ${missing.join(', ')}.',
      );
      return;
    }
    if (!ref.read(isOnlineProvider)) {
      state = state.copyWith(
        missing: const [],
        banner:
            'Finansa göndermek için bağlantı gerekir. Taslağı kaydedin; bağlantı gelince gönderin.',
      );
      return;
    }
    state = state.copyWith(missing: const []);
    if (state.draft.isNew || state.dirty) {
      final saved = await _saveDirect(showOutcome: false);
      if (saved == null) return;
    }
    // Belgeler sunucuda olmalı (vergi levhası şartı).
    for (final d in [...state.localDocs]) {
      if (d.state == LeadDocState.queued) continue;
      final ok = await _uploadNow(d.localId);
      if (!ok) {
        state = state.copyWith(
          banner:
              'Belgeler yüklenemedi; bağlantınızı kontrol edip tekrar deneyin.',
        );
        return;
      }
    }
    if (!state.taxPlateUploaded) {
      state = state.copyWith(
        missing: const ['Vergi levhası (Evrak)'],
        banner:
            'Vergi levhası henüz yüklenmedi; yükleme bitince tekrar gönderin.',
      );
      return;
    }
    final id = state.draft.id;
    state = state.copyWith(busy: true, busyLabel: 'Gönderiliyor', banner: null);
    try {
      final message = await retryUncertain(
        () => _repo.submitLead(
          id,
          concurrencyToken: state.draft.concurrencyToken,
        ),
        onRetry: (_) =>
            state = state.copyWith(busyLabel: 'Gönderim kontrol ediliyor…'),
        reconcile: () async {
          final d = await _repo.lead(id);
          return d.status.isEditable
              ? null
              : 'Ön kayıt finans onayına gönderildi.';
        },
      );
      await _clearAutosave();
      ref.read(fieldSyncTickProvider.notifier).bump();
      state = state.copyWith(
        busy: false,
        busyLabel: null,
        outcome: LeadSubmitted(
          leadId: id,
          leadNumber: state.leadNumber ?? '',
          message: message.isEmpty
              ? 'Ön kayıt finans onayına gönderildi.'
              : message,
        ),
      );
    } on AppFailure catch (f) {
      state = state.copyWith(busy: false, busyLabel: null);
      _showFailure(f);
    }
  }

  void clearOutcome() => state = state.copyWith(outcome: null);
}
