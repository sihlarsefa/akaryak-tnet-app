// A1 sahte uçları gerçek istemci yığınıyla (Dio + ara katmanlar + sahte adaptör): kilitlenme, kod yeniden
// gönderimi, OTP sınırı, telefon doğrulama ve app/config anahtarları.
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/features/auth/application/server_gate_controller.dart';
import 'package:akaryakitnet/features/auth/auth_fake.dart';
import 'package:akaryakitnet/features/auth/data/auth_api.dart';
import 'package:akaryakitnet/features/auth/data/server_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_test_support.dart';

void main() {
  late AuthHarness h;
  late ProviderContainer c;
  late TestClock clock;
  late AuthFakeControls ctl;

  setUp(() async {
    h = await AuthHarness.create();
    c = h.container();
    addTearDown(c.dispose);
    clock = TestClock();
    ctl = AuthFakeControls.of(h.server)..now = clock.call;
    await c.read(sessionControllerProvider.notifier).restore();
  });

  SessionController session() => c.read(sessionControllerProvider.notifier);

  test(
    '5 hatalı şifre: 429 + Retry-After; süre dolunca doğru şifre girer',
    () async {
      for (var i = 0; i < 4; i++) {
        await expectLater(
          session().loginWithPassword('musteri', 'yanlis'),
          throwsA(isA<UnauthorizedFailure>()),
        );
      }
      final locked = await session()
          .loginWithPassword('musteri', 'yanlis')
          .then<AppFailure?>(
            (_) => null,
            onError: (Object e) => e as AppFailure,
          );
      expect(locked, isA<RateLimitedFailure>());
      final r = locked! as RateLimitedFailure;
      expect(r.retryAfter, const Duration(minutes: 15));
      expect(r.message, contains('15 dakika kapatıldı'));

      // Kilitliyken doğru şifre de beklemeye takılır.
      await expectLater(
        session().loginWithPassword('musteri', 'demo'),
        throwsA(isA<RateLimitedFailure>()),
      );
      clock.advance(const Duration(minutes: 15, seconds: 1));
      final ok = await session().loginWithPassword('musteri', 'demo');
      expect(ok, isA<LoginSucceeded>());
    },
  );

  test(
    '2FA yeniden gönderim: 60 sn bekleme, sonra yeni kod; eski kod geçersiz',
    () async {
      final first = await session().loginWithPassword('merkez', 'demo');
      expect(first, isA<LoginNeedsCode>());
      final challenge = (first as LoginNeedsCode).challenge;
      expect(challenge.resendInSeconds, 60);

      final api = c.read(authApiProvider);
      final early = await api
          .resendChallenge(challenge.challengeId)
          .then<AppFailure?>(
            (_) => null,
            onError: (Object e) => e as AppFailure,
          );
      expect(early, isA<RateLimitedFailure>());
      expect(
        (early! as RateLimitedFailure).retryAfter,
        const Duration(seconds: 60),
      );

      clock.advance(const Duration(seconds: 61));
      final next = await api.resendChallenge(challenge.challengeId);
      expect(next.challengeId, isNot(challenge.challengeId));
      expect(next.maskedPhone, challenge.maskedPhone);
      expect(ctl.resends, 1);

      await expectLater(
        session().verifyCode(challenge.challengeId, '123456'),
        throwsA(isA<BusinessFailure>()),
      );
      final done = await session().verifyCode(next.challengeId, '123456');
      expect(done, isA<LoginSucceeded>());
      expect(c.read(sessionControllerProvider), isA<SessionAuthenticated>());
    },
  );

  test('telefonla giriş: numara başına 10 dakikada 3 kod', () async {
    for (var i = 0; i < 3; i++) {
      await session().sendOtp('905320000101');
    }
    final fourth = await session()
        .sendOtp('905320000101')
        .then<AppFailure?>((_) => null, onError: (Object e) => e as AppFailure);
    expect(fourth, isA<RateLimitedFailure>());
    expect(fourth!.message, contains('çok fazla kod'));
    // Başka numara etkilenmez.
    final other = await session().sendOtp('905320000102');
    expect(other.challengeId, isNotEmpty);
    clock.advance(const Duration(minutes: 10));
    final again = await session().sendOtp('905320000101');
    final verified = await session().verifyCode(again.challengeId, '123456');
    expect(verified, isA<LoginSucceeded>());
  });

  test(
    'telefon doğrulama: kod hatalıysa iş kuralı, doğruysa doğrulanır',
    () async {
      await session().loginWithPassword('musteri', 'demo');
      final api = c.read(authApiProvider);
      expect((await api.phoneStatus()).verified, isFalse);
      expect((await api.phoneStatus()).phoneMasked, isNotNull);

      final ch = await api.startPhoneVerification();
      expect(ch.maskedPhone, contains('***'));
      await expectLater(
        api.verifyPhone(ch.challengeId, '000000'),
        throwsA(isA<BusinessFailure>()),
      );
      await api.verifyPhone(ch.challengeId, '123456');
      expect((await api.phoneStatus()).verified, isTrue);
      expect(ctl.verifiedPhones, contains('musteri'));
    },
  );

  test('app/config: bakım, sözleşme farkı ve eski API (404)', () async {
    final keep = c.listen(serverGateProvider, (_, _) {});
    addTearDown(keep.close);
    expect((await c.read(serverGateProvider.future)).kind, ServerGateKind.ok);

    ctl.maintenance = true;
    ctl.maintenanceMessage = 'Gece bakımı 02:00–03:00.';
    c.invalidate(serverGateProvider);
    final m = await c.read(serverGateProvider.future);
    expect(m.kind, ServerGateKind.maintenance);
    expect(m.maintenanceMessage, 'Gece bakımı 02:00–03:00.');

    ctl
      ..maintenance = false
      ..contractVersion = 'mobile-v2';
    c.invalidate(serverGateProvider);
    expect(
      (await c.read(serverGateProvider.future)).kind,
      ServerGateKind.outdated,
    );

    ctl
      ..contractVersion = 'mobile-v1'
      ..configMissing = true;
    await expectLater(
      c.read(authApiProvider).appConfig(),
      throwsA(isA<NotFoundFailure>()),
    );
    c.invalidate(serverGateProvider);
    expect(
      (await c.read(serverGateProvider.future)).kind,
      ServerGateKind.outdated,
    );
  });
}
