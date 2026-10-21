import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/models/models.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/idempotency.dart';
import '../../../core/storage/prefs_store.dart';
import '../../../core/utils/log.dart';
import '../../../core/utils/turkish_text.dart';
import '../data/customer_orders_repository.dart';
import '../data/form_models.dart';
import '../data/order_models.dart';
import '../data/payment_models.dart';
import '../data/place_models.dart';
import 'home_controller.dart';
import 'loadable.dart';
import 'retry_policy.dart';
import 'wizard_models.dart';
import 'wizard_store.dart';

/// Gönderim aşaması (spec C.4a).
enum SubmitPhase {
  /// Gönderim yok (sihirbaz düzenleniyor).
  idle,

  /// İlk istek gidiyor.
  sending,

  /// Sonuç belirsiz; aynı anahtarla yeniden deneniyor ("Siparişiniz kontrol ediliyor").
  checking,

  /// 60 sn içinde doğrulanamadı; aynı anahtarla elle tekrar ya da siparişleri kontrol.
  uncertain,

  /// `idempotency_unknown`: Siparişlerim ile karşılaştırılıyor.
  reconciling,

  /// Sipariş bulunamadı: yeni anahtarla göndermeden önce kullanıcıya sorulur.
  askNewKey,

  /// Tüm satırlar oluştu ya da şirket içi talep açıldı.
  success,

  /// Bazı satırlar oluştu; kalanlar gönderilmedi.
  partial,

  /// Kesin ret (doğrulama, iş kuralı, yetki).
  failed,
}

/// Gönderim durumu.
@immutable
class SubmitState {
  const SubmitState({
    this.phase = SubmitPhase.idle,
    this.result,
    this.created = const [],
    this.failure,
    this.attempts = 0,
    this.reconciled = false,
    this.remainingLines = 0,
    this.templateSaved,
    this.firstOrder = false,
    this.documentUploadedGroup,
  });

  final SubmitPhase phase;

  /// Son sunucu sonucu (başarı / kısmi; doğrulamadan geldiyse sentezlenmiş).
  final PlaceOrderResult? result;

  /// Bu taslaktan bugüne oluşan tüm siparişler (kısmi gönderimler dahil).
  final List<CreateOrderResult> created;
  final AppFailure? failure;

  /// Aynı anahtarla yapılan deneme sayısı.
  final int attempts;

  /// Sonuç sunucu yanıtıyla değil Siparişlerim karşılaştırmasıyla bulundu.
  final bool reconciled;

  /// Kısmi sonuçta gönderilmeyen satır sayısı.
  final int remainingLines;

  /// "Şablon olarak kaydet" sonucu (istenmediyse null).
  final bool? templateSaved;

  /// Kullanıcının ilk siparişi (bildirim izni ön sayfası).
  final bool firstOrder;

  /// Belgesi yüklenmiş ödeme grubu.
  final String? documentUploadedGroup;

  bool get isBusy =>
      phase == SubmitPhase.sending ||
      phase == SubmitPhase.checking ||
      phase == SubmitPhase.reconciling;

  bool get isActive => phase != SubmitPhase.idle;

  SubmitState copyWith({
    SubmitPhase? phase,
    PlaceOrderResult? result,
    List<CreateOrderResult>? created,
    AppFailure? failure,
    bool clearFailure = false,
    int? attempts,
    bool? reconciled,
    int? remainingLines,
    bool? templateSaved,
    bool? firstOrder,
    String? documentUploadedGroup,
  }) => SubmitState(
    phase: phase ?? this.phase,
    result: result ?? this.result,
    created: created ?? this.created,
    failure: clearFailure ? null : (failure ?? this.failure),
    attempts: attempts ?? this.attempts,
    reconciled: reconciled ?? this.reconciled,
    remainingLines: remainingLines ?? this.remainingLines,
    templateSaved: templateSaved ?? this.templateSaved,
    firstOrder: firstOrder ?? this.firstOrder,
    documentUploadedGroup: documentUploadedGroup ?? this.documentUploadedGroup,
  );
}

/// Anahtar üretici (testler sabitler).
final a2KeyGenProvider = Provider<String Function()>(
  (ref) => newIdempotencyKey,
);

