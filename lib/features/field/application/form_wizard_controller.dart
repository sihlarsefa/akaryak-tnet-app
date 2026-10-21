import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/idempotency.dart';
import '../../../core/offline/cache_store.dart';
import '../../../core/offline/connectivity.dart';
import '../../../core/offline/outbox_op.dart';
import '../../../core/offline/outbox_store.dart';
import '../../../core/utils/debouncer.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../data/field_draft.dart';
import '../data/field_models.dart';
import '../data/field_outbox.dart';
import '../data/field_repository.dart';
import 'field_access.dart';
import 'field_lists.dart';
import 'uncertain.dart';

/// Sihirbaz adımları (spec A.3 F2: cari → tedarik → ödeme ve vade → satırlar → özet).
enum FieldWizardStep {
  customer('Cari'),
  supply('Tedarik'),
  payment('Ödeme'),
  lines('Satırlar'),
  summary('Özet');

  const FieldWizardStep(this.title);
  final String title;
}

/// Kaydet / gönder sonucu (sonuç ekranı).
sealed class FieldWizardOutcome {
  const FieldWizardOutcome();
}

/// Taslak sunucuya kaydedildi.
class FieldDraftSaved extends FieldWizardOutcome {
  const FieldDraftSaved(this.form);
  final FieldForm form;
}

/// Taslak bekleyen işlemlere alındı (çevrimdışı ya da belirsiz yanıt): "Kaydedildi — bağlantı gelince
/// gönderilecek".
class FieldDraftQueued extends FieldWizardOutcome {
  const FieldDraftQueued(this.opId, {this.submitRequested = false});
  final String opId;

  /// Kullanıcı "Onaya gönder" demişti; gönderim bağlantı gelince elle yapılır.
  final bool submitRequested;
}

/// Form onaya gönderildi.
class FieldFormSubmitted extends FieldWizardOutcome {
  const FieldFormSubmitted(this.result);
  final FieldSubmitResult result;
}

/// Sihirbazın açılış bilgisi.
@immutable
class FormWizardArgs {
  const FormWizardArgs({
    this.formId,
    this.customerId,
    this.customerTitle,
    this.queuedOpId,
  });

  /// Kayıtlı taslağı düzenle.
  final int? formId;

  /// Portföyden "Saha formu oluştur".
  final int? customerId;
  final String? customerTitle;

  /// Kuyruktaki (gönderilmemiş) taslağı düzenle.
  final String? queuedOpId;

  String get storageKey => formId != null
      ? 'field.wizard.form.$formId'
      : queuedOpId != null
      ? 'field.wizard.op.$queuedOpId'
      : 'field.wizard.form.new';

  @override
  bool operator ==(Object other) =>
      other is FormWizardArgs &&
      other.formId == formId &&
      other.customerId == customerId &&
      other.queuedOpId == queuedOpId;

  @override
  int get hashCode => Object.hash(formId, customerId, queuedOpId);
}

@immutable
class FormWizardState {
  const FormWizardState({
    this.draft = const FieldFormDraft(),
    this.step = FieldWizardStep.customer,
    this.loading = false,
    this.loadError,
    this.options,
    this.optionsLoading = false,
    this.optionsError,
    this.supply = const [],
    this.preview,
    this.previewLoading = false,
    this.previewError,
    this.previewKeys = const [],
    this.busy = false,
    this.busyLabel,
    this.banner,
    this.conflict = false,
    this.errors = const {},
    this.baseFingerprint = '',
    this.outcome,
    this.resumeCandidate,
    this.resumeSavedAt,
    this.queuedOpId,
  });

  final FieldFormDraft draft;
  final FieldWizardStep step;

  /// Kayıtlı ya da kuyruktaki taslak açılıyor.
  final bool loading;
  final AppFailure? loadError;
  final FieldOptions? options;
  final bool optionsLoading;
  final AppFailure? optionsError;
  final List<FieldSupplyOption> supply;
  final FieldPreview? preview;
  final bool previewLoading;
  final AppFailure? previewError;

  /// Önizleme satırı (sıra) → sihirbaz satır anahtarı.
  final List<String> previewKeys;
  final bool busy;
  final String? busyLabel;

  /// İş kuralı / bağlantı uyarısı (üstte bant).
  final String? banner;

  /// "Bu kayıt sizden sonra güncellendi" (girilen değerler korunur; "Yenile").
  final bool conflict;

  /// Alan hataları: başlık alanları (`shipDate`, `paymentTermDays` …) ve satırlar (`line:<anahtar>`).
  final Map<String, String> errors;
  final String baseFingerprint;
  final FieldWizardOutcome? outcome;

  /// Cihazda yarım kalan form (24 saat).
  final FieldFormDraft? resumeCandidate;
  final DateTime? resumeSavedAt;

  /// Kuyruktaki taslak düzenleniyor (yeni kayıt bu işlemden sonra gönderilir).
  final String? queuedOpId;

  bool get dirty => draft.fingerprint != baseFingerprint;
  bool get hasCustomer => (draft.customerId ?? 0) > 0;
  bool get showCosts => options?.showCosts ?? false;

  /// Önizlemedeki satır (sihirbaz satır anahtarıyla).
  FieldPreviewLine? previewLine(String key) {
    final p = preview;
    if (p == null) return null;
    final index = previewKeys.indexOf(key);
    return index < 0 ? null : p.line(index);
  }

