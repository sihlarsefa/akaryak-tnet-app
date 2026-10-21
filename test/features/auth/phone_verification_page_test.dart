// Telefon doğrulama (`/profile/phone`, spec A.4 A1): kod gönder → doğrula → "Telefonunuz doğrulandı";
// yeniden gönderim auth/challenge/resend ile; merkez hesabı için açıklama; erişilebilirlik matrisi.
import 'dart:async';

import 'package:akaryakitnet/features/auth/api.dart';
import 'package:akaryakitnet/features/auth/auth_fake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';

import 'auth_test_support.dart';

Future<ProviderContainer> _openPhonePage(
  WidgetTester tester, {
  String persona = 'musteri',
  AuthHarness? harness,
  List<Override> overrides = const [],
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  final c = await pumpAuthRoute(
    tester,
    '/home',
    harness: harness,
    overrides: overrides,
    textScale: textScale,
    brightness: brightness,
  );
  await signIn(tester, c, persona);
  unawaited(
    GoRouter.of(tester.element(find.text('ANA SAYFA'))).push(AuthRoutes.phone),
  );
  await pumpFor(tester, const Duration(milliseconds: 800));
  return c;
}

void main() {
  a11yMatrix('telefon doğrulama (giriş)', (tester, scale, b) async {
    await _openPhonePage(tester, textScale: scale, brightness: b);
    expect(find.text('Telefonla giriş'), findsOneWidget);
    expect(find.text('Doğrulanmadı'), findsOneWidget);
    expect(find.text('Doğrulama kodu gönder'), findsOneWidget);
  });

  a11yMatrix('telefon doğrulama (kod adımı)', (tester, scale, b) async {
    await _openPhonePage(tester, textScale: scale, brightness: b);
    await tapVisible(tester, find.text('Doğrulama kodu gönder'));
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(find.byType(Pinput), findsOneWidget);
  });

  testWidgets('kod gönder → hatalı kod → doğru kod → doğrulandı', (
    tester,
  ) async {
    setPhoneSize(tester);
    final h = await AuthHarness.create();
    final ctl = AuthFakeControls.of(h.server);
    await _openPhonePage(tester, harness: h);
    await tapVisible(tester, find.text('Doğrulama kodu gönder'));
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(ctl.phoneVerifyStarts, 1);
    expect(find.textContaining('0532 *** ** 01'), findsOneWidget);

    await tester.enterText(find.byType(Pinput), '000000');
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Kod hatalı. Tekrar deneyin.'), findsOneWidget);

    await tester.enterText(find.byType(Pinput), '123456');
    await pumpFor(tester, const Duration(milliseconds: 900));
    expect(find.text('Telefonunuz doğrulandı'), findsOneWidget);
    expect(ctl.verifiedPhones, contains('musteri'));

    await tester.tap(find.text('Tamam'));
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(find.text('ANA SAYFA'), findsOneWidget);

    // Yeniden açınca doğrulandı görünür.
    unawaited(
      GoRouter.of(
        tester.element(find.text('ANA SAYFA')),
      ).push(AuthRoutes.phone),
    );
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(find.text('Doğrulandı'), findsOneWidget);
    expect(find.text('Yeniden doğrula'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('yeniden gönderim auth/challenge/resend ile', (tester) async {
    setPhoneSize(tester);
    final clock = TestClock();
    final h = await AuthHarness.create();
    final ctl = AuthFakeControls.of(h.server)..now = clock.call;
    await _openPhonePage(
      tester,
      harness: h,
      overrides: clockAndLinks(clock: clock),
    );
    await tapVisible(tester, find.text('Doğrulama kodu gönder'));
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(find.text('Kodu tekrar gönder (1:00)'), findsOneWidget);
    clock.advance(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 1));
    await tapVisible(tester, find.text('Kodu tekrar gönder'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(ctl.resends, 1);
    expect(ctl.phoneVerifyStarts, 1);
    await tester.enterText(find.byType(Pinput), '123456');
    await pumpFor(tester, const Duration(milliseconds: 900));
    expect(find.text('Telefonunuz doğrulandı'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'merkez hesabı: telefonla giriş yok açıklaması, gönder düğmesi yok',
    (tester) async {
      setPhoneSize(tester);
      await _openPhonePage(tester, persona: 'merkez');
      expect(
        find.textContaining('Merkez hesapları telefonla giriş yapamaz'),
        findsOneWidget,
      );
      expect(find.text('Doğrulama kodu gönder'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
