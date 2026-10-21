import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/access_policy.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../assistant/api.dart';
import '../../field/api.dart' show TuprasStrip;
import '../../stats/api.dart'
    show ManagerStatsDeck, StatsScope, refreshManagerStats, statsScopeProvider;
import '../application/bayi_grants.dart';
import '../application/bayi_runtime.dart';
import '../application/home_controller.dart';
import '../application/role_tip.dart';
import '../copy.dart';
import '../data/home_models.dart';
import 'home/home_atoms.dart';
import 'home/home_sections.dart';
import 'home/order_pipeline.dart';
import 'home/role_plate.dart';
import 'widgets/bayi_widgets.dart' show openDestination, openPortal;
import 'widgets/paged_list_body.dart';

/// Bayi ana sayfası (tasarım v2 §7.5 / §7.6; tahta ekran 3, koyu ekran 8).
///
/// `AknHomeHeader` (logo karesi, bayi adı, "Ad Soyad, rol", zil) → ekranın tek plakası: istatistik
/// yetkisi varsa yönetici destesi (`ManagerStatsDeck`, üstteki kart plaka), yoksa rol plakası
/// (sipariş masası, sevkiyat, finans) → rolün bölümleri: "Sipariş hattı" + acil satır, "Tüpraş
/// fiyatları", "Tahsilat", "Onaylarım", "Sevkiyatlar", "Kurulum uyarıları"… Bölümler `GET home/bayi`
/// yükünden gelir (yetkisiz bölüm gelmez, yüklenemeyen bölüm "Bu bölüm yüklenemedi" der); önbellekten
/// çevrimdışı açılır. Sınıf adı ve kurucu imzası sabittir (ana sayfa seçici).
class BayiHome extends ConsumerWidget {
  const BayiHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bayiHomeProvider);
    final access = ref.watch(sessionControllerProvider.select((s) => s.access));
    // Asistan girişleri: özellik açık ve sunucu 503 `assistant_disabled` demedi (spec A.6).
    final assistant =
        ref.watch(appConfigProvider.select((c) => c.features.assistant)) &&
        ref.watch(assistantEnabledProvider);
    final controller = ref.read(bayiHomeProvider.notifier);
    final title = state.data?.stationTitle ?? '';
    final company = title.isNotEmpty ? title : (access?.stationTitle ?? 'Bayi');
    return AppScaffold(
      homeHeader: AknHomeHeader(
        company: company,
        person: homePersonLine(access),
        // Ada dokununca Profil (§6.2) şimdilik kapalı: AknHomeHeader'ın dokunma düğümü etiketsiz ve
        // 48 dp'den kısa (a11y kılavuzları); çekirdek düzeltilince `onOpenProfile` geri eklenecek.
        // Profil "Diğer"den açılır.
      ),
      refreshing: state.refreshing,
      body: LoadableBody<BayiHomeData>(
        state: state,
        onRetry: () => controller.load(useCache: true),
        skeleton: const _HomeSkeleton(),
        builder: (context, data) => PullToRefresh(
          onRefresh: () async {
            await Future.wait([controller.refresh(), refreshManagerStats(ref)]);
          },
          child: _HomeList(data: data, state: state, assistant: assistant),
        ),
      ),
    );
  }
}

/// Ana sayfa bölüm anahtarları (sunucu bölümlerine ek olarak ekran parçaları).
abstract final class _Slot {
  static const pipeline = 'pipeline';
  static const tip = 'tip';
  static const tupras = 'tupras';
  static const desk = BayiHomeSections.desk;
  static const shipments = BayiHomeSections.shipments;
  static const approvals = BayiHomeSections.approvals;
  static const collections = BayiHomeSections.collections;
  static const finance = BayiHomeSections.finance;
  static const leads = BayiHomeSections.leads;
  static const field = BayiHomeSections.field;
  static const setup = BayiHomeSections.setup;
  static const sales = BayiHomeSections.sales;
}

