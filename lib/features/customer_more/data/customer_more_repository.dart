import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/attachment_api.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';
import '../../../core/models/paged_result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/utils/tr_time.dart';
import 'company.dart';
import 'delivery_point.dart';
import 'documents.dart';
import 'finance_info.dart';
import 'order_requests.dart';
import 'shipments.dart';
import 'spending.dart';

/// Teslimat listesi ölçütü (`GET shipments`; eski bağlayıcı: tekrarlanan `statuses`).
@immutable
class ShipmentQuery {
  const ShipmentQuery({this.statuses = const [], this.search, this.sort = 0});

  final List<ShipmentStatus> statuses;
  final String? search;

  /// `ShipmentSort`: 0 yeni → eski, 1 plan (eski → yeni), 2 plan (yeni → eski), 3 teslim (yeni → eski).
  final int sort;

  Map<String, dynamic> toQuery({required int page, required int pageSize}) => {
    'page': page,
    'pageSize': pageSize,
    'statuses': [for (final s in statuses) s.code],
    'search': search,
    if (sort != 0) 'sort': sort,
  };

  @override
  bool operator ==(Object other) =>
      other is ShipmentQuery &&
      listEquals(other.statuses, statuses) &&
      other.search == search &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(Object.hashAll(statuses), search, sort);
}

/// Belge arşivi sevkiyat ölçütü (`DocumentArchiveShipmentFilter`).
enum ArchiveShipmentFilter {
  all(null, 'Tümü'),
  withShipment(1, 'Sevkiyatlı'),
  withoutShipment(2, 'Sevkiyatsız');

  const ArchiveShipmentFilter(this.code, this.label);
  final int? code;
  final String label;
}

/// Belge arşivi ölçütü (`DocumentArchiveQuery`; sunucu en geniş 366 gün, boşsa son 3 ay).
@immutable
class DocumentArchiveQuery {
  const DocumentArchiveQuery({
    this.from,
    this.to,
    this.search,
    this.shipment = ArchiveShipmentFilter.all,
    this.sort = 'created',
  });

  /// Türkiye gece yarısı anları (gün olarak gönderilir).
  final DateTime? from;
  final DateTime? to;
  final String? search;
  final ArchiveShipmentFilter shipment;

  /// `created` (yeni → eski) | `created:asc` | `delivered`.
  final String sort;

  /// Varsayılan ölçüt (çevrimdışı önbellek yalnızca bunun ilk sayfasını tutar).
  bool get isDefault =>
      from == null &&
      to == null &&
      (search == null || search!.trim().isEmpty) &&
      shipment == ArchiveShipmentFilter.all &&
      sort == 'created';

  Map<String, dynamic> toQuery({required int skip, required int take}) => {
    'skip': skip,
    'take': take,
    if (from != null) 'fromDate': TrTime.isoDate(from!),
    if (to != null) 'toDate': TrTime.isoDate(to!),
    'search': search,
    'shipment': shipment.code,
    if (sort != 'created') 'sort': sort,
  };

  DocumentArchiveQuery copyWith({
    DateTime? from,
    DateTime? to,
    bool clearRange = false,
    String? search,
    ArchiveShipmentFilter? shipment,
    String? sort,
  }) => DocumentArchiveQuery(
    from: clearRange ? null : (from ?? this.from),
    to: clearRange ? null : (to ?? this.to),
    search: search ?? this.search,
    shipment: shipment ?? this.shipment,
    sort: sort ?? this.sort,
  );

  @override
  bool operator ==(Object other) =>
      other is DocumentArchiveQuery &&
      other.from == from &&
      other.to == to &&
      other.search == search &&
      other.shipment == shipment &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(from, to, search, shipment, sort);
}

/// Harcama raporu ölçütü (`SpendingQuery`; sunucu en geniş 36 ay).
@immutable
class SpendingRange {
  const SpendingRange({required this.from, required this.to});

  /// Türkiye gece yarısı anları.
  final DateTime from;
  final DateTime to;

  static const maxMonths = 36;

