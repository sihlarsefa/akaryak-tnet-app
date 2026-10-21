import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/models/models.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/storage/prefs_store.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/log.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../data/customer_orders_repository.dart';
import '../data/form_models.dart';
import '../data/home_models.dart';
import '../data/payment_models.dart';
import '../data/place_models.dart';
import 'home_controller.dart';
import 'loadable.dart';
import 'wizard_models.dart';
import 'wizard_rules.dart';
import 'wizard_store.dart';

/// Sihirbazın açılış parametreleri (`/orders/new?fromTemplate=&fromRequest=&reorder=`).
@immutable
class WizardLaunch {
  const WizardLaunch({this.templateId, this.requestId, this.reorderId});

  factory WizardLaunch.fromQuery(Map<String, String> q) => WizardLaunch(
    templateId: int.tryParse(q['fromTemplate'] ?? ''),
    requestId: int.tryParse(q['fromRequest'] ?? ''),
    reorderId: int.tryParse(q['reorder'] ?? ''),
  );

  final int? templateId;
  final int? requestId;
  final int? reorderId;

  bool get hasSource =>
      templateId != null || requestId != null || reorderId != null;
}

/// Sihirbaz ekran durumu.
@immutable
class WizardState {
  const WizardState({
    this.draft = const OrderDraft(),
    this.ready = false,
    this.loadError,
    this.ordering,
    this.checkingOrdering = false,
    this.payment,
    this.loadingPayment = false,
    this.paymentError,
    this.notice,
    this.showErrors = false,
    this.autoAmount = true,
    this.autoDue = true,
  });

  final OrderDraft draft;

  /// Bağlam (ana sayfa, sipariş formu, taslak) yüklendi.
  final bool ready;
  final AppFailure? loadError;

  /// Seçili bayide sipariş verilebilirlik (girişte sunucudan denetlenir).
  final OrderingStatus? ordering;
  final bool checkingOrdering;

  /// Seçili bayinin ödeme seçenekleri ve ₺/L.
  final CustomerPaymentOptions? payment;
  final bool loadingPayment;
  final AppFailure? paymentError;

  /// Açılış notu ("Şablondaki 1 satır kullanılamıyor" gibi).
  final String? notice;

  /// "Devam" denendi: adımın hataları gösterilir.
  final bool showErrors;

  /// Çek / senet tutarı tahminden otomatik doluyor (kullanıcı değiştirmedi).
  final bool autoAmount;

  /// Çek / senet vadesi teslim + vadeden otomatik doluyor.
  final bool autoDue;

  Map<int, double> get prices => payment?.unitPrices ?? const {};
  PaymentOptions? get options => payment?.options;
  PaymentMethodOption? get method => options?.method(draft.payment.methodCode);
  Estimate get estimate => Estimate.of(draft, prices);

  /// Ödeme adımı gösterilir mi (seçim kapalıysa atlanır).
  bool get hasPaymentStep => options?.enabled ?? true;

  WizardState copyWith({
    OrderDraft? draft,
    bool? ready,
    AppFailure? loadError,
    bool clearLoadError = false,
    OrderingStatus? ordering,
    bool clearOrdering = false,
    bool? checkingOrdering,
    CustomerPaymentOptions? payment,
    bool clearPayment = false,
    bool? loadingPayment,
    AppFailure? paymentError,
    bool clearPaymentError = false,
    String? notice,
    bool clearNotice = false,
    bool? showErrors,
    bool? autoAmount,
    bool? autoDue,
  }) => WizardState(
    draft: draft ?? this.draft,
    ready: ready ?? this.ready,
    loadError: clearLoadError ? null : (loadError ?? this.loadError),
    ordering: clearOrdering ? null : (ordering ?? this.ordering),
    checkingOrdering: checkingOrdering ?? this.checkingOrdering,
    payment: clearPayment ? null : (payment ?? this.payment),
    loadingPayment: loadingPayment ?? this.loadingPayment,
    paymentError: clearPaymentError
        ? null
        : (paymentError ?? this.paymentError),
    notice: clearNotice ? null : (notice ?? this.notice),
    showErrors: showErrors ?? this.showErrors,
    autoAmount: autoAmount ?? this.autoAmount,
    autoDue: autoDue ?? this.autoDue,
  );
}

