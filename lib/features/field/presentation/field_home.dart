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
import '../../../core/utils/tr_time.dart';
import '../../assistant/api.dart';
import '../../stats/api.dart' show ManagerStatsDeck, refreshManagerStats;
import '../../weather/api.dart';
import '../application/field_access.dart';
import '../application/field_home_controller.dart';
import '../copy.dart';
import '../data/field_location.dart';
import '../data/field_models.dart';
import '../data/field_outbox.dart';
import 'location_capture.dart';
import 'widgets/field_widgets.dart';
import 'widgets/tupras_strip.dart';

/// Saha satış ana sayfası (tasarım v3 "Akış", `fieldRep`): turuncu `AknHomeHeader` bandı → bandın
/// üstüne yükselen kendi portföyünün istatistik destesi → gönderilmeyi bekleyenler → "Saha formlarım"
/// (sayaç gibi sayan KPI kutuları + onay bekleyen, taslak, reddedilen satır kartları) → "Ön
/// kayıtlarım" → "Tüpraş fiyatları" → bulunduğunuz yerde hava. Bölümler ilk açılışta sırayla, sonra
/// kaydırdıkça görünür oldukça kayarak belirir. "Saha formu" alt menünün ortasındaki tuştadır. Sınıf
/// adı ve kurucu imzası sabittir.
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
    final me = ref.watch(sessionControllerProvider.select((s) => s.access));
    final features = ref.watch(appConfigProvider.select((c) => c.features));
    // Asistan girişleri: özellik açık ve sunucu 503 `assistant_disabled` demedi (spec A.6).
    final assistantOn =
        features.assistant && ref.watch(assistantEnabledProvider);
    final queued = ref.watch(fieldQueuedItemsProvider);
    final data = state.data;

    Future<void> refresh() async {
      await Future.wait([
        ref.read(fieldHomeProvider.notifier).refresh(),
        refreshManagerStats(ref),
      ]);
    }

    final Widget body;
    if (state.loading && data == null) {
      body = const SkeletonList(itemCount: 4, header: _DeckSkeleton());
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

    final name = (me?.displayName ?? '').trim();
    final role = (me?.bayiRoleNames.isNotEmpty ?? false)
        ? me!.bayiRoleNames.first
        : 'Saha satış temsilcisi';
    return AppScaffold(
      homeHeader: AknHomeHeader(
        company: me?.stationTitle ?? 'Saha satış',
        person: [if (name.isNotEmpty) name, fieldLowerFirst(role)].join(', '),
        // Ada dokununca Profil (§6.2) şimdilik kapalı: AknHomeHeader'ın dokunma düğümü etiketsiz ve
        // 48 dp'den kısa (a11y kılavuzları); çekirdek düzeltilince `onOpenProfile` geri eklenecek.
      ),
      refreshing: state.refreshing,
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
    void openForms(int status) =>
        context.go('${AppRoutes.field}?tab=forms&status=$status');
    final formsFailed = data.failed.contains('forms');
    final children = <Widget>[
      // Sahip kararı G: deste turuncu şeridin üstüne biner (AknBandOverlap, liste üst boşluğu yok).
      const AknBandOverlap(
        padding: EdgeInsets.zero,
        child: ManagerStatsDeck(padding: EdgeInsets.symmetric(horizontal: 18)),
      ),
      if (cachedAt != null) FieldCachedNote(at: cachedAt!),
      if (queued.isNotEmpty) ...[
        SectionHeader(
          title: 'Gönderilmeyi bekleyenler',
          count: queued.length,
          subtitle: 'Bağlantı gelince otomatik gönderilir',
        ),
        AknLedger(
          children: [
            for (final q in queued)
              FieldQueuedTile(
                item: q,
                onEdit: q.isForm || q.isLead
                    ? () => context.push(
                        q.isForm
                            ? '${AppRoutes.fieldFormNew}?op=${q.op.id}'
                            : '${AppRoutes.fieldLeadNew}?op=${q.op.id}',
                      )
                    : null,
              ),
          ],
        ),
      ],
      if (access.canSeeForms) ...[
        SectionHeader(
          title: 'Saha formlarım',
          actionLabel: 'Tümü',
          onAction: () => context.go('${AppRoutes.field}?tab=forms'),
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
        ),
        if (formsFailed)
          const _SectionFailed(title: 'Saha formları')
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: KpiRow(
              children: [
                KpiTile(
                  label: 'Taslak',
                  value: data.drafts + queuedForms,
                  caption: queuedForms > 0
                      ? '$queuedForms gönderilmeyi bekliyor'
                      : null,
                  onTap: () => openForms(0),
                ),
                KpiTile(
                  label: 'Onayda',
                  value: data.pending,
                  onTap: () => openForms(1),
                ),
                KpiTile(
                  label: 'Reddedilen',
                  value: data.rejected,
                  caption: 'Son 30 gün',
                  onTap: () => openForms(3),
                ),
                if (access.isRep)
                  KpiTile(
                    label: 'Portföy',
                    value: data.portfolioCount,
                    caption: 'cari',
                    onTap: () => context.go('${AppRoutes.field}?tab=portfolio'),
                  ),
              ],
            ),
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
      if (noForms && access.canCreateForm && !formsFailed)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: EmptyState(
            compact: true,
            title: FieldCopy.formsEmptyTitle,
            message: FieldCopy.formsEmptyMessage,
            illustration: AknIllustration.field,
            actionLabel: 'Saha formu',
            onAction: () => context.push(AppRoutes.fieldFormNew),
          ),
        ),
      if (access.canSeeLeads) ..._leadSection(context),
      const TuprasStrip(),
      const _TipWell(),
      if (weather) const _WeatherHere(),
      if (assistant) const _AssistantRow(),
      const SizedBox(height: 32),
    ];
    // Deste bandın üstüne kendi yükselişiyle gelir; diğer bölümler sırayla (ve kaydırınca) belirir.
    return StaggerScope(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (var i = 0; i < children.length; i++)
            i == 0
                ? children[i]
                : FieldStaggerItem(index: i - 1, child: children[i]),
        ],
      ),
    );
  }

  List<Widget> _leadSection(BuildContext context) {
    final s = data.leadStats;
    final leadsFailed = data.failed.contains('leads');
    return [
      SectionHeader(
        title: 'Ön kayıtlarım',
        actionLabel: access.canCreateLead ? 'Yeni ön kayıt' : 'Tümü',
        onAction: access.canCreateLead
            ? () => context.push(AppRoutes.fieldLeadNew)
            : () => context.go('${AppRoutes.field}?tab=leads'),
      ),
      if (leadsFailed)
        const _SectionFailed(title: 'Ön kayıtlar')
      else if (s != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Semantics(
            container: true,
            label: 'Bu ay ön kayıtlar',
            child: KpiRow(
              children: [
                KpiTile(
                  label: 'Bu ay',
                  value: s.total,
                  caption: 'kayıt',
                  onTap: () => context.go('${AppRoutes.field}?tab=leads'),
                ),
                KpiTile(label: 'Finansta', value: s.inFinance + s.submitted),
                KpiTile(
                  label: 'Cariye dönüşen',
                  value: s.converted,
                  caption: s.conversionRatePercent == null
                      ? null
                      : 'Dönüşüm %${s.conversionRatePercent!.round()}',
                ),
              ],
            ),
          ),
        ),
      if (data.leadsNeedingInfo.isNotEmpty) ...[
        SectionHeader(
          title: 'Ek bilgi bekleyen ön kayıtlar',
          count: data.leadsNeedingInfoCount,
          actionLabel: 'Tümü',
          onAction: () =>
              context.go('${AppRoutes.field}?tab=leads&status=info'),
        ),
        AknLedger(
          children: [
            for (final l in data.leadsNeedingInfo) FieldLeadTile(row: l),
          ],
        ),
      ],
    ];
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
      AknLedger(children: [for (final r in rows) FieldFormTile(row: r)]),
    ];
  }
}

