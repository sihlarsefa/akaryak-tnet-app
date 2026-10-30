import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/outbox_op.dart';
import '../../../core/offline/pending_ops_chip.dart';
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

/// Şoför ana sayfası "Teslimatlar" (tasarım v4 §5 11; spec A.4 A7). Yalnızca şoför olanlarda alt
/// menünün kökü; kendisi teslim eden bayi personeli için `/driver` ile açılır (geri düğmesiyle).
/// Sınıf adı ve kurucu imzası sabittir (M0a). Sürücü kipinde çizilir (§6.30: yazı bir basamak büyük;
/// düğmeler uygulamanın standart 48 px boyunda, sahip 2026-10-30).
///
/// - Turuncu başlık bandı (sahip kararı G): "Teslimatlar", "Bugün 28 Ekim · 41 DMR 101".
/// - Sıradaki durak **kahraman kart olarak bandın üstüne yükselir** (ekranın tek plakası): itirazlı
///   teslimat varsa en üstte tek tehlike satırı; "Sıradaki teslimat 1 / 2", akan tanker yük çubuğu ve
///   "18.000 L yük · 2 durak", müşteri ve adres; ince çizginin altında ADR levhası, bu duraktaki litre
///   (sayaç gibi yuvarlanır), canlı » güzergâh çizgisi ve tek satır okumalar ("Varış planı 09:00",
///   altında "teslim aralığı 08:00–18:00" · "Tank kapasitesi 30.000 L"). Her litre etiketlidir.
///   Teslimat kaydedilince sıradaki durak kayarak gelir.
/// - Kartın altında yalnızca gerekince: eşitlenmemişken uyarı satırı ("Çevrimdışı · 2 işlem
///   bekliyor"), bekleyen işlem şeridi; sonra kapı notuyla teslim alacak kişinin kartı ("Ara").
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
    // "Teslimatlar", "Bugün 28 Ekim · 41 DMR 101"). Büyük yazıda başlık içerikle kayan beyaz satırdır.
    final driverName =
        ref.watch(sessionControllerProvider).access?.displayName ?? '';
    final dateLine = _dateLine(now);
    // Diğer'den açılan Teslimatlar (sahip, depo: alt menüde sekme değil) itilen bir sayfadır: bandın
    // başında geri düğmesi, geri dönülemiyorsa "Ana sayfa" (v4 §3.5, tur 2). Şoförün sekmesinde yok.
    final pushed = !AknTabScope.isIn(context);
    final bandLeading = pushed ? _pushedLeading(context) : null;
    final bandHeader = AknHomeHeader(
      greeting: DriverCopy.title,
      company: plate == null ? dateLine : '$dateLine · ${Fmt.plate(plate)}',
      person: driverName.isEmpty ? null : '$driverName, şoför',
      showBell: false,
      leading: bandLeading,
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
        child: _top(todayAsync, plan, nextDetail, ops, drafts, now, disputed),
      ),
      // Yalnızca eşitlenmemişken (v4 §5 11): eşitliyken hap yok.
      SliverToBoxAdapter(
        child: _SyncLine(
          state: today,
          online: online,
          pending: summarizeDriverOps(ops).waiting,
        ),
      ),
      // Çevrimdışı bekleyen sayısını eşitleme satırı söyler; şerit yalnızca çevrimiçi gönderim ve
      // ilgi bekleyen işlemler için (aynı bilgi iki kez yazmaz).
      const SliverToBoxAdapter(
        child: DriverOutboxStrip(
          margin: EdgeInsets.fromLTRB(20, 12, 20, 0),
          showOfflineWaiting: false,
        ),
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
      // Büyük yazıda bant içerikle kayar; itilen sayfada yine de geri düğmeli çubuk kalır.
      appBar: !largeText || pushed,
      title: largeText && pushed ? DriverCopy.title : null,
      homeHeader: largeText ? null : bandHeader,
      refreshing: tabState?.refreshing ?? false,
      actionBar: dock,
      body: body,
    );
  }

  /// İtilen Teslimatlar'ın bant düğmesi: geri dönülebiliyorsa geri, dönülemiyorsa (kabuksuz kök)
  /// "Ana sayfa".
  static Widget? _pushedLeading(BuildContext context) {
    if (ModalRoute.of(context)?.impliesAppBarDismissal ?? false) {
      return AknIconButton(
        icon: PhosphorIconsRegular.arrowLeft,
        semanticLabel: 'Geri',
        onPressed: () => unawaited(Navigator.of(context).maybePop()),
      );
    }
    final home = AppChrome.maybeOf(context)?.onGoHome;
    if (home == null) return null;
    return AknIconButton(
      icon: PhosphorIconsRegular.house,
      semanticLabel: 'Ana sayfa',
      onPressed: home,
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
  /// İtirazlı teslimat varsa kahramanın ÜSTÜNDE kendi tehlike şeridi olur (v4 §5 11, A13).
  Widget _top(
    AsyncValue<DriverListState> todayAsync,
    DriverRoutePlan plan,
    DriverShipmentDetail? detail,
    Map<int, DriverShipmentOps> ops,
    Map<int, DeliverDraft> drafts,
    DateTime now,
    List<DriverShipmentRow> disputed,
  ) {
    final dispute = disputed.isEmpty
        ? null
        : _DisputeRow(
            rows: disputed,
            onOpen: _open,
            onShow: () => setState(() => _tab = DriverTab.today),
          );
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sırada durak yokken itiraz şeridi bandın üstünde tek başına.
          if (dispute != null) AknBandOverlap(child: dispute),
          Padding(
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
          ),
        ],
      );
    }
    // Teslimat kaydedilince sıradaki durak plakaya kayarak gelir (§8.2, 300 ms).
    final stop = FadeThroughSwitcher(
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
    );
    // İtiraz, durak plakasının İÇİNDE değil, üstünde kendi şeridindedir (v4 §5 11, A13): plaka
    // kısalmaz, alt kenarı rıhtıma yapışmaz; şerit açılınca plaka yumuşakça aşağı kayar.
    return AknBandOverlap(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Şeridin altındaki 8 dp boşluk şeridin dokunma alanındadır.
          AknAnimatedSize(
            alignment: Alignment.topCenter,
            child: dispute ?? const SizedBox(width: double.infinity),
          ),
          stop,
        ],
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

