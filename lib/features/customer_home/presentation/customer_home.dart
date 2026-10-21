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

/// Müşteri ana sayfası (sahip kararı G "F2GO kart dili"): turuncu geçişli üst bant (avatar,
/// selamlama, şirket, zil) → bandın üstüne 48 px binen tek kahraman kart (yönetici destesi "Bu ay
/// harcama"; deste yoksa bu ayın kartı; beyaz, hafif turuncu tonlu) → #F9FAFB sayfada beyaz bölüm
/// kutuları: karar bekleyen en acil teklif (geri sayım) → "Yolda" (rota çizgisi) → onay bekleyen
/// talepler → yüklenecek ödeme belgeleri → Limitlerim → Şablonlarım. "Sipariş ver" alt çubuğun
/// ortasındaki tuştur. Talep eden: deste yok; sayfa "Taleplerim" ile başlar. Sınıf adı ve kurucu
/// imzası sabittir (spec C.3).
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
          padding: const EdgeInsets.only(bottom: 32),
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
    // Kahramandan sonraki ilk blokun üstü 14, sonrakiler 12 (bölüm kutuları arası ritim); kahraman
    // yoksa bandın hemen altı 16.
    var firstTaken = false;
    double top() {
      if (firstTaken) return 12;
      firstTaken = true;
      return hero == null ? 16 : 14;
    }

    // Kutunun içindeki başlığın üstü.
    const inner = 14.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hero != null) AknBandOverlap(child: hero),
        LastUpdatedNote(
          updatedAt: updatedAt,
          fromCache: fromCache,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        ),
        // Engelleyen durumlar ve yarım işler (kuyular).
        if (!home.canOrder) OrderingBanner(home: home, top: top()),
        if (home.financeInfoRequests > 0 && home.canOrder)
          Padding(
            padding: EdgeInsets.fromLTRB(18, top(), 18, 0),
            child: AknBanner(
              tone: AknTone.warn,
              icon: Icons.mark_email_unread_outlined,
              title: HomeCopy.financeInfo,
              message: HomeCopy.financeInfoMessage,
              actionLabel: 'Yanıtla',
              onAction: () => context.push(AppRoutes.financeInfo),
            ),
          ),
        if (submit.isActive) SubmissionStatusCard(state: submit, top: top()),
        if (!tipDismissed && dash.lastOrder == null && canCreate)
          FirstOrderTip(
            top: top(),
            onStart: () => context.push(AppRoutes.orderNew),
            onDismiss: () async {
              await prefs.setBool(A2Keys.tipFirstOrder(uid), true);
              ref.read(homeLocalRevisionProvider.notifier).bump();
            },
          ),
        // Talep eden: kendi talepleri önce.
        if (requester)
          CompanyRequestsSection(
            approver: false,
            headerTop: inner,
            boxTop: top(),
          ),
        if (dash.pendingDecisions.isNotEmpty)
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
        if (active != null)
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
        if (canDecide && home.companyApprovalsWaiting > 0)
          CompanyRequestsSection(
            headerTop: inner,
            boxTop: top(),
            approver: true,
            waiting: home.companyApprovalsWaiting,
          ),
        if (home.pendingPaymentDocuments.isNotEmpty)
          HomeSectionBox(
            top: top(),
            child: PendingDocumentsSection(
              headerTop: inner,
              documents: home.pendingPaymentDocuments,
              onUploaded: () async =>
                  ref.read(a2DataRevisionProvider.notifier).bump(),
            ),
          ),
        if (!submit.isActive && draft != null && canCreate)
          ResumeDraftCard(summary: draft, top: top()),
        if (home.limits.isNotEmpty)
          HomeSectionBox(
            top: top(),
            child: LimitsSection(limits: home.limits, headerTop: inner),
          ),
        if (home.templates.isNotEmpty && canCreate)
          HomeSectionBox(
            top: top(),
            child: TemplatesSection(
              templates: home.templates,
              headerTop: inner,
            ),
          ),
        if (assistant && !assistantDismissed)
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
        if (home.station != null)
          HomeSectionBox(
            top: top(),
            padding: const EdgeInsets.only(bottom: 14),
            child: StationSection(station: home.station!, headerTop: inner),
          ),
        if (updatedAt != null && !fromCache)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Text(
              'Güncellendi ${TurkishText.lower(Fmt.relative(updatedAt))}',
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