final orderWizardProvider =
    NotifierProvider.autoDispose<OrderWizardController, WizardState>(
      OrderWizardController.new,
    );

class OrderWizardController extends AutoDisposeNotifier<WizardState> {
  Timer? _saveTimer;
  List<CreateOrderResult> _created = const [];
  String? _docGroup;
  int _paymentSeq = 0;
  int _orderingSeq = 0;
  bool _disposed = false;
  WizardDraftStore? _store;

  /// Son durum (kapanırken saklamak için; `state` atfı burada da güncellenir).
  WizardState _mirror = const WizardState();

  @override
  set state(WizardState value) {
    _mirror = value;
    super.state = value;
  }

  @override
  WizardState build() {
    _store = ref.watch(wizardDraftStoreProvider);
    ref.onDispose(() {
      _disposed = true;
      _saveTimer?.cancel();
      // Kapanırken son hâl saklanır (başarıdan sonra taslak zaten silinmiştir).
      final last = _mirror;
      if (last.draft.dirty && last.ready) unawaited(_saveNow(last.draft));
    });
    _mirror = const WizardState();
    return _mirror;
  }

  CustomerOrdersRepository get _repo =>
      ref.read(customerOrdersRepositoryProvider);

  CustomerHomeData? get home => ref.read(customerHomeProvider).data;
  OrderFormOptions? get form => ref.read(orderFormProvider).data;

  // ------------------------------------------------------------------ Açılış

  /// Bağlamı yükler ve taslağı kurar. Bekleyen bir gönderim varsa onu bozmaz.
  Future<void> init(WizardLaunch launch, {bool hasPending = false}) async {
    try {
      final h = await _ensureHome();
      final f = await ref.read(orderFormProvider.notifier).ensure();
      if (_disposed) return;
      if (h == null || f == null) {
        final err =
            ref.read(customerHomeProvider).error ??
            ref.read(orderFormProvider).error ??
            const UnknownFailure();
        state = state.copyWith(loadError: err, ready: false);
        return;
      }
      final snap = await _store?.load();
      _created = snap?.created ?? const [];
      _docGroup = snap?.documentUploadedGroup;
      OrderDraft draft;
      String? notice;
      if (hasPending && snap != null) {
        draft = snap.draft;
      } else if (launch.hasSource) {
        final built = await _fromLaunch(launch, h, f);
        draft = built.$1;
        notice = built.$2;
        _created = const [];
        _docGroup = null;
      } else if (snap != null && !snap.draft.isBlank) {
        draft = snap.draft;
      } else {
        draft = _fresh(h, f);
      }
      if (_disposed) return;
      state = WizardState(draft: draft, ready: true, notice: notice);
      await Future.wait([
        checkOrdering(draft.stationId),
        loadPayment(applyDefaults: true),
      ]);
      if (launch.reorderId != null && !hasPending) _jumpToFirstInvalid();
    } on AppFailure catch (f) {
      if (_disposed) return;
      state = state.copyWith(loadError: f, ready: false);
    }
  }

  Future<CustomerHomeData?> _ensureHome() async {
    final ctrl = ref.read(customerHomeProvider.notifier);
    var s = ref.read(customerHomeProvider);
    if (s.data != null && !s.fromCache) return s.data;
    await ctrl.refresh();
    if (_disposed) return null;
    s = ref.read(customerHomeProvider);
    return s.data;
  }

  /// Taslağı yeniden okur (kısmi sonuçtan sonra kalan satırlar).
  Future<void> reloadFromStore() async {
    final snap = await _store?.load();
    if (snap == null || _disposed) return;
    _created = snap.created;
    _docGroup = snap.documentUploadedGroup;
    state = state.copyWith(draft: snap.draft, showErrors: false);
  }

