// Bildirim izni (spec C.4, C.7): Android 13+ (API 33) eklentisi henüz sorulmamış izni de "reddedildi"
// bildirir. Uygulama izni bir kez sorduğunu saklar; hiç sormadıysa durum "belirlenmedi" sayılır. İzin
// bir kez istenir (yerel bildirimler için ikinci bir sistem penceresi yok).
//
// Sahip kararı 2026-10-30: izin, girişten sonraki ön sayfa yerine uygulamanın İLK AÇILIŞINDA, herkese
// (müşteri dahil) doğrudan sistem penceresiyle bir kez sorulur. Karar verilmişse açılışta hiç sorulmaz;
// cihaz kaydı girişte yine yapılır, demo oturumunun kaydı canlı sunucuya gitmez.
import 'dart:convert';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/network/fake/fake_auth.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/push/push_providers.dart';
import 'package:akaryakitnet/core/push/push_service.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/demo_live_harness.dart';
import '../support/fake_push.dart';
import '../support/test_app.dart';

/// Android 13+ davranışı: istenmeden önce `denied`; isteyince kullanıcının seçimi.
class _FakePlatform implements PushPermissionPlatform {
  _FakePlatform({this.sdk = 33, this.answer = AuthorizationStatus.denied});

  final int? sdk;
  AuthorizationStatus answer;
  AuthorizationStatus current = AuthorizationStatus.denied;
  int requests = 0;

  @override
  Future<int?> androidSdkInt() async => sdk;

  @override
  Future<AuthorizationStatus> status() async => current;

  @override
  Future<AuthorizationStatus> request() async {
    requests++;
    current = answer;
    return answer;
  }
}

