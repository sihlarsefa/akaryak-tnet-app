// Arka ucun gerçek DTO'larından üretilmiş örnekler (`work/akn-mobile/contract-samples/stats-bayi.json`,
// `stats-customer.json`; BE ajanı, 2026-10-20 sabit saatiyle) uygulamanın istatistik modelleriyle okunur
// ve desteleri taşmadan çizilir. Örnekler burada kopyadır (test makineden bağımsız); sunucu alan adı ya
// da tipi değişirse bu test kırılır. Genel sözleşme denetimi `test/contract/` altındadır.
import 'dart:convert';

import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/stats/data/stats_models.dart';
import 'package:akaryakitnet/features/stats/presentation/deck/deck_cards.dart';
import 'package:akaryakitnet/features/stats/presentation/deck/manager_stats_deck.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/stats_app.dart' show tapDeckNext;

const _bayiJson = r'''
{
  "stationId": 1, "stationTitle": "Merkez Petrol", "scope": "station",
  "generatedAt": "2026-10-20T11:00:00+00:00",
  "period": { "key": "month", "label": "Bu ay", "from": "2026-10-01", "to": "2026-10-20",
              "compareLabel": "Geçen ayın aynı dönemi",
              "compareFrom": "2026-09-01", "compareTo": "2026-09-20" },
  "sales": { "orders": 5, "liters": 21000.0, "amount": 872000.0, "prevOrders": 1, "prevLiters": 6000.0,
             "prevAmount": 234000.0, "avgUnitPrice": 41.52, "prevAvgUnitPrice": 39,
             "activeCustomers": 4, "newCustomers": 1 },
  "months": [
    { "year": 2026, "month": 5, "label": "May", "orders": 0, "liters": 0, "amount": 0 },
    { "year": 2026, "month": 6, "label": "Haz", "orders": 0, "liters": 0, "amount": 0 },
    { "year": 2026, "month": 7, "label": "Tem", "orders": 1, "liters": 7000.0, "amount": 266000.0 },
    { "year": 2026, "month": 8, "label": "Ağu", "orders": 1, "liters": 1000.0, "amount": 42000.0 },
    { "year": 2026, "month": 9, "label": "Eyl", "orders": 2, "liters": 8000.0, "amount": 314000.0 },
    { "year": 2026, "month": 10, "label": "Eki", "orders": 5, "liters": 21000.0, "amount": 872000.0 }
  ],
  "products": [
    { "productId": 1, "name": "Motorin", "liters": 16000.0, "amount": 650000.0, "share": 0.7454 },
    { "productId": 2, "name": "Benzin", "liters": 5000.0, "amount": 222000.0, "share": 0.2546 }
  ],
  "topCustomers": [
    { "customerId": 1, "title": "Acar Nakliyat", "orders": 2, "liters": 13000.0, "amount": 532000.0, "share": 0.6101 },
    { "customerId": 2, "title": "Bora İnşaat", "orders": 1, "liters": 5000.0, "amount": 210000.0, "share": 0.2408 },
    { "customerId": 3, "title": "Deniz Lojistik", "orders": 1, "liters": 2000.0, "amount": 90000.0, "share": 0.1032 },
    { "customerId": 5, "title": "Ege Lojistik", "orders": 1, "liters": 1000.0, "amount": 40000.0, "share": 0.0459 }
  ],
  "funnel": { "requests": 11, "quoted": 8, "accepted": 5, "rejected": 1, "expired": 1,
              "conversionRate": 0.4545, "avgFirstQuoteMinutes": 26 },
  "deliveries": { "delivered": 4, "deliveredLiters": 19850.0, "onTimeRate": 0.75, "inTransit": 1,
                  "planned": 1, "disputes": 1 },
  "collections": { "collectedAmount": 40000.0, "collectedCount": 1, "overdueAmount": 400000.0,
                   "overdueCount": 1, "dueSoonAmount": 55000.0, "dueSoonCount": 2, "dueSoonDays": 7 },
  "team": [
    { "userId": "rep", "name": "Rıza Saha", "forms": 2, "converted": 1, "liters": 5000.0 },
    { "userId": "rep2", "name": "Selin Saha", "forms": 1, "converted": 1, "liters": 2000.0 }
  ],
  "risk": { "nearLimitCount": 1,
            "nearLimit": [ { "customerId": 1, "title": "Acar Nakliyat", "usageRate": 5.602 } ] },
  "failedSections": []
}
''';

