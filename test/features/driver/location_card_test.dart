import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/driver/application/location.dart';
import 'package:akaryakitnet/features/driver/copy.dart';
import 'package:akaryakitnet/features/driver/presentation/widgets/location_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/driver_harness.dart';

void main() {
  late FakeLocation service;
  late LocationCapture capture;

  Future<void> pump(
    WidgetTester tester, {
    required bool required,
    Brightness brightness = Brightness.light,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await real(tester, SharedPreferences.getInstance);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsStoreProvider.overrideWithValue(PrefsStore(prefs))],
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
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [LocationCard(capture: capture, required: required)],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    service = FakeLocation();
    capture = LocationCapture(service);
  });

  tearDown(() => capture.dispose());

  testWidgets('izin verilmiş: konum alınır, hassasiyet gösterilir', (
    tester,
  ) async {
    await pump(tester, required: true);
    await tester.runAsync(capture.prime);
    await tester.pump();
    expect(find.text(DriverCopy.locationOk('±8 m')), findsOneWidget);
  });

  testWidgets('düşük hassasiyet: uyarı + "Tekrar dene"', (tester) async {
    service.accuracy = 180;
    await pump(tester, required: false);
    await tester.runAsync(capture.prime);
    await tester.pump();
    expect(find.text(DriverCopy.locationLowAccuracy('±180 m')), findsOneWidget);
    expect(find.text(DriverCopy.locationRetry), findsOneWidget);
  });

  testWidgets(
    'kalıcı ret: "Ayarları aç"; zorunlu değilse "Konumsuz devam et"',
    (tester) async {
      service.perm = DriverLocationPermission.deniedForever;
      await pump(tester, required: false);
      await tester.runAsync(capture.prime);
      await tester.pump();
      expect(find.text(DriverCopy.locationDenied), findsOneWidget);
      expect(find.text(DriverCopy.locationOpenSettings), findsOneWidget);
      await tester.tap(find.text(DriverCopy.locationSkip));
      await tester.pump();
      expect(capture.phase, LocationPhase.skipped);
      expect(find.text(DriverCopy.locationSkipped), findsOneWidget);
    },
  );

  testWidgets('kalıcı ret ve konum zorunlu: "Konumsuz devam et" yok', (
    tester,
  ) async {
    service.perm = DriverLocationPermission.deniedForever;
    await pump(tester, required: true);
    await tester.runAsync(capture.prime);
    await tester.pump();
    expect(find.text(DriverCopy.locationSkip), findsNothing);
    await tester.tap(find.text(DriverCopy.locationOpenSettings));
    await tester.pump();
    expect(service.settingsOpened, 1);
  });

  testWidgets('konum servisi kapalı ve alınamayan konum', (tester) async {
    service.enabled = false;
    await pump(tester, required: true);
    await tester.runAsync(capture.prime);
    await tester.pump();
    expect(find.text(DriverCopy.locationServiceOff), findsOneWidget);

    service
      ..enabled = true
      ..fail = true;
    await tester.runAsync(capture.requestAndAcquire);
    await tester.pump();
    expect(find.text(DriverCopy.locationFailed), findsOneWidget);
    service.fail = false;
    await tester.tap(find.text(DriverCopy.locationRetry));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(capture.phase, LocationPhase.ready);
  });

  testWidgets('izin sorulmadı: "Konum ekle" → ön sayfa → "Şimdi değil" sistem '
      'penceresini açmaz', (tester) async {
    service.perm = DriverLocationPermission.notDetermined;
    await pump(tester, required: false);
    await tester.runAsync(capture.prime);
    await tester.pump();
    expect(capture.phase, LocationPhase.needsPermission);
    await tester.tap(find.text(DriverCopy.locationAdd));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text(DriverCopy.primerLocationTitle), findsOneWidget);
    await tester.tap(find.text(DriverCopy.primerNotNow));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(service.requests, 0);
    await tester.tap(find.text(DriverCopy.locationAdd));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text(DriverCopy.primerContinue));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(service.requests, 1);
    expect(capture.phase, LocationPhase.ready);
  });

  for (final b in Brightness.values) {
    testWidgets('erişilebilirlik (${b.name})', (tester) async {
      final handle = tester.ensureSemantics();
      phoneSize(tester);
      service.perm = DriverLocationPermission.deniedForever;
      await pump(tester, required: false, brightness: b);
      await tester.runAsync(capture.prime);
      await tester.pump();
      await expectA11y(tester);
      handle.dispose();
    });
  }
}
