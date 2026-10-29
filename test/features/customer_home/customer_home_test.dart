// Müşteri ana sayfası (tasarım v4 "Sade" §3.3): turuncu bant başlığı (şirket, kişi ve rol), bandın
// üstüne binen "Sıra sizde" kartı (görev kutusu; karar, belge, teslimat ve finans soruları ayrı bölüm
// değil, kartın satırları), ilk ekranda yönetici destesi ya da bu ayın kartı, ilk oturumda "Nasıl
// çalışır", "Yolda", "Hızlı sipariş", başlıksız limit ve bayi kartı; çevrimdışı son kayıt ve
// erişilebilirlik (360×640, %100 / %200 yazı, açık / koyu).
import 'dart:typed_data';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/media/image_capture.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/customer_home/api.dart';
import 'package:akaryakitnet/features/customer_home/copy.dart';
import 'package:akaryakitnet/features/customer_home/presentation/home_sections.dart';
import 'package:akaryakitnet/features/customer_orders/api.dart';
import 'package:akaryakitnet/features/customer_orders/application/wizard_models.dart';
import 'package:akaryakitnet/features/customer_orders/application/wizard_store.dart';
import 'package:akaryakitnet/features/stats/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import '../customer_orders/support/a2_support.dart';

/// 1×1 JPEG (görsel yükleme).
final _jpeg = Uint8List.fromList(const [
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, //
  0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9,
]);

