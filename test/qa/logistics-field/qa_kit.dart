// QA "logistics-field" ortak düzeni: gerçek uygulama (AknApp, gerçek yönlendirici ve kabuk) sahte
// sunucuyla, 360×640 telefonda açılır; şoför kamerası / konumu / dosya deposu, saha konumu / dosya
// deposu ve bağlantı test sahteleriyle değiştirilir (eklenti yok). Ağ yok.
import 'dart:async';
import 'dart:io';

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/offline/connectivity.dart';
import 'package:akaryakitnet/core/routing/nav_keys.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/driver/application/camera.dart';
import 'package:akaryakitnet/features/driver/application/location.dart';
import 'package:akaryakitnet/features/driver/data/deliver_draft.dart';
import 'package:akaryakitnet/features/field/application/lead_wizard_controller.dart';
import 'package:akaryakitnet/features/field/data/field_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../features/driver/support/driver_harness.dart'
    show FakeCamera, FakeLocation, TestFileStore;
import '../../features/field/field_test_kit.dart'
    show FakeFieldLocation, MemoryFieldFileStore;
import '../../support/test_app.dart';

/// Çevrimiçi / çevrimdışı anahtarı (uygulamanın `connectivityProvider`'ı bunu izler).
final qaOnlineProvider = StateProvider<bool>((ref) => true);

/// Açılmış uygulama.
class QaApp {
  QaApp._(
    this.harness,
    this.container,
    this.dir,
    this.camera,
    this.location,
    this.files,
    this.fieldLocation,
    this.fieldFiles,
  );

  final TestHarness harness;
  final ProviderContainer container;
  final Directory dir;
  final FakeCamera camera;
  final FakeLocation location;
  final TestFileStore files;
  final FakeFieldLocation fieldLocation;
  final MemoryFieldFileStore fieldFiles;

  FakeServer get server => harness.server;
  FakeWorld get world => harness.server.world;

  GoRouter router(WidgetTester tester) =>
      GoRouter.of(rootNavigatorKey.currentContext!);

  set online(bool v) => container.read(qaOnlineProvider.notifier).state = v;

  /// Uygulamayı açar (tanıtım görülmüş) ve [persona] ile giriş yapar.
  static Future<QaApp> start(
    WidgetTester tester, {
    required String persona,
    Size size = const Size(360, 640),
    double textScale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final h = await TestHarness.create(
      prefs: const {'akn.onboardingDone': true},
    );
    final dir = Directory.systemTemp.createTempSync('akn_qa_lf_');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final camera = FakeCamera(dir);
    final location = FakeLocation();
    final files = TestFileStore(dir);
    final fieldLocation = FakeFieldLocation()
      ..access = FieldLocationAccess.granted;
    final fieldFiles = MemoryFieldFileStore(dir);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...h.overrides,
          driverCameraProvider.overrideWithValue(camera),
          driverLocationServiceProvider.overrideWithValue(location),
          driverFileStoreProvider.overrideWithValue(files),
          fieldLocationServiceProvider.overrideWithValue(fieldLocation),
          fieldFileStoreProvider.overrideWithValue(fieldFiles),
          connectivityProvider.overrideWith((ref) {
            final ctl = StreamController<bool>();
            ref.listen<bool>(
              qaOnlineProvider,
              (_, v) => ctl.add(v),
              fireImmediately: true,
            );
            ref.onDispose(ctl.close);
            return ctl.stream;
          }),
        ],
        child: const AknApp(),
      ),
    );
    await steps(tester, const Duration(seconds: 2));
    final c = ProviderScope.containerOf(tester.element(find.byType(AknApp)));
    await tester.runAsync(() async {
      final s = c.read(sessionControllerProvider.notifier);
      final outcome = await s.loginWithPassword(persona, 'demo');
      if (outcome is LoginNeedsCode) {
        await s.verifyCode(outcome.challenge.challengeId, '123456');
      }
    });
    await steps(tester, const Duration(seconds: 2));
    await io(tester);
    expect(c.read(sessionControllerProvider), isA<SessionAuthenticated>());
    return QaApp._(
      h,
      c,
      dir,
      camera,
      location,
      files,
      fieldLocation,
      fieldFiles,
    );
  }

  /// Kapatır (zamanlayıcılar boşalsın).
  Future<void> close(WidgetTester tester) async {
    await steps(tester, const Duration(milliseconds: 600));
    await tester.pumpWidget(const SizedBox());
    await steps(tester, const Duration(milliseconds: 400));
  }
}

/// [total] süre boyunca 100 ms adımlarla ilerletir.
Future<void> steps(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

/// Gerçek G/Ç (büyük JSON çözümü, dosya) ilerlesin diye gerçek zamanda kısa bekler.
Future<void> io(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// [done] sağlanana kadar gerçek + sahte zamanı ilerletir.
Future<bool> until(
  WidgetTester tester,
  bool Function() done, {
  int maxRounds = 150,
}) async {
  for (var i = 0; i < maxRounds && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  return done();
}

/// Yerleşim / çalışma hatası yok.
void noErrors(WidgetTester tester, String where) {
  final e = tester.takeException();
  expect(e, isNull, reason: '$where: $e');
}

/// Sayfa ya da bölüm hata durumu görünmüyor.
void noErrorState(String where) {
  expect(find.byType(ErrorState), findsNothing, reason: '$where: hata durumu');
  expect(
    find.textContaining('yüklenemedi'),
    findsNothing,
    reason: '$where: yüklenemedi',
  );
}

/// Alt menü sekmesine dokunur.
Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AnimatedBottomBar),
      matching: find.text(label),
    ),
  );
  await steps(tester, const Duration(milliseconds: 1200));
  await io(tester);
}

/// Görünür kılıp dokunur (en büyük dikey listede kaydırarak).
Future<void> scrollTap(
  WidgetTester tester,
  Finder f, {
  Duration settle = const Duration(milliseconds: 700),
}) async {
  await reveal(tester, f);
  await tester.tap(f.first, warnIfMissed: false);
  await steps(tester, settle);
  await io(tester, rounds: 3);
}

/// Bulucuyu görünür kılar (kaydırarak).
Future<void> reveal(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    final s = find.byType(Scrollable);
    for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
      if (s.evaluate().isEmpty) break;
      await tester.drag(s.last, const Offset(0, -240), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));
    }
  }
  expect(f, findsWidgets, reason: 'bulunamadı: $f');
  await tester.ensureVisible(f.first);
  await tester.pump(const Duration(milliseconds: 200));
}

/// Ekrandaki tüm metinler (hata ayıklama).
List<String> visibleTexts(WidgetTester tester) => [
  for (final e in find.byType(Text).evaluate())
    if ((e.widget as Text).data != null)
      (e.widget as Text).data!
    else if ((e.widget as Text).textSpan != null)
      (e.widget as Text).textSpan!.toPlainText(),
];

/// Ekrandaki RichText metinleri (hata ayıklama).
List<String> richTexts(WidgetTester tester) => [
  for (final e in find.byType(RichText).evaluate())
    (e.widget as RichText).text.toPlainText(),
];
