import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/json.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/utils/tr_time.dart';
import 'field_models.dart';
import 'lead_models.dart';

/// Saha formu listesi sorgusu (`field-orders?skip&take&statuses&salesRepresentativeId&requiredApprovalLevel&search`).
/// Eski bağlayıcı tekrarlanan anahtar ister (`statuses=1&statuses=2`); `ApiClient` listeleri böyle gönderir.
class FieldFormsQuery {
  const FieldFormsQuery({
    this.statuses = const [],
    this.salesRepresentativeId,
    this.requiredApprovalLevel,
    this.customerId,
    this.search,
    this.fromUtc,
  });

  final List<int> statuses;
  final int? salesRepresentativeId;
  final int? requiredApprovalLevel;
  final int? customerId;
  final String? search;
  final DateTime? fromUtc;

  bool get isFiltered =>
      statuses.isNotEmpty ||
      salesRepresentativeId != null ||
      requiredApprovalLevel != null ||
      customerId != null ||
      (search ?? '').isNotEmpty;

  /// Önbellek anahtarı parçası.
  String get key =>
      's${statuses.join('.')}-r${salesRepresentativeId ?? ''}-l${requiredApprovalLevel ?? ''}'
      '-c${customerId ?? ''}-q${search ?? ''}-f${fromUtc?.millisecondsSinceEpoch ?? ''}';

  FieldFormsQuery copyWith({
    List<int>? statuses,
    int? Function()? salesRepresentativeId,
    int? Function()? requiredApprovalLevel,
    String? search,
  }) => FieldFormsQuery(
    statuses: statuses ?? this.statuses,
    salesRepresentativeId: salesRepresentativeId == null
        ? this.salesRepresentativeId
        : salesRepresentativeId(),
    requiredApprovalLevel: requiredApprovalLevel == null
        ? this.requiredApprovalLevel
        : requiredApprovalLevel(),
    customerId: customerId,
    search: search ?? this.search,
    fromUtc: fromUtc,
  );

  @override
  bool operator ==(Object other) =>
      other is FieldFormsQuery && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Ön kayıt listesi sorgusu (`leads?scope&status&q&page&pageSize`).
class LeadsQuery {
  const LeadsQuery({this.all = false, this.status, this.search});

  /// `scope=all` (yetkinlik `lead.viewAll` / `approve.finance.lead`).
  final bool all;

  /// `LeadStatusKeys`: draft · finance · info · converted · rejected · cancelled.
  final String? status;
  final String? search;

  bool get isFiltered => status != null || (search ?? '').isNotEmpty;

  String get key => '${all ? 'all' : 'mine'}-${status ?? ''}-${search ?? ''}';

  LeadsQuery copyWith({String? Function()? status, String? search}) =>
      LeadsQuery(
        all: all,
        status: status == null ? this.status : status(),
        search: search ?? this.search,
      );

  @override
  bool operator ==(Object other) => other is LeadsQuery && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Saha formu ve ön kayıt uçları (spec B.9 + B.15). Hata her zaman `AppFailure` olarak fırlar.
class FieldRepository {
  FieldRepository(this.api);

  final ApiClient api;

  static const pageSize = 25;

  // ─────────────────────────────────────────────────────────── Saha formları

  /// Ham sayfa JSON'u (ilk sayfa önbelleğe yazılır).
  Future<Object?> formsJson(
    FieldFormsQuery q, {
    int skip = 0,
    int take = pageSize,
    CancelToken? cancelToken,
  }) => api.get(
    'field-orders',
    query: {
      'skip': skip,
      'take': take,
      'statuses': q.statuses,
      'salesRepresentativeId': q.salesRepresentativeId,
      'requiredApprovalLevel': q.requiredApprovalLevel,
      'customerId': q.customerId,
      'search': q.search,
      'fromUtc': q.fromUtc?.toUtc().toIso8601String(),
    },
    cancelToken: cancelToken,
    parse: (j) => j,
  );

