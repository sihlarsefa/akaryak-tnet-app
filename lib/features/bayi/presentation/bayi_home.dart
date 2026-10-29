import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tasks/task_inbox.dart';
import '../../../core/auth/access_policy.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/offline/connectivity.dart';
import '../../../core/push/unread_count_provider.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../field/api.dart' show TuprasStrip;
import '../../stats/api.dart'
    show ManagerStatsDeck, StatsScope, refreshManagerStats, statsScopeProvider;
import '../application/bayi_grants.dart';
import '../application/bayi_runtime.dart' show Loadable;
import '../application/home_controller.dart';
import '../application/role_tip.dart';
import '../copy.dart';
import '../data/bayi_repository.dart';
import '../data/home_models.dart';
import 'home/home_atoms.dart';
import 'home/home_sections.dart';
import 'home/order_pipeline.dart';
import 'orders/quote_sheet.dart';
import 'widgets/bayi_widgets.dart'
    show openDestination, openPortal, showActionFailure;
import 'widgets/paged_list_body.dart';

/// Bayi ana sayfası (tasarım v4 "Sade" §3.3, §5 03): ana sayfa bir iş listesidir.
///
/// 1. Turuncu bant (`AknHomeHeader`, sahip kararı G; avatar Profil'i açar).
/// 2. "Sıra sizde" (`AknTaskCard`) bandın üstüne biner: başlıkta işlerin sayısı ve "● sizin
///    sıranız"; altında sipariş hattı (Finans · Teklif · Müşteri · Plan · Yolda · Teslim, her durak
///    süzülmüş listesini açar); öndeki iş ve tek birincil düğme ("Teklif ver" o siparişin teklif
///    sayfasını açar); en çok iki sıradaki iş; fazlası "Tümünü gör". İş yoksa sakin satır.
/// 3. Yöneticilere istatistik destesi (`ManagerStatsDeck(raised: false)`), ilk ekranda.
/// 4. İlk oturumda "Nasıl çalışır" ipucu (destenin altında: deste girişte görünür kalır).
/// 5. "Bugün": rol bölümlerinin her biri tek satır; karta sığmayan işler en üstte.
/// 6. Tüpraş fiyatları (tek kart) ve kurulum uyarıları (`tupras-today` hariç; o iş kartta).
/// 7. "Son güncelleme" notu (önbellekten açılış ya da tazeleme hatası).
///
/// Sınıf adı ve kurucu imzası sabittir (ana sayfa seçici).
class BayiHome extends ConsumerWidget {
  const BayiHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bayiHomeProvider);
    final access = ref.watch(sessionControllerProvider.select((s) => s.access));
    final controller = ref.read(bayiHomeProvider.notifier);
    final title = state.data?.stationTitle ?? '';
    final company = title.isNotEmpty ? title : (access?.stationTitle ?? 'Bayi');
    return AppScaffold(
      homeHeader: AknHomeHeader(
        company: company,
        person: homePersonLine(access),
        onOpenProfile: () => GoRouter.of(context).push(AppRoutes.profile),
      ),
      refreshing: state.refreshing,
      body: LoadableBody<BayiHomeData>(
        state: state,
        onRetry: () => controller.load(useCache: true),
        skeleton: const _HomeSkeleton(),
        builder: (context, data) => PullToRefresh(
          onRefresh: () async {
            await Future.wait([
              controller.refresh(),
              refreshManagerStats(ref),
              ref.read(unreadCountProvider.notifier).refresh(),
            ]);
          },
          child: _HomeList(data: data, state: state),
        ),
      ),
    );
  }
}

/// Tüpraş kartını gösteren roller (fiyat bağlamı teklif verenlere ve satışa ait).
const _tuprasPresets = {
  RolePreset.owner,
  RolePreset.orderDesk,
  RolePreset.salesManager,
  RolePreset.viewer,
  RolePreset.generic,
};

class _HomeList extends ConsumerWidget {
  const _HomeList({required this.data, required this.state});

  final BayiHomeData data;
  final Loadable<BayiHomeData> state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(accessPolicyProvider);
    final g = ref.watch(bayiGrantsProvider);
    final inbox = ref.watch(bayiTaskQueuesProvider);
    final counts = ref.watch(bayiPipelineCountsProvider).valueOrNull;
    final scope = ref.watch(statsScopeProvider);
    final hint = ref.watch(bayiFirstRunHintProvider);
    final preset = policy.rolePreset;
    final deck = scope != StatsScope.none;
    final stops = pipelineStops(
      context,
      data,
      preset: preset,
      grants: g,
      counts: counts,
    );

    List<AknTask> tasks({VoidCallback? before}) => [
      for (final t in inbox.items)
        if (_mine(t, g))
          _task(
            context,
            ref,
            t,
            g,
            data,
            before: before,
            pipeline: stops.isNotEmpty,
          ),
    ];
    final heroTasks = tasks();
    const shown = 1 + 2;
    final overflow = heroTasks.length > shown
        ? heroTasks.sublist(shown)
        : const <AknTask>[];

