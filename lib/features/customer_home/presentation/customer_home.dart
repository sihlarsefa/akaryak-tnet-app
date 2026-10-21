import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/storage/prefs_store.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../assistant/api.dart';
import '../../customer_orders/api.dart';
import '../copy.dart';
import 'home_sections.dart';

/// Son 6 ayın harcaması (ana sayfa eğrisi). Yetki ya da uç yoksa null (kart gizlenir).
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

/// Müşteri ana sayfası (spec A.4 A2): "Sipariş ver", sipariş verebilirlik, karar bekleyen teklifler
/// (geri sayım), yüklenecek ödeme belgeleri, yoldaki teslimat, limitler, son şablonlar, yarım kalan
/// sipariş, harcama eğrisi ve asistan. Sınıf adı ve kurucu imzası sabittir (spec C.3).
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
    await ref.read(customerHomeProvider.notifier).refresh();
    ref.invalidate(homeSpendingProvider);
    ref.invalidate(draftSummaryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(customerHomeProvider);
    final home = s.data;
    final policy = ref.watch(accessPolicyProvider);
    final features = ref.watch(appConfigProvider).features;
    // Asistan girişleri: özellik açık ve sunucu 503 `assistant_disabled` demedi (spec A.6).
    final assistantOn =
        features.assistant && ref.watch(assistantEnabledProvider);

    Widget body;
    if (home == null && s.isFirstLoad) {
      body = const SkeletonList(
        itemCount: 3,
        header: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: AknHeroPanel(
            child: SizedBox(height: 120, width: double.infinity),
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
            ContentWidth(
              child: _HomeContent(
                home: home,
                updatedAt: s.updatedAt,
                fromCache: s.fromCache,
                assistant: assistantOn,
                canCreate: policy.can(Pg.customerCreateOrder, Perm.create),
              ),
            ),
          ],
        ),
      );
    }

    return AppScaffold(
      navy: true,
      titleWidget: const AknLogo(markSize: 28, onDark: true),
      refreshing: s.refreshing,
      actions: [
        if (assistantOn)
          AknIconButton(
            icon: Icons.chat_bubble_outline_rounded,
            semanticLabel: HomeCopy.assistant,
            color: context.akn.onNavy,
            onPressed: () => context.push(AppRoutes.assistant),
          ),
      ],
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
    final spending = ref.watch(homeSpendingProvider).valueOrNull;
    final tipDismissed =
        uid == null ||
        prefs == null ||
        prefs.getBool(A2Keys.tipFirstOrder(uid));
    final assistantDismissed =
        uid == null ||
        prefs == null ||
        prefs.getBool(A2Keys.assistantCardDismissed(uid));
    final firstName = (access?.displayName ?? '').split(' ').first;
    final canSeeOrders = policy.canAny(const [
      Pg.customerOrders,
      Pg.customerQuotes,
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LastUpdatedNote(updatedAt: updatedAt, fromCache: fromCache),
        HomeHero(
          greeting:
              '${HomeCopy.greeting(TrTime.wall(TrTime.now()))}${firstName.isEmpty ? '' : ', $firstName'}',
          title: home.customerTitle,
          dashboard: dash,
          canCreate: canCreate && home.hasStations,
          canOrder: home.canOrder,
          onNewOrder: () => context.push(AppRoutes.orderNew),
          onDecisions: canSeeOrders
              ? () => context.push('${AppRoutes.orders}?segment=decision')
              : null,
          onShipments: policy.can(Pg.customerShipments)
              ? () => context.push(AppRoutes.shipments)
              : null,
        ),
        if (!home.canOrder) OrderingBanner(home: home),
        if (home.financeInfoRequests > 0 && home.canOrder)
          AknBanner(
            tone: AknTone.warn,
            icon: Icons.mark_email_unread_rounded,
            title: HomeCopy.financeInfo,
            message: HomeCopy.financeInfoMessage,
            actionLabel: 'Yanıtla',
            onAction: () => context.push(AppRoutes.financeInfo),
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          ),
        if (submit.isActive)
          SubmissionStatusCard(state: submit)
        else if (draft != null && canCreate)
          ResumeDraftCard(summary: draft),
        if (!tipDismissed && dash.lastOrder == null && canCreate)
          FirstOrderTip(
            onStart: () => context.push(AppRoutes.orderNew),
            onDismiss: () async {
              await prefs.setBool(A2Keys.tipFirstOrder(uid), true);
              ref.read(homeLocalRevisionProvider.notifier).bump();
            },
          ),
        if (dash.pendingDecisions.isNotEmpty)
          DecisionsSection(
            rows: dash.pendingDecisions,
            total: dash.pendingDecisionTotal,
            expiryEnabled: dash.expiryEnabled,
          ),
        if (home.pendingPaymentDocuments.isNotEmpty)
          PendingDocumentsSection(
            documents: home.pendingPaymentDocuments,
            onUploaded: () async =>
                ref.read(a2DataRevisionProvider.notifier).bump(),
          ),
        if (dash.activeShipment != null)
          ActiveDeliveryCard(
            shipment: dash.activeShipment!,
            openTotal: dash.openShipmentTotal,
            station: home.station,
          ),
        if (home.companyApprovalsWaiting > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AknCard(
              accent: AknTone.info,
              padding: EdgeInsets.zero,
              child: AknListTile(
                leadingIcon: Icons.how_to_reg_rounded,
                leadingTone: AknTone.info,
                title: HomeCopy.companyApprovals,
                subtitle:
                    '${home.companyApprovalsWaiting} şirket içi sipariş talebi kararınızı bekliyor.',
                onTap: () => context.push(AppRoutes.approvals),
              ),
            ),
          ),
        if (home.limits.isNotEmpty) LimitsSection(limits: home.limits),
        if (home.templates.isNotEmpty && canCreate)
          TemplatesSection(templates: home.templates),
        if (spending != null && spending.length > 1)
          SpendingSection(months: spending),
        if (assistant && !assistantDismissed)
          AssistantCard(
            onOpen: () => context.push(AppRoutes.assistant),
            onDismiss: () async {
              await prefs.setBool(A2Keys.assistantCardDismissed(uid), true);
              ref.read(homeLocalRevisionProvider.notifier).bump();
            },
          ),
        if (home.station != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bayiniz: ${home.station!.title}',
                  style: context.aknText.bodySmall.copyWith(
                    color: context.akn.dim,
                  ),
                ),
                const SizedBox(height: 6),
                StationContactButtons(station: home.station, dense: true),
              ],
            ),
          ),
        if (updatedAt != null && !fromCache)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Güncellendi ${Fmt.relative(updatedAt)}',
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
