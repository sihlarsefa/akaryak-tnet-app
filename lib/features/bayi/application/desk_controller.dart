import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/cache_store.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_number.dart';
import '../../../core/utils/tr_time.dart';
import '../data/bayi_json.dart';
import '../data/bayi_repository.dart';
import '../data/desk_models.dart';
import 'bayi_runtime.dart';

/// Satır taslağı: kullanıcının yazdığı ₺/L ve seçtiği teslim günü (boşsa satırın varsayılan günü).
@immutable
class DeskDraft {
  const DeskDraft({this.priceText = '', this.price, this.date});

  final String priceText;
  final double? price;
  final DateTime? date;

  bool get isEmpty => price == null && date == null && priceText.isEmpty;

  DeskDraft copyWith({
    String? priceText,
    Object? price = _keep,
    Object? date = _keep,
  }) => DeskDraft(
    priceText: priceText ?? this.priceText,
    price: price == _keep ? this.price : price as double?,
    date: date == _keep ? this.date : date as DateTime?,
  );
}

const Object _keep = Object();

/// Gönderim sonucu özeti (sonuç sayfası).
@immutable
class DeskSubmitSummary {
  const DeskSubmitSummary({required this.results, required this.rows});

  final List<DeskSubmitResult> results;

  /// Gönderilen satırların anlık görüntüsü (sonuç listesinde sipariş no ve cari için).
  final Map<int, DeskRow> rows;

  int count(DeskOutcome o) => results.where((r) => r.outcome == o).length;
  int get quoted => count(DeskOutcome.quoted);
  int get routedToFinance => count(DeskOutcome.routedToFinance);
  int get failed => results.length - quoted - routedToFinance;
}

/// Teklif masası durumu.
@immutable
class DeskState {
  const DeskState({
    this.view = DeskView.all,
    this.sort = DeskSort.expiry,
    this.customerId,
    this.productId,
    this.list = const PagedList.initial(),
    this.header,
    this.counts = const DeskCounts(),
    this.today = const DeskToday(),
    this.deadlines = const {},
    this.fromCache = false,
    this.facets = DeskFacets.empty,
    this.drafts = const {},
    this.selected = const {},
    this.outcomes = const {},
    this.rowErrors = const {},
    this.submitting = false,
    this.checking = false,
  });

  final DeskView view;
  final DeskSort sort;
  final int? customerId;
  final int? productId;
  final PagedList<DeskRow> list;
  final DeskHeader? header;
  final DeskCounts counts;
  final DeskToday today;

  /// Sipariş → süre sonu anı (yalnızca süre dolumu açıkken; `secondsLeft` + yanıt anı).
  final Map<int, DateTime> deadlines;
  final bool fromCache;
  final DeskFacets facets;
  final Map<int, DeskDraft> drafts;
  final Set<int> selected;

  /// Son gönderimin satır sonuçları (listede kalan satırlarda gösterilir).
  final Map<int, DeskSubmitResult> outcomes;

  /// Gönderim öncesi istemci doğrulaması (satır → mesaj).
  final Map<int, String> rowErrors;
  final bool submitting;

  /// Belirsiz sonuç: aynı anahtarla tekrar deneniyor ("Teklifler kontrol ediliyor").
  final bool checking;

  List<DeskRow> get rows => list.items;
  bool get expiryEnabled => header?.expiryEnabled ?? false;
  bool get isFiltered => customerId != null || productId != null;

  DeskDraft draftOf(int orderId) => drafts[orderId] ?? const DeskDraft();

