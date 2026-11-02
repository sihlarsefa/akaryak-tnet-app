import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/utils/tr_time.dart';
import 'bayi_json.dart';
import 'customer_models.dart';
import 'desk_models.dart';
import 'dispatch_models.dart';
import 'home_models.dart';
import 'order_models.dart';
import 'staff_models.dart';

/// Bayi operasyon uçları (spec B.7, B.10, B.15). Her hata `AppFailure` olarak fırlar.
///
/// Durum değiştiren uçlardan plan, şoför ataması, not ve toplu teklif `Idempotency-Key` taşır
/// (sunucuda isteğe bağlı; aynı anahtarla tekrar ikinci kayıt oluşturmaz).
class BayiRepository {
  BayiRepository(this.api);

  final ApiClient api;

  /// Ekran yüklemeleri 403'ü kendi "yetkiniz yok" durumuyla gösterir (genel bildirim gösterilmez).
  /// [cache]: yanıt önbelleğe yazılır (ilk sayfa, varsayılan süzgeç, ayrıntı; aramalar değil).
  Future<T> _get<T>(
    String path, {
    required JsonParser<T> parse,
    Map<String, dynamic>? query,
    bool cache = false,
  }) => api.get(path, parse: parse, query: query, quiet403: true, cache: cache);

  /// Önbellekteki son yanıt (ağa çıkmaz): ekran açılışta hemen gösterir, sonra sunucudan tazeler.
  Future<CachedResponse<T>?> _peek<T>(
    String path, {
    required JsonParser<T> parse,
    Map<String, dynamic>? query,
  }) => api.peek(path, parse: parse, query: query);

  static const deskPageSize = 50;
  static const listPageSize = 25;

  // ------------------------------------------------------------------ Ana sayfa

  Future<({BayiHomeData data, Object? raw})> home() =>
      _get('home/bayi', parse: (j) => (data: BayiHomeData.fromJson(j), raw: j));

  // ------------------------------------------------------------------ Teklif masası

  Future<({DeskPage page, Object? raw})> quoteDesk({
    required DeskView view,
    required DeskSort sort,
    int? customerId,
    int? productId,
    int page = 1,
    int pageSize = deskPageSize,
  }) => _get(
    'bayi/quote-desk',
    query: {
      'view': view.key,
      'sort': sort.key,
      'customerId': customerId,
      'productId': productId,
      'page': page,
      'pageSize': pageSize,
    },
    parse: (j) => (page: DeskPage.fromJson(j), raw: j),
  );

  Future<DeskCountsResult> quoteDeskCounts({int? customerId, int? productId}) =>
      _get(
        'bayi/quote-desk/counts',
        query: {'customerId': customerId, 'productId': productId},
        parse: DeskCountsResult.fromJson,
      );

  /// Süzgeç seçenekleri (eski masa ucu).
  Future<DeskFacets> quoteDeskFacets() => _get(
    'stations/me/quote-desk/facets',
    parse: DeskFacets.fromJson,
    cache: true,
  );

  Future<CachedResponse<DeskFacets>?> peekQuoteDeskFacets() =>
      _peek('stations/me/quote-desk/facets', parse: DeskFacets.fromJson);

  /// Toplu teklif: satır sonuçları istek sırasıyla döner.
  Future<List<DeskSubmitResult>> submitQuotes(
    List<DeskSubmitItem> items, {
    required String idempotencyKey,
  }) => api.post(
    'bayi/quote-desk/submit',
    body: {
      'items': [for (final i in items) i.toJson()],
    },
    idempotencyKey: idempotencyKey,
    parse: (j) => JsonReader.parseList(j, DeskSubmitResult.fromJson),
  );

  // ------------------------------------------------------------------ Siparişler

  Future<PagedResult<BayiOrderRow>> orders(
    BayiOrdersFilter filter, {
    int page = 1,
    int pageSize = listPageSize,
  }) => _get(
    'bayi/orders',
    query: filter.toQuery(page: page, pageSize: pageSize),
    parse: _parseOrders,
    cache: page == 1 && filter.q.trim().isEmpty,
  );

  /// Süzgecin önbellekteki ilk sayfası (aramada yok).
  Future<CachedResponse<PagedResult<BayiOrderRow>>?> peekOrders(
    BayiOrdersFilter filter, {
    int pageSize = listPageSize,
  }) async => filter.q.trim().isNotEmpty
      ? null
      : _peek(
          'bayi/orders',
          query: filter.toQuery(page: 1, pageSize: pageSize),
          parse: _parseOrders,
        );

  static PagedResult<BayiOrderRow> _parseOrders(Object? j) =>
      PagedResult.fromJson(j, BayiOrderRow.fromJson);

  Future<BayiOrderCounts> orderCounts() => _get(
    'bayi/orders/counts',
    parse: BayiOrderCounts.fromJson,
    cache: true,
  );

  Future<CachedResponse<BayiOrderCounts>?> peekOrderCounts() =>
      _peek('bayi/orders/counts', parse: BayiOrderCounts.fromJson);

