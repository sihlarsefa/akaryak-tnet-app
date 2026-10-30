import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/models/enums.dart'
    show ApprovalSlaState, ApprovalStatus, ApprovalType;
import '../../../core/network/app_failure.dart';
import '../../../core/offline/connectivity.dart';
import '../../../core/offline/outbox_op.dart' show OutboxStatus;
import '../../../core/offline/outbox_providers.dart';
import '../../../core/routing/app_location.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/storage/prefs_store.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../approvals/api.dart'
    show ApprovalRow, ApprovalsQuery, approvalsListProvider;
import '../../finance/api.dart'
    show
        MyApprovals,
        approvalsOfType,
        leadFinanceApprovals,
        myApprovalsBySubjectProvider;
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

/// Saha satış ana sayfası (tasarım v4 "Sade" §3.3, `fieldRep`): turuncu `AknHomeHeader` bandı (avatar
/// Profil'i açar) → bandın üstüne binen "Sıra sizde" kartı (gönderilmeyi bekleyen formlar "Şimdi
/// gönder", ek bilgi bekleyen ön kayıtlar, en sonda nötr taslaklar; iş yoksa sakin satır) → kendi
/// portföyünün istatistik destesi → ilk oturumda "Nasıl çalışır" → "Saha formlarım" (KPI satırı +
/// onay bekleyen, taslak, reddedilen satırları) → "Ön kayıtlarım" → "Tüpraş fiyatları" →
/// bulunduğunuz yerde hava. Bölümler ilk açılışta sırayla, sonra kaydırdıkça kayarak belirir. "Yeni
/// form" alt menünün ortasındaki tuştadır. Sınıf adı ve kurucu imzası sabittir.
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
          cachedAt: state.cachedAt,
        ),
      );
    }

    final name = (me?.displayName ?? '').trim();
    // Rol adı sunucudan (panelle aynı); yoksa şablonun adı (roller v5: "Satış temsilcisi").
    final role = (me?.bayiRoleNames.isNotEmpty ?? false)
        ? me!.bayiRoleNames.first
        : BayiRoleCodes.name(BayiRoleCodes.fieldRep);
    return AppScaffold(
      homeHeader: AknHomeHeader(
        company: me?.stationTitle ?? 'Saha satış',
        person: [if (name.isNotEmpty) name, fieldLowerFirst(role)].join(', '),
        // Profil bazı rollerde alt menünün sekmesidir: `push` kabuğu ikinci kez kurardı (SC-01).
        onOpenProfile: () => context.openAppLocation(AppRoutes.profile),
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
    this.cachedAt,
  });

  final FieldHomeData data;
  final FieldAccess access;
  final List<FieldQueuedItem> queued;
  final bool weather;
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
      // Sahip kararı G + v4 §3.3: "Sıra sizde" turuncu şeridin üstüne biner (AknBandOverlap).
      _FieldHero(data: data, queued: queued),
      // Kendi portföyünün destesi kahramanın hemen altında, ilk ekranda.
      const ManagerStatsDeck(
        raised: false,
        padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
      ),
      const _FieldHint(),
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
            actionLabel: 'Yeni form',
            onAction: () => context.push(AppRoutes.fieldFormNew),
          ),
        ),
      if (access.canSeeLeads) ..._leadSection(context),
      const TuprasStrip(),
      if (weather) const _WeatherHere(),
      const SizedBox(height: 32),
    ];
    // Kahraman bandın üstüne kendi yükselişiyle gelir; diğer bölümler sırayla (ve kaydırınca) belirir.
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

/// "Sıra sizde" (v4 §3.3 saha): gönderilmeyi bekleyen formlar ("Şimdi gönder": bekleyen işlemleri
/// hemen dener), ek bilgi bekleyen ön kayıtlar, en sonda nötr ve sayılmayan taslaklar. İş yoksa
/// sakin satır.
///
/// v4 tur 2 (B13): finansın bilgi istediği ön kayıt bir onay talebidir (Onaylar › Bende'de; Diğer'in
/// noktası da onu sayar). "Bilgi gönder" o talebin yanıt alanını açar (`/approvals/:id?reply=1`):
/// iş ve sayı tek sayfada. Birden çok talepte Onaylar ön kayıt türüne süzülü açılır; talep Bende'de
/// bulunamazsa ön kayıt açılır.
///
/// v4 tur 2: Bende'nin ön kayıt dışındaki talepleri de (bilgi istenen saha formu) birer iştir:
/// gecikmiş olan tehlike tonuyla öne geçer. Kartın sayısı Diğer › Onaylar'ın sayısıdır (gönderilecek
/// formlar eklenir): ana sayfa ile Onaylar aynı sayıyı söyler (P2).
class _FieldHero extends ConsumerWidget {
  const _FieldHero({required this.data, required this.queued});

