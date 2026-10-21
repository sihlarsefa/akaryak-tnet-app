// Biyometrik kilit (spec A.4 A1): açılışta bir kez sorar; başarıda kilit açılır; iptal ya da
// başarısızlıkta "Şifreyle giriş yap" (oturum kapanır, kullanıcı adı giriş formuna taşınır); cihaz uygun
// değilse doğrudan şifre; erişilebilirlik matrisi. Uygulamanın tamamıyla akış: auth_flow_test.dart.
import 'package:akaryakitnet/core/auth/lock_settings.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/auth/api.dart';
import 'package:akaryakitnet/features/auth/application/login_effects.dart';
import 'package:akaryakitnet/features/auth/presentation/locked_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'auth_test_support.dart';

/// Giriş yapar, kilitler ve `/locked` sayfasını açar.
Future<ProviderContainer> _locked(
  WidgetTester tester,
  FakeBiometric bio, {
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  final h = await AuthHarness.create(
    prefs: {'akn.onboardingDone': true, PrefKeys.biometricLock: true},
  );
  final c = await pumpAuthRoute(
    tester,
    '/home',
    harness: h,
    textScale: textScale,
    brightness: brightness,
    overrides: [biometricAuthenticatorProvider.overrideWithValue(bio)],
  );
  await signIn(tester, c, 'musteri');
  c.read(sessionControllerProvider.notifier).lock();
  GoRouter.of(tester.element(find.text('ANA SAYFA'))).go('/locked');
  await pumpFor(tester, const Duration(milliseconds: 600));
  return c;
}

void main() {
  a11yMatrix('kilit ekranı (iptal sonrası)', (tester, scale, b) async {
    final bio = FakeBiometric(outcomes: [BiometricOutcome.cancelled]);
    final c = await _locked(tester, bio, textScale: scale, brightness: b);
    expect(find.byType(LockedPage), findsOneWidget);
    expect(find.text('Tekrar hoş geldiniz, Selin Aydın'), findsOneWidget);
    expect(bio.calls, 1);
    expect(find.text('Doğrulama iptal edildi.'), findsOneWidget);
    expect(find.text('Şifreyle giriş yap'), findsOneWidget);
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(c.read(sessionControllerProvider), isA<SessionLocked>());
  });

  testWidgets('başarılı doğrulama kilidi açar (bir kez otomatik sorar)', (
    tester,
  ) async {
    setPhoneSize(tester);
    final bio = FakeBiometric();
    final c = await _locked(tester, bio);
    expect(bio.calls, 1);
    expect(c.read(sessionControllerProvider), isA<SessionAuthenticated>());
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'iptal → tekrar dene başarısız → "Şifreyle giriş yap" oturumu kapatır',
    (tester) async {
      setPhoneSize(tester);
      final bio = FakeBiometric(
        outcomes: [BiometricOutcome.cancelled, BiometricOutcome.failed],
      );
      final c = await _locked(tester, bio);
      await tester.tap(find.text('Tekrar dene'));
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.text('Kimliğiniz doğrulanamadı.'), findsOneWidget);
      expect(bio.calls, 2);

      await tester.tap(find.text('Şifreyle giriş yap'));
      await pumpUntil(
        tester,
        () => c.read(sessionControllerProvider) is SessionUnauthenticated,
      );
      final state = c.read(sessionControllerProvider) as SessionUnauthenticated;
      expect(state.message, 'Güvenliğiniz için şifrenizle giriş yapın.');
      expect(c.read(loginPrefillProvider), 'musteri');
      expect(c.read(biometricLockProvider), isTrue, reason: 'tercih korunur');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('cihaz uygun değil: yalnızca "Şifreyle giriş yap"', (
    tester,
  ) async {
    setPhoneSize(tester);
    final bio = FakeBiometric(
      supportValue: BiometricSupport.none,
      outcomes: [BiometricOutcome.unavailable],
    );
    await _locked(tester, bio);
    expect(
      find.text('Bu cihazda biyometrik doğrulama şu an kullanılamıyor.'),
      findsOneWidget,
    );
    expect(find.text('Şifreyle giriş yap'), findsOneWidget);
    expect(find.byType(AknButton), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
