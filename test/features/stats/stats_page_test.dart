// İstatistik sayfası (spec R1 §3.3): dönem seçici (istenen dönem, `?period=`), KPI'lar, aylık grafik ve
// Tutar / Litre / Sipariş seçimi, bayi / saha / müşteri bölümleri, "Detaylı harcama raporu", aşağı çekip
// yenileme, önbellekten çevrimdışı açılış, hata / yetki / henüz yok durumları; büyük yazıda taşma yok.
import 'package:akaryakitnet/core/network/failure_copy.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/offline/cache_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/stats/api.dart';
import 'package:akaryakitnet/features/stats/copy.dart';
import 'package:akaryakitnet/features/stats/presentation/charts/bar_chart.dart';
import 'package:akaryakitnet/features/stats/presentation/stats_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stats_app.dart';

/// Bölüm kartı (başlığından).
Finder _section(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(AknCard));

/// Bölüm başlığı (KPI etiketiyle karışmaz: başlıklar `Semantics(header: true)` içindedir).
Finder _header(String title) => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      w.properties.header == true &&
      w.child is Text &&
      (w.child! as Text).data == title,
);

/// KPI kutucuğundaki etiket.
Finder _kpi(String label) =>
    find.descendant(of: find.byType(KpiTile), matching: find.text(label));

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
  group('bayi', () {
    testWidgets(
      'sahip: KPI\'lar ve bölümler; dönem değişince yeni dönem istenir',
      (tester) async {
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
        for (final kpi in [
          StatsCopy.kpiSales,
          StatsCopy.kpiLiters,
          StatsCopy.kpiActiveCustomers,
        ]) {
          expect(_kpi(kpi), findsOneWidget, reason: kpi);
        }
        final d = app.container
            .read(bayiStatsProvider(StatsPeriod.month))
            .data!;
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

        // Dönem: sabit seçici, yeni dönem istenir; dönem başlığı değişir.
        await tester.tap(find.text(StatsPeriod.lastMonth.label));
        await StatsTestApp.settle(tester);
        expect(probe.bayi, ['month', 'lastMonth']);
        expect(find.textContaining(RegExp('^Geçen ay · ')), findsOneWidget);
        // Önceki döneme dönünce önbellekteki sonuç hemen görünür (yeniden istenmez).
        await tester.tap(find.text(StatsPeriod.month.label));
        await StatsTestApp.settle(tester);
        expect(probe.bayi, ['month', 'lastMonth']);
        expect(find.textContaining(RegExp('^Bu ay · ')), findsOneWidget);
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
      await revealIn(tester, find.text('Son 12 ay'));
      await app.finish(tester);
    });

    testWidgets('aylık grafik: Tutar / Litre / Sipariş ve ay seçimi', (
      tester,
    ) async {
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
      expect(_inMonthly(StatsFmt.moneyCompact(last.amount)), findsOneWidget);

      final monthly = _section(StatsCopy.monthlyTitle);
      await _tapIn(tester, monthly, StatsCopy.metricLiters);
      expect(_inMonthly(StatsFmt.litersCompact(last.liters)), findsOneWidget);
      await _tapIn(tester, monthly, StatsCopy.metricOrders);
      // Sayı eksen etiketiyle aynı olabilir.
      expect(_inMonthly(StatsFmt.count(last.orders)), findsWidgets);
      await _tapIn(tester, monthly, StatsCopy.metricAmount);

      // Ay seçimi: altındaki ayrıntı satırı o ayı yazar.
      final first = months.first;
      final bar = find.bySemanticsLabel(
        '${first.longLabel} satış ${StatsFmt.moneySpoken(first.amount)}',
      );
      await revealIn(tester, bar);
      await tester.tap(bar);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text(
          '${first.longLabel} · ${StatsFmt.money(first.amount)} · '
          '${StatsFmt.liters(first.liters)} · ${StatsCopy.ordersCount(first.orders)}',
        ),
        findsOneWidget,
      );
      semantics.dispose();
      await app.finish(tester);
    });

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
        StatsCopy.kpiUnitPrice,
      ]) {
        expect(_kpi(kpi), findsOneWidget, reason: kpi);
      }
      final d = app.container
          .read(customerStatsProvider(StatsPeriod.month))
          .data!;
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
