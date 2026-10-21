// Son doğrulama ekran görüntüleri (G renk dili, sahip kararları 2026-10-21): her persona için giriş,
// ana sayfa (ilk ekran + kaydırılmış), alt menünün her sekmesi, `/stats`, bir sipariş ayrıntısı ve
// sipariş sihirbazı; açık 1,0×, koyu 1,0× ve açık 2,0×. Normal test çalışmasında atlanır:
//
//   flutter test test/app/final_capture_test.dart --dart-define=AKN_SCREENS_DIR=/tam/yol
//
// 390×844 (durum çubuğu 47, ev çizgisi 34), 2× piksel PNG; gerçek yazı tipleri
// (`flutter_test_config.dart`). Görüntü sırasında taşma ya da istisna olursa test düşer.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/routing/route_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/a11y.dart';
import '../support/test_app.dart';

const _outDir = String.fromEnvironment('AKN_SCREENS_DIR');

/// Yalnızca bu personalar (virgülle ayrılmış anahtarlar; boşsa hepsi).
const _only = String.fromEnvironment('AKN_ONLY');

const _personas = [
  'musteri',
  'onay',
  'talep',
  'sahip',
  'mudur',
  'finans',
  'muhasebe',
  'satis',
  'saha',
  'siparis',
  'sevkiyat',
  'sofor',
  'depo',
  'izleyici',
];

const _variants = [
  ('acik-1x', 1.0, Brightness.light),
  ('koyu-1x', 1.0, Brightness.dark),
  ('acik-2x', 2.0, Brightness.light),
];

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

void main() {
  for (final key in _personas) {
    for (final (tag, scale, b) in _variants) {
      testWidgets(
        '$key $tag',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
          tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
          addTearDown(tester.view.reset);
          setA11yPlatform(tester, A11yVariant(scale, b));
          debugDisableShadows = false;
          addTearDown(() => debugDisableShadows = true);

          final errors = <String>[];
          final original = FlutterError.onError;
          FlutterError.onError = (d) {
            final where = RegExp(r'akaryakitnet-mobile/(lib/[^\s:]+\.dart:\d+)')
                .allMatches(d.toString())
                .map((m) => m.group(1))
                .toSet()
                .join(', ');
            errors.add('${d.exceptionAsString().split('\n').first} [$where]');
          };
          try {
            final h = await TestHarness.create(
              prefs: const {'akn.onboardingDone': true},
            );
            await tester.pumpWidget(
              ProviderScope(overrides: h.overrides, child: const AknApp()),
            );
            await pumpSteps(tester, const Duration(seconds: 2));
            final c = ProviderScope.containerOf(
              tester.element(find.byType(AknApp)),
            );
            final dir = '$key/${key}_$tag';
            if (key == _personas.first) {
              await _shot(tester, 'giris/giris_$tag');
            }
            await tester.runAsync(() async {
              final s = c.read(sessionControllerProvider.notifier);
              final outcome = await s.loginWithPassword(key, 'demo');
              if (outcome is LoginNeedsCode) {
                await s.verifyCode(outcome.challenge.challengeId, '123456');
              }
            });
            await pumpSteps(tester, const Duration(seconds: 3));
            await settleIo(tester);
            expect(
              c.read(sessionControllerProvider),
              isA<SessionAuthenticated>(),
            );
            await pumpSteps(tester, const Duration(seconds: 2));
            await _shot(tester, '${dir}_1_ana');

            Future<void> scrolled(String name) async {
              final lists = find.byType(Scrollable);
              if (lists.evaluate().isEmpty) return;
              var best = lists.first;
              var area = -1.0;
              for (var i = 0; i < lists.evaluate().length; i++) {
                final s = tester.widget<Scrollable>(lists.at(i));
                if (axisDirectionToAxis(s.axisDirection) != Axis.vertical) {
                  continue;
                }
                final size = tester.getSize(lists.at(i));
                if (size.width * size.height > area) {
                  area = size.width * size.height;
                  best = lists.at(i);
                }
              }
              await tester.drag(
                best,
                const Offset(0, -560),
                warnIfMissed: false,
              );
              await pumpSteps(tester, const Duration(milliseconds: 900));
              await _shot(tester, name);
            }

            await scrolled('${dir}_2_ana_kaydirilmis');

            final router = c.read(routerProvider);
            final layout = c.read(navLayoutProvider);
            final policy = AccessPolicy(
              c.read(sessionControllerProvider).access,
            );
            final features = c.read(appConfigProvider).features;
            bool allowed(String r) =>
                RouteAccess.isAllowed(r, policy, features);

            Future<void> open(String route, String name) async {
              if (!allowed(route)) return;
              router.go(route);
              await pumpSteps(tester, const Duration(milliseconds: 1500));
              await settleIo(tester, rounds: 4);
              await pumpSteps(tester, const Duration(milliseconds: 600));
              await _shot(tester, name);
            }

            // Alt menü sekmeleri (ilki ana sayfa).
            for (var i = 1; i < layout.bar.length; i++) {
              final d = layout.bar[i];
              await open(d.path, '${dir}_3_sekme${i + 1}_${d.id.name}');
            }
            await open('/stats', '${dir}_4_istatistik');
            final w = h.server.world;
            final customerOrder = w
                .ordersOfCustomer(101)
                .firstWhere(
                  (o) => o['id'] == 12002,
                  orElse: () => w.ordersOfCustomer(101).first,
                )['id'];
            await open('/orders/$customerOrder', '${dir}_5_siparis');
            final bayiOrder = w.ordersOfStation(1).first['id'];
            await open('/bayi/orders/$bayiOrder', '${dir}_5_bayi_siparis');
            await open('/orders/new', '${dir}_6_sihirbaz');
            await open('/approvals', '${dir}_7_onaylar');
            await open('/payments', '${dir}_8_tahsilat');

            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          } finally {
            FlutterError.onError = original;
            debugDisableShadows = true;
            if (errors.isNotEmpty) {
              File('$_outDir/_hatalar.txt')
                ..createSync(recursive: true)
                ..writeAsStringSync(
                  '${errors.map((e) => '$key $tag: $e').join('\n')}\n',
                  mode: FileMode.append,
                );
            }
          }
          expect(errors, isEmpty, reason: errors.join('\n'));
        },
        skip:
            _outDir.isEmpty ||
            (_only.isNotEmpty && !_only.split(',').contains(key)),
      );
    }
  }
}