void main() {
  test('başlık metinleri: kısa bayi adı, kişi ve rol, ay dönemi', () {
    expect(
      HomeCopy.quoteTitle('Demir Petrol Akaryakıt Ltd. Şti.'),
      'Demir Petrol teklifi',
    );
    expect(HomeCopy.shortCompany('Kuzey Enerji A.Ş.'), 'Kuzey Enerji');
    expect(HomeCopy.shortCompany('Ltd. Şti.'), 'Ltd. Şti.');
    expect(HomeCopy.quoteTitle(null), 'Bayi teklifi');
    expect(HomeCopy.person('Selin Aydın', 'Yönetici'), 'Selin Aydın, yönetici');
    expect(HomeCopy.person('Burak Yılmaz', null), 'Burak Yılmaz');
    expect(
      HomeCopy.limitTitle('Demir Petrol Akaryakıt Ltd. Şti.'),
      'Limit · Demir Petrol',
    );
    expect(
      HomeCopy.stationTitle('Demir Petrol Akaryakıt Ltd. Şti.'),
      'Bayiniz · Demir Petrol',
    );
    expect(monthToDateLabel(DateTime(2026, 10, 21)), '1–21 Ekim');
    expect(monthToDateLabel(DateTime(2026, 10, 1)), '1 Ekim');
    expect(compactMoneyParts(1500000), ('1,5', 'mn ₺'));
  });

  late A2Env env;

  // Gerçek yüz (Archivo): "Sıra sizde"nin baş satırı (başlık + geri sayım) cihazdaki gibi ölçülür.
  // Test yazı tipinde her harf 1 em genişliktedir; uzun geri sayım çekirdeğin satırını taşırır
  // (çekirdeğe bildirildi).
  setUpAll(loadRealFonts);

  setUp(() async {
    env = await A2Env.create();
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
    WidgetTester tester, {
    String persona = 'musteri',
    double textScale = 1,
    Brightness brightness = Brightness.light,
    String location = '/home',
    Finder? waitFor,
    Size size = const Size(360, 640),
    List<Override> extra = const [],
    Future<void> Function(ProviderContainer c)? before,
  }) async {
    final c = (await tester.runAsync(() async {
      final c = await env.signedIn(persona, extra: extra);
      await before?.call(c);
      return c;
    }))!;
    addTearDown(c.dispose);
    await pumpA2(
      tester,
      c,
      initialLocation: location,
      textScale: textScale,
      brightness: brightness,
      size: size,
    );
    await pumpUntil(tester, waitFor ?? find.textContaining('Selin'));
    await pumpReal(tester);
    return c;
  }

  /// "Sıra sizde" kartının içinde.
  Finder inHero(Finder f) =>
      find.descendant(of: find.byType(AknTaskCard), matching: f);

  /// [s] içeren yazı; öndeki işin alt satırında olgular bölünmesin diye boşluklar bölünmez boşluktur.
  Finder textWith(String s) => find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').replaceAll('\u00A0', ' ').contains(s),
  );

  testWidgets(
    'içerik: önce "Sıra sizde" (teklif + eksik çek tek iş), bu ayın kartı, Yolda, Hızlı sipariş, '
    'limit ve bayi',
    (tester) async {
      await open(tester);
      // Karar G: bant selamlama + şirket gösterir; kişi ve rol başlığın ekran okuyucu etiketinde.
      expect(find.textContaining(', Selin'), findsOneWidget);
      expect(
        tester.widget<AknHomeHeader>(find.byType(AknHomeHeader)).person,
        'Selin Aydın, yönetici',
      );
      expect(find.text('Anadolu Lojistik A.Ş.'), findsWidgets);
      // Kahraman: bandın üstündeki ilk kart "Sıra sizde".
      expect(
        find.descendant(
          of: find.byType(AknBandOverlap).first,
          matching: find.byType(AknTaskCard),
        ),
        findsOneWidget,
      );
      expect(inHero(find.text('Sıra sizde')), findsOneWidget);
      expect(inHero(find.text('Teklifi onaylayın')), findsOneWidget);
      // Satır önce siparişi söyler (ürün litre · nokta · bayinin kısa adı); sipariş tek kez (eski
      // "Karar bekleyen" ve "Yüklenecek ödeme belgeleri" bölümleri yok).
      expect(
        inHero(textWith('Motorin 8.000 L · Tuzla Şantiye')),
        findsOneWidget,
      );
      expect(find.textContaining('Akaryakıt Ltd'), findsNothing);
      expect(find.textContaining('Karar bekleyen'), findsNothing);
      expect(find.textContaining('Yüklenecek ödeme'), findsNothing);
      expect(find.text('Demir Petrol teklifi'), findsNothing);
      // Tek birincil düğme: eksik çek görseli önce yüklenir.
      final upload = find.widgetWithText(AknButton, 'Çek görselini yükle');
      expect(upload, findsOneWidget);
      expect(tester.widget<AknButton>(upload).onPressed, isNotNull);
      expect(find.byType(CountdownBadge), findsWidgets);
      // Deste ucu yok (A2 ortamı): bu ayın kartı, kahraman değil (düz).
      expect(find.byType(MonthPlate), findsOneWidget);
      expect(find.text('Bu ay harcama'), findsOneWidget);
      expect(tester.widget<AknPlate>(find.byType(AknPlate)).raised, isFalse);
      await tester.scrollUntilVisible(find.text('Yolda'), 200);
      expect(find.byType(TruckRoute), findsOneWidget);
      // Plaka ana sayfada yazılmaz (ayrıntıda kalır).
      expect(find.textContaining('41 DMR'), findsNothing);
      await tester.scrollUntilVisible(find.text(HomeCopy.reorderLast), 200);
      expect(find.text('Hızlı sipariş'), findsOneWidget);
      expect(find.text('Haftalık motorin – Pendik'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Limit · Demir Petrol'), 200);
      expect(find.byType(UsageBar), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Bayiniz · Demir Petrol'), 200);
      expect(find.widgetWithText(AknButton, HomeCopy.call), findsOneWidget);
      // Kaldırılanlar: asistan kartı (Diğer'de), Şablonlarım bölümü.
      expect(find.text('Asistana sorun'), findsNothing);
      expect(find.text('Şablonlarım'), findsNothing);
      await tearDownUi(tester);
    },
  );

  testWidgets(
    'yönetici destesi "Sıra sizde"nin hemen altında, ilk ekranda (390×844)',
    (tester) async {
      registerStatsFakes(env.server);
      final c = await open(tester, size: const Size(390, 844));
      await pumpUntil(tester, find.byType(ManagerStatsDeck));
      await pumpReal(tester);
      expect(c.read(canSeeStatsDeckProvider), isTrue);
      expect(find.byType(ManagerStatsDeck), findsOneWidget);
      expect(find.byType(MonthPlate), findsNothing);
      expect(
        tester.widget<ManagerStatsDeck>(find.byType(ManagerStatsDeck)).raised,
        isFalse,
      );
      final hero = tester.getRect(find.byType(AknTaskCard));
      final deck = tester.getRect(find.byType(ManagerStatsDeck));
      expect(hero.top, lessThan(260));
      expect(deck.top, greaterThanOrEqualTo(hero.bottom));
      expect(deck.top, lessThan(746), reason: 'sahip kararı 9: deste girişte');
      // İş varken "Nasıl çalışır" destenin altında.
      final hint = find.text('Nasıl çalışır');
      expect(hint, findsOneWidget);
      expect(tester.getRect(hint).top, greaterThan(deck.top));
      await tearDownUi(tester);
    },
  );

  testWidgets(
    'talep eden: deste ve plaka yok; kahraman yalnızca kendi işleri',
    (tester) async {
      registerStatsFakes(env.server);
      await open(
        tester,
        persona: 'talep',
        waitFor: find.textContaining('Burak'),
      );
      expect(find.textContaining(', Burak'), findsOneWidget);
      expect(
        tester.widget<AknHomeHeader>(find.byType(AknHomeHeader)).person,
        'Burak Yılmaz, talep eden',
      );
      expect(find.byType(ManagerStatsDeck), findsNothing);
      expect(find.byType(AknPlate), findsNothing);
      expect(find.byType(AknTaskCard), findsOneWidget);
      // Belge yükleme, teslimat ve finans soruları onaylayanın işidir.
      expect(inHero(find.text('Çek görselini yükle')), findsNothing);
      expect(inHero(find.text('Bekleyen işiniz yok')), findsOneWidget);
      expect(inHero(find.text(HomeCopy.calmCreate)), findsOneWidget);
      await tearDownUi(tester);
    },
  );

  testWidgets('teklif bayinin finansındayken "Sıra sizde"de karar yok', (
    tester,
  ) async {
    for (final o in env.world.ordersOfCustomer(
      findFakePersona('musteri')!.customerId!,
    )) {
      if (o['status'] == 2) o['financeStatus'] = 1;
    }
    await open(tester);
    expect(inHero(find.text('Teklifi onaylayın')), findsNothing);
    expect(find.text('Demir Petrol teklifi'), findsNothing);
    await tearDownUi(tester);
  });

  testWidgets('kahramanın satırı siparişi açar', (tester) async {
    await open(tester);
    await tester.tap(inHero(find.text('Teklifi onaylayın')));
    await pumpReal(tester);
    await pumpReal(tester);
    expect(find.byType(CustomerHome).hitTestable(), findsNothing);
    await tearDownUi(tester);
  });

  testWidgets(
    'çek görselini kahramandan yükle: düğme "Teklifi incele"ye döner, sayı aynı kalır',
    (tester) async {
      await open(tester, extra: mediaOverrides());
      final upload = find.widgetWithText(AknButton, 'Çek görselini yükle');
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
      await pumpReal(tester, rounds: 12);
      await pumpUntil(tester, find.widgetWithText(AknButton, 'Teklifi incele'));
      expect(find.widgetWithText(AknButton, 'Teklifi incele'), findsOneWidget);
      expect(
        find.widgetWithText(AknButton, 'Çek görselini yükle'),
        findsNothing,
      );
      await tearDownUi(tester);
    },
  );

  testWidgets('Hızlı sipariş: şablon satırı sihirbazı şablonla açar', (
    tester,
  ) async {
    await open(tester);
    await tester.scrollUntilVisible(
      find.text('Haftalık motorin – Pendik'),
      200,
    );
    await tester.pump();
    await tester.tap(find.text('Haftalık motorin – Pendik'));
    await pumpUntil(tester, find.text('Ürün ve litre'));
    expect(find.text('Ürün ve litre'), findsOneWidget);
    await tearDownUi(tester);
  });

  testWidgets(
    'Hızlı sipariş: "Son siparişi tekrarla" sihirbazı tekrarla açar',
    (tester) async {
      await open(tester);
      await tester.scrollUntilVisible(find.text(HomeCopy.reorderLast), 200);
      await tester.pump();
      await tester.tap(find.text(HomeCopy.reorderLast));
      await pumpUntil(tester, find.textContaining('siparişi tekrarlanıyor'));
      expect(find.textContaining('siparişi tekrarlanıyor'), findsOneWidget);
      await tearDownUi(tester);
    },
  );

  testWidgets(
    'ilk açılış ipucu: siparişi olmayan müşteride "İlk siparişinizi verin"; "Anladım" kapatır',
    (tester) async {
      env.world.orders.removeWhere((o) => o['customerId'] == 101);
      await open(tester);
      expect(find.text('Nasıl çalışır'), findsOneWidget);
      // Sakin kahramanın hemen altında.
      expect(inHero(find.text('Bekleyen işiniz yok')), findsOneWidget);
      expect(
        find.widgetWithText(AknButton, HomeCopy.firstOrder),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Anladım'));
      await tester.pump();
      await tester.tap(find.text('Anladım'));
      await pumpReal(tester);
      expect(find.text('Nasıl çalışır'), findsNothing);
      expect(
        env.prefs.getKeys().where((k) => k.contains('homeHint')),
        isNotEmpty,
      );
      await tearDownUi(tester);
    },
  );

  test(
    'ipucu yalnızca ilk oturumda: görüldüyse ya da kapatıldıysa gösterilmez',
    () async {
      final store = PrefsStore(env.prefs);
      const seen = 'ipucu-goruldu';
      const done = 'ipucu-kapatildi';
      expect(HomeFirstRunHint.visibleFor(store, seen), isTrue);
      await store.setBool(A2Keys.homeHintSeen(seen), true);
      expect(HomeFirstRunHint.visibleFor(store, seen), isFalse);
      await store.setBool(A2Keys.homeHintDone(done), true);
      expect(HomeFirstRunHint.visibleFor(store, done), isFalse);
    },
  );

  testWidgets('ipucu önceki oturumda görüldüyse (kapatılmasa da) gelmez', (
    tester,
  ) async {
    await open(
      tester,
      before: (c) async {
        final uid = c.read(currentUserIdProvider)!;
        await c
            .read(prefsStoreProvider)
            .setBool(A2Keys.homeHintSeen('$uid-baska'), true);
      },
    );
    // Bu kullanıcı için ilk oturum: görünür.
    expect(find.text('Nasıl çalışır'), findsOneWidget);
    await tearDownUi(tester);
  });

  testWidgets(
    'çevrimdışı: önbellekteki ana sayfa "Son güncelleme" ile açılır',
    (tester) async {
      final first = await open(tester);
      await tearDownUi(tester);
      first.dispose();
      env.server.failureMode = FakeFailureMode.offline;
      final c = env.container();
      addTearDown(c.dispose);
      // Oturum çekirdeğin önbelleğinden açılır (çevrimdışı açılış).
      await tester.runAsync(
        () => c.read(sessionControllerProvider.notifier).restore(),
      );
      await pumpA2(tester, c, initialLocation: '/home');
      await pumpUntil(tester, find.textContaining('Son güncelleme'));
      expect(find.textContaining('Son güncelleme'), findsOneWidget);
      expect(inHero(find.text('Teklifi onaylayın')), findsOneWidget);
      await tearDownUi(tester);
    },
  );

  testWidgets('asistan ana sayfada değil (Diğer sayfasında)', (tester) async {
    await open(
      tester,
      before: (c) => c.read(appConfigProvider.notifier).load(),
    );
    expect(find.byTooltip('Asistan'), findsNothing);
    expect(find.text('Asistana sorun'), findsNothing);
    await tearDownUi(tester);
  });

  testWidgets(
    'yarım kalan sipariş: "Sıra sizde"nin son, sayılmayan satırı; dokununca sihirbaz taslakla açılır',
    (tester) async {
      await open(
        tester,
        before: (c) => c
            .read(wizardDraftStoreProvider)!
            .save(
              WizardSnapshot(
                draft: OrderDraft(
                  stationId: 1,
                  lines: [DraftLine.create(productId: 1, liters: 5000)],
                  pointId: 1001,
                  dirty: true,
                ),
              ),
            ),
      );
      await pumpUntil(
        tester,
        find.byWidgetPredicate(
          (w) =>
              w is AknTaskCard &&
              w.tasks.isNotEmpty &&
              w.tasks.last.title == 'Yarım kalan siparişiniz',
        ),
      );
      final card = tester.widget<AknTaskCard>(find.byType(AknTaskCard));
      final draft = card.tasks.last;
      expect(draft.counts, isFalse, reason: 'taslak sayılmaz');
      expect(draft.subtitle, contains('5.000 L'));
      expect(card.total, card.tasks.where((t) => t.counts).length);
      // Satır sihirbazı taslakla açar.
      draft.onTap!();
      await pumpUntil(tester, find.text('Ürün ve litre'));
      await pumpReal(tester);
      expect(
        find.descendant(
          of: find.byType(LitersField),
          matching: find.text('5.000'),
        ),
        findsOneWidget,
      );
      await tearDownUi(tester);
    },
  );

  for (final scale in [1.0, 2.0]) {
    for (final b in Brightness.values) {
      testWidgets('erişilebilirlik: yazı ${scale}x, ${b.name}', (tester) async {
        await open(tester, textScale: scale, brightness: b);
        expect(tester.takeException(), isNull);
        await expectA11y(tester);
        await tearDownUi(tester);
      });
    }
  }

  testWidgets('Limitler: bayi başına kullanım ve limitsiz bayi', (
    tester,
  ) async {
    await open(
      tester,
      location: limitsRoute,
      waitFor: find.text('Demir Petrol Akaryakıt Ltd. Şti.'),
    );
    expect(find.byType(UsageBar), findsOneWidget);
    expect(find.text('Limitsiz'), findsWidgets);
    expect(find.text('Kalan'), findsOneWidget);
    expect(find.byType(AknCard), findsNothing, reason: 'defter satırları');
    await expectA11y(tester);
    await tearDownUi(tester);
  });
}
