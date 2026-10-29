// Test derlemesinin demo oturumu (sahip kararı: giriş ekranında demo hesapları; TestFlight derlemesi
// aynı zamanda canlı API ile giriş): derleme kararı (canlıda sahte sunucu ve demo yok), demo oturumunun
// etkin ortamı, belirtecin demo olarak yazılması, uygulamanın yeniden açılışında demo belirtecinin canlı
// API'ye hiç gitmemesi ve canlı yığının korumaları. Canlı API kayıtçı bir adaptördür (ağ yok).
import 'dart:convert';
import 'dart:io';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/auth/token_store.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/models/auth_models.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/network/fake/fake_api_adapter.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/offline/cache_store.dart';
import 'package:akaryakitnet/core/offline/outbox_providers.dart';
import 'package:akaryakitnet/core/storage/secure_store.dart';
import 'package:akaryakitnet/features/auth/presentation/widgets/demo_accounts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/demo_live_harness.dart';
import '../support/test_app.dart';

/// `env/<ad>.json` derleme tanımlarıyla (dart-define) kurulan ortam.
AppEnv _envFile(String name, {bool fakeCompiled = true}) {
  final defines =
      jsonDecode(File('env/$name.json').readAsStringSync())
          as Map<String, dynamic>;
  return AppEnv.fromDefines(
    aknEnv: '${defines['AKN_ENV']}',
    apiMode: '${defines['API_MODE']}',
    apiBaseUrl: '${defines['API_BASE_URL']}',
    portalBaseUrl: '${defines['PORTAL_BASE_URL']}',
    mapsEnabled: defines['MAPS_ENABLED'] == true,
    fakeCompiled: fakeCompiled,
  );
}

ProviderContainer _buildContainer(AppEnv build) {
  final c = ProviderContainer(
    overrides: [buildEnvProvider.overrideWithValue(build)],
  );
  addTearDown(c.dispose);
  return c;
}

