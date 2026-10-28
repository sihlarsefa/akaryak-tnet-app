// Tasarım v2 ekran görüntüleri — kimlik, tanıtım, bildirimler, asistan, profil, hava durumu ve kabuk
// (tasarım v2 §7.1–7.3, §7.17). Normal test çalışmasında atlanır; görüntü almak için:
//
//   flutter test test/features/auth/auth_shell_capture_test.dart --dart-define=AKN_SCREENS_DIR=/tam/yol
//
// 390×844 dp ekran 2× piksel PNG olarak yazılır (tahtadaki `screen-*.png` ile aynı ölçü); yazılar
// gerçek Mona Sans ve Material simgeleriyle çizilir (`flutter_test_config.dart`). Altın karşılaştırma
// değildir; gözle tahtayla karşılaştırmak içindir.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akaryakitnet/app/splash/splash_screen.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/models/auth_models.dart';
import 'package:akaryakitnet/core/routing/home_placeholder.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/auth/api.dart';
import 'package:akaryakitnet/features/auth/copy.dart';
import 'package:akaryakitnet/features/auth/presentation/code_page.dart';
import 'package:akaryakitnet/features/weather/presentation/weather_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../profile/a8_kit.dart' as a8;
import 'auth_test_support.dart';

const _outDir = String.fromEnvironment('AKN_SCREENS_DIR');
const _board = Size(390, 844);

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _board;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  debugDisableShadows = false;
  addTearDown(tester.view.reset);
}

