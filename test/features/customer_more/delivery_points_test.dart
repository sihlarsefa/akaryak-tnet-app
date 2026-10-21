import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/auth/permissions.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/models/me_access.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/customer_more/copy.dart';
import 'package:akaryakitnet/features/customer_more/data/customer_more_repository.dart';
import 'package:akaryakitnet/features/customer_more/data/delivery_point.dart';
import 'package:akaryakitnet/features/customer_more/data/location_service.dart';
import 'package:akaryakitnet/features/customer_more/data/window_time.dart';
import 'package:akaryakitnet/features/customer_more/presentation/delivery_points/delivery_points_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cm_test_utils.dart';

void main() {
  test(
    'TimeSpan gidiş-dönüş: 24:00 "1.00:00:00" gider, sunucu 23:59:59 döner',
    () async {
      final env = await CmEnv.create();
      addTearDown(env.dispose);
      final repo = env.container.read(customerMoreRepositoryProvider);
      final id = await repo.saveDeliveryPoint(
        const DeliveryPointDraft(
          name: 'Gece Deposu',
          city: 'Kocaeli',
          district: 'Gebze',
          address: 'OSB 3. Cadde',
          windowStart: WindowTime(7 * 60 + 30),
          windowEnd: WindowTime.endOfDay,
          tankCapacityLiters: 25000,
        ),
      );
      expect(env.requests.last.method, 'POST');
      final raw = await repo.deliveryPointsJson();
      final row = (raw! as List).cast<Map<String, dynamic>>().firstWhere(
        (d) => d['id'] == id,
      );
      expect(row['deliveryWindowStart'], '07:30:00');
      expect(row['deliveryWindowEnd'], '23:59:59');
      final point = CustomerMoreRepository.parseDeliveryPoints(
        raw,
      ).firstWhere((d) => d.id == id);
      expect(point.windowEnd!.isEndOfDay, isTrue);
      expect(point.window, '07:30–24:00');
      // Kaydedip yeniden okumak değeri değiştirmez.
      await repo.saveDeliveryPoint(DeliveryPointDraft.of(point));
      final again = CustomerMoreRepository.parseDeliveryPoints(
        await repo.deliveryPointsJson(),
      ).firstWhere((d) => d.id == id);
      expect(again.window, '07:30–24:00');
    },
  );

  testWidgets('liste: pencere, tank, sorumlu, konum bilgisi', (tester) async {
    final env = (await tester.runAsync(CmEnv.create))!;
    addTearDown(env.dispose);
    await pumpCmApp(tester, env, location: '/delivery-points');
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(DeliveryPointCard), findsNWidgets(2));
    expect(find.text('Pendik Lojistik Merkezi'), findsOneWidget);
    expect(find.text('08:00–18:00'), findsOneWidget);
    expect(find.textContaining('Tank'), findsWidgets);
    expect(find.text('Yeni teslimat noktası'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('çevrimdışı: liste önbellekten, "Son güncelleme" notu', (
    tester,
  ) async {
    final env = (await tester.runAsync(CmEnv.create))!;
    addTearDown(env.dispose);
    final router = await pumpCmApp(tester, env, location: '/delivery-points');
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(DeliveryPointCard), findsNWidgets(2));
    router.go('/home');
    await pumpFor(tester, const Duration(milliseconds: 600));

    env.harness.server.failureMode = FakeFailureMode.offline;
    router.go('/delivery-points');
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(DeliveryPointCard), findsNWidgets(2));
    expect(find.textContaining('Son güncelleme'), findsOneWidget);
    await finish(tester);
  });

  testWidgets(
    'haritasız mod: izin ön sayfası, "Bulunduğum konumu kullan", 50 m üstü uyarı',
    (tester) async {
      final location = FakeLocationService(
        fix: const LocationFix(
          latitude: 40.80001,
          longitude: 29.43002,
          accuracyMeters: 85,
        ),
      );
      final env = (await tester.runAsync(
        () => CmEnv.create(location: location),
      ))!;
      addTearDown(env.dispose);
      await pumpCmApp(tester, env, location: '/delivery-points/new');
      await pumpFor(tester, const Duration(milliseconds: 600));

      await scrollTo(tester, find.text(CmCopy.useMyLocation));
      await tester.tap(find.text(CmCopy.useMyLocation));
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text(CmCopy.locationPrimerTitle), findsOneWidget);
      await tester.tap(find.text('Devam'));
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(location.requests, 1);
      expect(find.text('±85 m'), findsOneWidget);
      expect(find.text('Konum doğruluğu düşük'), findsOneWidget);
      expect(find.text(CmCopy.openInMaps), findsOneWidget);

      // Hassas konum (≤ 50 m): uyarı yok.
      location.fix = const LocationFix(
        latitude: 40.8,
        longitude: 29.43,
        accuracyMeters: 9,
      );
      await tester.tap(find.text(CmCopy.useMyLocation));
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(find.text('±9 m'), findsOneWidget);
      expect(find.text('Konum doğruluğu düşük'), findsNothing);
      await finish(tester);
    },
  );

  testWidgets('yeni nokta: il / ilçe listeden, saat aralığı ve kayıt', (
    tester,
  ) async {
    final env = (await tester.runAsync(CmEnv.create))!;
    addTearDown(env.dispose);
    await pumpCmApp(tester, env, location: '/delivery-points/new');
    await pumpFor(tester, const Duration(milliseconds: 600));

    await tester.enterText(find.byType(TextFormField).first, 'Gebze Depo');
    await tester.tap(find.bySemanticsLabel(RegExp(r'^İl, zorunlu')));
    await pumpFor(tester, const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextField).last, 'koca');
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.text('Kocaeli').last);
    await pumpFor(tester, const Duration(milliseconds: 600));
    await tester.tap(find.bySemanticsLabel(RegExp(r'^İlçe, zorunlu')));
    await pumpFor(tester, const Duration(milliseconds: 600));
    await tester.tap(find.text('Gebze').last);
    await pumpFor(tester, const Duration(milliseconds: 600));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Açık adres *'),
      'Güzeller OSB 4. Cadde No:7',
    );
    await scrollTo(tester, find.text('Gün sonuna kadar (24:00)'));
    await tester.tap(find.text('Gün sonuna kadar (24:00)'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.text('Noktayı ekle'));
    await pumpFor(tester, const Duration(seconds: 1));

    final created = env.world.deliveryPoints.lastWhere(
      (d) => d['name'] == 'Gebze Depo',
    );
    expect(created['city'], 'Kocaeli');
    expect(created['district'], 'Gebze');
    expect(created['windowStart'], '08:00');
    expect(created['windowEnd'], '24:00');
    final post = env.requests.lastWhere(
      (r) => r.method == 'POST' && r.path == 'customers/me/delivery-points',
    );
    expect(post, isNotNull);
    await finish(tester);
  });

  testWidgets('pasifleştirme onay ister (Siler yetkisiyle)', (tester) async {
    final env = (await tester.runAsync(
      () => CmEnv.create(
        overrides: [
          accessPolicyProvider.overrideWith((ref) {
            final me = ref.watch(sessionControllerProvider).access;
            if (me == null) return AccessPolicy.signedOut;
            return AccessPolicy(
              MeAccess.fromJson({
                ...me.toJson(),
                'pages': [
                  ...me.pages,
                  '${Pg.customerDeliveryPoints}:${Perm.delete}',
                ],
              }),
            );
          }),
        ],
      ),
    ))!;
    addTearDown(env.dispose);
    // Sahte personanın Siler yetkisi yok; sunucu kuralını test için gevşet.
    env.harness.server.post(
      'customers/me/delivery-points/{id:int}/deactivate',
      (req) {
        env.world.deliveryPoint(req.intParam('id'))!['isActive'] = false;
        return {'message': 'Teslimat noktası pasifleştirildi.'};
      },
    );
    await pumpCmApp(tester, env, location: '/delivery-points/1002');
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.widgetWithText(AknButton, 'Pasifleştir'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Noktayı pasifleştirelim mi?'), findsOneWidget);
    expect(env.world.deliveryPoint(1002)!['isActive'], isNot(false));
    await tester.tap(find.widgetWithText(AknButton, 'Pasifleştir').last);
    await pumpFor(tester, const Duration(seconds: 1));
    expect(env.world.deliveryPoint(1002)!['isActive'], isFalse);
    await finish(tester);
  });

  test('sunucu doğrulama hatası Türkçe mesajla döner', () async {
    final env = await CmEnv.create();
    addTearDown(env.dispose);
    env.harness.server.failureMode = FakeFailureMode.none;
    final repo = env.container.read(customerMoreRepositoryProvider);
    await expectLater(
      repo.saveDeliveryPoint(
        const DeliveryPointDraft(name: 'X', city: 'A', district: 'B'),
      ),
      throwsA(
        predicate(
          (e) => e.toString().contains('İl, ilçe ve açık adres zorunlu'),
        ),
      ),
    );
  });
}