    final hero = AknBandOverlap(
      child: AknTaskCard(
        tasks: heroTasks,
        // Tek tek işler değil kuyruklar: her satır kendi sayısını söyler (onay satırı = Onaylar
        // rozeti), sipariş sayıları hattadır; başlıkta ikinci bir sayı olmaz (P2).
        showCount: false,
        overview: stops.isEmpty ? null : OrderPipeline(stops: stops),
        // "● sizin sıranız" büyük yazıda başlık satırına sığmaz (çekirdek başlığı kaydırmaz): o
        // ölçekte hat dikey listedir ve Pas sayılar kendini anlatır.
        legend:
            stops.any((s) => s.isYourMove) &&
            MediaQuery.textScalerOf(context).scale(10) < 13,
        onSeeAll: heroTasks.length > shown
            ? () => _showAll(context, (close) => tasks(before: close))
            : null,
        calm: 'Yeni sipariş gelince bildirim alırsınız.',
      ),
    );
    final hintCard = _Collapsible(
      visible: hint,
      child: AknFirstRunHint(
        steps: BayiHintSteps.forPreset(preset),
        onDismiss: () => ref.read(bayiFirstRunHintProvider.notifier).dismiss(),
      ),
    );
    final setup = data.setup;
    final sections = <Widget>[
      if (deck)
        const ManagerStatsDeck(
          raised: false,
          padding: EdgeInsets.fromLTRB(AknSpace.page, 16, AknSpace.page, 0),
        ),
      hintCard,
      for (final key in data.failedSections)
        HomeSectionFailed(
          title: BayiHomeSections.title(key),
          onRetry: ref.read(bayiHomeProvider.notifier).refresh,
        ),
      BayiTodayLedger(
        data: data,
        // Planlanacak sipariş sayısını hat zaten söylüyor: "Bugün" yinelemez (§3.3).
        overflow: [
          for (final t in overflow)
            if (!(stops.isNotEmpty && _pipelineShows(t.id))) t,
        ],
        heroKinds: {for (final t in inbox.items) t.id},
        showSales: !deck,
      ),
      if (_tuprasPresets.contains(preset)) _TuprasBlock(data: data),
      if (setup != null) SetupSectionView(section: setup),
      HomeUpdatedLine(
        updatedAt: state.updatedAt,
        fromCache: state.fromCache,
        error: state.error,
      ),
      if (data.isEmpty && heroTasks.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 24),
          child: EmptyState(
            title: BayiCopy.homeEmptyTitle,
            message: BayiCopy.homeEmptyMessage,
            illustration: AknIllustration.inbox,
          ),
        ),
    ];

    // Kahraman kendi yükselişiyle gelir; bölümler art arda (ve kaydırınca) belirir.
    return StaggerScope(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          hero,
          for (var i = 0; i < sections.length; i++)
            StaggerItem(index: i + 1, child: sections[i]),
        ],
      ),
    );
  }

  /// Sayısını sipariş hattının bir durağı zaten söyleyen kuyruk (Plan; şoför ataması da planın
  /// parçası): "Bugün" defterinde yinelenmez.
  static bool _pipelineShows(Object id) => id == 'plan' || id == 'drivers';

  /// İş izleyenin mi: teklif kuyruğu yalnızca teklif verebilene.
  static bool _mine(TaskItem t, BayiGrants g) => switch (t.kind) {
    TaskKind.quotes => g.quoteOnOrder || g.quoteOnDesk,
    _ => true,
  };

  /// Kutudaki işi karta çevirir; ekran eylemleri burada (v4 §3.4).
  static AknTask _task(
    BuildContext context,
    WidgetRef ref,
    TaskItem t,
    BayiGrants g,
    BayiHomeData data, {
    required bool pipeline,
    VoidCallback? before,
  }) {
    void run(VoidCallback f) {
      before?.call();
      f();
    }

    void open() => run(() => _openTask(context, ref, t, g, data));
    VoidCallback act = open;
    final id = t.orderId;
    if (t.actionKind == TaskActionKind.giveQuote && id != null) {
      act = () => run(() => unawaited(_giveQuote(context, ref, id, g)));
    }
    return AknTask(
      id: t.id,
      title: t.title,
      subtitle: t.subtitle,
      icon: TaskItem.iconOf(t.kind),
      tone: switch (t.tone) {
        TaskTone.yourMove => AknTaskTone.yourMove,
        TaskTone.danger => AknTaskTone.danger,
        TaskTone.warn => AknTaskTone.warn,
        TaskTone.neutral => AknTaskTone.neutral,
      },
      figure: t.figure,
      amount: t.amount,
      deadline: t.deadline,
      time: t.time,
      actionLabel: t.actionLabel,
      onAction: act,
      // Hat teklif sayısını zaten söylüyor: "6 sipariş teklif bekliyor" yinelenmez (P4).
      caption: t.kind == TaskKind.quotes && pipeline ? null : t.caption,
      note: t.note,
      onTap: open,
      counts: t.counts,
    );
  }

  static void _openTask(
    BuildContext context,
    WidgetRef ref,
    TaskItem t,
    BayiGrants g,
    BayiHomeData data,
  ) {
    switch (t.kind) {
      case TaskKind.quotes:
        final id = t.orderId;
        if (id != null && g.viewOrders) {
          unawaited(GoRouter.of(context).push(AppRoutes.bayiOrder(id)));
        } else {
          openDestination(context, AppRoutes.quoteDesk);
        }
      case TaskKind.tuprasToday:
        final check = data.setup?.checks
            .where((c) => c.key == 'tupras-today')
            .firstOrNull;
        unawaited(openPortal(context, ref, check?.portalPath ?? ''));
      default:
        openDestination(context, t.location);
    }
  }

  /// "Teklif ver": siparişi alıp teklif sayfasını açar; teklif verilemiyorsa (yetki, finans engeli)
  /// siparişi açar.
  static Future<void> _giveQuote(
    BuildContext context,
    WidgetRef ref,
    int orderId,
    BayiGrants g,
  ) async {
    if (!ref.read(isOnlineProvider)) {
      AppToast.info(
        'Çevrimdışısınız; teklif için bağlantı gerekli.',
        context: context,
      );
      return;
    }
    try {
      final order = await ref.read(bayiRepositoryProvider).order(orderId);
      if (!context.mounted) return;
      if (!g.canQuoteOrder(order.status, order.financeStatus)) {
        if (g.viewOrders) {
          unawaited(GoRouter.of(context).push(AppRoutes.bayiOrder(orderId)));
        } else {
          openDestination(context, AppRoutes.quoteDesk);
        }
        return;
      }
      await showQuoteSheet(context, order);
    } catch (e) {
      if (context.mounted) showActionFailure(context, e);
    }
  }

  /// "Tümünü gör": bütün işler bir sayfada, "Sıra sizde" satırlarıyla.
  static void _showAll(
    BuildContext context,
    List<AknTask> Function(VoidCallback close) build,
  ) {
    unawaited(
      showAppSheet<void>(
        context: context,
        title: 'Sıra sizde',
        builder: (sheet) {
          final tasks = build(() => Navigator.of(sheet).pop());
          return AknLedger(
            children: [for (final t in tasks) AknTaskRow(task: t)],
          );
        },
      ),
    );
  }
}

