// Kim neyi görür (spec R1 §3.1): her demo personanın istatistik kapsamı ve `/stats` rotası aynı kuralla.
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/models/app_config.dart';
import 'package:akaryakitnet/core/models/me_access.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/routing/app_routes.dart';
import 'package:akaryakitnet/core/routing/route_access.dart';
import 'package:akaryakitnet/features/stats/api.dart';
import 'package:flutter_test/flutter_test.dart';

final _world = FakeWorld.seeded();

AccessPolicy _policy(String key) =>
    AccessPolicy(MeAccess.fromJson(_world.meAccess(findFakePersona(key)!)));

void main() {
  const expected = {
    // Bayi yönetimi: bayi geneli.
    'sahip': StatsScope.station,
    'mudur': StatsScope.station,
    'finans': StatsScope.station,
    'finansuzman': StatsScope.station,
    'muhasebe': StatsScope.station,
    'satis': StatsScope.station,
    'izleyici': StatsScope.station,
    // Şablonsuz özel rol: rapor yetkisi var, operasyon rolü değil.
    'ozelrol': StatsScope.station,
    // Saha temsilcisi: kendi portföyü.
    'saha': StatsScope.own,
    // Müşteri yönetici ve onaylayan.
    'musteri': StatsScope.customer,
    'onay': StatsScope.customer,
    // Deste yok: talep eden, operasyon ekranları, şoför, merkez.
    'talep': StatsScope.none,
    'siparis': StatsScope.none,
    'sevkiyat': StatsScope.none,
    'sofor': StatsScope.none,
    'depo': StatsScope.none,
    'merkez': StatsScope.none,
  };

  group('kapsam', () {
    for (final e in expected.entries) {
      test('${e.key} → ${e.value.name}', () {
        expect(statsScopeFor(_policy(e.key)), e.value);
      });
    }

    test('her demo persona tabloda', () {
      expect(
        {for (final p in fakePersonas) p.key},
        expected.keys.toSet(),
        reason: 'yeni persona eklenince kapsamı da yazılmalı',
      );
    });

    test('oturum yokken kapsam yok', () {
      expect(statsScopeFor(AccessPolicy.signedOut), StatsScope.none);
    });

    test('sipariş masası rapor yetkisine rağmen desteyi görmez', () {
      final p = _policy('siparis');
      expect(p.can('StationReports'), isTrue);
      expect(statsScopeFor(p), StatsScope.none);
    });
  });

  group('/stats rotası deste kitlesiyle aynı', () {
    const features = AppFeatures(assistant: true);
    for (final key in expected.keys) {
      test(key, () {
        final p = _policy(key);
        expect(
          RouteAccess.isAllowed(AppRoutes.stats, p, features),
          statsScopeFor(p) != StatsScope.none,
        );
        expect(
          RouteAccess.isAllowed('${AppRoutes.stats}?period=year', p, features),
          statsScopeFor(p) != StatsScope.none,
        );
      });
    }

    test('izin yoksa push rotası Bildirimler\'e düşer', () {
      expect(
        RouteAccess.resolvePushRoute(
          AppRoutes.stats,
          _policy('talep'),
          features,
        ),
        AppRoutes.notifications,
      );
      expect(
        RouteAccess.resolvePushRoute(
          AppRoutes.stats,
          _policy('sahip'),
          features,
        ),
        AppRoutes.stats,
      );
    });
  });

  test('kapsam türleri', () {
    expect(StatsScope.station.isBayi, isTrue);
    expect(StatsScope.own.isBayi, isTrue);
    expect(StatsScope.customer.isBayi, isFalse);
    expect(StatsScope.none.isBayi, isFalse);
  });
}
