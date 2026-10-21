// Sipariş ayrıntısı ve teklif kararı (spec A.4): kart (₺/L, toplam, vN), önceki alımlar, belge eksikken
// Onayla kapalı (yükleyince açılır), onay özeti, revize ön ayar çipleri (web ile aynı),
// expectedQuoteId + anahtar, takip (yolda kamyon, "canlı konum değildir"), teklif bekleyen ipucu,
// çevrimdışı karar kapalı, erişilebilirlik.
import 'dart:typed_data';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/media/image_capture.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/offline/connectivity.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/customer_orders/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
    await pumpUntil(tester, find.text('Sipariş takibi'));
    await pumpReal(tester);
    return c;
  }

  AknButton approveButton(WidgetTester tester) =>
      tester.widget<AknButton>(find.widgetWithText(AknButton, 'Onayla').first);

  testWidgets('teklif kartı: ₺/L, toplam, sürüm, geri sayım, önceki alımlar', (
    tester,
  ) async {
    await open(tester, o2);
    expect(find.text('Teklif hazır'), findsOneWidget);
    expect(find.text('42,35 ₺/L'), findsWidgets);
    expect(find.text('338.800,00 ₺'), findsWidgets);
    expect(find.textContaining('v1'), findsWidgets);
    expect(find.byType(CountdownBadge), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Önceki alımlarınız'), 150);
    expect(find.textContaining('Son alıma göre'), findsOneWidget);
    await tearDownUi(tester);
  });

  testWidgets(
    'çek görseli eksik: Onayla kapalı; yükleyince açılır; onay özeti → onaylandı',
    (tester) async {
      await open(tester, o2);
      expect(find.text('Çek görseli bekleniyor'), findsWidgets);
      expect(approveButton(tester).onPressed, isNull);
      expect(find.textContaining('yüklenmeden onaylanamaz'), findsWidgets);

      final upload = find.text('Görseli yükle').first;
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

      await tester.tap(find.widgetWithText(AknButton, 'Onayla').first);
      await pumpReal(tester);
      expect(find.text('Teklifi onaylıyor musunuz?'), findsOneWidget);
      expect(
        find.textContaining('338.800,00 ₺ · 8.000 L · teslim'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(AknButton, 'Onayla').last);
      await pumpUntil(tester, find.text('Onaylanan teklif'));
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
        expect(find.widgetWithText(FilterChip, preset), findsOneWidget);
      }
      // Neden seçmeden gönderilemez.
      await tester.tap(find.widgetWithText(AknButton, 'Revize iste').last);
      await tester.pump();
      expect(
        find.text('Revize için bir neden seçin ya da yazın.'),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(FilterChip, 'Teslim tarihi uygun değil'),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(AknButton, 'Revize iste').last);
      await pumpUntil(tester, find.text('Revize teklif bekleniyor'));
      expect(env.world.order(o2)!['status'], 5);
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
      expect(find.widgetWithText(FilterChip, preset), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(AknButton, 'Reddet').last);
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

  testWidgets(
    'takip: yoldaki araç, plaka, "canlı konum değildir", sevkiyat kartları',
    (tester) async {
      await open(tester, o3);
      await tester.scrollUntilVisible(
        find.textContaining('Yolda (canlı konum değildir)'),
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
    expect(find.text('Çek görseli bekleniyor'), findsNothing);
    expect(approveButton(tester).onPressed, isNull);
    await tearDownUi(tester);
  });

  testWidgets('"Tekrarla" sihirbazı aynı siparişle özete açar', (tester) async {
    await open(tester, o3);
    final again = find.widgetWithText(AknButton, 'Tekrarla').first;
    await tester.ensureVisible(again);
    await tester.pump();
    await tester.tap(again);
    await pumpUntil(tester, find.textContaining('siparişi tekrarlanıyor'));
    await tester.pump(const Duration(seconds: 1)); // sayfa geçişi biter
    expect(find.text(OrdersCopy.saveAsTemplate), findsOneWidget);
    expect(find.text('Motorin · 20.000 L'), findsOneWidget);
    await tearDownUi(tester);
  });

  testWidgets('"Şablon yap": ad sayfası → şablon kaydedilir', (tester) async {
    final before = A2Fake.templatesOf(env.world, 101).length;
    await open(tester, o3);
    final make = find.widgetWithText(AknButton, 'Şablon yap');
    await tester.ensureVisible(make);
    await tester.pump();
    await tester.tap(make);
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
    expect(find.text('Teklif hazır'), findsOneWidget);
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
      await pumpUntil(tester, find.text('Teklif hazır'));
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
