// Sipariş ayrıntısı ve teklif kararı (spec A.4; tasarım v2 §7.8): teklif plakası (toplam, ₺/L, miktar,
// teslim), aşama şeridi, son alımlarla kıyas, belge eksikken Teklifi onayla kapalı (yükleyince açılır),
// onay özeti, revize ön ayar çipleri (web ile aynı),
// expectedQuoteId + anahtar, takip (yolda kamyon, "canlı konum değildir"), teklif bekleyen ipucu,
// çevrimdışı karar kapalı, erişilebilirlik.
import 'dart:typed_data';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/media/image_capture.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/offline/connectivity.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/fake/dispatch_fake.dart';
import 'package:akaryakitnet/features/customer_orders/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import 'support/a2_support.dart';

/// 1×1 JPEG (görsel yükleme testleri için).
final _jpeg = Uint8List.fromList(const [
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, //
  0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9,
]);

void main() {
  late A2Env env;
  late int o2; // karar bekleyen, çek, görsel eksik
  late int o3; // onaylı, yolda
  late int o1; // teklif bekleyen

  // Gerçek yüz (Mona Sans): plaka göstergeleri ve büyük yazı yerleşimi cihazdaki gibi ölçülür
  // (tasarım v2 §14.1). Dosyalar yoksa test yazı tipiyle sürer.
  setUpAll(loadRealFonts);

  setUp(() async {
    env = await A2Env.create();
    final w = env.world;
    o2 = w.orders.firstWhere((o) => o['status'] == 2)['id'] as int;
    o3 =
        w.orders.firstWhere(
              (o) => o['status'] == 3 && o['customerId'] == 101,
            )['id']
            as int;
    o1 =
        w.orders.firstWhere(
              (o) => o['status'] == 1 && o['customerId'] == 101,
            )['id']
            as int;
  });

  List<Override> mediaOverrides() => [
    a2DocumentPickerProvider.overrideWithValue(
      (context, source, kind) async => CapturedImage(
        path: '/tmp/cek.jpg',
        bytes: _jpeg,
        fileName: 'cek.jpg',
      ),
    ),
    a2DocumentUploaderProvider.overrideWithValue(({
      required target,
      required image,
      required idempotencyKey,
      onProgress,
    }) async {
      onProgress?.call(1);
      env.world.attachments.add({
        'publicId': 'p-$idempotencyKey',
        'ownerType': target.ownerType.code,
        'ownerId': target.ownerId,
        'kind': target.kind.code,
        'kindLabel': target.kind.label,
        'fileName': image.fileName,
        'contentType': 'image/jpeg',
        'sizeBytes': image.sizeBytes,
        'isActive': true,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
    }),
  ];

  Future<ProviderContainer> open(
    WidgetTester tester,
    int id, {
    double textScale = 1,
    Brightness brightness = Brightness.light,
    List<Override> extra = const [],
  }) async {
    final c = (await tester.runAsync(
      () => env.signedIn('musteri', extra: [...mediaOverrides(), ...extra]),
    ))!;
    addTearDown(c.dispose);
    await pumpA2(
      tester,
      c,
      initialLocation: '/orders/$id',
      textScale: textScale,
      brightness: brightness,
    );
    await pumpUntil(tester, find.byType(StageStrip));
    await pumpReal(tester);
    return c;
  }

  AknButton approveButton(WidgetTester tester) => tester.widget<AknButton>(
    find.widgetWithText(AknButton, OrdersCopy.approve).first,
  );

  /// ⋯ menüsünden bir seçenek.
  Future<void> openMenu(WidgetTester tester, String item) async {
    await tester.tap(find.bySemanticsLabel('Diğer seçenekler'));
    await pumpUntil(tester, find.text(item));
    await tester.tap(find.text(item));
    await pumpReal(tester);
  }

  testWidgets(
    'teklif plakası: toplam, ₺/L, miktar, teslim; geri sayım; aşama şeridi; son alımlarla kıyas',
    (tester) async {
      await open(tester, o2);
      expect(find.byType(AknPlate), findsOneWidget, reason: 'tek plaka');
      expect(find.text('Demir Petrol teklifi'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Teklif toplamı 338.800,00 lira')),
        findsOneWidget,
      );
      expect(find.textContaining('42,35'), findsWidgets);
      expect(find.text('Kararınızı bekliyor'), findsOneWidget);
      expect(find.byType(CountdownBadge), findsOneWidget);
      final strip = tester.widget<StageStrip>(find.byType(StageStrip));
      expect(strip.stages[strip.current], 'Karar');
      expect(strip.yourMove, isTrue);
      await tester.scrollUntilVisible(
        find.text('Son alımlarınızla kıyas'),
        150,
      );
      expect(
        find.textContaining('alımınızın ortalamasından litrede'),
        findsOneWidget,
      );
      await tearDownUi(tester);
    },
  );

  testWidgets(
    'çek görseli eksik: Onayla kapalı; yükleyince açılır; onay özeti → onaylandı',
    (tester) async {
      await open(tester, o2);
      expect(
        find.text('Onaylamak için çek görselini yükleyin'),
        findsOneWidget,
      );
      expect(approveButton(tester).onPressed, isNull);
      expect(find.textContaining('yüklenmeden onaylanamaz'), findsWidgets);

      final upload = find.text('Belge yükle').first;
      await tester.ensureVisible(upload);
      await tester.pump();
      await tester.tap(upload);
      await pumpUntil(tester, find.text('Galeriden seç'));
      await tester.tap(find.text('Galeriden seç'));
      await pumpUntil(tester, find.widgetWithText(AknButton, 'Yükle'));
      await tester.tap(find.widgetWithText(AknButton, 'Yükle'));
      await pumpUntil(
        tester,
        find.textContaining('Bilgiler hatalıysa bayinize bildirin'),
      );
      await tester.pump(const Duration(seconds: 1));
      await pumpReal(tester, rounds: 10);
      expect(approveButton(tester).onPressed, isNotNull);

      await tester.tap(
        find.widgetWithText(AknButton, OrdersCopy.approve).first,
      );
      await pumpReal(tester);
      expect(find.text('Teklifi onaylıyor musunuz?'), findsOneWidget);
      expect(
        find.textContaining('338.800,00 ₺, 8.000 L, teslim'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(AknButton, OrdersCopy.approve).last);
      await pumpUntil(tester, find.text('Onaylanan teklif'));
      expect(
        find.text('Teklif onaylandı. Bayi sevkiyatı planlayacak.'),
        findsOneWidget,
      );
      final strip = tester.widget<StageStrip>(find.byType(StageStrip));
      expect(strip.stages[strip.current], 'Plan');
      expect(env.world.order(o2)!['status'], 3);
      final sent = env.controls.decisionRequests.last;
      final latestId =
          ((env.world.order(o2)!['quotes'] as List).last as Map)['id'];
      expect(sent.body['expectedQuoteId'], latestId);
      expect(sent.key, isNotNull);
      await tearDownUi(tester);
    },
  );

  testWidgets(
    'revize: web ön ayar çipleri + metin; sipariş revize istendi olur',
    (tester) async {
      await open(tester, o2);
      await tester.tap(find.widgetWithText(AknButton, 'Revize iste'));
      await pumpReal(tester);
      for (final preset in QuoteDecisionPresets.revisionReasons) {
        expect(find.widgetWithText(AknChip, preset), findsOneWidget);
      }
      // Neden seçmeden gönderilemez.
      await tester.tap(find.widgetWithText(AknButton, 'Revize iste').last);
      await tester.pump();
      expect(
        find.text('Revize için bir neden seçin ya da yazın.'),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(AknChip, 'Teslim tarihi uygun değil'),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(AknButton, 'Revize iste').last);
      await pumpUntil(tester, find.text('Revize teklif bekleniyor'));
      expect(env.world.order(o2)!['status'], 5);
      expect(
        find.text('Revize istendi. Bayi yeni teklif hazırlayacak.'),
        findsOneWidget,
      );
      expect(
        ((env.world.order(o2)!['quotes'] as List).last as Map)['revisionNote'],
        'Teslim tarihi uygun değil',
      );
      await tearDownUi(tester);
    },
  );

  testWidgets('ret: web ön ayarları; not isteğe bağlı', (tester) async {
    await open(tester, o2);
    await tester.tap(find.widgetWithText(AknButton, 'Reddet'));
    await pumpReal(tester);
    for (final preset in QuoteDecisionPresets.rejectReasons) {
      expect(find.widgetWithText(AknChip, preset), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(AknButton, OrdersCopy.rejectQuote));
    await pumpUntil(tester, find.text('Reddedildi'));
    expect(env.world.order(o2)!['status'], 4);
    await tearDownUi(tester);
  });

  testWidgets('çevrimdışı: karar düğmeleri kapalı', (tester) async {
    await open(tester, o2, extra: [isOnlineProvider.overrideWithValue(false)]);
    expect(find.text('Çevrimdışıyken karar verilemez'), findsOneWidget);
    expect(approveButton(tester).onPressed, isNull);
    final revise = tester.widget<AknButton>(
      find.widgetWithText(AknButton, 'Revize iste'),
    );
    expect(revise.onPressed, isNull);
    await tearDownUi(tester);
  });

  // Sunucu her yeni teklifi "seçili" kaydeder (OrderService.SubmitQuoteAsync) ve revize / ret / süre
  // dolumunda bunu değiştirmez: "Onaylanan teklif" yalnızca onaylanmış siparişte görünmeli.
  void selectLatestQuote(int id) {
    final quotes = (env.world.order(id)!['quotes'] as List).cast<Map>();
    for (final q in quotes) {
      q['isSelected'] = identical(q, quotes.last);
    }
  }

  testWidgets(
    'revize istenen teklif "Onaylanan teklif" olarak gösterilmez (seçili olsa da)',
    (tester) async {
      selectLatestQuote(o2);
      await open(tester, o2);
      await tester.tap(find.widgetWithText(AknButton, 'Revize iste'));
      await pumpReal(tester);
      await tester.tap(
        find.widgetWithText(AknChip, 'Teslim tarihi uygun değil'),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(AknButton, 'Revize iste').last);
      await pumpUntil(tester, find.text('Revize teklif bekleniyor'));
      await pumpReal(tester);
      expect(env.world.order(o2)!['status'], 5);
      expect(find.text('Onaylanan teklif'), findsNothing);
      expect(find.text('Revize istenen teklif'), findsOneWidget);
      expect(find.text('Teslim tarihi uygun değil'), findsWidgets);
      await tearDownUi(tester);
    },
  );

  for (final (status, title) in const [
    (4, 'Reddedilen teklif'),
    (6, 'Süresi dolan teklif'),
  ]) {
    testWidgets('durum $status: teklif "$title" başlığıyla, onaylı değil', (
      tester,
    ) async {
      selectLatestQuote(o2);
      env.world.order(o2)!['status'] = status;
      await open(tester, o2);
      expect(find.text('Onaylanan teklif'), findsNothing);
      expect(find.text(title), findsOneWidget);
      expect(find.textContaining('42,35'), findsWidgets);
      await tearDownUi(tester);
    });
  }

  testWidgets('onaylı siparişte "Onaylanan teklif"', (tester) async {
    await open(tester, o3);
    expect(find.text('Onaylanan teklif'), findsOneWidget);
    await tearDownUi(tester);
  });

  // Canlı sandbox (sipariş 8284): 6.000 L'nin 5.400 L'si kabul edildi, kalan planı iptal; sipariş
  // "Onaylandı"da kalır ve sunucu müşteriye nedenini söyler (`shipments/order/{id}` → completionHint).
  testWidgets(
    'kısmi teslim, açık sevkiyat yok: "Sipariş henüz tamamlanmadı" notu',
    (tester) async {
      registerBayiDispatchFakes(env.server);
      final w = env.world;
      final qty = (w.order(o3)!['quantityLiters'] as num).toDouble();
      w.shipments.removeWhere((s) => s['orderId'] == o3);
      w.shipments.addAll([
        w.newShipment(
          id: 78001,
          orderId: o3,
          plannedLiters: qty * 0.9,
          status: 3,
          scheduledAt: DateTime.now().subtract(const Duration(hours: 6)),
          deliveredLiters: qty * 0.9,
          deliveryDocumentNo: 'IRS-KISMI-1',
        ),
        w.newShipment(
          id: 78002,
          orderId: o3,
          plannedLiters: qty * 0.1,
          status: 5,
          scheduledAt: DateTime.now().add(const Duration(hours: 20)),
        ),
      ]);
      await open(tester, o3);
      await tester.scrollUntilVisible(
        find.text('Sipariş henüz tamamlanmadı'),
        150,
      );
      expect(
        find.textContaining('Kalan litre bayinin yeni sevkiyatıyla gelir'),
        findsOneWidget,
      );
      await tearDownUi(tester);
    },
  );

  testWidgets('açık sevkiyat varken teslimat özeti okunmaz, not yok', (
    tester,
  ) async {
    var calls = 0;
    env.server.get('shipments/order/{orderId:int}', (req) {
      calls++;
      throw FakeResponse.notFound('Sipariş bulunamadı.');
    });
    await open(tester, o3);
    expect(find.text('Sipariş henüz tamamlanmadı'), findsNothing);
    expect(calls, 0, reason: 'yolda sevkiyat varken istek yok');
    await tearDownUi(tester);
  });

  testWidgets(
    'takip: yoldaki araç, plaka, "canlı konum değildir", sevkiyat kartları',
    (tester) async {
      await open(tester, o3);
      await tester.scrollUntilVisible(
        find.textContaining('canlı konum değildir'),
        150,
      );
      expect(find.byType(TruckRoute), findsOneWidget);
      expect(find.byType(PlateBadge), findsWidgets);
      expect(find.text('Haritada aç'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('SVK-').first, 150);
      expect(find.byType(StepTimeline), findsWidgets);
      await tearDownUi(tester);
    },
  );

  testWidgets(
    'teslimat bildirildi: alt çubukta "Teslimatı onayla" teslimat ayrıntısını açar',
    (tester) async {
      final shipment = env.world.shipments.firstWhere(
        (x) =>
            x['status'] == 2 &&
            env.world.order(x['orderId'] as int)?['customerId'] == 101,
      );
      await open(tester, shipment['orderId'] as int);
      expect(find.text('Teslimatı onaylayın'), findsWidgets);
      await tester.tap(
        find.widgetWithText(AknButton, OrdersCopy.confirmDelivery),
      );
      await pumpReal(tester);
      expect(find.text('ROUTE:/shipments/${shipment['id']}'), findsOneWidget);
      await tearDownUi(tester);
    },
  );

  testWidgets('tamamlanan siparişte alt çubukta "Siparişi tekrarla"', (
    tester,
  ) async {
    final done =
        env.world.orders.firstWhere(
              (o) => o['status'] == 7 && o['customerId'] == 101,
            )['id']
            as int;
    await open(tester, done);
    expect(find.text('Tamamlandı'), findsOneWidget);
    final strip = tester.widget<StageStrip>(find.byType(StageStrip));
    expect(strip.current, strip.stages.length, reason: 'tüm aşamalar bitti');
    expect(find.widgetWithText(AknButton, OrdersCopy.reorder), findsOneWidget);
    expect(find.widgetWithText(AknButton, OrdersCopy.approve), findsNothing);
    await tearDownUi(tester);
  });

  testWidgets('teklif yokken tahmini tutar plakası', (tester) async {
    await open(tester, o1);
    expect(find.byType(AknPlate), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AknPlate),
        matching: find.text('Tahmini tutar'),
      ),
      findsOneWidget,
    );
    expect(find.text('Teklif bekleniyor'), findsWidgets);
    await tearDownUi(tester);
  });

  testWidgets('teklif bekleyen: ipucu ve bayiyi ara', (tester) async {
    await open(tester, o1);
    await tester.scrollUntilVisible(
      find.textContaining(
        'Teklif gelince reddedebilir ya da bayinizi arayabilirsiniz',
      ),
      150,
    );
    expect(find.text('Bayiyi ara'), findsWidgets);
    await tearDownUi(tester);
  });

  testWidgets('avans bakiyesi teklif tutarından azsa Onayla kapalı ve uyarı', (
    tester,
  ) async {
    env.world.order(o2)!['paymentMethodCode'] = 'AVANS';
    env.world.bag<Map<String, double>>('a2.advance', () => {'1': 250000})['1'] =
        1000;
    await open(tester, o2);
    expect(find.text('Ön ödemeli bakiye yetersiz'), findsOneWidget);
    expect(find.text('Onaylamak için çek görselini yükleyin'), findsNothing);
    expect(approveButton(tester).onPressed, isNull);
    await tearDownUi(tester);
  });

  testWidgets('⋯ "Siparişi tekrarla" sihirbazı aynı siparişle özete açar', (
    tester,
  ) async {
    await open(tester, o3);
    await openMenu(tester, OrdersCopy.reorder);
    await pumpUntil(tester, find.textContaining('siparişi tekrarlanıyor'));
    await tester.pump(const Duration(seconds: 1)); // sayfa geçişi biter
    expect(find.text(OrdersCopy.saveAsTemplate), findsOneWidget);
    expect(find.text('Motorin, 20.000 L'), findsOneWidget);
    await tearDownUi(tester);
  });

  testWidgets('⋯ "Şablon olarak kaydet": ad sayfası → şablon kaydedilir', (
    tester,
  ) async {
    final before = A2Fake.templatesOf(env.world, 101).length;
    await open(tester, o3);
    await openMenu(tester, OrdersCopy.makeTemplate);
    await pumpUntil(tester, find.widgetWithText(AknButton, 'Kaydet'));
    await tester.enterText(find.byType(TextField).last, 'Pendik haftalık');
    await tester.tap(find.widgetWithText(AknButton, 'Kaydet'));
    await pumpUntil(tester, find.textContaining('şablon olarak kaydedildi'));
    final list = A2Fake.templatesOf(env.world, 101);
    expect(list.length, before + 1);
    expect(list.any((t) => t['name'] == 'Pendik haftalık'), isTrue);
    await tearDownUi(tester);
  });

  testWidgets('erişilebilirlik: takip ve sevkiyat kartları 2.0x', (
    tester,
  ) async {
    await open(tester, o3, textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.textContaining('SVK-').first, 200);
    expect(tester.takeException(), isNull);
    await expectA11y(tester);
    await tearDownUi(tester);
  });

  testWidgets('teklif süresi kapalıysa geri sayım gösterilmez', (tester) async {
    env.world.bag<Map<String, bool>>('a2.expiry', () => {'on': true})['on'] =
        false;
    await open(tester, o2);
    expect(find.text('Demir Petrol teklifi'), findsOneWidget);
    expect(find.byType(CountdownBadge), findsNothing);
    await tearDownUi(tester);
  });

  testWidgets(
    'çevrimdışı açılış: son görülen sipariş önbellekten, kararlar kapalı',
    (tester) async {
      final first = await open(tester, o2);
      await tearDownUi(tester);
      first.dispose();
      env.server.failureMode = FakeFailureMode.offline;
      final c = env.container(
        extra: [...mediaOverrides(), isOnlineProvider.overrideWithValue(false)],
      );
      addTearDown(c.dispose);
      await tester.runAsync(
        () => c.read(sessionControllerProvider.notifier).restore(),
      );
      await pumpA2(tester, c, initialLocation: '/orders/$o2');
      await pumpUntil(tester, find.text('Demir Petrol teklifi'));
      await pumpReal(tester);
      expect(find.textContaining(OrdersCopy.lastUpdate), findsWidgets);
      expect(find.text(OrdersCopy.decisionOffline), findsOneWidget);
      expect(approveButton(tester).onPressed, isNull);
      await tearDownUi(tester);
    },
  );

  for (final scale in [1.0, 2.0]) {
    for (final b in Brightness.values) {
      testWidgets('erişilebilirlik: karar ekranı ${scale}x ${b.name}', (
        tester,
      ) async {
        await open(tester, o2, textScale: scale, brightness: b);
        expect(tester.takeException(), isNull);
        await expectA11y(tester);
        await tester.scrollUntilVisible(find.text('Ödeme'), 200);
        await expectA11y(tester);
        await tearDownUi(tester);
      });
    }
  }
}