  Future<OrderDetail> order(int id) =>
      _get('orders/$id', parse: OrderDetail.fromJson, cache: true);

  Future<CachedResponse<OrderDetail>?> peekOrder(int id) =>
      _peek('orders/$id', parse: OrderDetail.fromJson);

  Future<List<OrderTimelineItem>> orderTimeline(int id) =>
      _get('orders/$id/timeline', parse: _parseTimeline, cache: true);

  Future<CachedResponse<List<OrderTimelineItem>>?> peekOrderTimeline(int id) =>
      _peek('orders/$id/timeline', parse: _parseTimeline);

  static List<OrderTimelineItem> _parseTimeline(Object? j) =>
      JsonReader.parseList(j, OrderTimelineItem.fromJson);

  Future<Fulfillment> fulfillment(int orderId) => _get(
    'shipments/order/$orderId',
    parse: Fulfillment.fromJson,
    cache: true,
  );

  Future<CachedResponse<Fulfillment>?> peekFulfillment(int orderId) =>
      _peek('shipments/order/$orderId', parse: Fulfillment.fromJson);

  /// Tekil teklif (sipariş ayrıntısı). Teslim günü Türkiye yerel gece yarısı olarak gider.
  Future<void> quoteOrder(
    int id, {
    required double unitPrice,
    required DateTime deliveryDate,
  }) => api.post<void>(
    'orders/$id/quote',
    body: {
      'unitPriceTry': unitPrice,
      'deliveryDate': BayiJson.isoLocal(TrTime.startOfDay(deliveryDate)),
    },
  );

  Future<void> completeOrder(int id) => api.post<void>('orders/$id/complete');

  // ------------------------------------------------------------------ Cariler

  Future<PagedResult<BayiCustomerRow>> customers({
    String q = '',
    int page = 1,
    int pageSize = listPageSize,
  }) => _get(
    'bayi/customers',
    query: {'q': q.trim(), 'page': page, 'pageSize': pageSize},
    parse: _parseCustomers,
    cache: page == 1 && q.trim().isEmpty,
  );

  /// Carilerin önbellekteki ilk sayfası (aramasız liste).
  Future<CachedResponse<PagedResult<BayiCustomerRow>>?> peekCustomers({
    int pageSize = listPageSize,
  }) => _peek(
    'bayi/customers',
    query: {'q': '', 'page': 1, 'pageSize': pageSize},
    parse: _parseCustomers,
  );

  static PagedResult<BayiCustomerRow> _parseCustomers(Object? j) =>
      PagedResult.fromJson(j, BayiCustomerRow.fromJson);

  Future<CustomerSummary> customerSummary(int customerId) => _get(
    'bayi/customers/$customerId/summary',
    parse: CustomerSummary.fromJson,
    cache: true,
  );

  Future<CachedResponse<CustomerSummary>?> peekCustomerSummary(
    int customerId,
  ) => _peek(
    'bayi/customers/$customerId/summary',
    parse: CustomerSummary.fromJson,
  );

  Future<List<CustomerNote>> notes(int customerId, {int take = 20}) => _get(
    'stations/me/customers/$customerId/notes',
    query: {'take': take},
    parse: (j) => JsonReader.parseList(j, CustomerNote.fromJson),
  );

  Future<CustomerNote> addNote(
    int customerId,
    String body, {
    required String idempotencyKey,
  }) => api.post(
    'stations/me/customers/$customerId/notes',
    body: {'body': body.trim()},
    idempotencyKey: idempotencyKey,
    parse: (j) => CustomerNote.fromJson(JsonReader.of(j)),
  );

  Future<void> deleteNote(int customerId, int noteId) =>
      api.delete<void>('stations/me/customers/$customerId/notes/$noteId');

  Future<void> createLimitRequest(int customerId, LimitRequestDraft draft) =>
      api.post<void>(
        'stations/me/customers/$customerId/limit-requests',
        body: draft.toJson(),
      );

  // ------------------------------------------------------------------ Sevkiyat

  Future<ShipmentBoard> board({DateTime? from, int days = 7}) => _get(
    'shipments/board',
    query: {'from': from == null ? null : BayiJson.isoDate(from), 'days': days},
    parse: ShipmentBoard.fromJson,
    cache: from == null,
  );

  /// Varsayılan panonun (bugünden 7 gün) önbellekteki son hâli.
  Future<CachedResponse<ShipmentBoard>?> peekBoard({int days = 7}) => _peek(
    'shipments/board',
    query: {'days': days},
    parse: ShipmentBoard.fromJson,
  );

  Future<BoardSuggestions> boardSuggestions() =>
      _get('shipments/board/suggestions', parse: BoardSuggestions.fromJson);

  Future<List<StationDriver>> drivers() => _get(
    'stations/me/drivers',
    parse: (j) => JsonReader.parseList(j, StationDriver.fromJson),
  );

  Future<ShipmentListPage> shipments(
    ShipmentListFilter filter, {
    int page = 1,
    int pageSize = listPageSize,
  }) => _get(
    'shipments',
    query: filter.toQuery(
      page: page,
      pageSize: pageSize,
      today: TrTime.todayStart(),
    ),
    parse: ShipmentListPage.fromJson,
    cache: page == 1 && filter.search.trim().isEmpty,
  );