  DeskState copyWith({
    DeskView? view,
    DeskSort? sort,
    Object? customerId = _keep,
    Object? productId = _keep,
    PagedList<DeskRow>? list,
    Object? header = _keep,
    DeskCounts? counts,
    DeskToday? today,
    Map<int, DateTime>? deadlines,
    bool? fromCache,
    DeskFacets? facets,
    Map<int, DeskDraft>? drafts,
    Set<int>? selected,
    Map<int, DeskSubmitResult>? outcomes,
    Map<int, String>? rowErrors,
    bool? submitting,
    bool? checking,
  }) => DeskState(
    view: view ?? this.view,
    sort: sort ?? this.sort,
    customerId: customerId == _keep ? this.customerId : customerId as int?,
    productId: productId == _keep ? this.productId : productId as int?,
    list: list ?? this.list,
    header: header == _keep ? this.header : header as DeskHeader?,
    counts: counts ?? this.counts,
    today: today ?? this.today,
    deadlines: deadlines ?? this.deadlines,
    fromCache: fromCache ?? this.fromCache,
    facets: facets ?? this.facets,
    drafts: drafts ?? this.drafts,
    selected: selected ?? this.selected,
    outcomes: outcomes ?? this.outcomes,
    rowErrors: rowErrors ?? this.rowErrors,
    submitting: submitting ?? this.submitting,
    checking: checking ?? this.checking,
  );
}

/// Teklif masası (`bayi/quote-desk*`): görünüm / sıralama / cari / ürün süzgeci, satır içi fiyat ve gün,
/// çoklu seçim, "Önerileri uygula", "Seçilenlere aynı fiyat/tarih", toplu gönderim ve satır sonuçları.
final quoteDeskProvider = NotifierProvider<QuoteDeskController, DeskState>(
  QuoteDeskController.new,
);

class QuoteDeskController extends Notifier<DeskState> {
  int _epoch = 0;
  String? _userId;

  static const maxUnitPrice = 999999.0;
  static const maxDaysAhead = 365;

  BayiRepository get _repo => ref.read(bayiRepositoryProvider);

  @override
  DeskState build() {
    _userId = ref.watch(currentUserIdProvider);
    final sub = ref.read(bayiChangesProvider).stream.listen((c) {
      // Sipariş ayrıntısından verilen tekil teklif masayı değiştirir; masanın kendi gönderimi
      // `orders` yayınlar ve masayı kendisi tazeler.
      if (c == BayiChange.quotes) unawaited(reload(silent: true));
    });
    ref.onDispose(sub.cancel);
    if (_userId == null) return const DeskState(list: PagedList());
    Future.microtask(() async {
      await reload(useCache: true);
      await loadFacets();
    });
    return const DeskState();
  }

  String? get _cacheKey =>
      _userId == null ? null : CacheKeys.user(_userId!, 'bayi.desk');

  bool get _isDefaultQuery =>
      state.view == DeskView.all &&
      state.sort == DeskSort.expiry &&
      state.customerId == null &&
      state.productId == null;

  // ------------------------------------------------------------------ Yükleme

  /// İlk sayfadan yükler. [silent]: içerik kalır, üstte ince çubuk.
  Future<void> reload({bool silent = false, bool useCache = false}) async {
    if (_userId == null) return;
    final epoch = ++_epoch;
    final hasRows = state.rows.isNotEmpty;
    final keep = silent && hasRows;
    state = state.copyWith(
      list: keep
          ? state.list.copyWith(refreshing: true, error: null, moreError: null)
          : const PagedList(loading: true),
    );
    if (useCache && !hasRows && _isDefaultQuery) {
      final cached = await ref.read(cacheStoreProvider).read(_cacheKey!);
      if (epoch != _epoch) return;
      if (cached != null) {
        final page = DeskPage.fromJson(
          cached.value,
          receivedAt: cached.storedAt,
        );
        _apply(
          page,
          append: false,
          fromCache: true,
          refreshing: true,
          at: cached.storedAt,
        );
      }
    }
    try {
      final r = await _repo.quoteDesk(
        view: state.view,
        sort: state.sort,
        customerId: state.customerId,
        productId: state.productId,
      );
      if (epoch != _epoch) return;
      _apply(r.page, append: false);
      if (_isDefaultQuery && _cacheKey != null) {
        await ref
            .read(cacheStoreProvider)
            .write(
              _cacheKey!,
              r.raw,
              userId: _userId,
              ttl: const Duration(days: 2),
            );
      }
    } catch (e) {
      if (epoch != _epoch) return;
      final f = AppFailure.from(e);
      state = state.copyWith(
        list: state.rows.isNotEmpty
            ? state.list.copyWith(refreshing: false, loading: false, error: f)
            : PagedList<DeskRow>(error: f),
      );
    }
  }

