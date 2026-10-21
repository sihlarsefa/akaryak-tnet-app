import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/paged_result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_providers.dart';
import 'finance_models.dart';

/// Finans kartı durum süzgeci (`FinanceStatusKeys`).
enum FinanceStatusFilter {
  pending('pending', 'Bekleyen'),
  approved('approved', 'Onaylı'),
  closed('closed', 'Kapalı');

  const FinanceStatusFilter(this.key, this.label);
  final String key;
  final String label;
}

/// `GET finance/customers` sorgusu (aile anahtarı).
@immutable
class FinanceQuery {
  const FinanceQuery({
    this.status,
    this.risk,
    this.reviewOverdue = false,
    this.search = '',
  });

  final FinanceStatusFilter? status;
  final RiskClass? risk;
  final bool reviewOverdue;
  final String search;

  bool get isFiltered =>
      status != null || risk != null || reviewOverdue || search.isNotEmpty;

  FinanceQuery copyWith({
    FinanceStatusFilter? Function()? status,
    RiskClass? Function()? risk,
    bool? reviewOverdue,
    String? search,
  }) => FinanceQuery(
    status: status == null ? this.status : status(),
    risk: risk == null ? this.risk : risk(),
    reviewOverdue: reviewOverdue ?? this.reviewOverdue,
    search: search ?? this.search,
  );

  @override
  bool operator ==(Object other) =>
      other is FinanceQuery &&
      other.status == status &&
      other.risk == risk &&
      other.reviewOverdue == reviewOverdue &&
      other.search == search;

  @override
  int get hashCode => Object.hash(status, risk, reviewOverdue, search);
}

/// Finans uçları (spec §B.8; yalnızca kullanıcının bayisi).
class FinanceRepository {
  FinanceRepository(this.api);

  final ApiClient api;

  Future<PagedResult<FinanceListItem>> list(
    FinanceQuery q, {
    int page = 1,
    int pageSize = 25,
  }) => api.get(
    'finance/customers',
    query: {
      'status': q.status?.key,
      'risk': q.risk?.code,
      if (q.reviewOverdue) 'overdue': true,
      'q': q.search,
      'page': page,
      'pageSize': pageSize,
    },
    parse: (j) => PagedResult.fromJson(j, FinanceListItem.fromJson),
  );

  Future<FinanceCard> card(int stationCustomerId) => api.get(
    'finance/customers/$stationCustomerId',
    parse: FinanceCard.fromJson,
  );
}

final financeRepositoryProvider = Provider<FinanceRepository>(
  (ref) => FinanceRepository(ref.watch(apiClientProvider)),
);
