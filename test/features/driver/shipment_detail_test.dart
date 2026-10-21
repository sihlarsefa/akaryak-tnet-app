import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/offline/outbox_op.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/driver/application/driver_lists.dart';
import 'package:akaryakitnet/features/driver/application/driver_ops.dart';
import 'package:akaryakitnet/features/driver/copy.dart';
import 'package:akaryakitnet/features/driver/data/driver_models.dart';
import 'package:akaryakitnet/features/driver/presentation/shipment_detail_page.dart';
import 'package:akaryakitnet/features/weather/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/driver_harness.dart';

void main() {
  late DriverHarness h;
  late ProviderContainer c;

  int idWhere(int status) =>
      h.world.shipments.firstWhere(
            (s) => s['status'] == status && s['driverUserId'] == 'u-sofor',
          )['id']
          as int;

  Future<int> open(
    WidgetTester tester,
    int Function() pick, {
    Brightness brightness = Brightness.light,
    double textScale = 1,
    Size size = const Size(400, 1600),
  }) async {
    phoneSize(tester, size);
    h = await real(tester, DriverHarness.create);
    c = h.container();
    await tester.runAsync(() => DriverHarness.login(c, 'sofor'));
    // Örnek kayıtlar ilk şoför isteğinde eklenir.
    await tester.runAsync(
      () => c.read(driverListProvider(DriverTab.today).future),
    );
    final id = pick();
    await tester.pumpWidget(
      driverTestApp(
        container: c,
        initialLocation: '/driver/shipments/$id',
        brightness: brightness,
        textScale: textScale,
      ),
    );
    await pumpUntil(tester, () => c.read(driverShipmentProvider(id)).hasValue);
    await pumpFor(tester, const Duration(milliseconds: 800));
    return id;
  }

  Future<void> finish(WidgetTester tester) async {
    await pumpFor(tester, const Duration(milliseconds: 1500));
    await tester.pumpWidget(const SizedBox());
    await pumpFor(tester, const Duration(milliseconds: 300));
    c.dispose();
    h.dispose();
  }

  OutboxOp? startOp(int id) => c.read(driverOpsProvider)[id]?.start;

  testWidgets(
    'yola çık: ekran okuyucu dokunuşuyla onay, çevrimiçi → gönderildi',
    (tester) async {
      final handle = tester.ensureSemantics();
      final id = await open(tester, () => idWhere(0));
      expect(find.byType(ShipmentDetailPage), findsOneWidget);
      expect(find.byType(SlideToConfirm), findsOneWidget);
      expect(
        find.textContaining('Yola çıkış konumu eklenecek'),
        findsOneWidget,
      );

      final node = tester.getSemantics(
        find.bySemanticsLabel(DriverCopy.slideStart),
      );
      expect(node.hint, 'Yola çıkmak için iki kez dokunun');
      tester.semantics.tap(find.semantics.byLabel(DriverCopy.slideStart));
      await pumpUntil(tester, () => startOp(id)?.status == OutboxStatus.done);
      await tester.pump(const Duration(milliseconds: 300));
      expect(startOp(id)?.status, OutboxStatus.done);
      expect(find.text(DriverCopy.startSentTitle), findsOneWidget);
      expect(find.byType(SuccessCheck), findsWidgets);
      final s = h.world.shipments.firstWhere((x) => x['id'] == id);
      expect(s['status'], 1);
      expect(s['dispatchLatitude'], 40.911912);
      // Ayrıntı yenilenir; başarı anı geçince "Teslim et".
      await pumpUntil(
        tester,
        () =>
            c.read(driverShipmentProvider(id)).value?.detail.row.isInTransit ??
            false,
      );
      await pumpFor(tester, const Duration(seconds: 6));
      expect(find.text(DriverCopy.actionDeliver), findsOneWidget);
      expect(tester.takeException(), isNull);
      handle.dispose();
      await finish(tester);
    },
  );

  testWidgets(
    'çevrimdışı yola çıkış: "Kaydedildi — bağlantı gelince gönderilecek", '
    'başarı işareti yok; bağlantı gelince gönderilir',
    (tester) async {
      final handle = tester.ensureSemantics();
      final id = await open(tester, () => idWhere(0));
      c.read(testOnlineProvider.notifier).state = false;
      await tester.pump();
      tester.semantics.tap(find.semantics.byLabel(DriverCopy.slideStart));
      await pumpUntil(tester, () => startOp(id) != null);
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(startOp(id)?.status, OutboxStatus.pending);
      expect(find.text(DriverCopy.queuedTitle), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsWidgets);
      expect(
        find.byType(SuccessCheck),
        findsNothing,
        reason: 'kuyrukta başarı yok',
      );
      // Kartta: Gönderilmeyi bekliyor.
      expect(find.text(DriverCopy.opWaiting), findsOneWidget);
      // Yola çıkış beklerken teslime devam edilebilir.
      expect(find.text(DriverCopy.actionDeliver), findsOneWidget);
      expect(h.world.shipments.firstWhere((x) => x['id'] == id)['status'], 0);

      c.read(testOnlineProvider.notifier).state = true;
      await pumpUntil(tester, () => startOp(id)?.status == OutboxStatus.done);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(DriverCopy.startSentTitle), findsOneWidget);
      expect(find.byType(SuccessCheck), findsWidgets);
      expect(h.world.shipments.firstWhere((x) => x['id'] == id)['status'], 1);
      await pumpFor(tester, const Duration(seconds: 6));
      handle.dispose();
      await finish(tester);
    },
  );

  testWidgets('hava durumu ve sürüş uyarısı (özellik açık, koordinat var)', (
    tester,
  ) async {
    final id = await open(tester, () => idWhere(0));
    expect(
      find.byType(WeatherCard),
      findsNothing,
      reason: 'özellik kapalıyken',
    );
    await tester.runAsync(() => c.read(appConfigProvider.notifier).load());
    await tester.pump();
    expect(c.read(appConfigProvider).features.weather, isTrue);
    expect(find.byType(DrivingAlertBanner), findsOneWidget);
    final card = tester.widget<WeatherCard>(find.byType(WeatherCard));
    final d = c.read(driverShipmentProvider(id)).value!.detail;
    expect(card.lat, d.latitude);
    expect(card.lng, d.longitude);
    await finish(tester);
  });

  testWidgets('itirazlı: müşteri notu ve "Teslimatı düzelt"', (tester) async {
    await open(tester, () => idWhere(4));
    expect(find.text(DriverCopy.disputedTitle), findsOneWidget);
    expect(find.textContaining('5.650 L'), findsOneWidget);
    expect(find.text(DriverCopy.actionFix), findsOneWidget);
    // Plaka teslim edilen litreyi taşır (tek plaka).
    expect(find.byType(AknPlate), findsOneWidget);
    expect(find.text(DriverCopy.plateDelivered), findsOneWidget);
    // Teslim kanıtı (önceki bildirim) aşağıda.
    await tester.scrollUntilVisible(
      find.text('IRS-779104'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(DriverCopy.proofTitle), findsOneWidget);
    expect(find.text('IRS-779104'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('kabul bekleyen: teslim kanıtı, eylem yok', (tester) async {
    await open(tester, () => idWhere(2));
    await tester.scrollUntilVisible(
      find.text('IRS-778812'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(DriverCopy.proofTitle), findsOneWidget);
    expect(find.text('IRS-778812'), findsOneWidget);
    expect(find.text('Kemal Uçar'), findsWidgets);
    expect(find.byType(SlideToConfirm), findsNothing);
    expect(find.text(DriverCopy.actionDeliver), findsNothing);
    expect(
      find.text('Teslimat bildirildi; müşteri onayı bekleniyor.'),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('başka şoföre geçmiş kayıt: "Bu kayıt artık görüntülenemiyor"', (
    tester,
  ) async {
    phoneSize(tester);
    h = await real(tester, DriverHarness.create);
    c = h.container();
    await tester.runAsync(() => DriverHarness.login(c, 'sofor'));
    await tester.pumpWidget(
      driverTestApp(container: c, initialLocation: '/driver/shipments/999999'),
    );
    await pumpUntil(
      tester,
      () => c.read(driverShipmentProvider(999999)).hasError,
    );
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text(DriverCopy.notFoundTitle), findsOneWidget);
    await finish(tester);
  });

  for (final b in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('erişilebilirlik (planlı): ${b.name}, ${scale}x, 360×640', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await open(
          tester,
          () => idWhere(0),
          brightness: b,
          textScale: scale,
          size: const Size(360, 640),
        );
        expect(tester.takeException(), isNull);
        await expectA11y(tester);
        await tester.drag(find.byType(ListView).first, const Offset(0, -600));
        await pumpFor(tester, const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        await expectA11y(tester);
        handle.dispose();
        await finish(tester);
      });
    }
  }
}
