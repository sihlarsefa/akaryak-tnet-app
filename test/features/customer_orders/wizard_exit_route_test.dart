// QA SC-01: sihirbazın sonuç ekranından "Siparişlere git". Siparişler her müşteri rolünde alt menü
// sekmesidir. Sihirbaz tam ekran bir sayfanın (talepler, sipariş ayrıntısı, şablonlar) üstünde
// açıldıysa, sihirbaz kapandıktan sonra sekme yolunu `push` etmek kabuğu kök gezginde ikinci kez
// kurardı ("A GlobalKey was used multiple times"). [leaveOrderWizard] sekmeye `go` ile geçer.
import 'dart:async';

import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/routing/app_routes.dart';
import 'package:akaryakitnet/features/customer_orders/presentation/wizard/order_wizard_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../qa/shell-common/qa_support.dart';

Future<void> _leave(
  WidgetTester tester, {
  required String below,
  required String Function(QaApp app) to,
}) async {
  final qa = QaProblems('wizard_exit_${below.replaceAll('/', '_')}');
  try {
    final app = await launchQa(tester);
    await qaSignIn(tester, app, 'musteri');
    final router = app.container.read(routerProvider);
    final route = to(app);
    if (below != AppRoutes.home) {
      unawaited(router.push(below));
      await pumpSteps(tester, const Duration(milliseconds: 1000));
      await settleIo(tester);
    }
    unawaited(router.push(AppRoutes.orderNew));
    await pumpSteps(tester, const Duration(milliseconds: 1200));
    await settleIo(tester);
    expect(find.byType(OrderWizardPage), findsOneWidget);
    qa.check(tester, 'sihirbaz');
    qa.where = 'sonuçtan ayrıl → $route';
    leaveOrderWizard(router, route);
    await pumpSteps(tester, const Duration(milliseconds: 1500));
    await settleIo(tester);
    qa.check(tester, 'sonuçtan ayrıl → $route');
    expect(find.byType(OrderWizardPage), findsNothing);
    expect(app.location, route);
    await tester.pumpWidget(const SizedBox());
  } catch (e, st) {
    qa.add(
      'beklenmeyen: ${e.toString().split('\n').take(8).join(' ')} @ '
      '${st.toString().split('\n').where((l) => l.contains('customer_orders')).take(3).join(' | ')}',
    );
  } finally {
    qa.finish();
  }
}

void main() {
  testWidgets(
    'talepler sayfasının üstünde açılan sihirbaz → "Siparişlere git" Siparişler sekmesine geçer',
    (tester) => _leave(
      tester,
      below: AppRoutes.companyRequests,
      to: (_) => AppRoutes.orders,
    ),
  );

  testWidgets(
    'ana sayfadan açılan sihirbaz → "Siparişlere git" Siparişler sekmesine geçer',
    (tester) =>
        _leave(tester, below: AppRoutes.home, to: (_) => AppRoutes.orders),
  );

  testWidgets(
    'talepler sayfasının üstünde açılan sihirbaz → "Siparişi aç" ayrıntıyı açar',
    (tester) async {
      // Ayrıntı alt menünün üstünde tam ekran açılır (`push`); sekme değildir.
      await _leave(
        tester,
        below: AppRoutes.companyRequests,
        to: (app) => AppRoutes.order(
          app.harness.server.world.ordersOfCustomer(101).first['id'] as int,
        ),
      );
    },
  );
}
