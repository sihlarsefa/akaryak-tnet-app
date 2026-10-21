import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/offline/cache_store.dart';
import '../../../core/utils/tr_time.dart';
import 'driver_models.dart';

/// Bir sekmenin sayfalı listesi (önbellekten geldiyse [storedAt] dolu).
class DriverListData {
  const DriverListData({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.totalPages,
    this.storedAt,
  });

  final List<DriverShipmentRow> items;
  final int totalCount;
  final int page;
  final int totalPages;

  /// Önbelleğe yazıldığı an (UTC); sunucudan yeni geldiyse null.
  final DateTime? storedAt;

  bool get hasMore => page < totalPages;

  JsonMap toJson() => {
    'items': [for (final i in items) i.raw],
    'totalCount': totalCount,
    'pageNumber': page,
    'totalPages': totalPages,
  };

  static DriverListData fromJson(Object? json, {DateTime? storedAt}) {
    final r = JsonReader.of(json);
    final items = r.list('items', DriverShipmentRow.fromJson);
    return DriverListData(
      items: List.unmodifiable(items),
      totalCount: r.integer('totalCount', items.length),
      page: r.integer('pageNumber', 1),
      totalPages: r.integer('totalPages', 1),
      storedAt: storedAt,
    );
  }
}

/// Önbellekten okunan ayrıntı.
class CachedDetail {
  const CachedDetail(this.detail, this.storedAt);
  final DriverShipmentDetail detail;
  final DateTime storedAt;
}

/// Şoför uçları (spec B.10) + çevrimdışı önbellek (spec C.4a: şoför listeleri ve ayrıntıları).
///
/// - `GET driver/shipments?scope=&page=&pageSize=` → `PagedResult<DriverShipmentRowDto>`.
/// - `GET driver/shipments/{id}` → `DriverShipmentDetailDto`.
/// - Yola çıkış ve teslim bekleyen işlemlerle gider (`driver_outbox.dart`).
///
/// "Bugün" sekmesi sunucunun `today` kapsamı ile `active` kapsamındaki gecikmiş planları
/// (plan günü geçmiş, yola çıkılmamış) birleştirir: hiçbir açık teslimat sekmelerin dışında kalmaz.
class DriverRepository {
  DriverRepository({required this.api, required this.cache});

  final ApiClient api;
  final CacheStore cache;

  static const pageSize = 25;

  /// "Bugün" tek sayfadır (bir günde 100'den fazla teslimat beklenmez).
  static const todayPageSize = 100;

  static String listKey(String userId, DriverTab tab) =>
      CacheKeys.user(userId, '${CacheKeys.driverShipments}.${tab.name}');

  static String detailKey(String userId, int id) =>
      CacheKeys.user(userId, 'driver.shipment.$id');

  Future<PagedResult<DriverShipmentRow>> fetchScope(
    DriverScope scope, {
    int page = 1,
    int pageSize = pageSize,
  }) => api.get(
    'driver/shipments',
    query: {'scope': scope.query, 'page': page, 'pageSize': pageSize},
    parse: (j) => PagedResult.fromJson(j, DriverShipmentRow.fromJson),
  );

  /// Sekmenin [page]. sayfası (sunucudan). İlk sayfa önbelleğe yazılır.
  Future<DriverListData> fetchTab(
    String userId,
    DriverTab tab, {
    int page = 1,
  }) async {
    final DriverListData data;
    if (tab == DriverTab.today) {
      data = await _fetchToday();
    } else {
      final p = await fetchScope(tab.scope, page: page);
      data = DriverListData(
        items: p.items,
        totalCount: p.totalCount,
        page: p.pageNumber,
        totalPages: p.totalPages,
      );
    }
    if (page == 1) {
      await cache.write(listKey(userId, tab), data.toJson(), userId: userId);
    }
    return data;
  }

  Future<DriverListData> _fetchToday() async {
    final results = await Future.wait([
      fetchScope(DriverScope.today, pageSize: todayPageSize),
      fetchScope(DriverScope.active, pageSize: todayPageSize),
    ]);
    final today = results[0].items;
    final ids = {for (final r in today) r.id};
    final now = TrTime.now();
    final overdue = [
      for (final r in results[1].items)
        if (!ids.contains(r.id) && r.isOverdue(now)) r,
    ];
    final items = sortToday([...today, ...overdue], now);
    return DriverListData(
      items: List.unmodifiable(items),
      totalCount: items.length,
      page: 1,
      totalPages: 1,
    );
  }

  /// Bugün sırası: itirazlı → yolda → gecikmiş plan → bugünkü plan (saate göre) → tamamlananlar.
  static List<DriverShipmentRow> sortToday(
    List<DriverShipmentRow> rows,
    DateTime now,
  ) {
    int rank(DriverShipmentRow r) {
      if (r.isDisputed) return 0;
      if (r.isInTransit) return 1;
      if (r.isOverdue(now)) return 2;
      if (r.isPlanned) return 3;
      return 4;
    }

    final sorted = [...rows]
      ..sort((a, b) {
        final ra = rank(a);
        final rb = rank(b);
        if (ra != rb) return ra.compareTo(rb);
        final ta = a.scheduledAt;
        final tb = b.scheduledAt;
        if (ta != null && tb != null && ta != tb) return ta.compareTo(tb);
        return a.id.compareTo(b.id);
      });
    return sorted;
  }

  Future<DriverListData?> readTab(String userId, DriverTab tab) async {
    final entry = await cache.read(listKey(userId, tab));
    if (entry == null) return null;
    return DriverListData.fromJson(entry.value, storedAt: entry.storedAt);
  }

  Future<DriverShipmentDetail> fetchDetail(String userId, int id) async {
    final json = await api.get<JsonMap>(
      'driver/shipments/$id',
      parse: JsonReader.asMap,
    );
    await saveDetail(userId, json);
    return DriverShipmentDetail.fromJson(json);
  }

  /// Sunucudan gelen ayrıntıyı (ör. yola çıkış / teslim yanıtı) önbelleğe yazar.
  Future<void> saveDetail(String userId, JsonMap json) {
    final id = JsonReader(json).integer('id');
    return cache.write(detailKey(userId, id), json, userId: userId);
  }

  /// Ayrıntıları arka planda önbelleğe alır (en çok [limit]; [maxAge]'den yeni önbellek atlanır).
  /// Hata yutulur; bağlantı koparsa durur.
  Future<void> prefetchDetails(
    String userId,
    Iterable<int> ids, {
    int limit = 15,
    Duration maxAge = const Duration(minutes: 10),
  }) async {
    var n = 0;
    for (final id in ids) {
      if (n++ >= limit) return;
      final cached = await cache.read(detailKey(userId, id));
      if (cached != null && cached.age < maxAge) continue;
      try {
        await fetchDetail(userId, id);
      } on AppFailure catch (f) {
        if (f is OfflineFailure || f is TimeoutFailure) return;
      } catch (_) {
        return;
      }
    }
  }

  Future<CachedDetail?> readDetail(String userId, int id) async {
    final entry = await cache.read(detailKey(userId, id));
    if (entry == null) return null;
    return CachedDetail(
      DriverShipmentDetail.fromJson(entry.value),
      entry.storedAt,
    );
  }
}

final driverRepositoryProvider = Provider<DriverRepository>(
  (ref) => DriverRepository(
    api: ref.watch(apiClientProvider),
    cache: ref.watch(cacheStoreProvider),
  ),
);
