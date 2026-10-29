// v4 tur 2 (son düzeltmeler, yönlendirme): Diğer › Teslimatlar itilen bir sayfadır ve geri düğmesi
// vardır; teslimattan "Listeye dön" kabuksuz köke `go` yapmaz, yığında listeye döner; sekmedeki
// Siparişler'de aynı durak bağlantısına yeniden dokunmak yine uygulanır.
import 'dart:async';

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/application/orders_controller.dart';
import 'package:akaryakitnet/features/bayi/data/order_models.dart';
import 'package:akaryakitnet/features/driver/driver_paths.dart';
import 'package:akaryakitnet/features/driver/presentation/driver_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

Future<ProviderContainer> _start(WidgetTester tester, String key) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  final h = await TestHarness.create(prefs: const {'akn.onboardingDone': true});
  await tester.pumpWidget(
    ProviderScope(overrides: h.overrides, child: const AknApp()),
  );
  await _pumpFor(tester, const Duration(seconds: 2));
  final c = ProviderScope.containerOf(tester.element(find.byType(AknApp)));
  await tester.runAsync(() async {
    final s = c.read(sessionControllerProvider.notifier);
    final outcome = await s.loginWithPassword(key, 'demo');
    if (outcome is LoginNeedsCode) {
      await s.verifyCode(outcome.challenge.challengeId, '123456');
    }
  });
  await _pumpFor(tester, const Duration(seconds: 3));
  expect(c.read(sessionControllerProvider), isA<SessionAuthenticated>());
  return c;
}

void main() {
  testWidgets('sahip: Diğer › Teslimatlar geri düğmesiyle açılır; geri Ana sayfa', (
    tester,
  ) async {
    final c = await _start(tester, 'sahip');
    final router = c.read(routerProvider);
    // Sahipte Teslimatlar alt menüde değil: itilir (bandın başında geri düğmesi).
    unawaited(router.push<Object?>(DriverPaths.home));
    await _pumpFor(tester, const Duration(seconds: 2));
    expect(find.byType(DriverHome), findsOneWidget);
    final header = tester.widget<AknHomeHeader>(
      find.byType(AknHomeHeader).last,
    );
    expect(
      header.leading,
      isNotNull,
      reason: 'itilen Teslimatlar geri düğmesi',
    );
    await tester.tap(find.bySemanticsLabel('Geri').last);
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(router.state.uri.path, '/home');
    expect(find.byType(AnimatedBottomBar), findsOneWidget);

    // "Listeye dön": yığında listeye kadar geri gelinir; kabuk (alt menü) yerinde kalır.
    unawaited(router.push<Object?>(DriverPaths.home));
    await _pumpFor(tester, const Duration(seconds: 1));
    unawaited(router.push<Object?>('${DriverPaths.home}/shipments/999999'));
    await _pumpFor(tester, const Duration(seconds: 1));
    backToDriverList(tester.element(find.byType(Scaffold).last));
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(router.state.uri.path, DriverPaths.home);
    expect(router.canPop(), isTrue, reason: 'altında Ana sayfa');
    router.pop();
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(router.state.uri.path, '/home');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'sahip: sekmedeki Siparişler\'de aynı durak bağlantısı elle seçimden sonra yine uygulanır',
    (tester) async {
      final c = await _start(tester, 'sahip');
      final router = c.read(routerProvider);
      const link = '/bayi/orders?segment=awaitingCustomer';
      router.go(link);
      await _pumpFor(tester, const Duration(seconds: 2));
      expect(
        c.read(bayiOrdersProvider).filter.segment,
        BayiOrderSegment.awaitingCustomer,
      );
      // Uygulanan bağlantı adresten düşer (sekme yalın adresi hatırlar).
      expect(router.state.uri.toString(), '/bayi/orders');
      // Kullanıcı "Tümü"yü seçer, Ana sayfaya döner ve aynı durağa yeniden dokunur.
      c.read(bayiOrdersProvider.notifier).setSegment(null);
      await _pumpFor(tester, const Duration(milliseconds: 500));
      router.go('/home');
      await _pumpFor(tester, const Duration(seconds: 1));
      router.go(link);
      await _pumpFor(tester, const Duration(seconds: 2));
      expect(
        c.read(bayiOrdersProvider).filter.segment,
        BayiOrderSegment.awaitingCustomer,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
