// A-INT persona geçişi (spec D.3, C.7): her persona 360×640 telefonda, yazı ölçeği 2,0 ve koyu temada
// giriş yapar; alt menüdeki her sekme ve "Diğer" sayfasındaki her hedef taşmadan açılır, sekme kökleri
// dört erişilebilirlik kılavuzunu geçer (dokunma hedefi, etiket, kontrast). Ağ yok; sahte sunucu.
import 'dart:async';

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/a11y.dart';
import '../support/test_app.dart';

Future<ProviderContainer> _signIn(WidgetTester tester, String persona) async {
  final h = await TestHarness.create(prefs: const {'akn.onboardingDone': true});
  await tester.pumpWidget(
    ProviderScope(overrides: h.overrides, child: const AknApp()),
  );
  await pumpSteps(tester, const Duration(seconds: 2));
  final c = ProviderScope.containerOf(tester.element(find.byType(AknApp)));
  await tester.runAsync(() async {
    final s = c.read(sessionControllerProvider.notifier);
    final outcome = await s.loginWithPassword(persona, 'demo');
    if (outcome is LoginNeedsCode) {
      await s.verifyCode(outcome.challenge.challengeId, '123456');
    }
  });
  await pumpSteps(tester, const Duration(seconds: 2));
  return c;
}

void main() {
  for (final persona in fakePersonas) {
    testWidgets('${persona.key}: 2,0× koyu — sekmeler ve Diğer', (
      tester,
    ) async {
      setA11yPhone(tester);
      setA11yPlatform(tester, A11yVariant.largeDark);
      final c = await _signIn(tester, persona.key);
      expect(c.read(sessionControllerProvider), isA<SessionAuthenticated>());
      final layout = c.read(navLayoutProvider);
      final bar = find.byType(AnimatedBottomBar);
      expect(bar, findsOneWidget);
      expectNoLayoutErrors(tester);
      // Ayarlar gerçekten uygulandı: koyu tema, 2,0× yazı (alt menü 1,3×'te sınırlı).
      final page = tester.element(find.byType(Scaffold).first);
      expect(Theme.of(page).brightness, Brightness.dark);
      expect(MediaQuery.textScalerOf(page).scale(10), 20);

      // Sekmeler (ilk sekme zaten açık).
      for (var i = 0; i < layout.bar.length; i++) {
        if (i > 0) {
          await tester.tap(
            find.descendant(
              of: bar,
              matching: find.text(layout.bar[i].barLabel),
            ),
          );
          await pumpSteps(tester, const Duration(milliseconds: 1500));
        }
        await settleIo(tester);
        expectNoLayoutErrors(tester);
        await expectA11yGuidelines(tester);
      }

      // "Diğer" sayfasındaki hedefler tam ekran açılır, geri dönülür.
      final router = GoRouter.of(tester.element(bar));
      for (final d in layout.more) {
        unawaited(router.push(d.path));
        await pumpSteps(tester, const Duration(milliseconds: 1500));
        await settleIo(tester);
        expectNoLayoutErrors(tester);
        router.pop();
        await pumpSteps(tester, const Duration(milliseconds: 800));
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
