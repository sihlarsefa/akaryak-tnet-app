import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/storage/prefs_store.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../assistant/api.dart';
import '../../weather/api.dart';
import '../application/field_access.dart';
import '../application/field_home_controller.dart';
import '../copy.dart';
import '../data/field_location.dart';
import '../data/field_models.dart';
import '../data/field_outbox.dart';
import 'location_capture.dart';
import 'widgets/field_widgets.dart';

/// Saha satış ana sayfası (spec A.4 A6): taslaklar, onay bekleyenler, reddedilenler, portföy sayısı,
/// hızlı işlemler, bulunduğunuz yerde hava. Sınıf adı ve kurucu imzası sabittir.
class FieldHome extends ConsumerWidget {
  const FieldHome({super.key});

  static String greeting([DateTime? now]) {
    final h = TrTime.wall(now ?? TrTime.now()).hour;
    if (h < 5) return 'İyi geceler';
    if (h < 12) return 'Günaydın';
    if (h < 18) return 'İyi günler';
    return 'İyi akşamlar';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fieldHomeProvider);
    final access = ref.watch(fieldAccessProvider);
    final features = ref.watch(appConfigProvider.select((c) => c.features));
    // Asistan girişleri: özellik açık ve sunucu 503 `assistant_disabled` demedi (spec A.6).
    final assistantOn =
        features.assistant && ref.watch(assistantEnabledProvider);
    final queued = ref.watch(fieldQueuedItemsProvider);
    final data = state.data;

    Future<void> refresh() => ref.read(fieldHomeProvider.notifier).refresh();

    final Widget body;
    if (state.loading && data == null) {
      body = const SkeletonList(itemCount: 4, header: _HeroSkeleton());
    } else if (data == null) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ErrorState(
            offline: state.error is OfflineFailure,
            message: state.error is OfflineFailure
                ? null
                : state.error?.message,
            onRetry: refresh,
          ),
        ],
      );
    } else {
      body = PullToRefresh(
        onRefresh: refresh,
        child: _HomeList(
          data: data,
          access: access,
          queued: queued,
          weather: features.weather,
          assistant: assistantOn,
          cachedAt: state.cachedAt,
        ),
      );
    }

    return AppScaffold(
      navy: true,
      // Lacivert başlıkta marka logosu (müşteri ana sayfasıyla aynı).
      titleWidget: const AknLogo(markSize: 28, onDark: true),
      refreshing: state.refreshing,
      actions: [
        if (assistantOn)
          AknIconButton(
            icon: Icons.chat_bubble_outline_rounded,
            semanticLabel: 'Asistan',
            color: context.akn.onNavy,
            onPressed: () => context.push(AppRoutes.assistant),
          ),
      ],
      body: body,
    );
  }
}

class _HomeList extends StatelessWidget {
  const _HomeList({
    required this.data,
    required this.access,
    required this.queued,
    required this.weather,
    required this.assistant,
    this.cachedAt,
  });

  final FieldHomeData data;
  final FieldAccess access;
  final List<FieldQueuedItem> queued;
  final bool weather;
  final bool assistant;
  final DateTime? cachedAt;