  /// Sonraki sayfa.
  Future<void> loadMore() async {
    final l = state.list;
    if (!l.hasMore || l.loadingMore || l.loading || l.refreshing) return;
    final epoch = _epoch;
    state = state.copyWith(
      list: l.copyWith(loadingMore: true, moreError: null),
    );
    try {
      final r = await _repo.quoteDesk(
        view: state.view,
        sort: state.sort,
        customerId: state.customerId,
        productId: state.productId,
        page: l.page + 1,
      );
      if (epoch != _epoch) return;
      _apply(r.page, append: true);
    } catch (e) {
      if (epoch != _epoch) return;
      state = state.copyWith(
        list: state.list.copyWith(
          loadingMore: false,
          moreError: AppFailure.from(e),
        ),
      );
    }
  }

  void _apply(
    DeskPage page, {
    required bool append,
    bool fromCache = false,
    bool refreshing = false,
    DateTime? at,
  }) {
    final existing = append ? state.rows : const <DeskRow>[];
    final seen = <int>{for (final r in existing) r.orderId};
    final rows = [
      ...existing,
      for (final r in page.rows)
        if (seen.add(r.orderId)) r,
    ];
    final deadlines = <int, DateTime>{if (append) ...state.deadlines};
    if (!append) deadlines.clear();
    if (page.header.expiryEnabled) {
      for (final r in page.rows) {
        final s = r.secondsLeft;
        if (s != null) {
          deadlines[r.orderId] = page.receivedAt.add(Duration(seconds: s));
        }
      }
    }
    final ids = {for (final r in rows) r.orderId};
    state = state.copyWith(
      list: PagedList<DeskRow>(
        items: List.unmodifiable(rows),
        page: page.page,
        hasMore: page.hasMore,
        totalCount: page.totalCount,
        refreshing: refreshing,
        updatedAt: at ?? DateTime.now().toUtc(),
      ),
      header: page.header,
      counts: page.counts,
      today: page.today,
      deadlines: Map.unmodifiable(deadlines),
      fromCache: fromCache,
      // Listede kalmayan satırların seçimi ve sonuçları düşer; taslaklar (yazılan fiyatlar) kalır.
      selected: Set.unmodifiable(state.selected.where(ids.contains)),
      outcomes: Map.unmodifiable(
        Map.fromEntries(
          state.outcomes.entries.where((e) => ids.contains(e.key)),
        ),
      ),
    );
  }

  /// Cari / ürün seçenekleri (yalnızca bekleyen siparişi olanlar). Hata sessizdir.
  Future<void> loadFacets() async {
    try {
      final f = await _repo.quoteDeskFacets();
      state = state.copyWith(facets: f);
    } catch (_) {
      // Süzgeç seçenekleri yoksa süzgeç düğmeleri boş liste gösterir.
    }
  }

  // ------------------------------------------------------------------ Süzgeçler

  void setView(DeskView v) {
    if (v == state.view) return;
    state = state.copyWith(view: v);
    unawaited(reload());
  }

  void setSort(DeskSort s) {
    if (s == state.sort) return;
    state = state.copyWith(sort: s);
    unawaited(reload());
  }

  void setCustomer(int? id) {
    if (id == state.customerId) return;
    state = state.copyWith(customerId: id);
    unawaited(reload());
  }

  void setProduct(int? id) {
    if (id == state.productId) return;
    state = state.copyWith(productId: id);
    unawaited(reload());
  }

  void clearFilters() {
    if (!state.isFiltered) return;
    state = state.copyWith(customerId: null, productId: null);
    unawaited(reload());
  }

  // ------------------------------------------------------------------ Seçim

  void toggle(int orderId) {
    final next = Set<int>.of(state.selected);
    if (!next.remove(orderId)) next.add(orderId);
    state = state.copyWith(
      selected: Set.unmodifiable(next),
      rowErrors: _without(state.rowErrors, orderId),
    );
  }

  void selectAll() => state = state.copyWith(
    selected: Set.unmodifiable({for (final r in state.rows) r.orderId}),
  );

  void clearSelection() =>
      state = state.copyWith(selected: const {}, rowErrors: const {});

  // ------------------------------------------------------------------ Taslaklar