  Future<FieldFormsPage> forms(
    FieldFormsQuery q, {
    int skip = 0,
    int take = pageSize,
    CancelToken? cancelToken,
  }) async => FieldFormsPage.fromJson(
    await formsJson(q, skip: skip, take: take, cancelToken: cancelToken),
  );

  Future<FieldFormDetail> form(int id) =>
      api.get('field-orders/$id', parse: FieldFormDetail.fromJson);

  /// Yeni taslak (Idempotency-Key isteğe bağlı; çevrimdışı kuyruk aynı anahtarla yineler).
  Future<FieldForm> createForm(JsonMap request, {String? idempotencyKey}) =>
      api.post(
        'field-orders',
        body: request,
        idempotencyKey: idempotencyKey,
        parse: FieldForm.fromJson,
      );

  Future<FieldForm> updateForm(int id, JsonMap request) =>
      api.put('field-orders/$id', body: request, parse: FieldForm.fromJson);

  Future<FieldPreview> preview(JsonMap request, {CancelToken? cancelToken}) =>
      api.post(
        'field-orders/preview-v2',
        body: request,
        cancelToken: cancelToken,
        parse: FieldPreview.fromJson,
      );

  Future<FieldOptions> options(int customerId, {int? stationId}) => api.get(
    'field-orders/options-v2',
    query: {'customerId': customerId, 'stationId': stationId},
    parse: FieldOptions.fromJson,
  );

  Future<List<FieldSupplyOption>> supplyOptions({String? query}) => api.get(
    'field-orders/supply-options',
    query: {'q': query},
    parse: (j) => JsonReader.parseList(j, FieldSupplyOption.fromJson),
  );

  /// Cari arama (portföy / bayi carileri, en çok 20).
  Future<List<IdName>> searchCustomers({
    required int stationId,
    String? term,
  }) => api.get(
    'field-orders/customers/search',
    query: {'stationId': stationId, 'term': term},
    parse: (j) => JsonReader.parseList(j, IdName.fromJson),
  );

  Future<FieldSubmitResult> submitForm(
    int id, {
    String? concurrencyToken,
    String? idempotencyKey,
  }) => api.post(
    'field-orders/$id/submit',
    body: {'concurrencyToken': ?concurrencyToken},
    idempotencyKey: idempotencyKey,
    parse: FieldSubmitResult.fromJson,
  );

  Future<String> cancelForm(int id, {String? note}) => api.post(
    'field-orders/$id/cancel',
    body: {'note': ?note},
    parse: (j) => JsonReader.of(j).str('message', 'Form iptal edildi.'),
  );

  Future<FieldSubmitResult> retryConversion(
    int id, {
    String? concurrencyToken,
  }) => api.post(
    'field-orders/$id/retry-conversion',
    body: {'concurrencyToken': ?concurrencyToken},
    parse: FieldSubmitResult.fromJson,
  );

  Future<FieldDocument> document(int id, {required bool internal}) => api.get(
    'field-orders/$id/document',
    query: {'variant': internal ? 'internal' : 'external'},
    parse: FieldDocument.fromJson,
  );

  Future<String> emailDocument(int id, {String? toEmail}) => api.post(
    'field-orders/$id/email',
    body: {'toEmail': ?toEmail},
    parse: (j) => JsonReader.of(j).str('message'),
  );

  Future<List<IdName>> reps() => api.get(
    'field-orders/reps',
    parse: (j) => JsonReader.parseList(j, IdName.fromJson),
  );

  /// Ham portföy sayfası (ilk sayfa çevrimdışı için önbelleğe yazılır; spec C.4a).
  Future<Object?> portfolioJson({
    String? search,
    int skip = 0,
    int take = pageSize,
  }) => api.get(
    'me/portfolio',
    query: {'search': search, 'skip': skip, 'take': take},
    parse: (j) => j,
  );

