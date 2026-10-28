import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/models/models.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/storage/prefs_store.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/turkish_text.dart';
import '../../assistant/api.dart';
import '../../customer_more/api.dart';
import '../../customer_orders/api.dart';
import '../../stats/api.dart';
import '../copy.dart';
import 'home_sections.dart';

/// Son 6 ayın harcaması (ay plakasının çubukları). Yetki ya da uç yoksa null.
final homeSpendingProvider = FutureProvider.autoDispose<List<SpendingMonth>?>((
  ref,
) async {
  final policy = ref.watch(accessPolicyProvider);
  if (!policy.can(Pg.customerSpending)) return null;
  try {
    final months = await ref
        .read(customerOrdersRepositoryProvider)
        .spendingMonths();
    return months.isEmpty ? null : months;
  } on AppFailure {
    return null;
  }
});

/// Müşteri ana sayfası (tasarım v3 "Akış", sahip kararı G): ışıklı turuncu üst bant (avatar,
/// selamlama, şirket, zil) → bandın üstüne binen tek kahraman kart (yönetici destesi "Bu ay
/// harcama"; deste yoksa bu ayın kartı; bant kendi yükselişiyle getirir) → kırık beyaz sayfada
/// yüzen beyaz bölüm kartları (r22), birbiri ardına yükselerek: karar bekleyen en acil teklif
/// (geri sayım) → "Yolda" (rota çizgisi) → onay bekleyen talepler → yüklenecek ödeme belgeleri →
/// Limitlerim → Şablonlarım. "Sipariş ver" alt çubuğun ortasındaki tuştur. Talep eden: deste yok;
/// sayfa "Taleplerim" ile başlar. Sınıf adı ve kurucu imzası sabittir (spec C.3).
class CustomerHome extends ConsumerStatefulWidget {
  const CustomerHome({super.key});

