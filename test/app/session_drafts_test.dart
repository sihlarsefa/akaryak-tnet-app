// İstem dışı çıkış (spec C.4a, D.7): oturum süresi dolunca, kilit ekranından şifreyle girişe geçince ya
// da şifre değişince kullanıcının yarım işleri (teslim taslakları, sipariş sihirbazı ve bekleyen gönderim
// anahtarı, saha taslakları) silinmez; belirteçler, yetkiler, önbellek ve diğer tercihler silinir. Aynı
// kullanıcı girince kaldığı yerden sürer; başka kullanıcı girerse ya da "Çıkış yap" denirse silinir.
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_events.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/offline/cache_store.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/storage/user_drafts.dart';
import 'package:akaryakitnet/features/customer_orders/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

const _user = 'u-musteri';

/// Teslim taslağı (tercih), sihirbaz taslağı + bekleyen anahtar ve saha taslağı (önbellek), sıradan bir
/// tercih ve önbellek kaydı yazar.
Future<void> _writeUserData(ProviderContainer c) async {
  final prefs = c.read(prefsStoreProvider);
  final cache = c.read(cacheStoreProvider);
  await prefs.setString(
    PrefKeys.user(_user, UserDrafts.deliverDrafts),
    '{"5003":{"shipmentId":5003}}',
  );
  await prefs.setInt(A2Keys.lastPoint(_user), 1001);
  await cache.write(A2Keys.wizard(_user), {
    'draft': {'lines': []},
    'pending': {'key': 'k-1'},
  }, userId: _user);
  await cache.write(
    CacheKeys.user(_user, '${UserDrafts.fieldWizardPrefix}form.new'),
    {'step': 2},
    userId: _user,
  );
  await cache.write(A2Keys.home(_user), {'x': 1}, userId: _user);
}

Future<({bool deliver, bool wizard, bool field, bool lastPoint, bool home})>
_present(ProviderContainer c) async {
  final prefs = c.read(prefsStoreProvider);
  final cache = c.read(cacheStoreProvider);
  return (
    deliver:
        prefs.getString(PrefKeys.user(_user, UserDrafts.deliverDrafts)) != null,
    wizard: await cache.read(A2Keys.wizard(_user)) != null,
    field:
        await cache.read(
          CacheKeys.user(_user, '${UserDrafts.fieldWizardPrefix}form.new'),
        ) !=
        null,
    lastPoint: prefs.getInt(A2Keys.lastPoint(_user)) != null,
    home: await cache.read(A2Keys.home(_user)) != null,
  );
}

Future<ProviderContainer> _signedIn(
  TestHarness h, {
  String persona = 'musteri',
}) async {
  final c = h.container();
  addTearDown(c.dispose);
  final s = c.read(sessionControllerProvider.notifier);
  await s.restore();
  await s.loginWithPassword(persona, 'demo');
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final reason in [
    SignOutReason.lockFallback,
    SignOutReason.expired,
    SignOutReason.securityChanged,
  ]) {
    test(
      '${reason.name}: yarım işler kalır, diğer veri gider; aynı kullanıcı sürdürür',
      () async {
        final h = await TestHarness.create();
        final c = await _signedIn(h);
        await _writeUserData(c);
        await c
            .read(sessionControllerProvider.notifier)
            .signOut(reason: reason, callServer: false);
        await pumpEventQueue();
        expect(
          c.read(sessionControllerProvider),
          isA<SessionUnauthenticated>(),
        );
        expect(c.read(tokenStoreProvider).hasRefreshToken, isFalse);
        final kept = await _present(c);
        expect(kept.deliver, isTrue, reason: 'teslim taslağı');
        expect(kept.wizard, isTrue, reason: 'sihirbaz + bekleyen anahtar');
        expect(kept.field, isTrue, reason: 'saha taslağı');
        expect(kept.lastPoint, isFalse, reason: 'sıradan tercih silinir');
        expect(kept.home, isFalse, reason: 'ekran önbelleği silinir');
        expect(
          await c
              .read(cacheStoreProvider)
              .read(CacheKeys.user(_user, CacheKeys.meAccess)),
          isNull,
          reason: 'yetkiler silinir',
        );
        expect(
          c.read(prefsStoreProvider).getString(PrefKeys.draftsOwner),
          _user,
        );

        await c
            .read(sessionControllerProvider.notifier)
            .loginWithPassword('musteri', 'demo');
        final resumed = await _present(c);
        expect(resumed.deliver && resumed.wizard && resumed.field, isTrue);
        expect(
          c.read(prefsStoreProvider).getString(PrefKeys.draftsOwner),
          isNull,
        );
      },
    );
  }

  test(
    'oturum süresi doldu (sunucu): taslaklar kalır; başka kullanıcı girince silinir',
    () async {
      final h = await TestHarness.create();
      final c = await _signedIn(h);
      await _writeUserData(c);
      c
          .read(sessionEventsProvider)
          .emit(const SessionExpiredEvent('token_expired'));
      for (
        var i = 0;
        i < 100 && c.read(sessionControllerProvider) is! SessionUnauthenticated;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await pumpEventQueue();
      expect(c.read(sessionControllerProvider), isA<SessionUnauthenticated>());
      expect((await _present(c)).wizard, isTrue);

      await c
          .read(sessionControllerProvider.notifier)
          .loginWithPassword('onay', 'demo');
      final after = await _present(c);
      expect(after.deliver, isFalse);
      expect(after.wizard, isFalse);
      expect(after.field, isFalse);
      expect(
        c.read(prefsStoreProvider).getString(PrefKeys.draftsOwner),
        isNull,
      );
    },
  );

  test('"Çıkış yap": yarım işler dahil her şey silinir', () async {
    final h = await TestHarness.create();
    final c = await _signedIn(h);
    await _writeUserData(c);
    await c.read(sessionControllerProvider.notifier).signOut(callServer: false);
    await pumpEventQueue();
    final gone = await _present(c);
    expect(
      gone.deliver || gone.wizard || gone.field || gone.lastPoint || gone.home,
      isFalse,
    );
    expect(c.read(prefsStoreProvider).getString(PrefKeys.draftsOwner), isNull);
  });
}
