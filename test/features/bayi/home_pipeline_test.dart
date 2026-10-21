// Bayi ana sayfası tasarım v2 parçaları: sipariş hattı (§6.17; "sıra sizde" durakları role göre,
// dokununca süzülmüş liste, büyük yazıda dikey liste), acil satır ve "Teklif ver", Tüpraş şeridi
// (§6.18; yetki yoksa gizli), Türkçe tamlayan eki.
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/features/bayi/presentation/desk/quote_desk_page.dart';
import 'package:akaryakitnet/features/bayi/presentation/home/home_atoms.dart';
import 'package:akaryakitnet/features/bayi/presentation/home/order_pipeline.dart';
import 'package:akaryakitnet/features/field/api.dart';
import 'package:akaryakitnet/features/field/field_fake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bayi_app.dart';

void main() {
  group('trGenitive', () {
    test('ünlü uyumu ve kaynaştırma', () {
      expect(trGenitive('Körfez Nakliyat'), 'Körfez Nakliyat’ın');
      expect(
        trGenitive('Körfez Nakliyat ve Ticaret'),
        'Körfez Nakliyat ve Ticaret’in',
      );
      expect(trGenitive('Ege Tarım Kooperatifi'), 'Ege Tarım Kooperatifi’nin');
      expect(trGenitive('Kuzey Enerji'), 'Kuzey Enerji’nin');
      expect(trGenitive('Demir Petrol'), 'Demir Petrol’ün');
      expect(trGenitive('Ankara Saat'), 'Ankara Saat’in');
      expect(trGenitive('Su Ürünleri Koru'), 'Su Ürünleri Koru’nun');
    });

    test('kısaltmalar okunuşuna göre', () {
      expect(trGenitive('Anadolu Lojistik A.Ş.'), 'Anadolu Lojistik A.Ş.’nin');
      expect(
        trGenitive('Marmara İnşaat Taahhüt Ltd. Şti.'),
        'Marmara İnşaat Taahhüt Ltd. Şti.’nin',
      );
    });
  });

  test('sıra sizde durakları rol ön ayarına göre', () {
    expect(pipelineYourMoves(RolePreset.owner), {'Finans', 'Teklif', 'Plan'});
    expect(pipelineYourMoves(RolePreset.orderDesk), {'Teklif'});
    expect(pipelineYourMoves(RolePreset.finance), {'Finans'});
    expect(pipelineYourMoves(RolePreset.dispatch), {'Plan'});
    expect(pipelineYourMoves(RolePreset.viewer), isEmpty);
  });

  testWidgets(
    'sahip: altı durak, sıra sizde anonsu, Teklif durağı masayı açar',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'sahip',
        location: '/home-bayi',
      );
      final handle = tester.ensureSemantics();
      final pipeline = tester.widget<OrderPipeline>(find.byType(OrderPipeline));
      expect(pipeline.stops.map((s) => s.label), [
        'Finans',
        'Teklif',
        'Karar',
        'Plan',
        'Yolda',
        'Teslim',
      ]);
      final teklif = pipeline.stops.firstWhere((s) => s.label == 'Teklif');
      expect(teklif.kind, PipelineStopKind.yourMove);
      expect(
        find.bySemanticsLabel(RegExp(r'^Teklif, \d+ sipariş, sıra sizde$')),
        findsOneWidget,
      );
      expect(
        pipeline.stops.firstWhere((s) => s.label == 'Karar').kind,
        PipelineStopKind.waiting,
      );
      handle.dispose();
      await tester.tap(find.text('Teklif').first);
      await BayiTestApp.settle(tester);
      expect(find.byType(QuoteDeskPage), findsOneWidget);
      await app.finish(tester);
    },
  );

  testWidgets('sahip: acil satır "Teklif ver" masayı o cariyle açar', (
    tester,
  ) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'sahip',
      location: '/home-bayi',
    );
    expect(find.byType(PipelineUrgentLine), findsOneWidget);
    expect(find.textContaining('teklif süresi'), findsOneWidget);
    await scrollTap(tester, find.text('Teklif ver'));
    final desk = tester.widget<QuoteDeskPage>(find.byType(QuoteDeskPage));
    expect(desk.initialCustomerId, isNotNull);
    await app.finish(tester);
  });

  testWidgets('sahip: Tüpraş şeridi saha fiyat bağlamından gelir', (
    tester,
  ) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'sahip',
      location: '/home-bayi',
      setup: (h) => registerFieldFakes(h.server),
    );
    await reveal(tester, find.text('Tüpraş fiyatları'));
    await BayiTestApp.settle(tester);
    await reveal(tester, find.text('Kurşunsuz 95'));
    expect(find.byType(TuprasStrip), findsOneWidget);
    expect(find.text('Tüpraş fiyatları'), findsOneWidget);
    expect(find.text('Motorin'), findsWidgets);
    expect(find.text('Kurşunsuz 95'), findsOneWidget);
    await app.finish(tester);
  });

  testWidgets('sipariş masası: saha yetkisi yok, Tüpraş şeridi çizilmez', (
    tester,
  ) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'siparis',
      location: '/home-bayi',
    );
    final pipeline = tester.widget<OrderPipeline>(find.byType(OrderPipeline));
    expect(
      pipeline.stops
          .where((s) => s.kind == PipelineStopKind.yourMove)
          .map((s) => s.label),
      ['Teklif'],
    );
    expect(find.text('Tüpraş fiyatları'), findsNothing);
    await app.finish(tester);
  });

  testWidgets('yazı 2,0×: hat dikey satır listesine döner, taşma yok', (
    tester,
  ) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'sahip',
      location: '/home-bayi',
      textScale: 2,
      size: const Size(360, 3000),
    );
    expect(find.byType(OrderPipeline), findsOneWidget);
    expect(find.text('Finans'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await app.finish(tester);
  });
}
