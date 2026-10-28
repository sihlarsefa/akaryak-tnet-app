import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/outbox_op.dart';
import '../../../core/routing/app_location.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../../weather/api.dart';
import '../application/driver_home_state.dart';
import '../application/driver_lists.dart';
import '../application/driver_ops.dart';
import '../application/location.dart';
import '../application/proximity.dart';
import '../application/route_plan.dart';
import '../copy.dart';
import '../data/deliver_draft.dart';
import '../data/driver_models.dart';
import '../data/driver_outbox.dart';
import '../driver_paths.dart';
import 'widgets/driver_tabs.dart';
import 'widgets/entrance.dart';
import 'widgets/load_bar.dart';
import 'widgets/navigation.dart';
import 'widgets/op_status.dart';
import 'widgets/shipment_card.dart';
import 'widgets/stop_dock.dart';
import 'widgets/stop_plate.dart';
import 'widgets/tip_card.dart';

/// Şoför ana sayfası "Teslimatlarım" (tasarım v3 "Akış", §7.11; spec A.4 A7). Yalnızca şoför
/// olanlarda alt menünün kökü; kendisi teslim eden bayi personeli için `/driver` ile açılır (geri
/// düğmesiyle). Sınıf adı ve kurucu imzası sabittir (M0a). Sürücü kipinde çizilir (§6.30: yazı bir
/// basamak büyük, 64 px düğmeler).
///
/// - Turuncu başlık bandı: "Teslimatlarım", bugünün tarihi ve tırın TR plakası (beyaz içerik).
/// - Sıradaki durak **kahraman kart olarak bandın üstüne yükselir** (ekranın tek plakası):
///   "Sıradaki teslimat, 1 / 3", akan tanker yük çubuğu, müşteri ve adres; ince çizginin altında
///   ADR levhası, bu duraktaki litre (sayaç gibi yuvarlanır), canlı güzergâh çizgisi ve okumalar
///   (plan saati, uzaklık, teslim saatleri). Teslimat kaydedilince sıradaki durak kayarak gelir.
/// - Kartın altında eşitleme hapı ("Eşitlendi 09:58" / çevrimdışı), düzeltme uyarısı, bekleyen
///   işlem şeridi ve kapı notuyla teslim alacak kişinin kartı ("Ara").
/// - Alta yapışık raf: "Yol tarifi" ve "Teslim et" (planlıysa "Yola çık"); birincil olan tırı
///   izler.
/// - Aşağıda: Bugün / Yaklaşan / Geçmiş; duraklar beyaz kartlar olarak sırayla yükselir (sekme
///   değişince yeniden), kaydırdıkça yenileri belirir.
/// - Çevrimdışı: önbellekteki liste; aşağı çekince yenilenir.
class DriverHome extends StatelessWidget {
  const DriverHome({super.key});

  @override
  Widget build(BuildContext context) =>
      const AknDriverScope(child: _DriverHomeView());
}

class _DriverHomeView extends ConsumerStatefulWidget {
  const _DriverHomeView();

  @override
  ConsumerState<_DriverHomeView> createState() => _DriverHomeState();
}

class _DriverHomeState extends ConsumerState<_DriverHomeView> {
  DriverTab _tab = DriverTab.today;
  late final AppLifecycleListener _lifecycle;
  late final ProximityWatch _proximity;