/// İçeriği görünürlüğe göre süzerek açıp kapatır (yükseklik + solma); kapanınca yer kalmaz.
class _Collapsible extends StatelessWidget {
  const _Collapsible({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AknMotion.reduced(context)) {
      return visible ? child : const SizedBox.shrink();
    }
    return AknAnimatedSize(
      duration: AknMotion.slow,
      curve: AknMotion.emphasizedCurve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: AknMotion.base,
        switchInCurve: AknMotion.standard,
        switchOutCurve: AknMotion.exit,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: visible
            ? KeyedSubtree(key: const ValueKey('on'), child: child)
            : const SizedBox(key: ValueKey('off'), width: double.infinity),
      ),
    );
  }
}

/// "Tüpraş fiyatları" kartı: fiyat bağlamı için yükteki bir cari; bugünün fiyatı girilmediyse
/// tarihin önünde uyarı noktası (fiyat girme işi "Sıra sizde" kartında).
class _TuprasBlock extends StatelessWidget {
  const _TuprasBlock({required this.data});

  final BayiHomeData data;

  @override
  Widget build(BuildContext context) {
    final d = data.desk;
    final orders = [...?d?.expiring, ...?d?.awaitingQuoteList];
    final ships = [...?data.shipments?.today, ...?data.shipments?.disputeList];
    final hint = orders.isNotEmpty
        ? orders.first.customerId
        : data.sales?.topCustomers.firstOrNull?.customerId ??
              ships.firstOrNull?.customerId;
    return TuprasStrip(
      customerHint: hint,
      missingToday: data.setup?.tuprasMissingToday ?? false,
    );
  }
}

/// İlk yükleme iskeleti: şeridin üstünde kahraman kart yerinde 26 köşeli blok, altında deste ve
/// defter yerinde sakin bloklar.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    padding: EdgeInsets.zero,
    children: const [
      AknBandOverlap(
        child: Shimmer(child: SkeletonBox(height: 320, radius: 26)),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(AknSpace.page, 16, AknSpace.page, 0),
        child: Shimmer(
          semanticLabel: null,
          child: SkeletonBox(height: 220, radius: 26),
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(AknSpace.page, 24, AknSpace.page, 0),
        child: Shimmer(
          semanticLabel: null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 20, radius: 6),
              SizedBox(height: 12),
              SkeletonBox(height: 140, radius: 20),
            ],
          ),
        ),
      ),
    ],
  );
}
