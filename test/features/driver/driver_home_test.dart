import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/driver/application/driver_home_state.dart';
import 'package:akaryakitnet/features/driver/application/driver_lists.dart';
import 'package:akaryakitnet/features/driver/application/driver_ops.dart';
import 'package:akaryakitnet/features/driver/application/location.dart';
import 'package:akaryakitnet/features/driver/copy.dart';
import 'package:akaryakitnet/features/driver/data/driver_models.dart';
import 'package:akaryakitnet/features/driver/presentation/driver_home.dart';
import 'package:akaryakitnet/features/driver/presentation/shipment_detail_page.dart';
import 'package:akaryakitnet/features/driver/presentation/widgets/shipment_card.dart';
import 'package:akaryakitnet/features/driver/presentation/widgets/stop_dock.dart';
import 'package:akaryakitnet/features/driver/presentation/widgets/stop_plate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/driver_harness.dart';

void main() {
  late DriverHarness h;
  late ProviderContainer c;

  Future<void> start(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double textScale = 1,
    String user = 'sofor',
    Size size = const Size(400, 2400),
    void Function(DriverHarness h)? before,
  }) async {
    phoneSize(tester, size);
    h = await real(tester, DriverHarness.create);
    before?.call(h);
    c = h.container();
    await tester.runAsync(() => DriverHarness.login(c, user));
    await tester.pumpWidget(
      driverTestApp(
        container: c,
        initialLocation: '/driver',
        brightness: brightness,
        textScale: textScale,
      ),
    );
    await pumpUntil(
      tester,
      () =>
          c.read(driverListProvider(DriverTab.today)).hasValue &&
          c.read(driverListProvider(DriverTab.upcoming)).hasValue,
    );
    await pumpFor(tester, const Duration(milliseconds: 900));
  }

  Future<void> finish(WidgetTester tester) async {
    await pumpFor(tester, const Duration(milliseconds: 1500));
    await tester.pumpWidget(const SizedBox());
    await pumpFor(tester, const Duration(milliseconds: 300));
    c.dispose();
    h.dispose();
  }

  testWidgets(
    'Bugün: itirazlı teslimat en üstte, not ve "Teslimatı düzelt" ile',
    (tester) async {
      await start(tester);
      expect(find.text(DriverCopy.title), findsOneWidget);
      expect(find.byType(DriverHome), findsOneWidget);
      final cards = find.byType(ShipmentCard);
      expect(cards, findsWidgets);
      final first = tester.widget<ShipmentCard>(cards.first);
      expect(first.row.status, ShipmentStatus.disputed);
      // v4 §5 11: itiraz, kahraman kartın en üstünde tek tehlike satırı (kaydırmadan görünür); not
      // ve "Teslimatı düzelt" aşağıdaki satırda.
      expect(find.text(DriverCopy.disputedCount(1)), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DriverStopPlate),
          matching: find.text(DriverCopy.disputedCount(1)),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text(DriverCopy.disputedCount(1))).dy,
        lessThan(tester.getTopLeft(find.text(DriverCopy.nextOf(1, 2))).dy),
      );
      expect(find.textContaining('5.650 L'), findsOneWidget);
      expect(find.text(DriverCopy.disputedTitle), findsOneWidget);
      expect(find.text(DriverCopy.actionFix), findsOneWidget);
      // Sıradaki durak: yoldaki teslimat; ekranın tek plakası onun litresi.
      expect(find.text(DriverCopy.nextOf(1, 2)), findsOneWidget);
      expect(find.byType(DriverStopPlate), findsOneWidget);
      expect(find.byType(AknPlate), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('^Motorin, bu durakta, 10.000 litre')),
        findsOneWidget,
      );
      expect(find.text('Anadolu Lojistik A.Ş.'), findsOneWidget);
      expect(find.textContaining('Kapı notu'), findsOneWidget);
      expect(find.text('Murat Kaya'), findsOneWidget);
      // Raf: "Teslim et" (konum noktada, birincil) ve "Yol tarifi".
      expect(find.byType(DriverStopDock), findsOneWidget);
      expect(find.text(DriverCopy.actionDeliver), findsOneWidget);
      expect(find.text(DriverCopy.actionNavigate), findsOneWidget);
      expect(
        tester
            .widget<DriverStopDock>(find.byType(DriverStopDock))
            .actionIsPrimary,
        isTrue,
      );
      // Sekme sayıları.
      expect(find.bySemanticsLabel(RegExp('^Bugün, \\d+\$')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'birincil iş tırı izler: noktaya ~17 km iken "Yol tarifi", uzaklık plakada',
    (tester) async {
      await start(
        tester,
        before: (h) => h.location
          ..latitude = 40.9923
          ..longitude = 29.1244,
      );
      final dock = tester.widget<DriverStopDock>(find.byType(DriverStopDock));
      expect(dock.actionIsPrimary, isFalse, reason: 'Yol tarifi birincil');
      expect(find.text(DriverCopy.actionDeliver), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Uzaklık: kuş uçuşu 17 km')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'konum izni yok: "Teslim et" hemen birincil, uzaklık yerine tank',
    (tester) async {
      await start(
        tester,
        before: (h) => h.location.perm = DriverLocationPermission.notDetermined,
      );
      final dock = tester.widget<DriverStopDock>(find.byType(DriverStopDock));
      expect(dock.actionIsPrimary, isTrue);
      expect(h.location.requests, 0, reason: 'ana sayfa izin penceresi açmaz');
      expect(
        find.bySemanticsLabel(RegExp('Tank kapasitesi: 30.000 L')),
        findsOneWidget,
      );
      await finish(tester);
    },
  );

  testWidgets(
    'v4: eşitliyken hap yok; çevrimdışıyken tek uyarı satırı "Çevrimdışı · …"',
    (tester) async {
      await start(tester);
      expect(find.textContaining('Eşitlendi'), findsNothing);
      expect(find.textContaining('Çevrimdışı'), findsNothing);
      c.read(testOnlineProvider.notifier).state = false;
      await pumpFor(tester, const Duration(milliseconds: 400));
      expect(find.text(DriverCopy.offlineWarn), findsOneWidget);
      c.read(testOnlineProvider.notifier).state = true;
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text(DriverCopy.offlineWarn), findsNothing);
      await finish(tester);
    },
  );

  testWidgets(
    'v4: her litre etiketli — "18.000 L yük · 2 durak", "Motorin, bu durakta", '
    '"Tank kapasitesi"; varış planının altında teslim aralığı; bantta "Teslimatlar"',
    (tester) async {
      // Konum izni yok: uzaklık yerine tank kapasitesi okunur.
      await start(
        tester,
        before: (h) => h.location.perm = DriverLocationPermission.notDetermined,
      );
      expect(find.text('Teslimatlar'), findsOneWidget);
      expect(find.text('Teslimatlarım'), findsNothing);
      expect(find.text(DriverCopy.nextOf(1, 2)), findsOneWidget);
      expect(find.text('Sıradaki teslimat 1 / 2'), findsOneWidget);
      expect(find.textContaining(' yük · 2 durak'), findsOneWidget);
      expect(find.text('18.000 L yük · 2 durak'), findsOneWidget);
      expect(find.text(DriverCopy.readoutPlan), findsOneWidget);
      expect(find.text(DriverCopy.readoutTank), findsOneWidget);
      expect(find.text('teslim aralığı 08:00–18:00'), findsOneWidget);
      // "Teslim saati" ayrı okuma değil (varış planının alt satırı).
      expect(find.text(DriverCopy.readoutWindow), findsNothing);
      // (Okumaların tek satıra sığması gerçek yazı tipiyle ekran görüntüsünde denetlenir; test yazı
      // tipinin kare harfleri daha geniştir.)
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets('ilk giriş ipucu bir kez gösterilir, "Anladım" ile kapanır', (
    tester,
  ) async {
    await start(tester);
    expect(find.text(DriverCopy.tipTitle), findsOneWidget);
    await tester.ensureVisible(find.text(DriverCopy.tipDismiss));
    await tester.tap(find.text(DriverCopy.tipDismiss));
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(find.text(DriverCopy.tipTitle), findsNothing);
    expect(h.prefs.getBool(DriverTipController.keyFor('u-sofor')), isTrue);
    await finish(tester);
  });

  testWidgets('Yaklaşan ve Geçmiş sekmeleri sunucu kapsamlarını gösterir', (
    tester,
  ) async {
    await start(tester);
    await tester.ensureVisible(find.text('Yaklaşan'));
    await tester.tap(find.text('Yaklaşan'));
    await pumpUntil(
      tester,
      () => c.read(driverListProvider(DriverTab.upcoming)).hasValue,
    );
    await pumpFor(tester, const Duration(milliseconds: 600));
    final upcoming = tester
        .widgetList<ShipmentCard>(find.byType(ShipmentCard))
        .toList();
    expect(upcoming, isNotEmpty);
    expect(
      upcoming.every((w) => w.row.status == ShipmentStatus.planned),
      isTrue,
    );

    await tester.tap(find.text('Geçmiş'));
    await pumpUntil(
      tester,
      () => c.read(driverListProvider(DriverTab.history)).hasValue,
    );
    await pumpFor(tester, const Duration(milliseconds: 600));
    final history = tester
        .widgetList<ShipmentCard>(find.byType(ShipmentCard))
        .toList();
    expect(history, isNotEmpty);
    expect(history.first.history, isTrue);
    expect(find.textContaining('Teslim edilen'), findsWidgets);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('karta dokununca ayrıntı açılır', (tester) async {
    await start(tester);
    await tester.tap(
      find
          .descendant(
            of: find.byType(ShipmentCard).first,
            matching: find.byType(InkWell),
          )
          .first,
    );
    await pumpUntil(
      tester,
      () => find.byType(ShipmentDetailPage).evaluate().isNotEmpty,
    );
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(find.byType(ShipmentDetailPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets(
    'kart: "Gönderilmeyi bekliyor" → sunucu onaylayınca başarı, sonra kalkar',
    (tester) async {
      await start(tester);
      final planned =
          h.world.shipments.firstWhere(
                (s) => s['status'] == 0 && s['driverUserId'] == 'u-sofor',
              )['id']
              as int;
      c.read(testOnlineProvider.notifier).state = false;
      await tester.pump();
      await tester.runAsync(
        () => c
            .read(driverCommandsProvider)
            .start(shipmentId: planned, code: 'SVK'),
      );
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text(DriverCopy.opWaiting), findsOneWidget);
      // v4: çevrimdışı bekleyen sayısını eşitleme satırı söyler (şerit aynı şeyi yinelemez).
      expect(find.text(DriverCopy.offlineWarnCount(1)), findsOneWidget);
      expect(
        find.textContaining('bağlantı gelince gönderilecek'),
        findsNothing,
      );

      c.read(testOnlineProvider.notifier).state = true;
      await pumpUntil(
        tester,
        () => find.text(DriverCopy.opSent).evaluate().isNotEmpty,
      );
      // Lamba geçişi (250 ms) bitsin.
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.text(DriverCopy.opSent), findsOneWidget);
      expect(find.text(DriverCopy.opWaiting), findsNothing);
      await pumpFor(tester, const Duration(seconds: 4));
      expect(find.text(DriverCopy.opSent), findsNothing);
      expect(
        h.world.shipments.firstWhere((s) => s['id'] == planned)['status'],
        1,
      );
      await finish(tester);
    },
  );

  testWidgets('kendisi teslim eden personel (sahip): kendi teslimatı', (
    tester,
  ) async {
    await start(tester, user: 'sahip');
    final today = c.read(driverListProvider(DriverTab.today)).value!;
    expect(today.items, isEmpty, reason: 'yarına planlı');
    final upcoming = c.read(driverListProvider(DriverTab.upcoming)).value!;
    expect(upcoming.items, hasLength(1));
    expect(find.text(DriverCopy.emptyTodayTitle), findsOneWidget);
    expect(find.bySemanticsLabel('Yaklaşan, 1'), findsOneWidget);
    await finish(tester);
  });

  for (final b in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('erişilebilirlik: ${b.name}, yazı ${scale}x, 360×640', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await start(
          tester,
          brightness: b,
          textScale: scale,
          size: const Size(360, 640),
        );
        expect(tester.takeException(), isNull, reason: 'taşma yok');
        await expectA11y(tester);
        // Aşağı kaydırıp listeyi de denetle.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
        await pumpFor(tester, const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        await expectA11y(tester);
        handle.dispose();
        await finish(tester);
      });
    }
  }

  testWidgets('çevrimdışı ve önbellek yok: "Çevrimdışısınız" + yeniden dene', (
    tester,
  ) async {
    phoneSize(tester, const Size(400, 2400));
    h = await real(tester, DriverHarness.create);
    c = h.container();
    await tester.runAsync(() => DriverHarness.login(c, 'sofor'));
    h.server.failureMode = FakeFailureMode.offline;
    await tester.pumpWidget(
      driverTestApp(container: c, initialLocation: '/driver'),
    );
    await pumpUntil(
      tester,
      () => c.read(driverListProvider(DriverTab.today)).hasError,
    );
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text(DriverCopy.offlineNoCacheTitle), findsOneWidget);
    expect(find.byType(DriverStopPlate), findsNothing);
    expect(find.byType(ChevronSpinner), findsNothing);

    h.server.failureMode = FakeFailureMode.none;
    await tester.tap(find.text(DriverCopy.opRetry));
    await pumpUntil(
      tester,
      () => c.read(driverListProvider(DriverTab.today)).hasValue,
    );
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.byType(ShipmentCard), findsWidgets);
    await finish(tester);
  });

  testWidgets('hareket azaltılmış: animasyonsuz çizilir', (tester) async {
    phoneSize(tester, const Size(400, 2400));
    h = await real(tester, DriverHarness.create);
    c = h.container();
    await tester.runAsync(() => DriverHarness.login(c, 'sofor'));
    await tester.pumpWidget(
      driverTestApp(
        container: c,
        initialLocation: '/driver',
        reduceMotion: true,
      ),
    );
    await pumpUntil(
      tester,
      () => c.read(driverListProvider(DriverTab.today)).hasValue,
    );
    await tester.pump();
    expect(find.byType(ShipmentCard), findsWidgets);
    expect(find.byType(DriverStopPlate), findsOneWidget);
    await finish(tester);
  });
}