  @override
  Widget build(BuildContext context) {
    final queuedForms = queued.where((q) => q.isForm).length;
    final noForms =
        data.recentDrafts.isEmpty &&
        data.recentPending.isEmpty &&
        data.recentRejected.isEmpty &&
        queued.isEmpty;
    final children = <Widget>[
      _Hero(data: data, access: access, queuedDrafts: queuedForms),
      if (cachedAt != null) FieldCachedNote(at: cachedAt!),
      const _TipCard(),
      _QuickActions(access: access),
      if (queued.isNotEmpty) ...[
        SectionHeader(
          title: 'Gönderilmeyi bekleyenler',
          count: queued.length,
          subtitle: 'Bağlantı gelince otomatik gönderilir',
        ),
        for (final q in queued)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: FieldQueuedTile(
              item: q,
              onEdit: q.isForm || q.isLead
                  ? () => context.push(
                      q.isForm
                          ? '${AppRoutes.fieldFormNew}?op=${q.op.id}'
                          : '${AppRoutes.fieldLeadNew}?op=${q.op.id}',
                    )
                  : null,
            ),
          ),
      ],
      if (data.failed.contains('forms'))
        const _SectionFailed(title: 'Saha formları'),
      if (data.leadsNeedingInfo.isNotEmpty) ...[
        SectionHeader(
          title: 'Ek bilgi bekleyen ön kayıtlar',
          count: data.leadsNeedingInfoCount,
          actionLabel: 'Tümü',
          onAction: () =>
              context.go('${AppRoutes.field}?tab=leads&status=info'),
        ),
        for (final l in data.leadsNeedingInfo)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: FieldLeadTile(row: l),
          ),
      ],
      ..._formSection(
        context,
        title: 'Onay bekleyen formlarım',
        rows: data.recentPending,
        total: data.pending,
        status: 1,
      ),
      ..._formSection(
        context,
        title: 'Taslaklarım',
        rows: data.recentDrafts,
        total: data.drafts,
        status: 0,
      ),
      ..._formSection(
        context,
        title: 'Son 30 günde reddedilenler',
        rows: data.recentRejected,
        total: data.rejected,
        status: 3,
      ),
      if (noForms && access.canCreateForm && !data.failed.contains('forms'))
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: AknCard(
            child: EmptyState(
              compact: true,
              title: FieldCopy.formsEmptyTitle,
              message: FieldCopy.formsEmptyMessage,
              illustration: AknIllustration.field,
              actionLabel: 'Saha formu',
              onAction: () => context.push(AppRoutes.fieldFormNew),
            ),
          ),
        ),
      if (data.leadStats != null) _LeadStatsCard(stats: data),
      if (weather) const _WeatherHere(),
      if (assistant) const _AssistantCard(),
      const SizedBox(height: 32),
    ];
    return StaggerScope(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: staggered(children),
      ),
    );
  }

  List<Widget> _formSection(
    BuildContext context, {
    required String title,
    required List<FieldFormRow> rows,
    required int total,
    required int status,
  }) {
    if (rows.isEmpty) return const [];
    return [
      SectionHeader(
        title: title,
        count: total,
        actionLabel: 'Tümü',
        onAction: () =>
            context.go('${AppRoutes.field}?tab=forms&status=$status'),
      ),
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: FieldFormTile(row: r),
        ),
    ];
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({
    required this.data,
    required this.access,
    required this.queuedDrafts,
  });

  final FieldHomeData data;
  final FieldAccess access;
  final int queuedDrafts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(sessionControllerProvider.select((s) => s.access));
    final firstName = (me?.displayName ?? '').split(' ').first;
    final roles = me?.bayiRoleNames.isNotEmpty ?? false
        ? me!.bayiRoleNames
        : const ['Saha satış'];
    return AknHeroPanel(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Builder(
        builder: (context) {
          final t = context.aknText;
          final c = context.akn;
          void openForms(int status) =>
              context.go('${AppRoutes.field}?tab=forms&status=$status');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  '${FieldHome.greeting()}${firstName.isEmpty ? '' : ', $firstName'}',
                  style: t.title,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                me?.stationTitle ?? 'Saha satış',
                style: t.body.copyWith(color: c.dim),
              ),
              const SizedBox(height: 10),
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
                        color: c.surface,
                        borderRadius: AknRadius.pillAll,
                      ),
                      child: Text(r, style: t.label.copyWith(color: c.ink)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              KpiRow(
                children: [
                  KpiTile(
                    label: 'Taslak',
                    value: data.drafts + queuedDrafts,
                    icon: Icons.edit_note_rounded,
                    caption: queuedDrafts > 0
                        ? '$queuedDrafts gönderilmeyi bekliyor'
                        : null,
                    onTap: () => openForms(0),
                  ),
                  KpiTile(
                    label: 'Onayda',
                    value: data.pending,
                    icon: Icons.hourglass_top_rounded,
                    onTap: () => openForms(1),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              KpiRow(
                children: [
                  KpiTile(
                    label: 'Reddedilen',
                    value: data.rejected,
                    icon: Icons.cancel_outlined,
                    caption: 'Son 30 gün',
                    onTap: () => openForms(3),
                  ),
                  if (access.isRep)
                    KpiTile(
                      label: 'Portföy',
                      value: data.portfolioCount,
                      icon: Icons.groups_rounded,
                      caption: 'cari',
                      onTap: () =>
                          context.go('${AppRoutes.field}?tab=portfolio'),
                    )
                  else
                    KpiTile(
                      label: 'Ön kayıt',
                      value: data.leadStats?.total,
                      icon: Icons.person_add_alt_1_rounded,
                      caption: 'Bu ay',
                      onTap: () => context.go('${AppRoutes.field}?tab=leads'),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: SkeletonBox(height: 220, radius: 24),
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.access});

  final FieldAccess access;

  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String, VoidCallback)>[
      if (access.canCreateForm)
        (
          Icons.post_add_rounded,
          'Saha formu',
          () => context.push(AppRoutes.fieldFormNew),
        ),
      if (access.canCreateLead)
        (
          Icons.person_add_alt_1_rounded,
          'Ön kayıt',
          () => context.push(AppRoutes.fieldLeadNew),
        ),
      if (access.isRep)
        (
          Icons.groups_rounded,
          'Portföy',
          () => context.go('${AppRoutes.field}?tab=portfolio'),
        ),
      if (access.canSeeForms)
        (
          Icons.receipt_long_rounded,
          'Formlarım',
          () => context.go('${AppRoutes.field}?tab=forms'),
        ),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final (icon, label, onTap) in actions)
            _QuickAction(icon: icon, label: label, onTap: onTap),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140, minHeight: 56),
      child: AknCard(
        onTap: onTap,
        semanticLabel: label,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AknIconBox(icon: icon, tone: AknTone.brand, size: 36),
            const SizedBox(width: 10),
            Flexible(child: Text(label, style: t.bodyStrong)),
          ],
        ),
      ),
    );
  }
}

