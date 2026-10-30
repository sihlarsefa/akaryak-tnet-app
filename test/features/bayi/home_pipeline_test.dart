// Bayi ana sayfası v4 "Sade" parçaları (§5 03): "Sıra sizde" kartındaki sipariş hattı (Finans · Teklif
// · Müşteri · Plan · Yolda · Teslim; sayılar Siparişler segmentleriyle aynı; sıra sizdeki duraklar Pas;
// Yolda mürekkep tır; her durak süzülmüş listeyi açar; büyük yazıda dikey liste), Tüpraş kartı (tek
// kart, uyarı kuyusu yok; yetki yoksa gizli), Türkçe tamlayan ve saat ekleri.
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/application/orders_controller.dart';
import 'package:akaryakitnet/features/bayi/copy.dart';
import 'package:akaryakitnet/features/bayi/data/bayi_repository.dart';
import 'package:akaryakitnet/features/bayi/data/order_models.dart';
import 'package:akaryakitnet/features/bayi/presentation/desk/quote_desk_page.dart';
import 'package:akaryakitnet/features/bayi/presentation/home/home_atoms.dart';
import 'package:akaryakitnet/features/bayi/presentation/home/order_pipeline.dart';
import 'package:akaryakitnet/features/bayi/presentation/orders/orders_page.dart';
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

  test('saatin yönelme eki okunuşuna göre', () {
    expect(timeDative('21:00'), "21:00'e");
    expect(timeDative('09:17'), "09:17'ye");
    expect(timeDative('10:30'), "10:30'a");
    expect(timeDative('16:50'), "16:50'ye");
    expect(timeDative('10:00'), "10:00'a");
    expect(timeDative('14:45'), "14:45'e");
  });

  test('sıra sizde durakları rol ön ayarına göre', () {
    expect(pipelineYourMoves(RolePreset.owner), {'Finans', 'Teklif', 'Plan'});
    // Roller v5 İkmal birimi: teklif ve sevkiyat planı.
    expect(pipelineYourMoves(RolePreset.supply), {'Teklif', 'Plan'});
    expect(pipelineYourMoves(RolePreset.orderDesk), {'Teklif'});
    expect(pipelineYourMoves(RolePreset.finance), {'Finans'});
    expect(pipelineYourMoves(RolePreset.dispatch), {'Plan'});
    expect(pipelineYourMoves(RolePreset.viewer), isEmpty);
  });

  testWidgets(
    'sahip: altı durak, sayılar Siparişler segmentleriyle aynı; Yolda turuncu değil',
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
        'Müşteri',
        'Plan',
        'Yolda',
        'Teslim',
      ]);
      late BayiOrderCounts counts;
      await tester.runAsync(
        () async => counts = await app.container
            .read(bayiRepositoryProvider)
            .orderCounts(),
      );
      int count(String label) =>
          pipeline.stops.firstWhere((s) => s.label == label).count;
      expect(count('Finans'), counts.of(BayiOrderSegment.financeHeld));
      expect(
        count('Teklif'),
        counts.of(BayiOrderSegment.awaitingQuote) +
            counts.of(BayiOrderSegment.revisionRequested),
      );
      expect(count('Müşteri'), counts.of(BayiOrderSegment.awaitingCustomer));
      expect(count('Plan'), counts.of(BayiOrderSegment.toPlan));
      expect(count('Yolda'), counts.of(BayiOrderSegment.inTransit));
      expect(count('Teslim'), counts.of(BayiOrderSegment.reported));
      final teklif = pipeline.stops.firstWhere((s) => s.label == 'Teklif');
      expect(teklif.kind, PipelineStopKind.yourMove);
      expect(
        find.bySemanticsLabel(RegExp(r'^Teklif, \d+ sipariş, sıra sizde$')),
        findsOneWidget,
      );
      expect(
        pipeline.stops.firstWhere((s) => s.label == 'Müşteri').kind,
        PipelineStopKind.waiting,
      );
      // Yolda: mürekkep tır (turuncu yok), hale yok.
      final c = tester.element(find.byType(OrderPipeline)).akn;
      final truck = tester.widget<Icon>(
        find.descendant(
          of: find.byType(OrderPipeline),
          matching: find.byIcon(PhosphorIconsRegular.truck),
        ),
      );
      expect(truck.color, anyOf(c.ink, c.dim));
      handle.dispose();
      await app.finish(tester);
    },
  );

  testWidgets('Teklif durağı Teklifler\'i açar', (tester) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'sahip',
      location: '/home-bayi',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(OrderPipeline),
        matching: find.text('Teklif'),
      ),
    );
    await BayiTestApp.settle(tester);
    expect(find.byType(QuoteDeskPage), findsOneWidget);
    await app.finish(tester);
  });

  testWidgets('Müşteri durağı Siparişler\'i "Müşteri kararında" ile açar', (
    tester,
  ) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'sahip',
      location: '/home-bayi',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(OrderPipeline),
        matching: find.text('Müşteri'),
      ),
    );
    await BayiTestApp.settle(tester);
    expect(find.byType(BayiOrdersPage), findsOneWidget);
    expect(
      app.container.read(bayiOrdersProvider).filter.segment,
      BayiOrderSegment.awaitingCustomer,
    );
    await app.finish(tester);
  });

  testWidgets(
    'sahip: Tüpraş tek kart, üç fiyat tek satırda, uyarı kuyusu yok',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'sahip',
        location: '/home-bayi',
        setup: (h) => registerFieldFakes(h.server),
      );
      await reveal(tester, find.text('Tüpraş fiyatları'));
      await BayiTestApp.settle(tester);
      expect(find.byType(TuprasStrip), findsOneWidget);
      expect(find.text('Tüpraş fiyatları'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TuprasStrip),
          matching: find.text('Kurşunsuz 95'),
        ),
        findsOneWidget,
      );
      // Uyarı kuyusu ve "Fiyat gir" yok: o iş "Sıra sizde" kartında.
      expect(
        find.descendant(
          of: find.byType(TuprasStrip),
          matching: find.byType(AknBanner),
        ),
        findsNothing,
      );
      expect(find.text('Fiyat gir'), findsNothing);
      await app.finish(tester);
    },
  );

  testWidgets('sipariş masası: saha yetkisi yok, Tüpraş kartı çizilmez', (
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
    expect(
      find.descendant(
        of: find.byType(OrderPipeline),
        matching: find.text('Finans'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await app.finish(tester);
  });
}