  OrderDraft _fresh(CustomerHomeData h, OrderFormOptions f) {
    final uid = ref.read(currentUserIdProvider);
    final prefs = _prefs;
    final lastStation = uid == null
        ? null
        : prefs?.getInt(A2Keys.lastStation(uid));
    final lastPoint = uid == null ? null : prefs?.getInt(A2Keys.lastPoint(uid));
    return OrderDraft(
      stationId: _defaultStation(h, lastStation),
      lines: [
        DraftLine.create(
          productId: f.products.length == 1 ? f.products.first.id : null,
        ),
      ],
      pointId:
          f.point(lastPoint)?.id ??
          (f.deliveryPoints.isEmpty ? null : f.deliveryPoints.first.id),
      date: _defaultDate(h),
    );
  }

  PrefsStore? get _prefs {
    try {
      return ref.read(prefsStoreProvider);
    } catch (_) {
      return null;
    }
  }

  static int? _defaultStation(CustomerHomeData h, int? last) {
    if (h.stations.isEmpty) return h.stationId;
    if (h.stations.length == 1) return h.stations.first.id;
    final l = h.stationById(last);
    if (l != null && l.canOrder) return l.id;
    final def = h.stationById(h.stationId);
    if (def != null && def.canOrder) return def.id;
    for (final s in h.stations) {
      if (s.canOrder) return s.id;
    }
    return h.stationId ?? h.stations.first.id;
  }

  /// Önerilen teslim tarihi (en erkenden önce olamaz).
  static DateTime _defaultDate(CustomerHomeData? h) {
    final today = TrTime.todayStart();
    final min = h?.minDeliveryDate;
    final suggested = h?.suggestedDeliveryDate;
    var d = suggested ?? min ?? today;
    if (min != null && d.isBefore(min)) d = min;
    if (d.isBefore(today)) d = today;
    return d;
  }

  DateTime get minDate {
    final today = TrTime.todayStart();
    final min = home?.minDeliveryDate;
    return min != null && min.isAfter(today) ? min : today;
  }

  Future<(OrderDraft, String?)> _fromLaunch(
    WizardLaunch launch,
    CustomerHomeData h,
    OrderFormOptions f,
  ) async {
    final base = _fresh(h, f);
    if (launch.templateId != null) {
      final t = await _repo.template(launch.templateId!);
      final usable = t.lines
          .where(
            (l) =>
                l.isAvailable &&
                f.product(l.productId) != null &&
                f.point(l.deliveryPointId) != null,
          )
          .toList();
      final skipped = t.lines.length - usable.length;
      if (usable.isEmpty) {
        return (
          base.copyWith(templateId: t.id, origin: DraftOrigin.template),
          'Şablondaki satırlar şu an kullanılamıyor; siparişi elle tamamlayın.',
        );
      }
      final mainPoint = usable.first.deliveryPointId;
      final station = usable.first.stationId;
      final st = h.stationById(station);
      return (
        base.copyWith(
          stationId: st != null && st.canOrder ? st.id : base.stationId,
          pointId: mainPoint,
          lines: [
            for (final l in usable)
              DraftLine.create(
                productId: l.productId,
                liters: l.quantityLiters,
              ).copyWith(
                custom: l.deliveryPointId != mainPoint,
                pointId: l.deliveryPointId != mainPoint
                    ? l.deliveryPointId
                    : null,
              ),
          ],
          templateId: t.id,
          origin: DraftOrigin.template,
          dirty: true,
        ),
        skipped > 0
            ? 'Şablondaki $skipped satır şu an kullanılamadığı için eklenmedi.'
            : '“${t.name}” şablonu yüklendi; litreleri kontrol edin.',
      );
    }
    if (launch.requestId != null) {
      final r = await _repo.orderRequest(launch.requestId!);
      final failed = r.failedLines.isEmpty ? r.lines : r.failedLines;
      final usable = failed
          .where(
            (l) =>
                f.product(l.productId) != null &&
                f.point(l.deliveryPointId) != null,
          )
          .toList();
      if (usable.isEmpty) {
        return (base, 'Talepteki satırlar şu an kullanılamıyor.');
      }
      final main = usable.first;
      final today = TrTime.todayStart();
      DateTime? keepDate(DateTime? d) =>
          d != null && TrTime.dayDiff(today, d) >= 0 ? d : null;
      final mainDate = keepDate(main.requestedDeliveryDate) ?? base.date;
      final st = h.stationById(main.stationId);
      return (
        base.copyWith(
          stationId: st?.id ?? base.stationId,
          pointId: main.deliveryPointId,
          date: mainDate,
          lines: [
            for (final l in usable)
              DraftLine.create(
                productId: l.productId,
                liters: l.quantityLiters,
              ).copyWith(
                custom:
                    l.deliveryPointId != main.deliveryPointId ||
                    (keepDate(l.requestedDeliveryDate) != null &&
                        !TrTime.isSameDay(
                          keepDate(l.requestedDeliveryDate)!,
                          mainDate!,
                        )),
                pointId: l.deliveryPointId,
                date: keepDate(l.requestedDeliveryDate),
              ),
          ],
          payment: _paymentFromStored(
            r.paymentMethodCode,
            r.paymentTermDays,
            r.paymentInstallments,
            r.paymentDetailJson,
          ),
          origin: DraftOrigin.request,
          dirty: true,
        ),
        'Talep #${r.id}: siparişe dönüşmeyen ${usable.length} satır aktarıldı.',
      );
    }
    // Tekrarla: aynı ürün, litre, nokta ve ödeme; tarih bugünkü öneri.
    final o = await _repo.order(launch.reorderId!);
    final st = h.stationById(o.stationId);
    return (
      base.copyWith(
        stationId: st?.id ?? base.stationId,
        pointId: f.point(o.deliveryPointId)?.id ?? base.pointId,
        lines: [
          DraftLine.create(
            productId: f.product(o.productId)?.id,
            liters: o.quantityLiters,
          ),
        ],
        payment: _paymentFromStored(
          o.paymentMethodCode,
          o.paymentTermDays,
          o.paymentInstallments,
          o.paymentDetailJson,
        ),
        origin: DraftOrigin.reorder,
        step: WizardStep.summary,
        dirty: true,
      ),
      '${o.orderNumber} siparişi tekrarlanıyor; özeti kontrol edip gönderin.',
    );
  }