  static const _unset = Object();

  FormWizardState copyWith({
    FieldFormDraft? draft,
    FieldWizardStep? step,
    bool? loading,
    Object? loadError = _unset,
    Object? options = _unset,
    bool? optionsLoading,
    Object? optionsError = _unset,
    List<FieldSupplyOption>? supply,
    Object? preview = _unset,
    bool? previewLoading,
    Object? previewError = _unset,
    List<String>? previewKeys,
    bool? busy,
    Object? busyLabel = _unset,
    Object? banner = _unset,
    bool? conflict,
    Map<String, String>? errors,
    String? baseFingerprint,
    Object? outcome = _unset,
    Object? resumeCandidate = _unset,
    Object? resumeSavedAt = _unset,
    Object? queuedOpId = _unset,
  }) {
    T pick<T>(Object? v, T current) => identical(v, _unset) ? current : v as T;
    return FormWizardState(
      draft: draft ?? this.draft,
      step: step ?? this.step,
      loading: loading ?? this.loading,
      loadError: pick<AppFailure?>(loadError, this.loadError),
      options: pick<FieldOptions?>(options, this.options),
      optionsLoading: optionsLoading ?? this.optionsLoading,
      optionsError: pick<AppFailure?>(optionsError, this.optionsError),
      supply: supply ?? this.supply,
      preview: pick<FieldPreview?>(preview, this.preview),
      previewLoading: previewLoading ?? this.previewLoading,
      previewError: pick<AppFailure?>(previewError, this.previewError),
      previewKeys: previewKeys ?? this.previewKeys,
      busy: busy ?? this.busy,
      busyLabel: pick<String?>(busyLabel, this.busyLabel),
      banner: pick<String?>(banner, this.banner),
      conflict: conflict ?? this.conflict,
      errors: errors ?? this.errors,
      baseFingerprint: baseFingerprint ?? this.baseFingerprint,
      outcome: pick<FieldWizardOutcome?>(outcome, this.outcome),
      resumeCandidate: pick<FieldFormDraft?>(
        resumeCandidate,
        this.resumeCandidate,
      ),
      resumeSavedAt: pick<DateTime?>(resumeSavedAt, this.resumeSavedAt),
      queuedOpId: pick<String?>(queuedOpId, this.queuedOpId),
    );
  }
}

final formWizardProvider = NotifierProvider.autoDispose
    .family<FormWizardController, FormWizardState, FormWizardArgs>(
      FormWizardController.new,
    );

