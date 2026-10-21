// Persona duman akışları (spec D.3 A-INT): sahte kipte giriş → kabuk → her sekme → "Diğer"deki her
// hedef → çıkış. Hem cihazda (`integration_test/app_smoke_test.dart`) hem ana makinede
// (`test/app/smoke_flows_test.dart`) aynı kod çalışır. Ağ yok.
import 'dart:async';

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../test/support/a11y.dart' show settleIo;
import '../test/support/test_app.dart';

/// Ekran görüntüsü alıcı (cihazda `binding.takeScreenshot`, ana makinede yok).
typedef ShotTaker = Future<void> Function(String name);

Future<void> pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

/// Uygulamayı sahte sunucuyla açar (tanıtım görülmüş) ve kapsayıcıyı döndürür. [world] verilirse o
/// dünya kullanılır (ör. performans senaryosunda 100+ sipariş).
Future<ProviderContainer> launchFakeApp(
  WidgetTester tester, {
  FakeWorld? world,
}) async {
  final h = await TestHarness.create(
    prefs: const {'akn.onboardingDone': true},
    world: world,
  );
  await tester.pumpWidget(
    ProviderScope(overrides: h.overrides, child: const AknApp()),
  );
  await pumpFor(tester, const Duration(seconds: 2));
  return ProviderScope.containerOf(tester.element(find.byType(AknApp)));
}

/// Demo hesabıyla giriş (şifre `demo`, SMS kodu `123456`).
Future<void> signInAs(
  WidgetTester tester,
  ProviderContainer c,
  String persona,
) async {
  await tester.runAsync(() async {
    final s = c.read(sessionControllerProvider.notifier);
    final outcome = await s.loginWithPassword(persona, 'demo');
    if (outcome is LoginNeedsCode) {
      await s.verifyCode(outcome.challenge.challengeId, '123456');
    }
  });
  await pumpFor(tester, const Duration(seconds: 2));
}

/// Sayfa ya da bölüm hata durumu görünmüyor (sahte sunucuda her uç personanın yetkisiyle yanıt verir).
void expectNoErrorState(String where) {
  expect(find.byType(ErrorState), findsNothing, reason: '$where: hata durumu');
  expect(
    find.textContaining('Bu bölüm yüklenemedi'),
    findsNothing,
    reason: '$where: bölüm yüklenemedi',
  );
}

/// Tek personanın duman akışı. Her adımda yerleşim hatası ve hata durumu olmadığını denetler.
Future<void> runPersonaSmoke(
  WidgetTester tester,
  String persona, {
  ShotTaker? shot,
}) async {
  final c = await launchFakeApp(tester);
  expect(find.text('Giriş yap'), findsOneWidget);
  await signInAs(tester, c, persona);
  expect(c.read(sessionControllerProvider), isA<SessionAuthenticated>());
  final layout = c.read(navLayoutProvider);
  final bar = find.byType(AnimatedBottomBar);
  expect(bar, findsOneWidget);
  await settleIo(tester);
  expectNoErrorState('$persona ${layout.bar.first.label}');
  await shot?.call('${persona}_1_${layout.bar.first.id.name}');

  for (var i = 1; i < layout.bar.length; i++) {
    await tester.tap(
      find.descendant(of: bar, matching: find.text(layout.bar[i].barLabel)),
    );
    await pumpFor(tester, const Duration(milliseconds: 1200));
    await settleIo(tester);
    expect(tester.takeException(), isNull, reason: layout.bar[i].label);
    expectNoErrorState('$persona ${layout.bar[i].label}');
    await shot?.call('${persona}_${i + 1}_${layout.bar[i].id.name}');
  }

  if (layout.hasMore) {
    await tester.tap(
      find.descendant(of: bar, matching: find.text(NavLayout.moreLabel)),
    );
    await pumpFor(tester, const Duration(milliseconds: 800));
    await shot?.call('${persona}_diger');
    // Sayfayı kapat (kaydırarak değil, geri ile).
    final nav = Navigator.of(
      tester.element(find.text(NavLayout.moreLabel).last),
    );
    nav.pop();
    await pumpFor(tester, const Duration(milliseconds: 600));
    final router = GoRouter.of(tester.element(bar));
    for (final d in layout.more) {
      unawaited(router.push(d.path));
      await pumpFor(tester, const Duration(milliseconds: 1200));
      await settleIo(tester);
      expect(tester.takeException(), isNull, reason: d.label);
      expectNoErrorState('$persona ${d.label}');
      router.pop();
      await pumpFor(tester, const Duration(milliseconds: 600));
    }
  }

  await tester.runAsync(
    () => c.read(sessionControllerProvider.notifier).signOut(),
  );
  await pumpFor(tester, const Duration(seconds: 1));
  expect(find.text('Giriş yap'), findsOneWidget);
  await tester.pumpWidget(const SizedBox());
}

/// Ekrandaki en büyük dikey kaydırılabilir alan (filtre çipleri gibi yatay listeler değil).
Finder mainVerticalList(WidgetTester tester) {
  final all = find.byType(Scrollable);
  var best = all.first;
  var bestArea = -1.0;
  for (var i = 0; i < all.evaluate().length; i++) {
    final f = all.at(i);
    final s = tester.widget<Scrollable>(f);
    if (axisDirectionToAxis(s.axisDirection) != Axis.vertical) continue;
    final size = tester.getSize(f);
    if (size.width * size.height > bestArea) {
      bestArea = size.width * size.height;
      best = f;
    }
  }
  return best;
}
