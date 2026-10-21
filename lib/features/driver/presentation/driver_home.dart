import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/outbox_op.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../weather/api.dart';
import '../application/driver_home_state.dart';
import '../application/driver_lists.dart';
import '../application/driver_ops.dart';
import '../copy.dart';
import '../data/deliver_draft.dart';
import '../data/driver_models.dart';
import '../data/driver_outbox.dart';
import '../driver_paths.dart';
import 'widgets/driver_tabs.dart';
import 'widgets/navigation.dart';
import 'widgets/next_stop_hero.dart';
import 'widgets/op_status.dart';
import 'widgets/shipment_card.dart';
import 'widgets/tip_card.dart';

/// Şoför ana sayfası / Teslimatlarım (spec A.4 A7). Yalnızca şoför olanlarda alt menünün kökü; kendisi
/// teslim eden bayi personeli için `/driver` ile açılır (geri düğmesiyle). Sınıf adı ve kurucu imzası
/// sabittir (M0a).
///
/// - Lacivert başlıkta sıradaki teslimat: saat penceresi, litre, plaka, yol tarifi, sonraki adım;
///   altında sürüş uyarısı ve hava durumu.
/// - Yarım kalan teslimat, bekleyen işlemler, ilk girişte "Teslimatı kaydırarak onaylayın" ipucu.
/// - Bugün / Yaklaşan / Geçmiş (sunucu kapsamları `today`, `upcoming`, `history`); itirazlılar en üstte,
///   itiraz notu ve "Teslimatı düzelt" ile.
/// - Çevrimdışı: önbellekteki liste "Son güncelleme" ile; aşağı çekince yenilenir.
class DriverHome extends ConsumerStatefulWidget {
  const DriverHome({super.key});

  @override
  ConsumerState<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends ConsumerState<DriverHome> {
  DriverTab _tab = DriverTab.today;
  late final AppLifecycleListener _lifecycle;

  /// Oturum başına bir kez: sahipsiz teslim dosyalarını temizle.
  static String? _sweptFor;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final uid = ref.read(currentUserIdProvider);
      if (uid == null || _sweptFor == uid) return;
      _sweptFor = uid;
      unawaited(ref.read(driverCommandsProvider).sweepFiles());
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _onResume() {
    final now = DateTime.now().toUtc();
    for (final tab in {DriverTab.today, _tab}) {
      final s = ref.read(driverListProvider(tab)).valueOrNull;
      final at = s?.updatedAt;
      if (at == null || now.difference(at) > const Duration(seconds: 30)) {
        unawaited(ref.read(driverListProvider(tab).notifier).refresh());
      }
    }
  }

  Future<void> _refresh() async {
    ref.read(driverDraftsProvider.notifier).reload();
    await Future.wait([
      ref.read(driverListProvider(DriverTab.today).notifier).refresh(),
      if (_tab != DriverTab.today)
        ref.read(driverListProvider(_tab).notifier).refresh(),
    ]);
  }

  bool _onScroll(ScrollNotification n) {
    if (_tab == DriverTab.today) return false;
    if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 480) {
      unawaited(ref.read(driverListProvider(_tab).notifier).loadMore());
    }
    return false;
  }

  void _open(DriverShipmentRow row) =>
      unawaited(context.push(DriverPaths.detail(row.id)));

  void _deliver(DriverShipmentRow row) =>
      unawaited(context.push(DriverPaths.deliver(row.id)));

  Future<void> _navigate(DriverShipmentRow row) async {
    try {
      final s = await ref.read(driverShipmentProvider(row.id).future);
      if (!mounted) return;
      await openNavigation(
        context,
        lat: s.detail.latitude,
        lng: s.detail.longitude,
        address: s.detail.fullAddress,
      );
    } on AppFailure catch (f) {
      if (mounted) AppToast.error(f.message, context: context);
    }
  }

