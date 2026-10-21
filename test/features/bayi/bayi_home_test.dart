// Bayi ana sayfası: yetkiye göre bölümler (yük ne getirirse), yüklenemeyen bölüm, rol ipucu, kurulum
// uyarıları ve bölümlerden gezinme.
import 'dart:async';

import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/application/home_controller.dart';
import 'package:akaryakitnet/features/bayi/application/role_tip.dart';
import 'package:akaryakitnet/features/bayi/copy.dart';
import 'package:akaryakitnet/features/bayi/fake/home_fake.dart';
import 'package:akaryakitnet/features/bayi/presentation/home/home_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bayi_app.dart';

void main() {
  testWidgets(
    'bayi sahibi: teklif, sevkiyat, tahsilat, kurulum bölümleri ve rol ipucu',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'sahip',
        location: '/home-bayi',
      );
      expect(find.byType(DeskSectionView), findsOneWidget);
      expect(
        find.text('Teklif masası tek ekranda'),
        findsOneWidget,
        reason: 'rol ipucu',
      );
      await scrollTap(tester, find.byTooltip('Kapat').first);
      expect(find.text('Teklif masası tek ekranda'), findsNothing);
      expect(app.container.read(bayiRoleTipProvider), isFalse);
      await tester.scrollUntilVisible(
        find.byType(ShipmentsSectionView),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(ShipmentsSectionView), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byType(CollectionsSectionView),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.scrollUntilVisible(
        find.byType(SetupSectionView),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Portalda düzelt'), findsWidgets);
      expect(tester.takeException(), isNull);
      await app.finish(tester);
    },
  );

  testWidgets(
    'depo: sevkiyat bölümü var, tahsilat ve finans yok; ipucu Sevkiyat',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'depo',
        location: '/home-bayi',
      );
      expect(find.text('Sevkiyat panosu'), findsOneWidget);
      expect(find.byType(ShipmentsSectionView), findsOneWidget);
      expect(find.byType(CollectionsSectionView), findsNothing);
      expect(find.byType(FinanceSectionView), findsNothing);
      expect(find.byType(SetupSectionView), findsNothing);
      await app.finish(tester);
    },
  );

  testWidgets(
    'yüklenemeyen bölüm "Bu bölüm yüklenemedi" der; yetkisiz bölüm hiç görünmez',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'muhasebe',
        location: '/home-bayi',
        setup: (h) => h.server.get('home/bayi', (req) {
          final json = bayiHomeJson(req.world, findFakePersona('muhasebe')!);
          (json['sections'] as Map)['collections'] = null;
          json['failedSections'] = ['collections'];
          return json;
        }),
      );
      expect(find.textContaining(BayiCopy.sectionFailed), findsOneWidget);
      expect(find.byType(CollectionsSectionView), findsNothing);
      expect(
        find.byType(ShipmentsSectionView),
        findsNothing,
        reason: 'yetki yok',
      );
      await app.finish(tester);
    },
  );

  testWidgets('tazeleme hatası: içerik kalır, "son güncelleme" görünür', (
    tester,
  ) async {
    var fail = false;
    final app = await BayiTestApp.start(
      tester,
      persona: 'sahip',
      location: '/home-bayi',
      setup: (h) => h.server.get('home/bayi', (req) {
        if (fail) throw FakeResponse.server();
        return bayiHomeJson(req.world, findFakePersona('sahip')!);
      }),
    );
    expect(find.byType(DeskSectionView), findsOneWidget);
    fail = true;
    unawaited(app.container.read(bayiHomeProvider.notifier).refresh());
    await BayiTestApp.settle(tester);
    expect(
      find.byType(DeskSectionView),
      findsOneWidget,
      reason: 'içerik kalır',
    );
    expect(find.textContaining('son güncelleme'), findsOneWidget);
    await app.finish(tester);
  });

  testWidgets('süresi yaklaşan siparişten sipariş ayrıntısına gidilir', (
    tester,
  ) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'mudur',
      location: '/home-bayi',
    );
    final countdown = find.byType(CountdownBadge);
    expect(countdown, findsWidgets);
    await scrollTap(tester, countdown.first);
    expect(find.textContaining('SIP-'), findsWidgets);
    expect(find.text('Teklif'), findsWidgets);
    await app.finish(tester);
  });
}