  /// Süzgecin önbellekteki ilk sayfası (aramada yok).
  Future<CachedResponse<ShipmentListPage>?> peekShipments(
    ShipmentListFilter filter, {
    int pageSize = listPageSize,
  }) async => filter.search.trim().isNotEmpty
      ? null
      : _peek(
          'shipments',
          query: filter.toQuery(
            page: 1,
            pageSize: pageSize,
            today: TrTime.todayStart(),
          ),
          parse: ShipmentListPage.fromJson,
        );

  Future<ShipmentDetail> shipmentDetail(int id) => _get(
    'shipments/$id/detail',
    parse: ShipmentDetail.fromJson,
    cache: true,
  );

  Future<CachedResponse<ShipmentDetail>?> peekShipmentDetail(int id) =>
      _peek('shipments/$id/detail', parse: ShipmentDetail.fromJson);

  /// Sevkiyat planla (`PlanShipmentRequest`). `scheduledAt` Türkiye yerel, ofsetsiz gider.
  Future<void> planShipment(
    PlanShipmentDraft draft, {
    required String idempotencyKey,
  }) => api.post<void>(
    'shipments',
    body: draft.toJson(),
    idempotencyKey: idempotencyKey,
  );

  Future<void> assignDriver(
    int shipmentId, {
    required String driverUserId,
    String? vehiclePlate,
    required String idempotencyKey,
  }) => api.post<void>(
    'shipments/$shipmentId/assign-driver',
    body: {'driverUserId': driverUserId, 'vehiclePlate': vehiclePlate},
    idempotencyKey: idempotencyKey,
  );

  Future<void> dispatch(int shipmentId) =>
      api.post<void>('shipments/$shipmentId/dispatch');

  Future<void> report(
    int shipmentId, {
    required double deliveredLiters,
    required String deliveryDocumentNo,
  }) => api.post<void>(
    'shipments/$shipmentId/report',
    body: {
      'shipmentId': shipmentId,
      'deliveredLiters': deliveredLiters,
      'deliveryDocumentNo': deliveryDocumentNo.trim(),
    },
  );

  Future<void> cancelShipment(int shipmentId) =>
      api.post<void>('shipments/$shipmentId/cancel');

  // ------------------------------------------------------------------ Ekip

  Future<List<StaffMember>> staff() =>
      _get('stations/me/staff', parse: _parseStaff, cache: true);

  Future<CachedResponse<List<StaffMember>>?> peekStaff() =>
      _peek('stations/me/staff', parse: _parseStaff);

  static List<StaffMember> _parseStaff(Object? j) =>
      JsonReader.parseList(j, StaffMember.fromJson);

  Future<void> setStaffActive(String userId, bool active) => api.post<void>(
    'stations/me/staff/${Uri.encodeComponent(userId)}/active',
    body: {'isActive': active},
  );

  Future<void> sendPasswordReset(String userId) => api.post<void>(
    'stations/me/staff/${Uri.encodeComponent(userId)}/send-password-reset',
  );

  /// "Şifre belirle" (sözleşme 2026-10-30): 204; sunucu kurallarına uymazsa 400 `validation`, bayinin
  /// ana hesabına başkası denerse 403 (ileti sayfada gösterilir, genel 403 bildirimi çıkmaz).
  Future<void> setStaffPassword(String userId, String newPassword) =>
      api.post<void>(
        'stations/me/staff/${Uri.encodeComponent(userId)}/password',
        body: {'newPassword': newPassword},
        quiet403: true,
      );
}

/// Sevkiyat planı taslağı (`PlanShipmentRequest`): şoför hesabıyla ([driverUserId]) ya da yalnızca adla.
class PlanShipmentDraft {
  const PlanShipmentDraft({
    required this.orderId,
    required this.plannedLiters,
    required this.vehiclePlate,
    required this.driverName,
    required this.scheduledAt,
    this.driverUserId,
  });

  final int orderId;
  final double plannedLiters;
  final String vehiclePlate;
  final String driverName;

  /// An (UTC); sunucuya Türkiye yerel saat olarak gider.
  final DateTime scheduledAt;
  final String? driverUserId;

  JsonMap toJson() => {
    'orderId': orderId,
    'plannedLiters': double.parse(plannedLiters.toStringAsFixed(3)),
    'vehiclePlate': vehiclePlate.trim(),
    'driverName': driverName.trim(),
    'scheduledAt': BayiJson.isoLocal(scheduledAt),
    'driverUserId': driverUserId,
  };

  /// Niyet anahtarı (aynı plan tekrarında aynı Idempotency-Key).
  String get intent =>
      'plan:$orderId:${plannedLiters.toStringAsFixed(3)}:${vehiclePlate.trim()}:'
      '${driverUserId ?? driverName.trim()}:${BayiJson.isoLocal(scheduledAt)}';
}

final bayiRepositoryProvider = Provider<BayiRepository>(
  (ref) => BayiRepository(ref.watch(apiClientProvider)),
);
