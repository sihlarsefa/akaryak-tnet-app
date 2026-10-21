import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/models/me_access.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/offline/cache_store.dart';
import 'package:akaryakitnet/core/push/unread_count_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

/// Olay döngüsünü [condition] sağlanana kadar çalıştırır (en fazla ~1 sn).
Future<void> settle(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late TestHarness h;
  late MemoryCacheStore cache;

  setUp(() async {
    h = await TestHarness.create(prefs: {'akn.onboardingDone': true});
    cache = MemoryCacheStore();
  });

  ProviderContainer container() {
    final c = h.container(extra: [cacheStoreProvider.overrideWithValue(cache)]);
    addTearDown(c.dispose);
    return c;
  }

  test('şifreyle giriş → yetkiler önbelleğe yazılır', () async {
    final c = container();
    final session = c.read(sessionControllerProvider.notifier);
    await session.restore();
    expect(c.read(sessionControllerProvider), isA<SessionUnauthenticated>());

    final outcome = await session.loginWithPassword('musteri', 'demo');
    expect(outcome, isA<LoginSucceeded>());
    final state = c.read(sessionControllerProvider);
    expect(state, isA<SessionAuthenticated>());
    expect(state.access!.persona, Persona.customer);
    expect(state.access!.customerTitle, 'Anadolu Lojistik A.Ş.');
    expect(c.read(accessPolicyProvider).isCustomer, isTrue);
    expect(h.secure.values['akn.refresh'], isNotEmpty);
    expect(h.secure.values['akn.userId'], 'u-musteri');
    expect(
      (await cache.read(
        CacheKeys.user('u-musteri', CacheKeys.meAccess),
      ))?.value,
      isNotNull,
    );
  });

  test('hatalı şifre: kullanıcıya Türkçe mesaj, oturum açılmaz', () async {
    final c = container();
    await c.read(sessionControllerProvider.notifier).restore();
    await expectLater(
      c
          .read(sessionControllerProvider.notifier)
          .loginWithPassword('musteri', 'yanlis'),
      throwsA(
        isA<UnauthorizedFailure>().having(
          (f) => f.message,
          'message',
          'Kullanıcı adı veya şifre hatalı.',
        ),
      ),
    );
    expect(c.read(sessionControllerProvider), isA<SessionUnauthenticated>());
    expect(h.secure.values['akn.refresh'], isNull);
  });

  test('merkez: şifre + SMS kodu (2FA)', () async {
    final c = container();
    final session = c.read(sessionControllerProvider.notifier);
    final first = await session.loginWithPassword('merkez', 'demo');
    expect(first, isA<LoginNeedsCode>());
    final challenge = (first as LoginNeedsCode).challenge;
    expect(challenge.maskedPhone, contains('***'));
    await expectLater(
      session.verifyCode(challenge.challengeId, '000000'),
      throwsA(isA<BusinessFailure>()),
    );
    final second = await session.verifyCode(challenge.challengeId, '123456');
    expect(second, isA<LoginSucceeded>());
    expect(c.read(accessPolicyProvider).isPlatform, isTrue);
  });

  test('telefonla giriş (OTP)', () async {
    final c = container();
    final session = c.read(sessionControllerProvider.notifier);
    final ch = await session.sendOtp('0532 000 02 09');
    expect(ch.resendInSeconds, 60);
    final out = await session.verifyCode(ch.challengeId, '123456');
    expect((out as LoginSucceeded).access.userName, 'sofor');
  });

  test(
    'bilinmeyen telefon: aynı yanıt, kod çalışmaz (numara ifşa edilmez)',
    () async {
      final c = container();
      final session = c.read(sessionControllerProvider.notifier);
      final ch = await session.sendOtp('0555 999 99 99');
      expect(ch.maskedPhone, '0555 *** ** 99');
      await expectLater(
        session.verifyCode(ch.challengeId, '123456'),
        throwsA(isA<BusinessFailure>()),
      );
    },
  );

  test('çevrimdışı açılış: önbellekteki yetkilerle açılır', () async {
    final first = container();
    await first
        .read(sessionControllerProvider.notifier)
        .loginWithPassword('sofor', 'demo');
    first.dispose();

    h.server.failureMode = FakeFailureMode.offline;
    final second = container();
    await second.read(sessionControllerProvider.notifier).restore();
    final state = second.read(sessionControllerProvider);
    expect(state, isA<SessionAuthenticated>());
    expect((state as SessionAuthenticated).fromCache, isTrue);
    expect(second.read(accessPolicyProvider).isDriverOnly, isTrue);
    await settle(
      () => false,
    ); // arka plan yenilemesi çevrimdışı hatasıyla biter; oturum korunur
    expect(second.read(sessionControllerProvider), isA<SessionAuthenticated>());
  });

  test(
    'sunucuda oturum kapatıldıysa açılışta "Oturumunuz sona erdi"',
    () async {
      final first = container();
      await first
          .read(sessionControllerProvider.notifier)
          .loginWithPassword('sahip', 'demo');
      first.dispose();
      h.server.auth.revokeAll('sahip');

      final second = container();
      await second.read(sessionControllerProvider.notifier).restore();
      await settle(
        () => second.read(sessionControllerProvider) is SessionUnauthenticated,
      );
      final state = second.read(sessionControllerProvider);
      expect(state, isA<SessionUnauthenticated>());
      expect(
        (state as SessionUnauthenticated).message,
        SessionController.sessionExpiredMessage,
      );
      expect(h.secure.values['akn.refresh'], isNull);
      expect(
        await cache.read(CacheKeys.user('u-sahip', CacheKeys.meAccess)),
        isNull,
        reason: 'kullanıcı önbelleği silinir',
      );
    },
  );

  test('erişim belirteci dolunca istek yenilenip sürer', () async {
    final c = container();
    await c
        .read(sessionControllerProvider.notifier)
        .loginWithPassword('finans', 'demo');
    final before = h.server.auth.refreshCalls;
    h.server.auth.expireAllAccessTokens();
    c.read(tokenStoreProvider).expireAccess();
    final access = await c
        .read(apiClientProvider)
        .get('me/access', parse: MeAccess.fromJson);
    expect(access.userName, 'finans');
    expect(h.server.auth.refreshCalls, before + 1);
  });

  test(
    'çıkış: belirteçler ve kullanıcı önbelleği silinir; rozetler sıfırlanır',
    () async {
      final c = container();
      await c
          .read(sessionControllerProvider.notifier)
          .loginWithPassword('finans', 'demo');
      await c.read(unreadCountProvider.notifier).refresh();
      expect(c.read(unreadCountProvider).approvals, greaterThan(0));
      expect(c.read(unreadCountProvider).notifications, greaterThan(0));

      await c.read(sessionControllerProvider.notifier).signOut();
      expect(c.read(sessionControllerProvider), isA<SessionUnauthenticated>());
      expect(h.secure.values.containsKey('akn.refresh'), isFalse);
      expect(
        await cache.read(CacheKeys.user('u-finans', CacheKeys.meAccess)),
        isNull,
      );
      await settle(() => c.read(unreadCountProvider).notifications == 0);
      expect(c.read(unreadCountProvider).approvals, 0);
    },
  );

  test(
    'kilit: biyometrik kilit açıksa açılışta kilitli, unlock ile açılır',
    () async {
      h = await TestHarness.create(
        prefs: {'akn.onboardingDone': true, 'akn.biometricLock': true},
      );
      final first = container();
      await first
          .read(sessionControllerProvider.notifier)
          .loginWithPassword('mudur', 'demo');
      first.dispose();
      final second = container();
      await second.read(sessionControllerProvider.notifier).restore();
      expect(second.read(sessionControllerProvider), isA<SessionLocked>());
      second.read(sessionControllerProvider.notifier).unlock();
      expect(
        second.read(sessionControllerProvider),
        isA<SessionAuthenticated>(),
      );
    },
  );
}