/// Bandın tarih satırı (v4 §5 11): "Bugün 28 Ekim".
String _dateLine(DateTime now) {
  final w = TrTime.wall(now);
  return '${Fmt.dayLabel(now, now: now)} ${w.day} ${Fmt.monthNames[w.month - 1]}';
}

/// Büyük yazıdaki başlık (tahta ekran 6): "Teslimatlar" (sürücü kipinde 34/40), altında "Bugün 28
/// Ekim" ve tırın TR plakası (32 px). Sayfa rengi; içerik altına kayınca ince çizgi (iskele çizer).
/// İtilerek açıldıysa (bayi personeli) geri düğmesi.
class _DriverHeader extends StatelessWidget {
  const _DriverHeader({required this.now, this.plate});

  final DateTime now;
  final String? plate;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final date = _dateLine(now);
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

/// Eşitleme satırı (tasarım v4 §5 11, kahraman kartın altında): yalnızca eşitlenmemişken görünür —
/// çevrimdışıyken uyarı satırı "Çevrimdışı · 2 işlem bekliyor" (bekleyen yoksa "Çevrimdışı ·
/// teslimatlar telefona kaydediliyor"), yenileme başarısızsa "Yenilenemedi · son güncelleme 09:58".
/// Eşitliyken hiçbir şey çizilmez (hap yok). Bekleyen işlem varken satıra dokunmak bekleyen işlemleri
/// açar. Satır yumuşakça açılıp kapanır.
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
    final (IconData, String)? line = offline
        ? (
            PhosphorIconsRegular.cloudSlash,
            pending > 0
                ? DriverCopy.offlineWarnCount(pending)
                : DriverCopy.offlineWarn,
          )
        : s?.refreshError != null && at != null
        ? (
            PhosphorIconsRegular.cloudWarning,
            DriverCopy.refreshWarn(Fmt.time(at)),
          )
        : null;
    Widget child = const SizedBox(
      key: ValueKey('synced'),
      width: double.infinity,
    );
    if (line != null) {
      final (icon, text) = line;
      final warn = c.tone(AknTone.warn);
      final tappable = offline && pending > 0;
      Widget row = Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: tappable ? context.minTap : 0),
          child: Row(
            children: [
              Icon(icon, size: 20, color: warn.fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: t.bodySmall.copyWith(
                    color: warn.fg,
                    fontWeight: FontWeight.w600,
                    fontFeatures: AknNumerals.tabular,
                  ),
                ),
              ),
              if (tappable)
                Icon(PhosphorIconsRegular.caretRight, size: 18, color: warn.fg),
            ],
          ),
        ),
      );
      if (tappable) {
        row = PressScale(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              AknHaptics.selection();
              unawaited(showPendingOpsSheet(context));
            },
            child: row,
          ),
        );
      }
      child = Semantics(
        key: ValueKey(text),
        liveRegion: offline,
        button: tappable,
        label: text,
        excludeSemantics: true,
        child: row,
      );
    }
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.6,
      child: AknAnimatedSize(
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: AknMotion.of(context, AknMotion.base),
          switchInCurve: AknMotion.spring,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.2),
                end: Offset.zero,
              ).animate(a),
              child: child,
            ),
          ),
          child: child,
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

  /// Tek satır okumalar (v4 §5 11): "Varış planı 09:00" (altında "teslim aralığı 08:00–18:00") ·
  /// "Tank kapasitesi 30.000 L" (konum biliniyorsa yerine kuş uçuşu "Uzaklık").
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
          caption: window == null ? null : DriverCopy.windowCaption(window),
        )
      else if (window != null)
        StopReadout(label: DriverCopy.readoutWindow, value: window),
      if (dist != null)
        distanceReadout(dist)
      else if (tank != null)
        StopReadout(
          label: DriverCopy.readoutTank,
          value: Fmt.number(tank),
          unit: 'L',
        ),
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
    final orderLine = Text(
      DriverCopy.nextOf(n, plan.total),
      style: t.label.copyWith(color: c.dim, fontWeight: FontWeight.w600),
    );
    // Yük çubuğunun yazısı (v4 §5 11): "18.000 L yük · 2 durak" — etiketsiz litre yok. Kalan yük
    // sayaç gibi döner: teslimat kaydedilince eski litreden yenisine iner.
    final remainingStops = plan.stops
        .where((s) => s.state != StopState.done)
        .length;
    final loadText = Fmt.liters(plan.remainingLiters);
    final loadCaption = DriverCopy.loadCaption(loadText, remainingStops);
    final captionStyle = t.label.copyWith(
      color: c.dim,
      fontWeight: FontWeight.w600,
      fontFeatures: AknNumerals.tabular,
    );
    final load = RollingText(
      TextSpan(
        style: captionStyle,
        children: [
          TextSpan(
            text: loadText,
            style: captionStyle.copyWith(
              color: c.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: loadCaption.substring(loadText.length)),
        ],
      ),
    );

    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        orderLine,
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, box) {
            final tp = TextPainter(
              text: TextSpan(text: loadCaption, style: captionStyle),
              textDirection: TextDirection.ltr,
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 1,
            )..layout();
            final width = tp.width;
            tp.dispose();
            // Sığmazsa (büyük yazı, dar ekran) çubuk üstte, yazı altında.
            if (width + 12 + 72 > box.maxWidth) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DriverLoadBar(plan: plan),
                  const SizedBox(height: 6),
                  Text(loadCaption, style: captionStyle),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: DriverLoadBar(plan: plan)),
                const SizedBox(width: 12),
                load,
              ],
            );
          },
        ),
        const SizedBox(height: 12),
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
      loadCaption,
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