class _HomeList extends ConsumerWidget {
  const _HomeList({
    required this.data,
    required this.state,
    required this.assistant,
  });

  final BayiHomeData data;
  final Loadable<BayiHomeData> state;
  final bool assistant;

  /// Rol ön ayarına göre bölüm sırası (§7.5, §7.6).
  static List<String> order(RolePreset preset) => switch (preset) {
    RolePreset.owner => const [
      _Slot.pipeline,
      _Slot.tip,
      _Slot.tupras,
      _Slot.collections,
      _Slot.approvals,
      _Slot.shipments,
      _Slot.setup,
    ],
    RolePreset.finance || RolePreset.accounting => const [
      _Slot.pipeline,
      _Slot.tip,
      _Slot.collections,
      _Slot.finance,
      _Slot.approvals,
      _Slot.setup,
    ],
    RolePreset.salesManager => const [
      _Slot.tip,
      _Slot.approvals,
      _Slot.field,
      _Slot.leads,
      _Slot.sales,
      _Slot.tupras,
    ],
    RolePreset.orderDesk => const [
      _Slot.pipeline,
      _Slot.tip,
      _Slot.desk,
      _Slot.tupras,
    ],
    RolePreset.dispatch => const [_Slot.pipeline, _Slot.tip, _Slot.shipments],
    RolePreset.viewer => const [
      _Slot.pipeline,
      _Slot.tip,
      _Slot.tupras,
      _Slot.approvals,
      _Slot.shipments,
      _Slot.sales,
      _Slot.setup,
    ],
    _ => const [
      _Slot.pipeline,
      _Slot.tip,
      _Slot.tupras,
      _Slot.desk,
      _Slot.collections,
      _Slot.approvals,
      _Slot.shipments,
      _Slot.finance,
      _Slot.field,
      _Slot.leads,
      _Slot.sales,
      _Slot.setup,
    ],
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(accessPolicyProvider);
    final grants = ref.watch(bayiGrantsProvider);
    final scope = ref.watch(statsScopeProvider);
    final tipVisible = ref.watch(bayiRoleTipProvider);
    final assistantRow = assistant && ref.watch(bayiAssistantCardProvider);
    final controller = ref.read(bayiHomeProvider.notifier);
    final preset = policy.rolePreset;
    final deck = scope != StatsScope.none;
    final finance =
        preset == RolePreset.finance || preset == RolePreset.accounting;

    Widget? slot(String key) {
      switch (key) {
        case _Slot.pipeline:
          return _PipelineBlock(data: data, preset: preset, grants: grants);
        case _Slot.tip:
          if (!tipVisible) return null;
          final tip = RoleTip.forPolicy(policy);
          return _RoleTipWell(
            tip: tip,
            onOpen: tip.route == null
                ? null
                : () => openDestination(context, tip.route!),
            onClose: () => ref.read(bayiRoleTipProvider.notifier).dismiss(),
          );
        case _Slot.tupras:
          return _TuprasBlock(data: data);
      }
      if (data.failed(key)) {
        return HomeSectionFailed(
          title: BayiHomeSections.title(key),
          onRetry: controller.refresh,
        );
      }
      return switch (key) {
        _Slot.desk =>
          data.desk == null ? null : DeskSectionView(desk: data.desk!),
        _Slot.shipments =>
          data.shipments == null
              ? null
              : ShipmentsSectionView(
                  section: data.shipments!,
                  dispatcher: preset == RolePreset.dispatch,
                ),
        _Slot.approvals =>
          data.approvals == null
              ? null
              : ApprovalsSectionView(section: data.approvals!),
        _Slot.collections =>
          data.collections == null
              ? null
              : CollectionsSectionView(
                  section: data.collections!,
                  detailed: finance,
                ),
        _Slot.finance =>
          data.finance == null
              ? null
              : FinanceSectionView(section: data.finance!),
        _Slot.leads =>
          data.leads == null ? null : LeadsSectionView(section: data.leads!),
        _Slot.field =>
          data.field == null ? null : FieldSectionView(section: data.field!),
        _Slot.setup =>
          data.setup == null ? null : SetupSectionView(section: data.setup!),
        _Slot.sales =>
          data.sales == null
              ? null
              : SalesSectionView(section: data.sales!, summary: !deck),
        _ => null,
      };
    }

    final sections = <Widget>[];
    for (final key in order(preset)) {
      final w = slot(key);
      if (w != null) sections.add(w);
    }

    // Sahip kararı G: ekranın tek kartı (deste ya da rol kartı) turuncu şeridin üstüne biner; şerit
    // kartın ilk 48 px'inin arkasında devam eder (AknBandOverlap, liste üst boşluğu yok).
    final Widget? plate = deck
        ? const AknBandOverlap(
            padding: EdgeInsets.zero,
            child: ManagerStatsDeck(
              padding: EdgeInsets.symmetric(horizontal: 18),
            ),
          )
        : BayiRolePlate.supports(preset, data)
        ? AknBandOverlap(
            child: BayiRolePlate(
              data: data,
              preset: preset,
              margin: EdgeInsets.zero,
            ),
          )
        : null;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        ?plate,
        if (plate == null) const SizedBox(height: 8),
        HomeUpdatedLine(
          updatedAt: state.updatedAt,
          fromCache: state.fromCache,
          error: state.error,
        ),
        if (data.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: EmptyState(
              title: BayiCopy.homeEmptyTitle,
              message: BayiCopy.homeEmptyMessage,
              illustration: AknIllustration.inbox,
            ),
          ),
        ...sections,
        if (grants.viewStaff || assistantRow) const SizedBox(height: 16),
        if (grants.viewStaff)
          AknListTile(
            leadingIcon: Icons.groups_outlined,
            title: 'Ekip',
            subtitle: 'Personel, roller ve şifre bağlantıları',
            showChevron: true,
            onTap: () => GoRouter.of(context).push(AppRoutes.bayiStaff),
          ),
        if (grants.viewStaff && assistantRow) const AknLedgerDivider(),
        if (assistantRow)
          AknListTile(
            leadingIcon: Icons.chat_bubble_outline_rounded,
            title: 'Asistana sorun',
            subtitle: '"Bugün kaç teklif bekliyor?", "Koşullu onay ne demek?"',
            onTap: () => GoRouter.of(context).push(AppRoutes.assistant),
            trailing: AknIconButton(
              icon: Icons.close_rounded,
              semanticLabel: 'Asistan satırını kapat',
              size: 20,
              color: context.akn.dim,
              onPressed: () =>
                  ref.read(bayiAssistantCardProvider.notifier).dismiss(),
            ),
          ),
      ],
    );
  }
}

