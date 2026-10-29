// QA (müşteri akışları): gerçek uygulama + sahte sunucu. Ana sayfadaki "Sipariş ver" → sihirbazın 4
// adımı → her ödeme yöntemiyle gönderim → başarı → "Siparişi aç" ile sipariş ayrıntısı. Talep eden
// için şirket içi onaya gönderim. Her adımda istisna / taşma yok.
import 'dart:async';

import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/customer_orders/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../integration_test/smoke_flows.dart';
import '../../support/a11y.dart';
import '../../support/fonts.dart';

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

/// Etiketi verilen metin alanı (etiket "Çek no *" gibi yıldızlı olabilir).
Finder _field(String label) => find.descendant(
  of: find.ancestor(
    of: find.textContaining(label),
    matching: find.byType(AknTextField),
  ),
  matching: find.byType(TextField),
);

Future<void> _next(WidgetTester tester) async {
  await _tap(tester, find.widgetWithText(AknButton, 'Devam'));
  await pumpFor(tester, const Duration(milliseconds: 500));
  await settleIo(tester);
}

final _products = find.text('Ürün ve litre');
final _delivery = find.text('Teslimat noktası');
final _payment = find.text('Ödeme yöntemi');
final _summary = find.text(OrdersCopy.saveAsTemplate);

Future<GoRouter> _openWizardFromHome(
  WidgetTester tester,
  String persona,
) async {
  final c = await launchFakeApp(tester);
  await signInAs(tester, c, persona);
  await settleIo(tester);
  expect(tester.takeException(), isNull, reason: 'ana sayfa');
  final bar = find.byType(AnimatedBottomBar);
  final router = GoRouter.of(tester.element(bar));
  // Ana sayfadaki birincil eylem.
  final cta = find.text(OrdersCopy.newOrder);
  expect(cta, findsWidgets, reason: 'ana sayfada "Sipariş ver" yok');
  await _tap(tester, cta.first);
  await pumpFor(tester, const Duration(milliseconds: 800));
  await _pumpUntil(tester, _products);
  expect(_products, findsOneWidget, reason: '"Sipariş ver" sihirbazı açmadı');
  return router;
}