/// Düzeltme bekleyen teslimat (tasarım v4 §5 11, A13): durak plakasının ÜSTÜNDE, bandın üzerinde
/// kendi kısa şeridi — beyaz kart (r16), tehlike simgesi ve "Müşteri itiraz etti · 1 teslimatı
/// düzeltin" (tehlike rengi 700, 15/20, en çok 2 satır; yalnızca " · "da kırılır), sağda ok. Kart
/// standart 48 dp dokunma hedefi kadar yüksek (sahip 2026-10-30: sürücüde de gereksiz büyük
/// değil), altında 8 dp boşluk; daha fazla değil: plaka rıhtıma yapışmaz. Müşteri adı
/// ekran okuyucu metninde ve aşağıdaki "Düzeltme bekleyen" kartında; dokununca ayrıntı açılır
/// (birden çoksa Bugün listesi gösterilir). Basınca hafifçe içe çöker.
class _DisputeRow extends StatelessWidget {
  const _DisputeRow({
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

    final danger = c.tone(AknTone.danger);
    const radius = BorderRadius.all(Radius.circular(16));
    // Kart = standart 48 dp dokunma hedefi; altında 8 dp boşluk: şerit hedef kadar yer kaplar,
    // fazlasını değil — plaka rıhtımdan ≥ 12 dp yukarıda biter (A13).
    const gap = 8.0;
    const card = AknSpace.minTap;
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    // Kısa kalsın: büyük yazıda en çok 1,6× (durak ve plaka ilk ekranda kalır).
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.6,
      child: Semantics(
        button: true,
        label: '$title: $who',
        hint: 'Ayrıntıları açmak için dokunun',
        onTap: tap,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: tap,
          excludeFromSemantics: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: PressScale(
              scale: 0.985,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: radius,
                  boxShadow: AknShadows.card(c),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: tap,
                    borderRadius: radius,
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: c.surfaceAlt,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: card),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
                        child: Row(
                          children: [
                            Icon(
                              PhosphorIconsRegular.warningOctagon,
                              size: 20,
                              color: danger.fg,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              // Büyük yazıda (≥ 1,3×) satır sınırı yok: söz kesilmez. İki satıra
                              // inerse olgular arasında kırılır, satır sonunda "·" kalmaz
                              // ("Müşteri itiraz etti" / "1 teslimatı düzeltin"; v4 tur 2).
                              child: AknFactLine(
                                title,
                                maxLines: large ? null : 2,
                                style: t.bodyStrong.copyWith(
                                  fontSize: 15,
                                  height: 20 / 15,
                                  color: danger.fg,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              PhosphorIconsRegular.caretRight,
                              size: 20,
                              color: c.dim,
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