/// "Sipariş hattı" başlığı ("şu an, 10:42"), hat ve süresi en yakın dolan teklifin acil satırı.
class _PipelineBlock extends ConsumerWidget {
  const _PipelineBlock({
    required this.data,
    required this.preset,
    required this.grants,
  });

  final BayiHomeData data;
  final RolePreset preset;
  final BayiGrants grants;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stops = pipelineStops(context, data, preset: preset, grants: grants);
    if (stops.isEmpty) return const SizedBox.shrink();
    final state = ref.watch(bayiHomeProvider);
    final at = data.generatedAt ?? state.updatedAt;
    final caption = at == null
        ? null
        : state.fromCache
        ? '${lowerFirst(Fmt.dayLabel(at))} ${Fmt.time(at)}'
        : 'şu an, ${Fmt.time(at)}';
    // Acil satır teklifle ilgilenenlere (masa ya da teklif yetkisi): sevkiyat ekibine gösterilmez.
    final quoting = grants.viewDesk || grants.quoteOnOrder;
    final urgent = quoting ? PipelineUrgentLine.mostUrgent(data.desk) : null;
    VoidCallback? act;
    if (urgent != null) {
      if (grants.viewDesk && grants.quoteOnDesk) {
        act = () => openDestination(
          context,
          '${AppRoutes.quoteDesk}?customerId=${urgent.customerId}',
        );
      } else if (grants.viewOrders && grants.quoteOnOrder) {
        act = () =>
            GoRouter.of(context).push(AppRoutes.bayiOrder(urgent.orderId));
      }
    }
    // G kart dili: hat beyaz bölüm kabında (18 köşe, ince çerçeve) ana sayfa zemininde durur.
    return HomeSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Sipariş hattı',
            caption: caption,
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
          ),
          OrderPipeline(stops: stops),
          if (urgent != null)
            PipelineUrgentLine(
              row: urgent,
              onAction: act,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            ),
        ],
      ),
    );
  }
}