const _customerJson = r'''
{
  "customerId": 1, "customerTitle": "Acar Nakliyat", "generatedAt": "2026-10-20T11:00:00+00:00",
  "period": { "key": "month", "label": "Bu ay", "from": "2026-10-01", "to": "2026-10-20",
              "compareLabel": "Geçen ayın aynı dönemi",
              "compareFrom": "2026-09-01", "compareTo": "2026-09-20" },
  "spending": { "orders": 3, "liters": 16000.0, "amount": 655000.0, "prevOrders": 1, "prevLiters": 6000.0,
                "prevAmount": 234000.0, "avgUnitPrice": 40.94, "prevAvgUnitPrice": 39 },
  "months": [
    { "year": 2026, "month": 5, "label": "May", "orders": 0, "liters": 0, "amount": 0 },
    { "year": 2026, "month": 6, "label": "Haz", "orders": 0, "liters": 0, "amount": 0 },
    { "year": 2026, "month": 7, "label": "Tem", "orders": 0, "liters": 0, "amount": 0 },
    { "year": 2026, "month": 8, "label": "Ağu", "orders": 1, "liters": 1000.0, "amount": 42000.0 },
    { "year": 2026, "month": 9, "label": "Eyl", "orders": 1, "liters": 6000.0, "amount": 234000.0 },
    { "year": 2026, "month": 10, "label": "Eki", "orders": 3, "liters": 16000.0, "amount": 655000.0 }
  ],
  "products": [
    { "productId": 1, "name": "Motorin", "liters": 13000.0, "amount": 523000.0, "share": 0.7985 },
    { "productId": 2, "name": "Benzin", "liters": 3000.0, "amount": 132000.0, "share": 0.2015 }
  ],
  "stations": [
    { "stationId": 1, "title": "Merkez Petrol", "liters": 13000.0, "amount": 532000.0, "share": 0.8122 },
    { "stationId": 2, "title": "Kuzey Petrol", "liters": 3000.0, "amount": 123000.0, "share": 0.1878 }
  ],
  "deliveryPoints": [
    { "deliveryPointId": 1, "name": "Tuzla Depo", "city": "İstanbul", "liters": 13000.0, "amount": 523000.0, "share": 0.7985 },
    { "deliveryPointId": 2, "name": "Gebze Şantiye", "city": "Kocaeli", "liters": 3000.0, "amount": 132000.0, "share": 0.2015 }
  ],
  "orders": { "awaitingQuote": 2, "awaitingDecision": 1, "awaitingCompanyApproval": 1, "inTransit": 1,
              "delivered": 2, "disputed": 1 },
  "limits": [
    { "stationId": 2, "stationTitle": "Kuzey Petrol", "limit": 20000.0, "used": 5000, "available": 15000.0,
      "usageRate": 0.25, "unit": "L", "periodLabel": "Bu ay" },
    { "stationId": 1, "stationTitle": "Merkez Petrol", "limit": 100000.0, "used": 560200, "available": 0,
      "usageRate": 5.602, "unit": "TL", "periodLabel": "Bu ay" }
  ],
  "failedSections": []
}
''';

final _bayi = BayiStats.fromJson(jsonDecode(_bayiJson));
final _customer = CustomerStats.fromJson(jsonDecode(_customerJson));