  /// Saklanan ödeme (talep / önceki sipariş). Çek / senet bilgileri yeni belge için boşaltılır.
  static DraftPayment _paymentFromStored(
    String? code,
    int? term,
    int? installments,
    String? detailJson,
  ) {
    if (code == null) return const DraftPayment();
    var fields = <String, String>{};
    if (!PaymentCodes.isInstrument(code) && detailJson != null) {
      try {
        final m = jsonDecode(detailJson);
        if (m is Map) {
          fields = {
            for (final e in m.entries)
              if (e.value != null) '${e.key}': '${e.value}',
          };
        }
      } catch (_) {}
    }
    return DraftPayment(
      methodCode: code.asciiUpper,
      termDays: term,
      installments: installments,
      fields: fields,
      touched: true,
    );
  }

  void _jumpToFirstInvalid() {
    final s = state;
    final h = home;
    final f = form;
    WizardStep step = WizardStep.summary;
    if (WizardRules.products(
      s.draft,
      stations: h?.stations ?? const [],
      form: f,
    ).any((i) => i.blocking)) {
      step = WizardStep.products;
    } else if (WizardRules.delivery(
      s.draft,
      form: f,
      minDate: minDate,
    ).any((i) => i.blocking)) {
      step = WizardStep.delivery;
    } else if (s.hasPaymentStep &&
        (WizardRules.payment(
              s.draft,
              options: s.options,
              estimate: s.estimate,
            ).any((i) => i.blocking) ||
            (s.options != null &&
                s.draft.payment.methodCode != null &&
                s.method == null))) {
      step = WizardStep.payment;
    }
    _set(s.draft.copyWith(step: step), persist: true);
  }

  // ------------------------------------------------------------------ Sunucu denetimleri