/// "Tüpraş fiyatları" şeridi: fiyat bağlamı için yükteki bir cari; bugünün fiyatı girilmediyse
/// (kurulum kontrolü) uyarı kuyusu ve portal bağlantısı.
class _TuprasBlock extends ConsumerWidget {
  const _TuprasBlock({required this.data});

  final BayiHomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = data.desk;
    final orders = [...?d?.expiring, ...?d?.awaitingQuoteList];
    final ships = [...?data.shipments?.today, ...?data.shipments?.disputeList];
    final hint = orders.isNotEmpty
        ? orders.first.customerId
        : data.sales?.topCustomers.firstOrNull?.customerId ??
              ships.firstOrNull?.customerId;
    final setup = data.setup;
    final check = setup?.checks
        .where((c) => c.key == 'tupras-today' && c.portalPath != null)
        .firstOrNull;
    return HomeSectionCard(
      child: TuprasStrip(
        customerHint: hint,
        missingToday: setup?.tuprasMissingToday ?? false,
        headerPadding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
        onEnterPrice: check == null
            ? null
            : () => openPortal(context, ref, check.portalPath!),
      ),
    );
  }
}

/// İlk giriş rol ipucu: Beton kuyu, ampul simgesi, başlık + cümle, mürekkep bağlantı ve "Kapat".
class _RoleTipWell extends StatelessWidget {
  const _RoleTipWell({
    required this.tip,
    required this.onOpen,
    required this.onClose,
  });

  final RoleTip tip;
  final VoidCallback? onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Semantics(
        container: true,
        child: Container(
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: AknRadius.card,
          ),
          padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 2, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.lightbulb_outline_rounded,
                  color: c.ink,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tip.title, style: t.bodyStrong.copyWith(color: c.ink)),
                    const SizedBox(height: 2),
                    Text(
                      tip.message,
                      style: t.bodySmall.copyWith(color: c.ink),
                    ),
                    if (onOpen != null && tip.actionLabel != null) ...[
                      const SizedBox(height: 4),
                      AknInlineLink(label: tip.actionLabel!, onTap: onOpen!),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Kapat',
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, color: c.dim, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// İlk yükleme iskeleti: plaka yerinde Beton kağıt (turuncu yok), sonra defter satırları.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) => Shimmer(
    child: ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      children: const [
        SkeletonBox(height: 300, radius: 20),
        SizedBox(height: 28),
        SkeletonBox(width: 140, height: 20, radius: 6),
        SizedBox(height: 16),
        SkeletonBox(height: 72, radius: 12),
        SizedBox(height: 28),
        SkeletonBox(width: 160, height: 20, radius: 6),
        SizedBox(height: 12),
        SkeletonBox(width: 220, height: 16, radius: 6),
        SizedBox(height: 8),
        SkeletonBox(width: 150, height: 14, radius: 6),
        SizedBox(height: 20),
        SkeletonBox(width: 220, height: 16, radius: 6),
        SizedBox(height: 8),
        SkeletonBox(width: 150, height: 14, radius: 6),
      ],
    ),
  );
}