Future<void> _end(WidgetTester tester) async {
  AppToast.dismiss();
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  debugDisableShadows = true;
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

const _variants = [
  ('acik-1x', 1.0, Brightness.light),
  ('koyu-1x', 1.0, Brightness.dark),
  ('acik-2x', 2.0, Brightness.light),
];

void main() {
  final skip = _outDir.isEmpty;

  for (final (tag, scale, b) in _variants) {
    testWidgets('giriş $tag', (tester) async {
      _phone(tester);
      await pumpAuthRoute(tester, '/login', textScale: scale, brightness: b);
      await pumpFor(tester, const Duration(seconds: 1));
      await _shot(tester, '01-giris-$tag');
      await _end(tester);
    }, skip: skip);

    testWidgets('tanıtım $tag', (tester) async {
      _phone(tester);
      await pumpAuthRoute(
        tester,
        '/onboarding',
        harness: await AuthHarness.create(prefs: const {}),
        textScale: scale,
        brightness: b,
      );
      for (var i = 1; i <= 3; i++) {
        await pumpFor(tester, const Duration(seconds: 2));
        await _shot(tester, '03-tanitim-$i-$tag');
        if (i < 3) {
          await tester.tap(find.text('Devam'));
          await pumpFor(tester, const Duration(milliseconds: 700));
        }
      }
      await _end(tester);
    }, skip: skip);
  }

  testWidgets('giriş (telefon, hata, kilit)', (tester) async {
    _phone(tester);
    await pumpAuthRoute(tester, '/login');
    final phone = find.text(AuthCopy.modePhone);
    if (phone.evaluate().isNotEmpty) {
      await tapVisible(tester, phone);
      await pumpFor(tester, const Duration(milliseconds: 600));
      await _shot(tester, '01-giris-telefon');
    }
    await _end(tester);
  }, skip: skip);

  testWidgets('kod ekranı', (tester) async {
    _phone(tester);
    await pumpAuthRoute(
      tester,
      '/login/code',
      extra: const CodePageArgs(
        challenge: OtpChallenge(
          challengeId: 'c1',
          maskedPhone: '0532 *** ** 34',
          expiresInSeconds: 180,
          resendInSeconds: 45,
        ),
        purpose: CodePurpose.twoFactor,
      ),
    );
    await pumpFor(tester, const Duration(seconds: 1));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _shot(tester, '02-kod');
    await _end(tester);
  }, skip: skip);

  for (final reason in ['forced', 'optional', 'maintenance', 'server']) {
    testWidgets('güncelleme $reason', (tester) async {
      _phone(tester);
      await pumpAuthRoute(tester, '/update?reason=$reason');
      await pumpFor(tester, const Duration(seconds: 1));
      await _shot(tester, '02-guncelleme-$reason');
      await _end(tester);
    }, skip: skip);
  }

  for (final (tag, scale, b) in _variants) {
    testWidgets('kilit $tag', (tester) async {
      _phone(tester);
      final h = await AuthHarness.create(
        prefs: {'akn.onboardingDone': true, PrefKeys.biometricLock: true},
      );
      final bio = FakeBiometric(outcomes: [BiometricOutcome.cancelled]);
      final c = await pumpAuthRoute(
        tester,
        '/home',
        harness: h,
        textScale: scale,
        brightness: b,
        overrides: [biometricAuthenticatorProvider.overrideWithValue(bio)],
      );
      await signIn(tester, c, 'musteri');
      c.read(sessionControllerProvider.notifier).lock();
      GoRouter.of(tester.element(find.text('ANA SAYFA'))).go('/locked');
      await pumpFor(tester, const Duration(seconds: 1));
      await _shot(tester, '02-kilit-$tag');
      await _end(tester);
    }, skip: skip);
  }

  testWidgets('telefon doğrulama', (tester) async {
    _phone(tester);
    final c = await pumpAuthRoute(tester, '/home');
    await signIn(tester, c, 'musteri');
    unawaited(
      GoRouter.of(
        tester.element(find.text('ANA SAYFA')),
      ).push(AuthRoutes.phone),
    );
    await pumpFor(tester, const Duration(seconds: 1));
    await _shot(tester, '02-telefon-dogrulama');
    await tapVisible(tester, find.text(AuthCopy.sendVerification));
    await pumpFor(tester, const Duration(seconds: 1));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _shot(tester, '02-telefon-dogrulama-kod');
    await _end(tester);
  }, skip: skip);

  // ------------------------------------------------------------------ A8: bildirimler, asistan, profil
  for (final (tag, scale, b) in _variants) {
    for (final (name, location, persona) in const [
      ('04-bildirimler', '/notifications', 'musteri'),
      ('04-bildirim-ayarlari', '/notifications/settings', 'musteri'),
      ('05-asistan', '/assistant', 'musteri'),
      ('06-profil', '/profile', 'musteri'),
      ('06-profil-sifre', '/profile/password', 'musteri'),
      ('06-profil-duzenle', '/profile/edit', 'musteri'),
      ('06-profil-oturumlar', '/profile/sessions', 'musteri'),
      ('06-profil-sil', '/profile/delete-account', 'musteri'),
    ]) {
      testWidgets('$name $tag', (tester) async {
        _phone(tester);
        a8.fixClock();
        await a8.pumpA8(
          tester,
          location,
          persona: persona,
          textScale: scale,
          brightness: b,
        );
        await a8.pumpFor(tester, const Duration(seconds: 1));
        await _shot(tester, '$name-$tag');
        if (name == '05-asistan') {
          final accept = find.text('Kabul ediyorum');
          if (accept.evaluate().isNotEmpty) {
            await a8.tapVisible(tester, accept.first);
            await a8.pumpFor(tester, const Duration(seconds: 1));
            await _shot(tester, '$name-sohbet-$tag');
          }
        }
        await _end(tester);
      }, skip: skip);
    }
  }

  // ------------------------------------------------------------------ Hava durumu, açılış, yer tutucu
  for (final (tag, scale, b) in _variants) {
    testWidgets('hava durumu $tag', (tester) async {
      _phone(tester);
      a8.fixClock();
      await a8.pumpA8(
        tester,
        '/weather-test',
        textScale: scale,
        brightness: b,
        extraRoutes: [
          GoRoute(
            path: '/weather-test',
            builder: (_, _) => AppScaffold(
              title: 'Hava durumu',
              body: ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: const [WeatherCard(lat: 40.99, lng: 29.03)],
              ),
            ),
          ),
        ],
      );
      await a8.pumpFor(tester, const Duration(seconds: 1));
      await _shot(tester, '07-hava-$tag');
      await _end(tester);
    }, skip: skip);

    testWidgets('açılış $tag', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AknTheme.light(),
          darkTheme: AknTheme.dark(),
          themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          home: SplashScreen(onFinished: () {}),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _shot(tester, '00-acilis-baslangic-$tag');
      await pumpFor(tester, const Duration(seconds: 2));
      await _shot(tester, '00-acilis-$tag');
      await _end(tester);
    }, skip: skip);

    testWidgets('yer tutucu ana sayfa $tag', (tester) async {
      _phone(tester);
      a8.fixClock();
      await a8.pumpA8(
        tester,
        '/placeholder',
        textScale: scale,
        brightness: b,
        extraRoutes: [
          GoRoute(
            path: '/placeholder',
            builder: (_, _) => const HomePlaceholder(
              roleLabel: 'Şoför',
              upcoming: [
                (
                  PhosphorIconsRegular.truck,
                  'Teslimatlarım',
                  'Bugünkü duraklar sırayla.',
                ),
                (
                  PhosphorIconsRegular.path,
                  'Yol tarifi',
                  'Tek dokunuşla harita.',
                ),
              ],
            ),
          ),
        ],
      );
      await a8.pumpFor(tester, const Duration(seconds: 1));
      await _shot(tester, '08-yer-tutucu-$tag');
      await _end(tester);
    }, skip: skip);
  }
}