  /// Girişte ve bayi değişince sipariş verilebilirlik denetimi.
  Future<void> checkOrdering(int? stationId) async {
    if (stationId == null) return;
    final seq = ++_orderingSeq;
    state = state.copyWith(checkingOrdering: true);
    try {
      final o = await _repo.orderingStatus(stationId);
      if (_disposed || seq != _orderingSeq) return;
      state = state.copyWith(ordering: o, checkingOrdering: false);
    } on AppFailure catch (f) {
      if (_disposed || seq != _orderingSeq) return;
      AppLog.debug('Sipariş verilebilirlik denetlenemedi: $f');
      final st = home?.stationById(stationId);
      state = state.copyWith(
        checkingOrdering: false,
        ordering: st == null
            ? null
            : OrderingStatus(
                stationId: st.id,
                canOrder: st.canOrder,
                blockReason: st.blockReason,
              ),
      );
    }
  }

  /// Seçili bayinin ödeme seçenekleri ve fiyatları.
  Future<void> loadPayment({bool applyDefaults = false}) async {
    final d = state.draft;
    final station = d.stationId;
    if (station == null) return;
    final seq = ++_paymentSeq;
    state = state.copyWith(loadingPayment: true, clearPaymentError: true);
    final products = {
      for (final p in form?.products ?? const <ProductOption>[]) p.id,
      for (final l in d.lines)
        if (l.productId != null) l.productId!,
    };
    try {
      final o = await _repo.paymentOptions(
        stationId: station,
        productIds: products,
      );
      if (_disposed || seq != _paymentSeq) return;
      state = state.copyWith(payment: o, loadingPayment: false);
      _applyPaymentDefaults(force: applyDefaults);
    } on AppFailure catch (f) {
      if (_disposed || seq != _paymentSeq) return;
      state = state.copyWith(loadingPayment: false, paymentError: f);
    }
  }

  void _applyPaymentDefaults({bool force = false}) {
    final s = state;
    final o = s.options;
    if (o == null || !o.enabled || o.methods.isEmpty) return;
    var p = s.draft.payment;
    if (p.methodCode != null && o.method(p.methodCode) == null) {
      // Önceki yöntem bu bayide yok.
      p = const DraftPayment();
    }
    if (p.methodCode == null && !p.cleared) {
      final uid = ref.read(currentUserIdProvider);
      final last = uid == null
          ? null
          : _prefs?.getString(A2Keys.lastMethod(uid));
      final code = o.method(last)?.code ?? o.method(o.defaultMethodCode)?.code;
      if (code != null) {
        _selectMethod(code, base: p, persist: force, markDirty: false);
        return;
      }
    }
    if (p != s.draft.payment) {
      _set(s.draft.copyWith(payment: p), persist: true, markDirty: false);
    }
    _syncInstrument();
  }

  // ------------------------------------------------------------------ Düzenleme

  void _set(OrderDraft d, {bool persist = true, bool markDirty = true}) {
    state = state.copyWith(draft: markDirty ? d.copyWith(dirty: true) : d);
    if (persist && state.ready) _scheduleSave();
  }

  void setStation(int id) {
    if (state.draft.stationId == id) return;
    _set(state.draft.copyWith(stationId: id));
    state = state.copyWith(clearPayment: true, clearOrdering: true);
    unawaited(checkOrdering(id));
    unawaited(loadPayment());
  }

  void addLine() {
    final lines = state.draft.lines;
    if (lines.length >= WizardRules.maxLines) return;
    _set(state.draft.copyWith(lines: [...lines, DraftLine.create()]));
  }

  void removeLine(String uid) {
    final lines = state.draft.lines.where((l) => l.uid != uid).toList();
    _set(
      state.draft.copyWith(lines: lines.isEmpty ? [DraftLine.create()] : lines),
    );
    _syncInstrument();
  }

  void updateLine(
    String uid, {
    int? productId,
    double? liters,
    bool clearLiters = false,
  }) {
    final lines = [
      for (final l in state.draft.lines)
        l.uid == uid
            ? l.copyWith(
                productId: productId,
                liters: liters,
                clearLiters: clearLiters,
              )
            : l,
    ];
    _set(state.draft.copyWith(lines: lines));
    if (productId != null && !state.prices.containsKey(productId)) {
      unawaited(loadPayment());
    }
    _syncInstrument();
  }