/// Saha formu v2 sihirbazı (spec A.3 F2–F3, C.4a).
///
/// - Canlı önizleme son düzenlemeden 600 ms sonra çalışır; eski yanıtlar yok sayılır.
/// - "Taslak kaydet" çevrimdışı güvenlidir: bağlantı yoksa ya da yanıt belirsizse istek aynı
///   Idempotency-Key ile bekleyen işlemlere alınır.
/// - "Onaya gönder" bağlantı ister; gönderim aynı anahtarla yinelenir, belirsizlikte form yeniden okunur.
class FormWizardController
    extends AutoDisposeFamilyNotifier<FormWizardState, FormWizardArgs> {
  /// Önizleme bekleme süresi (spec A.3 F2).
  static const previewDelay = Duration(milliseconds: 600);
  static const _autosaveDelay = Duration(milliseconds: 800);
  static const _resumeLifetime = Duration(hours: 24);

  late final Debouncer _previewDebounce = Debouncer(previewDelay);
  late final Debouncer _autosaveDebounce = Debouncer(_autosaveDelay);
  CancelToken? _previewCancel;
  int _previewEpoch = 0;

  /// Yeni form için Idempotency-Key (bir niyet = bir anahtar; içerik değişince yenilenir).
  String? _createKey;
  String? _createKeyFingerprint;
  String? _submitKey;

  FieldRepository get _repo => ref.read(fieldRepositoryProvider);

  @override
  FormWizardState build(FormWizardArgs arg) {
    ref.onDispose(() {
      _previewDebounce.dispose();
      _autosaveDebounce.dispose();
      _previewCancel?.cancel();
    });
    final editing = arg.formId != null || arg.queuedOpId != null;
    Future.microtask(_init);
    return FormWizardState(
      loading: editing,
      draft: FieldFormDraft(stationId: ref.read(fieldAccessProvider).stationId),
      baseFingerprint: FieldFormDraft(
        stationId: ref.read(fieldAccessProvider).stationId,
      ).fingerprint,
    );
  }

  // ─────────────────────────────────────────────────────────── Açılış

  Future<void> _init() async {
    final opId = arg.queuedOpId;
    if (opId != null) {
      await _openQueued(opId);
      return;
    }
    final formId = arg.formId;
    if (formId != null) {
      await _openExisting(formId);
      return;
    }
    await _checkResume();
    final cid = arg.customerId;
    if (cid != null && cid > 0) {
      await selectCustomer(cid, arg.customerTitle ?? '');
    }
  }

  Future<void> _openExisting(int formId) async {
    state = state.copyWith(loading: true, loadError: null);
    try {
      final detail = await _repo.form(formId);
      final draft = FieldFormDraft.fromForm(detail.form);
      state = state.copyWith(
        loading: false,
        draft: draft,
        baseFingerprint: draft.fingerprint,
        step: FieldWizardStep.lines,
      );
      await _checkResume();
      await loadOptions();
    } catch (e) {
      state = state.copyWith(loading: false, loadError: AppFailure.from(e));
    }
  }

  Future<void> _openQueued(String opId) async {
    final op = await ref.read(outboxStoreProvider).get(opId);
    if (op == null || op.type != FieldOps.saveDraft) {
      state = state.copyWith(
        loading: false,
        loadError: const NotFoundFailure(
          message: 'Bu taslak artık bekleyen işlemlerde değil.',
        ),
      );
      return;
    }
    final item = FieldQueuedItem(op, chain: [op]);
    final draft = FieldFormDraft.fromJson(
      _requestToDraftJson(item.formRequest ?? const {}, item.formId),
    ).copyWith(customerTitle: item.customerTitle);
    state = state.copyWith(
      loading: false,
      draft: draft,
      baseFingerprint: draft.fingerprint,
      queuedOpId: opId,
      step: FieldWizardStep.lines,
    );
    await loadOptions();
  }

  /// Kuyruktaki istek gövdesi → sihirbaz taslağı.
  static JsonMap _requestToDraftJson(JsonMap request, int? formId) {
    final r = JsonReader(request);
    return {
      ...request,
      'formId': formId,
      'lines': [
        for (final l in r.list('lines', (x) => x))
          {
            'key': FieldLineDraft.newKey(),
            'productId': l.intOrNull('productId'),
            'deliveryPointId': l.intOrNull('deliveryPointId'),
            'liters': l.decOrNull('quantityLiters'),
            'date': l.strOrNull('requestedDeliveryDate'),
            'unitPrice': l.decOrNull('proposedUnitPrice'),
            'priceEdited': true,
            'tuprasM3': l.decOrNull('tuprasPriceM3'),
            'tuprasEdited': l.decOrNull('tuprasPriceM3') != null,
            'pumpPrice': l.decOrNull('pumpPricePerLiter'),
            'pumpEdited': l.decOrNull('pumpPricePerLiter') != null,
            'bindirimM3': l.decOrNull('bindirimM3'),
            'priceEntryMode': l.integer('priceEntryMode'),
            'profitPercent': l.decOrNull('profitPercent'),
          },
      ],
    };
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
      final draft = FieldFormDraft.fromJson(raw['draft']);
      if (draft.fingerprint == state.draft.fingerprint) return;
      if ((draft.customerId ?? 0) <= 0 && draft.lines.isEmpty) return;
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

  /// "Yarım kalan formunuza devam edin".
  Future<void> resume() async {
    final d = state.resumeCandidate;
    if (d == null) return;
    state = state.copyWith(
      draft: d,
      resumeCandidate: null,
      resumeSavedAt: null,
      step: (d.customerId ?? 0) > 0
          ? FieldWizardStep.lines
          : FieldWizardStep.customer,
    );
    if ((d.customerId ?? 0) > 0) await loadOptions(applyDefaults: false);
  }

  /// Yarım kalanı sil, baştan başla.
  Future<void> discardResume() async {
    state = state.copyWith(resumeCandidate: null, resumeSavedAt: null);
    _createKey = null;
    final key = _autosaveKey;
    if (key != null) await ref.read(cacheStoreProvider).remove(key);
  }

  // ─────────────────────────────────────────────────────────── Cari ve seçenekler

  Future<void> selectCustomer(int id, String title) async {
    if (state.draft.customerId == id && state.options != null) return;
    final changed = state.draft.customerId != id;
    state = state.copyWith(
      draft: state.draft.copyWith(
        customerId: id,
        customerTitle: title,
        lines: changed ? const [] : state.draft.lines,
      ),
      preview: null,
      previewKeys: const [],
      errors: const {},
      banner: null,
    );
    await loadOptions();
  }

  /// Carinin seçenekleri (ürün, nokta, limit, Tüpraş/pompa, ödeme).
  Future<void> loadOptions({bool applyDefaults = true}) async {
    final cid = state.draft.customerId;
    if (cid == null || cid <= 0) return;
    state = state.copyWith(optionsLoading: true, optionsError: null);
    try {
      final platform = ref.read(accessPolicyProvider).isPlatform;
      final o = await _repo.options(
        cid,
        stationId: platform ? state.draft.stationId : null,
      );
      if (state.draft.customerId != cid) return;
      var draft = state.draft.copyWith(
        customerTitle: o.customerTitle.isEmpty
            ? state.draft.customerTitle
            : o.customerTitle,
        stationId: state.draft.stationId ?? o.stationId,
      );
      if (applyDefaults) draft = _withDefaults(draft, o);
      final wasBase = state.baseFingerprint == state.draft.fingerprint;
      state = state.copyWith(
        options: o,
        optionsLoading: false,
        draft: draft,
        // Varsayılanların doldurulması "değişiklik" sayılmaz (kayıtlı taslak açılınca).
        baseFingerprint: wasBase && !state.draft.isNew
            ? draft.fingerprint
            : state.baseFingerprint,
      );
      unawaited(_loadSupply());
      _schedulePreview(immediate: true);
    } catch (e) {
      if (state.draft.customerId != cid) return;
      state = state.copyWith(
        optionsLoading: false,
        optionsError: AppFailure.from(e),
      );
    }
  }

  Future<void> _loadSupply() async {
    if (state.supply.isNotEmpty) return;
    try {
      final list = await _repo.supplyOptions();
      state = state.copyWith(supply: list);
    } catch (_) {
      // Öneriler olmadan da serbest metin girilir.
    }
  }

  FieldFormDraft _withDefaults(FieldFormDraft d, FieldOptions o) {
    var draft = d;
    if (draft.shipDate == null && o.defaultDate != null) {
      draft = draft.copyWith(shipDate: o.defaultDate);
    }
    if (draft.refineryLocation == null && o.location != null) {
      draft = draft.copyWith(refineryLocation: o.location);
    }
    if (draft.distributorName == null && o.distributor != null) {
      draft = draft.copyWith(distributorName: o.distributor);
    }
    if (draft.terminalName == null && o.terminal != null) {
      draft = draft.copyWith(terminalName: o.terminal);
    }
    final pay = o.payment;
    if (draft.paymentMethodCode == null &&
        pay != null &&
        pay.enabled &&
        pay.defaultMethodCode != null) {
      final m = pay.method(pay.defaultMethodCode);
      draft = draft.copyWith(
        paymentMethodCode: pay.defaultMethodCode,
        paymentTermDays: _defaultTerm(m),
      );
    }
    if (draft.lines.isEmpty) {
      draft = draft.copyWith(lines: [_newLine(draft, o)]);
    }
    return draft;
  }

  static int _defaultTerm(PaymentMethodChoice? m) {
    if (m == null) return 0;
    final t = m.defaultTermDays ?? m.minTermDays;
    return t.clamp(
      m.minTermDays,
      m.maxTermDays < m.minTermDays ? m.minTermDays : m.maxTermDays,
    );
  }

  FieldLineDraft _newLine(FieldFormDraft d, FieldOptions o) {
    final last = d.lines.isEmpty ? null : d.lines.last;
    var line = FieldLineDraft(
      key: FieldLineDraft.newKey(),
      date: last?.date ?? d.shipDate ?? o.defaultDate,
      deliveryPointId:
          last?.deliveryPointId ??
          (o.points.length == 1 ? o.points.first.id : null),
    );
    final productId = o.products.length == 1 ? o.products.first.id : null;
    if (productId != null) {
      line = _applyProduct(line, productId, d.refineryLocation, o);
    }
    return line;
  }

  FieldLineDraft _applyProduct(
    FieldLineDraft line,
    int productId,
    String? location,
    FieldOptions o,
  ) {
    final p = o.product(productId);
    var l = line.copyWith(productId: productId);
    if (p == null) return l;
    if (!l.priceEdited) l = l.copyWith(unitPrice: p.suggestedUnitPrice);
    if (!l.tuprasEdited) {
      l = l.copyWith(
        tuprasM3: location == null ? null : p.tuprasPricesM3[location],
      );
    }
    if (!l.pumpEdited) l = l.copyWith(pumpPrice: p.pumpPricePerLiter);
    final bindirim = o.costInputs?.defaultBindirimM3[productId];
    if (o.showCosts && l.bindirimM3 == null && bindirim != null) {
      l = l.copyWith(bindirimM3: bindirim);
    }
    return l;
  }

  // ─────────────────────────────────────────────────────────── Düzenleme

  void _changed(FieldFormDraft draft, {Set<String> clearErrors = const {}}) {
    final errors = Map<String, String>.of(state.errors)
      ..removeWhere(
        (k, _) => clearErrors.contains(k) || clearErrors.contains('*'),
      );
    state = state.copyWith(draft: draft, errors: errors, banner: null);
    _schedulePreview();
    _scheduleAutosave();
  }

  /// Başlık alanı güncellemesi.
  void update(
    FieldFormDraft Function(FieldFormDraft d) change, {
    Set<String> clears = const {},
  }) => _changed(change(state.draft), clearErrors: clears);

  void setShipDate(DateTime date) {
    final old = state.draft.shipDate;
    final lines = [
      for (final l in state.draft.lines)
        l.date == null || (old != null && TrTime.isSameDay(l.date!, old))
            ? l.copyWith(date: date)
            : l,
    ];
    _changed(
      state.draft.copyWith(shipDate: date, lines: lines),
      clearErrors: {'shipDate'},
    );
  }

  void setLocation(String? code) {
    final o = state.options;
    final lines = [
      for (final l in state.draft.lines)
        if (!l.tuprasEdited && o != null && l.productId != null)
          l.copyWith(
            tuprasM3: code == null
                ? null
                : o.product(l.productId)?.tuprasPricesM3[code],
          )
        else
          l,
    ];
    _changed(state.draft.copyWith(refineryLocation: code, lines: lines));
  }

  void setPaymentMethod(String? code) {
    final m = state.options?.payment?.method(code);
    _changed(
      state.draft.copyWith(
        paymentMethodCode: code,
        paymentTermDays: code == null ? 0 : _defaultTerm(m),
        paymentDetails: const {},
      ),
      clearErrors: {'paymentTermDays', 'paymentMethodCode'},
    );
  }

  void updateLine(
    String key,
    FieldLineDraft Function(FieldLineDraft l) change,
  ) {
    final lines = [
      for (final l in state.draft.lines) l.key == key ? change(l) : l,
    ];
    _changed(state.draft.copyWith(lines: lines), clearErrors: {'line:$key'});
  }

  void setLineProduct(String key, int productId) {
    final o = state.options;
    if (o == null) return;
    updateLine(
      key,
      (l) => _applyProduct(l, productId, state.draft.refineryLocation, o),
    );
  }

  /// Tüpraş fiyatını referansa döndürür ("Referansa dön").
  void resetLineTupras(String key) {
    final o = state.options;
    updateLine(key, (l) {
      final ref = state.draft.refineryLocation == null
          ? null
          : o
                ?.product(l.productId)
                ?.tuprasPricesM3[state.draft.refineryLocation];
      return l.copyWith(tuprasM3: ref, tuprasEdited: false);
    });
  }

  void addLine() {
    final o = state.options;
    if (o == null || state.draft.lines.length >= 20) return;
    _changed(
      state.draft.copyWith(
        lines: [...state.draft.lines, _newLine(state.draft, o)],
      ),
    );
  }

  void removeLine(String key) {
    _changed(
      state.draft.copyWith(
        lines: [
          for (final l in state.draft.lines)
            if (l.key != key) l,
        ],
      ),
      clearErrors: {'line:$key'},
    );
  }

  // ─────────────────────────────────────────────────────────── Adımlar

  void goTo(FieldWizardStep step) {
    if (step == state.step) return;
    if (step.index > state.step.index) {
      // İleri atlamada aradaki adımlar doğrulanır.
      for (var i = state.step.index; i < step.index; i++) {
        final errors = validateStep(FieldWizardStep.values[i]);
        if (errors.isNotEmpty) {
          state = state.copyWith(
            step: FieldWizardStep.values[i],
            errors: {...state.errors, ...errors},
          );
          return;
        }
      }
    }
    state = state.copyWith(step: step);
  }

  /// İleri: adım doğrulanır; hata varsa adımda kalınır. Dönüş: ilerlendi mi.
  bool next() {
    final errors = validateStep(state.step);
    if (errors.isNotEmpty) {
      state = state.copyWith(errors: {...state.errors, ...errors});
      return false;
    }
    if (state.step.index < FieldWizardStep.values.length - 1) {
      state = state.copyWith(
        step: FieldWizardStep.values[state.step.index + 1],
      );
      if (state.step == FieldWizardStep.summary) {
        _schedulePreview(immediate: true);
      }
    }
    return true;
  }

  void back() {
    if (state.step.index == 0) return;
    state = state.copyWith(step: FieldWizardStep.values[state.step.index - 1]);
  }

  /// Adımın alan hataları (boş = geçerli). Metinler sunucu doğrulamasıyla aynıdır.
  Map<String, String> validateStep(FieldWizardStep step) {
    final d = state.draft;
    final o = state.options;
    final errors = <String, String>{};
    final today = TrTime.todayStart();
    switch (step) {
      case FieldWizardStep.customer:
        if (!state.hasCustomer) errors['customer'] = 'Cari seçin.';
        if (o == null && state.hasCustomer) {
          errors['customer'] =
              state.optionsError?.message ??
              'Carinin bilgileri yükleniyor; lütfen bekleyin.';
        }
        final ship = d.shipDate;
        if (ship != null && TrTime.dayDiff(today, ship) < 0) {
          errors['shipDate'] = 'Sevk tarihi geçmiş olamaz.';
        }
        if (ship != null && TrTime.dayDiff(today, ship) > 365) {
          errors['shipDate'] = 'Sevk tarihi en çok 1 yıl sonrası olabilir.';
        }
      case FieldWizardStep.supply:
        if ((d.transportKm ?? 0) < 0 || (d.transportKm ?? 0) > 100000) {
          errors['transportKm'] =
              'Nakliye mesafesi 0–100.000 km arasında olmalı.';
        }
        if ((d.transportTotal ?? 0) < 0) {
          errors['transportTotal'] =
              'Nakliye tutarı 0 ya da pozitif olmalı (en çok 2 ondalık).';
        }
        if (d.isCombinedShipment) {
          if ((d.combinedTruckLiters ?? 0) <= 0) {
            errors['combinedTruckLiters'] =
                'Birleştirilmiş sevkiyatta tırın toplam litresini girin.';
          }
          if (d.combinedTruckCost == null || d.combinedTruckCost! < 0) {
            errors['combinedTruckCost'] =
                'Birleştirilmiş sevkiyatta tır nakliye tutarını girin.';
          }
        }
        final other = d.otherPercent;
        if (other != null && (other < 0 || other > 50)) {
          errors['otherPercent'] =
              'Diğer % 0–50 arasında ve en çok 4 ondalık olmalı.';
        }
        final a = d.purchaseTermPercent;
        if (a != null && (a < 0 || a > 100)) {
          errors['purchaseTermPercent'] =
              'Alım şartı %0–%100 arasında ve en çok 4 ondalık olmalı.';
        }
      case FieldWizardStep.payment:
        final m = o?.payment?.method(d.paymentMethodCode);
        final max = m?.maxTermDays ?? o?.maxPaymentTermDays ?? 365;
        final min = m?.minTermDays ?? 0;
        // Ödeme belgesi bilgileri saha formunda isteğe bağlıdır (sipariş açılınca da girilebilir).
        if (d.paymentTermDays < min ||
            d.paymentTermDays > (max < min ? min : max)) {
          errors['paymentTermDays'] = m == null
              ? 'Vade 0–${o?.maxPaymentTermDays ?? 365} gün arasında olmalı.'
              : '${m.name} için vade $min–$max gün arasında olmalı.';
        }
      case FieldWizardStep.lines:
        final lines = d.lines;
        if (lines.isEmpty) errors['lines'] = 'En az bir satır ekleyin.';
        for (var i = 0; i < lines.length; i++) {
          final e = _lineError(i + 1, lines[i], today);
          if (e != null) errors['line:${lines[i].key}'] = e;
        }
      case FieldWizardStep.summary:
        if (d.strategicExceptionRequested &&
            (d.exceptionJustification ?? '').trim().length < 20) {
          errors['exceptionJustification'] =
              'İstisna gerekçesi en az 20 karakter olmalı.';
        }
        if ((d.note ?? '').length > 1000) {
          errors['note'] = 'Not en çok 1000 karakter olabilir.';
        }
    }
    return errors;
  }

  String? _lineError(int no, FieldLineDraft l, DateTime today) {
    if ((l.productId ?? 0) <= 0) return '$no. satır: ürün seçin.';
    if ((l.deliveryPointId ?? 0) <= 0) {
      return '$no. satır: teslimat noktası seçin.';
    }
    final liters = l.liters ?? 0;
    if (liters <= 0 || liters > 999999999) {
      return '$no. satır: litre pozitif olmalı ve en çok 3 ondalık içermeli.';
    }
    if (l.priceEntryMode == 1) {
      if (l.profitPercent == null) return '$no. satır: satış kârı % girin.';
    } else {
      final p = l.unitPrice ?? 0;
      if (p <= 0 || p > 999999) {
        return "$no. satır: birim fiyat 0'dan büyük ve en çok 4 ondalık olmalı.";
      }
    }
    final date = l.date ?? state.draft.shipDate;
    if (date == null) return '$no. satır: teslim tarihi seçin.';
    if (TrTime.dayDiff(today, date) < 0) {
      return '$no. satır: teslim tarihi geçmiş olamaz.';
    }
    if (TrTime.dayDiff(today, date) > 365) {
      return '$no. satır: teslim tarihi en çok 1 yıl sonrası olabilir.';
    }
    final t = l.tuprasM3;
    if (t != null && (t < 1000 || t > 1000000)) {
      return '$no. satır: Tüpraş fiyatı ₺/m³ (KDV dahil) olarak girilmeli (ör. 61.507,69).';
    }
    final pump = l.pumpPrice;
    if (pump != null && (pump <= 0 || pump > 1000)) {
      return '$no. satır: pompa fiyatı ₺/L olarak girilmeli (ör. 72,42).';
    }
    return null;
  }

  /// Tüm adımların hataları; ilk hatalı adıma gidilir.
  bool _validateAll() {
    final all = <String, String>{};
    FieldWizardStep? first;
    for (final s in FieldWizardStep.values) {
      final e = validateStep(s);
      if (e.isNotEmpty) {
        first ??= s;
        all.addAll(e);
      }
    }
    if (all.isEmpty) return true;
    state = state.copyWith(errors: all, step: first);
    return false;
  }

  // ─────────────────────────────────────────────────────────── Canlı önizleme

  void _schedulePreview({bool immediate = false}) {
    if (immediate) {
      _previewDebounce.cancel();
      unawaited(_runPreview());
    } else {
      _previewDebounce(() => unawaited(_runPreview()));
    }
  }

  /// Önizlemeyi şimdi yeniler ("Tekrar dene").
  Future<void> refreshPreview() => _runPreview(force: true);

  Future<void> _runPreview({bool force = false}) async {
    final o = state.options;
    final d = state.draft;
    if (o == null || !state.hasCustomer) return;
    final complete = d.completeLines;
    if (complete.isEmpty) {
      if (state.preview != null || state.previewError != null) {
        state = state.copyWith(
          preview: null,
          previewError: null,
          previewKeys: const [],
        );
      }
      return;
    }
    final request = d.toRequest(
      includeCosts: o.showCosts,
      onlyCompleteLines: true,
      forPreview: true,
    );
    final fingerprint = request.toString();
    if (!force &&
        fingerprint == _lastPreviewFor &&
        state.previewError == null) {
      return;
    }
    if (!ref.read(isOnlineProvider)) {
      state = state.copyWith(
        previewLoading: false,
        previewError: const OfflineFailure(),
      );
      return;
    }
    final epoch = ++_previewEpoch;
    _previewCancel?.cancel();
    final cancel = _previewCancel = CancelToken();
    state = state.copyWith(previewLoading: true);
    try {
      final p = await _repo.preview(request, cancelToken: cancel);
      if (epoch != _previewEpoch) return;
      _lastPreviewFor = fingerprint;
      state = state.copyWith(
        preview: p,
        previewLoading: false,
        previewError: null,
        previewKeys: [for (final l in complete) l.key],
      );
    } catch (e) {
      if (epoch != _previewEpoch) return;
      final f = AppFailure.from(e);
      if (f is UnknownFailure && f.cancelled) return;
      state = state.copyWith(previewLoading: false, previewError: f);
    }
  }

  String? _lastPreviewFor;

  // ─────────────────────────────────────────────────────────── Cihaza yazma

  void _scheduleAutosave() {
    _autosaveDebounce(() => unawaited(_autosave()));
  }

  Future<void> _autosave() async {
    final key = _autosaveKey;
    if (key == null || state.outcome != null) return;
    if (!state.dirty) return;
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

  /// Eksik satırlar (hiçbir alanı dolmamış) atılır; kısmen dolu satır hatadır.
  List<FieldLineDraft> _linesForSave() => [
    for (final l in state.draft.lines)
      if (l.productId != null ||
          (l.liters ?? 0) > 0 ||
          l.deliveryPointId != null)
        l,
  ];

  /// Taslak kaydet (çevrimdışı güvenli). Sonuç [FormWizardState.outcome] ile gösterilir.
  Future<void> saveDraft() async {
    if (state.busy) return;
    if (!state.hasCustomer) {
      state = state.copyWith(
        step: FieldWizardStep.customer,
        errors: {'customer': 'Taslağı kaydetmek için önce cari seçin.'},
      );
      return;
    }
    final lines = _linesForSave();
    final today = TrTime.todayStart();
    final lineErrors = <String, String>{};
    for (var i = 0; i < lines.length; i++) {
      final e = _lineError(i + 1, lines[i], today);
      if (e != null) lineErrors['line:${lines[i].key}'] = e;
    }
    final header = {
      ...validateStep(FieldWizardStep.customer)..remove('customer'),
      ...validateStep(FieldWizardStep.supply),
      ...validateStep(FieldWizardStep.payment),
      ...validateStep(FieldWizardStep.summary),
    };
    if (lineErrors.isNotEmpty || header.isNotEmpty) {
      state = state.copyWith(
        errors: {...lineErrors, ...header},
        step: lineErrors.isNotEmpty
            ? FieldWizardStep.lines
            : FieldWizardStep.values.firstWhere(
                (s) => validateStep(s).keys.any(header.containsKey),
                orElse: () => state.step,
              ),
      );
      return;
    }
    final draft = state.draft.copyWith(lines: lines);
    state = state.copyWith(draft: draft);
    await _save(draft, submitAfter: false);
  }

  JsonMap _requestFor(FieldFormDraft d) =>
      d.toRequest(includeCosts: state.showCosts);

  String _keyFor(JsonMap request) {
    final fp = request.toString();
    if (_createKey == null || _createKeyFingerprint != fp) {
      _createKey = newIdempotencyKey();
      _createKeyFingerprint = fp;
    }
    return _createKey!;
  }

  /// Kaydeder. Dönüş: kaydedilen form (çevrimdışı / belirsiz → kuyruk ve null).
  Future<FieldForm?> _save(
    FieldFormDraft d, {
    required bool submitAfter,
  }) async {
    final request = _requestFor(d);
    final queuedAfter = state.queuedOpId;
    final key = _keyFor(request);
    if (queuedAfter != null || !ref.read(isOnlineProvider)) {
      await _queue(d, request, key, submitAfter: submitAfter);
      return null;
    }
    state = state.copyWith(
      busy: true,
      busyLabel: 'Kaydediliyor',
      banner: null,
      conflict: false,
    );
    try {
      final form = d.formId == null
          ? await _repo.createForm(request, idempotencyKey: key)
          : await _repo.updateForm(d.formId!, request);
      _createKey = null;
      state = state.copyWith(
        busy: false,
        busyLabel: null,
        draft: d.copyWith(
          formId: form.id,
          formNumber: form.formNumber,
          concurrencyToken: form.concurrencyToken,
        ),
        baseFingerprint: d
            .copyWith(
              formId: form.id,
              formNumber: form.formNumber,
              concurrencyToken: form.concurrencyToken,
            )
            .fingerprint,
      );
      if (!submitAfter) {
        await _clearAutosave();
        ref.read(fieldSyncTickProvider.notifier).bump();
        state = state.copyWith(outcome: FieldDraftSaved(form));
      }
      return form;
    } on AppFailure catch (f) {
      state = state.copyWith(busy: false, busyLabel: null);
      if (f.isUncertain || f is OfflineFailure) {
        // Sunucu işlemiş olabilir: aynı anahtarla bekleyen işlemlere alınır (tekrar ikinci form açmaz).
        await _queue(d, request, key, submitAfter: submitAfter);
        return null;
      }
      _showFailure(f);
      return null;
    }
  }

  Future<void> _queue(
    FieldFormDraft d,
    JsonMap request,
    String key, {
    required bool submitAfter,
  }) async {
    final outbox = ref.read(fieldOutboxProvider);
    var previousOp = state.queuedOpId;
    if (previousOp != null) {
      final prev = await ref.read(outboxStoreProvider).get(previousOp);
      if (prev != null && prev.status == OutboxStatus.needsAttention) {
        // Sunucu önceki kaydı reddetti: düzeltilmiş taslak baştan (yeni anahtarla) gönderilir.
        await outbox.discardChain(previousOp);
        previousOp = null;
      } else if (prev == null) {
        previousOp = null;
      }
    }
    final op = await outbox.queueFormSave(
      request: request,
      idempotencyKey: previousOp != null ? newIdempotencyKey() : key,
      formId: d.formId,
      chainAfter: previousOp,
      customerTitle: d.customerTitle,
      formNumber: d.formNumber,
      liters: d.totalLiters,
    );
    _createKey = null;
    await _clearAutosave();
    state = state.copyWith(
      baseFingerprint: d.fingerprint,
      outcome: FieldDraftQueued(op.id, submitRequested: submitAfter),
    );
  }

  void _showFailure(AppFailure f) {
    switch (f) {
      case ConflictFailure(isConcurrency: true):
        state = state.copyWith(conflict: true, banner: f.message);
      case BusinessFailure() when f.message.contains('değiştirildi'):
        state = state.copyWith(conflict: true, banner: f.message);
      case ValidationFailure(:final fieldErrors):
        final mapped = <String, String>{};
        fieldErrors.forEach((k, v) {
          if (v.isNotEmpty) mapped[_fieldKey(k)] = v.first;
        });
        state = state.copyWith(
          errors: {...state.errors, ...mapped},
          banner: f.message,
        );
      default:
        state = state.copyWith(banner: f.message);
    }
  }

  static String _fieldKey(String serverKey) {
    final k = serverKey.trim();
    if (k.isEmpty) return k;
    return k[0].asciiLower + k.substring(1);
  }

  /// Çakışmadan sonra "Yenile": güncel taslak okunur, girilen satırlar korunur.
  Future<void> reloadAfterConflict() async {
    final id = state.draft.formId;
    if (id == null) {
      state = state.copyWith(conflict: false, banner: null);
      return;
    }
    try {
      final current = (await _repo.form(id)).form;
      state = state.copyWith(
        conflict: false,
        banner: null,
        draft: state.draft.copyWith(concurrencyToken: current.concurrencyToken),
        baseFingerprint: FieldFormDraft.fromForm(current).fingerprint,
      );
      if (!current.status.isEditable) {
        state = state.copyWith(
          banner:
              'Form artık taslak değil (${current.displayStatus}); düzenleme kaydedilemez.',
        );
      }
    } on AppFailure catch (f) {
      state = state.copyWith(banner: f.message);
    }
  }

  // ─────────────────────────────────────────────────────────── Gönder

  /// Onaya gönder (bağlantı gerekir). Önce taslak kaydedilir; gönderim belirsizse aynı anahtarla
  /// yinelenir ve form yeniden okunur.
  Future<void> submit() async {
    if (state.busy) return;
    if (!_validateAll()) return;
    if (!ref.read(isOnlineProvider)) {
      state = state.copyWith(
        banner:
            'Göndermek için bağlantı gerekir. Taslağı kaydedin; bağlantı gelince Formlarım’dan gönderin.',
      );
      return;
    }
    var d = state.draft.copyWith(lines: _linesForSave());
    FieldForm? form;
    if (d.formId == null || state.dirty || state.queuedOpId != null) {
      form = await _save(d, submitAfter: true);
      if (form == null) return; // Kuyruğa alındı ya da hata gösterildi.
      d = state.draft;
    }
    final id = d.formId!;
    final token = form?.concurrencyToken ?? d.concurrencyToken;
    _submitKey ??= newIdempotencyKey();
    state = state.copyWith(busy: true, busyLabel: 'Gönderiliyor', banner: null);
    try {
      final result = await retryUncertain(
        () => _repo.submitForm(
          id,
          concurrencyToken: token,
          idempotencyKey: _submitKey,
        ),
        onRetry: (_) =>
            state = state.copyWith(busyLabel: 'Gönderim kontrol ediliyor…'),
        reconcile: () async {
          final f = (await _repo.form(id)).form;
          if (f.status == FieldOrderFormStatus.draft) return null;
          return FieldSubmitResult(
            formId: f.id,
            formNumber: f.formNumber,
            status: f.status,
            requiredApprovalLevel: f.requiredApprovalLevel,
            autoApproved: f.status == FieldOrderFormStatus.converted,
            convertedOrderIds: f.convertedOrderIds,
            financeStatus: f.financeStatus,
            message: _statusMessage(f),
          );
        },
      );
      _submitKey = null;
      await _clearAutosave();
      ref.read(fieldSyncTickProvider.notifier).bump();
      state = state.copyWith(
        busy: false,
        busyLabel: null,
        outcome: FieldFormSubmitted(result),
      );
    } on AppFailure catch (f) {
      state = state.copyWith(busy: false, busyLabel: null);
      if (f is OfflineFailure) {
        state = state.copyWith(
          banner:
              'Bağlantı kesildi. Taslak kaydedildi; bağlantı gelince yeniden gönderin.',
        );
        return;
      }
      _showFailure(f);
    }
  }

  static String _statusMessage(FieldForm f) => switch (f.status) {
    FieldOrderFormStatus.converted => 'Form onaylandı ve siparişe dönüştü.',
    FieldOrderFormStatus.pendingApproval =>
      'Form onaya gönderildi: ${FieldLevels.waitingText(f.requiredApprovalLevel)}',
    FieldOrderFormStatus.rejected => 'Form reddedildi.',
    FieldOrderFormStatus.approved =>
      'Kârlılık onayı tamam; finans onayı bekleniyor.',
    _ => f.displayStatus,
  };

  /// Sonuç ekranından sihirbaza dönüş (ör. "Düzenlemeye devam et").
  void clearOutcome() => state = state.copyWith(outcome: null);

  /// Tahmini toplam (önizleme yoksa): "Tahmini 1.234,56 ₺".
  String get estimatedText => Fmt.money(state.draft.estimatedAmount);
}