  /// İçinde bulunulan ay dahil son [months] ay (ayın 1'i → bugün).
  factory SpendingRange.lastMonths(int months, {DateTime? now}) {
    final today = TrTime.startOfDay(now ?? TrTime.now());
    final w = TrTime.wall(today);
    final start = TrTime.fromWall(w.year, w.month - (months - 1), 1);
    return SpendingRange(from: start, to: today);
  }

  /// Bu yıl (1 Ocak → bugün).
  factory SpendingRange.thisYear({DateTime? now}) {
    final today = TrTime.startOfDay(now ?? TrTime.now());
    return SpendingRange(
      from: TrTime.fromWall(TrTime.wall(today).year),
      to: today,
    );
  }

  /// Geçen yıl (1 Ocak → 31 Aralık).
  factory SpendingRange.lastYear({DateTime? now}) {
    final y = TrTime.wall(now ?? TrTime.now()).year - 1;
    return SpendingRange(
      from: TrTime.fromWall(y),
      to: TrTime.fromWall(y, 12, 31),
    );
  }

  /// Sunucu kuralı (`SpendingReport.NormalizeRange`): ters aralık düzelir, bitiş bugünü geçmez,
  /// 36 aydan geniş aralık başlangıçtan kırpılır.
  SpendingRange normalized({DateTime? now}) {
    final today = TrTime.startOfDay(now ?? TrTime.now());
    var f = TrTime.startOfDay(from);
    var t = TrTime.startOfDay(to);
    if (t.isAfter(today)) t = today;
    if (f.isAfter(t)) (f, t) = (t, f);
    final wt = TrTime.wall(t);
    final earliest = TrTime.fromWall(wt.year, wt.month - (maxMonths - 1), 1);
    if (f.isBefore(earliest)) f = earliest;
    return SpendingRange(from: f, to: t);
  }

  /// Kırpılacak mı.
  bool exceedsMax({DateTime? now}) => normalized(now: now).from != from;

  Map<String, dynamic> toQuery() => {
    'fromDate': TrTime.isoDate(from),
    'toDate': TrTime.isoDate(to),
  };

  @override
  bool operator ==(Object other) =>
      other is SpendingRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// A3 (müşteri: teslimatlar, belgeler, harcamalar, talepler, teslimat noktaları, finans bilgisi, şirket
/// kullanıcıları) uç noktaları. Hatalar `AppFailure` olarak fırlar (ApiClient).
class CustomerMoreRepository {
  CustomerMoreRepository(this.api, this.attachments);

  final ApiClient api;
  final AttachmentApi attachments;

  static Object? _raw(Object? json) => json;

  // ------------------------------------------------------------------ Teslimatlar

  Future<ShipmentListPage> shipments(
    ShipmentQuery query, {
    int page = 1,
    int pageSize = 25,
  }) => api.get(
    'shipments',
    query: query.toQuery(page: page, pageSize: pageSize),
    parse: ShipmentListPage.fromJson,
  );

  Future<ShipmentDetail> shipmentDetail(int id) =>
      api.get('shipments/$id/detail', parse: ShipmentDetail.fromJson);

  /// Teslimatı kabul (204). Idempotency-Key aynı niyetin tekrarında aynı kalır.
  Future<void> acceptShipment(int id, {required String idempotencyKey}) =>
      api.post<void>('shipments/$id/accept', idempotencyKey: idempotencyKey);

  /// İtiraz (204). Önce itiraz fotoğrafları yüklenir.
  Future<void> disputeShipment(
    int id,
    String note, {
    required String idempotencyKey,
  }) => api.post<void>(
    'shipments/$id/dispute',
    body: {'note': note.trim()},
    idempotencyKey: idempotencyKey,
  );

  /// İtiraz fotoğrafı (Shipment = 10, DisputePhoto = 32; sıkıştırılmış JPEG baytları).
  Future<AttachmentUploadResult> uploadDisputePhoto({
    required int shipmentId,
    required Uint8List bytes,
    required String fileName,
    required String idempotencyKey,
    void Function(double progress)? onProgress,
  }) => attachments.uploadBytes(
    ownerType: AttachmentOwnerType.shipment,
    ownerId: shipmentId,
    kind: AttachmentKind.disputePhoto,
    bytes: bytes,
    fileName: fileName,
    contentType: 'image/jpeg',
    idempotencyKey: idempotencyKey,
    onProgress: onProgress,
  );