  void setLineCustom(String uid, bool custom) {
    final d = state.draft;
    final lines = [
      for (final l in d.lines)
        l.uid == uid
            ? l.copyWith(
                custom: custom,
                pointId: l.pointId ?? d.pointId,
                date: l.date ?? d.date,
              )
            : l,
    ];
    _set(d.copyWith(lines: lines));
  }

  void setLinePoint(String uid, int pointId) {
    final lines = [
      for (final l in state.draft.lines)
        l.uid == uid ? l.copyWith(pointId: pointId) : l,
    ];
    _set(state.draft.copyWith(lines: lines));
  }

  void setLineDate(String uid, DateTime date) {
    final lines = [
      for (final l in state.draft.lines)
        l.uid == uid ? l.copyWith(date: date) : l,
    ];
    _set(state.draft.copyWith(lines: lines));
  }

  void setPoint(int id) => _set(state.draft.copyWith(pointId: id));

  void setDate(DateTime date) {
    _set(state.draft.copyWith(date: date));
    _syncInstrument(dateChanged: true);
  }

  void selectMethod(String code) => _selectMethod(code);

  void _selectMethod(
    String code, {
    DraftPayment? base,
    bool persist = true,
    bool markDirty = true,
  }) {
    final o = state.options;
    final m = o?.method(code);
    if (m == null) return;
    final prev = base ?? state.draft.payment;
    final sameMethod = prev.methodCode == code;
    var term = sameMethod ? prev.termDays : null;
    if (m.hasTerm) {
      term ??= WizardRules.defaultTerm(m);
    } else {
      term = 0;
    }
    var inst = sameMethod ? prev.installments : null;
    if (m.hasInstallments) {
      inst = m.installmentOptions.contains(inst)
          ? inst
          : m.installmentOptions.first;
    } else {
      inst = null;
    }
    final p = DraftPayment(
      methodCode: code,
      termDays: term,
      installments: inst,
      fields: sameMethod ? prev.fields : const {},
      receiptPath: code == PaymentCodes.transfer ? prev.receiptPath : null,
      touched: true,
    );
    state = state.copyWith(autoAmount: true, autoDue: true);
    _set(
      state.draft.copyWith(payment: p),
      persist: persist,
      markDirty: markDirty || state.draft.dirty,
    );
    _syncInstrument();
  }

  /// Ödemeyi belirtmeden gönder.
  void clearMethod() {
    _set(
      state.draft.copyWith(
        payment: const DraftPayment(cleared: true, touched: true),
      ),
    );
  }

  void setTerm(int days) {
    final p = state.draft.payment.copyWith(termDays: days);
    _set(state.draft.copyWith(payment: p));
    _syncInstrument(termChanged: true);
  }

  void setInstallments(int n) => _set(
    state.draft.copyWith(
      payment: state.draft.payment.copyWith(installments: n),
    ),
  );

  /// Yöntem alanı. Çek / senet vadesi değişince vade (gün) belgeden hesaplanır (web ile aynı).
  void setField(String key, String value) {
    final d = state.draft;
    final fields = {...d.payment.fields, key: value};
    var p = d.payment.copyWith(fields: fields);
    final m = state.method;
    if (key == 'amount') state = state.copyWith(autoAmount: false);
    if (key == 'dueDate') {
      state = state.copyWith(autoDue: false);
      final due = TrTime.parseDate(value);
      if (m != null &&
          m.isInstrument &&
          m.hasTerm &&
          due != null &&
          d.date != null) {
        if (WizardRules.instrumentDueError(m, d.date!, due) == null) {
          p = p.copyWith(termDays: WizardRules.termFromDue(m, d.date!, due));
        }
      }
    }
    _set(d.copyWith(payment: p));
  }

  void setReceipt(String? path) => _set(
    state.draft.copyWith(
      payment: path == null
          ? state.draft.payment.copyWith(clearReceipt: true)
          : state.draft.payment.copyWith(receiptPath: path),
    ),
  );

