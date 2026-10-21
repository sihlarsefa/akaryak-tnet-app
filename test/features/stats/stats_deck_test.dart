// Yönetici destesi (spec R1 §3.1–3.2): kim görür ve hangi kartları hangi sırayla; kaydırma / atış /
// yaylanma (F2GO fiziği), "Sonraki kart", noktalar, semantik eylemler, titreşim, sütun seçimi, hareket
// azaltma, bir kerelik ipucu, 403 / 404'te gizlenme, hata kartı ve yeniden deneme, çevrimdışı son kayıt,
// "Detaylı istatistikler", kart menüsü; büyük yazı ve koyu temada taşmasız çizim.
import 'dart:math' as math;

import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/offline/cache_store.dart';
import 'package:akaryakitnet/features/stats/api.dart';
import 'package:akaryakitnet/features/stats/copy.dart';
import 'package:akaryakitnet/features/stats/data/stats_models.dart';
import 'package:akaryakitnet/features/stats/presentation/charts/bar_chart.dart';
import 'package:akaryakitnet/features/stats/presentation/deck/deck_cards.dart';
import 'package:akaryakitnet/features/stats/presentation/deck/manager_stats_deck.dart';
import 'package:akaryakitnet/features/stats/presentation/stats_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stats_app.dart';

/// Bayi destesinin beklenen sırası (spec R1 §3.2; verisi gelmeyen kart yok).
List<String> _expectedBayi(BayiStats d, {required bool own}) => [
  if (d.sales != null) ...[DeckCards.sales, DeckCards.fuel],
  if (!own && d.funnel != null) DeckCards.funnel,
  if (!own && d.collections != null) DeckCards.collections,
  if (!own && d.deliveries != null) DeckCards.deliveries,
  if (d.topCustomers.isNotEmpty) DeckCards.topCustomers,
  if (own) DeckCards.ownForms else if (d.team.isNotEmpty) DeckCards.team,
  if (!own && (d.risk?.nearLimitCount ?? 0) > 0) DeckCards.risk,
];

/// Müşteri destesinin beklenen sırası.
List<String> _expectedCustomer(CustomerStats d) => [
  if (d.spending != null) ...[
    DeckCards.spend,
    DeckCards.purchase,
    if (d.spending!.unitPrice != null) DeckCards.unitPrice,
  ],
  if (d.limits.isNotEmpty) DeckCards.limits,
  if (d.deliveryPoints.isNotEmpty) DeckCards.points,
  if (d.orders != null) DeckCards.orderStatus,
];

BayiStats _bayiData(StatsTestApp app) =>
    app.container.read(bayiStatsProvider(StatsPeriod.month)).data!;

CustomerStats _customerData(StatsTestApp app) =>
    app.container.read(customerStatsProvider(StatsPeriod.month)).data!;

final _topCardFinder = find.byWidgetPredicate(
  (w) => w is DeckCardView && w.raised,
);

/// Destenin yüksekliği (kendini gizleyince 0; sıfır yükseklikli öğe "ekran dışı" sayılır).
double _deckHeight(WidgetTester tester) =>
    tester.getSize(find.byType(ManagerStatsDeck, skipOffstage: false)).height;

/// En üstteki kartın sol üst köşesinin yatay kayması (dinlenirken 0).
double _topShift(WidgetTester tester) =>
    tester.getTopLeft(_topCardFinder.last).dx - 16;

/// Arkadaki en büyük kartın çizilen genişliği (sürüklerken öne gelir).
double _behindWidth(WidgetTester tester) => tester
    .widgetList<DeckCardView>(find.byType(DeckCardView))
    .where((v) => !v.raised)
    .map((v) => tester.getRect(find.byWidget(v)).width)
    .fold<double>(0, math.max);

/// Platform titreşim çağrılarını sayar.
List<String> _recordHaptics(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add('${call.arguments}');
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

/// İlk kare (animasyon saati başlar) + 260 ms uçuş + kartın yerine oturduğu kare.
Future<void> _afterFlight(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('deck-next')));
  await tester.pump(const Duration(milliseconds: 320));
}

