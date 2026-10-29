import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tasks/task_inbox.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/connectivity.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/tr_time.dart';
import '../application/home_controller.dart';
import '../application/orders_list_controller.dart';
import '../copy.dart';
import '../data/order_models.dart';
import 'widgets/common.dart';
import 'widgets/order_parts.dart';
import 'widgets/order_row_card.dart';

/// Siparişler (spec A.4; tasarım v4 §5 ekran 04): sayfa bandı "Siparişler" ve canlı durum satırı
/// ("1 teklif onayınızı bekliyor"; iş yoksa "2 sipariş sürüyor") + ⌕ → tek anahtar
/// [AknSegmented] (Onay bekleyen n · Aktif · Geçmiş; onay bekleyen varken onunla açılır) → tek
/// defter: satırlar kutusuz, aralarında ince çizgi ([OrderRow]). Geçmiş güne göre gruplanır. Arama
/// banttaki ⌕ ile açılan şeritte (sunucu araması); sonsuz kaydırma, çevrimdışı ilk sayfa ("Son
/// güncelleme"). Sekme değişince liste dokunulan yöne kayarak gelir.
class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key, this.initialSegment});

  /// `/orders?segment=decision`.
  final OrderSegment? initialSegment;

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  late OrderSegment _segment = widget.initialSegment ?? OrderSegment.active;
  final _query = TextEditingController();
  bool _searchOpen = false;

  /// Son geçişin yönü (paylaşılan eksen kayması).
  bool _reverse = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialSegment == null) {
      // Onay bekleyen teklif varken onunla açılır.
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
    if (s != null && s != old.initialSegment && s != _segment) {
      _reverse = s.index < _segment.index;
      _segment = s;
      // Sağlayıcı kurulum sırasında değiştirilmez: arama bir sonraki karede taşınır.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncQuery(s);
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _select(OrderSegment s) {
    if (s == _segment) return;
    setState(() {
      _reverse = s.index < _segment.index;
      _segment = s;
    });
    _syncQuery(s);
  }

  /// Açılan bölüm şeritteki aramayı taşır.
  void _syncQuery(OrderSegment s) {
    final q = _query.text.trim();
    if (ref.read(ordersListProvider(s)).query != q) {
      ref.read(ordersListProvider(s).notifier).search(q);
    }
  }

  void _search(String q) =>
      ref.read(ordersListProvider(_segment).notifier).search(q.trim());

  void _closeSearch() {
    setState(() => _searchOpen = false);
    if (ref.read(ordersListProvider(_segment)).query.isNotEmpty) _search('');
  }

  void _clearSearch() {
    _query.clear();
    _search('');
  }

  /// Bandın durum satırı (v4 §3.2): sırası görüntüleyende olan teklifler ([mine]: görev kutusunun
  /// teklif işleri, ana sayfa = Onaylar rozeti = Bende ile aynı sayı) için Pas "1 teklif onayınızı
  /// bekliyor"; onay bekleyen teklifler başkasını bekliyorsa (bayinin finansı, şirketin onaylayanı,
  /// karar yetkisi yok) sakin "2 teklif onay bekliyor"; iş yoksa "2 sipariş sürüyor" (Aktif listesi
  /// yüklüyse).
  Object? _status(int decisions, int mine) {
    if (mine > 0) {
      return AknStatusClause.yourMove(
        OrdersCopy.decisionsWaiting(mine, yours: true),
      );
    }
    if (decisions > 0) {
      return OrdersCopy.decisionsWaiting(decisions, yours: false);
    }
    if (!ref.exists(ordersListProvider(OrderSegment.active))) return null;
    final active = ref.watch(ordersListProvider(OrderSegment.active));
    if (!active.loaded || active.query.isNotEmpty) return null;
    return OrdersCopy.ordersRunning(active.totalCount);
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(customerHomeProvider).data;
    // Panel eşitliği (tek kural, `CustomerDecider`): sıra sizde olan teklifler görev kutusundan; talep
    // edenin eşik üstü teklifi onaylayanı bekler, band ona "onay bekliyor" der.
    final mine = ref.watch(
      customerTasksProvider.select(
        (inbox) => inbox.items
            .where((t) => t.counts && t.kind == TaskKind.quoteDecision)
            .length,
      ),
    );
    final decisions = home?.dashboard.pendingDecisionTotal ?? 0;
    final s = ref.watch(ordersListProvider(_segment));
    return AppScaffold(
      title: OrdersCopy.myOrders,
      bandIcon: PhosphorIconsRegular.receipt,
      status: _status(decisions, mine),
      refreshing: s.loading && s.loaded,
      actions: [
        AknSearchReveal.button(
          semanticLabel: 'Siparişlerde ara',
          onPressed: () => setState(() => _searchOpen = true),
        ),
      ],
      body: Column(
        children: [
          ContentWidth(
            child: AknSearchReveal(
              open: _searchOpen,
              controller: _query,
              hint: OrdersCopy.searchHint,
              onChanged: _search,
              onClose: _closeSearch,
            ),
          ),
          ContentWidth(
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: AknSegmented<OrderSegment>(
                value: _segment,
                onChanged: _select,
                segments: [
                  for (final seg in OrderSegment.values)
                    FilterOption(
                      value: seg,
                      label: seg.label,
                      count: seg == OrderSegment.decision && decisions > 0
                          ? decisions
                          : null,
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SharedAxisSwitcher(
              reverse: _reverse,
              duration: AknMotion.thumb,
              child: KeyedSubtree(
                key: ValueKey(_segment),
                child: _OrdersList(
                  segment: _segment,
                  showStation: (home?.stations.length ?? 0) > 1,
                  onClearSearch: _clearSearch,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bir bölümün listesi: tek defter (Geçmiş'te gün başlıklarıyla birden çok defter), tembel
/// kurulur. Satırlar ilk açılışta (ve yeni aramada) defterin içine dökülür; kaydırınca gelenler
/// beklemeden durur.
class _OrdersList extends ConsumerStatefulWidget {
  const _OrdersList({
    required this.segment,
    required this.onClearSearch,
    required this.showStation,
  });

  final OrderSegment segment;
  final VoidCallback onClearSearch;
  final bool showStation;

  @override
  ConsumerState<_OrdersList> createState() => _OrdersListState();
}

class _OrdersListState extends ConsumerState<_OrdersList> {
  /// İlk satırların dökülme penceresi (sonra kurulan satır kaydırmayla gelir, oynamaz).
  final Stopwatch _clock = Stopwatch()..start();
  String? _query;

  bool get _pour => _clock.elapsed < const Duration(milliseconds: 900);

  @override
  Widget build(BuildContext context) {
    final segment = widget.segment;
    final s = ref.watch(ordersListProvider(segment));
    final ctrl = ref.read(ordersListProvider(segment).notifier);
    final online = ref.watch(isOnlineProvider);
    final policy = ref.watch(accessPolicyProvider);
    if (_query != s.query) {
      // Yeni arama sonuçları yeniden dökülür.
      _query = s.query;
      _clock
        ..reset()
        ..start();
    }

    if (s.isFirstLoad) {
      return const SkeletonList(itemCount: 4, lines: 3, leading: false);
    }
    if (s.showError) {
      final f = s.error!;
      if (f is OfflineFailure || (!online && !s.loaded)) {
        return _scrollable(
          EmptyState.compact(
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
          EmptyState.compact(
            title: OrdersCopy.noResults(s.query),
            message: OrdersCopy.emptyFilteredMessage,
            illustration: AknIllustration.search,
            actionLabel: OrdersCopy.clearFilters,
            onAction: widget.onClearSearch,
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
          canCreate
              ? OrdersCopy.emptyActiveMessage
              : OrdersCopy.emptyActiveMessageNoCreate,
        ),
        OrderSegment.history => (
          OrdersCopy.emptyHistoryTitle,
          OrdersCopy.emptyHistoryMessage,
        ),
      };
      return _scrollable(
        EmptyState.compact(
          title: title,
          message: message,
          illustration: AknIllustration.orders,
          actionLabel: canCreate && segment != OrderSegment.history
              ? OrdersCopy.newOrder
              : null,
          onAction: canCreate && segment != OrderSegment.history
              ? () => context.push(AppRoutes.orderNew)
              : null,
        ),
        ctrl.refresh,
      );
    }

    // Defterler: Geçmiş güne göre gruplanır, diğer bölümler tek defter.
    final groups = <(String?, List<CustomerOrderRow>)>[];
    for (final row in s.items) {
      final day = segment == OrderSegment.history
          ? _dayHeader(row.requestedDeliveryDate ?? row.createdAt)
          : null;
      if (groups.isEmpty || groups.last.$1 != day) {
        groups.add((day, <CustomerOrderRow>[]));
      }
      groups.last.$2.add(row);
    }
    final pour = _pour;
    var index = 0;
    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: LastUpdatedNote(
          updatedAt: s.updatedAt,
          fromCache: s.fromCache,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        ),
      ),
      for (final (i, (day, rows)) in groups.indexed) ...[
        if (day != null)
          SliverToBoxAdapter(
            child: ContentWidth(
              child: AknLedgerGroup(
                title: day,
                padding: EdgeInsets.fromLTRB(24, i == 0 ? 6 : 16, 24, 8),
              ),
            ),
          ),
        LedgerSliver(
          first: i == 0 && day == null,
          rows: [
            for (final row in rows)
              _row(
                row,
                pourIndex: pour ? index++ : null,
                onTap: () => context.push(AppRoutes.order(row.id)),
              ),
          ],
        ),
      ],
      SliverToBoxAdapter(
        child: s.loadingMore
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: ChevronSpinner(size: 24)),
              )
            : SizedBox(height: s.hasMore ? 48 : 8),
      ),
    ];
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
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            ...slivers,
            SliverPadding(
              padding: EdgeInsets.only(
                bottom: 24 + MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    CustomerOrderRow row, {
    required int? pourIndex,
    required VoidCallback onTap,
  }) {
    final child = OrderRow(
      row: row,
      segment: widget.segment,
      showStation: widget.showStation,
      onTap: onTap,
    );
    final i = pourIndex;
    return i == null ? child : AknRowPour(index: i, child: child);
  }

  /// "Bugün", "Dün", "18 Ekim".
  static String? _dayHeader(DateTime? at) {
    if (at == null) return null;
    final diff = TrTime.dayDiff(TrTime.now(), at);
    return switch (diff) {
      0 => 'Bugün',
      -1 => 'Dün',
      1 => 'Yarın',
      _ => dayMonthLong(at),
    };
  }

  Widget _scrollable(Widget child, Future<void> Function() onRefresh) =>
      PullToRefresh(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 32),
            FadeUp(offset: 16, scale: 0.97, child: child),
          ],
        ),
      );
}