/// Desteyi verilen kartlarla, gerçek tema ve tercihlerle çizer.
Future<void> _pumpDeck(
  WidgetTester tester,
  List<DeckCardSpec> Function(BuildContext context) cards, {
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  SharedPreferences.setMockInitialValues({'akn.stats.deckHint': true});
  final sp = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [prefsStoreProvider.overrideWithValue(PrefsStore(sp))],
      child: MaterialApp(
        theme: AknTheme.light(),
        darkTheme: AknTheme.dark(),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Builder(
                builder: (context) =>
                    SwipeDeck(cards: cards(context), onRefresh: () async {}),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 900));
}

/// Kartları sırayla üste getirir; kimlikleri döner. v4 (§4): şerit "1 / N" yazmaz; sonraki karta
/// destenin "Sonraki kart" ekran okuyucu eylemiyle geçilir (`support/stats_app.dart`).
Future<List<String>> _visitAll(WidgetTester tester) async {
  final ids = <String>[];
  for (var i = 0; i < 10; i++) {
    final top = tester
        .widgetList<DeckCardView>(find.byType(DeckCardView))
        .where((v) => v.raised)
        .last
        .card
        .id;
    if (ids.contains(top)) break;
    ids.add(top);
    await tapDeckNext(tester);
    await tester.pump(const Duration(milliseconds: 400));
  }
  return ids;
}

void main() {
  group('bayi örneği', () {
    test('okunur', () {
      final s = _bayi;
      expect(s.stationTitle, 'Merkez Petrol');
      expect(s.generatedAt, DateTime.utc(2026, 10, 20, 11));
      expect(s.period.key, StatsPeriod.month);
      expect(s.period.compareLabel, 'Geçen ayın aynı dönemi');
      expect(s.sales!.prevUnitPrice, 39, reason: 'tamsayı ondalık okunur');
      expect(s.months, hasLength(6));
      expect(s.months.first.amount, 0, reason: 'boş aylar sıfır');
      expect(s.months[3].shortLabel, 'Ağu');
      expect(s.products.map((p) => p.name), ['Motorin', 'Benzin']);
      expect(s.topCustomers, hasLength(4));
      expect(s.topCustomers[1].title, 'Bora İnşaat');
      expect(s.funnel!.conversion, 0.4545);
      expect(s.deliveries!.onTimeRate, 0.75);
      expect(s.collections!.overdueAmount, 400000);
      expect(s.team.map((m) => m.userId), ['rep', 'rep2']);
      expect(s.risk!.nearLimit.single.usageRate, 5.602, reason: 'aşım > 1');
    });

    testWidgets('8 kartın hepsi çizilir (1,0× açık ve 2,0× koyu)', (
      tester,
    ) async {
      for (final (scale, brightness) in [
        (1.0, Brightness.light),
        (2.0, Brightness.dark),
      ]) {
        await _pumpDeck(
          tester,
          (context) => bayiDeckCards(context, _bayi, own: false),
          textScale: scale,
          brightness: brightness,
        );
        expect(await _visitAll(tester), [
          DeckCards.sales,
          DeckCards.fuel,
          DeckCards.funnel,
          DeckCards.collections,
          DeckCards.deliveries,
          DeckCards.topCustomers,
          DeckCards.team,
          DeckCards.risk,
        ]);
      }
    });
  });

  group('müşteri örneği', () {
    test('okunur', () {
      final s = _customer;
      expect(s.customerTitle, 'Acar Nakliyat');
      expect(s.spending!.unitPrice, 40.94);
      expect(s.stations.map((x) => x.title), ['Merkez Petrol', 'Kuzey Petrol']);
      expect(s.deliveryPoints.first.city, 'İstanbul');
      expect(s.orders!.open, 2 + 1 + 1 + 1);
      expect(s.orders!.delivered, 2);
      final litre = s.limits[0];
      expect(litre.isLiters, isTrue);
      expect(litre.available, 15000);
      final tl = s.limits[1];
      expect(tl.isLiters, isFalse);
      expect(tl.usageRate, 5.602);
      expect(tl.available, 0);
    });

    testWidgets('6 kartın hepsi çizilir (1,0× açık ve 2,0× koyu)', (
      tester,
    ) async {
      for (final (scale, brightness) in [
        (1.0, Brightness.light),
        (2.0, Brightness.dark),
      ]) {
        await _pumpDeck(
          tester,
          (context) => customerDeckCards(context, _customer),
          textScale: scale,
          brightness: brightness,
        );
        expect(await _visitAll(tester), [
          DeckCards.spend,
          DeckCards.purchase,
          DeckCards.unitPrice,
          DeckCards.limits,
          DeckCards.points,
          DeckCards.orderStatus,
        ]);
      }
    });
  });
}
