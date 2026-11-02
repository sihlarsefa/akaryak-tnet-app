import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/paged_result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/offline/cache_first.dart';
import '../../../core/offline/revalidate.dart';
import '../../approvals/api.dart';
import '../data/finance_models.dart';
import '../data/finance_repository.dart';

/// Cari finans kartları listesi (süzgeç başına). Önce önbellekteki ilk sayfa, hemen ardından sunucu.
final financeListProvider = NotifierProvider.autoDispose
    .family<FinanceListController, PagedState<FinanceListItem>, FinanceQuery>(
      FinanceListController.new,
    );

class FinanceListController
    extends PagedNotifier<FinanceListItem, FinanceQuery> {
  final _first = FirstPageCache();
  bool _alive = true;

  @override
  PagedState<FinanceListItem> build(FinanceQuery arg) {
    _alive = true;
    ref.onDispose(() => _alive = false);
    ref.listen(revalidateProvider, (_, e) {
      final s = state;
      if (e == null || s.loading || s.refreshing) return;
      if (Freshness.isStale(s.loadedAt, Freshness.list)) unawaited(refresh());
    });
    return super.build(arg);
  }

  @override
  Future<PagedResult<FinanceListItem>> fetchPage(FinanceQuery q, int page) {
    final repo = ref.read(financeRepositoryProvider);
    if (page != 1) return repo.list(q, page: page, pageSize: pageSize);
    return _first.page1(
      peek: () => repo.peekList(q, pageSize: pageSize),
      network: () => repo.list(q, pageSize: pageSize),
      revalidate: () {
        if (_alive) unawaited(refresh());
      },
    );
  }

  @override
  Object? keyOf(FinanceListItem item) => item.stationCustomerId;
}

/// Cari finans kartı: önce önbellekteki kart, arka planda sunucu (değer kalır).
final financeCardProvider = AsyncNotifierProvider.autoDispose
    .family<FinanceCardController, FinanceCard, int>(
      FinanceCardController.new,
    );

class FinanceCardController
    extends CacheFirstFamilyAsyncNotifier<FinanceCard, int> {
  @override
  Future<CachedResponse<FinanceCard>?> peek(int arg) =>
      ref.read(financeRepositoryProvider).peekCard(arg);

  @override
  Future<FinanceCard> fetch(int arg) =>
      ref.read(financeRepositoryProvider).card(arg);
}
