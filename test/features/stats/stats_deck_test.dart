// Yönetici destesi (spec R1 §3.1–3.2, tasarım v2 §5.3 / §8 / §14.1): kim görür ve hangi kartları hangi
// sırayla; plaka bir konumdur (üst kart plaka renkleri, arkadaki kâğıt); kaydırma / atış / yaylanma,
// "1 / 8" (sonraki kart), şerit çizgileri, semantik eylemler, titreşim, çubuk baloncuğu, hareket azaltma
// (son kare), oturumda bir kez sayaç dönüşü, bir kerelik ±10 px ipucu, 403 / 404'te gizlenme, hata kâğıdı
// ve yeniden deneme, çevrimdışı son kayıt, "İstatistikler" bağlantısı, ⋯ menüsü (Detaylı istatistikler,
// Yenile, Nasıl hesaplanır?), %100'de duran ölçer, kart yüksekliği ve büyük yazı düzeni; büyük yazı ve
// koyu temada taşmasız çizim.
import 'dart:math' as math;

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/offline/cache_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/stats/api.dart';
import 'package:akaryakitnet/features/stats/copy.dart';
import 'package:akaryakitnet/features/stats/presentation/deck/deck_cards.dart';
import 'package:akaryakitnet/features/stats/presentation/deck/manager_stats_deck.dart';
import 'package:akaryakitnet/features/stats/presentation/stats_format.dart';
import 'package:akaryakitnet/features/stats/stats_fake.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
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
    tester.getTopLeft(_topCardFinder.last).dx - 20;

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
  await _deckNext(tester);
  await tester.pump(const Duration(milliseconds: 320));
}

// v4 (§4): the pager no longer draws "1 / N" (its semantics stay), so the
// deck's position is read from the LanePager and "Sonraki kart" is its
// position action.
LanePager _pager(WidgetTester tester) =>
    tester.widget<LanePager>(find.byType(LanePager));

(int, int) _deckPosition(WidgetTester tester) {
  final p = _pager(tester);
  return (p.index + 1, p.count);
}

/// "Sonraki kart": the deck's own custom action, as a screen reader does it
/// (v4: the pager no longer carries a hidden button).
Future<void> _deckNext(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  final node = tester.getSemantics(
    find.bySemanticsLabel(RegExp(r'karttan \d+\. kart: ')),
  );
  node.owner!.performAction(
    node.id,
    SemanticsAction.customAction,
    CustomSemanticsAction.getIdentifier(
      const CustomSemanticsAction(label: StatsCopy.deckNext),
    ),
  );
  handle.dispose();
  await tester.pump();
}

Future<void> _deckLane(WidgetTester tester, int lane) async {
  final (pos, _) = _deckPosition(tester);
  final active = pos - 1;
  var left = 0.0;
  for (var i = 0; i < lane; i++) {
    left += (i == active ? 20 : 6) + 10;
  }
  final w = lane == active ? 20.0 : 6.0;
  final origin = tester.getTopLeft(find.byType(LanePager));
  await tester.tapAt(origin + Offset(left + w / 2, 20));
}

Future<List<String>> _deckOrder(WidgetTester tester) async {
  if (find.byType(LanePager).evaluate().isEmpty || _pager(tester).count < 2) {
    return [topCardId(tester)];
  }
  final (_, n) = _deckPosition(tester);
  final ids = <String>[];
  for (var i = 0; i < n; i++) {
    ids.add(topCardId(tester));
    await _deckNext(tester);
    await tester.pump(const Duration(milliseconds: 300));
  }
  return ids;
}

/// Kartın renkleri (deste her katmana kendi paletini verir).
AknColors _colorsOf(WidgetTester tester, DeckCardView view) =>
    Theme.of(tester.element(find.byWidget(view))).extension<AknColors>()!;

/// Üst kartın içindekiler.
Finder _inTop(Finder f) => find.descendant(of: _topCardFinder, matching: f);

/// Bayi yanıtında limit riskini değiştirir (aşım: %100'ü geçen kullanım).
void _overLimit(FakeServer s) {
  s.get('stats/bayi', (req) {
    final body = StatsFake.handleBayi(req);
    body['risk'] = {
      'nearLimitCount': 1,
      'nearLimit': [
        {'customerId': 7, 'title': 'Aşım Ticaret Ltd.', 'usageRate': 1.25},
      ],
    };
    return body;
  });
}

