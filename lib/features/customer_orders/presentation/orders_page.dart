import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import 'templates_page.dart';
import 'widgets/common.dart';
import 'widgets/order_parts.dart';
import 'widgets/order_row_card.dart';
import 'widgets/search_well.dart';

/// Siparişlerim (spec A.4; tasarım v2 §7.7, pano ekran 4): kök başlık (display) + şablon kısayolu
/// → sekmeler (Karar bekleyen, Aktif, Geçmiş; sayılarıyla, turuncu iğne) → arama kuyusu →
/// ledger satırları → kayıtların nereye gittiğini söyleyen dip cümlesi. Geçmiş güne göre
/// gruplanır. Sunucu araması, sonsuz kaydırma, çevrimdışı ilk sayfa ("Son güncelleme").
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

  /// Sekmedeki sayı: karar bekleyen ana sayfa özetinden; diğerleri yüklenmiş ve aramasız listenin
  /// toplamından (bilinmiyorsa gösterilmez).
  int? _count(OrderSegment s, int? decisions) {
    if (s == OrderSegment.decision) {
      return decisions == null || decisions == 0 ? null : decisions;
    }
    // Açılmamış sekmenin listesi bu yüzden yüklenmez.
    if (s != _segment && !ref.exists(ordersListProvider(s))) return null;
    final st = ref.watch(ordersListProvider(s));
    if (!st.loaded || st.query.isNotEmpty) return null;
    return st.totalCount;
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(customerHomeProvider).data;
    final policy = ref.watch(accessPolicyProvider);
    final decisions = home?.dashboard.pendingDecisionTotal;
    final s = ref.watch(ordersListProvider(_segment));
    return AppScaffold(
      title: OrdersCopy.myOrders,
      largeTitle: true,
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
          _SegmentTabs(
            value: _segment,
            onChanged: _select,
            segments: [
              for (final seg in OrderSegment.values)
                (seg, _count(seg, decisions)),
            ],
          ),
          ContentWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: OrdersSearchWell(
                controller: _search,
                hint: OrdersCopy.searchHint,
                onChanged: (q) =>
                    ref.read(ordersListProvider(_segment).notifier).search(q),
              ),
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

/// Sekmeler (§6.11): etiket 16/20 600 (seçili mürekkep, diğerleri soluk) + sayı 500; seçilinin
/// altında 3 px turuncu iğne, altta 1 px çizgi. Büyük yazıda yatay kayar ve seçili sekme görünür
/// alana getirilir.
class _SegmentTabs extends StatefulWidget {
  const _SegmentTabs({
    required this.value,
    required this.onChanged,
    required this.segments,
  });

  final OrderSegment value;
  final ValueChanged<OrderSegment> onChanged;
  final List<(OrderSegment, int?)> segments;

  @override
  State<_SegmentTabs> createState() => _SegmentTabsState();
}

class _SegmentTabsState extends State<_SegmentTabs> {
  final _keys = {for (final s in OrderSegment.values) s: GlobalKey()};

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(_SegmentTabs old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _reveal();
  }

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[widget.value]?.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: AknMotion.of(context, AknMotion.fast),
      );
      Scrollable.ensureVisible(
        ctx,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        duration: AknMotion.of(context, AknMotion.fast),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (seg, count) in widget.segments)
              _Tab(
                key: _keys[seg],
                label: seg.label,
                count: count,
                selected: seg == widget.value,
                onTap: () => widget.onChanged(seg),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final style = t.button.copyWith(color: selected ? c.ink : c.dim);
    return Semantics(
      button: true,
      selected: selected,
      label: count == null ? label : '$label, $count sipariş',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: c.surfaceAlt,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: style),
                      if (count != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '$count',
                          style: style.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 11),
                  AnimatedContainer(
                    duration: AknMotion.of(context, AknMotion.needle),
                    curve: AknMotion.standard,
                    height: 3,
                    decoration: BoxDecoration(
                      color: selected ? c.logo : Colors.transparent,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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

    // Satırlar (geçmişte gün başlıklarıyla) + dip.
    final entries = <Object>[];
    String? lastDay;
    for (final row in s.items) {
      if (segment == OrderSegment.history) {
        final day = _dayHeader(row.requestedDeliveryDate ?? row.createdAt);
        if (day != null && day != lastDay) {
          entries.add(day);
          lastDay = day;
        } else if (entries.isNotEmpty && entries.last is CustomerOrderRow) {
          entries.add(const _Divider());
        }
      } else if (entries.isNotEmpty) {
        entries.add(const _Divider());
      }
      entries.add(row);
    }
    final footer = switch (segment) {
      OrderSegment.decision => OrdersCopy.decisionFooter,
      OrderSegment.active => OrdersCopy.activeFooter,
      OrderSegment.history => null,
    };
    final count = entries.length + 2;
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
              if (footer == null) return const SizedBox(height: 8);
              return ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Text(
                    footer,
                    style: context.aknText.bodySmall.copyWith(
                      color: context.akn.dim,
                    ),
                  ),
                ),
              );
            }
            final e = entries[i - 1];
            if (e is _Divider) {
              return const ContentWidth(child: AknLedgerDivider());
            }
            if (e is String) {
              return ContentWidth(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, i == 1 ? 8 : 20, 20, 2),
                  child: Semantics(
                    header: true,
                    child: Text(
                      e,
                      style: context.aknText.label.copyWith(
                        color: context.akn.dim,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            }
            final row = e as CustomerOrderRow;
            return ContentWidth(
              child: OrderRowCard(
                row: row,
                onTap: () => context.push(AppRoutes.order(row.id)),
              ),
            );
          },
        ),
      ),
    );
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
          children: [const SizedBox(height: 32), child],
        ),
      );
}

class _Divider {
  const _Divider();
}