class _SectionFailed extends ConsumerWidget {
  const _SectionFailed({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: AknBanner(
      tone: AknTone.warn,
      title: title,
      message: FieldCopy.sectionFailed,
      actionLabel: FieldCopy.retry,
      onAction: () => ref.read(fieldHomeProvider.notifier).refresh(),
    ),
  );
}

class _LeadStatsCard extends StatelessWidget {
  const _LeadStatsCard({required this.stats});

  final FieldHomeData stats;

  @override
  Widget build(BuildContext context) {
    final s = stats.leadStats!;
    final t = context.aknText;
    final rate = s.conversionRatePercent == null
        ? ''
        : ' · ${Fmt.percent(s.conversionRatePercent)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: AknCard(
        onTap: () => context.go('${AppRoutes.field}?tab=leads'),
        semanticLabel:
            'Ön kayıtlar bu ay: ${s.total} kayıt, ${s.inFinance} finansta, ${s.converted} cariye dönüştü',
        child: Row(
          children: [
            const AknIconBox(icon: Icons.person_add_alt_1_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ön kayıtlar · bu ay', style: t.bodyStrong),
                  const SizedBox(height: 2),
                  Text(
                    '${s.total} kayıt · ${s.inFinance} finansta · ${s.converted} dönüştü$rate',
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.akn.faint),
          ],
        ),
      ),
    );
  }
}

/// Rol ipucu (ilk girişte bir kez; kapatılabilir).
class _TipCard extends ConsumerStatefulWidget {
  const _TipCard();

  @override
  ConsumerState<_TipCard> createState() => _TipCardState();
}

class _TipCardState extends ConsumerState<_TipCard> {
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    final uid = ref.read(currentUserIdProvider);
    final key = uid == null ? null : PrefKeys.user(uid, 'field.tipDismissed');
    if (_hidden || key == null || ref.read(prefsStoreProvider).getBool(key)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: AknBanner(
        tone: AknTone.info,
        icon: Icons.tips_and_updates_outlined,
        title: 'Sahada bağlantı kesilirse',
        message:
            'Saha formunu ve ön kaydı bağlantı olmadan da kaydedebilirsiniz; bağlantı gelince otomatik gönderilir.',
        // Kapatma metin düğmesiyle (48 dp dokunma hedefi; bant içindeki küçük kapat simgesi yerine).
        actionLabel: 'Anladım',
        onAction: () {
          setState(() => _hidden = true);
          unawaited(ref.read(prefsStoreProvider).setBool(key, true));
        },
      ),
    );
  }
}

