// Push rota tablosu (spec A.5, D.3 A-INT): sunucunun her olay × alıcı tarafı için ürettiği rota
// (`NotificationTemplates.Route`) uygulamada bir sayfaya eşleşir ve o tarafın personasına açıktır;
// açamayan kullanıcı `/notifications`'a düşer.
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/app/fakes.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/models/app_config.dart';
import 'package:akaryakitnet/core/models/me_access.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/routing/nav_keys.dart';
import 'package:akaryakitnet/core/routing/route_access.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

final _world = buildFakeServer(latency: false).world;

AccessPolicy _policy(String key) =>
    AccessPolicy(MeAccess.fromJson(_world.meAccess(findFakePersona(key)!)));

const _features = AppFeatures(assistant: true);

/// Sunucunun rotaları (B2 `NotificationTemplates.Route`) ve o tarafın örnek personaları.
const _table = <(String event, String audience, String route, List<String>)>[
  ('order.created', 'bayi', '/bayi/orders/12', ['sahip', 'mudur', 'siparis']),
  ('order.quote_ready', 'customer', '/orders/12', ['musteri', 'onay', 'talep']),
  ('order.quote_expiring', 'customer', '/orders/12', ['musteri', 'onay']),
  ('order.approved', 'bayi', '/bayi/orders/12', ['sahip', 'mudur']),
  ('order.rejected', 'bayi', '/bayi/orders/12', ['sahip', 'siparis']),
  ('order.rejected', 'customer', '/orders/12', ['musteri', 'talep']),
  ('order.expired', 'customer', '/orders/12', ['musteri']),
  ('order.completed', 'bayi', '/bayi/orders/12', ['sahip', 'mudur']),
  ('order.finance_info', 'customer', '/orders/12', ['musteri', 'talep']),
  ('payment.document_uploaded', 'bayi', '/payments/12', ['muhasebe', 'sahip']),
  ('payment.bounced', 'bayi', '/payments/12', ['muhasebe', 'finans']),
  ('payment.collected', 'customer', '/orders/12', ['musteri']),
  ('payment.instrument_due', 'bayi', '/payments/12', ['muhasebe']),
  ('shipment.planned', 'customer', '/orders/12', ['musteri', 'onay']),
  ('shipment.planned', 'driver', '/driver/shipments/5', ['sofor', 'sahip']),
  ('shipment.assigned', 'driver', '/driver/shipments/5', ['sofor', 'sahip']),
  ('shipment.unassigned', 'driver', '/driver', ['sofor']),
  ('shipment.dispatched', 'customer', '/orders/12', ['musteri']),
  ('shipment.reported', 'customer', '/shipments/5', ['musteri', 'onay']),
  (
    'shipment.reported',
    'bayi',
    '/bayi/orders/12',
    ['sahip', 'siparis', 'sevkiyat', 'depo'],
  ),
  ('shipment.disputed', 'bayi', '/bayi/orders/12', ['sahip', 'sevkiyat']),
  ('shipment.disputed', 'driver', '/driver/shipments/5', ['sofor']),
  ('shipment.cancelled', 'customer', '/orders/12', ['musteri']),
  (
    'approval.pending',
    'approver',
    '/approvals/9001',
    ['finans', 'finansuzman', 'mudur', 'sahip', 'satis', 'onay', 'musteri'],
  ),
  ('approval.pending', 'platform', '/approvals/9001', ['merkez']),
  (
    'approval.info_requested',
    'customer',
    '/approvals/9004',
    ['musteri', 'talep'],
  ),
  ('fieldform.decided', 'creator', '/field/forms/7001', ['saha']),
  ('lead.updated', 'creator', '/field/leads/8001', ['saha']),
  ('company_request.decided', 'creator', '/company/requests/3001', ['talep']),
  ('limit_request.decided', 'creator', '/customers/102', ['sahip', 'satis']),
  ('system.test', 'any', '/notifications', ['sofor', 'musteri', 'merkez']),
];

void main() {
  late GoRouter router;

  setUpAll(() {
    // Tüm özellik rotalarıyla kurulmuş tablo (kabuk sekmeleri bir bayi yerleşiminden).
    final layout = buildNavLayout(_policy('sahip'), _features);
    router = GoRouter(
      navigatorKey: rootNavigatorKey,
      routes: buildAppRoutes(layout),
    );
  });

  tearDownAll(() => router.dispose());

  group('her olay rotası uygulamada bir sayfaya eşleşir', () {
    for (final (event, audience, route, _) in _table) {
      test('$event / $audience → $route', () {
        final match = router.configuration.findMatch(Uri.parse(route));
        expect(match.isError, isFalse, reason: route);
        expect(match.isNotEmpty, isTrue, reason: route);
      });
    }
  });

  group('alıcı tarafının personası rotayı açabilir', () {
    for (final (event, audience, route, personas) in _table) {
      for (final key in personas) {
        test('$event / $audience → $key', () {
          expect(
            RouteAccess.resolvePushRoute(route, _policy(key), _features),
            route,
          );
        });
      }
    }
  });

  group('açamayan kullanıcı Bildirimler\'e düşer', () {
    final denied = <(String route, String persona)>[
      ('/bayi/orders/12', 'musteri'),
      ('/bayi/orders/12', 'sofor'),
      ('/orders/12', 'sahip'),
      ('/payments/12', 'saha'),
      ('/payments/12', 'musteri'),
      ('/field/forms/7001', 'muhasebe'),
      ('/company/requests/3001', 'sahip'),
      ('/driver/shipments/5', 'musteri'),
      ('/orders/12', 'merkez'),
      ('/customers/102', 'musteri'),
    ];
    for (final (route, key) in denied) {
      test('$key ✗ $route', () {
        expect(
          RouteAccess.resolvePushRoute(route, _policy(key), _features),
          '/notifications',
        );
      });
    }

    test('boş, göreli ya da bozuk rota', () {
      final p = _policy('musteri');
      expect(
        RouteAccess.resolvePushRoute(null, p, _features),
        '/notifications',
      );
      expect(RouteAccess.resolvePushRoute('', p, _features), '/notifications');
      expect(
        RouteAccess.resolvePushRoute('orders/12', p, _features),
        '/notifications',
      );
    });
  });
}
