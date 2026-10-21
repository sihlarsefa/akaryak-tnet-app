import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/models/paged_result.dart';
import '../../approvals/api.dart';
import '../data/finance_models.dart';
import '../data/finance_repository.dart';

/// Cari finans kartları listesi (süzgeç başına).
final financeListProvider = NotifierProvider.autoDispose
    .family<FinanceListController, PagedState<FinanceListItem>, FinanceQuery>(
      FinanceListController.new,
    );

class FinanceListController
    extends PagedNotifier<FinanceListItem, FinanceQuery> {
  @override
  Future<PagedResult<FinanceListItem>> fetchPage(FinanceQuery q, int page) =>
      ref
          .read(financeRepositoryProvider)
          .list(q, page: page, pageSize: pageSize);

  @override
  Object? keyOf(FinanceListItem item) => item.stationCustomerId;
}

/// Cari finans kartı.
final financeCardProvider = FutureProvider.autoDispose.family<FinanceCard, int>(
  (ref, stationCustomerId) {
    ref.watch(currentUserIdProvider);
    return ref.read(financeRepositoryProvider).card(stationCustomerId);
  },
);