/// İlk yükleme: plaka kartının yerinde parıltılı iskelet (hero kartı biçiminde, r26).
class _DeckSkeleton extends StatelessWidget {
  const _DeckSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
    child: SkeletonBox(height: 300, radius: AknRadius.plateRadius),
  );
}

class _SectionFailed extends ConsumerWidget {
  const _SectionFailed({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
    child: AknBanner(
      tone: AknTone.warn,
      icon: PhosphorIconsRegular.cloudSlash,
      title: title,
      message: FieldCopy.sectionFailed,
      actionLabel: FieldCopy.retry,
      onAction: () => ref.read(fieldHomeProvider.notifier).refresh(),
    ),
  );
}

/// Rol ipucu (ilk girişte bir kez; kapatılabilir): yumuşak tonlu bilgi bandı.
class _TipWell extends ConsumerStatefulWidget {
  const _TipWell();

  @override
  ConsumerState<_TipWell> createState() => _TipWellState();
}

class _TipWellState extends ConsumerState<_TipWell> {
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    final uid = ref.read(currentUserIdProvider);
    final key = uid == null ? null : PrefKeys.user(uid, 'field.tipDismissed');
    if (_hidden || key == null || ref.read(prefsStoreProvider).getBool(key)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: AknBanner(
        tone: AknTone.info,
        icon: PhosphorIconsRegular.lightbulbFilament,
        title: 'Sahada bağlantı kesilirse',
        message:
            'Saha formunu ve ön kaydı bağlantı olmadan da kaydedebilirsiniz; bağlantı gelince otomatik gönderilir.',
        // Kapatma metin düğmesiyle (48 dp dokunma hedefi; kuyu içindeki küçük kapat simgesi yerine).
        actionLabel: 'Anladım',
        onAction: () {
          setState(() => _hidden = true);
          unawaited(ref.read(prefsStoreProvider).setBool(key, true));
        },
      ),
    );
  }
}