Future<PrefsStore> _prefs([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return PrefsStore(await SharedPreferences.getInstance());
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// Firebase yapılandırılmış gibi: [platform] izni, sabit belirteç.
List<Override> _pushOn(SharedPreferences prefs, FakePushPlatform platform) => [
  firebaseAvailableProvider.overrideWithValue(true),
  pushServiceProvider.overrideWith((ref) {
    final s = FakePushService(prefs: PrefsStore(prefs), permissions: platform);
    ref.onDispose(s.dispose);
    return s;
  }),
];

Future<void> _login(ProviderContainer c, String persona) async {
  final s = c.read(sessionControllerProvider.notifier);
  final outcome = await s.loginWithPassword(persona, 'demo');
  if (outcome is LoginNeedsCode) {
    await s.verifyCode(outcome.challenge.challengeId, '123456');
  }
}

FakeDeviceSession? _device(TestHarness h, String persona) =>
    h.server.auth.sessions[persona]?['test-device'];

ResponseBody _json(int status, Object? body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json; charset=utf-8'],
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('Android 13+', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('hiç sorulmamış izin "belirlenmedi"; bir kez sorulur', () async {
      final prefs = await _prefs();
      final platform = _FakePlatform(answer: AuthorizationStatus.authorized);
      final push = PushService(
        available: true,
        prefs: prefs,
        permissions: platform,
      );
      expect(await push.permission(), PushPermission.notDetermined);
      expect(await push.requestPermission(), isTrue);
      expect(platform.requests, 1, reason: 'tek sistem penceresi');
      expect(prefs.getBool(PrefKeys.pushPermissionRequested), isTrue);
      expect(await push.permission(), PushPermission.granted);
      await push.dispose();
    });

    test('sorulup reddedilen izin "reddedildi" kalır', () async {
      final prefs = await _prefs();
      final platform = _FakePlatform();
      final push = PushService(
        available: true,
        prefs: prefs,
        permissions: platform,
      );
      expect(await push.requestPermission(), isFalse);
      expect(await push.permission(), PushPermission.denied);
      // Uygulama yeniden açıldı: bilgi tercihlerde.
      final again = PushService(
        available: true,
        prefs: prefs,
        permissions: platform,
      );
      expect(await again.permission(), PushPermission.denied);
      await push.dispose();
      await again.dispose();
    });

    test('Android 12 ve öncesi: "kapalı" kullanıcı ayarıdır', () async {
      final push = PushService(
        available: true,
        prefs: await _prefs(),
        permissions: _FakePlatform(sdk: 32),
      );
      expect(await push.permission(), PushPermission.denied);
      await push.dispose();
    });

    test('ilk açılışta hiç sorulmamış izin bir kez istenir', () async {
      final prefs = await _prefs();
      final platform = _FakePlatform(answer: AuthorizationStatus.authorized);
      final push = PushService(
        available: true,
        prefs: prefs,
        permissions: platform,
      );
      expect(await push.requestAtFirstLaunch(), isTrue);
      expect(platform.requests, 1);
      expect(await push.requestAtFirstLaunch(), isFalse);
      expect(platform.requests, 1);
      await push.dispose();
    });
  });

  test(
    'iOS: sorulmamış izin zaten "belirlenmedi" gelir; "reddedildi" olduğu gibi',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final platform = _FakePlatform(sdk: null);
      final push = PushService(
        available: true,
        prefs: await _prefs(),
        permissions: platform,
      );
      expect(await push.permission(), PushPermission.denied);
      platform.current = AuthorizationStatus.notDetermined;
      expect(await push.permission(), PushPermission.notDetermined);
      await push.dispose();
    },
  );

  group('ilk açılış (sahip kararı 2026-10-30)', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    test(
      'hiç sorulmamış izin ön sayfasız, doğrudan ve yalnızca bir kez istenir',
      () async {
        final prefs = await _prefs();
        final platform = FakePushPlatform();
        final push = FakePushService(prefs: prefs, permissions: platform);
        expect(await push.requestAtFirstLaunch(), isTrue);
        expect(platform.requests, 1);
        expect(prefs.getBool(PrefKeys.pushLaunchAsked), isTrue);
        expect(await push.permission(), PushPermission.granted);
        // Yeniden açılış: tercihlerde not var, pencere bir daha açılmaz.
        final again = FakePushService(prefs: prefs, permissions: platform);
        expect(await again.requestAtFirstLaunch(), isFalse);
        expect(platform.requests, 1);
        await push.dispose();
        await again.dispose();
      },
    );

    test('reddedilen izin için açılışta ısrar edilmez', () async {
      final prefs = await _prefs();
      final platform = FakePushPlatform(answer: AuthorizationStatus.denied);
      final push = FakePushService(prefs: prefs, permissions: platform);
      expect(await push.requestAtFirstLaunch(), isTrue);
      expect(await push.permission(), PushPermission.denied);
      for (var i = 0; i < 3; i++) {
        final again = FakePushService(prefs: prefs, permissions: platform);
        expect(await again.requestAtFirstLaunch(), isFalse);
        await again.dispose();
      }
      expect(platform.requests, 1);
      await push.dispose();
    });

    for (final decided in const [
      AuthorizationStatus.authorized,
      AuthorizationStatus.denied,
    ]) {
      test('izin zaten "${decided.name}" ise açılışta sorulmaz', () async {
        final prefs = await _prefs();
        final platform = FakePushPlatform(current: decided);
        final push = FakePushService(prefs: prefs, permissions: platform);
        expect(await push.requestAtFirstLaunch(), isFalse);
        expect(platform.requests, 0);
        expect(prefs.getBool(PrefKeys.pushLaunchAsked), isTrue);
        // Sonradan sıfırlansa bile (telefon ayarlarından) açılış bir daha bakmaz.
        platform.current = AuthorizationStatus.notDetermined;
        expect(await push.requestAtFirstLaunch(), isFalse);
        expect(platform.requests, 0);
        await push.dispose();
      });
    }

    test('Firebase yoksa hiçbir şey yapılmaz, not da düşülmez', () async {
      final prefs = await _prefs();
      final platform = FakePushPlatform();
      final push = PushService(
        available: false,
        prefs: prefs,
        permissions: platform,
      );
      expect(await push.requestAtFirstLaunch(), isFalse);
      expect(platform.requests, 0);
      expect(prefs.getBool(PrefKeys.pushLaunchAsked), isFalse);
      await push.dispose();
    });

    test(
      'koordinatör: giriş ekranında müşteri dahil herkese sorulur; girişte cihaz yine kaydedilir',
      () async {
        final h = await TestHarness.create(
          prefs: const {'akn.onboardingDone': true},
        );
        final platform = FakePushPlatform();
        final c = h.container(extra: _pushOn(h.prefs, platform));
        addTearDown(c.dispose);
        // AknApp gibi: koordinatör oturum geri yüklenmeden başlar; oturum bilinmezken sorulmaz.
        c.read(pushCoordinatorProvider);
        await pumpEventQueue();
        expect(platform.requests, 0);
        await c.read(sessionControllerProvider.notifier).restore();
        expect(
          c.read(sessionControllerProvider),
          isA<SessionUnauthenticated>(),
        );
        await _until(() => platform.requests > 0);
        expect(platform.requests, 1, reason: 'giriş ekranında, girişten önce');
        // Girişten önce verilen izin: giriş cihazı kaydeder (belirteç + push açık).
        await _login(c, 'musteri');
        await _until(() => _device(h, 'musteri')?.pushToken != null);
        expect(_device(h, 'musteri')?.pushToken, 'tok-1');
        expect(_device(h, 'musteri')?.pushEnabled, isTrue);
        // Çıkış ve yeniden giriş: pencere bir daha açılmaz, kayıt yine yapılır.
        await c.read(sessionControllerProvider.notifier).signOut();
        await _login(c, 'musteri');
        await _until(() => _device(h, 'musteri')?.pushToken != null);
        expect(_device(h, 'musteri')?.pushEnabled, isTrue);
        expect(platform.requests, 1);
      },
    );

    test(
      'koordinatör: kilitli oturumda biyometrik pencereyle çakışmaz, kilit açılınca sorulur',
      () async {
        final h = await TestHarness.create(
          prefs: const {'akn.onboardingDone': true},
        );
        // Önceki sürüm: oturum açık, izin hiç sorulmamış (Firebase yokken açılış bir şey yapmaz).
        final before = h.container();
        await before.read(sessionControllerProvider.notifier).restore();
        await _login(before, 'onay');
        before.dispose();
        await h.prefs.setBool(PrefKeys.biometricLock, true);
        // Yeni sürümle açılış: oturum kilitli geri gelir.
        final platform = FakePushPlatform();
        final c = h.container(extra: _pushOn(h.prefs, platform));
        addTearDown(c.dispose);
        c.read(pushCoordinatorProvider);
        await c.read(sessionControllerProvider.notifier).restore();
        expect(c.read(sessionControllerProvider), isA<SessionLocked>());
        await pumpEventQueue();
        expect(platform.requests, 0, reason: 'kilit ekranında sorulmaz');
        c.read(sessionControllerProvider.notifier).unlock();
        await _until(() => platform.requests > 0);
        expect(platform.requests, 1);
        // Açık oturumda izin verildi: kayıt (yeniden) gönderilir.
        await _until(() => _device(h, 'onay')?.pushToken != null);
        expect(_device(h, 'onay')?.pushToken, 'tok-1');
        expect(_device(h, 'onay')?.pushEnabled, isTrue);
      },
    );

    test(
      'test derlemesi: açılışta verilen izinle demo oturumu yalnızca sahte sunucuya, canlı oturum '
      'canlıya kaydolur',
      () async {
        final h = await DemoLiveHarness.create();
        final musteri = fakePersonas.firstWhere((p) => p.key == 'musteri');
        final liveMe = {
          ...h.server.world.meAccess(musteri),
          'userId': 'live-guid-1',
          'userName': 'ahmet',
        };
        final base = h.live.fallback!;
        h.live.fallback = (o) {
          final path = o.uri.path;
          if (path.endsWith('/app/config')) return base(o);
          if (path.endsWith('/auth/login')) {
            return _json(200, {
              'status': 'ok',
              'tokens': {
                'accessToken': 'la-1',
                'accessExpiresAt': DateTime.now()
                    .toUtc()
                    .add(const Duration(minutes: 15))
                    .toIso8601String(),
                'refreshToken': 'lr-1',
                'userId': 'live-guid-1',
              },
            });
          }
          if (path.endsWith('/me/access')) return _json(200, liveMe);
          if (path.endsWith('/auth/logout') ||
              path.endsWith('/devices/current')) {
            return _json(200, const {});
          }
          return _json(404, {
            'title': 'Bulunamadı',
            'status': 404,
            'code': 'not_found',
          });
        };
        final platform = FakePushPlatform();
        final c = h.container(extra: _pushOn(h.prefs, platform));
        addTearDown(c.dispose);
        c.read(pushCoordinatorProvider);
        final s = c.read(sessionControllerProvider.notifier);
        await s.restore();
        await _until(() => platform.requests > 0);
        expect(platform.requests, 1, reason: 'giriş ekranında bir kez');

        // Demo kartı: kayıt sahte dünyaya gider; canlıya cihaz kaydı yok.
        expect(c.read(demoSessionProvider.notifier).start(), isTrue);
        expect(
          await s.loginWithPassword('musteri', 'demo'),
          isA<LoginSucceeded>(),
        );
        final demoDevices = h.server.auth.sessions['musteri'];
        await _until(
          () => demoDevices?.values.any((d) => d.pushToken == 'tok-1') ?? false,
        );
        expect(
          demoDevices?.values.where((d) => d.pushToken == 'tok-1').single,
          isA<FakeDeviceSession>().having(
            (d) => d.pushEnabled,
            'pushEnabled',
            isTrue,
          ),
        );
        expect(
          h.livePaths.where((p) => p.endsWith('devices/current')),
          isEmpty,
        );
        await s.signOut();
        expect(c.read(appEnvProvider).isFake, isFalse);

        // Canlı giriş: kayıt canlıya, canlı belirteçle, push açık.
        expect(
          await s.loginWithPassword('ahmet', 'gizli'),
          isA<LoginSucceeded>(),
        );
        await _until(
          () => h.live.requests.any((r) => r.path.endsWith('/devices/current')),
        );
        final put = h.live.requests.singleWhere(
          (r) => r.path.endsWith('/devices/current'),
        );
        expect(put.header('authorization'), 'Bearer la-1');
        expect((put.body! as Map)['pushToken'], 'tok-1');
        expect((put.body! as Map)['pushEnabled'], isTrue);
        expect(platform.requests, 1);
      },
    );
  });
}
