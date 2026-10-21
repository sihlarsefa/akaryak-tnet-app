import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/paged_result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_providers.dart';
import 'payment_models.dart';

/// Varsayılan ödeme süzgeci: açık ödemeler (Bekliyor + Belge yüklendi).
const defaultPaymentStatuses = {
  PaymentStatus.pending,
  PaymentStatus.documentUploaded,
};

/// `GET payments` sorgusu (aile anahtarı).
@immutable
class PaymentsQuery {
  const PaymentsQuery({
    this.statuses = defaultPaymentStatuses,
    this.overdueOnly = false,
    this.customer,
    this.search = '',
  });

  /// Boş küme = tüm durumlar.
  final Set<PaymentStatus> statuses;
  final bool overdueOnly;
  final CustomerOption? customer;
  final String search;

  bool get isFiltered =>
      !setEquals(statuses, defaultPaymentStatuses) ||
      overdueOnly ||
      customer != null ||
      search.isNotEmpty;

  PaymentsQuery copyWith({
    Set<PaymentStatus>? statuses,
    bool? overdueOnly,
    CustomerOption? Function()? customer,
    String? search,
  }) => PaymentsQuery(
    statuses: statuses ?? this.statuses,
    overdueOnly: overdueOnly ?? this.overdueOnly,
    customer: customer == null ? this.customer : customer(),
    search: search ?? this.search,
  );

  /// Sorgu parametreleri (çoklu durum `statuses`; boşsa `status=all`).
  Map<String, dynamic> toQuery() {
    final codes = [
      for (final s in PaymentStatus.values)
        if (statuses.contains(s)) s.code,
    ];
    return {
      if (codes.isEmpty) 'status': 'all' else 'statuses': codes,
      'customerId': customer?.customerId,
      if (overdueOnly) 'overdue': true,
      'q': search,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is PaymentsQuery &&
      setEquals(other.statuses, statuses) &&
      other.overdueOnly == overdueOnly &&
      other.customer == customer &&
      other.search == search;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(statuses),
    overdueOnly,
    customer,
    search,
  );
}

/// Portföy durum süzgeci.
enum InstrumentFilter {
  open('open', 'Açık'),
  bounced('5', 'Karşılıksız'),
  protested('7', 'Protestolu'),
  collected('4', 'Tahsil edildi'),
  all('all', 'Tümü');

  const InstrumentFilter(this.key, this.label);
  final String key;
  final String label;
}

/// `GET payments/instruments` sorgusu.
@immutable
class InstrumentsQuery {
  const InstrumentsQuery({
    this.kind,
    this.filter = InstrumentFilter.open,
    this.search = '',
  });

  final InstrumentKind? kind;
  final InstrumentFilter filter;
  final String search;

  bool get isFiltered =>
      kind != null || filter != InstrumentFilter.open || search.isNotEmpty;

  InstrumentsQuery copyWith({
    InstrumentKind? Function()? kind,
    InstrumentFilter? filter,
    String? search,
  }) => InstrumentsQuery(
    kind: kind == null ? this.kind : kind(),
    filter: filter ?? this.filter,
    search: search ?? this.search,
  );

  @override
  bool operator ==(Object other) =>
      other is InstrumentsQuery &&
      other.kind == kind &&
      other.filter == filter &&
      other.search == search;

  @override
  int get hashCode => Object.hash(kind, filter, search);
}

/// Tahsilat uçları (spec §B.8; yalnızca kullanıcının bayisi).
class PaymentsRepository {
  PaymentsRepository(this.api);

  final ApiClient api;

  Future<PagedResult<PaymentRow>> list(
    PaymentsQuery q, {
    int page = 1,
    int pageSize = 25,
  }) => api.get(
    'payments',
    query: {...q.toQuery(), 'page': page, 'pageSize': pageSize},
    parse: (j) => PagedResult.fromJson(j, PaymentRow.fromJson),
  );

  Future<PaymentDetail> detail(int orderId) =>
      api.get('payments/$orderId', parse: PaymentDetail.fromJson);

  /// Ödeme durumunu değiştirir (204). Yalnızca `allowedTransitions`; gerekçe `noteRequiredFor`.
  /// [idempotencyKey]: niyet başına tek anahtar (C.4a); belirsiz sonuçta aynı anahtarla yinelenir.
  Future<void> changeStatus(
    int orderId, {
    required PaymentStatus to,
    required String concurrencyToken,
    String? note,
    String? attachmentPublicId,
    String? idempotencyKey,
  }) {
    final n = note?.trim();
    return api.post<void>(
      'payments/$orderId/status',
      body: {
        'toStatus': to.code,
        if (n != null && n.isNotEmpty) 'note': n,
        'concurrencyToken': concurrencyToken,
        'attachmentPublicId': ?attachmentPublicId,
      },
      idempotencyKey: idempotencyKey,
    );
  }

  Future<PagedResult<Instrument>> instruments(
    InstrumentsQuery q, {
    int page = 1,
    int pageSize = 25,
  }) => api.get(
    'payments/instruments',
    query: {
      'kind': q.kind?.code,
      'status': q.filter.key,
      'q': q.search,
      'page': page,
      'pageSize': pageSize,
    },
    parse: (j) => PagedResult.fromJson(j, Instrument.fromJson),
  );

  Future<void> changeInstrumentStatus(
    int id, {
    required InstrumentStatus to,
    String? note,
    String? idempotencyKey,
  }) {
    final n = note?.trim();
    return api.post<void>(
      'payments/instruments/$id/status',
      body: {'toStatus': to.code, if (n != null && n.isNotEmpty) 'note': n},
      idempotencyKey: idempotencyKey,
    );
  }

  /// Cari süzgeci (B4 `bayi/customers`; yetki yoksa ekran yalnızca aramayla çalışır).
  Future<List<CustomerOption>> customers(String q) => api.get(
    'bayi/customers',
    query: {'q': q, 'page': 1, 'pageSize': 30},
    quiet403: true,
    parse: (j) => PagedResult.fromJson(j, CustomerOption.fromJson).items,
  );
}

final paymentsRepositoryProvider = Provider<PaymentsRepository>(
  (ref) => PaymentsRepository(ref.watch(apiClientProvider)),
);
