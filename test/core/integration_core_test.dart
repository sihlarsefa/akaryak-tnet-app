// A-INT çekirdek davranışları (spec D.7.5): sunucu kapısı (bakım / uyumsuz sözleşme / 404), app/config
// 3 sn ve önbellek, çıkışta temizlik ve `auth/revoke`, ilk açılışta güvenli anahtarlar, bekleyen işlem
// çakışma tekrarı ve Retry-After, ortam denetimi, hata metinleri, ASCII büyük/küçük harf.
import 'dart:io';
import 'dart:typed_data';

import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/auth/session_cleanup.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/media/document_picker.dart';
import 'package:akaryakitnet/core/models/app_config.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/models/me_access.dart';
import 'package:akaryakitnet/core/models/problem.dart';
import 'package:akaryakitnet/core/network/api_client.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/network/failure_copy.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/offline/cache_store.dart';
import 'package:akaryakitnet/core/offline/outbox_op.dart';
import 'package:akaryakitnet/core/offline/outbox_runner.dart';
import 'package:akaryakitnet/core/offline/outbox_store.dart';
import 'package:akaryakitnet/core/storage/secure_store.dart';
import 'package:akaryakitnet/core/utils/external_activity.dart';
import 'package:akaryakitnet/core/utils/turkish_text.dart';
import 'package:akaryakitnet/features/auth/auth_fake.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

final _world = FakeWorld.seeded();

MeAccess _access(String key) =>
    MeAccess.fromJson(_world.meAccess(findFakePersona(key)!));

RedirectResult _redirect(
  String location, {
  SessionState session = const SessionUnauthenticated(),
  ServerAvailability availability = ServerAvailability.unknown,
  String? deferred,
}) {
  final policy = AccessPolicy(session.access);
  const features = AppFeatures(assistant: true);
  return computeRedirect(
    uri: Uri.parse(location),
    session: session,
    update: UpdateStatus.none,
    availability: availability,
    onboardingDone: true,
    splashDone: true,
    layout: buildNavLayout(policy, features),
    policy: policy,
    features: features,
    deferred: deferred,
  );
}

