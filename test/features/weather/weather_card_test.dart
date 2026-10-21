// Hava durumu kartı ve sürüş bandı (spec A.6): veri, sürüş durumu, bant varken kartın tekrar
// yazmaması, kapalı / alınamıyor durumları, ayrıntı sayfası, erişilebilirlik (C.7).
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/weather/api.dart';
import 'package:akaryakitnet/features/weather/weather_fake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../profile/a8_kit.dart';

/// İzmit (yarın sabah yoğun yağış senaryosu) ve Tuzla (açık).
const _izmit = (lat: 40.7654, lng: 29.9408);
const _tuzla = (lat: 40.9119, lng: 29.3014);

GoRoute _host({bool banner = false, ({double lat, double lng}) at = _izmit}) =>
    GoRoute(
      path: '/weather-host',
      builder: (context, state) => AppScaffold(
        title: 'Teslimat',
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (banner) DrivingAlertBanner(lat: at.lat, lng: at.lng),
            WeatherCard(lat: at.lat, lng: at.lng),
          ],
        ),
      ),
    );

void main() {
  setUp(fixClock);

  a11yMatrix('hava kartı + sürüş bandı', (tester, scale, b) async {
    fixClock();
    await pumpA8(
      tester,
      '/weather-host',
      textScale: scale,
      brightness: b,
      extraRoutes: [_host(banner: true)],
    );
    expect(find.text('Yarın sabah yoğun yağış'), findsOneWidget);
    expect(find.text('Open-Meteo'), findsOneWidget);
  });

  testWidgets(
    'açık hava: sıcaklık, durum, sonraki saatler, "Sürüş için uygun hava"',
    (tester) async {
      setPhoneSize(tester);
      final h = await A8Harness.create();
      await pumpA8(
        tester,
        '/weather-host',
        harness: h,
        extraRoutes: [_host(at: _tuzla)],
      );
      expect(find.byType(WeatherCard), findsOneWidget);
      expect(find.textContaining('°'), findsWidgets);
      expect(find.text('Sürüş için uygun hava'), findsOneWidget);
      expect(find.text('Open-Meteo'), findsOneWidget);
      expect(h.weather.calls, 1);
      await finish(tester);
    },
  );

  testWidgets('bant uyarıyı gösterirken kart sürüş durumunu tekrar yazmaz', (
    tester,
  ) async {
    setPhoneSize(tester);
    final h = await A8Harness.create();
    await pumpA8(
      tester,
      '/weather-host',
      harness: h,
      extraRoutes: [_host(banner: true)],
    );
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('Yarın sabah yoğun yağış'), findsOneWidget);
    expect(
      find.text('Hızınızı düşürün; takip mesafesini iki katına çıkarın.'),
      findsOneWidget,
    );
    expect(find.text('Sürüş için uygun hava'), findsNothing);
    expect(h.weather.calls, 1, reason: 'kart ve bant aynı veriyi paylaşır');
    await finish(tester);
  });

  testWidgets('bant yokken kart uyarıyı kendi şeridinde gösterir', (
    tester,
  ) async {
    setPhoneSize(tester);
    await pumpA8(tester, '/weather-host', extraRoutes: [_host()]);
    expect(find.text('Yarın sabah yoğun yağış'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('uyarı yoksa bant hiçbir şey çizmez', (tester) async {
    setPhoneSize(tester);
    await pumpA8(
      tester,
      '/weather-host',
      extraRoutes: [_host(banner: true, at: _tuzla)],
    );
    expect(find.byType(AknBanner), findsNothing);
    expect(find.text('Sürüş için uygun hava'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('sunucuda kapalı (503 "kapalı") → kart gizlenir', (tester) async {
    setPhoneSize(tester);
    final h = await A8Harness.create();
    h.weather.disabled = true;
    await pumpA8(tester, '/weather-host', harness: h, extraRoutes: [_host()]);
    expect(find.byType(AknCard), findsNothing);
    expect(find.text('Hava durumu şu an alınamıyor'), findsNothing);
    await finish(tester);
  });

  testWidgets('kaynak yanıt vermiyor → "alınamıyor" + yeniden dene', (
    tester,
  ) async {
    setPhoneSize(tester);
    final h = await A8Harness.create();
    h.weather.failing = true;
    await pumpA8(tester, '/weather-host', harness: h, extraRoutes: [_host()]);
    expect(find.text('Hava durumu şu an alınamıyor'), findsOneWidget);
    h.weather.failing = false;
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Yarın sabah yoğun yağış'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('özellik kapalıyken (features.weather) istek bile atılmaz', (
    tester,
  ) async {
    setPhoneSize(tester);
    final h = await A8Harness.create();
    await pumpA8(
      tester,
      '/weather-host',
      harness: h,
      persona: null,
      extraRoutes: [_host()],
    );
    expect(find.byType(AknCard), findsNothing);
    expect(h.weather.calls, 0);
    await finish(tester);
  });

  testWidgets('dokununca saatlik ve 3 günlük tahmin, Open-Meteo atfı', (
    tester,
  ) async {
    setPhoneSize(tester, const Size(390, 844));
    await pumpA8(tester, '/weather-host', extraRoutes: [_host(at: _tuzla)]);
    await tester.tap(find.byType(WeatherCard));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Saatlik'), findsOneWidget);
    expect(find.text('Şimdi'), findsOneWidget);
    expect(find.text('3 günlük'), findsOneWidget);
    expect(find.text('Bugün'), findsOneWidget);
    expect(find.text('Yarın'), findsOneWidget);
    expect(find.text('Hava verisi: Open-Meteo.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('ileri teslimat: bant teslimat saatine göre değerlendirir', (
    tester,
  ) async {
    setPhoneSize(tester);
    final h = await A8Harness.create();
    h.weather.scenario = WeatherScenario.heavyRain;
    await pumpA8(
      tester,
      '/weather-host',
      harness: h,
      extraRoutes: [
        GoRoute(
          path: '/weather-host',
          builder: (_, _) => Scaffold(
            body: ListView(
              children: [
                DrivingAlertBanner(
                  lat: _tuzla.lat,
                  lng: _tuzla.lng,
                  at: a8Now.add(const Duration(hours: 22)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    expect(find.text('Yarın sabah yoğun yağış'), findsOneWidget);
    await finish(tester);
  });
}