void main() {
  group('kim görür, hangi kartlar', () {
    for (final persona in [
      'sahip',
      'mudur',
      'finans',
      'muhasebe',
      'satis',
      'izleyici',
    ]) {
      testWidgets('$persona: bayi destesi, spec sırasıyla', (tester) async {
        final app = await StatsTestApp.start(tester, persona: persona);
        expect(app.container.read(statsScopeProvider), StatsScope.station);
        expect(app.container.read(canSeeStatsDeckProvider), isTrue);
        final d = _bayiData(app);
        expect(d.scope, 'station');
        expect(topCardId(tester), DeckCards.sales);
        expect(find.text(StatsCopy.cardSales), findsOneWidget);
        expect(find.text(StatsCopy.deckDetails), findsOneWidget);
        final order = await deckOrder(tester);
        expect(order, _expectedBayi(d, own: false));
        expect(order.length, deckPosition(tester).$2);
        await app.finish(tester);
      });
    }

    testWidgets(
      'rol bölümleri: sahipte ekip + tahsilat, izleyicide ikisi de yok',
      (tester) async {
        var app = await StatsTestApp.start(tester, persona: 'sahip');
        var order = await deckOrder(tester);
        expect(order, containsAll([DeckCards.collections, DeckCards.team]));
        await app.finish(tester);

        app = await StatsTestApp.start(tester, persona: 'izleyici');
        order = await deckOrder(tester);
        expect(order, isNot(contains(DeckCards.collections)));
        expect(order, isNot(contains(DeckCards.team)));
        await app.finish(tester);
      },
    );

    testWidgets('saha: kendi portföyü — satış, yakıt, carilerim, formlarım', (
      tester,
    ) async {
      final app = await StatsTestApp.start(tester, persona: 'saha');
      expect(app.container.read(statsScopeProvider), StatsScope.own);
      final d = _bayiData(app);
      expect(d.isOwn, isTrue);
      expect(find.text(StatsCopy.cardSalesOwn), findsOneWidget);
      final order = await deckOrder(tester);
      expect(order, _expectedBayi(d, own: true));
      expect(order.first, DeckCards.sales);
      expect(order.last, DeckCards.ownForms);
      for (final hidden in [
        DeckCards.funnel,
        DeckCards.collections,
        DeckCards.deliveries,
        DeckCards.team,
        DeckCards.risk,
      ]) {
        expect(order, isNot(contains(hidden)));
      }
      await app.finish(tester);
    });

    for (final persona in ['musteri', 'onay']) {
      testWidgets('$persona: müşteri destesi', (tester) async {
        final app = await StatsTestApp.start(tester, persona: persona);
        expect(app.container.read(statsScopeProvider), StatsScope.customer);
        expect(app.container.read(canSeeStatsDeckProvider), isTrue);
        expect(find.text(StatsCopy.cardSpend), findsOneWidget);
        final order = await deckOrder(tester);
        expect(order, _expectedCustomer(_customerData(app)));
        expect(order.first, DeckCards.spend);
        await app.finish(tester);
      });
    }

    for (final persona in [
      'talep',
      'siparis',
      'sevkiyat',
      'sofor',
      'depo',
      'merkez',
    ]) {
      testWidgets('$persona: deste yok, istek de yok', (tester) async {
        final probe = StatsProbe();
        final app = await StatsTestApp.start(
          tester,
          persona: persona,
          probe: probe,
        );
        expect(app.container.read(statsScopeProvider), StatsScope.none);
        expect(app.container.read(canSeeStatsDeckProvider), isFalse);
        expect(find.byType(SwipeDeck), findsNothing);
        expect(find.text(StatsCopy.deckDetails), findsNothing);
        expect(_deckHeight(tester), 0);
        expect(probe.total, 0);
        await app.finish(tester);
      });
    }
  });

  group('sunucu', () {
    for (final (name, response) in <(String, FakeResponse Function())>[
      ('403', FakeResponse.forbidden),
      ('404 (uç henüz yok)', FakeResponse.notFound),
    ]) {
      testWidgets('bayi $name → deste gizlenir', (tester) async {
        final probe = StatsProbe(fail: () => response());
        final app = await StatsTestApp.start(
          tester,
          persona: 'sahip',
          probe: probe,
        );
        expect(probe.bayi, isNotEmpty);
        expect(find.byType(SwipeDeck), findsNothing);
        expect(find.text(StatsCopy.deckFailedTitle), findsNothing);
        expect(_deckHeight(tester), 0);
        expect(app.container.read(canSeeStatsDeckProvider), isFalse);
        await app.finish(tester);
      });
    }

    testWidgets('müşteri 403 → deste gizlenir, harcama eğrisi geri gelir', (
      tester,
    ) async {
      final app = await StatsTestApp.start(
        tester,
        persona: 'musteri',
        probe: StatsProbe(fail: FakeResponse.forbidden),
      );
      expect(find.byType(SwipeDeck), findsNothing);
      expect(_deckHeight(tester), 0);
      expect(app.container.read(canSeeStatsDeckProvider), isFalse);
      await app.finish(tester);
    });

    testWidgets(
      'sunucu hatasında kısa hata kartı; "Tekrar dene" desteyi getirir',
      (tester) async {
        var failing = true;
        final probe = StatsProbe(
          fail: () => failing ? FakeResponse.server() : null,
        );
        final app = await StatsTestApp.start(
          tester,
          persona: 'sahip',
          probe: probe,
        );
        expect(find.text(StatsCopy.deckFailedTitle), findsOneWidget);
        expect(find.byType(SwipeDeck), findsNothing);
        // Hata, ana sayfadaki harcama eğrisini geri getirmez (deste yeniden denenebilir).
        expect(app.container.read(canSeeStatsDeckProvider), isTrue);
        failing = false;
        await tester.tap(find.text(StatsCopy.retry));
        await StatsTestApp.settle(tester);
        expect(find.byType(SwipeDeck), findsOneWidget);
        expect(find.text(StatsCopy.deckFailedTitle), findsNothing);
        expect(probe.bayi, ['month', 'month']);
        await app.finish(tester);
      },
    );

    testWidgets(
      'çevrimdışı açılışta son kayıt "Son güncelleme" ile; bağlantı gelince tazelenir',
      (tester) async {
        final store = MemoryCacheStore();
        final first = await StatsTestApp.start(
          tester,
          persona: 'sahip',
          overrides: [cacheStoreProvider.overrideWithValue(store)],
        );
        final n = deckPosition(tester).$2;
        expect(find.textContaining('Son güncelleme'), findsNothing);
        await first.finish(tester);

        final second = await StatsTestApp.start(
          tester,
          persona: 'sahip',
          overrides: [cacheStoreProvider.overrideWithValue(store)],
          setup: (s) => s.failureMode = FakeFailureMode.offline,
        );
        expect(find.byType(SwipeDeck), findsOneWidget);
        expect(deckPosition(tester).$2, n);
        expect(find.textContaining('Son güncelleme'), findsOneWidget);

        second.server.failureMode = FakeFailureMode.none;
        second.setOnline(false);
        await tester.pump();
        second.setOnline(true);
        await StatsTestApp.settle(tester);
        expect(find.textContaining('Son güncelleme'), findsNothing);
        expect(find.byType(SwipeDeck), findsOneWidget);
        await second.finish(tester);
      },
    );

    testWidgets('çevrimdışı ve önbellek yoksa bağlantı kartı', (tester) async {
      final app = await StatsTestApp.start(
        tester,
        persona: 'musteri',
        setup: (s) => s.failureMode = FakeFailureMode.offline,
      );
      expect(find.text(StatsCopy.deckOfflineTitle), findsOneWidget);
      expect(find.byType(SwipeDeck), findsNothing);
      await app.finish(tester);
    });
  });

  group('gezinme', () {
    testWidgets(
      '"Sonraki kart", noktalar ve semantik eylemler; her geçişte titreşim',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final app = await StatsTestApp.start(tester, persona: 'sahip');
        final haptics = _recordHaptics(tester);
        final (start, n) = deckPosition(tester);
        expect(start, 1);
        expect(n, greaterThanOrEqualTo(6));

        await _tapNext(tester);
        expect(deckPosition(tester), (2, n));
        expect(topCardId(tester), DeckCards.fuel);

        // Noktaya dokunmak o karta götürür.
        await tester.tap(find.byKey(const ValueKey('deck-dot-4')));
        await tester.pump(const Duration(milliseconds: 320));
        expect(deckPosition(tester), (5, n));

        // Ekran okuyucu: kart konumu + başlık; "Sonraki / Önceki kart" eylemleri.
        final deck = find.bySemanticsLabel(RegExp('^$n karttan 5\\. kart: '));
        expect(deck, findsOneWidget);
        final node = tester.getSemantics(deck);
        int action(String label) => CustomSemanticsAction.getIdentifier(
          CustomSemanticsAction(label: label),
        );
        node.owner!.performAction(
          node.id,
          SemanticsAction.customAction,
          action(StatsCopy.deckNext),
        );
        await tester.pump(const Duration(milliseconds: 320));
        expect(deckPosition(tester), (6, n));
        final again = tester.getSemantics(
          find.bySemanticsLabel(RegExp('^$n karttan 6\\. kart: ')),
        );
        again.owner!.performAction(
          again.id,
          SemanticsAction.customAction,
          action(StatsCopy.deckPrevious),
        );
        await tester.pump(const Duration(milliseconds: 320));
        expect(deckPosition(tester), (5, n));

        // Son karttan sonra başa döner.
        for (var i = 5; i <= n; i++) {
          await _tapNext(tester);
        }
        expect(deckPosition(tester), (1, n));
        // Her kart değişiminde bir titreşim: sonraki (1) + nokta (1) + iki eylem (2) + başa dönüş (n - 4).
        expect(
          haptics.where((h) => h == 'HapticFeedbackType.selectionClick').length,
          n,
        );
        semantics.dispose();
        await app.finish(tester);
      },
    );

    testWidgets(
      'kaydırma: kısa sürükleme yaylanarak döner, %28 üstü ve hızlı atış kartı geçirir',
      (tester) async {
        final app = await StatsTestApp.start(
          tester,
          persona: 'sahip',
          reduceMotion: false,
        );
        await StatsTestApp.settle(tester, rounds: 10);
        final n = deckPosition(tester).$2;
        expect(_topShift(tester), moreOrLessEquals(0, epsilon: 0.5));
        final restBehind = _behindWidth(tester);

        // Sürüklerken kart parmağı izler, arkadaki kart öne gelir (ölçek .95 → 1).
        final gesture = await tester.startGesture(
          tester.getCenter(_topCardFinder),
        );
        await gesture.moveBy(const Offset(-30, 0));
        await gesture.moveBy(const Offset(-40, 0));
        await tester.pump();
        expect(_topShift(tester), lessThan(-30));
        expect(_behindWidth(tester), greaterThan(restBehind + 2));

        // Eşiğin altında ve yavaş bırakınca yaylanarak yerine döner (600 ms elasticOut).
        await gesture.up();
        await tester.pump();
        expect(_topShift(tester), lessThan(-20));
        await tester.pump(const Duration(milliseconds: 650));
        expect(_topShift(tester), moreOrLessEquals(0, epsilon: 0.5));
        expect(deckPosition(tester), (1, n));
        expect(
          _behindWidth(tester),
          moreOrLessEquals(restBehind, epsilon: 0.5),
        );

        // Genişliğin %28'inden uzun, yavaş sürükleme: kart uçar (260 ms), sıradaki üste gelir.
        await tester.timedDrag(
          _topCardFinder,
          const Offset(-170, 0),
          const Duration(milliseconds: 900),
        );
        await tester.pump();
        expect(deckPosition(tester), (1, n), reason: 'uçuş sürüyor');
        await _afterFlight(tester);
        expect(deckPosition(tester), (2, n));
        expect(_topShift(tester), moreOrLessEquals(0, epsilon: 0.5));

        // Kısa ama hızlı atış (> 700 px/s) da kartı geçirir.
        await tester.fling(_topCardFinder, const Offset(-60, 0), 1600);
        await _afterFlight(tester);
        expect(deckPosition(tester), (3, n));

        // Sağa kaydırma da sıradaki kartı getirir (kart destenin arkasına geçer).
        await tester.timedDrag(
          _topCardFinder,
          const Offset(170, 0),
          const Duration(milliseconds: 900),
        );
        await _afterFlight(tester);
        expect(deckPosition(tester), (4, n));

        // "Sonraki kart" da uçarak geçer; noktaya dokununca kartlar sırayla uçar.
        await tester.tap(find.byKey(const ValueKey('deck-next')));
        await tester.pump();
        expect(deckPosition(tester), (4, n), reason: 'uçuş sürüyor');
        await _afterFlight(tester);
        expect(deckPosition(tester), (5, n));
        await tester.tap(find.byKey(const ValueKey('deck-dot-0')));
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(deckPosition(tester), (1, n));
        await app.finish(tester);
      },
    );

    testWidgets('"Detaylı istatistikler" /stats sayfasını açar', (
      tester,
    ) async {
      final app = await StatsTestApp.start(tester, persona: 'musteri');
      await tester.tap(find.byKey(const ValueKey('deck-details')));
      await StatsTestApp.settle(tester);
      expect(find.byType(StatsPage), findsOneWidget);
      expect(find.text(StatsCopy.pageTitle), findsOneWidget);
      expect(
        app.router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/stats',
      );
      await app.finish(tester);
    });

    testWidgets(
      'kart menüsü: "Yenile" sunucuyu yeniden çağırır, "Nasıl hesaplanır?" açıklar',
      (tester) async {
        final probe = StatsProbe();
        final app = await StatsTestApp.start(
          tester,
          persona: 'sahip',
          probe: probe,
        );
        final before = probe.bayi.length;
        await tester.tap(find.byKey(const ValueKey('deck-menu-sales')));
        await StatsTestApp.settle(tester, rounds: 8);
        await tester.tap(find.text(StatsCopy.deckRefresh));
        await StatsTestApp.settle(tester);
        expect(probe.bayi.length, before + 1);
        expect(probe.bayi.toSet(), {'month'});

        await tester.tap(find.byKey(const ValueKey('deck-menu-sales')));
        await StatsTestApp.settle(tester, rounds: 8);
        await tester.tap(find.text(StatsCopy.deckHowTo));
        await StatsTestApp.settle(tester);
        expect(find.text(StatsCopy.howSales), findsOneWidget);
        await app.finish(tester);
      },
    );
  });

  group('grafik', () {
    testWidgets(
      'satış kartı: varsayılan bu ay seçili; sütuna dokununca o ayın değeri yazar',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final app = await StatsTestApp.start(tester, persona: 'sahip');
        final months = _bayiData(app).months;
        expect(months, hasLength(6));
        final chart = find.descendant(
          of: _topCardFinder,
          matching: find.byType(StatsBarChart),
        );
        expect(chart, findsOneWidget);
        String label(StatsMonth m) => StatsFmt.moneyCompact(m.amount);
        Finder inChart(String text) =>
            find.descendant(of: chart, matching: find.text(text));
        expect(inChart(label(months.last)), findsOneWidget);

        // Bu ayın etiketinden farklı yazan ilk ay seçilir.
        final target = months.firstWhere((m) => label(m) != label(months.last));
        final bar = find.bySemanticsLabel(
          '${target.longLabel} satış ${StatsFmt.moneySpoken(target.amount)}',
        );
        expect(bar, findsOneWidget);
        await tester.tap(bar);
        await tester.pump(const Duration(milliseconds: 300));
        expect(inChart(label(target)), findsOneWidget);
        expect(inChart(label(months.last)), findsNothing);
        semantics.dispose();
        await app.finish(tester);
      },
    );
  });

  group('hareket', () {
    testWidgets(
      'ilk gösterimde bir kez sallanır ve tercih yazılır; sonra sallanmaz',
      (tester) async {
        var app = await StatsTestApp.start(
          tester,
          persona: 'sahip',
          reduceMotion: false,
          prefs: const {'akn.onboardingDone': true},
        );
        expect(app.prefs.getBool(StatsKeys.deckHint), isTrue);
        var moved = 0.0;
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          moved = math.max(moved, _topShift(tester).abs());
        }
        expect(moved, greaterThan(20));
        expect(_topShift(tester), moreOrLessEquals(0, epsilon: 0.5));
        expect(deckPosition(tester).$1, 1, reason: 'ipucu kart değiştirmez');
        await app.finish(tester);

        app = await StatsTestApp.start(
          tester,
          persona: 'sahip',
          reduceMotion: false,
        );
        moved = 0;
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          moved = math.max(moved, _topShift(tester).abs());
        }
        expect(moved, lessThan(0.5));
        await app.finish(tester);
      },
    );

    testWidgets('hareket azaltma: sallanma yok, kart geçişi beklemeden', (
      tester,
    ) async {
      final app = await StatsTestApp.start(
        tester,
        persona: 'sahip',
        prefs: const {'akn.onboardingDone': true},
      );
      expect(app.prefs.getBool(StatsKeys.deckHint), isNull);
      var moved = 0.0;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        moved = math.max(moved, _topShift(tester).abs());
      }
      expect(moved, lessThan(0.5));
      final n = deckPosition(tester).$2;
      await tester.tap(find.byKey(const ValueKey('deck-next')));
      await tester.pump();
      expect(deckPosition(tester), (2, n));
      // Kısa sürükleme hemen yerine döner; uzun sürükleme kartı hemen geçirir.
      await tester.timedDrag(
        _topCardFinder.last,
        const Offset(-60, 0),
        const Duration(milliseconds: 700),
      );
      await tester.pump();
      expect(_topShift(tester), moreOrLessEquals(0, epsilon: 0.5));
      await tester.timedDrag(
        _topCardFinder.last,
        const Offset(-170, 0),
        const Duration(milliseconds: 900),
      );
      await tester.pump();
      expect(deckPosition(tester), (3, n));
      await app.finish(tester);
    });
  });

  group('büyük yazı ve koyu tema: taşma yok', () {
    for (final (tag, brightness, scale) in [
      ('2,0× koyu', Brightness.dark, 2.0),
      ('1,6× açık', Brightness.light, 1.6),
      ('1,0× koyu', Brightness.dark, 1.0),
    ]) {
      for (final persona in ['sahip', 'saha', 'musteri']) {
        testWidgets('$persona $tag, 320 dp', (tester) async {
          final app = await StatsTestApp.start(
            tester,
            persona: persona,
            brightness: brightness,
            textScale: scale,
            size: const Size(320, 1400),
          );
          final order = await deckOrder(tester);
          expect(order, isNotEmpty);
          // Çizim hatası (taşma) olursa test kendiliğinden ayrıntısıyla düşer.
          await app.finish(tester);
        });
      }
    }

    testWidgets('hata kartı 2,0× yazıda', (tester) async {
      final app = await StatsTestApp.start(
        tester,
        persona: 'sahip',
        textScale: 2,
        size: const Size(320, 1400),
        probe: StatsProbe(fail: FakeResponse.server),
      );
      expect(find.text(StatsCopy.deckFailedTitle), findsOneWidget);
      // Çizim hatası (taşma) olursa test kendiliğinden ayrıntısıyla düşer.
      await app.finish(tester);
    });
  });
}