  /// Satıra yazılan fiyat (Türkçe biçim). Fiyat yazılan satır seçilir.
  void setPrice(int orderId, String text) {
    final parsed = TrNumber.parse(text);
    final drafts = Map<int, DeskDraft>.of(state.drafts);
    drafts[orderId] = state
        .draftOf(orderId)
        .copyWith(priceText: text, price: parsed);
    final selected = Set<int>.of(state.selected);
    if (parsed != null && parsed > 0) selected.add(orderId);
    state = state.copyWith(
      drafts: Map.unmodifiable(drafts),
      selected: Set.unmodifiable(selected),
      rowErrors: _without(state.rowErrors, orderId),
    );
  }

  void setDate(int orderId, DateTime date) {
    final drafts = Map<int, DeskDraft>.of(state.drafts);
    drafts[orderId] = state
        .draftOf(orderId)
        .copyWith(date: TrTime.startOfDay(date));
    state = state.copyWith(
      drafts: Map.unmodifiable(drafts),
      rowErrors: _without(state.rowErrors, orderId),
    );
  }

  /// Satırın gönderilecek teslim günü: seçilen ya da sunucunun varsayılanı (geçmişse bugün).
  DateTime effectiveDate(DeskRow row) {
    final d = state.draftOf(row.orderId).date ?? row.defaultDeliveryDate;
    final today = TrTime.todayStart();
    if (d == null || d.isBefore(today)) return today;
    return d;
  }

  /// "Önerileri uygula": seçili satırlara (seçim yoksa tüm satırlara) önerilen ₺/L yazılır; öneri
  /// alan satırlar seçilir. Dönen değer: öneri uygulanan satır sayısı.
  int applySuggestions() {
    final targets = state.selected.isNotEmpty
        ? state.rows.where((r) => state.selected.contains(r.orderId))
        : state.rows;
    final drafts = Map<int, DeskDraft>.of(state.drafts);
    final selected = Set<int>.of(state.selected);
    var applied = 0;
    for (final row in targets) {
      // Revize satırında önceki teklif yazılmaz (müşterinin geri çevirdiği fiyat, v4 tur 2).
      final s = row.offeredUnitPrice;
      if (s == null || s <= 0) continue;
      drafts[row.orderId] = state
          .draftOf(row.orderId)
          .copyWith(priceText: formatUnitPrice(s), price: s);
      selected.add(row.orderId);
      applied++;
    }
    state = state.copyWith(
      drafts: Map.unmodifiable(drafts),
      selected: Set.unmodifiable(selected),
      rowErrors: const {},
    );
    return applied;
  }

  /// "Seçilenlere aynı fiyat/tarih": verilen fiyat ve/veya gün seçili satırların tümüne yazılır.
  int applySame({double? price, DateTime? date}) {
    if (state.selected.isEmpty || (price == null && date == null)) return 0;
    final drafts = Map<int, DeskDraft>.of(state.drafts);
    for (final id in state.selected) {
      var d = state.draftOf(id);
      if (price != null) {
        d = d.copyWith(priceText: formatUnitPrice(price), price: price);
      }
      if (date != null) d = d.copyWith(date: TrTime.startOfDay(date));
      drafts[id] = d;
    }
    state = state.copyWith(
      drafts: Map.unmodifiable(drafts),
      rowErrors: const {},
    );
    return state.selected.length;
  }

  /// Seçili satırlardan gönderilmeye hazır olanlar (fiyat yazılmış).
  int get readyCount => state.rows
      .where((r) => state.selected.contains(r.orderId))
      .where((r) => (state.draftOf(r.orderId).price ?? 0) > 0)
      .length;

  /// Satır doğrulaması (sunucunun `QuoteDeskRules.Validate` kuralları). Geçerliyse null.
  String? validate(DeskRow row) {
    final price = state.draftOf(row.orderId).price;
    if (price == null) return 'Birim fiyat girin.';
    if (price <= 0) return 'Birim fiyat sıfırdan büyük olmalı.';
    if (price > maxUnitPrice) {
      return 'Birim fiyat en fazla 999.999 ₺/L olabilir.';
    }
    final scaled = price * 10000;
    if ((scaled - scaled.roundToDouble()).abs() > 1e-6) {
      return 'Birim fiyat en fazla 4 ondalık basamak içerebilir.';
    }
    final date = effectiveDate(row);
    final today = TrTime.todayStart();
    if (TrTime.dayDiff(today, date) < 0) {
      return 'Teslim tarihi bugünden önce olamaz.';
    }
    if (TrTime.dayDiff(today, date) > maxDaysAhead) {
      return 'Teslim tarihi en fazla bir yıl sonrası olabilir.';
    }
    return null;
  }

