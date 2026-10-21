// Saha ekranlarının tasarım v2 ekran görüntüleri (Formlarım, ön kayıtlar, portföy, form ayrıntısı
// plakası, ön kayıt ayrıntısı, sihirbaz özeti). Normal test çalışmasında atlanır; görüntü almak için:
//
//   flutter test test/features/field/field_capture_test.dart --dart-define=AKN_SCREENS_DIR=/tam/yol
//
// Tam uygulama 390 × 844 dp'de, 2× piksel.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/features/field/application/form_wizard_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/a11y.dart';
import '../../support/test_app.dart';

const _outDir = String.fromEnvironment('AKN_SCREENS_DIR');

const _formArgs = FormWizardArgs(
  customerId: 103,
  customerTitle: 'Ege Tarım Kooperatifi',
);

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
  const screens = [
    ('saha', '/field', 'formlarim'),
    ('saha', '/field?tab=leads', 'onkayitlar'),
    ('saha', '/field?tab=portfolio', 'portfoy'),
    ('saha', '/field/forms/7005', 'form-ayrinti'),
    ('satis', '/field/forms/7001', 'form-ayrinti-maliyet'),
    ('saha', '/field/leads/8001', 'onkayit-ayrinti'),
    ('satis', '/field', 'saha-ekibi'),
    (
      'saha',
      '/field/forms/new?customerId=103&customerTitle=Ege%20Tar%C4%B1m%20Kooperatifi',
      'sihirbaz-ozet',
    ),
  ];
  const variants = [
    ('acik-1x', A11yVariant(1, Brightness.light)),
    ('koyu-1x', A11yVariant(1, Brightness.dark)),
  ];
  for (final (persona, location, name) in screens) {
    for (final (tag, variant) in variants) {
      testWidgets('$name $tag', (tester) async {
        setA11yPhone(tester, size: const Size(390, 844));
        setA11yPlatform(tester, variant);
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
          final outcome = await s.loginWithPassword(persona, 'demo');
          if (outcome is LoginNeedsCode) {
            await s.verifyCode(outcome.challenge.challengeId, '123456');
          }
        });
        await pumpSteps(tester, const Duration(seconds: 2));
        expect(c.read(sessionControllerProvider), isA<SessionAuthenticated>());
        final router = c.read(routerProvider);
        if (location == '/field' || location.startsWith('/field?')) {
          router.go(location);
        } else {
          unawaited(router.push(location));
        }
        await settleIo(tester);
        await pumpSteps(tester, const Duration(seconds: 2));
        if (name == 'sihirbaz-ozet') {
          final ctrl = c.read(formWizardProvider(_formArgs).notifier);
          final key = c
              .read(formWizardProvider(_formArgs))
              .draft
              .lines
              .single
              .key;
          ctrl
            ..setLineProduct(key, 1)
            ..updateLine(key, (l) => l.copyWith(liters: 8000))
            ..goTo(FieldWizardStep.summary);
          await settleIo(tester);
          await pumpSteps(tester, const Duration(seconds: 2));
        }
        await _capture(tester, boundary, 'field/${name}_${tag}_1');
        final scrollables = find.byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.vertical,
        );
        if (scrollables.evaluate().isNotEmpty) {
          ScrollableState? main;
          var best = 0.0;
          for (final e in scrollables.evaluate()) {
            final hgt = e.size?.height ?? 0;
            if (hgt > best) {
              best = hgt;
              main = (e as StatefulElement).state as ScrollableState;
            }
          }
          final pos = main!.position;
          if (pos.maxScrollExtent > 0) {
            pos.jumpTo((pos.pixels + 640).clamp(0, pos.maxScrollExtent));
            await pumpSteps(tester, const Duration(milliseconds: 600));
            await _capture(tester, boundary, 'field/${name}_${tag}_2');
          }
        }
        await tester.pumpWidget(const SizedBox());
      }, skip: _outDir.isEmpty);
    }
  }
}
