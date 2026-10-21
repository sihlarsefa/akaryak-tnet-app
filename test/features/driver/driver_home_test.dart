import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/driver/application/driver_home_state.dart';
import 'package:akaryakitnet/features/driver/application/driver_lists.dart';
import 'package:akaryakitnet/features/driver/application/driver_ops.dart';
import 'package:akaryakitnet/features/driver/copy.dart';
import 'package:akaryakitnet/features/driver/data/driver_models.dart';
import 'package:akaryakitnet/features/driver/presentation/driver_home.dart';
import 'package:akaryakitnet/features/driver/presentation/shipment_detail_page.dart';
import 'package:akaryakitnet/features/driver/presentation/widgets/shipment_card.dart';
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
  }) async {
    phoneSize(tester, size);
    h = await real(tester, DriverHarness.create);
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
      // Not hem üstteki uyarıda hem kartta; "Teslimatı düzelt" iki yerde de.
      expect(find.textContaining('5.650 L'), findsNWidgets(2));
      expect(find.text(DriverCopy.disputedTitle), findsOneWidget);
      expect(find.text(DriverCopy.actionFix), findsNWidgets(2));
      // Kahraman: yoldaki teslimat sıradaki.
      expect(find.text(DriverCopy.enRoute), findsWidgets);
      expect(find.text(DriverCopy.actionDeliver), findsOneWidget);
      // Sekme sayıları.
      expect(find.bySemanticsLabel(RegExp('^Bugün, \\d+\$')), findsOneWidget);
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
    await tester.tap(find.byType(ShipmentCard).first);
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
      expect(
        find.textContaining('bağlantı gelince gönderilecek'),
        findsOneWidget,
      );

      c.read(testOnlineProvider.notifier).state = true;
      await pumpUntil(
        tester,
        () => find.text(DriverCopy.opSent).evaluate().isNotEmpty,
      );
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
    expect(find.text(DriverCopy.nothingToday), findsOneWidget);
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
    expect(find.byType(AknHeroPanel), findsOneWidget);
    await finish(tester);
  });
}