  // ------------------------------------------------------------------ Gönderim

  /// Seçili satırları gönderir. İstemci doğrulaması geçmeyen satır varsa gönderilmez ve
  /// [DeskState.rowErrors] dolar (dönüş null). Sunucu hatası `AppFailure` olarak fırlar.
  Future<DeskSubmitSummary?> submit() async {
    if (state.submitting) return null;
    final chosen = [
      for (final r in state.rows)
        if (state.selected.contains(r.orderId)) r,
    ];
    if (chosen.isEmpty) return null;
    final errors = <int, String>{};
    for (final r in chosen) {
      final e = validate(r);
      if (e != null) errors[r.orderId] = e;
    }
    final max = state.header?.maxBatch ?? 50;
    if (chosen.length > max) {
      throw BusinessFailure('Tek seferde en çok $max sipariş gönderilebilir.');
    }
    if (errors.isNotEmpty) {
      state = state.copyWith(rowErrors: Map.unmodifiable(errors));
      return null;
    }
    final items = [
      for (final r in chosen)
        DeskSubmitItem(
          orderId: r.orderId,
          unitPrice: double.parse(
            state.draftOf(r.orderId).price!.toStringAsFixed(4),
          ),
          deliveryDate: BayiJson.isoDate(effectiveDate(r)),
        ),
    ];
    final snapshot = {for (final r in chosen) r.orderId: r};
    final intent =
        'desk:${items.map((i) => '${i.orderId}=${i.unitPrice}@${i.deliveryDate}').join(',')}';
    state = state.copyWith(
      submitting: true,
      checking: false,
      rowErrors: const {},
    );
    List<DeskSubmitResult> results = const [];
    try {
      await runIdempotent(
        ledger: ref.read(bayiIdempotencyProvider),
        intent: intent,
        delays: ref.read(bayiRetryDelaysProvider),
        onChecking: () => state = state.copyWith(checking: true),
        call: (key) async {
          results = await _repo.submitQuotes(items, idempotencyKey: key);
        },
      );
    } catch (e) {
      state = state.copyWith(submitting: false, checking: false);
      rethrow;
    }

    final outcomes = Map<int, DeskSubmitResult>.of(state.outcomes);
    final drafts = Map<int, DeskDraft>.of(state.drafts);
    final selected = Set<int>.of(state.selected);
    for (final r in results) {
      outcomes[r.orderId] = r;
      if (r.outcome == DeskOutcome.quoted ||
          r.outcome == DeskOutcome.routedToFinance) {
        drafts.remove(r.orderId);
        selected.remove(r.orderId);
      }
    }
    state = state.copyWith(
      submitting: false,
      checking: false,
      outcomes: Map.unmodifiable(outcomes),
      drafts: Map.unmodifiable(drafts),
      selected: Set.unmodifiable(selected),
    );
    ref.read(bayiChangesProvider).emit(const [BayiChange.orders]);
    // Gönderim sonrası masa ve sayılar tazelenir (teklif verilenler masadan düşer).
    unawaited(reload(silent: true));
    unawaited(loadFacets());
    return DeskSubmitSummary(
      results: List.unmodifiable(results),
      rows: snapshot,
    );
  }

  /// Son gönderim sonuçlarını temizler.
  void clearOutcomes() => state = state.copyWith(outcomes: const {});

  static Map<int, String> _without(Map<int, String> m, int key) {
    if (!m.containsKey(key)) return m;
    return Map.unmodifiable(Map.of(m)..remove(key));
  }
}

/// ₺/L girişi için Türkçe metin (`42,35`, `42,1255`).
String formatUnitPrice(double v) =>
    Fmt.number(v, minFraction: 2, maxFraction: 4);
