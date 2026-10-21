// Özellikler arası rota sözleşmesi (spec C.4, D.3 A-INT): her alt menü hedefinin gerçek bir ekranı
// vardır ("Yakında" yedeği kullanılmaz), `AppRoutes` yollarının hepsi bir sayfaya eşleşir ve iki özellik
// aynı kök yolu tanımlamaz.
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/app/fakes.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/models/app_config.dart';
import 'package:akaryakitnet/core/models/me_access.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/routing/app_routes.dart';
import 'package:akaryakitnet/core/routing/nav_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  final table = featureRouteTable();
  final topLevel = [
    for (final r in table)
      if (r is GoRoute) r.path,
  ];

  test('her hedefin özellik rotası var (Yakında yedeği yok)', () {
    for (final d in appDestinations) {
      if (d.id == DestinationId.home) continue;
      expect(topLevel, contains(d.path), reason: '${d.id.name} → ${d.path}');
    }
  });

  test('iki özellik aynı kök yolu tanımlamaz', () {
    final seen = <String>{};
    final dupes = [
      for (final p in topLevel)
        if (!seen.add(p)) p,
    ];
    expect(dupes, isEmpty);
  });

  group('AppRoutes yolları bir sayfaya eşleşir', () {
    late GoRouter router;
    setUpAll(() {
      final world = buildFakeServer(latency: false).world;
      final policy = AccessPolicy(
        MeAccess.fromJson(world.meAccess(findFakePersona('sahip')!)),
      );
      router = GoRouter(
        navigatorKey: rootNavigatorKey,
        routes: buildAppRoutes(
          buildNavLayout(policy, const AppFeatures(assistant: true)),
          devRoutes: true,
        ),
      );
    });
    tearDownAll(() => router.dispose());

    final paths = <String>[
      AppRoutes.splash,
      AppRoutes.update,
      '${AppRoutes.update}?reason=server',
      AppRoutes.onboarding,
      AppRoutes.login,
      AppRoutes.loginCode,
      AppRoutes.locked,
      AppRoutes.home,
      AppRoutes.notifications,
      AppRoutes.assistant,
      AppRoutes.profile,
      AppRoutes.profilePhone,
      AppRoutes.orders,
      AppRoutes.orderNew,
      AppRoutes.order(12),
      AppRoutes.orderNewFrom(template: 3),
      AppRoutes.orderNewFrom(request: 3001),
      AppRoutes.orderNewFrom(reorder: 12),
      AppRoutes.shipments,
      AppRoutes.shipment(5),
      AppRoutes.companyRequests,
      AppRoutes.companyRequest(3001),
      AppRoutes.financeInfo,
      AppRoutes.documents,
      '${AppRoutes.documents}?orderId=12',
      AppRoutes.spending,
      AppRoutes.deliveryPoints,
      AppRoutes.templates,
      AppRoutes.limits,
      AppRoutes.companyUsers,
      AppRoutes.quoteDesk,
      AppRoutes.bayiOrders,
      AppRoutes.bayiOrder(12),
      AppRoutes.customers,
      AppRoutes.customer(102),
      AppRoutes.dispatch,
      AppRoutes.bayiStaff,
      AppRoutes.driver,
      AppRoutes.driverShipment(5),
      AppRoutes.approvals,
      '${AppRoutes.approvals}?scope=bende',
      AppRoutes.approval(9001),
      '${AppRoutes.approval(9004)}?reply=1',
      AppRoutes.finance,
      AppRoutes.financeCustomer(501),
      AppRoutes.payments,
      '${AppRoutes.payments}?tab=instruments',
      AppRoutes.payment(12),
      AppRoutes.field,
      '${AppRoutes.field}?tab=leads&status=info',
      AppRoutes.fieldFormNew,
      AppRoutes.fieldForm(7001),
      AppRoutes.fieldLeadNew,
      AppRoutes.fieldLead(8001),
      AppRoutes.dev,
      AppRoutes.devGallery,
    ];
    for (final p in paths) {
      test(p, () {
        final match = router.configuration.findMatch(Uri.parse(p));
        expect(match.isError, isFalse, reason: p);
        expect(match.isNotEmpty, isTrue, reason: p);
      });
    }
  });
}
