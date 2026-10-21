// Kod ekranı (spec A.4 A1): 6 kutu, hatalı kod, doğru kodla oturum; 2FA yeniden gönderimi
// auth/challenge/resend, OTP yeniden gönderimi auth/otp/send ile ve geri sayımlı; kodun geçerlilik süresi;
// erişilebilirlik matrisi. Uygulamanın tamamıyla akış: auth_flow_test.dart.
import 'package:akaryakitnet/core/models/auth_models.dart';
import 'package:akaryakitnet/core/network/fake/fake_auth.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/features/auth/presentation/code_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinput/pinput.dart';

import 'auth_test_support.dart';

const _sample = OtpChallenge(
  challengeId: 'c-test',
  maskedPhone: '0532 *** ** 01',
  expiresInSeconds: 300,
  resendInSeconds: 60,
);

/// Sahte sunucuda gerçek bir sorgu açar (persona + amaç).
OtpChallenge _challengeFor(AuthHarness h, String persona, int purpose) {
  final p = findFakePersona(persona)!;
  final FakeChallenge c = h.server.auth.createChallenge(
    p,
    purpose: purpose,
    deviceId: 'test-device',
  );
  return OtpChallenge(
    challengeId: c.id,
    maskedPhone: p.phoneMasked,
    expiresInSeconds: 300,
    resendInSeconds: 60,
  );
}

Future<void> _typeCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(Pinput), code);
  await tester.pump();
}

void main() {
  a11yMatrix('kod ekranı (2FA)', (tester, scale, b) async {
    await pumpAuthRoute(
      tester,
      '/login/code',
      textScale: scale,
      brightness: b,
      extra: const CodePageArgs(
        challenge: _sample,
        purpose: CodePurpose.twoFactor,
      ),
    );
    expect(find.text('Kodu girin'), findsOneWidget);
    // Amaç görünür başlık değil, ekran okuyucu etiketi (beyaz sayfa: logo + "Kodu girin").
    expect(find.bySemanticsLabel('Doğrulama kodu'), findsOneWidget);
    expect(find.byType(Pinput), findsOneWidget);
    expect(find.textContaining('Kodu tekrar gönder'), findsOneWidget);
  });

  a11yMatrix('kod ekranı (hatalı kod)', (tester, scale, b) async {
    final h = await AuthHarness.create();
    await pumpAuthRoute(
      tester,
      '/login/code',
      harness: h,
      textScale: scale,
      brightness: b,
      extra: CodePageArgs(
        challenge: _challengeFor(h, 'merkez', 1),
        purpose: CodePurpose.twoFactor,
      ),
    );
    await _typeCode(tester, '000000');
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(find.text('Kod hatalı. Tekrar deneyin.'), findsOneWidget);
  });

  a11yMatrix('kod ekranı (eksik sorgu)', (tester, scale, b) async {
    await pumpAuthRoute(tester, '/login/code', textScale: scale, brightness: b);
    expect(find.text('Kod isteği bulunamadı'), findsOneWidget);
    expect(find.text('Girişe dön'), findsOneWidget);
  });

  testWidgets('2FA: hatalı kod oturum açmaz, doğru kod açar', (tester) async {
    setPhoneSize(tester);
    final h = await AuthHarness.create();
    final c = await pumpAuthRoute(
      tester,
      '/login/code',
      harness: h,
      extra: CodePageArgs(
        challenge: _challengeFor(h, 'merkez', 1),
        purpose: CodePurpose.twoFactor,
      ),
    );
    expect(find.textContaining('0532 *** ** 01'), findsOneWidget);
    await _typeCode(tester, '000000');
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(isSignedIn(c), isFalse);
    expect(
      tester.widget<Pinput>(find.byType(Pinput)).controller!.text,
      isEmpty,
      reason: 'hatalı kod silinir',
    );
    await _typeCode(tester, FakeAuth.code);
    await pumpUntil(tester, () => isSignedIn(c));
    expect(isSignedIn(c), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    '2FA yeniden gönderim: 60 sn sayar, sonra auth/challenge/resend',
    (tester) async {
      setPhoneSize(tester);
      final clock = TestClock();
      final h = await AuthHarness.create();
      h.controls.now = clock.call;
      final c = await pumpAuthRoute(
        tester,
        '/login/code',
        harness: h,
        overrides: clockAndLinks(clock: clock),
        extra: CodePageArgs(
          challenge: _challengeFor(h, 'merkez', 1),
          purpose: CodePurpose.twoFactor,
        ),
      );
      expect(find.text('Kodu tekrar gönder (1:00)'), findsOneWidget);
      await tester.tap(find.text('Kodu tekrar gönder (1:00)'));
      await tester.pump();
      expect(h.controls.resends, 0, reason: 'sayarken dokunulmaz');

      clock.advance(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Kodu tekrar gönder (30 sn)'), findsOneWidget);

      clock.advance(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Kodu tekrar gönder'), findsOneWidget);
      await tester.tap(find.text('Kodu tekrar gönder'));
      await pumpFor(tester, const Duration(milliseconds: 400));
      expect(h.controls.resends, 1);
      expect(h.controls.otpSends, 0);
      expect(find.text('Kodu tekrar gönder (1:00)'), findsOneWidget);

      await _typeCode(tester, FakeAuth.code);
      await pumpUntil(tester, () => isSignedIn(c));
      expect(isSignedIn(c), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'telefonla giriş: yeniden gönderim auth/otp/send ile (yeni sorgu)',
    (tester) async {
      setPhoneSize(tester);
      final clock = TestClock();
      final h = await AuthHarness.create();
      h.controls.now = clock.call;
      final c = await pumpAuthRoute(
        tester,
        '/login/code',
        harness: h,
        overrides: clockAndLinks(clock: clock),
        extra: CodePageArgs(
          challenge: _challengeFor(h, 'musteri', 2),
          purpose: CodePurpose.otpLogin,
          phone: '905320000101',
        ),
      );
      expect(find.byType(CodePage), findsOneWidget);
      clock.advance(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Kodu tekrar gönder'));
      await pumpFor(tester, const Duration(milliseconds: 400));
      expect(h.controls.otpSends, 1);
      expect(h.controls.resends, 0);

      await _typeCode(tester, FakeAuth.code);
      await pumpUntil(tester, () => isSignedIn(c));
      expect(isSignedIn(c), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('yeniden gönderim 429: kalan süre sunucudan', (tester) async {
    setPhoneSize(tester);
    final clock = TestClock();
    final h = await AuthHarness.create();
    h.controls
      ..now = clock.call
      ..otpSendsPerWindow = 0;
    await pumpAuthRoute(
      tester,
      '/login/code',
      harness: h,
      overrides: clockAndLinks(clock: clock),
      extra: CodePageArgs(
        challenge: _challengeFor(h, 'musteri', 2),
        purpose: CodePurpose.otpLogin,
        phone: '905320000101',
      ),
    );
    clock.advance(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Kodu tekrar gönder'));
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(find.textContaining('çok fazla kod istendi'), findsOneWidget);
    expect(find.text('Kodu tekrar gönder (10:00)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('kodun geçerlilik süresi dolunca uyarı', (tester) async {
    setPhoneSize(tester);
    final clock = TestClock();
    await pumpAuthRoute(
      tester,
      '/login/code',
      overrides: clockAndLinks(clock: clock),
      extra: const CodePageArgs(
        challenge: _sample,
        purpose: CodePurpose.twoFactor,
      ),
    );
    expect(find.text('Kod 5:00 geçerli.'), findsOneWidget);
    clock.advance(const Duration(minutes: 5, seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Kodun süresi doldu. Yeni kod isteyin.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