AuthTokens _tokens(String access, String refresh, {Duration? validFor}) =>
    AuthTokens(
      accessToken: access,
      accessExpiresAt: DateTime.now().toUtc().add(
        validFor ?? const Duration(minutes: 10),
      ),
      refreshToken: refresh,
      userId: 'u-1',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Derleme kararı (saf)', () {
    test(
      'canlı ortam her API_MODE için sahte sunucu ve demo oturumu almaz',
      () {
        for (final compiled in const [true, false]) {
          for (final mode in ApiMode.values) {
            expect(
              fakeApiPolicyFor(
                env: AknEnv.prod,
                apiMode: mode,
                compiled: compiled,
              ),
              FakeApiPolicy.none,
              reason: '$mode, derlendi: $compiled',
            );
          }
          for (final aknEnv in const ['prod', 'production', 'PROD', ' Prod ']) {
            for (final mode in const [
              'fake',
              'live',
              'FAKE',
              'Live',
              '',
              'x',
            ]) {
              final env = AppEnv.fromDefines(
                aknEnv: aknEnv,
                apiMode: mode,
                apiBaseUrl: 'https://api.akaryakitnet.com.tr/',
                portalBaseUrl: 'https://portal.akaryakitnet.com.tr/',
                fakeCompiled: compiled,
              );
              final why = '"$aknEnv" + "$mode", derlendi: $compiled';
              expect(env.isProd, isTrue, reason: why);
              expect(env.isFake, isFalse, reason: why);
              expect(env.apiMode, ApiMode.live, reason: why);
              expect(env.demoOnDemand, isFalse, reason: why);
              expect(env.ribbon, isNull, reason: why);
              expect(env.asDemoSession(), same(env), reason: why);
              expect(env.validate(), isEmpty, reason: why);
            }
          }
        }
      },
    );

    test(
      'canlı derleme (env/prod.json): sahte kip, demo kartı ve demo oturumu yok',
      () {
        for (final compiled in const [true, false]) {
          final prod = _envFile('prod', fakeCompiled: compiled);
          expect(prod.isProd, isTrue);
          expect(prod.isFake, isFalse);
          expect(prod.demoOnDemand, isFalse);
          final c = _buildContainer(prod);
          expect(c.read(demoLoginsEnabledProvider), isFalse);
          expect(c.read(demoSessionProvider.notifier).start(), isFalse);
          expect(c.read(demoSessionProvider), isFalse);
          expect(c.read(appEnvProvider).isFake, isFalse);
          expect(c.read(appEnvProvider).ribbon, isNull);
        }
      },
    );

    test('sahte sunucusu derlenmemiş derleme her ortamda canlı ve demosuz', () {
      for (final e in AknEnv.values) {
        for (final mode in ApiMode.values) {
          expect(
            fakeApiPolicyFor(env: e, apiMode: mode, compiled: false),
            FakeApiPolicy.none,
          );
        }
      }
      final test = _envFile('test', fakeCompiled: false);
      expect(test.isFake, isFalse);
      expect(test.demoOnDemand, isFalse);
    });

    test(
      'test derlemesi (env/test.json): canlı açılış, demo oturumu sunar',
      () {
        expect(
          fakeApiPolicyFor(env: AknEnv.test, apiMode: ApiMode.live),
          FakeApiPolicy.onDemand,
        );
        final test = _envFile('test');
        expect(test.env, AknEnv.test);
        expect(test.isFake, isFalse);
        expect(test.demoOnDemand, isTrue);
        expect(test.demoSession, isFalse);
        expect(test.ribbon, 'TEST');
        expect(test.badge, 'Test');
        expect(test.validate(), isEmpty);

        final demo = test.asDemoSession();
        expect(demo.isFake, isTrue);
        expect(demo.demoSession, isTrue);
        expect(demo.env, AknEnv.test);
        expect(demo.ribbon, 'DEMO');
        expect(demo.badge, 'Test, sahte API');
        expect(demo.apiBaseUrl, test.apiBaseUrl);
        expect(demo.portalBaseUrl, test.portalBaseUrl);
        expect(demo.validate(), isEmpty);
        expect(demo.asDemoSession(), same(demo));
      },
    );

    test(
      'geliştirme ve demo derlemesi (env/dev.json, env/demo.json) bugünkü gibi',
      () {
        expect(
          kFakeApiCompiled,
          isTrue,
          reason: 'testler sahte kipte derlenir',
        );
        for (final name in const ['dev', 'demo']) {
          final env = _envFile(name);
          expect(env.isFake, isTrue, reason: name);
          expect(env.isDev, isTrue, reason: name);
          expect(env.demoOnDemand, isFalse, reason: name);
          expect(env.ribbon, 'DEMO', reason: name);
          expect(env.asDemoSession(), same(env), reason: name);
          final c = _buildContainer(env);
          expect(c.read(demoLoginsEnabledProvider), isTrue, reason: name);
          // Demo kartı ortamı değiştirmez: baştan sahte kip.
          expect(c.read(demoSessionProvider.notifier).start(), isFalse);
          expect(c.read(appEnvProvider), same(env));
        }
      },
    );
  });

  group('Demo oturumunun etkin ortamı', () {
    test(
      'test derlemesi: kart sahte yığına, çıkış canlı yığına geçirir',
      () async {
        final h = await DemoLiveHarness.create();
        final c = h.container();
        addTearDown(c.dispose);
        expect(c.read(demoLoginsEnabledProvider), isTrue);
        expect(c.read(appEnvProvider).isFake, isFalse);
        expect(c.read(dioProvider).httpClientAdapter, same(h.live));

        expect(c.read(demoSessionProvider.notifier).start(), isTrue);
        final demo = c.read(appEnvProvider);
        expect(demo.demoSession, isTrue);
        expect(demo.ribbon, 'DEMO');
        expect(c.read(dioProvider).httpClientAdapter, isA<FakeApiAdapter>());
        expect(c.read(demoLoginsEnabledProvider), isTrue);

        c.read(demoSessionProvider.notifier).end();
        expect(c.read(appEnvProvider).isFake, isFalse);
        expect(c.read(appEnvProvider).ribbon, 'TEST');
        expect(c.read(dioProvider).httpClientAdapter, same(h.live));
      },
    );

    test(
      'demo derlemesi (testlerin sahte ortamı): kart demo oturumu açmaz',
      () async {
        final h = await TestHarness.create(prefs: {'akn.onboardingDone': true});
        final c = h.container();
        addTearDown(c.dispose);
        final s = c.read(sessionControllerProvider.notifier);
        expect(c.read(demoSessionProvider.notifier).start(), isFalse);
        expect(c.read(appEnvProvider), same(AppEnv.fakeForTests));
        await s.restore();
        await s.loginWithPassword('musteri', 'demo');
        expect(c.read(tokenStoreProvider).isDemo, isFalse);
        expect(h.secure.values['akn.refresh'], isNot(startsWith('demo:')));
        c.dispose();

        // Yeniden açılış bugünkü gibi: oturum sahte dünyada sürer.
        final again = h.container();
        addTearDown(again.dispose);
        await again.read(sessionControllerProvider.notifier).restore();
        expect(
          again.read(sessionControllerProvider),
          isA<SessionAuthenticated>(),
        );
        await again.read(sessionControllerProvider.notifier).signOut();
        expect(again.read(appEnvProvider).isFake, isTrue);
      },
    );
  });

  group('Belirteç deposu', () {
    test(
      'demo oturumu önekle yazılır; yenileme türü korur; açılışta yüklenmez',
      () async {
        final secure = MemorySecureStore();
        final store = TokenStore(secure);
        await store.save(
          _tokens('fa.musteri.1.x', 'fr.musteri.1.x'),
          demo: true,
        );
        expect(store.isDemo, isTrue);
        expect(store.refreshToken, 'fr.musteri.1.x');
        expect(secure.values[SecureKeys.refresh], 'demo:fr.musteri.1.x');

        // Yenileme (tür belirtilmez): demo olarak kalır.
        await store.save(_tokens('fa.musteri.2.y', 'fr.musteri.2.y'));
        expect(store.isDemo, isTrue);
        expect(secure.values[SecureKeys.refresh], 'demo:fr.musteri.2.y');

        // Yeniden açılış: önekli belirteç belleğe alınmaz.
        final next = TokenStore(secure);
        await next.load();
        expect(next.staleDemo, isTrue);
        expect(next.hasRefreshToken, isFalse);
        expect(next.refreshToken, isNull);
        expect(next.accessToken, isNull);
        expect(next.userId, 'u-1', reason: 'yerel verisi silinecek kullanıcı');
        await next.clear();
        expect(next.staleDemo, isFalse);
        expect(secure.values.containsKey(SecureKeys.refresh), isFalse);
      },
    );

    test('canlı oturum bugünkü gibi: önek yok, açılışta yüklenir', () async {
      final secure = MemorySecureStore();
      final store = TokenStore(secure);
      await store.save(_tokens('a', 'r-live'), demo: false);
      expect(store.isDemo, isFalse);
      expect(secure.values[SecureKeys.refresh], 'r-live');
      final next = TokenStore(secure);
      await next.load();
      expect(next.staleDemo, isFalse);
      expect(next.refreshToken, 'r-live');
      expect(next.userId, 'u-1');
    });
  });

  group('Yeniden açılış', () {
    test(
      'demo oturumunda kapanan uygulama: kalan oturum silinir, sahte belirteç canlı API\'ye gitmez',
      () async {
        final h = await DemoLiveHarness.create();
        final first = h.container();
        final s1 = first.read(sessionControllerProvider.notifier);
        await s1.restore();
        expect(first.read(demoSessionProvider.notifier).start(), isTrue);
        expect(
          await s1.loginWithPassword('sofor', 'demo'),
          isA<LoginSucceeded>(),
        );
        expect(first.read(tokenStoreProvider).isDemo, isTrue);
        expect(h.secure.values[SecureKeys.refresh], startsWith('demo:fr.'));
        final op = await first
            .read(outboxRunnerProvider)
            .enqueue(
              type: 'driver.start',
              payload: const {'shipmentId': 7},
              runNow: false,
            );
        expect(
          await h.cache.read(CacheKeys.user('u-sofor', CacheKeys.meAccess)),
          isNotNull,
        );
        expect(h.liveRequestsWithTokens, isEmpty);
        // Uygulama demo oturumundayken kapanır (çıkış yok).
        first.dispose();
        final before = h.live.requests.length;

        final second = h.container();
        addTearDown(second.dispose);
        await second.read(sessionControllerProvider.notifier).restore();
        expect(
          second.read(sessionControllerProvider),
          isA<SessionUnauthenticated>(),
        );
        expect(second.read(appEnvProvider).isFake, isFalse);
        expect(second.read(demoLoginsEnabledProvider), isTrue);
        final tokens = second.read(tokenStoreProvider);
        expect(tokens.refreshToken, isNull);
        expect(tokens.accessToken, isNull);
        expect(tokens.isDemo, isFalse);
        expect(h.secure.values.containsKey(SecureKeys.refresh), isFalse);
        expect(h.secure.values.containsKey(SecureKeys.userId), isFalse);
        expect(
          await h.cache.read(CacheKeys.user('u-sofor', CacheKeys.meAccess)),
          isNull,
          reason: 'demo kullanıcısının önbelleği silinir',
        );
        expect(
          await h.outbox.get(op.id),
          isNull,
          reason: 'demo işlemleri silinir',
        );
        expect(
          h.live.requests.length,
          before,
          reason: 'temizlik ağa çıkmaz: ${h.livePaths.skip(before)}',
        );

        // Açılıştan sonra oturum isteyen bir canlı istek: belirteçsiz, yenileme yok.
        await expectLater(
          second
              .read(apiClientProvider)
              .get<Object?>('me/access', parse: (j) => j),
          throwsA(isA<UnauthorizedFailure>()),
        );
        expect(h.live.requests.length, greaterThan(before));
        expect(h.liveRequestsWithTokens, isEmpty);
        expect(h.livePaths.where((p) => p.contains('auth/')), isEmpty);
      },
    );
  });

  group('Canlı yığının korumaları', () {
    test(
      'depo demo oturumunu tutarken canlı yığından istek çıkmaz (savunma derinliği)',
      () async {
        final h = await DemoLiveHarness.create();
        final c = h.container();
        addTearDown(c.dispose);
        // Hata senaryosu: ortam canlıyken depoda demo belirteci (erişim süresi dolmuş).
        await c
            .read(tokenStoreProvider)
            .save(
              _tokens(
                'fa.musteri.1.x',
                'fr.musteri.1.x',
                validFor: const Duration(seconds: -1),
              ),
              demo: true,
            );
        await expectLater(
          c.read(apiClientProvider).get<Object?>('me/access', parse: (j) => j),
          throwsA(isA<AppFailure>()),
        );
        expect(h.live.requests, isEmpty);
      },
    );

    test(
      'yenileme sürerken oturum kapanırsa dönen belirteç depoya geri yazılmaz',
      () async {
        final h = await DemoLiveHarness.create();
        final c = h.container();
        addTearDown(c.dispose);
        final tokens = c.read(tokenStoreProvider);
        await tokens.save(
          _tokens('a-1', 'r-1', validFor: const Duration(seconds: -1)),
          demo: false,
        );
        final release = h.live.held(200, {
          'status': 'ok',
          'tokens': {
            'accessToken': 'a-2',
            'accessExpiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 15))
                .toIso8601String(),
            'refreshToken': 'r-2',
            'userId': 'u-1',
          },
        });
        final call = c
            .read(apiClientProvider)
            .get<Object?>('me/access', parse: (j) => j);
        await pumpEventQueue();
        expect(h.livePaths, ['POST auth/refresh']);
        // Yenileme yanıtı gelmeden oturum kapanır (çıkış, demo oturumunun bitişi).
        await tokens.clear();
        release.complete();
        await expectLater(call, throwsA(isA<AppFailure>()));
        expect(tokens.refreshToken, isNull);
        expect(tokens.accessToken, isNull);
        expect(h.secure.values.containsKey(SecureKeys.refresh), isFalse);
      },
    );
  });
}