  /// Ödeme belgesi (çek / senet görseli, dekont) baytları.
  Future<AttachmentUploadResult> uploadPaymentDocument({
    required AttachmentOwnerType ownerType,
    required int ownerId,
    required AttachmentKind kind,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required String idempotencyKey,
    void Function(double progress)? onProgress,
  }) => attachments.uploadBytes(
    ownerType: ownerType,
    ownerId: ownerId,
    kind: kind,
    bytes: bytes,
    fileName: fileName,
    contentType: contentType,
    idempotencyKey: idempotencyKey,
    onProgress: onProgress,
  );

  Future<void> deleteAttachment(String publicId) =>
      attachments.delete(publicId);

  // ------------------------------------------------------------------ Belgeler

  /// Ham JSON (çevrimdışı önbellek için) — [DocumentArchivePage.fromJson] ile okunur.
  Future<Object?> documentArchiveJson(
    DocumentArchiveQuery query, {
    int skip = 0,
    int take = 25,
  }) => api.get(
    'customers/me/documents',
    query: query.toQuery(skip: skip, take: take),
    parse: _raw,
  );

  Future<OrderDocument> orderDocument(int orderId) =>
      api.get('documents/orders/$orderId', parse: OrderDocument.fromJson);

  Future<ShipmentDocument> shipmentDocument(int shipmentId) => api.get(
    'documents/shipments/$shipmentId',
    parse: ShipmentDocument.fromJson,
  );

  // ------------------------------------------------------------------ Harcamalar

  Future<SpendingReport> spending(
    SpendingRange range, {
    int? deliveryPointId,
    int? productId,
    int? stationId,
  }) => api.get(
    'customers/me/spending',
    query: {
      ...range.toQuery(),
      'deliveryPointId': deliveryPointId,
      'productId': productId,
      'stationId': stationId,
    },
    parse: SpendingReport.fromJson,
  );

  // ------------------------------------------------------------------ Teslimat noktaları

  /// Ham JSON (çevrimdışı önbellek için).
  Future<Object?> deliveryPointsJson({bool includeInactive = false}) => api.get(
    'customers/me/delivery-points',
    query: {if (includeInactive) 'includeInactive': true},
    parse: _raw,
  );

  static List<DeliveryPoint> parseDeliveryPoints(Object? json) =>
      JsonReader.parseList(json, DeliveryPoint.fromJson);

  Future<DeliveryPoint> deliveryPoint(int id) => api.get(
    'customers/me/delivery-points/$id',
    parse: (j) => DeliveryPoint.fromJson(JsonReader.of(j)),
  );

  /// Yeni nokta → kimlik.
  Future<int> saveDeliveryPoint(DeliveryPointDraft draft) {
    final body = draft.toJson();
    int parse(Object? j) => JsonReader.of(j).integer('id', draft.id);
    return draft.isNew
        ? api.post('customers/me/delivery-points', body: body, parse: parse)
        : api.put(
            'customers/me/delivery-points/${draft.id}',
            body: body,
            parse: parse,
          );
  }

  Future<String?> deactivateDeliveryPoint(int id) => api.post(
    'customers/me/delivery-points/$id/deactivate',
    parse: (j) => JsonReader.of(j).nonEmpty('message'),
  );

  // ------------------------------------------------------------------ Şirket içi talepler

  Future<PagedResult<OrderRequest>> orderRequests({
    int skip = 0,
    int take = 25,
    List<CustomerOrderRequestStatus> statuses = const [],
  }) => api.get(
    'customers/me/order-requests',
    query: {
      'skip': skip,
      'take': take,
      'statuses': [for (final s in statuses) s.code],
    },
    parse: (j) => PagedResult.fromJson(j, OrderRequest.fromJson),
  );

  Future<OrderRequest> orderRequest(int id) => api.get(
    'customers/me/order-requests/$id',
    parse: (j) => OrderRequest.fromJson(JsonReader.of(j)),
  );

  Future<String?> cancelOrderRequest(int id) => api.post(
    'customers/me/order-requests/$id/cancel',
    parse: (j) => JsonReader.of(j).nonEmpty('message'),
  );