  Future<SkipTakePage<PortfolioRow>> portfolio({
    String? search,
    int skip = 0,
    int take = pageSize,
  }) async => SkipTakePage.fromJson(
    await portfolioJson(search: search, skip: skip, take: take),
    PortfolioRow.fromJson,
  );

  /// Cari kartı (B4 `bayi/customers/{id}/summary`). Sessiz 403: kart yoksa bölüm gizlenir.
  Future<FieldCustomerSummary> customerSummary(int customerId) => api.get(
    'bayi/customers/$customerId/summary',
    quiet403: true,
    parse: FieldCustomerSummary.fromJson,
  );

  // ─────────────────────────────────────────────────────────── Ön kayıtlar

  /// Ham ön kayıt sayfası (`PagedResult<LeadListItemDto>`).
  Future<Object?> leadsJson(
    LeadsQuery q, {
    int page = 1,
    int size = pageSize,
  }) => api.get(
    'leads',
    query: {
      'scope': q.all ? 'all' : 'mine',
      'status': q.status,
      'q': q.search,
      'page': page,
      'pageSize': size,
    },
    parse: (j) => j,
  );

  Future<({List<LeadRow> items, int totalCount})> leads(
    LeadsQuery q, {
    int page = 1,
    int size = pageSize,
  }) async => parseLeads(await leadsJson(q, page: page, size: size));

  static ({List<LeadRow> items, int totalCount}) parseLeads(Object? j) {
    final r = JsonReader.of(j);
    final items = r.list('items', LeadRow.fromJson);
    return (
      items: List<LeadRow>.unmodifiable(items),
      totalCount: r.integer('totalCount', items.length),
    );
  }

  Future<LeadDetail> lead(int id) =>
      api.get('leads/$id', parse: LeadDetail.fromJson);

  Future<LeadOptions> leadOptions() =>
      api.get('leads/options', parse: LeadOptions.fromJson);

  Future<LeadDuplicateCheck> checkDuplicate(
    String taxNumber, {
    int? excludeId,
  }) => api.get(
    'leads/check-duplicate',
    query: {
      'taxNumber': taxNumber,
      'excludeId': excludeId == null || excludeId <= 0 ? null : excludeId,
    },
    parse: LeadDuplicateCheck.fromJson,
  );

  Future<LeadStats> leadStats({DateTime? from, DateTime? to}) => api.get(
    'leads/stats',
    query: {
      'from': from == null ? null : TrTime.isoDate(from),
      'to': to == null ? null : TrTime.isoDate(to),
    },
    parse: LeadStats.fromJson,
  );

  /// Yeni ön kayıt (Idempotency-Key zorunlu).
  Future<LeadSaveResult> createLead(
    JsonMap body, {
    required String idempotencyKey,
  }) => api.post(
    'leads',
    body: body,
    idempotencyKey: idempotencyKey,
    parse: LeadSaveResult.fromJson,
  );

  Future<LeadSaveResult> updateLead(int id, JsonMap body) =>
      api.put('leads/$id', body: body, parse: LeadSaveResult.fromJson);

  Future<String> submitLead(int id, {String? concurrencyToken}) => api.post(
    'leads/$id/submit',
    body: {
      'concurrencyToken':
          concurrencyToken ?? '00000000-0000-0000-0000-000000000000',
    },
    parse: _message,
  );

  Future<String> cancelLead(int id, {String? note}) =>
      api.post('leads/$id/cancel', body: {'note': ?note}, parse: _message);

  Future<String> forwardLeadToHq(int id, {String? note}) =>
      api.post('leads/$id/forward-hq', body: {'note': ?note}, parse: _message);

  Future<String> resendLeadInvite(int id, {String? email}) => api.post(
    'leads/$id/resend-invite',
    body: {'email': ?email},
    parse: _message,
  );

  static String _message(Object? j) => JsonReader.of(j).str('message');
}

final fieldRepositoryProvider = Provider<FieldRepository>(
  (ref) => FieldRepository(ref.watch(apiClientProvider)),
);
