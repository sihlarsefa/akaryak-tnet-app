import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/models/app_config.dart';
import 'package:akaryakitnet/core/models/me_access.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/routing/route_access.dart';
import 'package:flutter_test/flutter_test.dart';

final _world = FakeWorld.seeded();

MeAccess _access(String key) =>
    MeAccess.fromJson(_world.meAccess(findFakePersona(key)!));

RedirectResult _redirect(
  String location, {
  SessionState session = const SessionUnauthenticated(),
  UpdateStatus update = UpdateStatus.none,
  bool onboardingDone = true,
  bool splashDone = true,
  String? deferred,
  String? deferredFallback,
  bool dev = false,
}) {
  final access = session.access;
  final policy = AccessPolicy(access);
  const features = AppFeatures(assistant: true);
  return computeRedirect(
    uri: Uri.parse(location),
    session: session,
    update: update,
    onboardingDone: onboardingDone,
    splashDone: splashDone,
    layout: buildNavLayout(policy, features),
    policy: policy,
    features: features,
    devRoutesEnabled: dev,
    deferred: deferred,
    deferredFallback: deferredFallback,
  );
}

void main() {
  group('Açılış ve giriş', () {
    test('oturum bilinmezken açılış ekranı; derin bağlantı saklanır', () {
      final r = _redirect('/orders/12', session: const SessionUnknown());
      expect(r.location, '/splash');
      expect(r.defer, '/orders/12');
      expect(
        _redirect('/splash', session: const SessionUnknown()).location,
        isNull,
      );
    });

    test('açılış animasyonu bitmeden oturum açık olsa da beklenir', () {
      expect(
        _redirect(
          '/splash',
          session: SessionAuthenticated(_access('musteri')),
          splashDone: false,
        ).location,
        isNull,
      );
    });

    test('zorunlu güncelleme her şeyin önündedir', () {
      expect(
        _redirect(
          '/home',
          session: SessionAuthenticated(_access('musteri')),
          update: UpdateStatus.required,
        ).location,
        '/update',
      );
      expect(
        _redirect('/update', update: UpdateStatus.required).location,
        isNull,
      );
    });

    test('ilk açılış: tanıtım, sonra giriş', () {
      expect(
        _redirect('/splash', onboardingDone: false).location,
        '/onboarding',
      );
      expect(_redirect('/onboarding', onboardingDone: false).location, isNull);
      expect(_redirect('/splash').location, '/login');
      expect(_redirect('/login').location, isNull);
      expect(_redirect('/login/code').location, isNull);
      final deep = _redirect('/approvals/9001');
      expect(deep.location, '/login');
      expect(deep.defer, '/approvals/9001');
    });

    test('kilitliyken kilit ekranı', () {
      expect(
        _redirect('/home', session: SessionLocked(_access('sahip'))).location,
        '/locked',
      );
      expect(
        _redirect('/locked', session: SessionLocked(_access('sahip'))).location,
        isNull,
      );
    });
  });

  group('Oturum açık', () {
    test('girişten sonra ilk sekme; şoför Teslimatlarım', () {
      expect(
        _redirect(
          '/login',
          session: SessionAuthenticated(_access('musteri')),
        ).location,
        '/home',
      );
      expect(
        _redirect(
          '/splash',
          session: SessionAuthenticated(_access('sofor')),
        ).location,
        '/driver',
      );
      expect(
        _redirect(
          '/home',
          session: SessionAuthenticated(_access('sofor')),
        ).location,
        '/driver',
      );
    });

    test('saklanan derin bağlantı izin varsa açılır', () {
      final r = _redirect(
        '/login',
        session: SessionAuthenticated(_access('finans')),
        deferred: '/approvals/9001',
      );
      expect(r.location, '/approvals/9001');
      expect(r.consumedDeferred, isTrue);
      final denied = _redirect(
        '/login',
        session: SessionAuthenticated(_access('sofor')),
        deferred: '/quote-desk',
      );
      expect(denied.location, '/driver');
      expect(denied.consumedDeferred, isTrue);
    });

    test(
      'oturumsuzken dokunulan push: izin varsa rota, yoksa gelen kutusu (ilk sekme değil)',
      () {
        final ok = _redirect(
          '/login',
          session: SessionAuthenticated(_access('musteri')),
          deferred: '/orders/12',
          deferredFallback: '/notifications',
        );
        expect(ok.location, '/orders/12');
        expect(ok.consumedDeferred, isTrue);
        final denied = _redirect(
          '/splash',
          session: SessionAuthenticated(_access('musteri')),
          deferred: '/bayi/orders/12',
          deferredFallback: '/notifications',
        );
        expect(denied.location, '/notifications');
        expect(denied.consumedDeferred, isTrue);
        // Saklanan bağlantı yoksa yedek kullanılmaz.
        expect(
          _redirect(
            '/login',
            session: SessionAuthenticated(_access('musteri')),
            deferredFallback: '/notifications',
          ).location,
          '/home',
        );
      },
    );

    test('yetkisiz rota ilk sekmeye döner', () {
      expect(
        _redirect(
          '/quote-desk',
          session: SessionAuthenticated(_access('musteri')),
        ).location,
        '/home',
      );
      expect(
        _redirect(
          '/orders/new',
          session: SessionAuthenticated(_access('sahip')),
        ).location,
        '/home',
      );
      expect(
        _redirect(
          '/payments',
          session: SessionAuthenticated(_access('saha')),
        ).location,
        '/home',
      );
      expect(
        _redirect(
          '/orders/12',
          session: SessionAuthenticated(_access('musteri')),
        ).location,
        isNull,
      );
      expect(
        _redirect(
          '/driver/shipments/5002',
          session: SessionAuthenticated(_access('sofor')),
        ).location,
        isNull,
      );
    });

    test('merkez yalnızca Onaylarım, Bildirimler, Profil', () {
      final s = SessionAuthenticated(_access('merkez'));
      expect(_redirect('/approvals/9001', session: s).location, isNull);
      expect(_redirect('/notifications', session: s).location, isNull);
      expect(_redirect('/quote-desk', session: s).location, '/home');
      expect(_redirect('/orders', session: s).location, '/home');
    });

    test('geliştirici rotaları yalnızca sahte/dev ortamında', () {
      final s = SessionAuthenticated(_access('sahip'));
      expect(_redirect('/dev', session: s, dev: true).location, isNull);
      expect(_redirect('/dev/gallery', session: s).location, '/home');
    });
  });

  group('Push rotası', () {
    test('izin yoksa /notifications', () {
      final driver = AccessPolicy(_access('sofor'));
      const f = AppFeatures(assistant: true);
      expect(
        RouteAccess.resolvePushRoute('/driver/shipments/5002', driver, f),
        '/driver/shipments/5002',
      );
      expect(
        RouteAccess.resolvePushRoute('/bayi/orders/12001', driver, f),
        '/notifications',
      );
      expect(RouteAccess.resolvePushRoute(null, driver, f), '/notifications');
      expect(
        RouteAccess.resolvePushRoute('http://kötü', driver, f),
        '/notifications',
      );
      final customer = AccessPolicy(_access('talep'));
      expect(
        RouteAccess.resolvePushRoute('/company/requests/3001', customer, f),
        '/company/requests/3001',
      );
      expect(
        RouteAccess.resolvePushRoute(
          '/assistant',
          customer,
          const AppFeatures(),
        ),
        '/notifications',
      );
    });
  });
}
