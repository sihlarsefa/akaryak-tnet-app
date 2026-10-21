// Uygulamanın tamamıyla (gerçek yönlendirici, kabuk, tüm sahte uçlar) A1 akışları (spec D.3 A1):
// ilk açılışta tanıtım → "Atla" → giriş; giriş → 2FA → kabuk; telefonla giriş → kabuk; zorunlu
// güncelleme yönlendirmesi; eski API'de "Sunucu güncel değil"; kilit ekranı ve şifreye dönüş;
// ikinci girişte biyometrik kilit önerisi.
import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/shell/platform_home.dart';
import 'package:akaryakitnet/core/auth/lock_settings.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/network/fake/core_fakes.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/auth/api.dart';
import 'package:akaryakitnet/features/auth/application/login_effects.dart';
import 'package:akaryakitnet/features/auth/auth_fake.dart';
import 'package:akaryakitnet/features/auth/presentation/code_page.dart';
import 'package:akaryakitnet/features/auth/presentation/locked_page.dart';
import 'package:akaryakitnet/features/auth/presentation/update_page.dart';
import 'package:akaryakitnet/features/customer_home/api.dart';
import 'package:akaryakitnet/features/onboarding/presentation/onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinput/pinput.dart';

import '../../support/test_app.dart';
import 'auth_test_support.dart';

/// Etiketi alanın üstünde duran (tasarım v2 §6.10) metin alanı.
Finder _field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(AknTextField)),
  matching: find.byType(TextField),
);

Future<ProviderContainer> _launch(
  WidgetTester tester, {
  Map<String, Object> prefs = const {'akn.onboardingDone': true},
  TestHarness? harness,
  List<Override> overrides = const [],
}) async {
  setPhoneSize(tester, const Size(390, 844));
  final h = harness ?? await TestHarness.create(prefs: prefs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...h.overrides, ...overrides],
      child: const AknApp(),
    ),
  );
  await pumpFor(tester, const Duration(seconds: 2));
  return ProviderScope.containerOf(tester.element(find.byType(AknApp)));
}

Future<void> _typeLogin(
  WidgetTester tester,
  String user,
  String password,
) async {
  await tester.enterText(_field('E-posta ya da kullanıcı adı'), user);
  await tester.enterText(_field('Şifre'), password);
  await tapVisible(tester, find.text('Giriş yap'));
  await pumpFor(tester, const Duration(seconds: 1));
}