Future<void> _settle(bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('Sunucu kapısı (bakım, uyumsuz sunucu)', () {
    final signedIn = SessionAuthenticated(_access('musteri'));

    test(
      'oturum açıkken bakım → /update?reason=maintenance, konum saklanır',
      () {
        final r = _redirect(
          '/orders/12',
          session: signedIn,
          availability: ServerAvailability.maintenance,
        );
        expect(r.location, '/update?reason=maintenance');
        expect(r.defer, '/orders/12');
        expect(
          _redirect(
            '/update?reason=maintenance',
            session: signedIn,
            availability: ServerAvailability.maintenance,
          ).location,
          isNull,
        );
      },
    );

    test('uyumsuz sözleşme / eski API → /update?reason=server', () {
      expect(
        _redirect(
          '/home',
          session: signedIn,
          availability: ServerAvailability.outdated,
        ).location,
        '/update?reason=server',
      );
    });

    test('düzelince saklanan konuma ya da ilk sekmeye döner', () {
      final back = _redirect(
        '/update?reason=server',
        session: signedIn,
        availability: ServerAvailability.ok,
        deferred: '/orders/12',
      );
      expect(back.location, '/orders/12');
      expect(back.consumedDeferred, isTrue);
      expect(
        _redirect(
          '/update?reason=maintenance',
          session: signedIn,
          availability: ServerAvailability.unknown,
        ).location,
        '/home',
      );
    });

    test(
      'oturum yokken giriş ekranı kendi durumunu gösterir (yönlendirme yok)',
      () {
        expect(
          _redirect(
            '/login',
            availability: ServerAvailability.maintenance,
          ).location,
          isNull,
        );
      },
    );

    test('AppConfig: bakım, sözleşme, yeni alanlar', () {
      final c = AppConfig.fromJson({
        'minBuild': 1,
        'latestBuild': 3,
        'features': {'orderExpiry': true, 'assistant': true},
        'support': {'url': 'http://x/legal/support'},
        'legal': {'accountDeletionUrl': 'http://x/legal/account-deletion'},
        'assistantConsentVersion': '2',
        'maintenance': {'active': true, 'message': 'Gece bakımı'},
        'apiBuild': 'abc123',
        'contractVersion': 'mobile-v1',
      });
      expect(c.features.orderExpiry, isTrue);
      expect(c.support.url, 'http://x/legal/support');
      expect(c.legal.accountDeletionUrl, 'http://x/legal/account-deletion');
      expect(c.assistantConsentVersion, '2');
      expect(c.maintenance.active, isTrue);
      expect(c.maintenance.message, 'Gece bakımı');
      expect(c.apiBuild, 'abc123');
      expect(c.contractMatches, isTrue);
      expect(
        AppConfig.fromJson({'contractVersion': 'mobile-v2'}).contractMatches,
        isFalse,
      );
      expect(AppConfig.fromJson(const {}).contractMatches, isTrue);
      final round = AppConfig.fromJson(c.toJson());
      expect(round.maintenance.message, 'Gece bakımı');
      expect(round.features.orderExpiry, isTrue);
    });

    test('denetleyici: tamam / bakım / farklı sözleşme / 404', () async {
      final h = await TestHarness.create();
      final ctl = AuthFakeControls.of(h.server);
      final c = h.container();
      addTearDown(c.dispose);
      Future<ServerAvailability> load() async {
        await c.read(appConfigProvider.notifier).load();
        return c.read(serverAvailabilityProvider);
      }

      expect(await load(), ServerAvailability.ok);
      ctl.maintenance = true;
      ctl.maintenanceMessage = 'Bakım';
      expect(await load(), ServerAvailability.maintenance);
      expect(c.read(appConfigProvider).maintenance.message, 'Bakım');
      ctl
        ..maintenance = false
        ..contractVersion = 'mobile-v9';
      expect(await load(), ServerAvailability.outdated);
      ctl
        ..contractVersion = 'mobile-v1'
        ..configMissing = true;
      expect(await load(), ServerAvailability.outdated);
      ctl.configMissing = false;
      expect(await load(), ServerAvailability.ok);
    });

    test('3 sn içinde gelmezse önbellek; geç yanıt yine uygulanır', () async {
      final h = await TestHarness.create();
      final cache = MemoryCacheStore();
      await cache.write(CacheKeys.appConfig, {
        'minBuild': 1,
        'latestBuild': 7,
        'features': {'weather': true},
      });
      h.server.latencyEnabled = true;
      h.server
        ..minLatency = const Duration(milliseconds: 400)
        ..maxLatency = const Duration(milliseconds: 401);
      final c = h.container(
        extra: [cacheStoreProvider.overrideWithValue(cache)],
      );
      addTearDown(c.dispose);
      final sw = Stopwatch()..start();
      await c
          .read(appConfigProvider.notifier)
          .load(timeout: const Duration(milliseconds: 50));
      expect(sw.elapsedMilliseconds, lessThan(350), reason: 'beklemez');
      expect(c.read(appConfigProvider).latestBuild, 7, reason: 'önbellek');
      expect(c.read(appConfigProvider).fromCache, isTrue);
      await _settle(() => !c.read(appConfigProvider).fromCache);
      expect(c.read(appConfigProvider).fromCache, isFalse, reason: 'geç yanıt');
    });
  });

  group('Çıkış ve kullanıcı değişimi', () {
    test(
      'çıkış: önbellek (oturumdan bağımsız kayıt hariç) ve temizlik',
      () async {
        final h = await TestHarness.create();
        final cache = MemoryCacheStore();
        var cleaned = <String?>[];
        final c = h.container(
          extra: [
            cacheStoreProvider.overrideWithValue(cache),
            sessionCleanupProvider.overrideWithValue(
              (u) async => cleaned.add(u),
            ),
          ],
        );
        addTearDown(c.dispose);
        final s = c.read(sessionControllerProvider.notifier);
        await s.restore();
        await s.loginWithPassword('musteri', 'demo');
        await cache.write('serbest.anahtar', {'x': 1});
        await cache.write(CacheKeys.appConfig, {'minBuild': 1});
        await s.signOut();
        expect(await cache.read('serbest.anahtar'), isNull);
        expect(
          await cache.read(CacheKeys.user('u-musteri', CacheKeys.meAccess)),
          isNull,
        );
        expect(await cache.read(CacheKeys.appConfig), isNotNull);
        expect(cleaned, ['u-musteri']);
        expect(h.secure.values['akn.refresh'], isNull);
        cleaned = [];
      },
    );

    test(
      'erişim belirteci dolmuşsa çıkış auth/revoke ile (yenileme yok)',
      () async {
        final h = await TestHarness.create();
        final c = h.container(
          extra: [sessionCleanupProvider.overrideWithValue((_) async {})],
        );
        addTearDown(c.dispose);
        final s = c.read(sessionControllerProvider.notifier);
        await s.restore();
        await s.loginWithPassword('sahip', 'demo');
        c.read(tokenStoreProvider).expireAccess();
        final refreshesBefore = h.server.auth.refreshCalls;
        await s.signOut();
        expect(h.server.auth.revokeCalls, 1);
        expect(
          h.server.auth.refreshCalls,
          refreshesBefore,
          reason: 'yenilemez',
        );
        expect(
          c.read(sessionControllerProvider),
          isA<SessionUnauthenticated>(),
        );
      },
    );

    test('başka kullanıcıyla giriş öncekinin izlerini siler', () async {
      final h = await TestHarness.create();
      final cache = MemoryCacheStore();
      final cleaned = <String?>[];
      final c = h.container(
        extra: [
          cacheStoreProvider.overrideWithValue(cache),
          sessionCleanupProvider.overrideWithValue((u) async => cleaned.add(u)),
        ],
      );
      addTearDown(c.dispose);
      final s = c.read(sessionControllerProvider.notifier);
      await s.restore();
      await s.loginWithPassword('musteri', 'demo');
      await cache.write(CacheKeys.user('u-musteri', 'ozel'), {
        'a': 1,
      }, userId: 'u-musteri');
      // Oturum sunucuda düştü ama yerel kimlik kaldı; doğrudan başka kullanıcı giriyor.
      await s.loginWithPassword('sahip', 'demo');
      expect(await cache.read(CacheKeys.user('u-musteri', 'ozel')), isNull);
      expect(cleaned, contains('u-musteri'));
    });

    test('ilk açılışta akn.* güvenli anahtarları silinir, bir kez', () async {
      final secure = MemorySecureStore({
        SecureKeys.refresh: 'eski',
        SecureKeys.userId: 'u-eski',
        SecureKeys.deviceId: 'cihaz-eski',
      });
      final prefs = <String, bool>{};
      Future<bool> run() => FirstLaunch.wipeIfFresh(
        hasPref: prefs.containsKey,
        markPref: (k) async => prefs[k] = true,
        secure: secure,
      );
      expect(await run(), isTrue);
      expect(secure.values, isEmpty);
      await secure.write(SecureKeys.refresh, 'yeni');
      expect(await run(), isFalse);
      expect(secure.values[SecureKeys.refresh], 'yeni');
    });
  });

  group('Bekleyen işlemler', () {
    late MemoryOutboxStore store;
    final calls = <bool>[];

    OutboxRunner runner(List<Object> script) => OutboxRunner(
      store: store,
      api: ApiClient(Dio()),
      currentUserId: () => 'u-1',
      handlers: {
        'field.saveDraft': (op, ctx) async {
          calls.add(ctx.isConflictRetry);
          final next = script.removeAt(0);
          if (next is AppFailure) throw next;
          return next as JsonMap;
        },
      },
    );

    setUp(() {
      store = MemoryOutboxStore();
      calls.clear();
    });

    test('çakışma: bir kez yeniden okuyup tekrar → başarı', () async {
      final r = runner([
        ConflictFailure('concurrency_conflict'),
        <String, dynamic>{'ok': true},
      ]);
      final op = await r.enqueue(
        type: 'field.saveDraft',
        payload: const {'x': 1},
        runNow: false,
      );
      await r.runOnce();
      expect(calls, [false, true]);
      expect((await store.get(op.id))!.status, OutboxStatus.done);
    });

    test('ikinci çakışma kullanıcıya bırakılır', () async {
      final r = runner([
        ConflictFailure('concurrency_conflict'),
        ConflictFailure('concurrency_conflict'),
      ]);
      final op = await r.enqueue(
        type: 'field.saveDraft',
        payload: const {'x': 1},
        runNow: false,
      );
      await r.runOnce();
      final after = (await store.get(op.id))!;
      expect(after.status, OutboxStatus.needsAttention);
      expect(calls, [false, true]);
    });

    test(
      '503 Retry-After beklemesi kullanılır; bağlantı gelince sıfırlanır',
      () async {
        final r = runner([
          const ServerFailure(
            statusCode: 503,
            retryAfter: Duration(minutes: 9),
          ),
          <String, dynamic>{'ok': true},
        ]);
        final op = await r.enqueue(
          type: 'field.saveDraft',
          payload: const {},
          runNow: false,
        );
        await r.runOnce();
        final failed = (await store.get(op.id))!;
        expect(failed.status, OutboxStatus.failed);
        final wait = failed.nextAttemptAt!.difference(DateTime.now().toUtc());
        expect(wait.inMinutes, greaterThanOrEqualTo(8));
        await r.retryWaiting();
        expect((await store.get(op.id))!.status, OutboxStatus.done);
      },
    );

    test('Retry-After başlığı 429 ve 503 için okunur', () {
      final f503 = AppFailure.fromResponse(503, const {
        'code': 'service_unavailable',
      }, retryAfterHeader: '120');
      expect(f503.retryAfter, const Duration(seconds: 120));
      final f429 = AppFailure.fromResponse(429, null, retryAfterHeader: '30');
      expect(f429.retryAfter, const Duration(seconds: 30));
      expect(f429, isA<RateLimitedFailure>());
    });
  });

  group('Ortam denetimi', () {
    AppEnv env(AknEnv e, String api, String portal, ApiMode mode) =>
        AppEnv(env: e, apiBaseUrl: api, apiMode: mode, portalBaseUrl: portal);

    test('canlı: HTTPS + canlı API + gerçek alan adı', () {
      expect(
        env(
          AknEnv.prod,
          'https://api.akaryakitnet.com.tr/',
          'https://portal.akaryakitnet.com.tr/',
          ApiMode.live,
        ).validate(),
        isEmpty,
      );
      final bad = env(
        AknEnv.prod,
        'http://134.149.201.54:3108/',
        'https://portal.akaryakitnet.example/',
        ApiMode.fake,
      ).validate();
      expect(bad.join(' '), contains('HTTPS'));
      expect(bad.join(' '), contains('sahte API'));
      expect(bad.join(' '), contains('örnek alan adı'));
    });

    test('test ortamı canlı API ister; geliştirme sahte olabilir', () {
      expect(
        env(
          AknEnv.test,
          'http://134.149.201.54:3108/',
          'http://134.149.201.54:3107/',
          ApiMode.live,
        ).validate(),
        isEmpty,
      );
      expect(
        env(AknEnv.test, 'http://x/', 'http://y/', ApiMode.fake).validate(),
        isNotEmpty,
      );
      expect(AppEnv.fakeForTests.validate(), isEmpty);
    });

    test('şerit: canlıda yok, sahte veride DEMO, testte TEST', () {
      expect(AppEnv.fakeForTests.ribbon, 'DEMO');
      expect(
        env(AknEnv.test, 'http://x/', 'http://y/', ApiMode.live).ribbon,
        'TEST',
      );
      expect(
        env(AknEnv.prod, 'https://x/', 'https://y/', ApiMode.live).ribbon,
        isNull,
      );
    });

    test('derleme zamanı sahte koruması (testler sahte kipte derlenir)', () {
      expect(kFakeApiCompiled, isTrue);
    });
  });

  group('Hata metinleri tablosu (spec C.7)', () {
    test('başlıklar ve destek kodu', () {
      expect(
        FailureCopy.title(const OfflineFailure()),
        'İnternet bağlantısı yok',
      );
      expect(
        FailureCopy.title(const TimeoutFailure()),
        'Sunucu zamanında yanıt vermedi',
      );
      expect(
        FailureCopy.message(RateLimitedFailure(const Duration(seconds: 30))),
        'Çok fazla deneme. 30 sn sonra tekrar deneyin.',
      );
      expect(
        FailureCopy.title(ConflictFailure('concurrency_conflict')),
        'Bu kayıt sizden sonra güncellendi',
      );
      const server = ServerFailure(
        statusCode: 500,
        problem: Problem(
          status: 500,
          code: 'server_error',
          traceId: '1a2b3c4d5e6f7a8b',
        ),
      );
      expect(FailureCopy.title(server), 'Beklenmeyen bir hata oluştu');
      expect(FailureCopy.supportCodeOf(server), '1a2b3c4d');
      expect(FailureCopy.supportLine('1a2b3c4d'), 'Destek kodu: 1a2b3c4d');
      expect(
        FailureCopy.message(const BusinessFailure('Limit aşıldı.')),
        'Limit aşıldı.',
      );
    });
  });

  group('Dış etkinlik (kilit)', () {
    tearDown(ExternalActivity.reset);

    test('etkinlik sürerken ve hemen sonrasında etkin sayılır', () async {
      var now = DateTime(2026, 10, 21, 10);
      ExternalActivity.clock = () => now;
      addTearDown(() => ExternalActivity.clock = DateTime.now);
      expect(ExternalActivity.active, isFalse);
      late bool during;
      await ExternalActivity.run(() async => during = ExternalActivity.active);
      expect(during, isTrue);
      expect(ExternalActivity.active, isTrue, reason: 'kısa süre sonra da');
      now = now.add(const Duration(seconds: 5));
      expect(ExternalActivity.active, isFalse);
    });
  });

  group('Belge seçici (PDF)', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('akn_pdf'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('PDF imzası ve boyut sınırı', () async {
      final pdf = File('${dir.path}/dekont.pdf')
        ..writeAsBytesSync(
          Uint8List.fromList([...'%PDF-1.7\n'.codeUnits, 1, 2]),
        );
      final doc = await DocumentPicker.read(pdf.path);
      expect(doc.fileName, 'dekont.pdf');
      expect(doc.contentType, 'application/pdf');

      final jpg = File('${dir.path}/foto.pdf')
        ..writeAsBytesSync(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0]));
      await expectLater(
        DocumentPicker.read(jpg.path),
        throwsA(
          isA<DocumentPickFailure>().having(
            (f) => f.message,
            'message',
            'Yalnızca PDF dosyası seçebilirsiniz.',
          ),
        ),
      );

      final big = File('${dir.path}/buyuk.pdf')
        ..writeAsBytesSync(
          Uint8List(1024 * 1024 + 10)..setAll(0, '%PDF'.codeUnits),
        );
      await expectLater(
        DocumentPicker.read(big.path, maxMb: 1),
        throwsA(
          isA<DocumentPickFailure>().having(
            (f) => f.message,
            'message',
            'Dosya en fazla 1 MB olabilir.',
          ),
        ),
      );
    });
  });

  group('ASCII büyük/küçük harf (Türkçe metin dışı)', () {
    test('yalnızca A–Z değişir', () {
      expect('Image/JPEG'.asciiLower, 'image/jpeg');
      expect('34 abc 12'.asciiUpper, '34 ABC 12');
      expect('İstanbul'.asciiLower, 'İstanbul', reason: 'İ ASCII değil');
      expect('ışık'.asciiUpper, 'ışıK', reason: 'ı ASCII değil');
      expect(TurkishText.upper('sipariş formu'), 'SİPARİŞ FORMU');
    });
  });

  test(
    'ProviderContainer kurulumu (sahte sunucu kayıtları) bozulmadı',
    () async {
      final h = await TestHarness.create();
      final c = ProviderContainer(overrides: h.overrides);
      addTearDown(c.dispose);
      expect(c.read(fakeServerProvider).routeCount, greaterThan(100));
    },
  );
}