/// "Asistana sorun" kartı (kapatılabilir; asistan ekranı rota ile açılır).
class _AssistantCard extends ConsumerStatefulWidget {
  const _AssistantCard();

  @override
  ConsumerState<_AssistantCard> createState() => _AssistantCardState();
}

class _AssistantCardState extends ConsumerState<_AssistantCard> {
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    final uid = ref.read(currentUserIdProvider);
    final key = uid == null
        ? null
        : PrefKeys.user(uid, 'field.assistantCardDismissed');
    if (_hidden || key == null || ref.read(prefsStoreProvider).getBool(key)) {
      return const SizedBox.shrink();
    }
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: AknCard(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            const ExcludeSemantics(child: LogoMark(size: 36)),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                button: true,
                label:
                    'Asistana sorun: saha formu ve ön kayıt hakkında sorular',
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => context.push(AppRoutes.assistant),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AknSpace.minTap,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Asistana sorun', style: t.bodyStrong),
                        const SizedBox(height: 2),
                        Text(
                          '"Koşullu onay ne demek?", "Barem bandı nedir?"',
                          style: t.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            AknIconButton(
              icon: Icons.close_rounded,
              semanticLabel: 'Asistan kartını kapat',
              size: 20,
              onPressed: () {
                setState(() => _hidden = true);
                unawaited(ref.read(prefsStoreProvider).setBool(key, true));
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Son alınan "bulunduğum yer" (oturum boyunca).
final fieldHereProvider =
    NotifierProvider<FieldHereController, FieldLocationFix?>(
      FieldHereController.new,
    );

class FieldHereController extends Notifier<FieldLocationFix?> {
  @override
  FieldLocationFix? build() {
    ref.watch(currentUserIdProvider);
    return null;
  }

  void set(FieldLocationFix fix) => state = fix;
}

/// Bulunduğunuz yerde hava (konum yalnızca dokununca istenir; izin zaten varsa sessizce alınır).
class _WeatherHere extends ConsumerStatefulWidget {
  const _WeatherHere();

  @override
  ConsumerState<_WeatherHere> createState() => _WeatherHereState();
}

class _WeatherHereState extends ConsumerState<_WeatherHere> {
  FieldLocationOutcome? _outcome;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_silent()));
  }

  /// İzin zaten verilmişse istem göstermeden konum alır.
  Future<void> _silent() async {
    if (!mounted || ref.read(fieldHereProvider) != null) return;
    final svc = ref.read(fieldLocationServiceProvider);
    final access = await svc.status();
    if (!mounted || !access.canRead) return;
    try {
      final fix = await svc.current();
      if (mounted) ref.read(fieldHereProvider.notifier).set(fix);
    } catch (_) {
      // Sessiz deneme: hata gösterilmez.
    }
  }

  Future<void> _locate() async {
    setState(() => _busy = true);
    final o = await captureFieldLocation(
      context,
      ref,
      reason: FieldCopy.weatherPrimerReason,
      icon: Icons.wb_sunny_outlined,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = o;
    });
    if (o is LocationCaptured) ref.read(fieldHereProvider.notifier).set(o.fix);
  }

  @override
  Widget build(BuildContext context) {
    final fix = ref.watch(fieldHereProvider);
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Bulunduğunuz yerde hava', style: t.bodyStrong),
          ),
          const SizedBox(height: 8),
          if (fix != null)
            WeatherCard(lat: fix.latitude, lng: fix.longitude)
          else
            AknCard(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const AknIconBox(icon: Icons.wb_sunny_outlined),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      'Ziyaret planınız için bulunduğunuz yerin hava durumunu görün.',
                      style: t.bodySmall,
                    ),
                  ),
                  AknButton.secondary(
                    label: _busy ? 'Konum alınıyor…' : 'Konumu kullan',
                    icon: Icons.my_location_rounded,
                    size: AknButtonSize.small,
                    onPressed: _busy ? null : _locate,
                  ),
                ],
              ),
            ),
          FieldLocationNotice(
            outcome: _outcome,
            onRetry: _locate,
            margin: const EdgeInsets.only(top: 8),
          ),
        ],
      ),
    );
  }
}
