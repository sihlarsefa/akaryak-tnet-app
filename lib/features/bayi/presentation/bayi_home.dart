import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/access_policy.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/routing/home_placeholder.dart';
import '../../../core/ui/ui.dart';
import '../../assistant/api.dart';
import '../application/bayi_grants.dart';
import '../application/bayi_runtime.dart';
import '../application/home_controller.dart';
import '../application/role_tip.dart';
import '../copy.dart';
import '../data/home_models.dart';
import 'home/home_sections.dart';
import 'widgets/bayi_widgets.dart';
import 'widgets/paged_list_body.dart';

/// Bayi ana sayfası (spec A.4 / C.5 Home tarifi): lacivert karşılama, ilk girişte rol ipucu, yetkiye göre
/// bölümler (`GET home/bayi`; yetkisiz bölüm gelmez, yüklenemeyen bölüm "Bu bölüm yüklenemedi" der),
/// önbellekten çevrimdışı açılış. Bölüm sırası rol ön ayarına göre (finansçı önce Onaylarım'ı görür).
/// Sınıf adı ve kurucu imzası sabittir (ana sayfa seçici).
class BayiHome extends ConsumerWidget {
  const BayiHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bayiHomeProvider);
    // Asistan girişleri: özellik açık ve sunucu 503 `assistant_disabled` demedi (spec A.6).
    final assistant =
        ref.watch(appConfigProvider.select((c) => c.features.assistant)) &&
        ref.watch(assistantEnabledProvider);
    final controller = ref.read(bayiHomeProvider.notifier);
    return AppScaffold(
      navy: true,
      // Lacivert başlıkta marka logosu (müşteri ana sayfasıyla aynı).
      titleWidget: const AknLogo(markSize: 28, onDark: true),
      refreshing: state.refreshing,
      actions: [
        if (assistant)
          AknIconButton(
            icon: Icons.chat_bubble_outline_rounded,
            semanticLabel: 'Asistan',
            color: context.akn.onNavy,
            onPressed: () => GoRouter.of(context).push(AppRoutes.assistant),
          ),
      ],
      body: LoadableBody<BayiHomeData>(
        state: state,
        onRetry: () => controller.load(useCache: true),
        skeleton: const _HomeSkeleton(),
        builder: (context, data) => PullToRefresh(
          onRefresh: controller.refresh,
          child: _HomeList(data: data, state: state, assistant: assistant),
        ),
      ),
    );
  }
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(accessPolicyProvider);
    final grants = ref.watch(bayiGrantsProvider);
    final tipVisible = ref.watch(bayiRoleTipProvider);
    final assistantCard = assistant && ref.watch(bayiAssistantCardProvider);
    final controller = ref.read(bayiHomeProvider.notifier);
    final sections = <Widget>[];
    for (final key in _order(policy.rolePreset)) {
      final w = _section(key, data, controller);
      if (w != null) sections.add(w);
    }
    final tip = RoleTip.forPolicy(policy);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _Hero(data: data),
        UpdatedCaption(
          updatedAt: state.updatedAt,
          fromCache: state.fromCache,
          error: state.error,
        ),
        if (tipVisible)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: FadeUp(
              child: _RoleTipCard(
                tip: tip,
                onOpen: tip.route == null
                    ? null
                    : () => openDestination(context, tip.route!),
                onClose: () => ref.read(bayiRoleTipProvider.notifier).dismiss(),
              ),
            ),
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
        ...staggered(sections),
        if (grants.viewStaff)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: AknCard(
              padding: EdgeInsets.zero,
              onTap: () => GoRouter.of(context).push('/bayi/staff'),
              child: const AknListTile(
                leadingIcon: Icons.badge_outlined,
                title: 'Ekip',
                subtitle: 'Personel, roller ve şifre bağlantıları',
                showChevron: true,
              ),
            ),
          ),
        if (assistantCard)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: AknCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
              onTap: () => GoRouter.of(context).push(AppRoutes.assistant),
              child: Row(
                children: [
                  const LogoMark(size: 36, semanticLabel: null),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Asistana sorun',
                          style: context.aknText.bodyStrong,
                        ),
                        Text(
                          '"Bugün kaç teklif bekliyor?", "Koşullu onay ne demek?"',
                          style: context.aknText.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  AknIconButton(
                    icon: Icons.close_rounded,
                    semanticLabel: 'Asistan kartını kapat',
                    color: context.akn.dim,
                    onPressed: () =>
                        ref.read(bayiAssistantCardProvider.notifier).dismiss(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Rol ön ayarına göre bölüm sırası.
  static List<String> _order(RolePreset preset) => switch (preset) {
    RolePreset.finance => const [
      BayiHomeSections.approvals,
      BayiHomeSections.finance,
      BayiHomeSections.collections,
      BayiHomeSections.desk,
      BayiHomeSections.leads,
      BayiHomeSections.field,
      BayiHomeSections.shipments,
      BayiHomeSections.sales,
      BayiHomeSections.setup,
    ],
    RolePreset.accounting => const [
      BayiHomeSections.collections,
      BayiHomeSections.approvals,
      BayiHomeSections.finance,
      BayiHomeSections.desk,
      BayiHomeSections.shipments,
      BayiHomeSections.sales,
      BayiHomeSections.leads,
      BayiHomeSections.field,
      BayiHomeSections.setup,
    ],
    RolePreset.dispatch => const [
      BayiHomeSections.shipments,
      BayiHomeSections.desk,
      BayiHomeSections.approvals,
      BayiHomeSections.sales,
      BayiHomeSections.collections,
      BayiHomeSections.finance,
      BayiHomeSections.leads,
      BayiHomeSections.field,
      BayiHomeSections.setup,
    ],
    RolePreset.salesManager => const [
      BayiHomeSections.approvals,
      BayiHomeSections.field,
      BayiHomeSections.leads,
      BayiHomeSections.sales,
      BayiHomeSections.desk,
      BayiHomeSections.shipments,
      BayiHomeSections.collections,
      BayiHomeSections.finance,
      BayiHomeSections.setup,
    ],
    _ => const [
      BayiHomeSections.desk,
      BayiHomeSections.approvals,
      BayiHomeSections.shipments,
      BayiHomeSections.collections,
      BayiHomeSections.finance,
      BayiHomeSections.sales,
      BayiHomeSections.leads,
      BayiHomeSections.field,
      BayiHomeSections.setup,
    ],
  };

  static Widget? _section(String key, BayiHomeData d, BayiHomeController c) {
    if (d.failed(key)) {
      return SectionFailedCard(
        title: BayiHomeSections.title(key),
        onRetry: c.refresh,
      );
    }
    return switch (key) {
      BayiHomeSections.desk =>
        d.desk == null ? null : DeskSectionView(desk: d.desk!),
      BayiHomeSections.shipments =>
        d.shipments == null
            ? null
            : ShipmentsSectionView(section: d.shipments!),
      BayiHomeSections.approvals =>
        d.approvals == null
            ? null
            : ApprovalsSectionView(section: d.approvals!),
      BayiHomeSections.collections =>
        d.collections == null
            ? null
            : CollectionsSectionView(section: d.collections!),
      BayiHomeSections.finance =>
        d.finance == null ? null : FinanceSectionView(section: d.finance!),
      BayiHomeSections.leads =>
        d.leads == null ? null : LeadsSectionView(section: d.leads!),
      BayiHomeSections.field =>
        d.field == null ? null : FieldSectionView(section: d.field!),
      BayiHomeSections.setup =>
        d.setup == null ? null : SetupSectionView(section: d.setup!),
      BayiHomeSections.sales =>
        d.sales == null ? null : SalesSectionView(section: d.sales!),
      _ => null,
    };
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.data});

  final BayiHomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(sessionControllerProvider).access;
    final first = (access?.displayName ?? '').split(' ').first;
    final roles = access?.bayiRoleNames ?? const <String>[];
    final desk = data.desk;
    final ships = data.shipments;
    final facts = <String>[
      if (desk != null && desk.openForQuote > 0)
        '${desk.openForQuote} teklif bekliyor',
      if (ships != null && ships.inTransit > 0)
        '${ships.inTransit} sevkiyat yolda',
      if (data.approvals != null && data.approvals!.toMe > 0)
        '${data.approvals!.toMe} onay sizde',
    ];
    return AknHeroPanel(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Builder(
        builder: (context) {
          final t = context.aknText;
          final c = context.akn;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  '${HomePlaceholder.greeting()}${first.isEmpty ? '' : ', $first'}',
                  style: t.title,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                data.stationTitle.isEmpty
                    ? (access?.stationTitle ?? 'Bayi')
                    : data.stationTitle,
                style: t.body.copyWith(color: c.dim),
              ),
              if (facts.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(facts.join(' · '), style: t.bodyStrong),
              ],
              if (roles.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in roles)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: c.ink.withValues(alpha: 0.12),
                          borderRadius: AknRadius.pillAll,
                        ),
                        child: Text(r, style: t.label.copyWith(color: c.ink)),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) => Shimmer(
    child: ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      children: const [
        SkeletonBox(height: 120, radius: 24),
        SizedBox(height: 24),
        SkeletonBox(width: 120, height: 16),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 88, radius: 12)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 88, radius: 12)),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 88, radius: 12)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 88, radius: 12)),
          ],
        ),
        SizedBox(height: 24),
        SkeletonCard(lines: 3, margin: EdgeInsets.zero),
      ],
    ),
  );
}

/// İlk giriş rol ipucu: başlık, açıklama, hedef ekran düğmesi ve 48 dp "Kapat" düğmesi.
class _RoleTipCard extends StatelessWidget {
  const _RoleTipCard({
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
    final tc = c.tone(AknTone.brand);
    return Semantics(
      container: true,
      child: Container(
        decoration: BoxDecoration(
          color: tc.bg,
          borderRadius: AknRadius.card,
          border: Border.all(color: tc.line),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.lightbulb_outline_rounded,
                color: tc.fg,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tip.title, style: t.bodyStrong.copyWith(color: tc.fg)),
                  const SizedBox(height: 2),
                  Text(tip.message, style: t.body.copyWith(color: c.text)),
                  if (onOpen != null && tip.actionLabel != null)
                    TextButton(
                      onPressed: onOpen,
                      style: TextButton.styleFrom(
                        foregroundColor: tc.fg,
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft,
                      ),
                      child: Text(tip.actionLabel!),
                    )
                  else
                    const SizedBox(height: 8),
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
    );
  }
}