  /// Ödeme belgesi hedefi (204 → null).
  Future<PaymentUploadTarget?> paymentDocumentTarget({
    required List<int> orderIds,
    String? methodCode,
  }) => api.get(
    'orders/payment-document-target',
    query: {'orderIds': orderIds.join(','), 'methodCode': methodCode},
    parse: PaymentUploadTarget.tryParse,
  );

  Future<List<Attachment>> attachmentsOf(
    AttachmentOwnerType ownerType,
    int ownerId,
  ) => attachments.list(ownerType, ownerId);

  // ------------------------------------------------------------------ Finans bilgisi

  Future<FinanceInfo> financeInfo() =>
      api.get('customers/me/finance-info', parse: FinanceInfo.fromJson);

  // ------------------------------------------------------------------ Şirket kullanıcıları

  Future<List<CompanyUser>> companyUsers() => api.get(
    'customers/me/company-users',
    parse: (j) => JsonReader.parseList(j, CompanyUser.fromJson),
  );

  /// Yeni şirket kullanıcısı. Kullanıcı adı zorunlu; şifre verilirse kullanıcı hemen girer, verilmezse
  /// e-postaya davet bağlantısı gider (e-posta o zaman zorunlu). Boş e-posta / şifre gönderilmez.
  Future<CompanyUser> createCompanyUser({
    required String displayName,
    required String userName,
    String? email,
    String? password,
    String? phoneNumber,
    required CustomerUserRole role,
  }) => api.post(
    'customers/me/company-users',
    body: {
      'customerId': 0,
      'displayName': displayName.trim(),
      'userName': userName.trim(),
      'email': ?_clean(email),
      'password': ?((password ?? '').isEmpty ? null : password),
      'phoneNumber': _clean(phoneNumber),
      'role': role.code,
    },
    parse: (j) => CompanyUser.fromJson(JsonReader.of(j)),
  );

  /// Yöneticinin belirlediği yeni şifre (204; sunucu kurallarına uymazsa 400 `validation`).
  Future<void> setCompanyUserPassword(String userId, String newPassword) =>
      api.post<void>(
        'customers/me/company-users/${Uri.encodeComponent(userId)}/password',
        body: {'newPassword': newPassword},
        quiet403: true,
      );

  Future<CompanyUser> updateCompanyUser({
    required String userId,
    required String displayName,
    String? phoneNumber,
    required CustomerUserRole role,
  }) => api.put(
    'customers/me/company-users',
    body: {
      'customerId': 0,
      'userId': userId,
      'displayName': displayName.trim(),
      'phoneNumber': _clean(phoneNumber),
      'role': role.code,
    },
    parse: (j) => CompanyUser.fromJson(JsonReader.of(j)),
  );

  Future<String?> setCompanyUserActive(String userId, bool isActive) =>
      api.post(
        'customers/me/company-users/${Uri.encodeComponent(userId)}/active',
        body: {'isActive': isActive},
        parse: (j) => JsonReader.of(j).nonEmpty('message'),
      );

  /// Davet / şifre belirleme bağlantısını yeniden gönderir (204).
  Future<void> sendPasswordLink(String userId) => api.post<void>(
    'customers/me/company-users/${Uri.encodeComponent(userId)}/password-link',
  );

  Future<ApprovalThresholds> approvalThresholds() => api.get(
    'customers/me/company-users/approval-settings',
    parse: ApprovalThresholds.fromJson,
  );

  Future<ApprovalThresholds> saveApprovalThresholds({
    double? aboveLitres,
    double? aboveAmount,
  }) => api.put(
    'customers/me/company-users/approval-settings',
    body: {
      'customerId': 0,
      'requireApprovalAboveLitres': aboveLitres,
      'requireApprovalAboveAmount': aboveAmount,
    },
    parse: ApprovalThresholds.fromJson,
  );

  static String? _clean(String? s) {
    final v = s?.trim();
    return v == null || v.isEmpty ? null : v;
  }
}

final customerMoreRepositoryProvider = Provider<CustomerMoreRepository>(
  (ref) => CustomerMoreRepository(
    ref.watch(apiClientProvider),
    ref.watch(attachmentApiProvider),
  ),
);