void main() {
  testWidgets('ilk açılış: açılış → tanıtım → "Atla" → giriş', (tester) async {
    await _launch(tester, prefs: const {});
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.text('Sipariş birkaç dokunuşla'), findsOneWidget);
    await tester.tap(find.text('Atla'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Giriş yap'), findsOneWidget);
    // Demo hesapları ilk ekranda, üst alanın altında tek satırda (sahip kararı 2026-10-21).
    expect(find.text('Demo hesaplarıyla girin').hitTestable(), findsOneWidget);
    expect(find.text('Selin Aydın').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('demo kartı tek dokunuşla kabuğu açar (müşteri)', (tester) async {
    final c = await _launch(tester);
    await tapVisible(tester, find.text('Selin Aydın'));
    await pumpUntil(tester, () => isSignedIn(c));
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.byType(AnimatedBottomBar), findsOneWidget);
    expect(find.byType(CustomerHome), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('demo kartı: merkez tek dokunuşla (SMS kodu kendiliğinden)', (
    tester,
  ) async {
    final c = await _launch(tester);
    await tapVisible(tester, find.text('Merkez Operasyon'));
    await pumpUntil(tester, () => isSignedIn(c));
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.byType(CodePage), findsNothing);
    expect(find.byType(PlatformHome), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('demo kartı: şoför (Bayi satırının sonundan) kendi kabuğuna', (
    tester,
  ) async {
    final c = await _launch(tester);
    final row = find.ancestor(
      of: find.text('Mehmet Demir'),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Ahmet Kurt'),
      200,
      scrollable: row.first,
    );
    await tapVisible(tester, find.text('Ahmet Kurt'));
    await pumpUntil(tester, () => isSignedIn(c));
    await pumpFor(tester, const Duration(seconds: 2));
    expect(c.read(sessionControllerProvider).access!.userName, 'sofor');
    expect(find.byType(AnimatedBottomBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('giriş → 2FA → kabuk (merkez)', (tester) async {
    final c = await _launch(tester);
    await _typeLogin(tester, 'merkez', 'demo');
    expect(find.byType(CodePage), findsOneWidget);
    await tester.enterText(find.byType(Pinput), '123456');
    await pumpUntil(tester, () => isSignedIn(c));
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.byType(AnimatedBottomBar), findsOneWidget);
    expect(find.byType(PlatformHome), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('telefonla giriş → kabuk (müşteri)', (tester) async {
    final c = await _launch(tester);
    await tapVisible(tester, find.text('Numara ile'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.enterText(_field('Cep telefonu'), '0532 000 01 01');
    await tapVisible(tester, find.text('Kod gönder'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Kodu girin'), findsOneWidget);
    await tester.enterText(find.byType(Pinput), '123456');
    await pumpUntil(tester, () => isSignedIn(c));
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.byType(CustomerHome), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('zorunlu güncelleme: açılışta /update, giriş yok', (
    tester,
  ) async {
    final h = await TestHarness.create(prefs: {'akn.onboardingDone': true});
    h.server.get(
      'app/config',
      (req) => {
        ...fakeAppConfig(),
        'minBuild': 5,
        'storeUrl': 'https://store.test/akaryakitnet',
      },
      anonymous: true,
    );
    await _launch(tester, harness: h);
    expect(find.byType(UpdatePage), findsOneWidget);
    expect(find.text('Güncelleme gerekli'), findsOneWidget);
    expect(find.text('Mağazada aç'), findsOneWidget);
    expect(find.text('Giriş yap'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'eski API (app/config 404): "Sunucu güncel değil", düzelince giriş',
    (tester) async {
      final h = await TestHarness.create(prefs: {'akn.onboardingDone': true});
      final ctl = AuthFakeControls.of(h.server)..configMissing = true;
      await _launch(tester, harness: h);
      expect(find.text('Sunucu güncel değil'), findsOneWidget);
      ctl.configMissing = false;
      await tester.tap(find.text('Tekrar dene'));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.text('Giriş yap'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'kilit: iptal → "Şifreyle giriş yap" → giriş formu kullanıcı adıyla',
    (tester) async {
      final bio = FakeBiometric(outcomes: [BiometricOutcome.cancelled]);
      final c = await _launch(
        tester,
        prefs: {'akn.onboardingDone': true, PrefKeys.biometricLock: true},
        overrides: [biometricAuthenticatorProvider.overrideWithValue(bio)],
      );
      await signIn(tester, c, 'musteri');
      await pumpFor(tester, const Duration(seconds: 2));
      c.read(sessionControllerProvider.notifier).lock();
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.byType(LockedPage), findsOneWidget);
      expect(find.text('Doğrulama iptal edildi.'), findsOneWidget);

      await tester.tap(find.text('Şifreyle giriş yap'));
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.text('Giriş yap'), findsOneWidget);
      expect(
        find.text('Güvenliğiniz için şifrenizle giriş yapın.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(_field('E-posta ya da kullanıcı adı'))
            .controller!
            .text,
        'musteri',
      );
      expect(c.read(biometricLockProvider), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('kilit: başarılı doğrulama kabuğa döner', (tester) async {
    final bio = FakeBiometric();
    final c = await _launch(
      tester,
      prefs: {'akn.onboardingDone': true, PrefKeys.biometricLock: true},
      overrides: [biometricAuthenticatorProvider.overrideWithValue(bio)],
    );
    await signIn(tester, c, 'musteri');
    await pumpFor(tester, const Duration(seconds: 2));
    c.read(sessionControllerProvider.notifier).lock();
    await pumpFor(tester, const Duration(seconds: 2));
    expect(bio.calls, 1);
    expect(find.byType(LockedPage), findsNothing);
    expect(find.byType(CustomerHome), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'ikinci girişte biyometrik kilit önerisi (bildirim ön sayfası yokken)',
    (tester) async {
      final bio = FakeBiometric();
      final c = await _launch(
        tester,
        prefs: {'akn.onboardingDone': true, AuthPrefKeys.loginCount: 1},
        overrides: [biometricAuthenticatorProvider.overrideWithValue(bio)],
      );
      await _typeLogin(tester, 'musteri', 'demo');
      await pumpUntil(tester, () => isSignedIn(c));
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.text('Daha hızlı ve güvenli açılış'), findsOneWidget);
      await tester.tap(find.textContaining('tanıma kullan'));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(bio.calls, 1);
      expect(c.read(biometricLockProvider), isTrue);
      await pumpFor(tester, const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
