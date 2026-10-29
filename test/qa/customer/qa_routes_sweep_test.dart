// QA (müşteri akışları): her müşteri personası gerçek uygulamada (sahte sunucu) giriş yapar ve
// müşteri rotalarının tamamını — liste, ayrıntı (her sipariş / sevkiyat / talep), ekleme ve
// düzenleme sayfaları — 360×640 telefonda 1,0× ve 2,0× yazı ölçeğinde açar. Her sayfada yerleşim
// hatası (RenderFlex taşması vb.), istisna, hata durumu ve takılı yükleme olmamalı.
import 'dart:async';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../integration_test/smoke_flows.dart';
import '../../support/a11y.dart';
import '../../support/fonts.dart';
import 'qa_support.dart';

const _customerPersonas = ['musteri', 'talep', 'onay'];

/// Müşteri rotaları (sahte dünyada müşteri 101'in kayıtları).
const _routes = [
  '/home',
  '/orders',
  '/orders/new',
  '/orders/12001',
  '/orders/12002',
  '/orders/12003',
  '/orders/12004',
  '/orders/12008',
  '/shipments',
  '/shipments/5001',
  '/shipments/5003',
  '/shipments/5004',
  '/shipments/5005',
  '/company/requests',
  '/finance-info',
  '/documents',
  '/spending',
  '/delivery-points',
  '/delivery-points/new',
  '/delivery-points/1001',
  '/templates',
  '/limits',
  '/company/users',
  '/notifications',
  '/profile',
  '/stats',
  '/assistant',
];

void main() {
  // Gerçek yüz (Archivo): "Sıra sizde" baş satırı cihazdaki gibi ölçülür (test yazı tipinde
  // çekirdeğin satırı uzun geri sayımla taşar; çekirdeğe bildirildi).
  setUpAll(loadRealFonts);

  for (final scale in [1.0, 2.0]) {
    for (final persona in _customerPersonas) {
      testWidgets('QA $persona ${scale}x: müşteri rotaları hatasız açılır', (
        tester,
      ) async {
        await qaRun(tester, 'routes_${persona}_$scale', (q) async {
          setA11yPhone(tester);
          setA11yPlatform(tester, A11yVariant(scale, Brightness.light));
          final c = await launchFakeApp(tester);
          await signInAs(tester, c, persona);
          expect(
            c.read(sessionControllerProvider),
            isA<SessionAuthenticated>(),
          );
          await settleIo(tester);
          expect(tester.takeException(), isNull, reason: 'home');
          final bar = find.byType(AnimatedBottomBar);
          expect(bar, findsOneWidget);
          final router = GoRouter.of(tester.element(bar));
          final problems = <String>[];
          for (final r in _routes) {
            q.where = r;
            unawaited(router.push(r));
            await pumpFor(tester, const Duration(milliseconds: 1200));
            await settleIo(tester);
            await pumpFor(tester, const Duration(milliseconds: 600));
            final e = tester.takeException();
            if (e != null) problems.add('$r: istisna $e');
            if (find.byType(ErrorState).evaluate().isNotEmpty) {
              final texts = find
                  .descendant(
                    of: find.byType(ErrorState).first,
                    matching: find.byType(Text),
                  )
                  .evaluate()
                  .map((el) => (el.widget as Text).data)
                  .join(' | ');
              problems.add('$r: hata durumu ($texts)');
            }
            if (find.textContaining('yüklenemedi').evaluate().isNotEmpty) {
              problems.add('$r: "yüklenemedi" metni');
            }
            if (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
              // Uzun süre dönen yükleme göstergesi.
              await settleIo(tester, rounds: 10);
              await pumpFor(tester, const Duration(seconds: 2));
              if (find
                  .byType(CircularProgressIndicator)
                  .hitTestable()
                  .evaluate()
                  .isNotEmpty) {
                problems.add('$r: takılı yükleme göstergesi');
              }
            }
            if (router.canPop()) router.pop();
            await pumpFor(tester, const Duration(milliseconds: 600));
            final e2 = tester.takeException();
            if (e2 != null) problems.add('$r (geri): istisna $e2');
          }
          await tester.pumpWidget(const SizedBox());
          expect(problems, isEmpty, reason: problems.join('\n'));
        });
        // QA C-01 / C-02 (düzeltildi): 2,0× yazıda /stats plaka satırı ve teklif kıyas başlığı
        // (quote_decision_card.dart) artık taşmıyor; 2,0× turu da koşar.
      });
    }
  }
}