  final FieldHomeData data;
  final List<FieldQueuedItem> queued;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = [
      for (final q in queued)
        if (q.isForm || q.isLead) q,
    ];
    final stuck = waiting.any((q) => q.status == OutboxStatus.needsAttention);
    void send() {
      if (!ref.read(isOnlineProvider)) {
        AppToast.info(
          'Çevrimdışısınız; bağlantı gelince otomatik gönderilir.',
          context: context,
        );
        return;
      }
      unawaited(ref.read(outboxRunnerProvider).retryWaiting());
    }

    final forms = waiting.where((q) => q.isForm).length;
    final leads = waiting.length - forms;
    final what = [
      if (forms > 0) '$forms form',
      if (leads > 0) '$leads ön kayıt',
    ].join(' ve ');
    final info = data.leadsNeedingInfoCount > 0
        ? data.leadsNeedingInfoCount
        : data.leadsNeedingInfo.length;
    final mine = info > 0
        ? ref.watch(myApprovalsBySubjectProvider(leadFinanceApprovals))
        : null;
    // Bende (Diğer › Onaylar'ın listesi ve sayısı): ön kayıt işinin taşımadığı talepler.
    final bende = ref.watch(approvalsListProvider(const ApprovalsQuery()));
    final now = TrTime.now();
    final others = [
      for (final a in bende.items)
        if (!(info > 0 && a.type == ApprovalType.leadFinance)) a,
    ];
    bool late(ApprovalRow a) =>
        a.slaState == ApprovalSlaState.overdue ||
        (a.dueAt != null && !a.dueAt!.isAfter(now));
    final overdue = [
      for (final a in others)
        if (late(a)) _requestTask(context, a, now, late: true),
    ];
    final onTime = [
      for (final a in others)
        if (!late(a)) _requestTask(context, a, now, late: false),
    ];
    final tasks = <AknTask>[
      ...overdue,
      if (waiting.isNotEmpty)
        AknTask(
          id: 'field-queue',
          title: 'Gönderilmeyi bekleyen $what',
          subtitle: stuck
              ? 'Biri düzeltilmeyi bekliyor'
              : 'Bağlantı gelince otomatik gönderilir',
          icon: PhosphorIconsRegular.cloudArrowUp,
          tone: stuck ? AknTaskTone.danger : AknTaskTone.yourMove,
          actionLabel: 'Şimdi gönder',
          onAction: send,
        ),
      if (info > 0)
        AknTask(
          id: 'field-lead-info',
          title: info == 1
              ? 'Ön kayıt için bilgi gönderin'
              : '$info ön kayıt için bilgi gönderin',
          subtitle: data.leadsNeedingInfo.isEmpty
              ? 'Finans ek bilgi istedi'
              : data.leadsNeedingInfo
                    .take(2)
                    .map((l) => l.companyTitle)
                    .join(' · '),
          icon: PhosphorIconsRegular.question,
          actionLabel: 'Bilgi gönder',
          onAction: () => _openInfo(context, mine),
          onTap: () => _openInfo(context, mine),
        ),
      ...onTime,
      if (data.drafts > 0)
        AknTask(
          id: 'field-drafts',
          title: data.drafts == 1
              ? 'Yarım kalan formunuz'
              : 'Yarım kalan ${data.drafts} form',
          subtitle: data.recentDrafts.isEmpty
              ? null
              : data.recentDrafts.first.customerTitle,
          icon: PhosphorIconsRegular.notePencil,
          tone: AknTaskTone.neutral,
          actionLabel: 'Taslaklara git',
          onAction: () => context.go('${AppRoutes.field}?tab=forms&status=0'),
          onTap: () => context.go('${AppRoutes.field}?tab=forms&status=0'),
          counts: false,
        ),
    ];
    // Sayı = Diğer › Onaylar'ın sayısı (Bende'nin toplamı) + gönderilecek formlar; Bende okunamazsa
    // kartın kendi işleri.
    final total = bende.hasData
        ? bende.totalCount + (waiting.isNotEmpty ? 1 : 0)
        : null;
    return AknBandOverlap(
      child: AknTaskCard(
        tasks: tasks,
        total: total == null
            ? null
            : math.max(total, tasks.where((t) => t.counts).length),
        calm: 'Ziyaretten sonra Yeni form ile siparişi yazın.',
        onSeeAll: () => context.go(AppRoutes.field),
      ),
    );
  }

  /// Bende'deki bir talep "Sıra sizde" işi olarak: bilgi isteneni "… için bilgi gönderin" ve müşteri;
  /// gecikmişse tehlike tonu ve "2 sa gecikti". Dokununca talebin yanıt alanı açılır (B13 ile aynı
  /// sayfa).
  static AknTask _requestTask(
    BuildContext context,
    ApprovalRow a,
    DateTime now, {
    required bool late,
  }) {
    final info = a.status == ApprovalStatus.infoRequested;
    final title = !info
        ? 'Talebi inceleyin'
        : switch (a.type) {
            ApprovalType.fieldFormFinance ||
            ApprovalType.fieldOrderProfit => 'Saha formu için bilgi gönderin',
            ApprovalType.leadFinance => 'Ön kayıt için bilgi gönderin',
            _ => 'Bilgi gönderin',
          };
    final summary = (a.summary ?? '').split(' · ').first.trim();
    final who = a.customerTitle ?? (summary.isEmpty ? null : summary);
    final due = a.dueAt;
    void open() => unawaited(
      context.push(
        info
            ? '${AppRoutes.approval(a.id)}?reply=1'
            : '${AppRoutes.approval(a.id)}?focus=request',
      ),
    );
    return AknTask(
      id: 'approval-${a.id}',
      title: title,
      subtitle: who,
      icon: info
          ? PhosphorIconsRegular.question
          : PhosphorIconsRegular.checkCircle,
      tone: late ? AknTaskTone.danger : AknTaskTone.yourMove,
      amount: a.amount == null ? null : Fmt.moneyWhole(a.amount!),
      deadline: !late && due != null ? due : null,
      time: late && due != null
          ? '${_lateShort(now.difference(due))} gecikti'
          : null,
      actionLabel: info ? 'Bilgi gönder' : 'Talebi incele',
      onAction: open,
      onTap: open,
    );
  }

  /// "2 g", "5 sa", "40 dk": gecikmenin en büyük birimi (Onaylar satırıyla aynı söz).
  static String _lateShort(Duration d) {
    if (d.inDays > 0) return '${d.inDays} g';
    if (d.inHours > 0) return '${d.inHours} sa';
    return '${d.inMinutes.clamp(1, 59)} dk';
  }

  /// Bilgi isteyen talebin yanıt alanı (B13): tek talepte `/approvals/:id?reply=1`, birden çokta
  /// Onaylar (ön kayıt türü). Bende okunamadıysa ya da talep orada değilse ön kayıt sayfaları.
  void _openInfo(BuildContext context, MyApprovals? mine) {
    final leads = data.leadsNeedingInfo;
    final requests = [for (final l in leads) ?mine?[l.id]];
    if (leads.length == 1 && requests.length == 1) {
      unawaited(
        context.push('${AppRoutes.approval(requests.single.id)}?reply=1'),
      );
    } else if (leads.length > 1 && requests.isNotEmpty) {
      context.openAppLocation(approvalsOfType(ApprovalType.leadFinance));
    } else if (leads.length == 1) {
      unawaited(context.push(AppRoutes.fieldLead(leads.first.id)));
    } else {
      context.go('${AppRoutes.field}?tab=leads&status=info');
    }
  }
}

