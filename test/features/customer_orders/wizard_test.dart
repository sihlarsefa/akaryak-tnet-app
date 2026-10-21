// "Sipariş ver" sihirbazı (spec A.3 adım 1, A.4 A2, C.4a, C.5): bayi seçici, ürün + litre, tank
// uyarısı, önerilen teslim tarihi, sipariş verilebilirlik denetimi, çek tutarı / vadesi ön dolumu ve
// farklılık uyarısı, Talep eden için şirket içi onay uyarısı + "Onaylayana not", teklif süresi notu,
// "Şablon olarak kaydet", gönderim (başarı / kısmi → kalanları yeni anahtar + aynı ödeme grubuyla),
// şablondan / talepten / tekrarla açılış, çıkışta taslak sakla / çık, C.7 erişilebilirlik.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:akaryakitnet/core/media/image_capture.dart';
import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/routing/app_routes.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/core/utils/format.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/customer_orders/api.dart';
import 'package:akaryakitnet/features/customer_orders/application/wizard_models.dart';
import 'package:akaryakitnet/features/customer_orders/presentation/wizard/order_wizard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fonts.dart';
import 'support/a2_support.dart';

void main() {
  late A2Env env;

  // Gerçek yüz (Mona Sans): plaka göstergeleri ve büyük yazı yerleşimi cihazdaki gibi ölçülür
  // (tasarım v2 §14.1). Dosyalar yoksa test yazı tipiyle sürer.
  setUpAll(loadRealFonts);

  setUp(() async {
    env = await A2Env.create();
  });

  final productsTitle = find.text('Ürün ve litre');
  final deliveryTitle = find.text('Teslimat noktası');
  final paymentTitle = find.text('Ödeme yöntemi');
  final summaryMarker = find.text(OrdersCopy.saveAsTemplate);

  Future<(ProviderContainer, GoRouter)> openWizard(
    WidgetTester tester, {
    String persona = 'musteri',
    String location = '/orders/new',
    double textScale = 1,
    Brightness brightness = Brightness.light,
    Finder? waitFor,
    List<Override> extra = const [],
  }) async {
    final c = (await tester.runAsync(
      () => env.signedIn(persona, extra: extra),
    ))!;
    addTearDown(c.dispose);
    final router = await pumpA2(
      tester,
      c,
      initialLocation: location,
      textScale: textScale,
      brightness: brightness,
    );
    await pumpUntil(tester, waitFor ?? productsTitle);
    await pumpReal(tester);
    return (c, router);
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> fillLine(
    WidgetTester tester,
    String liters, {
    String product = 'Motorin',
  }) async {
    await tapVisible(tester, find.widgetWithText(ChoiceCard, product).first);
    await tester.enterText(find.byType(TextField).first, liters);
    await tester.pump();
  }

  /// Etiketi alanın üstünde duran (tasarım v2) metin alanı.
  Finder fieldLabelled(String label) => find.descendant(
    of: find.ancestor(
      of: find.text(label),
      matching: find.byType(AknTextField),
    ),
    matching: find.byType(TextField),
  );

  Future<void> pumpUntilGone(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 60 && finder.evaluate().isNotEmpty; i++) {
      await pumpReal(tester, rounds: 1);
    }
  }

  Future<void> next(WidgetTester tester, Finder until) async {
    await tester.tap(find.widgetWithText(AknButton, 'Devam'));
    await pumpUntil(tester, until);
    await pumpReal(tester, rounds: 2);
  }

  /// Ürünler (Motorin + litre) → teslimat → ödeme → özet.
  Future<void> toSummary(WidgetTester tester, String liters) async {
    await fillLine(tester, liters);
    await next(tester, deliveryTitle);
    await next(tester, paymentTitle);
    await next(tester, summaryMarker);
  }

  testWidgets(
    'bayi seçici, eksik satırda ilerlemez, tank uyarısı, önerilen teslim tarihi',
    (tester) async {
      await openWizard(tester);
      expect(find.text('Bayi'), findsOneWidget);
      expect(find.text('Demir Petrol Akaryakıt Ltd. Şti.'), findsOneWidget);
      expect(find.text('Kuzey Enerji A.Ş.'), findsOneWidget);
      expect(find.text('Varsayılan'), findsOneWidget);

      // Ürün ve litre girilmeden ilerlenmez.
      await tester.tap(find.widgetWithText(AknButton, 'Devam'));
      await pumpReal(tester, rounds: 2);
      expect(productsTitle, findsOneWidget);
      expect(find.text('Ürün seçin.'), findsOneWidget);

      await fillLine(tester, '35000');
      expect(find.textContaining('42,10 ₺/L'), findsWidgets);
      await next(tester, deliveryTitle);
      expect(find.text('Tank kapasitesi aşılıyor'), findsOneWidget);
      final tomorrow = TrTime.addDays(TrTime.todayStart(), 1);
      expect(find.textContaining(Fmt.date(tomorrow)), findsWidgets);

      // Tuzla'nın tankı da küçük (15.000 L); uyarı kalır. Litre azaltılınca gider.
      await tapVisible(tester, find.text('Tuzla Şantiye'));
      expect(find.text('Tank kapasitesi aşılıyor'), findsOneWidget);
      await tester.tap(find.widgetWithText(AknButton, 'Geri'));
      await pumpUntil(tester, productsTitle);
      await tester.enterText(find.byType(TextField).first, '12000');
      await tester.pump();
      await next(tester, deliveryTitle);
      expect(find.text('Tank kapasitesi aşılıyor'), findsNothing);
      await tearDownUi(tester);
    },
  );

  testWidgets('sipariş verilemeyen bayide uyarı ve bayiyi ara; ilerlenmez', (
    tester,
  ) async {
    for (final l in env.world.links.where((l) => l['customerId'] == 101)) {
      l['orderingBlocked'] = 'Finans incelemesi sürüyor.';
    }
    await openWizard(
      tester,
      waitFor: find.text('Bu bayide şu an sipariş veremezsiniz'),
    );
    expect(find.text('Bu bayide şu an sipariş veremezsiniz'), findsOneWidget);
    expect(find.text('Finans incelemesi sürüyor.'), findsWidgets);
    expect(find.text('Bayiyi ara'), findsOneWidget);
    await fillLine(tester, '5000');
    await tester.tap(find.widgetWithText(AknButton, 'Devam'));
    await pumpReal(tester, rounds: 2);
    expect(productsTitle, findsOneWidget);
    expect(deliveryTitle, findsNothing);
    await tearDownUi(tester);
  });

  testWidgets(
    'çek: tutar tahminden, vade teslim + 30 günden dolar; farklı tutar uyarısı',
    (tester) async {
      await openWizard(tester);
      await fillLine(tester, '10000');
      await next(tester, deliveryTitle);
      await next(tester, paymentTitle);
      // Varsayılan yöntem (havale) seçili gelir.
      expect(find.text('Havale ayrıntıları'), findsOneWidget);

      await tapVisible(tester, find.text('Çek'));
      await pumpUntil(tester, find.text('Çek ayrıntıları'));
      expect(find.text('421.000,00'), findsOneWidget);
      final tomorrow = TrTime.addDays(TrTime.todayStart(), 1);
      // Ödeme özetinde ("Çek, 30 gün, vade …"; vade alanı tarihi gün adıyla yazar).
      expect(
        find.textContaining(Fmt.date(TrTime.addDays(tomorrow, 30))),
        findsWidgets,
      );
      expect(find.text(OrdersCopy.financeHint), findsOneWidget);
      expect(find.text(OrdersCopy.instrumentPhotoLater), findsOneWidget);
      expect(find.textContaining('tahmini tutardan'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, '421.000,00'),
        '400000',
      );
      await tester.pump();
      expect(find.textContaining('tahmini tutardan'), findsOneWidget);
      await tearDownUi(tester);
    },
  );

  testWidgets('"Şablondan başla": seçilen şablon satırları doldurur', (
    tester,
  ) async {
    await openWizard(tester);
    await tapVisible(tester, find.text(OrdersCopy.fromTemplate));
    await pumpUntil(tester, find.text('Benzin – Pendik'));
    await tester.tap(find.text('Benzin – Pendik'));
    await pumpUntil(tester, find.textContaining('şablonu yüklendi'));
    await pumpReal(tester);
    expect(find.text('5.000'), findsOneWidget);
    final card = tester.widget<ChoiceCard>(
      find.widgetWithText(ChoiceCard, 'Kurşunsuz Benzin 95'),
    );
    expect(card.selected, isTrue);
    await tearDownUi(tester);
  });

  testWidgets('avans: bakiye gösterilir; tahmin bakiyeyi aşarsa ilerlenmez', (
    tester,
  ) async {
    await openWizard(tester);
    await fillLine(tester, '10000'); // ≈ 421.000 ₺ > 250.000 ₺ bakiye
    await next(tester, deliveryTitle);
    await next(tester, paymentTitle);
    await tapVisible(tester, find.text('Avans'));
    await pumpUntil(tester, find.text('Ön ödemeli bakiye'));
    expect(find.textContaining('Ön ödemeli bakiye yetersiz'), findsOneWidget);
    await tester.tap(find.widgetWithText(AknButton, 'Devam'));
    await pumpReal(tester, rounds: 2);
    expect(paymentTitle, findsOneWidget);
    expect(summaryMarker, findsNothing);

    // Litre azalınca bakiye yeter.
    await tester.tap(find.widgetWithText(AknButton, 'Geri'));
    await pumpUntil(tester, deliveryTitle);
    await tester.tap(find.widgetWithText(AknButton, 'Geri'));
    await pumpUntil(tester, productsTitle);
    await tester.enterText(find.byType(TextField).first, '5000');
    await tester.pump();
    await next(tester, deliveryTitle);
    await next(tester, paymentTitle);
    expect(
      find.textContaining('Kullanılabilir bakiye: 250.000,00 ₺'),
      findsOneWidget,
    );
    await next(tester, summaryMarker);
    expect(summaryMarker, findsOneWidget);
    await tearDownUi(tester);
  });

  testWidgets(
    'havale: dekont isteğe bağlı eklenir; sipariş oluşunca yükleme paneli',
    (tester) async {
      final jpeg = Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9]);
      await openWizard(
        tester,
        extra: [
          a2DocumentPickerProvider.overrideWithValue(
            (context, source, kind) async => CapturedImage(
              path: '/nonexistent/dekont.jpg',
              bytes: jpeg,
              fileName: 'dekont.jpg',
            ),
          ),
        ],
      );
      await fillLine(tester, '3000');
      await next(tester, deliveryTitle);
      await next(tester, paymentTitle);
      expect(find.text(OrdersCopy.transferReceiptOptional), findsOneWidget);
      await tapVisible(tester, find.text('Galeriden seç'));
      await pumpUntil(
        tester,
        find.text('Dekont eklendi; sipariş oluşunca yüklenecek.'),
      );
      await next(tester, summaryMarker);
      await tapVisible(tester, find.widgetWithText(AknButton, OrdersCopy.send));
      await pumpUntil(tester, find.text(OrdersCopy.successTitle));
      await pumpReal(tester);
      expect(find.text('Havale / EFT dekontu yükleyin'), findsOneWidget);
      await tearDownUi(tester);
    },
  );

  testWidgets(
    'Talep eden: eşik üstü şirket içi onaya düşer; "Onaylayana not" ile gönderilir',
    (tester) async {
      await openWizard(tester, persona: 'talep');
      await toSummary(tester, '25000');
      expect(find.text('Şirket içi onaya düşecek'), findsOneWidget);
      expect(find.textContaining('Teklif yaklaşık'), findsNothing);
      final note = fieldLabelled(OrdersCopy.noteForApprover);
      expect(note, findsOneWidget);
      await tester.enterText(note, 'Şantiye bekliyor');
      await tester.pump();

      await tapVisible(
        tester,
        find.widgetWithText(AknButton, OrdersCopy.sendForApproval),
      );
      await pumpUntil(tester, find.text(OrdersCopy.companyRequestTitle));
      expect(find.text(OrdersCopy.companyRequestTitle), findsOneWidget);
      expect(find.text('Talebi görüntüle'), findsOneWidget);
      final sent = env.controls.placeRequests.single;
      expect(sent.key, isNotNull);
      expect(sent.body['note'], 'Şantiye bekliyor');
      expect(
        A2Fake.companyRequests(env.world).last['note'],
        'Şantiye bekliyor',
      );
      await tearDownUi(tester);
    },
  );

  testWidgets(
    'yönetici: doğrudan sipariş; teklif süresi notu; şablon olarak kaydet',
    (tester) async {
      final templatesBefore = A2Fake.templatesOf(env.world, 101).length;
      final ordersBefore = env.world.orders.length;
      await openWizard(tester);
      await toSummary(tester, '25000');
      expect(find.text('Şirket içi onaya düşecek'), findsNothing);
      expect(fieldLabelled(OrdersCopy.noteForApprover), findsNothing);
      expect(find.textContaining('Teklif yaklaşık'), findsOneWidget);

      await tapVisible(tester, find.text(OrdersCopy.saveAsTemplate));
      await pumpReal(tester, rounds: 2);
      expect(find.text('Motorin – Pendik Lojistik Merkezi'), findsOneWidget);

      await tapVisible(tester, find.widgetWithText(AknButton, OrdersCopy.send));
      await pumpUntil(tester, find.text(OrdersCopy.successTitle));
      expect(find.text(OrdersCopy.successTitle), findsOneWidget);
      await pumpUntil(tester, find.text('Şablon kaydedildi'));
      expect(find.text('Şablon kaydedildi'), findsOneWidget);
      expect(env.world.orders.length, ordersBefore + 1);
      expect(A2Fake.templatesOf(env.world, 101).length, templatesBefore + 1);
      final sent = env.controls.placeRequests.single;
      expect(sent.key, isNotNull);
      expect(sent.body.containsKey('note'), isFalse);
      expect(find.text(OrdersCopy.viewOrder), findsOneWidget);
      await tearDownUi(tester);
    },
  );

  testWidgets(
    'kısmi sonuç: kalan satır yeni anahtar ve aynı ödeme grubuyla gönderilir',
    (tester) async {
      env.controls.failLineAt = 1;
      await openWizard(
        tester,
        location: '/orders/new?fromTemplate=702',
        waitFor: find.textContaining('şablonu yüklendi'),
      );
      expect(find.text('Satır 1'), findsOneWidget);
      expect(find.text('Satır 2'), findsOneWidget);
      await next(tester, deliveryTitle);
      await next(tester, paymentTitle);
      await next(tester, summaryMarker);
      await tapVisible(tester, find.widgetWithText(AknButton, OrdersCopy.send));
      await pumpUntil(tester, find.text(OrdersCopy.partialTitle));
      expect(find.text(OrdersCopy.partialTitle), findsOneWidget);
      expect(env.controls.placeRequests, hasLength(1));
      final first = env.controls.placeRequests.first;
      expect((first.body['lines'] as List), hasLength(2));
      expect(first.body['templateId'], 702);

      await tapVisible(
        tester,
        find.widgetWithText(AknButton, OrdersCopy.sendRemaining),
      );
      await pumpUntil(tester, find.text(OrdersCopy.successTitle));
      expect(find.text(OrdersCopy.successTitle), findsOneWidget);
      expect(env.controls.placeRequests, hasLength(2));
      final second = env.controls.placeRequests.last;
      expect(second.key, isNot(first.key));
      final lines = (second.body['lines'] as List).cast<JsonMap>();
      expect(lines, hasLength(1));
      expect(lines.single['quantityLiters'], 8000);
      final group = env.world.orders.last['paymentGroupKey'];
      expect(group, isNotNull);
      expect(second.body['paymentGroupKey'], group);
      await tearDownUi(tester);
    },
  );

  testWidgets(
    'tekrarla: önceki siparişin ürünü, litresi ve ödemesiyle özete açılır',
    (tester) async {
      final o3 = env.world.orders.firstWhere(
        (o) => o['status'] == 3 && o['customerId'] == 101,
      );
      await openWizard(
        tester,
        location: '/orders/new?reorder=${o3['id']}',
        waitFor: find.textContaining('siparişi tekrarlanıyor'),
      );
      expect(summaryMarker, findsOneWidget);
      expect(find.text('Motorin, 20.000 L'), findsOneWidget);
      expect(find.textContaining('Açık hesap'), findsWidgets);
      await tearDownUi(tester);
    },
  );

  testWidgets('talepten: siparişe dönüşmeyen satırlar aktarılır', (
    tester,
  ) async {
    final requestId = 3901;
    A2Fake.companyRequests(env.world).add({
      'id': requestId,
      'customerId': 101,
      'requestedByUserId': 'u-talep',
      'status': 4,
      'statusLabel': 'Kısmen oluşturuldu',
      'totalLiters': 9000.0,
      'paymentMethodCode': 'HAVALE',
      'paymentTermDays': null,
      'paymentInstallments': null,
      'paymentDetailJson': null,
      'lines': [
        {
          'stationId': 1,
          'productId': 1,
          'deliveryPointId': 1001,
          'quantityLiters': 6000.0,
          'requestedDeliveryDate': null,
          'orderId': 12999,
          'orderNumber': 'SIP-TEST',
          'error': null,
        },
        {
          'stationId': 1,
          'productId': 3,
          'deliveryPointId': 1002,
          'quantityLiters': 3000.0,
          'requestedDeliveryDate': null,
          'orderId': null,
          'orderNumber': null,
          'error': 'Ürün stokta yok.',
        },
      ],
    });
    // Talep ayrıntısı başka özelliğin sahte ucudur; bu test kendi basit karşılığını kaydeder.
    env.server.get('customers/me/order-requests/{id:int}', (req) {
      final id = req.intParam('id');
      return A2Fake.companyRequests(req.world).firstWhere((r) => r['id'] == id);
    });
    await openWizard(
      tester,
      location: '/orders/new?fromRequest=$requestId',
      waitFor: find.textContaining('Talep #$requestId'),
    );
    expect(find.textContaining('1 satır aktarıldı'), findsOneWidget);
    expect(find.text('3.000'), findsOneWidget);
    await tearDownUi(tester);
  });

  testWidgets(
    'çıkış: "Taslak olarak sakla" taslağı korur; yeniden açınca geri gelir',
    (tester) async {
      final (c, router) = await openWizard(tester);
      await fillLine(tester, '12345');
      await tester.tap(find.byTooltip('Kapat').first);
      await pumpUntil(tester, find.text(OrdersCopy.exitTitle));
      expect(find.text(OrdersCopy.keepDraft), findsOneWidget);
      await tester.tap(find.text(OrdersCopy.keepDraft));
      await pumpUntilGone(tester, productsTitle);
      expect(productsTitle, findsNothing);
      expect(find.text(OrdersCopy.myOrders), findsOneWidget);
      final snap = await tester.runAsync(
        () => c.read(wizardDraftStoreProvider)!.load(),
      );
      expect(snap?.draft.lines.single.liters, 12345);

      unawaited(router.push('/orders/new'));
      await pumpUntil(tester, productsTitle);
      await pumpReal(tester);
      expect(find.text('12.345'), findsOneWidget);
      await tearDownUi(tester);
    },
  );

  testWidgets('çıkış: "Çık" taslağı siler', (tester) async {
    final (c, _) = await openWizard(tester);
    await fillLine(tester, '7000');
    await tester.pump(const Duration(milliseconds: 500)); // otomatik kayıt
    await pumpReal(tester);
    await tester.tap(find.byTooltip('Kapat').first);
    await pumpUntil(tester, find.text(OrdersCopy.exitTitle));
    await tester.tap(find.widgetWithText(AknButton, OrdersCopy.discard));
    await pumpUntilGone(tester, productsTitle);
    expect(find.text(OrdersCopy.myOrders), findsOneWidget);
    final snap = await tester.runAsync(
      () => c.read(wizardDraftStoreProvider)!.load(),
    );
    expect(snap, isNull);
    await tearDownUi(tester);
  });

  String location(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.path;

  /// Şablon 702 (iki satır) ikinci satırda düşer: kısmi sonuç ekranı.
  Future<(ProviderContainer, GoRouter)> toPartial(WidgetTester tester) async {
    env.controls.failLineAt = 1;
    final opened = await openWizard(
      tester,
      location: '/orders/new?fromTemplate=702',
      waitFor: find.textContaining('şablonu yüklendi'),
    );
    await next(tester, deliveryTitle);
    await next(tester, paymentTitle);
    await next(tester, summaryMarker);
    await tapVisible(tester, find.widgetWithText(AknButton, OrdersCopy.send));
    await pumpUntil(tester, find.text(OrdersCopy.partialTitle));
    await pumpReal(tester);
    return opened;
  }

  for (final exit in [OrdersCopy.backHome, OrdersCopy.viewOrder]) {
    testWidgets(
      'başarıdan sonra "$exit": gönderilen taslak geri yazılmaz; sonraki "Sipariş ver" boş açılır',
      (tester) async {
        final c = (await tester.runAsync(() => env.signedIn('musteri')))!;
        addTearDown(c.dispose);
        // Uygulamadaki gibi: ana sayfadan sihirbaz açılır.
        final router = await pumpA2(tester, c, initialLocation: '/home');
        await pumpReal(tester, rounds: 10);
        unawaited(router.push('/orders/new'));
        await pumpUntil(tester, productsTitle);
        await pumpReal(tester);
        await toSummary(tester, '4200');
        await tapVisible(
          tester,
          find.widgetWithText(AknButton, OrdersCopy.send),
        );
        await pumpUntil(tester, find.text(OrdersCopy.successTitle));
        // Bekleyen otomatik kayıt zamanlayıcısı da taslağı geri getirmemeli.
        await tester.pump(const Duration(seconds: 1));
        await pumpReal(tester);
        await tapVisible(tester, find.widgetWithText(AknButton, exit));
        await pumpUntilGone(tester, find.text(OrdersCopy.successTitle));
        // Sayfa kapanır, sihirbaz sağlayıcısı atılır (kapanış kaydı burada çalışırdı).
        await tester.pump(const Duration(seconds: 1));
        await pumpReal(tester, rounds: 10);
        expect(find.byType(OrderWizardPage), findsNothing);
        final snap = await tester.runAsync(
          () => c.read(wizardDraftStoreProvider)!.load(),
        );
        expect(snap, isNull, reason: 'gönderilen taslak saklanmamalı');
        c.invalidate(draftSummaryProvider);
        final summary = await tester.runAsync(
          () => c.read(draftSummaryProvider.future),
        );
        expect(summary, isNull, reason: '"Yarım kalan siparişiniz" kartı yok');

        unawaited(router.push('/orders/new'));
        await pumpUntil(tester, productsTitle);
        await pumpReal(tester);
        expect(productsTitle, findsOneWidget);
        expect(summaryMarker, findsNothing);
        expect(find.widgetWithText(AknButton, OrdersCopy.send), findsNothing);
        expect(env.controls.placeRequests, hasLength(1));
        await tearDownUi(tester);
      },
    );
  }

  testWidgets(
    'kısmi sonuç → Kapat: kalan satır, oluşan sipariş ve ödeme grubu korunur; '
    'yeniden açınca yalnızca kalan satır aynı grupla gönderilir',
    (tester) async {
      final (c, router) = await toPartial(tester);
      final atPartial = (await tester.runAsync(
        () => c.read(wizardDraftStoreProvider)!.load(),
      ))!;
      expect(atPartial.draft.lines, hasLength(1));
      expect(atPartial.created, hasLength(1));
      final group = atPartial.draft.paymentGroupKey;
      expect(group, isNotNull);

      await tester.tap(find.byTooltip('Kapat').first);
      await pumpUntilGone(tester, find.text(OrdersCopy.partialTitle));
      // Sayfa kapanır, sihirbaz sağlayıcısı atılır (kapanış kaydı burada çalışırdı).
      await tester.pump(const Duration(seconds: 1));
      await pumpReal(tester, rounds: 10);
      expect(find.text(OrdersCopy.exitTitle), findsNothing);
      expect(find.byType(OrderWizardPage), findsNothing);
      final closed = (await tester.runAsync(
        () => c.read(wizardDraftStoreProvider)!.load(),
      ))!;
      expect(
        closed.draft.lines,
        hasLength(1),
        reason: 'eski taslakla ezilmedi',
      );
      expect(closed.draft.lines.single.liters, 8000);
      expect(closed.created, hasLength(1));
      expect(closed.draft.paymentGroupKey, group);
      expect(closed.draft.origin, DraftOrigin.partial);

      // "Yarım kalan siparişiniz" → sihirbaz kalan satırın özetiyle açılır.
      unawaited(router.push('/orders/new'));
      await pumpUntil(
        tester,
        find.textContaining('Önceki gönderimde 1 sipariş'),
      );
      await pumpReal(tester);
      await tapVisible(tester, find.widgetWithText(AknButton, OrdersCopy.send));
      await pumpUntil(tester, find.text(OrdersCopy.successTitle));
      expect(env.controls.placeRequests, hasLength(2));
      final second = env.controls.placeRequests.last;
      final lines = (second.body['lines'] as List).cast<JsonMap>();
      expect(lines, hasLength(1), reason: 'oluşan satır yeniden gönderilmez');
      expect(lines.single['quantityLiters'], 8000);
      expect(second.body['paymentGroupKey'], group);
      expect(second.key, isNot(env.controls.placeRequests.first.key));
      await tearDownUi(tester);
    },
  );

  testWidgets(
    'kısmi sonuç → "Siparişlerime git": siparişler açılır (çıkış sayfası yok); kalanlar taslakta',
    (tester) async {
      final (c, router) = await toPartial(tester);
      await tapVisible(
        tester,
        find.widgetWithText(AknButton, OrdersCopy.viewOrders),
      );
      await tester.pump(const Duration(seconds: 1));
      await pumpReal(tester, rounds: 10);
      expect(find.text(OrdersCopy.exitTitle), findsNothing);
      expect(find.byType(OrderWizardPage), findsNothing);
      expect(location(router), AppRoutes.orders);
      expect(find.text(OrdersCopy.partialTitle), findsNothing);
      expect(productsTitle, findsNothing);
      final snap = (await tester.runAsync(
        () => c.read(wizardDraftStoreProvider)!.load(),
      ))!;
      expect(snap.draft.lines, hasLength(1));
      expect(snap.draft.lines.single.liters, 8000);
      expect(snap.created, hasLength(1));
      expect(snap.draft.paymentGroupKey, isNotNull);
      expect(env.controls.placeRequests, hasLength(1));
      expect(c.read(orderSubmitProvider).phase, SubmitPhase.idle);
      await tearDownUi(tester);
    },
  );

  testWidgets(
    'havale: sihirbazda eklenen dekont sipariş oluşunca kendiliğinden yüklenir (bir kez)',
    (tester) async {
      final jpeg = Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9]);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('akn_dekont'),
      ))!;
      final path = '${dir.path}${Platform.pathSeparator}dekont.jpg';
      await tester.runAsync(() => File(path).writeAsBytes(jpeg));
      final uploads = <(PaymentUploadTarget, String, String)>[];
      await openWizard(
        tester,
        extra: [
          a2DocumentPickerProvider.overrideWithValue(
            (context, source, kind) async =>
                CapturedImage(path: path, bytes: jpeg, fileName: 'dekont.jpg'),
          ),
          a2DocumentUploaderProvider.overrideWithValue(({
            required target,
            required image,
            required idempotencyKey,
            onProgress,
          }) async {
            onProgress?.call(1);
            uploads.add((target, image.fileName, idempotencyKey));
          }),
        ],
      );
      await fillLine(tester, '3000');
      await next(tester, deliveryTitle);
      await next(tester, paymentTitle);
      await tapVisible(tester, find.text('Galeriden seç'));
      await pumpUntil(
        tester,
        find.text('Dekont eklendi; sipariş oluşunca yüklenecek.'),
      );
      await next(tester, summaryMarker);
      await tapVisible(tester, find.widgetWithText(AknButton, OrdersCopy.send));
      await pumpUntil(tester, find.text(OrdersCopy.successTitle));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 400));
        await pumpReal(tester, rounds: 2);
      }
      expect(uploads, hasLength(1), reason: 'dekont kendiliğinden yüklendi');
      expect(uploads.single.$1.kind, AttachmentKind.transferReceipt);
      expect(uploads.single.$1.isUploadable, isTrue);
      expect(uploads.single.$2, 'dekont.jpg');
      expect(find.text('Havale / EFT dekontu yüklendi.'), findsOneWidget);
      expect(find.text('Galeriden seç'), findsNothing);
      await tearDownUi(tester);
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );

  for (final scale in [1.0, 2.0]) {
    for (final b in Brightness.values) {
      testWidgets('erişilebilirlik: tüm adımlar ${scale}x ${b.name}', (
        tester,
      ) async {
        await openWizard(tester, textScale: scale, brightness: b);
        Future<void> check() async {
          expect(tester.takeException(), isNull);
          await expectA11y(tester);
        }

        await check();
        await fillLine(tester, '10000');
        await next(tester, deliveryTitle);
        await check();
        await next(tester, paymentTitle);
        await check();
        await next(tester, summaryMarker);
        await check();
        // Gönderim sonrası başarı ekranı (dekont yükleme paneliyle).
        await tapVisible(
          tester,
          find.widgetWithText(AknButton, OrdersCopy.send),
        );
        await pumpUntil(tester, find.text(OrdersCopy.successTitle));
        await pumpReal(tester);
        await check();
        await tearDownUi(tester);
      });
    }
  }

  testWidgets('erişilebilirlik: kısmi sonuç ekranı 2.0x', (tester) async {
    env.controls.failLineAt = 1;
    await openWizard(
      tester,
      location: '/orders/new?fromTemplate=702',
      textScale: 2,
      waitFor: find.textContaining('şablonu yüklendi'),
    );
    await next(tester, deliveryTitle);
    await next(tester, paymentTitle);
    await next(tester, summaryMarker);
    await tapVisible(tester, find.widgetWithText(AknButton, OrdersCopy.send));
    await pumpUntil(tester, find.text(OrdersCopy.partialTitle));
    await pumpReal(tester);
    expect(tester.takeException(), isNull);
    await expectA11y(tester);
    await tearDownUi(tester);
  });
}
