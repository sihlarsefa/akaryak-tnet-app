import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/tasks/task_inbox.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/models/models.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/routing/app_location.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/turkish_text.dart';
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

/// Müşteri ana sayfası (tasarım v4 "Sade" §3.3, sahip kararı G): ışıklı turuncu üst bant (avatar
/// profili açar, selamlama, şirket, zil) → bandın üstüne binen "Sıra sizde" kartı (görev kutusu:
/// sayısı Onaylar rozetiyle aynı; iş yoksa sakin satır) → gönderim durumu (varsa) → yönetici
/// destesi ya da bu ayın kartı (ilk ekranda) → ilk oturumda "Nasıl çalışır" → "Yolda" (araç yoldayken
/// ya da bugün planlıyken) → "Hızlı sipariş" → başlıksız limit ve bayi kartı. Talep eden: deste yok;
/// "Sıra sizde"den sonra "Taleplerim". Karar, belge, şirket talebi ve finans uyarıları ayrı bölüm
/// değildir: hepsi "Sıra sizde"nin satırlarıdır. Sınıf adı ve kurucu imzası sabittir (spec C.3).
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
            child: SkeletonBox(height: 260, radius: AknRadius.plateRadius),
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
        // Avatar ve adlar tek, etiketli, ≥ 48 px düğüm: profili açar (Profil bazı rollerde
        // sekmedir: `openAppLocation`).
        onOpenProfile: () => context.openAppLocation(AppRoutes.profile),
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
  });

  final CustomerHomeData home;
  final DateTime? updatedAt;
  final bool fromCache;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(accessPolicyProvider);
    final submit = ref.watch(orderSubmitProvider);
    final inbox = ref.watch(customerTasksProvider);
    final dash = home.dashboard;
    final role = policy.customerRole;
    final requester = role == CustomerUserRole.requester;
    final canCreate = policy.can(Pg.customerCreateOrder, Perm.create);
    final deck = !requester && ref.watch(canSeeStatsDeckProvider);
    final monthPlate =
        !deck && !requester && dash.stats != null && dash.lastOrder != null;
    final months = monthPlate
        ? ref.watch(homeSpendingProvider).valueOrNull
        : null;

    // Yöneticinin destesi ilk ekranda kalır (sahip kararı 9): iş varken "Nasıl çalışır" destenin
    // altına iner; "Sıra sizde" sakinken hemen altında durur.
    final hintFirst = customerHeroTasks(inbox, role).isEmpty;
    final hint = HomeFirstRunHint(
      key: const ValueKey('hint'),
      steps: requester
          ? HomeCopy.requesterSteps
          : canCreate
          ? AknFirstRunHint.customerSteps
          : HomeCopy.viewerSteps,
      firstOrder: canCreate && dash.lastOrder == null,
    );
    final Widget? plate = deck
        ? const ManagerStatsDeck(
            key: ValueKey('deck'),
            raised: false,
            padding: EdgeInsets.fromLTRB(AknSpace.page, 16, AknSpace.page, 0),
          )
        : monthPlate
        ? MonthPlate(
            key: const ValueKey('month'),
            dashboard: dash,
            months: months,
            onOpen: policy.can(Pg.customerSpending)
                ? () => context.openAppLocation(AppRoutes.spending)
                : null,
          )
        : null;

    // "Sıra sizde"nin altındaki bölümler birbiri ardına yükselerek gelir; sonradan eklenen bölüm
    // kendi yerinde belirir.
    final sections = <Widget>[
      if (hintFirst) hint,
      ?plate,
      if (!hintFirst) hint,
      if (requester) const MyRequestsSection(key: ValueKey('requests')),
      if (OnTheWaySection.pick(dash) != null)
        OnTheWaySection(key: const ValueKey('on-the-way'), dashboard: dash),
      if (canCreate)
        QuickOrderSection(
          key: const ValueKey('quick'),
          lastOrder: dash.lastOrder,
          templates: home.templates,
        ),
      HomeLimitsLedger(
        key: const ValueKey('limits'),
        limits: home.limits,
        station: home.station,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Kahraman: "Sıra sizde" bandın üstüne biner ve yükselerek gelir.
        AknBandOverlap(child: CustomerTaskHero(home: home)),
        if (submit.isActive) SubmissionStatusCard(state: submit),
        LastUpdatedNote(
          updatedAt: updatedAt,
          fromCache: fromCache,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        ),
        StaggerScope(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, section) in sections.indexed)
                StaggerItem(key: section.key, index: i + 1, child: section),
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
}