void main() {
  // Gerçek yüz (Archivo): "Sıra sizde" baş satırı cihazdaki gibi ölçülür (test yazı tipinde
  // çekirdeğin satırı uzun geri sayımla taşar; çekirdeğe bildirildi).
  setUpAll(loadRealFonts);

  const methods = <(String, Map<String, String>)>[
    ('Havale', {}),
    (
      'Çek',
      {'Çek no': 'A-123456', 'Banka': 'Ziraat', 'Keşideci': 'Aydın Lojistik'},
    ),
    ('Senet', {'Borçlu': 'Aydın Lojistik'}),
    ('Açık hesap', {}),
    ('Kart', {}),
    ('Avans', {}),
    ('Nakit', {}),
  ];

  for (final (method, fields) in methods) {
    testWidgets(
      'QA musteri: ana sayfa → sihirbaz → "$method" → gönder → sipariş',
      (tester) async {
        setA11yPhone(tester);
        await _openWizardFromHome(tester, 'musteri');
        await _tap(tester, find.widgetWithText(ChoiceCard, 'Motorin').first);
        await tester.enterText(find.byType(TextField).first, '3000');
        await tester.pump();
        await _next(tester);
        expect(_delivery, findsOneWidget, reason: 'teslimat adımı');
        await _next(tester);
        expect(_payment, findsOneWidget, reason: 'ödeme adımı');
        final m = find.text(method);
        expect(m, findsWidgets, reason: 'yöntem listede yok: $method');
        await _tap(tester, m.first);
        await pumpFor(tester, const Duration(milliseconds: 400));
        for (final e in fields.entries) {
          final f = _field(e.key);
          expect(f, findsWidgets, reason: 'alan yok: ${e.key}');
          await tester.ensureVisible(f.first);
          await tester.enterText(f.first, e.value);
          await tester.pump();
        }
        expect(tester.takeException(), isNull, reason: 'ödeme adımı ($method)');
        await _next(tester);
        expect(
          _summary,
          findsOneWidget,
          reason: 'özet adımına geçilmedi ($method)',
        );
        expect(tester.takeException(), isNull, reason: 'özet ($method)');
        await _tap(tester, find.widgetWithText(AknButton, OrdersCopy.send));
        await _pumpUntil(
          tester,
          find.text(OrdersCopy.successTitle),
          rounds: 60,
        );
        expect(
          find.text(OrdersCopy.successTitle),
          findsOneWidget,
          reason: 'gönderim başarı ekranı yok ($method)',
        );
        expect(tester.takeException(), isNull, reason: 'başarı ($method)');
        await pumpFor(tester, const Duration(seconds: 1));
        await _tap(tester, find.text(OrdersCopy.viewOrder).first);
        await pumpFor(tester, const Duration(seconds: 1));
        await settleIo(tester);
        expect(tester.takeException(), isNull, reason: 'sipariş ayrıntısı');
        expect(find.byType(ErrorState), findsNothing);
        expect(find.text(OrdersCopy.successTitle), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'QA talep: sihirbaz → şirket içi onaya gönder → talebi görüntüle',
    (tester) async {
      setA11yPhone(tester);
      await _openWizardFromHome(tester, 'talep');
      await _tap(tester, find.widgetWithText(ChoiceCard, 'Motorin').first);
      await tester.enterText(find.byType(TextField).first, '25000');
      await tester.pump();
      await _next(tester);
      await _next(tester);
      await _next(tester);
      expect(_summary, findsOneWidget);
      expect(find.text('Şirket içi onaya düşecek'), findsOneWidget);
      await _tap(
        tester,
        find.widgetWithText(AknButton, OrdersCopy.sendForApproval),
      );
      await _pumpUntil(tester, find.text(OrdersCopy.companyRequestTitle));
      expect(find.text(OrdersCopy.companyRequestTitle), findsOneWidget);
      await _tap(tester, find.text('Talebi görüntüle'));
      await pumpFor(tester, const Duration(seconds: 1));
      await settleIo(tester);
      expect(tester.takeException(), isNull, reason: 'talep ayrıntısı');
      expect(find.byType(ErrorState), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('QA musteri: çok satırlı sipariş (Satır ekle) → gönder', (
    tester,
  ) async {
    setA11yPhone(tester);
    await _openWizardFromHome(tester, 'musteri');
    await _tap(tester, find.widgetWithText(ChoiceCard, 'Motorin').first);
    await tester.enterText(find.byType(TextField).first, '5000');
    await tester.pump();
    await _tap(tester, find.text(OrdersCopy.addLine));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull, reason: 'satır ekle');
    expect(find.text('Satır 2'), findsOneWidget);
    await _tap(
      tester,
      find.widgetWithText(ChoiceCard, 'Kurşunsuz Benzin 95').last,
    );
    await tester.enterText(find.byType(TextField).last, '3000');
    await tester.pump();
    await _next(tester);
    expect(
      _delivery,
      findsOneWidget,
      reason: 'çok satırda teslimata geçilmedi',
    );
    await _next(tester);
    await _next(tester);
    expect(_summary, findsOneWidget);
    await _tap(tester, find.widgetWithText(AknButton, OrdersCopy.send));
    await _pumpUntil(tester, find.text(OrdersCopy.successTitle), rounds: 60);
    expect(find.text(OrdersCopy.successTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('QA musteri: yarım sihirbaz taslak saklanır ve geri dönülür', (
    tester,
  ) async {
    setA11yPhone(tester);
    final router = await _openWizardFromHome(tester, 'musteri');
    await _tap(tester, find.widgetWithText(ChoiceCard, 'Motorin').first);
    await tester.enterText(find.byType(TextField).first, '7777');
    await tester.pump();
    await _next(tester);
    // Geri tuşu → çıkış sorusu → taslak sakla.
    await tester.binding.handlePopRoute();
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text(OrdersCopy.exitTitle), findsOneWidget);
    await _tap(tester, find.text(OrdersCopy.keepDraft));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(_delivery, findsNothing, reason: 'sihirbaz kapanmadı');
    expect(tester.takeException(), isNull);
    unawaited(router.push('/orders/new'));
    await pumpFor(tester, const Duration(seconds: 1));
    await settleIo(tester);
    // Taslak kaldığı adımdan (Teslimat) sürer; Geri ile ürün adımında litre durur.
    expect(find.textContaining('Adım 2 / 4'), findsOneWidget);
    await _tap(tester, find.widgetWithText(AknButton, 'Geri'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    final fields = find
        .byType(EditableText)
        .evaluate()
        .map((e) => (e.widget as EditableText).controller.text)
        .toList();
    expect(
      fields.any((t) => t.replaceAll('.', '') == '7777'),
      isTrue,
      reason: 'taslak litresi yok; alanlar: $fields',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