/// "Asistana sorun" satırı (kapatılabilir; asistan ekranı rota ile açılır).
class _AssistantRow extends ConsumerStatefulWidget {
  const _AssistantRow();

  @override
  ConsumerState<_AssistantRow> createState() => _AssistantRowState();
}

class _AssistantRowState extends ConsumerState<_AssistantRow> {
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
    return FieldListCard(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: AknListTile(
        leadingIcon: PhosphorIconsRegular.chatCircle,
        leadingTone: AknTone.brand,
        title: 'Asistana sorun',
        subtitle: '"Koşullu onay ne demek?", "Barem bandı nedir?"',
        semanticLabel:
            'Asistana sorun: saha formu ve ön kayıt hakkında sorular',
        onTap: () => context.push(AppRoutes.assistant),
        trailing: AknIconButton(
          icon: PhosphorIconsRegular.x,
          semanticLabel: 'Asistan satırını kapat',
          size: 20,
          color: context.akn.dim,
          onPressed: () {
            setState(() => _hidden = true);
            unawaited(ref.read(prefsStoreProvider).setBool(key, true));
          },
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
      icon: PhosphorIconsRegular.sun,
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
    final c = context.akn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Bulunduğunuz yerde hava'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AnimatedSwitcher(
            duration: AknMotion.of(context, AknMotion.base),
            switchInCurve: AknMotion.emphasizedCurve,
            child: fix != null
                ? WeatherCard(
                    key: const ValueKey('weather'),
                    lat: fix.latitude,
                    lng: fix.longitude,
                  )
                : AknCard(
                    key: const ValueKey('prompt'),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const _FloatingSun(),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(
                            'Ziyaret planınız için bulunduğunuz yerin hava durumunu görün.',
                            style: t.bodySmall.copyWith(color: c.ink),
                          ),
                        ),
                        AknButton.secondary(
                          label: _busy ? 'Konum alınıyor…' : 'Konumu kullan',
                          icon: PhosphorIconsRegular.gpsFix,
                          size: AknButtonSize.small,
                          onPressed: _busy ? null : _locate,
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        FieldLocationNotice(
          outcome: _outcome,
          onRetry: _locate,
          margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        ),
      ],
    );
  }
}

/// Hava kartı isteminin güneşi: sıcak turuncu yumuşak dairede, hafifçe süzülür (ortam hareketi).
class _FloatingSun extends StatelessWidget {
  const _FloatingSun();

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final sun = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.brandSoft, shape: BoxShape.circle),
      child: Icon(PhosphorIconsFill.sun, size: 24, color: c.brand),
    );
    return AknAmbient(
      period: AknMotion.float,
      reverse: true,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, -3 + 6 * t),
        child: Transform.rotate(angle: 0.12 * t, child: child),
      ),
      child: sun,
    );
  }
}
