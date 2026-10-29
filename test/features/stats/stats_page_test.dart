// İstatistik sayfası (spec R1 §3.3, tasarım v2 §7.12): dönem seçici (istenen dönem, `?period=`), tek
// plaka (başlık ölçüsü, fark, okumalar), aylık grafik (Tutar / Litre / Sipariş, bu ay etiketi, baloncuk,
// "Tablo olarak göster"), sıralı çubuklar, bayi / saha / müşteri bölümleri, %100'de duran kullanım
// çubukları, paylaş, "Detaylı harcama raporu", aşağı çekip yenileme, önbellekten çevrimdışı açılış, hata /
// yetki / henüz yok durumları; büyük yazıda taşma yok.
import 'package:akaryakitnet/core/network/failure_copy.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/offline/cache_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/stats/api.dart';
import 'package:akaryakitnet/features/stats/copy.dart';
import 'package:akaryakitnet/features/stats/presentation/charts/bar_chart.dart';
import 'package:akaryakitnet/features/stats/presentation/charts/mix_chart.dart';
import 'package:akaryakitnet/features/stats/presentation/stats_format.dart';
import 'package:akaryakitnet/features/stats/presentation/widgets/stats_atoms.dart';
import 'package:akaryakitnet/features/stats/stats_fake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import 'support/stats_app.dart';

/// Bölüm (başlığından).
Finder _section(String title) =>
    find.byWidgetPredicate((w) => w is StatsSection && w.title == title);

/// Bölüm başlığı (plakadaki okuma etiketiyle karışmaz).
Finder _header(String title) =>
    find.byWidgetPredicate((w) => w is SectionHeader && w.title == title);

/// Sayfanın tek plakasındaki yazı (başlık ya da okuma etiketi).
Finder _kpi(String label) =>
    find.descendant(of: find.byType(AknPlate), matching: find.text(label));

/// Aylık grafikte yazan metin.
Finder _inMonthly(String text) =>
    find.descendant(of: find.byType(StatsBarChart), matching: find.text(text));