void main() {
  // Gerçek yüz (Mona Sans): şeritteki "İstatistikler" bağlantısı ve sığma ölçüleri cihazdaki gibi.
  setUpAll(loadRealFonts);

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
        expect(find.text(StatsCopy.deckStatsLink), findsOneWidget);
        final order = await _deckOrder(tester);
        expect(order, _expectedBayi(d, own: false));
        expect(order.length, _deckPosition(tester).$2);
        await app.finish(tester);
      });
    }

    testWidgets(
      'rol bölümleri: sahipte ekip + tahsilat, izleyicide ikisi de yok',
      (tester) async {
        var app = await StatsTestApp.start(tester, persona: 'sahip');
        var order = await _deckOrder(tester);
        expect(order, containsAll([DeckCards.collections, DeckCards.team]));
        await app.finish(tester);

        app = await StatsTestApp.start(tester, persona: 'izleyici');
        order = await _deckOrder(tester);
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
      final order = await _deckOrder(tester);
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
        final order = await _deckOrder(tester);
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
        expect(find.text(StatsCopy.deckStatsLink), findsNothing);
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
        final n = _deckPosition(tester).$2;
        expect(find.textContaining('Son güncelleme'), findsNothing);
        await first.finish(tester);

        final second = await StatsTestApp.start(
          tester,
          persona: 'sahip',
          overrides: [cacheStoreProvider.overrideWithValue(store)],
          setup: (s) => s.failureMode = FakeFailureMode.offline,
        );
        expect(find.byType(SwipeDeck), findsOneWidget);
        expect(_deckPosition(tester).$2, n);
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
      '"1 / 8", şerit çizgileri ve semantik eylemler; her geçişte bir titreşim',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final app = await StatsTestApp.start(tester, persona: 'sahip');
        final haptics = _recordHaptics(tester);
        final (start, n) = _deckPosition(tester);
        expect(start, 1);
        expect(n, greaterThanOrEqualTo(6));

        await _tapNext(tester);
        expect(_deckPosition(tester), (2, n));
        expect(topCardId(tester), DeckCards.fuel);

        // Şeritteki çizgiye dokunmak o karta götürür.
        await _deckLane(tester, 4);
        await tester.pump(const Duration(milliseconds: 320));
        expect(_deckPosition(tester), (5, n));

        // Ekran okuyucu: kart konumu, başlık ve özet; "Sonraki / Önceki kart" eylemleri.
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
        expect(_deckPosition(tester), (6, n));
        final again = tester.getSemantics(
          find.bySemanticsLabel(RegExp('^$n karttan 6\\. kart: ')),
        );
        again.owner!.performAction(
          again.id,
          SemanticsAction.customAction,
          action(StatsCopy.deckPrevious),
        );
        await tester.pump(const Duration(milliseconds: 320));
        expect(_deckPosition(tester), (5, n));

        // Son karttan sonra başa döner.
        for (var i = 5; i <= n; i++) {
          await _tapNext(tester);
        }
        expect(_deckPosition(tester), (1, n));
        // Her kart değişiminde bir titreşim: sonraki (1) + çizgi (1) + iki eylem (2) + başa dönüş (n - 4).
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
        final n = _deckPosition(tester).$2;
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

        // Sürüklenen kart kalkık gölge alır; hemen arkadaki kâğıt plakaya doğru renk değiştirir.
        final behind = tester
            .widgetList<DeckCardView>(find.byType(DeckCardView))
            .where((v) => !v.raised)
            .toList();
        expect(topCard(tester).shadow, isNotEmpty);
        final paper = Theme.of(
          tester.element(find.byType(SwipeDeck)),
        ).extension<AknColors>()!;
        expect(
          behind.map((v) => _colorsOf(tester, v).surface),
          contains(isNot(anyOf(paper.surface, paper.surfaceAlt, paper.plate))),
          reason: 'devir sürüyor: kâğıt ile plaka arası',
        );

        // Eşiğin altında ve yavaş bırakınca yaylanarak yerine döner (600 ms elasticOut).
        await gesture.up();
        await tester.pump();
        expect(_topShift(tester), lessThan(-20));
        await tester.pump(const Duration(milliseconds: 650));
        expect(_topShift(tester), moreOrLessEquals(0, epsilon: 0.5));
        expect(_deckPosition(tester), (1, n));
        expect(
          _behindWidth(tester),
          moreOrLessEquals(restBehind, epsilon: 0.5),
        );

        expect(
          topCard(tester).shadow,
          isEmpty,
          reason: 'dinlenirken gölge yok',
        );

        // Genişliğin %28'inden uzun, yavaş sürükleme: kart uçar (240 ms), sıradaki üste gelir.
        await tester.timedDrag(
          _topCardFinder,
          const Offset(-170, 0),
          const Duration(milliseconds: 900),
        );
        await tester.pump();
        expect(_deckPosition(tester), (1, n), reason: 'uçuş sürüyor');
        await _afterFlight(tester);
        expect(_deckPosition(tester), (2, n));
        expect(_topShift(tester), moreOrLessEquals(0, epsilon: 0.5));

        // Kısa ama hızlı atış (> 700 px/s) da kartı geçirir.
        await tester.fling(_topCardFinder, const Offset(-60, 0), 1600);
        await _afterFlight(tester);
        expect(_deckPosition(tester), (3, n));

        // Sağa kaydırma da sıradaki kartı getirir (kart destenin arkasına geçer).
        await tester.timedDrag(
          _topCardFinder,
          const Offset(170, 0),
          const Duration(milliseconds: 900),
        );
        await _afterFlight(tester);
        expect(_deckPosition(tester), (4, n));

        // v4: "1 / 8" çizilmez; ekran okuyucunun "Sonraki kart" eylemi geçirir; şeritteki çizgi o
        // kartı doğrudan üste getirir ve plaka 200 ms'de yanar.
        await _deckNext(tester);
        await _afterFlight(tester);
        expect(_deckPosition(tester), (5, n));
        await _deckLane(tester, 0);
        await tester.pump();
        expect(_deckPosition(tester), (1, n));
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          _colorsOf(tester, topCard(tester)).surface,
          paper.plate,
          reason: 'devir tamamlandı',
        );
        await app.finish(tester);
      },
    );

    testWidgets('"İstatistikler" bağlantısı /stats sayfasını açar', (
      tester,
    ) async {
      final app = await StatsTestApp.start(tester, persona: 'musteri');
      await tester.tap(
        find.descendant(
          of: find.byType(LanePager),
          matching: find.text(StatsCopy.deckStatsLink),
        ),
      );
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
      'v4: ⋯ menüsü yok; fark çipi başlıkta, "Detaylı" sayfa bağlantısında',
      (tester) async {
        final app = await StatsTestApp.start(tester, persona: 'sahip');
        // No ⋯ on any card (refresh is pull-to-refresh, "how" lives on /stats).
        expect(find.byKey(const ValueKey('deck-menu-sales')), findsNothing);
        expect(find.byIcon(PhosphorIconsRegular.dotsThree), findsNothing);
        expect(find.text(StatsCopy.deckRefresh), findsNothing);
        // The delta chip sits in the card's head (PlateHead.trailing).
        final head = _inTop(find.byType(PlateHead));
        expect(head, findsOneWidget);
        expect(
          find.descendant(of: head, matching: find.byType(TriangleGlyph)),
          findsOneWidget,
        );
        // "Detaylı istatistikler" is the pager link.
        await tester.tap(find.text(StatsCopy.deckStatsLink));
        await StatsTestApp.settle(tester);
        expect(
          app.router.routerDelegate.currentConfiguration.last.matchedLocation,
          '/stats',
        );
        await app.finish(tester);
      },
    );
  });

  group('grafik', () {
    testWidgets(
      'satış kartı: 6 ay, bu ay vurgulu; sütuna dokununca baloncukta değeri yazar',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final app = await StatsTestApp.start(tester, persona: 'sahip');
        final months = _bayiData(app).months;
        expect(months, hasLength(6));
        final bars = _inTop(find.byType(PlateBars));
        expect(bars, findsOneWidget);
        final w = tester.widget<PlateBars>(bars);
        expect(w.values, [for (final m in months) m.amount]);
        expect(w.labels.last, months.last.shortLabel);

        final target = months.first;
        final label = StatsFmt.moneyCompact(target.amount);
        expect(_inTop(find.text(label)), findsNothing);
        final bar = find.bySemanticsLabel(
          '${target.longLabel}, ${StatsFmt.moneySpoken(target.amount)}',
        );
        expect(bar, findsOneWidget);
        await tester.tap(bar);
        await tester.pump(const Duration(milliseconds: 100));
        expect(_inTop(find.text(label)), findsOneWidget);
        // Baloncuk 2 sn sonra kaybolur.
        await tester.pump(const Duration(milliseconds: 2100));
        expect(_inTop(find.text(label)), findsNothing);
        semantics.dispose();
        await app.finish(tester);
      },
    );

    testWidgets('limit aşımı plakada "!" ile; ölçer %100\'de durur', (
      tester,
    ) async {
      final app = await StatsTestApp.start(
        tester,
        persona: 'sahip',
        setup: _overLimit,
      );
      final order = await _deckOrder(tester);
      await _deckLane(tester, order.indexOf(DeckCards.risk));
      await tester.pump(const Duration(milliseconds: 300));
      expect(topCardId(tester), DeckCards.risk);
      expect(_inTop(find.text('Aşım Ticaret Ltd.')), findsOneWidget);
      expect(_inTop(find.text('%125')), findsOneWidget);
      expect(_inTop(find.byType(PlateBang)), findsOneWidget);
      final meter = tester.widget<PlateMeter>(_inTop(find.byType(PlateMeter)));
      expect(meter.value, 1.0);
      expect(meter.threshold, StatsCopy.warnLevel);
      await app.finish(tester);
    });
  });

  group('plaka bir konumdur', () {
    testWidgets(
      'üst kart plaka renklerinde, arkadakiler kâğıt (koyu temada da)',
      (tester) async {
        for (final brightness in Brightness.values) {
          final app = await StatsTestApp.start(
            tester,
            persona: 'sahip',
            brightness: brightness,
          );
          final paper = Theme.of(
            tester.element(find.byType(SwipeDeck)),
          ).extension<AknColors>()!;
          final views = tester
              .widgetList<DeckCardView>(find.byType(DeckCardView))
              .toList();
          // v4: one paper edge behind the top card.
          expect(views, hasLength(2));
          final top = views.singleWhere((v) => v.raised);
          final topColors = _colorsOf(tester, top);
          expect(topColors.surface, paper.plate);
          // Sahip kararı G: plaka beyaz kart, rakamlar mürekkep (siyah değil).
          expect(topColors.ink, paper.onPlate);
          expect(top.shadow, isEmpty);
          expect(top.plate, 1, reason: 'üst kart plaka kartını giyer');
          final behind = views.where((v) => !v.raised).toList();
          for (final v in behind) {
            final c = _colorsOf(tester, v);
            expect(v.plate ?? 0, 0, reason: 'arkadaki kart kâğıt');
            expect(c.ink, paper.ink);
          }
          // Hemen arkadaki Beton (yığının tek kenarı okunur).
          expect(behind.map((v) => _colorsOf(tester, v).surface).toSet(), {
            paper.surfaceAlt,
          });
          await app.finish(tester);
        }
      },
    );

    testWidgets('kart değişince plaka sıradaki karta geçer', (tester) async {
      final app = await StatsTestApp.start(tester, persona: 'musteri');
      final plate = Theme.of(
        tester.element(find.byType(SwipeDeck)),
      ).extension<AknColors>()!.plate;
      expect(topCardId(tester), DeckCards.spend);
      final next = tester
          .widgetList<DeckCardView>(find.byType(DeckCardView))
          .singleWhere((v) => v.card.id == DeckCards.purchase);
      expect(_colorsOf(tester, next).surface, isNot(plate), reason: 'kâğıt');
      await _tapNext(tester);
      await tester.pump();
      expect(topCardId(tester), DeckCards.purchase);
      expect(_colorsOf(tester, topCard(tester)).surface, plate);
      expect(topCard(tester).plate, 1);
      for (final v
          in tester
              .widgetList<DeckCardView>(find.byType(DeckCardView))
              .where((v) => !v.raised)) {
        expect(v.plate ?? 0, 0, reason: 'kâğıt');
      }
      await app.finish(tester);
    });

    testWidgets(
      'başlık satırı: dönem ve karşılaştırma ("1–21 Ekim · geçen aya göre"), ikon kutusu yok',
      (tester) async {
        final app = await StatsTestApp.start(tester, persona: 'sahip');
        final d = _bayiData(app);
        final period = StatsFmt.rangeShort(d.period.from, d.period.to);
        // v4 tur 2: karşılaştırma başlıkta (/stats plakasıyla aynı söz); rakamın altında ayrı cümle yok.
        final head = '$period · ${StatsPeriod.month.compareBrief}';
        expect(topCard(tester).card.subtitle, head);
        expect(_inTop(find.text(head)), findsOneWidget);
        expect(
          _inTop(find.textContaining(StatsPeriod.month.compareShort)),
          findsNothing,
        );
        expect(_inTop(find.byType(PlateHead)), findsOneWidget);
        // Satış kartı: kural ve üç okuma.
        expect(_inTop(find.byType(PlateRule)), findsOneWidget);
        final readouts = tester.widget<PlateReadouts>(
          _inTop(find.byType(PlateReadouts)),
        );
        expect(readouts.items, hasLength(3));
        expect(readouts.items.first.label, StatsCopy.kpiLiters);
        await app.finish(tester);
      },
    );
  });

  group('yükseklik ve büyük yazı', () {
    // v4: 1,0×–1,6× arası 248 + 170 × (s − 1); büyük yazı düzeninde en uzun kartın içeriği kadar (en
    // çok 320) — 2,0×'te karar satırı ilk ekranda kalsın (pano ekranı 9).
    for (final (scale, height) in [
      (1.0, 248.0),
      (1.3, 299.0),
      (1.6, null),
      (2.0, null),
    ]) {
      testWidgets('$scale×: kart ${height ?? 'içerik kadar'}', (tester) async {
        final app = await StatsTestApp.start(
          tester,
          persona: 'musteri',
          textScale: scale,
          size: const Size(390, 1400),
        );
        final h = tester.getSize(_topCardFinder).height;
        if (height != null) {
          expect(h, moreOrLessEquals(height, epsilon: 0.5));
        } else {
          expect(h, inInclusiveRange(200.0, 300.0));
          // Hiçbir kart küçülmeden sığar: her kartın büyük yazı içeriği ölçülen yükseklikte.
          final cards = tester.widget<SwipeDeck>(find.byType(SwipeDeck)).cards;
          final measured = deckCompactHeight(
            tester.element(_topCardFinder),
            cards,
            tester.getSize(find.byType(SwipeDeck)).width,
          );
          expect(h, moreOrLessEquals(measured, epsilon: 0.5));
        }
        final compact = scale >= 1.6;
        expect(
          _inTop(find.byType(PlateBars)),
          compact ? findsNothing : findsOneWidget,
        );
        expect(
          _inTop(find.byType(PlateReadouts)),
          compact ? findsNothing : findsOneWidget,
        );
        // Rakam ve karşılaştırma her düzende (karşılaştırma başlığın dönem satırında, v4 tur 2).
        expect(_inTop(find.byType(PlateFigure)), findsOneWidget);
        expect(
          _inTop(find.textContaining(StatsPeriod.month.compareBrief)),
          findsOneWidget,
        );
        await app.finish(tester);
      });
    }
  });

  // v4 tur 2 (M3): 390×844'te ayrıntı küçülüp ortalanmaz — okuma etiketleri en az 11 dp çizilir ve
  // ayrıntının sol kenarı başlıkla aynı çizgidedir (çubuklar kısalır, yazı küçülmez).
  group('ayrıntı tam boyda, başlıkla hizalı (390×844)', () {
    for (final (persona, label) in [
      ('musteri', StatsCopy.kpiLitersCustomer),
      ('sahip', StatsCopy.kpiLiters),
    ]) {
      testWidgets('$persona: "$label" ≥ 11 dp, sol kenar başlıkla aynı', (
        tester,
      ) async {
        final app = await StatsTestApp.start(
          tester,
          persona: persona,
          size: const Size(390, 844),
        );
        final readout = _inTop(find.text(label));
        expect(readout, findsOneWidget);
        // 12/16 etiket: çizilen satır yüksekliği 16 × ölçek; 11 dp yazı = 14,67.
        expect(tester.getRect(readout).height, greaterThanOrEqualTo(14.6));
        final title = _inTop(find.text(topCard(tester).card.title));
        expect(title, findsOneWidget);
        expect(
          tester.getRect(readout).left,
          moreOrLessEquals(tester.getRect(title).left, epsilon: 1),
        );
        // Rakam da aynı çizgide.
        expect(
          tester.getRect(_inTop(find.byType(PlateFigure))).left,
          moreOrLessEquals(tester.getRect(title).left, epsilon: 1),
        );
        await app.finish(tester);
      });
    }
  });

  group('hareket', () {
    testWidgets(
      'ilk gösterimde bir kez ±10 px sallanır ve tercih yazılır; sonra sallanmaz',
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
        expect(moved, greaterThan(5));
        // ±10 px kayma (+ en çok 6° eğimin üst köşede birkaç pikseli).
        expect(moved, lessThanOrEqualTo(14));
        expect(_topShift(tester), moreOrLessEquals(0, epsilon: 0.5));
        expect(_deckPosition(tester).$1, 1, reason: 'ipucu kart değiştirmez');
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

    testWidgets(
      'hareket azaltma: son kare hemen (sayaç dönmez), sallanma yok, kart geçişi beklemeden',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final app = await StatsTestApp.start(
          tester,
          persona: 'sahip',
          prefs: const {'akn.onboardingDone': true},
        );
        expect(app.prefs.getBool(StatsKeys.deckHint), isNull);
        // Son kare: plaka yanık, rakam son değerinde; dönüş "görülmüş" sayılır.
        final amount = _bayiData(app).sales!.amount;
        final plate = Theme.of(
          tester.element(find.byType(SwipeDeck)),
        ).extension<AknColors>()!.plate;
        expect(_colorsOf(tester, topCard(tester)).surface, plate);
        final figure = tester.widget<RollingFigure>(
          _inTop(find.byType(RollingFigure)),
        );
        expect(figure.value, StatsFmt.count(amount));
        expect(
          find.bySemanticsLabel(
            RegExp(RegExp.escape(StatsFmt.moneyWholeSpoken(amount))),
          ),
          findsWidgets,
        );
        expect(app.container.read(plateRollSeenProvider), isTrue);
        expect(tester.hasRunningAnimations, isFalse);
        var moved = 0.0;
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          moved = math.max(moved, _topShift(tester).abs());
        }
        expect(moved, lessThan(0.5));
        final n = _deckPosition(tester).$2;
        await _deckNext(tester);
        await tester.pump();
        expect(_deckPosition(tester), (2, n));
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
        expect(_deckPosition(tester), (3, n));
        semantics.dispose();
        await app.finish(tester);
      },
    );

    testWidgets(
      'sayaç dönüşü oturumda bir kez: plaka kâğıttan yanar; deste yeniden kurulunca dönmez; çıkışta sıfırlanır',
      (tester) async {
        final app = await StatsTestApp.start(
          tester,
          persona: 'sahip',
          reduceMotion: false,
        );
        expect(app.container.read(plateRollSeenProvider), isTrue);
        final plate = Theme.of(
          tester.element(find.byType(SwipeDeck).first),
        ).extension<AknColors>()!.plate;
        await StatsTestApp.settle(tester, rounds: 10);
        expect(_colorsOf(tester, topCard(tester)).surface, plate);

        // Ana sayfa yeniden kurulur (sekme / sayfa değişimi): plaka hemen yanık, dönüş yok.
        app.router.go('/stats');
        await StatsTestApp.settle(tester, rounds: 6);
        app.router.go(hostPath);
        await tester.pump();
        await tester.pump();
        expect(find.byType(SwipeDeck), findsWidgets);
        expect(_colorsOf(tester, topCard(tester)).surface, plate);

        // Çıkış: bir sonraki oturumda yeniden oynar.
        await tester.runAsync(
          () => app.container
              .read(sessionControllerProvider.notifier)
              .signOut(callServer: false),
        );
        await tester.pump();
        expect(app.container.read(plateRollSeenProvider), isFalse);
        await app.finish(tester);
      },
    );
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
          final order = await _deckOrder(tester);
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