  void setNote(String note) => _set(state.draft.copyWith(note: note));

  void setSaveAsTemplate(bool on) =>
      _set(state.draft.copyWith(saveAsTemplate: on));

  void setTemplateName(String name) =>
      _set(state.draft.copyWith(templateName: name));

  /// "Şablondan başla" (sihirbaz içinde).
  Future<String?> applyTemplate(int templateId) async {
    final h = home;
    final f = form;
    if (h == null || f == null) return null;
    try {
      final built = await _fromLaunch(
        WizardLaunch(templateId: templateId),
        h,
        f,
      );
      if (_disposed) return null;
      final d = built.$1.copyWith(
        payment: state.draft.payment,
        date: state.draft.date,
        step: WizardStep.products,
      );
      _set(d);
      if (d.stationId != null) unawaited(loadPayment());
      state = state.copyWith(notice: built.$2);
      _syncInstrument();
      return built.$2;
    } on AppFailure catch (e) {
      return e.message;
    }
  }

  /// Çek / senet tutarı ve vadesi: kullanıcı değiştirmedikçe tahminden ve teslim + vadeden dolar.
  void _syncInstrument({bool dateChanged = false, bool termChanged = false}) {
    final s = state;
    final m = s.method;
    if (m == null || !m.isInstrument) return;
    final d = s.draft;
    final fields = {...d.payment.fields};
    var changed = false;
    if (s.autoAmount && m.field('amount') != null) {
      final est = s.estimate.value;
      final text = est == null
          ? ''
          : Fmt.number(est, minFraction: 2, maxFraction: 2);
      if ((fields['amount'] ?? '') != text) {
        fields['amount'] = text;
        changed = true;
      }
    }
    var term = d.payment.termDays;
    if (m.field('dueDate') != null && d.date != null) {
      final due = TrTime.parseDate(fields['dueDate']);
      if (s.autoDue || due == null) {
        final t = term ?? WizardRules.defaultTerm(m) ?? m.minTermDays;
        final iso = TrTime.isoDate(TrTime.addDays(d.date!, t));
        if (fields['dueDate'] != iso) {
          fields['dueDate'] = iso;
          changed = true;
        }
      } else if (dateChanged && !termChanged) {
        // Kullanıcının vadesi korunur; vade (gün) yeni teslim tarihine göre hesaplanır.
        if (WizardRules.instrumentDueError(m, d.date!, due) == null) {
          final t = WizardRules.termFromDue(m, d.date!, due);
          if (t != term) {
            term = t;
            changed = true;
          }
        }
      }
    }
    if (!changed) return;
    _set(
      d.copyWith(
        payment: d.payment.copyWith(fields: fields, termDays: term),
      ),
      markDirty: d.dirty,
    );
  }

  // ------------------------------------------------------------------ Adımlar

  List<WizardStep> get steps => [
    WizardStep.products,
    WizardStep.delivery,
    if (state.hasPaymentStep) WizardStep.payment,
    WizardStep.summary,
  ];

  /// Adımın engelleyen hataları.
  List<RuleIssue> issuesFor(WizardStep step) {
    final s = state;
    return switch (step) {
      WizardStep.products => WizardRules.products(
        s.draft,
        stations: home?.stations ?? const [],
        form: form,
      ),
      WizardStep.delivery => WizardRules.delivery(
        s.draft,
        form: form,
        minDate: minDate,
      ),
      WizardStep.payment => [
        ...WizardRules.payment(
          s.draft,
          options: s.options,
          estimate: s.estimate,
        ),
        if (s.loadingPayment && s.payment == null)
          const RuleIssue('Ödeme seçenekleri yükleniyor…', field: 'loading'),
      ],
      WizardStep.summary => [
        if (s.draft.note.length > WizardRules.maxNote)
          const RuleIssue('Not en çok 1000 karakter olabilir.', field: 'note'),
        if (s.draft.saveAsTemplate && s.draft.templateName.trim().isEmpty)
          const RuleIssue('Şablon adı girin.', field: 'templateName'),
        if (s.draft.templateName.length > WizardRules.maxTemplateName)
          const RuleIssue(
            'Şablon adı en çok 100 karakter olabilir.',
            field: 'templateName',
          ),
      ],
    };
  }

