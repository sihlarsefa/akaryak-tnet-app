import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/connectivity.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../application/home_controller.dart';
import '../application/orders_list_controller.dart';
import '../copy.dart';
import '../data/order_models.dart';
import 'templates_page.dart';
import 'widgets/common.dart';
import 'widgets/order_row_card.dart';

/// Siparişlerim (spec A.4): Karar bekleyen / Aktif / Geçmiş, arama, sonsuz kaydırma, çevrimdışı
/// ilk sayfa ("Son güncelleme").
class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key, this.initialSegment});

  /// `/orders?segment=decision`.
  final OrderSegment? initialSegment;

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  late OrderSegment _segment = widget.initialSegment ?? OrderSegment.active;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialSegment == null) {
      // Karar bekleyen varsa onunla açılır.
      final waiting =
          ref.read(customerHomeProvider).data?.dashboard.pendingDecisionTotal ??
          0;
      if (waiting > 0) _segment = OrderSegment.decision;
    }
  }

  @override
  void didUpdateWidget(OrdersPage old) {
    super.didUpdateWidget(old);
    final s = widget.initialSegment;
    if (s != null && s != old.initialSegment) setState(() => _segment = s);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _select(OrderSegment s) {
    if (s == _segment) return;
    setState(() => _segment = s);
    final q = _search.text.trim();
    final state = ref.read(ordersListProvider(s));
    if (state.query != q) {
      ref.read(ordersListProvider(s).notifier).search(q);
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(customerHomeProvider).data;
    final policy = ref.watch(accessPolicyProvider);
    final decisions = home?.dashboard.pendingDecisionTotal;
    final s = ref.watch(ordersListProvider(_segment));
    return AppScaffold(
      title: OrdersCopy.myOrders,
      refreshing: s.loading && s.loaded,
      actions: [
        if (policy.can(Pg.customerCreateOrder))
          AknIconButton(
            icon: Icons.bookmarks_outlined,
            semanticLabel: OrdersCopy.templates,
            onPressed: () => context.push(templatesRoute),
          ),
      ],
      body: Column(
        children: [
          const SizedBox(height: 8),
          A2Segmented<OrderSegment>(
            segments: [
              FilterOption(
                value: OrderSegment.decision,
                label: OrderSegment.decision.label,
                count: decisions == null || decisions == 0 ? null : decisions,
              ),
              FilterOption(
                value: OrderSegment.active,
                label: OrderSegment.active.label,
              ),
              FilterOption(
                value: OrderSegment.history,
                label: OrderSegment.history.label,
              ),
            ],
            value: _segment,
            onChanged: _select,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SearchField(
              controller: _search,
              hint: OrdersCopy.searchHint,
              onChanged: (q) =>
                  ref.read(ordersListProvider(_segment).notifier).search(q),
            ),
          ),
          Expanded(
            child: FadeThroughSwitcher(
              child: KeyedSubtree(
                key: ValueKey(_segment),
                child: _OrdersList(
                  segment: _segment,
                  onClearSearch: () {
                    _search.clear();
                    ref.read(ordersListProvider(_segment).notifier).search('');
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdersList extends ConsumerWidget {
  const _OrdersList({required this.segment, required this.onClearSearch});

  final OrderSegment segment;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(ordersListProvider(segment));
    final ctrl = ref.read(ordersListProvider(segment).notifier);
    final online = ref.watch(isOnlineProvider);
    final policy = ref.watch(accessPolicyProvider);

    if (s.isFirstLoad) return const SkeletonList(itemCount: 4, lines: 3);
    if (s.showError) {
      final f = s.error!;
      if (f is OfflineFailure || (!online && !s.loaded)) {
        return _scrollable(
          EmptyState(
            title: OrdersCopy.offlineNoData,
            message: 'Bağlantı gelince liste kendiliğinden yenilenir.',
            illustration: AknIllustration.offline,
            actionLabel: OrdersCopy.retry,
            onAction: ctrl.refresh,
          ),
          ctrl.refresh,
        );
      }
      return _scrollable(
        FailureView(failure: f, onRetry: ctrl.refresh),
        ctrl.refresh,
      );
    }
    if (s.items.isEmpty) {
      if (s.query.isNotEmpty) {
        return _scrollable(
          EmptyState(
            title: OrdersCopy.emptyFiltered,
            message: OrdersCopy.emptyFilteredMessage,
            illustration: AknIllustration.search,
            actionLabel: OrdersCopy.clearFilters,
            onAction: onClearSearch,
          ),
          ctrl.refresh,
        );
      }
      final canCreate = policy.can(Pg.customerCreateOrder, Perm.create);
      final (title, message) = switch (segment) {
        OrderSegment.decision => (
          OrdersCopy.emptyDecisionTitle,
          OrdersCopy.emptyDecisionMessage,
        ),
        OrderSegment.active => (
          OrdersCopy.emptyActiveTitle,
          OrdersCopy.emptyActiveMessage,
        ),
        OrderSegment.history => (
          OrdersCopy.emptyHistoryTitle,
          OrdersCopy.emptyHistoryMessage,
        ),
      };
      return _scrollable(
        EmptyState(
          title: title,
          message: message,
          illustration: AknIllustration.orders,
          actionLabel: canCreate && segment != OrderSegment.history
              ? OrdersCopy.newOrder
              : null,
          onAction: canCreate ? () => context.push(AppRoutes.orderNew) : null,
        ),
        ctrl.refresh,
      );
    }

    final count = s.items.length + 2;
    return PullToRefresh(
      onRefresh: ctrl.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if ((n is ScrollUpdateNotification || n is OverscrollNotification) &&
              n.metrics.extentAfter < 400 &&
              s.hasMore &&
              !s.loadingMore) {
            Future.microtask(ctrl.loadMore);
          }
          return false;
        },
        child: StaggerScope(
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            itemCount: count,
            itemBuilder: (context, i) {
              if (i == 0) {
                return LastUpdatedNote(
                  updatedAt: s.updatedAt,
                  fromCache: s.fromCache,
                );
              }
              if (i == count - 1) {
                if (s.loadingMore) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: ChevronSpinner(size: 24)),
                  );
                }
                if (s.hasMore) return const SizedBox(height: 48);
                return const SizedBox(height: 8);
              }
              final row = s.items[i - 1];
              return StaggerItem(
                index: i - 1,
                child: ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: OrderRowCard(
                      row: row,
                      onTap: () => context.push(AppRoutes.order(row.id)),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _scrollable(Widget child, Future<void> Function() onRefresh) =>
      PullToRefresh(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [const SizedBox(height: 32), child],
        ),
      );
}