/// "Nasıl çalışır" (v4 §4 `AknFirstRunHint`): ilk oturumda bir kez, kullanıcı başına; "Anladım"
/// deyince bir daha gösterilmez (eski ipucu ve asistan satırının yerine).
class _FieldHint extends ConsumerStatefulWidget {
  const _FieldHint();

  @override
  ConsumerState<_FieldHint> createState() => _FieldHintState();
}

class _FieldHintState extends ConsumerState<_FieldHint> {
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    final uid = ref.read(currentUserIdProvider);
    final key = uid == null ? null : PrefKeys.user(uid, 'field.tipDismissed');
    final hide =
        _hidden || key == null || ref.read(prefsStoreProvider).getBool(key);
    return AknAnimatedSize(
      duration: AknMotion.slow,
      curve: AknMotion.emphasizedCurve,
      alignment: Alignment.topCenter,
      child: hide
          ? const SizedBox(width: double.infinity)
          : AknFirstRunHint(
              steps: AknFirstRunHint.fieldSteps,
              onDismiss: () {
                setState(() => _hidden = true);
                unawaited(ref.read(prefsStoreProvider).setBool(key, true));
              },
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
    // v4 §6: liste içinde döngü yok — güneş üç kez süzülür, sonra durur.
    return AknAmbient(
      period: AknMotion.float,
      reverse: true,
      cycles: 3,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, -3 + 6 * t),
        child: Transform.rotate(angle: 0.12 * t, child: child),
      ),
      child: sun,
    );
  }
}
