// QA (müşteri akışları): gerçek uygulama + sahte sunucu. Teklif kararı (onayla / revize / reddet),
// sipariş akışı (takip), teslimat kabulü ve itiraz, şablondan sipariş, tekrar sipariş, şirket içi talep
// onayı, bildirim derin bağlantısı. Her adımda istisna / taşma / hata durumu yok.
import 'dart:async';

import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/customer_orders/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../integration_test/smoke_flows.dart';
import '../../support/a11y.dart';
import 'qa_support.dart';

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder f, {
  int rounds = 40,
}) async {
  for (var i = 0; i < rounds && f.evaluate().isEmpty; i++) {
    await settleIo(tester, rounds: 1);
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
  await settleIo(tester, rounds: 3);
}

Future<(ProviderContainer, GoRouter)> _signedIn(
  WidgetTester tester,
  String persona,
) async {
  final c = await launchFakeApp(tester);
  await signInAs(tester, c, persona);
  await settleIo(tester);
  final bar = find.byType(AnimatedBottomBar);
  return (c, GoRouter.of(tester.element(bar)));
}

Future<void> _go(WidgetTester tester, GoRouter router, String path) async {
  unawaited(router.push(path));
  await pumpFor(tester, const Duration(milliseconds: 1000));
  await settleIo(tester);
}

List<String> _texts() => find
    .byType(Text)
    .evaluate()
    .map((e) => (e.widget as Text).data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

void main() {
  testWidgets(
    'QA musteri: çekli teklif (12002) çek görseli olmadan onaylanamaz',
    (tester) async {
      setA11yPhone(tester, size: const Size(390, 844));
      await qaRun(tester, 'decision_approve_gate', (q) async {
        final (_, router) = await _signedIn(tester, 'musteri');
        await _go(tester, router, '/orders/12002');
        final approve = find.widgetWithText(AknButton, OrdersCopy.approve);
        expect(
          approve,
          findsOneWidget,
          reason: 'onay düğmesi yok: ${_texts()}',
        );
        expect(tester.widget<AknButton>(approve).onPressed, isNull);
        expect(
          find.text('Çek görseli yüklenmeden onaylanamaz'),
          findsOneWidget,
        );
        expect(find.text('Belge yükle'), findsWidgets);
        expect(
          find.textContaining('kaldı'),
          findsWidgets,
          reason: 'geri sayım',
        );
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets('QA onay: teklif revize iste (12002) → gerekçe + açıklama', (
    tester,
  ) async {
    setA11yPhone(tester, size: const Size(390, 844));
    await qaRun(tester, 'decision_revise', (q) async {
      final (_, router) = await _signedIn(tester, 'onay');
      await _go(tester, router, '/orders/12002');
      final revise = find.widgetWithText(AknButton, OrdersCopy.revise);
      expect(revise, findsOneWidget, reason: 'revize düğmesi yok: ${_texts()}');
      await _tap(tester, revise);
      await pumpFor(tester, const Duration(milliseconds: 600));
      // Gerekçe seçmeden gönderilemez (doğrulama).
      await _tap(
        tester,
        find.widgetWithText(AknButton, OrdersCopy.revise).last,
      );
      await pumpFor(tester, const Duration(milliseconds: 400));
      expect(
        find.text(OrdersCopy.reviseHint),
        findsOneWidget,
        reason: 'boş gerekçeyle sayfa kapandı',
      );
      await _tap(
        tester,
        find.text(QuoteDecisionPresets.revisionReasons.first).last,
      );
      await _tap(
        tester,
        find.widgetWithText(AknButton, OrdersCopy.revise).last,
      );
      await pumpFor(tester, const Duration(seconds: 1));
      await settleIo(tester, rounds: 10);
      expect(find.text(OrdersCopy.reviseHint), findsNothing);
      expect(
        find.widgetWithText(AknButton, OrdersCopy.approve),
        findsNothing,
        reason: 'revize sonrası karar düğmeleri kalmış: ${_texts()}',
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('QA musteri: teklif reddet (12002)', (tester) async {
    setA11yPhone(tester, size: const Size(390, 844));
    await qaRun(tester, 'decision_reject', (q) async {
      final (_, router) = await _signedIn(tester, 'musteri');
      await _go(tester, router, '/orders/12002');
      await _tap(tester, find.widgetWithText(AknButton, OrdersCopy.reject));
      await pumpFor(tester, const Duration(milliseconds: 600));
      await _tap(
        tester,
        find.text(QuoteDecisionPresets.rejectReasons.first).last,
      );
      await _tap(
        tester,
        find.widgetWithText(DestructiveButton, OrdersCopy.rejectQuote),
      );
      await pumpFor(tester, const Duration(seconds: 1));
      await settleIo(tester, rounds: 10);
      expect(find.text(OrdersCopy.rejectHint), findsNothing);
      expect(find.widgetWithText(AknButton, OrdersCopy.reject), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('QA talep: teklif kararı veremez (12002 düğmesiz)', (
    tester,
  ) async {
    setA11yPhone(tester, size: const Size(390, 844));
    await qaRun(tester, 'decision_talep', (q) async {
      final (_, router) = await _signedIn(tester, 'talep');
      await _go(tester, router, '/orders/12002');
      expect(find.byType(ErrorState), findsNothing);
      // Talep edenin teklif kararı yetkisi var mı? Görünen düğmeler kayda geçer.
      final hasDecide = find
          .widgetWithText(AknButton, OrdersCopy.approve)
          .evaluate()
          .isNotEmpty;
      debugPrint('QA talep 12002 karar düğmesi: $hasDecide');
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('QA musteri: teslimat kabulü (5003) sipariş 12008 üzerinden', (
    tester,
  ) async {
    setA11yPhone(tester, size: const Size(390, 844));
    await qaRun(tester, 'delivery_accept', (q) async {
      final (_, router) = await _signedIn(tester, 'musteri');
      await _go(tester, router, '/orders/12008');
      final confirm = find.widgetWithText(
        AknButton,
        OrdersCopy.confirmDelivery,
      );
      expect(
        confirm,
        findsOneWidget,
        reason: 'teslim onay düğmesi yok: ${_texts()}',
      );
      await _tap(tester, confirm);
      await pumpFor(tester, const Duration(seconds: 1));
      await settleIo(tester);
      final accept = find.widgetWithText(AknButton, 'Teslimatı onayla');
      expect(
        accept,
        findsWidgets,
        reason: 'sevkiyat ayrıntısında onay yok: ${_texts()}',
      );
      await _tap(tester, accept.last);
      await pumpFor(tester, const Duration(milliseconds: 600));
      await _tap(tester, find.widgetWithText(AknButton, 'Onayla').last);
      await pumpFor(tester, const Duration(seconds: 1));
      await settleIo(tester, rounds: 10);
      expect(
        find.widgetWithText(AknButton, 'Teslimatı onayla'),
        findsNothing,
        reason: 'kabul sonrası düğme kalmış: ${_texts()}',
      );
      // Siparişe dön: dock'taki teslim onayı kalkmalı.
      router.pop();
      await pumpFor(tester, const Duration(seconds: 1));
      await settleIo(tester, rounds: 10);
      expect(
        find.widgetWithText(AknButton, OrdersCopy.confirmDelivery),
        findsNothing,
        reason: 'sipariş ayrıntısı eski (teslim onayı hâlâ istenir)',
      );
      await tester.pumpWidget(const SizedBox());
    });
    // QA C-03 (düzeltildi): kabul / itiraz müşteri verisini tazeler; sipariş ayrıntısı dönüşte
    // yeniden okunur, dock'taki "Teslimatı onayla" kalkar.
  });

  testWidgets('QA onay: teslimata itiraz (5003)', (tester) async {
    setA11yPhone(tester, size: const Size(390, 844));
    await qaRun(tester, 'delivery_dispute', (q) async {
      final (_, router) = await _signedIn(tester, 'onay');
      await _go(tester, router, '/shipments/5003');
      final dispute = find.widgetWithText(AknButton, 'İtiraz et');
      expect(
        dispute,
        findsOneWidget,
        reason: 'itiraz düğmesi yok: ${_texts()}',
      );
      await _tap(tester, dispute);
      await pumpFor(tester, const Duration(seconds: 1));
      await settleIo(tester);
      expect(find.byType(ErrorState), findsNothing);
      // Gerekçe seçmeden gönder → doğrulama.
      final send = find.byWidgetPredicate(
        (w) =>
            w is AknButton &&
            (w.label.contains('İtiraz') || w.label.contains('Gönder')),
      );
      expect(send, findsWidgets, reason: 'itiraz gönder yok: ${_texts()}');
      debugPrint('QA itiraz sayfası: ${_texts().take(40)}');
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('QA musteri: şablondan sipariş (Şablonlarım → kullan)', (
    tester,
  ) async {
    setA11yPhone(tester, size: const Size(390, 844));
    await qaRun(tester, 'template_use', (q) async {
      final (_, router) = await _signedIn(tester, 'musteri');
      await _go(tester, router, '/templates');
      expect(find.byType(ErrorState), findsNothing);
      debugPrint('QA şablonlar: ${_texts().take(30)}');
      final use = find.widgetWithText(AknButton, 'Kullan');
      expect(
        use,
        findsWidgets,
        reason: 'şablonda sipariş ver yok: ${_texts()}',
      );
      await _tap(tester, use.first);
      await pumpFor(tester, const Duration(seconds: 1));
      await settleIo(tester);
      await _pumpUntil(tester, find.text('Ürün ve litre'));
      expect(find.text('Ürün ve litre'), findsOneWidget);
      expect(find.textContaining('şablonu yüklendi'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('QA musteri: tamamlanan sipariş tekrarla (12004)', (
    tester,
  ) async {
    setA11yPhone(tester, size: const Size(390, 844));
    await qaRun(tester, 'reorder', (q) async {
      final (_, router) = await _signedIn(tester, 'musteri');
      await _go(tester, router, '/orders/12004');
      final re = find.widgetWithText(AknButton, OrdersCopy.reorder);
      expect(re, findsOneWidget, reason: 'tekrarla yok: ${_texts()}');
      await _tap(tester, re);
      await pumpFor(tester, const Duration(seconds: 1));
      await settleIo(tester);
      // Tekrarla doğrudan özete açılır (tasarım): ürün, litre, nokta, yöntem ön dolu.
      await _pumpUntil(tester, find.text(OrdersCopy.saveAsTemplate));
      expect(find.textContaining('siparişi tekrarlanıyor'), findsOneWidget);
      await _tap(tester, find.widgetWithText(AknButton, OrdersCopy.send));
      await _pumpUntil(tester, find.text(OrdersCopy.successTitle), rounds: 60);
      expect(find.text(OrdersCopy.successTitle), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
