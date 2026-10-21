// Persona duman akışları (spec D.3 A-INT): sahte kipte giriş → kabuk → her sekme → "Diğer"deki her
// hedef → çıkış. Hem cihazda (`integration_test/app_smoke_test.dart`) hem ana makinede
// (`test/app/smoke_flows_test.dart`) aynı kod çalışır. Ağ yok.
import 'dart:async';

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../test/support/test_app.dart';

/// Ekran görüntüsü alıcı (cihazda `binding.takeScreenshot`, ana makinede yok).
typedef ShotTaker = Future<void> Function(String name);

Future<void> pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

/// Uygulamayı sahte sunucuyla açar (tanıtım görülmüş) ve kapsayıcıyı döndürür.
Future<ProviderContainer> launchFakeApp(WidgetTester tester) async {
  final h = await TestHarness.create(prefs: const {'akn.onboardingDone': true});
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

/// Tek personanın duman akışı. Her adımda yerleşim hatası olmadığını denetler.
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
  await shot?.call('${persona}_1_${layout.bar.first.id.name}');

  for (var i = 1; i < layout.bar.length; i++) {
    await tester.tap(
      find.descendant(of: bar, matching: find.text(layout.bar[i].barLabel)),
    );
    await pumpFor(tester, const Duration(milliseconds: 1200));
    expect(tester.takeException(), isNull, reason: layout.bar[i].label);
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
      expect(tester.takeException(), isNull, reason: d.label);
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