Future<void> _tapIn(WidgetTester tester, Finder scope, String text) async {
  final f = find.descendant(of: scope, matching: find.text(text));
  await revealIn(tester, f);
  await tester.tap(f);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Sayfanın sonuna kadar kaydırır (her adımda çizim hatası birikirse test düşer).
Future<void> _scrollThrough(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.drag(verticalScrollable, const Offset(0, -450));
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  // Gerçek yüz (Mona Sans): seçicinin sığma kararı ve sığma ölçüleri cihazdaki gibi.
  setUpAll(loadRealFonts);

  group('bayi', () {
    testWidgets('sahip: KPI\'lar ve bölümler; dönem değişince yeni dönem istenir', (
      tester,
    ) async {
      final probe = StatsProbe();
      final app = await StatsTestApp.start(
        tester,
        persona: 'sahip',
        location: '/stats',
        probe: probe,
      );
      expect(find.text(StatsCopy.pageTitle), findsOneWidget);
      for (final p in StatsPeriod.values) {
        expect(find.text(p.label), findsOneWidget, reason: p.key);
      }
      expect(probe.bayi, ['month']);
      // Tek plaka; paylaş düğmesi.
      expect(find.byType(AknPlate), findsOneWidget);
      expect(find.byIcon(PhosphorIconsRegular.export), findsOneWidget);
      for (final kpi in [
        StatsCopy.kpiSales,
        StatsCopy.kpiLiters,
        StatsCopy.kpiActiveCustomers,
      ]) {
        expect(_kpi(kpi), findsOneWidget, reason: kpi);
      }
      final d = app.container.read(bayiStatsProvider(StatsPeriod.month)).data!;
      for (final title in [
        StatsCopy.monthlyTitle,
        StatsCopy.mixTitle,
        StatsCopy.funnelTitle,
        StatsCopy.deliveriesTitle,
        StatsCopy.collectionsTitle,
        if (d.topCustomers.isNotEmpty) StatsCopy.topCustomersTitle,
        StatsCopy.teamTitle,
        if ((d.risk?.nearLimitCount ?? 0) > 0) StatsCopy.riskTitle,
      ]) {
        await revealIn(tester, _header(title));
        expect(_header(title), findsOneWidget, reason: title);
      }
      // Maliyet / kâr yok: yöntem notu.
      await revealIn(tester, find.text(StatsCopy.methodology));

      // Dönem: sabit seçici, yeni dönem istenir; dönem satırı değişir ("1–30 Eylül, güncellendi …").
      String caption(StatsPeriod p) {
        final x = app.container.read(bayiStatsProvider(p)).data!.period;
        return StatsFmt.rangeShort(x.from, x.to);
      }

      await tester.tap(find.text(StatsPeriod.lastMonth.label));
      await StatsTestApp.settle(tester);
      expect(probe.bayi, ['month', 'lastMonth']);
      // v4 §5 12: dönem yalnızca plakanın başlığında (üstte ayrı dönem satırı yok); "güncellendi"
      // sayfanın sonundaki notta. v4 tur 2 (A11): fark çipi varken karşılaştırmanın adı dönem
      // satırında ("1–30 Eylül · önceki aya göre").
      expect(
        find.descendant(
          of: find.byType(AknPlate),
          matching: find.textContaining(caption(StatsPeriod.lastMonth)),
        ),
        findsOneWidget,
        reason: 'plaka başlığındaki dönem',
      );
      final chip = find.descendant(
        of: find.byType(AknPlate),
        matching: find.byType(AknDeltaChip),
      );
      if (chip.evaluate().isNotEmpty) {
        expect(
          _kpi(
            '${caption(StatsPeriod.lastMonth)} · '
            '${StatsPeriod.lastMonth.compareBrief}',
          ),
          findsOneWidget,
          reason: 'çipin neye göre olduğu yanında',
        );
      }
      expect(
        find.textContaining(caption(StatsPeriod.lastMonth)),
        findsOneWidget,
        reason: 'dönem bir kez yazılır',
      );
      expect(find.textContaining(', güncellendi '), findsNothing);
      // Önceki döneme dönünce önbellekteki sonuç hemen görünür (yeniden istenmez).
      await tester.tap(find.text(StatsPeriod.month.label));
      await StatsTestApp.settle(tester);
      expect(probe.bayi, ['month', 'lastMonth']);
      expect(
        find.descendant(
          of: find.byType(AknPlate),
          matching: find.textContaining(caption(StatsPeriod.month)),
        ),
        findsOneWidget,
      );
      await revealIn(tester, find.textContaining(RegExp(r'^Güncellendi \d')));
      await app.finish(tester);
    });

    testWidgets(
      '(i) "Nasıl hesaplanır?" kart metinlerini ve yöntem notunu açar',
      (tester) async {
        final app = await StatsTestApp.start(
          tester,
          persona: 'sahip',
          location: '/stats',
        );
        // v4 §4: destenin ⋯ menüsündeki "Nasıl hesaplanır?" /stats'ta (i) oldu.
        await tester.tap(find.bySemanticsLabel(StatsCopy.deckHowTo));
        await StatsTestApp.settle(tester);
        expect(find.byType(AppSheet), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AppSheet),
            matching: find.text(StatsCopy.howSales),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(AppSheet),
            matching: find.text(StatsCopy.methodology),
          ),
          findsOneWidget,
        );
        await app.finish(tester);
      },
    );

    testWidgets('?period=year: Bu yıl seçili, 12 ay', (tester) async {
      final probe = StatsProbe();
      final app = await StatsTestApp.start(
        tester,
        persona: 'mudur',
        location: '/stats?period=year',
        probe: probe,
      );
      expect(probe.bayi, ['year']);
      expect(
        app.container.read(bayiStatsProvider(StatsPeriod.year)).data!.months,
        hasLength(12),
      );
      await revealIn(tester, find.text(StatsCopy.lastTwelveMonths));
      await app.finish(tester);
    });

    testWidgets(
      'aylık grafik: bu ay etiketi; Tutar / Litre / Sipariş; dokununca baloncuk; tablo',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final app = await StatsTestApp.start(
          tester,
          persona: 'sahip',
          location: '/stats',
        );
        final months = app.container
            .read(bayiStatsProvider(StatsPeriod.month))
            .data!
            .months;
        final last = months.last;
        await revealIn(tester, find.byType(StatsBarChart));
        // Doğrudan etiket yalnızca bu aya: "bu ay" + kısa değer.
        expect(_inMonthly(StatsCopy.thisMonth), findsOneWidget);
        expect(_inMonthly(StatsFmt.compactNumber(last.amount)), findsOneWidget);
        // v4 §5 12: tek sütun etiketi (en yüksek ayın ve tahminin etiketi yok; tahmin kartın
        // altındaki cümlede) ve tek dolu iz (dönem seçicisi; ölçü sekmeleri metin).
        final chartTexts = [
          for (final e
              in find
                  .descendant(
                    of: find.byType(StatsBarChart),
                    matching: find.byType(Text),
                  )
                  .evaluate())
            (e.widget as Text).data ?? '',
        ]..removeWhere((t) => months.any((m) => m.shortLabel == t));
        expect(
          chartTexts,
          unorderedEquals([
            StatsCopy.thisMonth,
            StatsFmt.compactNumber(last.amount),
          ]),
        );
        expect(
          find.byWidgetPredicate((w) => w is AknSegmented),
          findsOneWidget,
        );

        final monthly = _section(StatsCopy.monthlyTitle);
        await _tapIn(tester, monthly, StatsCopy.metricLiters);
        expect(_inMonthly(StatsFmt.compactNumber(last.liters)), findsOneWidget);
        await _tapIn(tester, monthly, StatsCopy.metricOrders);
        expect(_inMonthly(StatsFmt.count(last.orders)), findsWidgets);
        await _tapIn(tester, monthly, StatsCopy.metricAmount);

        // Bir aya dokununca baloncuk o ayın tam değerini yazar (2 sn).
        final first = months.first;
        final bubble = '${first.longLabel}: ${StatsFmt.money(first.amount)}';
        final bar = find.bySemanticsLabel(
          '${first.longLabel} satış ${StatsFmt.moneySpoken(first.amount)}',
        );
        await revealIn(tester, bar);
        expect(find.text(bubble), findsNothing);
        await tester.tap(bar);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text(bubble), findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        expect(find.text(bubble), findsNothing);

        // "Tablo" (hayalet düğme; ekran okuyucuda "Tablo olarak göster"): ay | değer satırları;
        // geri dönülebilir.
        expect(find.bySemanticsLabel(StatsCopy.tableShow), findsOneWidget);
        await _tapIn(tester, monthly, StatsCopy.tableShort);
        expect(find.byType(StatsBarChart), findsNothing);
        expect(find.text(first.longLabel), findsOneWidget);
        expect(find.text(StatsFmt.money(first.amount)), findsOneWidget);
        await _tapIn(tester, monthly, StatsCopy.chartShort);
        expect(find.byType(StatsBarChart), findsOneWidget);
        semantics.dispose();
        await app.finish(tester);
      },
    );

    testWidgets(
      'limit riski: %100\'ü geçen kullanımda çubuk dolu, "Limit aşıldı"',
      (tester) async {
        final app = await StatsTestApp.start(
          tester,
          persona: 'sahip',
          location: '/stats',
          setup: (s) => s.get('stats/bayi', (req) {
            final body = StatsFake.handleBayi(req);
            body['risk'] = {
              'nearLimitCount': 2,
              'nearLimit': [
                {
                  'customerId': 7,
                  'title': 'Aşım Ticaret Ltd.',
                  'usageRate': 1.25,
                },
                {
                  'customerId': 8,
                  'title': 'Sınırda Lojistik',
                  'usageRate': 0.86,
                },
              ],
            };
            return body;
          }),
        );
        await revealIn(tester, _header(StatsCopy.riskTitle));
        final list = tester.widget<StatsRankedList>(
          find.descendant(
            of: _section(StatsCopy.riskTitle),
            matching: find.byType(StatsRankedList),
          ),
        );
        expect(list.items.map((i) => i.fraction), [1.0, 0.86]);
        expect(list.threshold, StatsCopy.warnLevel);
        await revealIn(tester, find.text(StatsCopy.limitOver));
        expect(find.text(StatsCopy.limitNear), findsOneWidget);
        await app.finish(tester);
      },
    );

    testWidgets('saha: portföy KPI\'ı; tahsilat, sevkiyat, risk yok', (
      tester,
    ) async {
      final app = await StatsTestApp.start(
        tester,
        persona: 'saha',
        location: '/stats',
      );
      expect(_kpi(StatsCopy.cardSalesOwn), findsOneWidget);
      final d = app.container.read(bayiStatsProvider(StatsPeriod.month)).data!;
      if (d.topCustomers.isNotEmpty) {
        await revealIn(tester, _header(StatsCopy.topCustomersOwnTitle));
      }
      await revealIn(tester, _header(StatsCopy.cardOwnForms));
      await revealIn(tester, find.text(StatsCopy.methodology));
      for (final hidden in [
        StatsCopy.collectionsTitle,
        StatsCopy.deliveriesTitle,
        StatsCopy.riskTitle,
        StatsCopy.teamTitle,
      ]) {
        expect(find.text(hidden), findsNothing, reason: hidden);
      }
      await app.finish(tester);
    });

    testWidgets('aşağı çekince yenilenir', (tester) async {
      final probe = StatsProbe();
      final app = await StatsTestApp.start(
        tester,
        persona: 'sahip',
        location: '/stats',
        probe: probe,
      );
      await tester.fling(_kpi(StatsCopy.kpiSales), const Offset(0, 400), 1000);
      await tester.pump();
      await StatsTestApp.settle(tester);
      expect(probe.bayi, ['month', 'month']);
      await app.finish(tester);
    });
  });

  group('müşteri', () {
    testWidgets('musteri: KPI\'lar, bölümler ve "Detaylı harcama raporu"', (
      tester,
    ) async {
      final probe = StatsProbe();
      final app = await StatsTestApp.start(
        tester,
        persona: 'musteri',
        location: '/stats',
        probe: probe,
      );
      expect(probe.customer, ['month']);
      expect(probe.bayi, isEmpty);
      for (final kpi in [
        StatsCopy.kpiSpending,
        StatsCopy.kpiLitersCustomer,
        StatsCopy.readoutAverage,
      ]) {
        expect(_kpi(kpi), findsOneWidget, reason: kpi);
      }
      final d = app.container
          .read(customerStatsProvider(StatsPeriod.month))
          .data!;
      // v4 tur 2 (A11): çip varken dönem satırı kısa karşılaştırmayla biter ("1–29 Ekim · geçen
      // aya göre"); uzun cümle plakada yazmaz (çipin yanında "göre" alt satırda yalnız kalırdı).
      final chip = find.descendant(
        of: find.byType(AknPlate),
        matching: find.byType(AknDeltaChip),
      );
      if (chip.evaluate().isNotEmpty) {
        final range = d.period.from == null
            ? d.period.title
            : StatsFmt.rangeShort(d.period.from, d.period.to);
        expect(
          _kpi('$range · ${StatsPeriod.month.compareBrief}'),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(AknPlate),
            matching: find.textContaining(StatsPeriod.month.compareShort),
          ),
          findsNothing,
        );
      }
      for (final title in [
        StatsCopy.monthlyTitle,
        if (d.products.isNotEmpty) StatsCopy.mixTitle,
        if (d.months.where((m) => m.unitPrice != null).length >= 2)
          StatsCopy.unitPriceTitle,
        if (d.stations.isNotEmpty) StatsCopy.stationsTitle,
        if (d.deliveryPoints.isNotEmpty) StatsCopy.pointsTitle,
        StatsCopy.orderStatusTitle,
        if (d.limits.isNotEmpty) StatsCopy.limitsTitle,
      ]) {
        await revealIn(tester, _header(title));
        expect(_header(title), findsOneWidget, reason: title);
      }
      final report = find.text(StatsCopy.spendingReport);
      await revealIn(tester, report);
      await tester.tap(report);
      await StatsTestApp.settle(tester);
      expect(find.text('stub:/spending'), findsOneWidget);
      await app.finish(tester);
    });

    testWidgets('talep eden: yetki yok ekranı, istek yok', (tester) async {
      final probe = StatsProbe();
      final app = await StatsTestApp.start(
        tester,
        persona: 'talep',
        location: '/stats',
        probe: probe,
      );
      expect(find.text(FailureCopy.forbidden), findsOneWidget);
      expect(find.text(StatsPeriod.month.label), findsNothing);
      expect(probe.total, 0);
      await app.finish(tester);
    });
  });

  group('durumlar', () {
    testWidgets('sunucu hatası: hata ekranı, "Tekrar dene" ile gelir', (
      tester,
    ) async {
      var failing = true;
      final app = await StatsTestApp.start(
        tester,
        persona: 'sahip',
        location: '/stats',
        probe: StatsProbe(fail: () => failing ? FakeResponse.server() : null),
      );
      expect(find.text(FailureCopy.retry), findsOneWidget);
      expect(_kpi(StatsCopy.kpiSales), findsNothing);
      failing = false;
      await tester.tap(find.text(FailureCopy.retry));
      await StatsTestApp.settle(tester);
      expect(_kpi(StatsCopy.kpiSales), findsOneWidget);
      await app.finish(tester);
    });

    testWidgets('uç henüz yok (404): bilgilendirme', (tester) async {
      final app = await StatsTestApp.start(
        tester,
        persona: 'musteri',
        location: '/stats',
        probe: StatsProbe(fail: FakeResponse.notFound),
      );
      expect(find.text('İstatistikler henüz hazır değil'), findsOneWidget);
      await app.finish(tester);
    });

    testWidgets('çevrimdışı: dönemin son sonucu "Son güncelleme" ile', (
      tester,
    ) async {
      final store = MemoryCacheStore();
      final first = await StatsTestApp.start(
        tester,
        persona: 'musteri',
        location: '/stats',
        overrides: [cacheStoreProvider.overrideWithValue(store)],
      );
      expect(find.textContaining('Son güncelleme'), findsNothing);
      await first.finish(tester);

      final second = await StatsTestApp.start(
        tester,
        persona: 'musteri',
        location: '/stats',
        overrides: [cacheStoreProvider.overrideWithValue(store)],
        setup: (s) => s.failureMode = FakeFailureMode.offline,
      );
      expect(_kpi(StatsCopy.kpiSpending), findsOneWidget);
      expect(find.textContaining('Son güncelleme'), findsOneWidget);
      // Önbelleği olmayan dönem: çevrimdışı hata ekranı.
      await tester.tap(find.text(StatsPeriod.year.label));
      await StatsTestApp.settle(tester);
      expect(find.text(FailureCopy.retry), findsOneWidget);
      await second.finish(tester);
    });

    testWidgets('yükleme: iskelet', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await StatsTestApp.start(
        tester,
        persona: 'sahip',
        location: '/stats',
        setup: (s) => s
          ..latencyEnabled = true
          ..minLatency = const Duration(seconds: 30)
          ..maxLatency = const Duration(seconds: 31),
      );
      expect(find.bySemanticsLabel(StatsCopy.deckLoading), findsOneWidget);
      expect(_kpi(StatsCopy.kpiSales), findsNothing);
      // Bekleyen sahte gecikme biter, veri gelir.
      await tester.pump(const Duration(seconds: 32));
      await StatsTestApp.settle(tester);
      expect(_kpi(StatsCopy.kpiSales), findsOneWidget);
      semantics.dispose();
      await app.finish(tester);
    });
  });

  group('büyük yazı ve koyu tema: taşma yok', () {
    for (final persona in ['sahip', 'saha', 'musteri']) {
      for (final (tag, brightness, scale) in [
        ('2,0× koyu', Brightness.dark, 2.0),
        ('1,0× açık', Brightness.light, 1.0),
      ]) {
        testWidgets('$persona $tag, 320 dp', (tester) async {
          final app = await StatsTestApp.start(
            tester,
            persona: persona,
            location: '/stats',
            brightness: brightness,
            textScale: scale,
            size: const Size(320, 640),
          );
          await _scrollThrough(tester);
          // Çizim hatası (taşma) olursa test kendiliğinden ayrıntısıyla düşer.
          await app.finish(tester);
        });
      }
    }
  });
}
