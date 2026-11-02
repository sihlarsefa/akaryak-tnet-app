// A1 sahte uçları gerçek istemci yığınıyla (Dio + ara katmanlar + sahte adaptör): kilitlenme, kod yeniden
// gönderimi, OTP sınırı, telefonla girişin hedefi (ayrı telefon doğrulaması yok, 2026-11: hesapta kayıtlı
// numara; merkez, demo / tohum, pasif ve paylaşılan numara hariç) ve app/config anahtarları.
import 'package:akaryakitnet/core/auth/auth_repository.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/network/fake/fake_phones.dart';
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
    'telefon doğrulama uçları yok (2026-11): me/phone/verify-start ve me/phone/verify → 404',
    () async {
      for (final path in const ['me/phone/verify-start', 'me/phone/verify']) {
        final r = await h.server.handle(
          method: 'POST',
          path: path,
          uri: Uri.parse('http://fake.test/$path'),
          body: const <String, Object?>{},
        );
        expect(r.status, 404, reason: path);
      }
    },
  );

  test(
    'telefonla giriş: doğrulama yapılmamış personanın hesabındaki numarasına kod gider; '
    'me/access.phoneVerified = numara kayıtlı',
    () async {
      final ch = await session().sendOtp('0532 000 02 06');
      expect(ch.maskedPhone, '0532 *** ** 06');
      expect(ctl.otpSmsTo, ['saha']);
      final out = await session().verifyCode(ch.challengeId, '123456');
      expect((out as LoginSucceeded).access.userName, 'saha');
      expect(out.access.phoneVerified, isTrue);
      expect(out.access.phoneMasked, '0532 *** ** 06');

      // Numara hesaptan silinince: phoneVerified false, maske yok.
      FakePhones.edits(h.server.world)['saha'] = {
        'displayName': 'Deniz Koç',
        'phoneNumber': null,
      };
      final access = await c.read(authRepositoryProvider).meAccess();
      expect(access.phoneVerified, isFalse);
      expect(access.phoneMasked, isNull);
    },
  );

  test(
    'merkez, demo / tohum ve pasif hesaba SMS gitmez (yanıt aynı: kod gönderildi)',
    () async {
      FakePhones.seedAccounts(h.server.world).add('sofor');
      for (final (phone, who) in const [
        ('905320000301', 'merkez'),
        ('905320000209', 'demo / tohum hesabı (sofor)'),
        ('905320000102', 'pasif (talep)'),
        ('905320000202', 'pasif (mudur)'),
      ]) {
        final ch = await session().sendOtp(phone);
        expect(ch.challengeId, isNotEmpty, reason: who);
        expect(ch.maskedPhone, contains('***'), reason: who);
        expect(ch.expiresInSeconds, 300, reason: who);
        await expectLater(
          session().verifyCode(ch.challengeId, '123456'),
          throwsA(isA<BusinessFailure>()),
          reason: who,
        );
      }
      expect(ctl.otpSmsTo, isEmpty);
      expect(ctl.otpSends, 4);
      // Yalnızca işaretlenen hesap demo / tohum sayılır; diğer etkin personalar uygundur.
      expect(
        FakePhones.eligible(h.server.world, findFakePersona('musteri')!),
        isTrue,
      );
    },
  );

  test(
    'aynı numara iki uygun hesapta: SMS gitmez; biri uygun değilse kod uygun olana gider',
    () async {
      final edits = FakePhones.edits(h.server.world);
      edits['saha'] = {
        'displayName': 'Deniz Koç',
        'phoneNumber': '0532 000 01 01',
      };
      final shared = await session().sendOtp('905320000101');
      expect(shared.maskedPhone, '0532 *** ** 01');
      expect(ctl.otpSmsTo, isEmpty);
      await expectLater(
        session().verifyCode(shared.challengeId, '123456'),
        throwsA(isA<BusinessFailure>()),
      );

      // Numarayı paylaşan pasif hesap (talep) sayılmaz.
      edits
        ..remove('saha')
        ..['talep'] = {
          'displayName': 'Burak Yılmaz',
          'phoneNumber': '0532 000 01 01',
        };
      final single = await session().sendOtp('905320000101');
      expect(ctl.otpSmsTo, ['musteri']);
      final out = await session().verifyCode(single.challengeId, '123456');
      expect((out as LoginSucceeded).access.userName, 'musteri');
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
