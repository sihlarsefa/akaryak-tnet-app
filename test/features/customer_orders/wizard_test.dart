// "Sipariş ver" sihirbazı (spec A.3 adım 1, A.4 A2, C.4a, C.5): bayi seçici, ürün + litre, tank
// uyarısı, önerilen teslim tarihi, sipariş verilebilirlik denetimi, çek tutarı / vadesi ön dolumu ve
// farklılık uyarısı, Talep eden için şirket içi onay uyarısı + "Onaylayana not", teklif süresi notu,
// "Şablon olarak kaydet", gönderim (başarı / kısmi → kalanları yeni anahtar + aynı ödeme grubuyla),
// şablondan / talepten / tekrarla açılış, çıkışta taslak sakla / çık, C.7 erişilebilirlik.
import 'dart:async';
import 'dart:typed_data';

import 'package:akaryakitnet/core/media/image_capture.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/core/utils/format.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/customer_orders/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/a2_support.dart';

void main() {
  late A2Env env;

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
    await tapVisible(tester, find.widgetWithText(ChoiceChip, product).first);
    await tester.enterText(find.byType(TextField).first, liters);
    await tester.pump();
  }

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
      // Vade alanında ve ödeme özetinde ("Çek · 30 gün · vade …").
      expect(
        find.textContaining(Fmt.date(TrTime.addDays(tomorrow, 30))),
        findsNWidgets(2),
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
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Kurşunsuz Benzin 95'),
    );
    expect(chip.selected, isTrue);
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
      final note = find.widgetWithText(TextField, OrdersCopy.noteForApprover);
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
      expect(
        find.widgetWithText(TextField, OrdersCopy.noteForApprover),
        findsNothing,
      );
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
      expect(find.text('Motorin · 20.000 L'), findsOneWidget);
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
