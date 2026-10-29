// QA shell-common: yönlendirici erişim kuralları gerçek uygulamada, her persona × her hedef.
//
// Oturum açıkken `router.go(rota)`: `RouteAccess.isAllowed` izin veriyorsa sayfa açılır (istisna yok,
// hata durumu yok — istemcinin izin verdiği sayfayı sunucu 403 ile reddetmemeli); izin vermiyorsa
// personanın ilk sekmesine dönülür (yasak sayfa bir kare bile çizilmez).
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/routing/route_access.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_support.dart';

List<String> _routes(QaApp app) {
  final w = app.harness.server.world;
  final customerOrder = w.ordersOfCustomer(101).first['id'];
  final bayiOrder = w.ordersOfStation(1).first['id'];
  final shipment = w.shipments.isEmpty ? 5 : w.shipments.first['id'];
  final approval = w.approvals.isEmpty ? 9001 : w.approvals.first['id'];
  return [
    '/home',
    '/notifications',
    '/notifications/settings',
    '/assistant',
    '/profile',
    '/profile/password',
    '/profile/edit',
    '/profile/sessions',
    '/profile/delete-account',
    '/stats',
    '/orders',
    '/orders/new',
    '/orders/$customerOrder',
    '/shipments',
    '/shipments/$shipment',
    '/company/requests',
    '/finance-info',
    '/documents',
    '/spending',
    '/delivery-points',
    '/templates',
    '/limits',
    '/company/users',
    '/quote-desk',
    '/bayi/orders',
    '/bayi/orders/$bayiOrder',
    '/customers',
    '/dispatch',
    '/bayi/staff',
    '/driver',
    '/driver/shipments/$shipment',
    '/approvals',
    '/approvals/$approval',
    '/finance',
    '/payments',
    '/payments/$bayiOrder',
    '/field',
    '/field/forms/new',
    '/field/leads/new',
  ];
}

/// Şu an bilinen hatayla düşen personalar (düzeltilince silin).
// QA SC-02 düzeltildi (mix_chart.dart: değer sığmazsa adın altına iner).
const _knownIssues = <String, String>{};

void main() {
  for (final persona in fakePersonas) {
    final known = _knownIssues[persona.key];
    testWidgets(
      '${persona.key}: her rotada erişim kuralı ve sayfa'
      '${known == null ? '' : ' [$known]'}',
      skip: known != null,
      (tester) async {
        final qa = QaProblems('access_${persona.key}');
        try {
          final app = await launchQa(tester);
          await qaSignIn(tester, app, persona.key);
          final layout = app.container.read(navLayoutProvider);
          final router = app.container.read(routerProvider);
          final problems = qa.items;
          for (final route in _routes(app)) {
            final policy = AccessPolicy(
              app.container.read(sessionControllerProvider).access,
            );
            final features = app.container.read(appConfigProvider).features;
            final allowed = RouteAccess.isAllowed(route, policy, features);
            qa.where = route;
            router.go(route);
            await pumpSteps(tester, const Duration(milliseconds: 900));
            await settleIo(tester, rounds: 4);
            final e = tester.takeException();
            if (e != null) problems.add('$route → istisna: $e');
            final at = app.location;
            if (allowed) {
              final home =
                  route == '/home' && !layout.inBar(DestinationId.home);
              if (!home && at != route) {
                problems.add('$route izinli ama konum $at');
              }
              final errs = qaErrorTexts();
              if (errs.isNotEmpty) problems.add('$route izinli ama: $errs');
              if (find.text('Bu sayfa bulunamadı').evaluate().isNotEmpty) {
                problems.add('$route izinli ama "Bu sayfa bulunamadı"');
              }
            } else {
              // v4 §3.5: the nearest allowed parent, else the first tab.
              final expected =
                  allowedParentOf(
                    Uri.parse(route).path,
                    layout,
                    policy,
                    features,
                  ) ??
                  layout.initialLocation;
              if (at != expected) {
                problems.add('$route yasak ama konum $at (beklenen $expected)');
              }
            }
          }
          await tester.pumpWidget(const SizedBox());
        } catch (e, st) {
          qa.add(
            'beklenmeyen: ${e.toString().split('\n').take(8).join(' ')} @ '
            '${st.toString().split('\n').where((l) => l.contains('shell-common')).take(3).join(' | ')}',
          );
        } finally {
          qa.finish();
        }
      },
    );
  }
}