  /// Oturum başına bir kez: sahipsiz teslim dosyalarını temizle.
  static String? _sweptFor;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    _proximity = ProximityWatch(ref.read(driverLocationServiceProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _proximity.start();
      final uid = ref.read(currentUserIdProvider);
      if (uid == null || _sweptFor == uid) return;
      _sweptFor = uid;
      unawaited(ref.read(driverCommandsProvider).sweepFiles());
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _proximity.dispose();
    super.dispose();
  }

  void _onResume() {
    _proximity.resume();
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
    _proximity.resume();
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
    final online = ref.watchOnline();
    final now = TrTime.now();
    final today = todayAsync.valueOrNull;
    final plan = DriverRoutePlan.of(today?.items ?? const [], now, ops: ops);
    final next = plan.next;
    final nextDetail = next == null
        ? null
        : ref.watch(driverShipmentProvider(next.id)).valueOrNull?.detail;
    final tabState = tabAsync.valueOrNull;

    final upcomingCount = upcomingAsync.valueOrNull?.totalCount;
    final disputed = [
      for (final r in today?.items ?? const <DriverShipmentRow>[])
        if (r.isDisputed && !(ops[r.id]?.deliverWaiting ?? false)) r,
    ];
    final plate =
        next?.vehiclePlate ??
        (today?.items ?? const <DriverShipmentRow>[])
            .map((r) => r.vehiclePlate)
            .nonNulls
            .firstOrNull;

    // Büyük yazıda (≥ 1,6×) başlık sabit durmaz, içerikle kayar: yer plakaya ve rafa kalır.
    final largeText = MediaQuery.textScalerOf(context).scale(10) >= 16;
    final header = _DriverHeader(now: now, plate: plate);
    // Sahip kararı G: şoför ana sayfası da turuncu başlık bandıyla açılır (beyaz içerik: avatar,
    // "Teslimatlarım", tarih ve araç plakası). Büyük yazıda başlık içerikle kayan beyaz satırdır.
    final driverName =
        ref.watch(sessionControllerProvider).access?.displayName ?? '';
    final wall = TrTime.wall(now);
    final dateLine =
        '${Fmt.dayLabel(now, now: now)}, ${wall.day} '
        '${Fmt.monthNames[wall.month - 1]} ${Fmt.weekday(now)}';
    final bandHeader = AknHomeHeader(
      greeting: DriverCopy.title,
      company: plate == null ? dateLine : '$dateLine, ${Fmt.plate(plate)}',
      person: driverName.isEmpty ? null : '$driverName, şoför',
      showBell: false,
      onOpenProfile: () => context.openAppLocation(AppRoutes.profile),
    );
    final slivers = <Widget>[
      // Büyük yazıda bant içerikle kayar (sahip kararı G: turuncu bant, beyaz içerik).
      if (largeText)
        SliverToBoxAdapter(
          child: AknBand(
            padding: const EdgeInsets.only(bottom: 10),
            child: header,
          ),
        ),
      // Sıradaki durak bandın üstüne yükselir (kahraman kart); yoksa boş / hata görünümü.
      SliverToBoxAdapter(
        child: _top(todayAsync, plan, nextDetail, ops, drafts, now),
      ),
      SliverToBoxAdapter(
        child: _SyncLine(
          state: today,
          online: online,
          pending: summarizeDriverOps(ops).waiting,
        ),
      ),
      if (disputed.isNotEmpty)
        SliverToBoxAdapter(
          child: _DisputeAlert(
            rows: disputed,
            onOpen: _open,
            onShow: () => setState(() => _tab = DriverTab.today),
          ),
        ),
      const SliverToBoxAdapter(
        child: DriverOutboxStrip(margin: EdgeInsets.fromLTRB(20, 12, 20, 0)),
      ),
      if (next != null && nextDetail != null)
        SliverToBoxAdapter(child: _StopContactCard(detail: nextDetail)),
      if (next != null) SliverToBoxAdapter(child: _NextStopWeather(row: next)),
      // İpucu kapanınca yumuşakça söner ve yer kapanır.
      SliverToBoxAdapter(
        child: AknAnimatedSize(
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: AknMotion.of(context, AknMotion.base),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1).animate(a),
                child: child,
              ),
            ),
            child: showTip
                ? Padding(
                    key: const ValueKey('tip'),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: DriverFadeUp(
                      offset: 16,
                      child: DriverTipCard(
                        onDismiss: () => unawaited(
                          ref.read(driverTipVisibleProvider.notifier).dismiss(),
                        ),
                      ),
                    ),
                  )
                : const SizedBox(
                    key: ValueKey('no-tip'),
                    width: double.infinity,
                  ),
          ),
        ),
      ),
      if (today != null || !todayAsync.hasError)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: DriverTabs<DriverTab>(
              value: _tab,
              onChanged: (t) => setState(() => _tab = t),
              segments: [
                FilterOption(
                  value: DriverTab.today,
                  label: DriverTab.today.label,
                  count: today?.open.length,
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
      if (_tab != DriverTab.today &&
          tabState != null &&
          (tabState.fromCache || tabState.refreshError != null))
        SliverToBoxAdapter(child: _FreshnessLine(state: tabState)),
      ..._content(tabAsync, plan, disputed, ops, drafts, now),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];

    final Widget? dock = next == null
        ? null
        : ListenableBuilder(
            listenable: _proximity,
            builder: (context, _) =>
                _dockFor(next, nextDetail, ops[next.id], drafts[next.id]),
          );

    Widget body = PullToRefresh(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: slivers,
        ),
      ),
    );
    if (largeText) {
      // Durum çubuğu şeridi bandın rengindedir (açık simgeler); içerik altından kayar.
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AknBand(
            topInset: true,
            child: SizedBox(width: double.infinity),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: body,
            ),
          ),
        ],
      );
    }
    return AppScaffold(
      showOfflineBanner: false,
      appBar: !largeText,
      homeHeader: largeText ? null : bandHeader,
      refreshing: tabState?.refreshing ?? false,
      actionBar: dock,
      body: body,
    );
  }

  Widget _dockFor(
    DriverShipmentRow next,
    DriverShipmentDetail? detail,
    DriverShipmentOps? ops,
    DeliverDraft? draft,
  ) {
    final moving = next.isInTransit || (ops?.startWaiting ?? false);
    if (!moving) {
      return DriverStopDock(
        onNavigate: () => unawaited(_navigate(next)),
        actionLabel: DriverCopy.actionStart,
        actionIcon: PhosphorIconsRegular.truck,
        actionIsPrimary: true,
        onAction: () => _open(next),
      );
    }
    return DriverStopDock(
      onNavigate: () => unawaited(_navigate(next)),
      actionLabel: draft != null
          ? DriverCopy.actionResume
          : DriverCopy.actionDeliver,
      actionIcon: PhosphorIconsFill.checkCircle,
      actionSemanticLabel: draft != null
          ? '${DriverCopy.actionDeliver}: ${DriverCopy.resumeDraft}'
          : null,
      actionIsPrimary: _proximity.deliverIsPrimary(
        detail?.latitude,
        detail?.longitude,
      ),
      onAction: () => _deliver(next),
    );
  }

  /// Sıradaki durak (bandın üstüne yükselen kahraman kart); yoksa yükleniyor / hata / boş görünümü.
  Widget _top(
    AsyncValue<DriverListState> todayAsync,
    DriverRoutePlan plan,
    DriverShipmentDetail? detail,
    Map<int, DriverShipmentOps> ops,
    Map<int, DeliverDraft> drafts,
    DateTime now,
  ) {
    final today = todayAsync.valueOrNull;
    if (today == null) {
      if (todayAsync.hasError) return _errorView(todayAsync.error);
      // İskelet de bandın üstünde durur; veri gelince kart yerine solarak geçer.
      return const AknBandOverlap(
        child: FadeThroughSwitcher(
          child: KeyedSubtree(
            key: ValueKey('next-stop-skeleton'),
            child: _NextStopSkeleton(),
          ),
        ),
      );
    }
    final next = plan.next;
    if (next == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: EmptyState(
          title: today.isEmpty
              ? DriverCopy.emptyTodayTitle
              : DriverCopy.nothingToday,
          message: today.isEmpty
              ? DriverCopy.emptyTodayMessage
              : DriverCopy.nothingTodayHint,
          illustration: AknIllustration.delivery,
          compact: true,
        ),
      );
    }
    // Teslimat kaydedilince sıradaki durak plakaya kayarak gelir (§8.2, 300 ms).
    return AknBandOverlap(
      child: FadeThroughSwitcher(
        child: KeyedSubtree(
          key: const ValueKey('next-stop'),
          child: SharedAxisSwitcher(
            duration: AknMotion.stopSlide,
            child: KeyedSubtree(
              key: ValueKey(next.id),
              child: ListenableBuilder(
                listenable: _proximity,
                builder: (context, _) => _NextStop(
                  plan: plan,
                  row: next,
                  detail: detail,
                  ops: ops[next.id],
                  draft: drafts[next.id],
                  distance: _proximity.distanceTo(
                    detail?.latitude,
                    detail?.longitude,
                  ),
                  now: now,
                  onOpen: () => _open(next),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(
    AsyncValue<DriverListState> async,
    DriverRoutePlan plan,
    List<DriverShipmentRow> disputed,
    Map<int, DriverShipmentOps> ops,
    Map<int, DeliverDraft> drafts,
    DateTime now,
  ) {
    final state = async.valueOrNull;
    if (state == null) {
      if (_tab == DriverTab.today) return const [];
      if (async.hasError) {
        return [SliverToBoxAdapter(child: _errorView(async.error))];
      }
      return const [
        SliverToBoxAdapter(
          child: Shimmer(
            child: Column(
              children: [
                SizedBox(height: 12),
                SkeletonCard(lines: 2),
                SkeletonCard(lines: 2),
                SkeletonCard(lines: 2),
              ],
            ),
          ),
        ),
      ];
    }

    Widget row(DriverShipmentRow r, {int? number}) => ShipmentCard(
      row: r,
      now: now,
      number: number,
      ops: ops[r.id],
      draft: drafts[r.id],
      history: _tab == DriverTab.history,
      onOpen: () => _open(r),
      onCorrect: () => _deliver(r),
      onResume: () => _deliver(r),
      onFixOp: (op) => unawaited(_fixOp(op)),
    );

    if (_tab == DriverTab.today) {
      if (state.isEmpty) return const [];
      final upcoming = plan.upcoming;
      final done = plan.done;
      // Kartlar bugünün bölümleri boyunca tek bir çağlayanla yükselir.
      var index = 0;
      List<Widget> cards(List<Widget> rows) => [
        for (final r in rows) _staggeredCard(index++, r),
      ];
      return [
        SliverToBoxAdapter(
          child: StaggerScope(
            key: const ValueKey('driver-today'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (disputed.isNotEmpty)
                  ..._section(
                    DriverCopy.sectionDisputed,
                    cards([for (final r in disputed) row(r)]),
                  ),
                if (upcoming.isNotEmpty)
                  ..._section(
                    DriverCopy.sectionNext,
                    cards([
                      for (final s in upcoming) row(s.row, number: s.number),
                    ]),
                  )
                else if (plan.next != null)
                  FadeUp(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Row(
                        children: [
                          Icon(
                            PhosphorIconsRegular.flagCheckered,
                            size: 20,
                            color: context.akn.dim,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              DriverCopy.noMoreStops,
                              style: context.aknText.bodySmall.copyWith(
                                color: context.akn.dim,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (done.isNotEmpty)
                  ..._section(
                    DriverCopy.sectionDone,
                    cards([for (final s in done) row(s.row, number: s.number)]),
                  ),
              ],
            ),
          ),
        ),
      ];
    }

    if (state.isEmpty) {
      final (title, message) = switch (_tab) {
        DriverTab.upcoming => (
          DriverCopy.emptyUpcomingTitle,
          DriverCopy.emptyUpcomingMessage,
        ),
        _ => (DriverCopy.emptyHistoryTitle, DriverCopy.emptyHistoryMessage),
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
    final items = state.items;
    return [
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
      // Sekme değişince çağlayan yeniden oynar; kaydırdıkça gelen kartlar hemen yükselir.
      StaggerScope(
        key: ValueKey(_tab),
        child: SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, i) => _staggeredCard(i, row(items[i])),
        ),
      ),
      if (state.loadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: ChevronSpinner(size: 22)),
          ),
        )
      else if (state.loadMoreError != null)
        SliverToBoxAdapter(
          child: Center(
            child: AknButton.ghost(
              label: '${DriverCopy.loadMoreFailed} ${DriverCopy.opRetry}',
              icon: PhosphorIconsRegular.arrowClockwise,
              onPressed: () => unawaited(
                ref.read(driverListProvider(_tab).notifier).loadMore(),
              ),
            ),
          ),
        ),
    ];
  }

  /// Sayfa kenarında, aralıklı bir durak kartı; sırayla yükselir.
  Widget _staggeredCard(int index, Widget card) => DriverStaggerItem(
    index: index,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: card,
    ),
  );

  List<Widget> _section(String title, List<Widget> cards) => [
    SectionHeader(
      title: title,
      count: cards.length,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
    ),
    ...cards,
  ];

  Widget _errorView(Object? error) {
    final f = AppFailure.from(error ?? const UnknownFailure());
    void retry() {
      unawaited(
        ref.read(driverListProvider(DriverTab.today).notifier).refresh(),
      );
      if (_tab != DriverTab.today) {
        unawaited(ref.read(driverListProvider(_tab).notifier).refresh());
      }
    }

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

/// Başlık (tahta ekran 6): "Teslimatlarım" (sürücü kipinde 34/40), altında "Bugün, 21 Ekim
/// Çarşamba" ve sağda tırın TR plakası (32 px). Sayfa rengi; içerik altına kayınca ince çizgi
/// (iskele çizer). İtilerek açıldıysa (bayi personeli) geri düğmesi.
class _DriverHeader extends StatelessWidget {
  const _DriverHeader({required this.now, this.plate});

  final DateTime now;
  final String? plate;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final w = TrTime.wall(now);
    final date =
        '${Fmt.dayLabel(now, now: now)}, ${w.day} ${Fmt.monthNames[w.month - 1]} ${Fmt.weekday(now)}';
    final p0 = plate;
    // Bantta tek başlık düğümü (sahip kararı G): ekran okuyucu başlığı, tarihi ve plakayı birlikte
    // okur; ayrı metin düğümleri yok (AknHomeHeader gibi).
    final spoken = [
      DriverCopy.title,
      date,
      if (p0 != null) 'araç plakası ${Fmt.plate(p0)}',
    ].join(', ');
    final title = MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        header: true,
        label: spoken,
        excludeSemantics: true,
        child: Text(
          DriverCopy.title,
          style: t.display.copyWith(color: c.ink, letterSpacing: -0.8),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    final p = plate;
    return Padding(
      padding: EdgeInsets.fromLTRB(canPop ? 4 : AknSpace.page, 6, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canPop)
            Row(
              children: [
                const BackButton(),
                const SizedBox(width: 4),
                Expanded(child: title),
              ],
            )
          else
            title,
          const SizedBox(height: 2),
          Padding(
            padding: EdgeInsets.only(left: canPop ? 16 : 0),
            // Tarih (en çok 1,3×) ve plaka; tek satıra sığmazsa plaka alta geçer. Başlık düğümü
            // bunları zaten okur.
            child: ExcludeSemantics(
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text(date, style: t.body.copyWith(color: c.dim)),
                    if (p != null) PlateBadge(plate: p, fontSize: 17),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Eşitleme hapı (tasarım v3 §4 durum hapı, kahraman kartın altında): çevrimdışıyken "Çevrimdışı.
/// Teslimatlar telefona kaydediliyor." (bekleyen işlem sayısıyla, uyarı tonu), çevrimiçiyken
/// "Eşitlendi 09:58" (yeşil bulut), yenileme başarısızsa son güncelleme saati. Durum değişince hap
/// yumuşakça yer değiştirir.
class _SyncLine extends StatelessWidget {
  const _SyncLine({
    required this.state,
    required this.online,
    required this.pending,
  });

  final DriverListState? state;
  final bool online;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final s = state;
    final offline = !online || s?.refreshError is OfflineFailure;
    final at = s?.updatedAt;
    final (IconData icon, String? text, AknTone tone) = offline
        ? (
            PhosphorIconsRegular.cloudSlash,
            pending > 0
                ? DriverCopy.offlineLineCount(pending)
                : DriverCopy.offlineLine,
            AknTone.warn,
          )
        : s?.refreshError != null && at != null
        ? (
            PhosphorIconsRegular.cloudWarning,
            DriverCopy.refreshFailed(Fmt.time(at)),
            AknTone.warn,
          )
        : at != null
        ? (
            PhosphorIconsRegular.cloudCheck,
            DriverCopy.syncedAt(Fmt.time(at)),
            AknTone.ok,
          )
        : (PhosphorIconsRegular.cloud, null, AknTone.neutral);
    final Widget pill;
    if (text == null) {
      pill = const SizedBox(key: ValueKey('none'), height: 4);
    } else {
      final tc = c.tone(tone);
      pill = Semantics(
        key: ValueKey(text),
        liveRegion: offline,
        label: text,
        excludeSemantics: true,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 14, 6),
            decoration: BoxDecoration(
              color: tc.bg,
              borderRadius: AknRadius.pillAll,
              border: Border.all(color: tc.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(icon, size: 18, color: tc.fg),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text,
                    style: t.label.copyWith(
                      color: tone == AknTone.ok ? c.ink : tc.fg,
                      fontWeight: FontWeight.w600,
                      fontFeatures: AknNumerals.tabular,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: AnimatedSwitcher(
          duration: AknMotion.of(context, AknMotion.base),
          switchInCurve: AknMotion.spring,
          layoutBuilder: (current, previous) => Stack(
            alignment: AlignmentDirectional.topStart,
            children: [...previous, ?current],
          ),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(
              alignment: AlignmentDirectional.centerStart.resolve(
                Directionality.of(context),
              ),
              scale: Tween<double>(begin: 0.92, end: 1).animate(a),
              child: child,
            ),
          ),
          child: pill,
        ),
      ),
    );
  }
}

/// Sıradaki durak (tasarım v3 §4, kahraman kart): üstte sıra ve akan yük çubuğu, müşteri (24/30
/// 800) ve adres, durum (yalnızca olağan dışıysa); ince çizginin altında ekranın tek plakası (ADR
/// levhası, litre, canlı güzergâh çizgisi, okumalar). Kartın tamamı ayrıntıyı açar.
class _NextStop extends StatelessWidget {
  const _NextStop({
    required this.plan,
    required this.row,
    required this.detail,
    required this.ops,
    required this.draft,
    required this.distance,
    required this.now,
    required this.onOpen,
  });

  final DriverRoutePlan plan;
  final DriverShipmentRow row;
  final DriverShipmentDetail? detail;
  final DriverShipmentOps? ops;
  final DeliverDraft? draft;

  /// Kuş uçuşu uzaklık (metre); konum yoksa null.
  final double? distance;
  final DateTime now;
  final VoidCallback onOpen;

  /// Durumun olağan dışı hali (gecikmiş, yola çıkış bekliyor, yarım taslak); olağansa null.
  DriverLamp? get _lamp {
    if (ops?.startWaiting ?? false) {
      return (
        tone: AknTone.warn,
        label: DriverCopy.startQueuedNote,
        solid: false,
      );
    }
    final d = draft;
    if (d != null) {
      return (
        tone: AknTone.brand,
        label: DriverCopy.draftAt(DriverCopy.stepShort[d.step.index]),
        solid: false,
      );
    }
    if (row.isOverdue(now)) {
      final at = row.scheduledAt;
      final day = TurkishText.lower(Fmt.dayLabel(at, now: now));
      return (
        tone: AknTone.danger,
        label: DriverCopy.overdueSince('$day ${Fmt.time(at)}'),
        solid: false,
      );
    }
    return null;
  }

  List<StopReadout> get _readouts {
    final at = row.scheduledAt;
    final day = Fmt.dayLabel(at, now: now);
    final dist = distance;
    final tank = detail?.tankCapacityLiters;
    final window = row.windowLabel;
    return [
      if (at != null)
        StopReadout(
          label: day == 'Bugün'
              ? DriverCopy.readoutPlan
              : DriverCopy.readoutPlanOn(TurkishText.lower(day)),
          value: Fmt.time(at),
        ),
      if (dist != null)
        distanceReadout(dist)
      else if (tank != null)
        StopReadout(
          label: DriverCopy.readoutTank,
          value: Fmt.number(tank),
          unit: 'L',
        ),
      if (window != null)
        StopReadout(label: DriverCopy.readoutWindow, value: window),
    ];
  }

  /// Güzergâh çizgisindeki tırın yeri: planlıyken depoda, yoldayken yolun ortasında (300 m
  /// içindeyse noktanın hemen önünde).
  Widget get _route {
    final moving = row.isInTransit || (ops?.startWaiting ?? false);
    final dist = distance;
    final double? progress = !moving
        ? 0
        : (dist != null && dist < 300 ? 0.92 : null);
    return TruckRoute(moving: moving, progress: progress);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final n = plan.nextNumber ?? 1;
    final address = [
      ?(detail?.row.deliveryPointName ?? row.deliveryPointName),
      ?detail?.address,
      ?(row.district ?? row.city),
    ].join(', ');
    final lamp = _lamp;
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final orderLine = Text(
      DriverCopy.nextOf(n, plan.total),
      style: t.label.copyWith(color: c.dim, fontWeight: FontWeight.w600),
    );
    final loadText = Fmt.liters(plan.remainingLiters);
    final loadStyle = t.label.copyWith(
      fontWeight: FontWeight.w800,
      fontFeatures: AknNumerals.tabular,
      color: c.ink,
    );
    // Kalan yük sayaç gibi döner: teslimat kaydedilince eski litreden yenisine iner.
    final load = RollingText(TextSpan(text: loadText, style: loadStyle));
    final bar = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 120, minWidth: 72),
      child: DriverLoadBar(plan: plan),
    );

    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            double w(String text, TextStyle? style) {
              final tp = TextPainter(
                text: TextSpan(text: text, style: style),
                textDirection: TextDirection.ltr,
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
              )..layout();
              final width = tp.width;
              tp.dispose();
              return width;
            }

            // Sığmazsa (büyük yazı, dar ekran) sıra satırı üstte, yük çubuğu altında.
            final fits =
                !large &&
                w(orderLine.data!, orderLine.style) +
                        12 +
                        72 +
                        12 +
                        w(loadText, loadStyle) <=
                    box.maxWidth;
            if (!fits) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  orderLine,
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: DriverLoadBar(plan: plan)),
                      const SizedBox(width: 12),
                      load,
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                orderLine,
                const SizedBox(width: 12),
                const Spacer(),
                Flexible(flex: 4, child: bar),
                const SizedBox(width: 12),
                load,
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.6,
          child: Text(
            row.customerTitle ?? row.code,
            style: AknDriverMode.stopName(t).copyWith(
              color: c.ink,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
        ),
        if (address.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(address, style: t.body.copyWith(color: c.dim)),
        ],
        if (lamp != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AknLamp(label: lamp.label, tone: lamp.tone),
          ),
        ],
      ],
    );

    final summary = [
      DriverCopy.nextOf(n, plan.total),
      ?row.customerTitle,
      if (address.isNotEmpty) address,
      ?lamp?.label,
    ].join(', ');

    return DriverStopPlate(
      product: row.productName,
      figure: Fmt.number(row.plannedLiters, maxFraction: 3),
      readouts: _readouts,
      chart: _route,
      onTap: onOpen,
      // Kartın üstü (durak kimliği) kendi düğmesidir; plaka okuması ayrı düğümdür.
      header: Semantics(
        container: true,
        button: true,
        label: summary,
        hint: 'Ayrıntıları açmak için dokunun',
        onTap: onOpen,
        excludeSemantics: true,
        child: head,
      ),
    );
  }
}

/// Sıradaki durağın kapı notu ve teslim alacak kişisi (tasarım v3 §4 kart): beyaz kart, satırlar
/// arasında içeriden ince çizgi. Bilgi yoksa çizilmez.
class _StopContactCard extends StatelessWidget {
  const _StopContactCard({required this.detail});

  final DriverShipmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final hasDoor = d.accessNotes != null;
    final hasContact = d.contactName != null || d.contactPhone != null;
    if (!hasDoor && !hasContact) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: DriverFadeUp(
        offset: 16,
        duration: AknMotion.stagger,
        curve: AknMotion.emphasizedCurve,
        child: AknCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasDoor) DoorNoteRow(text: d.accessNotes!),
              if (hasDoor && hasContact)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: AknLedgerDivider(indent: 0),
                ),
              if (hasContact)
                ContactRow(
                  name: d.contactName,
                  phone: d.contactPhone,
                  role: DriverCopy.recipientRole,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kapı notu satırı: kuyuda kapı simgesi, "Kapı notu:" (600) ve not.
class DoorNoteRow extends StatelessWidget {
  const DoorNoteRow({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AknIconBox(icon: PhosphorIconsRegular.door),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: '${DriverCopy.doorNote} ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: text),
                ],
              ),
              style: t.body.copyWith(color: c.ink),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Uzaklık" okuması: 50 m içinde "<50 m", 1 km altında metre (10'a yuvarlı), 10 km altında bir
/// ondalık, üstünde tam km.
StopReadout distanceReadout(double meters) {
  final (String value, String unit) = meters < 50
      ? ('<50', 'm')
      : meters < 1000
      ? (Fmt.integer((meters / 10).round() * 10), 'm')
      : meters < 10000
      ? (Fmt.number(meters / 1000, maxFraction: 1), 'km')
      : (Fmt.integer((meters / 1000).round()), 'km');
  return StopReadout(
    label: DriverCopy.readoutDistance,
    value: value,
    unit: unit,
    semanticLabel:
        '${DriverCopy.readoutDistance}: ${DriverCopy.distanceSemantics('$value $unit')}',
  );
}

/// Teslim alacak kişi (tasarım v3): kuyuda kişi simgesi, ad (17/22 700) ve rolü (15/20 soluk);
/// telefon varsa yazılı "Ara" düğmesi (şoförde simge-yalnız düğme yok, §13).
class ContactRow extends StatelessWidget {
  const ContactRow({super.key, this.name, this.phone, required this.role});

  final String? name;
  final String? phone;
  final String role;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final who = name ?? DriverCopy.contact;
    return Row(
      children: [
        const AknIconBox(icon: PhosphorIconsRegular.user),
        const SizedBox(width: 14),
        Expanded(
          child: Semantics(
            label: '$who, $role',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  who,
                  style: t.body.copyWith(
                    color: c.ink,
                    fontWeight: FontWeight.w700,
                    height: 22 / 17,
                  ),
                ),
                Text(role, style: t.bodySmall.copyWith(color: c.dim)),
              ],
            ),
          ),
        ),
        if (phone != null) ...[
          const SizedBox(width: 12),
          AknButton.secondary(
            label: DriverCopy.actionCall,
            icon: PhosphorIconsRegular.phone,
            semanticLabel: DriverCopy.callSemantics(who),
            onPressed: () => callPhone(context, phone),
          ),
        ],
      ],
    );
  }
}

/// Kahraman kartın iskeleti (bandın üstünde, plaka biçiminde; parıltı süpürür).
class _NextStopSkeleton extends StatelessWidget {
  const _NextStopSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AknRadius.plate,
        boxShadow: AknShadows.plate(c),
      ),
      child: const Shimmer(
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SkeletonLine(widthFactor: 0.55, height: 14),
              SizedBox(height: 12),
              SkeletonLine(widthFactor: 0.75, height: 24),
              SizedBox(height: 8),
              SkeletonLine(widthFactor: 0.9, height: 16),
              SizedBox(height: 20),
              SkeletonBox(height: 40, width: 180, radius: 12),
              SizedBox(height: 14),
              SkeletonBox(height: 56, width: 220, radius: 12),
              SizedBox(height: 16),
              SkeletonLine(widthFactor: 1, height: 12),
            ],
          ),
        ),
      ),
    );
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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

/// Düzeltme bekleyen teslimat (tasarım v3 §4 yumuşak tonlu kart; kahraman kartın hemen altında,
/// kaydırmadan görünür ve kısa): kırmızı kuyu, beyaz dairede kırmızı simge, "1 teslimat düzeltme
/// bekliyor" ve müşteri; basınca küçülür, dokununca ayrıntı (birden çoksa Bugün listesi). Not ve
/// "Teslimatı düzelt" aşağıdaki "Düzeltme bekleyen" kartındadır.
class _DisputeAlert extends StatelessWidget {
  const _DisputeAlert({
    required this.rows,
    required this.onOpen,
    required this.onShow,
  });

  final List<DriverShipmentRow> rows;
  final ValueChanged<DriverShipmentRow> onOpen;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final first = rows.first;
    final many = rows.length > 1;
    final title = DriverCopy.disputedCount(rows.length);
    final who = many
        ? rows.map((r) => r.customerTitle ?? r.code).join(', ')
        : (first.customerTitle ?? first.code);
    void tap() {
      AknHaptics.selection();
      many ? onShow() : onOpen(first);
    }

    // Kısa kalsın: büyük yazıda en çok 1,6× (durak ve plaka ilk ekranda kalır).
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: DriverFadeUp(
          offset: 12,
          child: Semantics(
            button: true,
            label: '$title: $who',
            hint: 'Ayrıntıları açmak için dokunun',
            onTap: tap,
            excludeSemantics: true,
            child: PressScale(
              child: Material(
                color: c.danger.bg,
                shape: RoundedRectangleBorder(
                  borderRadius: AknRadius.card,
                  side: BorderSide(color: c.danger.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: tap,
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: c.danger.line.withValues(alpha: 0.5),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: context.minTap),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: 40,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: c.isDark ? c.surfaceRaised : c.surface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                PhosphorIconsRegular.warningOctagon,
                                size: 22,
                                color: c.danger.fg,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  style: t.bodyStrong.copyWith(
                                    color: c.ink,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  who,
                                  style: t.bodySmall.copyWith(color: c.ink),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            PhosphorIconsRegular.caretRight,
                            size: 22,
                            color: c.ink,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
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
    ].join(', ');
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Row(
        children: [
          Icon(
            offline
                ? PhosphorIconsRegular.cloudSlash
                : PhosphorIconsRegular.clockCounterClockwise,
            size: 18,
            color: c.dim,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: t.caption.copyWith(color: c.dim)),
          ),
        ],
      ),
    );
  }
}