/// Sipariş gönderimi (spec A.4 "Submission" + C.4a):
/// - Taslak ve Idempotency-Key kullanıcı başına saklanır (24 sa); uygulama kapanıp açılınca aynı
///   anahtarla devam edilir ([resumeIfPending]).
/// - Zaman aşımı, bağlantı yok ve 5xx'te aynı anahtarla 2–4–8–16 sn (en çok 60 sn);
///   `idempotency_in_progress` alındıkça yoklanır.
/// - `idempotency_unknown`: Siparişlerim ile karşılaştırılır; bulunamazsa yeni anahtar sorulur.
/// - Kısmi hata: kalan satırlar yeni anahtar + dönen `paymentGroupKey` ile gönderilir.
final orderSubmitProvider =
    NotifierProvider<OrderSubmitController, SubmitState>(
      OrderSubmitController.new,
    );

class OrderSubmitController extends Notifier<SubmitState> {
  bool _running = false;
  int _epoch = 0;
  bool _alive = true;

  @override
  SubmitState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    ref.watch(currentUserIdProvider);
    _epoch++;
    _running = false;
    return const SubmitState();
  }

  CustomerOrdersRepository get _repo =>
      ref.read(customerOrdersRepositoryProvider);
  WizardDraftStore? get _store => ref.read(wizardDraftStoreProvider);

  // ------------------------------------------------------------------ Giriş noktaları

  /// Kullanıcı "Gönder"e bastı. Aynı gövde için bekleyen anahtar varsa o kullanılır.
  Future<void> submit(OrderDraft draft, PlaceOrderRequest request) async {
    if (_running) return;
    final store = _store;
    if (store == null) return;
    final snap = await store.load();
    var pending = snap?.pending;
    if (pending == null || !_sameBody(pending.request, request)) {
      pending = PendingSubmission(
        key: ref.read(a2KeyGenProvider)(),
        request: request,
        startedAt: DateTime.now().toUtc(),
      );
    }
    final next = WizardSnapshot(
      draft: draft.copyWith(dirty: true),
      pending: pending,
      created: snap?.created ?? const [],
      documentUploadedGroup: snap?.documentUploadedGroup,
    );
    await store.save(next);
    if (!_alive) return;
    _bumpDraft();
    state = SubmitState(
      phase: SubmitPhase.sending,
      created: next.created,
      documentUploadedGroup: next.documentUploadedGroup,
    );
    await _run(next);
  }

  /// Açılışta (ana sayfa, sihirbaz) bekleyen gönderim varsa aynı anahtarla sürdürür.
  Future<bool> resumeIfPending() async {
    if (_running || state.isActive) return false;
    final snap = await _store?.load();
    if (!_alive || snap?.pending == null) return false;
    state = SubmitState(
      phase: SubmitPhase.checking,
      created: snap!.created,
      documentUploadedGroup: snap.documentUploadedGroup,
    );
    await _run(snap);
    return true;
  }

  /// Belirsiz sonuçtan sonra aynı anahtarla tekrar dene.
  Future<void> retrySameKey() async {
    final snap = await _store?.load();
    if (snap?.pending == null || _running) return;
    state = state.copyWith(phase: SubmitPhase.checking, clearFailure: true);
    await _run(snap!);
  }

  /// Belirsiz sonuçta Siparişlerim ile karşılaştır.
  Future<void> checkOrders() async {
    final snap = await _store?.load();
    final pending = snap?.pending;
    if (pending == null || _running) return;
    _running = true;
    try {
      await _reconcile(snap!, pending, _epoch);
    } finally {
      _running = false;
    }
  }

  /// Sipariş bulunamadı: kullanıcı onayıyla yeni anahtar.
  Future<void> confirmNewKey() async {
    final store = _store;
    final snap = await store?.load();
    final pending = snap?.pending;
    if (store == null || pending == null || _running) return;
    final next = snap!.copyWith(
      pending: PendingSubmission(
        key: ref.read(a2KeyGenProvider)(),
        request: pending.request,
        startedAt: DateTime.now().toUtc(),
      ),
    );
    await store.save(next);
    state = state.copyWith(
      phase: SubmitPhase.sending,
      attempts: 0,
      clearFailure: true,
    );
    await _run(next);
  }

  /// Kısmi sonuçtan sonra kalan satırları yeni anahtar + aynı ödeme grubuyla gönder.
  Future<void> sendRemaining(PlaceOrderRequest request) async {
    final snap = await _store?.load();
    if (snap == null) return;
    await submit(snap.draft, request);
  }

  /// Belirsiz / reddedilmiş gönderimden düzenlemeye dön: anahtar bırakılır (yeni niyet).
  Future<void> backToEditing() async {
    final store = _store;
    final snap = await store?.load();
    if (store != null && snap != null && snap.pending != null) {
      await store.save(snap.copyWith(clearPending: true));
    }
    if (!_alive) return;
    _bumpDraft();
    state = state.copyWith(
      phase: SubmitPhase.idle,
      clearFailure: true,
      attempts: 0,
    );
  }

  /// Başarı ekranı kapatıldı.
  void acknowledge() {
    if (state.isBusy) return;
    state = const SubmitState();
  }

  /// Ödeme belgesi yüklendi (aynı grupta ikinci kez istenmez).
  Future<void> markDocumentUploaded(String? groupKey) async {
    state = state.copyWith(documentUploadedGroup: groupKey ?? '-');
    final store = _store;
    final snap = await store?.load();
    if (store != null && snap != null) {
      await store.save(snap.copyWith(documentUploadedGroup: groupKey ?? '-'));
    }
  }

  // ------------------------------------------------------------------ Çalıştırma

  Future<void> _run(WizardSnapshot snap) async {
    final pending = snap.pending;
    if (pending == null || _running) return;
    _running = true;
    final epoch = _epoch;
    final policy = ref.read(a2RetryPolicyProvider);
    final wait = ref.read(a2WaitProvider);
    var attempt = 0;
    var waited = Duration.zero;
    try {
      while (_alive && epoch == _epoch) {
        try {
          final res = await _repo.place(
            pending.request,
            idempotencyKey: pending.key,
          );
          if (!_alive || epoch != _epoch) return;
          await _onResult(snap, pending, res);
          return;
        } on AppFailure catch (f) {
          if (!_alive || epoch != _epoch) return;
          if (f is ConflictFailure && f.conflictCode == 'idempotency_unknown') {
            await _reconcile(snap, pending, epoch);
            return;
          }
          if (isRetryableFailure(f)) {
            final inProgress = f is ConflictFailure && f.isInProgress;
            if (!policy.allows(attempt, waited, inProgress: inProgress)) {
              state = state.copyWith(
                phase: SubmitPhase.uncertain,
                failure: f,
                attempts: attempt + 1,
              );
              return;
            }
            final d = f is RateLimitedFailure && f.retryAfter != null
                ? f.retryAfter!
                : policy.delayFor(attempt);
            state = state.copyWith(
              phase: SubmitPhase.checking,
              failure: f,
              attempts: attempt + 1,
            );
            await wait(d);
            waited += d;
            attempt++;
            continue;
          }
          // Kesin yanıt: hiçbir sipariş oluşmadı (sunucu önce doğrular). Anahtar bırakılır.
          final store = _store;
          if (store != null) {
            await store.save(snap.copyWith(clearPending: true));
          }
          if (!_alive) return;
          _bumpDraft();
          state = state.copyWith(phase: SubmitPhase.failed, failure: f);
          return;
        }
      }
    } finally {
      if (_alive && epoch == _epoch) _running = false;
    }
  }

  Future<void> _onResult(
    WizardSnapshot snap,
    PendingSubmission pending,
    PlaceOrderResult res, {
    bool reconciled = false,
  }) async {
    final store = _store;
    final created = [...snap.created, ...res.orders];
    if (res.isPartial && res.orders.isNotEmpty) {
      final from = res.failedLineIndex!.clamp(0, snap.draft.lines.length);
      final rest = snap.draft.lines.sublist(from);
      final draft = snap.draft.copyWith(
        lines: rest,
        paymentGroupKey: res.paymentGroupKey ?? snap.draft.paymentGroupKey,
        origin: DraftOrigin.partial,
        step: WizardStep.summary,
        clearTemplate: true,
        saveAsTemplate: false,
        dirty: true,
      );
      if (store != null) {
        await store.save(
          WizardSnapshot(
            draft: draft,
            created: created,
            documentUploadedGroup: snap.documentUploadedGroup,
          ),
        );
      }
      if (!_alive) return;
      _bumpDraft();
      state = state.copyWith(
        phase: SubmitPhase.partial,
        result: res,
        created: created,
        reconciled: reconciled,
        remainingLines: rest.length,
        clearFailure: true,
      );
      _refreshLists();
      return;
    }

    // Başarı: taslak ve anahtar silinir.
    await store?.clear();
    if (!_alive) return;
    _bumpDraft();
    final first = await _markFirstOrder();
    await _rememberDefaults(snap.draft);
    if (!_alive) return;
    state = state.copyWith(
      phase: SubmitPhase.success,
      result: res,
      created: created,
      reconciled: reconciled,
      remainingLines: 0,
      firstOrder: first,
      clearFailure: true,
    );
    _refreshLists();
    if (snap.draft.saveAsTemplate &&
        snap.draft.templateName.trim().isNotEmpty) {
      unawaited(_saveTemplate(snap.draft, pending.request));
    }
  }

  // ------------------------------------------------------------------ Doğrulama

  Future<void> _reconcile(
    WizardSnapshot snap,
    PendingSubmission pending,
    int epoch,
  ) async {
    state = state.copyWith(phase: SubmitPhase.reconciling);
    final found = await findPlacement(pending);
    if (!_alive || epoch != _epoch) return;
    if (found != null) {
      await _onResult(snap, pending, found, reconciled: true);
      return;
    }
    state = state.copyWith(phase: SubmitPhase.askNewKey, reconciled: true);
  }

  /// Gönderimin sunucuda oluşup oluşmadığını Siparişlerim (ve Talep eden için şirket içi talepler)
  /// ile karşılaştırır. Satırlar sırayla oluşur ve ilk hatada durulur; eşleşen ön ek kadar sipariş
  /// oluşmuş sayılır. Hiç eşleşme yoksa null.
  @visibleForTesting
  Future<PlaceOrderResult?> findPlacement(PendingSubmission pending) async {
    final req = pending.request;
    final repo = _repo;
    final access = ref.read(sessionControllerProvider).access;
    OrderFormOptions? form = ref.read(orderFormProvider).data;
    if (form == null) {
      try {
        form = OrderFormOptions.fromJson(await repo.orderFormRaw());
      } on AppFailure catch (f) {
        AppLog.debug('Doğrulama için sipariş formu alınamadı: $f');
      }
    }
    final rows = <CustomerOrderRow>[];
    for (final seg in [OrderSegment.active, OrderSegment.decision]) {
      try {
        final page = await repo.orders(segment: seg, pageSize: 50);
        rows.addAll(page.items);
      } on AppFailure catch (f) {
        AppLog.debug('Doğrulama listesi alınamadı ($seg): $f');
      }
    }
    final since = pending.startedAt.subtract(const Duration(minutes: 2));
    final candidates =
        rows
            .where(
              (r) =>
                  (r.createdAt == null || !r.createdAt!.isBefore(since)) &&
                  (req.stationId <= 0 || r.stationId == req.stationId),
            )
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    final used = <int>{};
    final matched = <CustomerOrderRow>[];
    for (final line in req.lines) {
      final productName = form?.product(line.productId)?.name;
      final pointName = form
          ?.point(line.deliveryPointId ?? req.deliveryPointId)
          ?.name;
      CustomerOrderRow? hit;
      for (final r in candidates) {
        if (used.contains(r.id)) continue;
        if ((r.quantityLiters - line.quantityLiters).abs() > 0.0005) continue;
        if (productName != null && !_sameText(r.productName, productName)) {
          continue;
        }
        if (pointName != null && !_sameText(r.deliveryPointName, pointName)) {
          continue;
        }
        hit = r;
        break;
      }
      if (hit == null) break;
      used.add(hit.id);
      matched.add(hit);
    }
    if (matched.isNotEmpty) {
      String? groupKey = req.paymentGroupKey;
      if (groupKey == null && req.payment != null) {
        try {
          groupKey = (await repo.order(matched.first.id)).paymentGroupKey;
        } on AppFailure catch (_) {}
      }
      final orders = [
        for (final m in matched)
          CreateOrderResult(
            orderId: m.id,
            orderNumber: m.orderNumber,
            expiresAt: m.expiresAt,
            financeStatus: m.financeStatus,
            paymentMethodCode: m.paymentMethodCode,
            paymentDueDate: m.paymentDueDate,
            paymentGroupKey: groupKey,
          ),
      ];
      final complete = matched.length == req.lines.length;
      final doc = req.payment == null
          ? null
          : await _documentTargetSafe(
              repo,
              req.payment!.methodCode,
              groupKey,
              orders.map((o) => o.orderId),
            );
      return PlaceOrderResult(
        orders: orders,
        paymentGroupKey: groupKey,
        financePendingCount: orders
            .where((o) => o.financeStatus == OrderFinanceStatus.pending)
            .length,
        paymentDocument: doc,
        partialError: complete
            ? null
            : 'Kalan satırların gönderildiği doğrulanamadı; tekrar gönderebilirsiniz.',
        failedLineIndex: complete ? null : matched.length,
        message: complete
            ? (orders.length == 1
                  ? 'Sipariş oluşturulmuş: ${orders.first.orderNumber}'
                  : '${orders.length} sipariş oluşturulmuş: ${orders.map((o) => o.orderNumber).join(', ')}')
            : '${orders.length} sipariş oluşturulmuş; kalan satırlar gönderilmemiş.',
      );
    }
    // Talep eden: sipariş yerine şirket içi talep açılmış olabilir.
    if (access?.customerUserRole == CustomerUserRole.requester) {
      try {
        final requests = await repo.recentOrderRequests();
        for (final r in requests) {
          final at = r.createdAt;
          if (at != null && at.isBefore(since)) continue;
          if ((r.totalLiters - req.totalLiters).abs() > 0.0005) continue;
          return PlaceOrderResult(
            kind: PlaceOrderResult.kindCompanyRequest,
            companyRequest: CompanyRequestRef(
              id: r.id,
              message:
                  'Siparişiniz şirket içi onaya gönderilmiş (Talep #${r.id}). '
                  'Onaylanınca siparişleriniz bayiye iletilir.',
            ),
            message:
                'Siparişiniz şirket içi onaya gönderilmiş (Talep #${r.id}).',
          );
        }
      } on AppFailure catch (f) {
        AppLog.debug('Talepler doğrulanamadı: $f');
      }
    }
    return null;
  }

  Future<PaymentUploadTarget?> _documentTargetSafe(
    CustomerOrdersRepository repo,
    String method,
    String? groupKey,
    Iterable<int> orderIds,
  ) async {
    try {
      return await repo.documentTarget(
        methodCode: method,
        groupKey: groupKey,
        orderIds: orderIds,
      );
    } on AppFailure catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------ Yan etkiler

  Future<void> _saveTemplate(OrderDraft draft, PlaceOrderRequest req) async {
    try {
      await _repo.saveTemplate(
        name: draft.templateName.trim(),
        lines: [
          for (final l in req.lines)
            (
              productId: l.productId,
              deliveryPointId: l.deliveryPointId ?? req.deliveryPointId,
              liters: l.quantityLiters,
              stationId: req.stationId > 0 ? req.stationId : null,
            ),
        ],
      );
      if (_alive) state = state.copyWith(templateSaved: true);
    } on AppFailure catch (f) {
      AppLog.debug('Şablon kaydedilemedi: $f');
      if (_alive) state = state.copyWith(templateSaved: false);
    }
  }

  Future<bool> _markFirstOrder() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return false;
    try {
      final prefs = ref.read(prefsStoreProvider);
      final key = A2Keys.firstOrderDone(uid);
      if (prefs.getBool(key)) return false;
      await prefs.setBool(key, true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _rememberDefaults(OrderDraft d) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    try {
      final prefs = ref.read(prefsStoreProvider);
      if (d.pointId != null) {
        await prefs.setInt(A2Keys.lastPoint(uid), d.pointId!);
      }
      if (d.stationId != null) {
        await prefs.setInt(A2Keys.lastStation(uid), d.stationId!);
      }
      await prefs.setString(A2Keys.lastMethod(uid), d.payment.methodCode);
    } catch (_) {}
  }

  void _refreshLists() {
    if (!_alive) return;
    ref.read(a2DataRevisionProvider.notifier).bump();
  }

  void _bumpDraft() {
    if (_alive) ref.read(draftRevisionProvider.notifier).bump();
  }

  static bool _sameBody(PlaceOrderRequest a, PlaceOrderRequest b) =>
      mapEquals(_canon(a.toJson()), _canon(b.toJson()));

  static Map<String, Object?> _canon(JsonMap m) => {
    for (final e in m.entries) e.key: '${e.value}',
  };

  static bool _sameText(String? a, String b) =>
      TurkishText.searchKey(a ?? '') == TurkishText.searchKey(b);
}
