// Test derlemesinin (TestFlight: `AKN_ENV=test`, `API_MODE=live`) demo yolunun ekran görüntüleri, bütün
// uygulamayla (`AknApp`). Canlı API kayıtçı bir adaptördür (ağ yok); canlı form gönderilmez. Normal test
// çalışmasında atlanır; görüntü almak için:
//
//   flutter test test/features/auth/demo_session_capture_test.dart --dart-define=AKN_SCREENS_DIR=/tam/yol
//
// 1) giriş: "TEST" şeridi, demo kartları ve canlı form birlikte (ilk ekran ve tam boy), 2) "Müşteri ·
// Yönetici" kartı: ana sayfa "DEMO" şeridiyle, 3) Profil → "Çıkış yap": giriş yine "TEST" şeridiyle,
// 4) canlı sunucu bakımda: kartlar kalır, canlı form yerine bakım notu. 2× piksel PNG.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/routing/app_routes.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/a11y.dart' show settleIo;
import '../../support/demo_live_harness.dart';
import 'auth_test_support.dart';

const _outDir = String.fromEnvironment('AKN_SCREENS_DIR');

void _view(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  debugDisableShadows = false;
  addTearDown(tester.view.reset);
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump();
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<ProviderContainer> _launch(
  WidgetTester tester,
  DemoLiveHarness h,
) async {
  await tester.pumpWidget(
    ProviderScope(overrides: h.overrides, child: const AknApp()),
  );
  await pumpFor(tester, const Duration(seconds: 2));
  await settleIo(tester);
  await pumpFor(tester, const Duration(seconds: 1));
  return ProviderScope.containerOf(
    tester.element(find.byType(AknApp)),
    listen: false,
  );
}

Future<void> _end(WidgetTester tester) async {
  AppToast.dismiss();
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  debugDisableShadows = true;
}

void main() {
  final skip = _outDir.isEmpty;
  setUp(() => AknMotion.ambient = false);

  testWidgets('test derlemesi: giriş tam boy (kartlar + canlı form)', (
    tester,
  ) async {
    _view(tester, const Size(390, 1500));
    final h = await DemoLiveHarness.create();
    final c = await _launch(tester, h);
    expect(c.read(appEnvProvider).ribbon, 'TEST');
    expect(find.text('Demo hesaplarıyla girin'), findsOneWidget);
    expect(find.text('Giriş yap'), findsOneWidget);
    await _shot(tester, 'demo-01b-giris-tam-boy-TEST');
    await _end(tester);
  }, skip: skip);

  testWidgets(
    'test derlemesi: giriş → Müşteri yönetici kartı → ana sayfa DEMO → çıkış → giriş TEST',
    (tester) async {
      _view(tester, const Size(390, 844));
      final h = await DemoLiveHarness.create();
      final c = await _launch(tester, h);
      expect(c.read(appEnvProvider).ribbon, 'TEST');
      await _shot(tester, 'demo-01-giris-TEST');

      final before = h.live.requests.length;
      await tapVisible(tester, find.text('Selin Aydın'));
      await pumpUntil(tester, () => isSignedIn(c));
      await pumpFor(tester, const Duration(seconds: 2));
      await settleIo(tester);
      await pumpFor(tester, const Duration(seconds: 2));
      expect(c.read(appEnvProvider).ribbon, 'DEMO');
      expect(h.live.requests.length, before);
      await _shot(tester, 'demo-02-ana-sayfa-DEMO');

      // Profil → "Çıkış yap" → onay.
      c.read(routerProvider).go(AppRoutes.profile);
      await pumpFor(tester, const Duration(seconds: 1));
      await settleIo(tester);
      final signOut = find.text('Çıkış yap');
      await tester.scrollUntilVisible(
        signOut,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpFor(tester, const Duration(milliseconds: 400));
      await _shot(tester, 'demo-02b-profil-DEMO');
      await tester.tap(signOut);
      await pumpFor(tester, const Duration(milliseconds: 600));
      final confirm = find.descendant(
        of: find.byType(AknButton),
        matching: find.text('Çıkış yap'),
      );
      await tester.tap(confirm.last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await pumpUntil(
        tester,
        () => c.read(sessionControllerProvider) is SessionUnauthenticated,
      );
      await pumpFor(tester, const Duration(seconds: 2));
      await settleIo(tester);
      await pumpFor(tester, const Duration(seconds: 1));
      expect(c.read(sessionControllerProvider), isA<SessionUnauthenticated>());
      expect(c.read(appEnvProvider).ribbon, 'TEST');
      expect(find.text('Demo hesaplarıyla girin'), findsOneWidget);
      expect(h.liveRequestsWithTokens, isEmpty);
      await _shot(tester, 'demo-03-cikis-giris-TEST');
      await _end(tester);
    },
    skip: skip,
  );

  testWidgets('test derlemesi: canlı sunucu bakımda, kartlar kalır', (
    tester,
  ) async {
    _view(tester, const Size(390, 844));
    final h = await DemoLiveHarness.create();
    final base = h.live.fallback!;
    h.live.fallback = (o) => o.uri.path.endsWith('/app/config')
        ? ResponseBody.fromString(
            jsonEncode({
              ...liveConfig,
              'maintenance': {'active': true},
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json; charset=utf-8'],
            },
          )
        : base(o);
    await _launch(tester, h);
    expect(find.text('Demo hesaplarıyla girin'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('login.liveGate')));
    await pumpFor(tester, const Duration(milliseconds: 400));
    await _shot(tester, 'demo-04-bakim-kartlar-TEST');
    await _end(tester);
  }, skip: skip);
}
