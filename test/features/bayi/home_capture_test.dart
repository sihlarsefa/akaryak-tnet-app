// Bayi ve saha ana sayfalarının tasarım v2 ekran görüntüleri (tahta ekran 3 / 8 ile karşılaştırma
// için). Normal test çalışmasında atlanır; görüntü almak için:
//
//   flutter test test/features/bayi/home_capture_test.dart --dart-define=AKN_SCREENS_DIR=/tam/yol
//
// Tam uygulama (kabuk, alt menü, zil) 390 × 844 dp'de, 47 dp durum çubuğuyla, 2× piksel; her persona
// için ilk ekran ve aşağı kaydırılmış ikinci ekran. Tüpraş şeridinde değişim görünsün diye cihazdaki
// fiyat geçmişine dünün fiyatları yazılır.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/offline/cache_store.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/bayi/application/role_tip.dart';
import 'package:akaryakitnet/features/field/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/a11y.dart';
import '../../support/test_app.dart';

const _outDir = String.fromEnvironment('AKN_SCREENS_DIR');

/// Yalnızca bu personalar (boşsa hepsi): `--dart-define=AKN_HOME_PERSONAS=sahip,siparis`.
const _only = String.fromEnvironment('AKN_HOME_PERSONAS');

const _personas = [
  'sahip',
  'mudur',
  'finans',
  'muhasebe',
  'satis',
  'saha',
  'siparis',
  'sevkiyat',
  'depo',
  'izleyici',
];

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

/// Dünün Tüpraş fiyatları (₺/L): Motorin 0,38 ucuz, benzin aynı, kalorifer 0,12 pahalı.
Future<void> _seedTuprasHistory(ProviderContainer c, String uid) async {
  final today = TrTime.isoDate(TrTime.todayStart());
  final yesterday = TrTime.isoDate(TrTime.addDays(TrTime.todayStart(), -1));
  await c.read(cacheStoreProvider).write(
    CacheKeys.user(uid, 'tupras.history.İZMİT'),
    {
      'day': today,
      'prices': {'1': 38.40, '2': 40.90, '3': 35.30},
      'prevDay': yesterday,
      'prev': {'1': 38.02, '2': 40.90, '3': 35.42},
    },
    userId: uid,
  );
  c.invalidate(tuprasPricesProvider);
}

void main() {
  const variants = [
    ('acik-1x', A11yVariant(1, Brightness.light)),
    ('koyu-1x', A11yVariant(1, Brightness.dark)),
    ('acik-2x', A11yVariant(2, Brightness.light)),
  ];
  final personas = _only.isEmpty ? _personas : _only.split(',');

  for (final key in personas) {
    for (final (tag, variant) in variants) {
      testWidgets('$key $tag ana sayfa görüntüsü', (tester) async {
        setA11yPhone(tester, size: const Size(390, 844));
        setA11yPlatform(tester, variant);
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = true);
        tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
        final boundary = GlobalKey();
        final h = await TestHarness.create(
          prefs: const {'akn.onboardingDone': true},
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: ProviderScope(overrides: h.overrides, child: const AknApp()),
          ),
        );
        await pumpSteps(tester, const Duration(seconds: 2));
        final c = ProviderScope.containerOf(
          tester.element(find.byType(AknApp)),
        );
        await tester.runAsync(() async {
          final s = c.read(sessionControllerProvider.notifier);
          final outcome = await s.loginWithPassword(key, 'demo');
          if (outcome is LoginNeedsCode) {
            await s.verifyCode(outcome.challenge.challengeId, '123456');
          }
        });
        await pumpSteps(tester, const Duration(seconds: 2));
        expect(c.read(sessionControllerProvider), isA<SessionAuthenticated>());
        final uid = findFakePersona(key)!.userId;
        await tester.runAsync(() async {
          await c.read(bayiRoleTipProvider.notifier).dismiss();
          await _seedTuprasHistory(c, uid);
        });
        await settleIo(tester);
        await pumpSteps(tester, const Duration(seconds: 3));
        await _capture(tester, boundary, 'home/${key}_${tag}_1');
        final scrollables = find.byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.vertical,
        );
        if (scrollables.evaluate().isNotEmpty) {
          final pos = tester.state<ScrollableState>(scrollables.first).position;
          for (var page = 2; page <= 4; page++) {
            if (pos.pixels >= pos.maxScrollExtent) break;
            pos.jumpTo(
              (pos.pixels + 640).clamp(0, pos.maxScrollExtent).toDouble(),
            );
            await pumpSteps(tester, const Duration(milliseconds: 600));
            await _capture(tester, boundary, 'home/${key}_${tag}_$page');
          }
        }
        await tester.pumpWidget(const SizedBox());
        debugDisableShadows = true;
      }, skip: _outDir.isEmpty);
    }
  }
}