  /// Seçili bayide sipariş engeli (girişte denetlenir).
  String? get orderingBlock {
    final o = state.ordering;
    if (o != null && !o.canOrder) {
      return o.blockReason ?? 'Bu bayide şu an sipariş veremezsiniz.';
    }
    return null;
  }

  /// İleri. Hata varsa adımda kalır ve hataları gösterir.
  bool next() {
    final s = state;
    final order = steps;
    final i = order.indexOf(s.draft.step);
    final blocking = issuesFor(s.draft.step).where((x) => x.blocking).toList();
    if (blocking.isNotEmpty ||
        (s.draft.step == WizardStep.products && orderingBlock != null)) {
      state = state.copyWith(showErrors: true);
      return false;
    }
    if (i < 0 || i >= order.length - 1) return true;
    state = state.copyWith(showErrors: false);
    _set(s.draft.copyWith(step: order[i + 1]), markDirty: s.draft.dirty);
    return true;
  }

  /// Geri; ilk adımdaysa false (sayfa kapanır).
  bool back() {
    final order = steps;
    final i = order.indexOf(state.draft.step);
    if (i <= 0) return false;
    state = state.copyWith(showErrors: false);
    _set(
      state.draft.copyWith(step: order[i - 1]),
      markDirty: state.draft.dirty,
    );
    return true;
  }

  /// Önceki adımlara dokunarak dönüş.
  void goTo(WizardStep step) {
    final order = steps;
    if (order.indexOf(step) >= order.indexOf(state.draft.step)) return;
    state = state.copyWith(showErrors: false);
    _set(state.draft.copyWith(step: step), markDirty: state.draft.dirty);
  }

  /// [step] adımına gider ve hatalarını gösterir (gönderimde ilk hatalı adım).
  void showErrorsAt(WizardStep step) {
    _set(state.draft.copyWith(step: step), markDirty: state.draft.dirty);
    state = state.copyWith(showErrors: true);
  }

  /// Tüm adımlar geçerli mi (gönderimden önce).
  bool get allValid =>
      steps.every((st) => issuesFor(st).where((x) => x.blocking).isEmpty);

  /// Şirket içi onaya düşecek mi (Talep eden; sunucu kuralının portu).
  bool get companyRequestPredicted {
    final rule = home?.companyApproval;
    if (rule == null) return false;
    return rule.predicts(
      totalLiters: state.draft.totalLiters,
      estimatedAmount: state.estimate.value,
    );
  }

  PlaceOrderRequest buildRequest() => WizardRules.buildRequest(
    state.draft,
    options: state.options,
    companyRequestPredicted: companyRequestPredicted,
  );

  /// Önceki kısmi gönderimlerde oluşan siparişler.
  List<CreateOrderResult> get created => _created;
  String? get documentUploadedGroup => _docGroup;

  // ------------------------------------------------------------------ Kayıt

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_saveNow());
    });
  }

  Future<void> _saveNow([OrderDraft? draft]) async {
    final store = _store;
    if (store == null) return;
    final d = draft ?? _mirror.draft;
    if (!d.dirty) return;
    final existing = await store.load();
    if (existing?.pending != null) return; // gönderim sürerken taslak sabit
    await store.save(
      WizardSnapshot(
        draft: d,
        created: _created,
        documentUploadedGroup: _docGroup,
      ),
    );
    if (!_disposed) ref.read(draftRevisionProvider.notifier).bump();
  }

  /// "Taslak olarak sakla".
  Future<void> saveDraftNow() async {
    _saveTimer?.cancel();
    await _saveNow();
  }

  /// "Çık": taslak silinir.
  Future<void> discardDraft() async {
    _saveTimer?.cancel();
    state = state.copyWith(draft: state.draft.copyWith(dirty: false));
    final store = _store;
    final existing = await store?.load();
    if (existing?.pending == null) await store?.clear();
    if (!_disposed) ref.read(draftRevisionProvider.notifier).bump();
  }
}