  @override
  ConsumerState<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends ConsumerState<CustomerHome> {
  @override
  void initState() {
    super.initState();
    // Uygulama gönderim sırasında kapandıysa aynı anahtarla doğrula (spec C.4a).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(orderSubmitProvider.notifier).resumeIfPending());
    });
  }

  Future<void> _refresh() async {
    await Future.wait([
      ref.read(customerHomeProvider.notifier).refresh(),
      refreshManagerStats(ref),
    ]);
    ref.invalidate(homeSpendingProvider);
    ref.invalidate(draftSummaryProvider);
    ref.invalidate(homeOrderRequestsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(customerHomeProvider);
    final home = s.data;
    final policy = ref.watch(accessPolicyProvider);
    final access = ref.watch(sessionControllerProvider).access;
    final features = ref.watch(appConfigProvider).features;
    // Asistan girişleri: özellik açık ve sunucu 503 `assistant_disabled` demedi (spec A.6).
    final assistantOn =
        features.assistant && ref.watch(assistantEnabledProvider);
    final company = home?.customerTitle ?? access?.customerTitle ?? '';
    final role =
        access?.customerUserRoleLabel ??
        (policy.customerRole.isUnknown ? null : policy.customerRole.label);

    Widget body;
    if (home == null && s.isFirstLoad) {
      body = const SkeletonList(
        itemCount: 3,
        padding: EdgeInsets.zero,
        header: AknBandOverlap(
          child: Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: SkeletonBox(height: 300, radius: AknRadius.plateRadius),
          ),
        ),
      );
    } else if (home == null) {
      body = Center(
        child: SingleChildScrollView(
          child: FailureView(
            failure: s.error ?? const UnknownFailure(),
            onRetry: _refresh,
          ),
        ),
      );
    } else {
      body = PullToRefresh(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: 32 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            _HomeContent(
              home: home,
              updatedAt: s.updatedAt,
              fromCache: s.fromCache,
              assistant: assistantOn,
              canCreate: policy.can(Pg.customerCreateOrder, Perm.create),
            ),
          ],
        ),
      );
    }

    return AppScaffold(
      homeHeader: AknHomeHeader(
        company: company,
        person: access == null
            ? null
            : HomeCopy.person(access.displayName, role),
        // Avatar ve adlar tek, etiketli, ≥ 48 px düğüm (çekirdek düzeltmesi): profili açar.
        onOpenProfile: () => context.push(AppRoutes.profile),
      ),
      refreshing: s.refreshing,
      body: body,
    );
  }
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent({
    required this.home,
    required this.updatedAt,
    required this.fromCache,
    required this.assistant,
    required this.canCreate,
  });

  final CustomerHomeData home;
  final DateTime? updatedAt;
  final bool fromCache;
  final bool assistant;
  final bool canCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(homeLocalRevisionProvider);
    final policy = ref.watch(accessPolicyProvider);
    final access = ref.watch(sessionControllerProvider).access;
    final uid = access?.userId;
    final prefs = _prefs(ref);
    final dash = home.dashboard;
    final draft = ref.watch(draftSummaryProvider).valueOrNull;
    final submit = ref.watch(orderSubmitProvider);
    final role = policy.customerRole;
    final requester = role == CustomerUserRole.requester;
    final canDecide = role.canApprove;
    final deck = !requester && ref.watch(canSeeStatsDeckProvider);
    final stats = dash.stats;
    final monthPlate =
        !deck && !requester && stats != null && dash.lastOrder != null;
    final months = monthPlate
        ? ref.watch(homeSpendingProvider).valueOrNull
        : null;
    final tipDismissed =
        uid == null ||
        prefs == null ||
        prefs.getBool(A2Keys.tipFirstOrder(uid));
    final assistantDismissed =
        uid == null ||
        prefs == null ||
        prefs.getBool(A2Keys.assistantCardDismissed(uid));
    final active = dash.activeShipment;
    // Ekranın tek kahraman kartı: yönetici destesi ya da bu ayın kartı; bandın üstüne biner.
    final Widget? hero = deck
        ? const ManagerStatsDeck(padding: EdgeInsets.zero)
        : monthPlate
        ? MonthPlate(
            dashboard: dash,
            months: months,
            padding: EdgeInsets.zero,
            onOpen: policy.can(Pg.customerSpending)
                ? () => context.push(AppRoutes.spending)
                : null,
          )
        : null;
    // Ritim (v3 §3): kahramanın (ve sayfa noktalarının) altından ilk karta 20, kartlar arası 14;
    // kahraman yoksa bandın hemen altı 16.
    var firstTaken = false;
    double top() {
      if (firstTaken) return 14;
      firstTaken = true;
      return hero == null ? 16 : 20;
    }

    // Kartın içindeki başlığın üstü.
    const inner = 16.0;

    // Bölüm kartları: kahramanın altında birbiri ardına yükselerek gelir (v3 §5); sonradan
    // eklenen kart (yeni teklif, taslak) kendi yerinde belirir. Kahraman kartı bandın üstünde
    // kendi girişini yapar.
    final sections = <(String, Widget)>[
      // Engelleyen durumlar ve yarım işler (kuyular).
      if (!home.canOrder) ('ordering', OrderingBanner(home: home, top: top())),
      if (home.financeInfoRequests > 0 && home.canOrder)
        (
          'finance',
          Padding(
            padding: EdgeInsets.fromLTRB(
              homeBoxGutter(context),
              top(),
              homeBoxGutter(context),
              0,
            ),
            child: AknBanner(
              tone: AknTone.warn,
              icon: PhosphorIconsRegular.envelopeSimple,
              title: HomeCopy.financeInfo,
              message: HomeCopy.financeInfoMessage,
              actionLabel: 'Yanıtla',
              onAction: () => context.push(AppRoutes.financeInfo),
            ),
          ),
        ),
      if (submit.isActive)
        ('submit', SubmissionStatusCard(state: submit, top: top())),
      if (!tipDismissed && dash.lastOrder == null && canCreate)
        (
          'tip',
          FirstOrderTip(
            top: top(),
            onStart: () => context.push(AppRoutes.orderNew),
            onDismiss: () async {
              await prefs.setBool(A2Keys.tipFirstOrder(uid), true);
              ref.read(homeLocalRevisionProvider.notifier).bump();
            },
          ),
        ),
      // Talep eden: kendi talepleri önce.
      if (requester)
        (
          'my-requests',
          CompanyRequestsSection(
            approver: false,
            headerTop: inner,
            boxTop: top(),
          ),
        ),
      if (dash.pendingDecisions.isNotEmpty)
        (
          'decisions',
          HomeSectionBox(
            top: top(),
            child: DecisionsSection(
              headerTop: inner,
              rows: dash.pendingDecisions,
              total: dash.pendingDecisionTotal,
              expiryEnabled: dash.expiryEnabled,
              canDecide: canDecide,
            ),
          ),
        ),
      if (active != null)
        (
          'delivery',
          HomeSectionBox(
            top: top(),
            padding: EdgeInsets.zero,
            child: ActiveDeliveryCard(
              headerTop: inner,
              shipment: active,
              openTotal: dash.openShipmentTotal,
              station: home.station,
              canDecide: canDecide,
            ),
          ),
        ),
      if (canDecide && home.companyApprovalsWaiting > 0)
        (
          'approvals',
          CompanyRequestsSection(
            headerTop: inner,
            boxTop: top(),
            approver: true,
            waiting: home.companyApprovalsWaiting,
          ),
        ),
      if (home.pendingPaymentDocuments.isNotEmpty)
        (
          'documents',
          HomeSectionBox(
            top: top(),
            child: PendingDocumentsSection(
              headerTop: inner,
              documents: home.pendingPaymentDocuments,
              onUploaded: () async =>
                  ref.read(a2DataRevisionProvider.notifier).bump(),
            ),
          ),
        ),
      if (!submit.isActive && draft != null && canCreate)
        ('draft', ResumeDraftCard(summary: draft, top: top())),
      if (home.limits.isNotEmpty)
        (
          'limits',
          HomeSectionBox(
            top: top(),
            child: LimitsSection(limits: home.limits, headerTop: inner),
          ),
        ),
      if (home.templates.isNotEmpty && canCreate)
        (
          'templates',
          HomeSectionBox(
            top: top(),
            child: TemplatesSection(
              templates: home.templates,
              headerTop: inner,
            ),
          ),
        ),
      if (assistant && !assistantDismissed)
        (
          'assistant',
          HomeSectionBox(
            top: top(),
            padding: EdgeInsets.zero,
            child: AssistantCard(
              top: 4,
              onOpen: () => context.push(AppRoutes.assistant),
              onDismiss: () async {
                await prefs.setBool(A2Keys.assistantCardDismissed(uid), true);
                ref.read(homeLocalRevisionProvider.notifier).bump();
              },
            ),
          ),
        ),
      if (home.station != null)
        (
          'station',
          HomeSectionBox(
            top: top(),
            padding: const EdgeInsets.only(bottom: 18),
            child: StationSection(station: home.station!, headerTop: inner),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hero != null) AknBandOverlap(child: hero),
        LastUpdatedNote(
          updatedAt: updatedAt,
          fromCache: fromCache,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        ),
        StaggerScope(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, (id, section)) in sections.indexed)
                StaggerItem(key: ValueKey(id), index: i, child: section),
            ],
          ),
        ),
        if (updatedAt != null && !fromCache)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Text(
              'Güncellendi ${TurkishText.lower(Fmt.relative(updatedAt))}',
              textAlign: TextAlign.center,
              style: context.aknText.caption.copyWith(color: context.akn.dim),
            ),
          ),
      ],
    );
  }

  static PrefsStore? _prefs(WidgetRef ref) {
    try {
      return ref.read(prefsStoreProvider);
    } catch (_) {
      return null;
    }
  }
}
