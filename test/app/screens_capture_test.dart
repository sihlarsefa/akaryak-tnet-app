// Persona ekran görüntüleri (spec D.3 A-INT: "text scale 2.0 + dark mode pass with screenshots per
// persona"). Normal test çalışmasında atlanır; görüntü almak için:
//
//   flutter test test/app/screens_capture_test.dart --dart-define=AKN_SCREENS_DIR=/tam/yol/screens
//
// Her persona için açık 1,0× ve koyu 2,0× varyantında alt menünün her sekmesi ve "Diğer" sayfası
// 360×640 dp (2× piksel) PNG olarak yazılır. Yazılar gerçek Roboto ve Material simgeleriyle çizilir
// (Flutter SDK'nın material_fonts klasörü). Altın (golden) karşılaştırma değildir.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/a11y.dart';
import '../support/test_app.dart';

const _outDir = String.fromEnvironment('AKN_SCREENS_DIR');

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/Users/f2gomac/flutter';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final file = File('$dir/$f');
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await family('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]);
  await family('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    if (_outDir.isNotEmpty) await _loadFonts();
  });

  const variants = [
    ('acik-1x', A11yVariant(1, Brightness.light)),
    ('koyu-2x', A11yVariant.largeDark),
  ];

  for (final persona in fakePersonas) {
    for (final (tag, variant) in variants) {
      testWidgets('${persona.key} $tag ekran görüntüleri', (tester) async {
        setA11yPhone(tester);
        setA11yPlatform(tester, variant);
        // Test ortamı gölgeleri siyah çerçeve olarak çizer; görüntüde gerçek gölge olsun.
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = true);
        // Gerçek telefondaki gibi durum çubuğu (Android 24 dp): üst çubuk ve ortam şeridi yerinde durur.
        tester.view.padding = const FakeViewPadding(top: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 24);
        final key = GlobalKey();
        final h = await TestHarness.create(
          prefs: const {'akn.onboardingDone': true},
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: ProviderScope(overrides: h.overrides, child: const AknApp()),
          ),
        );
        await pumpSteps(tester, const Duration(seconds: 2));
        final c = ProviderScope.containerOf(
          tester.element(find.byType(AknApp)),
        );
        if (persona == fakePersonas.first) {
          await _capture(tester, key, 'giris/giris_$tag');
        }
        await tester.runAsync(() async {
          final s = c.read(sessionControllerProvider.notifier);
          final outcome = await s.loginWithPassword(persona.key, 'demo');
          if (outcome is LoginNeedsCode) {
            await s.verifyCode(outcome.challenge.challengeId, '123456');
          }
        });
        await pumpSteps(tester, const Duration(seconds: 3));
        expect(c.read(sessionControllerProvider), isA<SessionAuthenticated>());
        final layout = c.read(navLayoutProvider);
        final bar = find.byType(AnimatedBottomBar);
        for (var i = 0; i < layout.bar.length; i++) {
          if (i > 0) {
            await tester.tap(
              find.descendant(
                of: bar,
                matching: find.text(layout.bar[i].barLabel),
              ),
            );
            await pumpSteps(tester, const Duration(seconds: 2));
          }
          await settleIo(tester);
          await pumpSteps(tester, const Duration(milliseconds: 800));
          await _capture(
            tester,
            key,
            '${persona.key}/${persona.key}_${tag}_${i + 1}_${layout.bar[i].id.name}',
          );
        }
        if (layout.hasMore) {
          await tester.tap(
            find.descendant(of: bar, matching: find.text(NavLayout.moreLabel)),
          );
          await pumpSteps(tester, const Duration(seconds: 1));
          await _capture(
            tester,
            key,
            '${persona.key}/${persona.key}_${tag}_diger',
          );
        }
        await tester.pumpWidget(const SizedBox());
        debugDisableShadows = true;
      }, skip: _outDir.isEmpty);
    }
  }
}