  Future<void> _fixOp(OutboxOp op) async {
    final commands = ref.read(driverCommandsProvider);
    if (op.type == DriverOutbox.deliver) {
      final draft = await commands.draftForFix(op.id);
      if (!mounted || draft == null) return;
      await context.push(DriverPaths.deliver(draft.shipmentId));
    } else {
      await commands.retry(op.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayAsync = ref.watch(driverListProvider(DriverTab.today));
    final upcomingAsync = ref.watch(driverListProvider(DriverTab.upcoming));
    final tabAsync = switch (_tab) {
      DriverTab.today => todayAsync,
      DriverTab.upcoming => upcomingAsync,
      DriverTab.history => ref.watch(driverListProvider(DriverTab.history)),
    };
    final ops = ref.watchDriverOps();
    final drafts = ref.watch(driverDraftsProvider);
    final showTip = ref.watch(driverTipVisibleProvider);
    final next = pickNextStop(
      todayAsync.valueOrNull?.items ?? const [],
      TrTime.now(),
    );
    final tabState = tabAsync.valueOrNull;
    final now = TrTime.now();

    final todayOpen = todayAsync.valueOrNull?.open.length;
    final upcomingCount = upcomingAsync.valueOrNull?.totalCount;
    final disputed = [
      for (final r
          in todayAsync.valueOrNull?.items ?? const <DriverShipmentRow>[])
        if (r.isDisputed && !(ops[r.id]?.deliverWaiting ?? false)) r,
    ];

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: NextStopHero(
          onOpen: _open,
          onDeliver: _deliver,
          onNavigate: (r) => unawaited(_navigate(r)),
        ),
      ),
      if (next != null) SliverToBoxAdapter(child: _NextStopWeather(row: next)),
      if (disputed.isNotEmpty)
        SliverToBoxAdapter(
          child: _DisputeAlert(
            rows: disputed,
            onFix: _deliver,
            onShow: () => setState(() => _tab = DriverTab.today),
          ),
        ),
      if (drafts.isNotEmpty)
        SliverToBoxAdapter(
          child: _ResumeBanner(
            draft: _latest(drafts.values),
            onResume: (d) =>
                unawaited(context.push(DriverPaths.deliver(d.shipmentId))),
          ),
        ),
      const SliverToBoxAdapter(
        child: DriverOutboxStrip(margin: EdgeInsets.fromLTRB(16, 12, 16, 0)),
      ),
      if (showTip)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: DriverTipCard(
              onDismiss: () => unawaited(
                ref.read(driverTipVisibleProvider.notifier).dismiss(),
              ),
            ),
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 4),
          child: DriverTabs<DriverTab>(
            value: _tab,
            onChanged: (t) => setState(() => _tab = t),
            segments: [
              FilterOption(
                value: DriverTab.today,
                label: DriverTab.today.label,
                count: todayOpen,
              ),
              FilterOption(
                value: DriverTab.upcoming,
                label: DriverTab.upcoming.label,
                count: upcomingCount,
              ),
              FilterOption(
                value: DriverTab.history,
                label: DriverTab.history.label,
              ),
            ],
          ),
        ),
      ),
      if (tabState != null &&
          (tabState.fromCache || tabState.refreshError != null))
        SliverToBoxAdapter(child: _FreshnessLine(state: tabState)),
      ..._content(tabAsync, ops, drafts, now),
      const SliverToBoxAdapter(child: SizedBox(height: 32)),
    ];

    return AppScaffold(
      navy: true,
      title: DriverCopy.title,
      refreshing: tabState?.refreshing ?? false,
      body: PullToRefresh(
        onRefresh: _refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: slivers,
          ),
        ),
      ),
    );
  }

  static DeliverDraft _latest(Iterable<DeliverDraft> drafts) =>
      drafts.reduce((a, b) => a.savedAt.isAfter(b.savedAt) ? a : b);

  List<Widget> _content(
    AsyncValue<DriverListState> async,
    Map<int, DriverShipmentOps> ops,
    Map<int, DeliverDraft> drafts,
    DateTime now,
  ) {
    final state = async.valueOrNull;
    if (state == null) {
      if (async.hasError) {
        return [SliverToBoxAdapter(child: _errorView(async.error))];
      }
      return const [
        SliverToBoxAdapter(
          child: Shimmer(
            child: Column(
              children: [
                SizedBox(height: 8),
                SkeletonCard(lines: 3),
                SkeletonCard(lines: 3),
                SkeletonCard(lines: 3),
              ],
            ),
          ),
        ),
      ];
    }
    if (state.isEmpty) {
      final (title, message) = switch (_tab) {
        DriverTab.today => (
          DriverCopy.emptyTodayTitle,
          DriverCopy.emptyTodayMessage,
        ),
        DriverTab.upcoming => (
          DriverCopy.emptyUpcomingTitle,
          DriverCopy.emptyUpcomingMessage,
        ),
        DriverTab.history => (
          DriverCopy.emptyHistoryTitle,
          DriverCopy.emptyHistoryMessage,
        ),
      };
      return [
        SliverToBoxAdapter(
          child: EmptyState(
            title: title,
            message: message,
            illustration: AknIllustration.delivery,
            compact: true,
          ),
        ),
      ];
    }

    Widget card(DriverShipmentRow r, int index) => StaggerItem(
      index: index,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ShipmentCard(
          row: r,
          now: now,
          ops: ops[r.id],
          draft: drafts[r.id],
          history: _tab == DriverTab.history,
          onOpen: () => _open(r),
          onCorrect: () => _deliver(r),
          onResume: () => _deliver(r),
          onFixOp: (op) => unawaited(_fixOp(op)),
        ),
      ),
    );

    final out = <Widget>[];
    if (_tab == DriverTab.today) {
      final open = state.open;
      final closed = state.closed;
      var i = 0;
      final children = <Widget>[
        if (open.isNotEmpty)
          SectionHeader(
            title: DriverCopy.sectionTodo,
            count: open.length,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          ),
        for (final r in open) card(r, i++),
        if (closed.isNotEmpty)
          SectionHeader(
            title: DriverCopy.sectionDone,
            count: closed.length,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          ),
        for (final r in closed) card(r, i++),
      ];
      out.add(
        StaggerScope(
          key: const ValueKey('today'),
          child: SliverList.list(children: children),
        ),
      );
    } else {
      out.add(const SliverToBoxAdapter(child: SizedBox(height: 12)));
      out.add(
        StaggerScope(
          key: ValueKey(_tab),
          child: SliverList.builder(
            itemCount: state.items.length,
            itemBuilder: (context, i) => card(state.items[i], i),
          ),
        ),
      );
      if (state.loadingMore) {
        out.add(
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: ChevronSpinner(size: 22)),
            ),
          ),
        );
      } else if (state.loadMoreError != null) {
        out.add(
          SliverToBoxAdapter(
            child: Center(
              child: AknButton.ghost(
                label: '${DriverCopy.loadMoreFailed} ${DriverCopy.opRetry}',
                icon: Icons.refresh_rounded,
                onPressed: () => unawaited(
                  ref.read(driverListProvider(_tab).notifier).loadMore(),
                ),
              ),
            ),
          ),
        );
      }
    }
    return out;
  }

  Widget _errorView(Object? error) {
    final f = AppFailure.from(error ?? const UnknownFailure());
    void retry() =>
        unawaited(ref.read(driverListProvider(_tab).notifier).refresh());
    return switch (f) {
      OfflineFailure() => EmptyState(
        title: DriverCopy.offlineNoCacheTitle,
        message: DriverCopy.offlineNoCacheMessage,
        illustration: AknIllustration.offline,
        actionLabel: DriverCopy.opRetry,
        onAction: retry,
        compact: true,
      ),
      ForbiddenFailure() => const EmptyState(
        title: DriverCopy.forbiddenTitle,
        message: DriverCopy.forbiddenMessage,
        illustration: AknIllustration.locked,
        compact: true,
      ),
      _ => ErrorState(
        message: f.message,
        traceId: f.traceId,
        onRetry: retry,
        compact: true,
      ),
    };
  }
}

/// Sıradaki teslimatın hava durumu ve sürüş uyarısı (koordinat ve özellik açıksa).
class _NextStopWeather extends ConsumerWidget {
  const _NextStopWeather({required this.row});

  final DriverShipmentRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(appConfigProvider.select((c) => c.features.weather));
    if (!on || !row.hasCoordinates) return const SizedBox.shrink();
    final d = ref.watch(driverShipmentProvider(row.id)).valueOrNull?.detail;
    final lat = d?.latitude;
    final lng = d?.longitude;
    if (lat == null || lng == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DrivingAlertBanner(lat: lat, lng: lng, at: row.scheduledAt),
          WeatherCard(lat: lat, lng: lng),
        ],
      ),
    );
  }
}

/// İtirazlı teslimat uyarısı (listenin üstünde, kaydırmadan görünür): müşteri notu + "Teslimatı düzelt".
class _DisputeAlert extends StatelessWidget {
  const _DisputeAlert({
    required this.rows,
    required this.onFix,
    required this.onShow,
  });

  final List<DriverShipmentRow> rows;
  final ValueChanged<DriverShipmentRow> onFix;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final first = rows.first;
    final many = rows.length > 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: AknBanner(
        tone: AknTone.danger,
        icon: Icons.report_rounded,
        title: many
            ? '${rows.length} teslimat düzeltme bekliyor'
            : '${DriverCopy.disputedTitle} · ${first.code}',
        message: [
          ?first.customerTitle,
          first.disputeNote ?? DriverCopy.disputedFallback,
        ].join(': '),
        actionLabel: many ? DriverCopy.opsShow : DriverCopy.actionFix,
        onAction: many ? onShow : () => onFix(first),
      ),
    );
  }
}

class _ResumeBanner extends StatelessWidget {
  const _ResumeBanner({required this.draft, required this.onResume});

  final DeliverDraft draft;
  final ValueChanged<DeliverDraft> onResume;

  @override
  Widget build(BuildContext context) {
    final step = DriverCopy.stepShort[draft.step.index];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: AknBanner(
        tone: AknTone.brand,
        icon: Icons.edit_note_rounded,
        title: DriverCopy.resumeDraft,
        message: DriverCopy.resumeDraftBody(draft.code, step),
        actionLabel: DriverCopy.actionResume,
        onAction: () => onResume(draft),
      ),
    );
  }
}

class _FreshnessLine extends StatelessWidget {
  const _FreshnessLine({required this.state});

  final DriverListState state;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final offline = state.refreshError is OfflineFailure;
    final at = state.updatedAt;
    final text = [
      if (at != null) '${DriverCopy.lastUpdated} ${Fmt.relative(at)}',
      if (offline) 'Çevrimdışı',
      if (!offline && state.refreshError != null) state.refreshError!.message,
    ].join(' · ');
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Icon(
            offline ? Icons.cloud_off_rounded : Icons.history_rounded,
            size: 16,
            color: c.dim,
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: t.caption)),
        ],
      ),
    );
  }
}
