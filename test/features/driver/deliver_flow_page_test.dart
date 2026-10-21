import 'dart:io';

import 'package:akaryakitnet/core/offline/outbox_op.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/driver/application/camera.dart';
import 'package:akaryakitnet/features/driver/application/driver_lists.dart';
import 'package:akaryakitnet/features/driver/application/driver_ops.dart';
import 'package:akaryakitnet/features/driver/application/location.dart';
import 'package:akaryakitnet/features/driver/copy.dart';
import 'package:akaryakitnet/features/driver/data/deliver_draft.dart';
import 'package:akaryakitnet/features/driver/data/driver_models.dart';
import 'package:akaryakitnet/features/driver/presentation/deliver_flow_page.dart';
import 'package:akaryakitnet/features/driver/presentation/widgets/litre_keypad.dart';
import 'package:akaryakitnet/features/driver/presentation/widgets/stop_plate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/driver_harness.dart';

void main() {
  late DriverHarness h;
  late ProviderContainer c;
  late int id;

  int inTransit() =>
      h.world.shipments.firstWhere(
            (s) => s['status'] == 1 && s['driverUserId'] == 'u-sofor',
          )['id']
          as int;

  Future<void> boot(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double textScale = 1,
    Size size = const Size(400, 1400),
    DriverHarness? reuse,
    void Function(DriverHarness h)? before,
    DeliverDraft Function(int id)? seedDraft,
  }) async {
    phoneSize(tester, size);
    h = reuse ?? await real(tester, DriverHarness.create);
    before?.call(h);
    c = h.container();
    await tester.runAsync(() => DriverHarness.login(c, 'sofor'));
    await tester.runAsync(
      () => c.read(driverListProvider(DriverTab.today).future),
    );
    id = inTransit();
    final draft = seedDraft?.call(id);
    if (draft != null) {
      await tester.runAsync(
        () => DeliverDraftStore(
          PrefsStore(h.prefs),
          h.files,
        ).save('u-sofor', draft),
      );
    }
    await tester.pumpWidget(
      driverTestApp(
        container: c,
        initialLocation: '/driver/shipments/$id/deliver',
        brightness: brightness,
        textScale: textScale,
      ),
    );
    await pumpUntil(tester, () => c.read(driverShipmentProvider(id)).hasValue);
    await pumpFor(tester, const Duration(milliseconds: 700));
  }

  Future<void> finish(WidgetTester tester, {bool keepHarness = false}) async {
    await pumpFor(tester, const Duration(milliseconds: 1500));
    await tester.pumpWidget(const SizedBox());
    await pumpFor(tester, const Duration(milliseconds: 400));
    c.dispose();
    if (!keepHarness) h.dispose();
  }

  Finder key(String k) => find.descendant(
    of: find.byType(LitreKeypad),
    matching: find.bySemanticsLabel(k),
  );

  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.text(DriverCopy.next));
    await pumpFor(tester, const Duration(milliseconds: 450));
  }

  String photo() {
    final f = File(
      '${h.dir.path}/seed-${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    f.writeAsBytesSync(sampleJpeg);
    return f.path;
  }

  OutboxOp? deliverOp() => c.read(driverOpsProvider)[id]?.deliver;

  Map<String, dynamic> shipment() =>
      h.world.shipments.firstWhere((s) => s['id'] == id);

  DeliverDraft summaryDraft(int sid, {String doc = 'IRS-5001'}) => DeliverDraft(
    shipmentId: sid,
    code: DriverShipmentRow.shipmentCode(sid),
    step: DeliverStep.summary,
    litersText: '9950',
    documentNo: doc,
    recipientName: 'Murat Kaya',
    photos: [DraftPhoto(path: photo())],
    waiver: const SignatureWaiver(SignatureWaiverReason.refused),
    savedAt: DateTime.now().toUtc(),
  );

  testWidgets('tam akış: tuşlar → irsaliye → teslim alan → fotoğraf → '
      'imza alınamadı → özet → kaydırarak onay → teslimat bildirildi', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await boot(tester);
    expect(find.byType(DeliverFlowPage), findsOneWidget);
    expect(find.text(DriverCopy.flowTitle), findsWidgets);
    // Sayaç adımı: ekranın tek plakası okumayı ve planlananı gösterir.
    expect(find.byType(DriverStopPlate), findsOneWidget);
    expect(find.text(DriverCopy.plateReading), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Planlanan 10.000 L')), findsOneWidget);

    // 1. Litre: önce boş ileri → hata, sonra tuşlar.
    await tapNext(tester);
    expect(find.text(DriverCopy.litersRequired), findsOneWidget);
    for (final k in ['9', '9', '5', '0']) {
      await tester.tap(key(k));
      await tester.pump();
    }
    expect(find.bySemanticsLabel(RegExp(r'9\.950 litre')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Fark 50 L eksik')), findsOneWidget);
    await tapNext(tester);

    // 2. İrsaliye.
    expect(find.text(DriverCopy.documentHint), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'IRS-5001');
    await tapNext(tester);

    // 3. Teslim alan: yetkiliyi yaz.
    await tester.tap(find.textContaining(DriverCopy.recipientUseContact));
    await tester.pump();
    await tapNext(tester);

    // 4. Fotoğraf (sahte kamera).
    expect(find.text(DriverCopy.photosRequired), findsOneWidget);
    await tester.tap(find.text(DriverCopy.photoTake));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text(DriverCopy.photoCount(1)), findsOneWidget);
    await tapNext(tester);

    // 5. İmza alınamıyor → İmzadan imtina.
    await tester.tap(find.text(DriverCopy.signatureCantGet));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text(DriverCopy.waiverSubtitle), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('^İmzadan imtina')));
    await tester.pump();
    await tester.tap(find.text(DriverCopy.waiverConfirm));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text(DriverCopy.signatureWaived), findsOneWidget);
    await tapNext(tester);

    // 6. Özet: konum alındı, kaydırıcı açık.
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.textContaining('Konum alındı'), findsOneWidget);
    expect(find.text('9.950 L'), findsOneWidget);
    expect(find.text('IRS-5001'), findsOneWidget);
    final slide = tester.getSemantics(
      find.bySemanticsLabel(DriverCopy.slideDeliver),
    );
    expect(slide.flagsCollection.isEnabled, isNotNull);
    tester.semantics.tap(find.semantics.byLabel(DriverCopy.slideDeliver));
    await pumpUntil(tester, () => deliverOp()?.status == OutboxStatus.done);
    await pumpFor(tester, const Duration(milliseconds: 900));
    expect(
      deliverOp()?.status,
      OutboxStatus.done,
      reason: deliverOp()?.lastError,
    );
    expect(find.text(DriverCopy.deliverSentTitle), findsOneWidget);
    expect(find.byType(SuccessCheck), findsOneWidget);

    final s = shipment();
    expect(s['status'], 2);
    expect(s['deliveredLiters'], 9950);
    expect(s['deliveryDocumentNo'], 'IRS-5001');
    expect(s['recipientName'], 'Murat Kaya');
    expect(s['signatureWaiverLabel'], 'İmzadan imtina');
    expect(s['deliveredLatitude'], 40.911912);
    expect(
      DeliverDraftStore(PrefsStore(h.prefs), h.files).get('u-sofor', id),
      isNull,
      reason: 'taslak işleme devredildi',
    );
    expect(tester.takeException(), isNull);
    handle.dispose();
    await finish(tester);
  });

  testWidgets(
    'çevrimdışı: "Teslimat telefona kaydedildi" (uyarı + '
    'saat, başarı işareti yok); bağlantı gelince gönderilir ve başarı oynar',
    (tester) async {
      final handle = tester.ensureSemantics();
      await boot(tester, seedDraft: summaryDraft);
      expect(find.text(DriverCopy.stepSummary), findsOneWidget);
      c.read(testOnlineProvider.notifier).state = false;
      await tester.pump();
      tester.semantics.tap(find.semantics.byLabel(DriverCopy.slideDeliver));
      await pumpUntil(tester, () => deliverOp() != null);
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text(DriverCopy.queuedDeliverTitle), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      expect(find.byType(SuccessCheck), findsNothing);
      expect(deliverOp()?.status.isWaiting, isTrue);
      expect(shipment()['status'], 1);

      c.read(testOnlineProvider.notifier).state = true;
      await pumpUntil(tester, () => deliverOp()?.status == OutboxStatus.done);
      await pumpFor(tester, const Duration(milliseconds: 900));
      expect(find.text(DriverCopy.deliverSentTitle), findsOneWidget);
      expect(find.byType(SuccessCheck), findsOneWidget);
      expect(shipment()['status'], 2);
      handle.dispose();
      await finish(tester);
    },
  );

  testWidgets('uygulama yeniden açılınca kaldığı adımdan sürer (24 saat)', (
    tester,
  ) async {
    await boot(tester);
    for (final k in ['8', '0', '0', '0']) {
      await tester.tap(key(k));
      await tester.pump();
    }
    await tapNext(tester);
    await tester.enterText(find.byType(TextField), 'IRS-42');
    await tapNext(tester);
    expect(find.text(DriverCopy.recipientHint), findsOneWidget);
    await finish(tester, keepHarness: true);

    // "Yeniden açılış": aynı tercihlerle yeni oturum.
    final previous = h;
    await boot(tester, reuse: previous);
    expect(find.text(DriverCopy.recipientHint), findsOneWidget);
    expect(find.text(DriverCopy.stepRecipient), findsOneWidget);
    await tester.tap(find.text(DriverCopy.back));
    await pumpFor(tester, const Duration(milliseconds: 450));
    expect(find.text('IRS-42'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('sunucu reddederse: sunucu mesajı + "Düzelt" / "Vazgeç"', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await boot(tester, seedDraft: summaryDraft);
    // Bu arada bayi personeli farklı bilgilerle teslim bildirdi.
    final s = shipment();
    s['status'] = 2;
    s['deliveredLiters'] = 9000.0;
    s['deliveryDocumentNo'] = 'IRS-WEB';
    tester.semantics.tap(find.semantics.byLabel(DriverCopy.slideDeliver));
    await pumpUntil(
      tester,
      () => deliverOp()?.status == OutboxStatus.needsAttention,
    );
    await pumpFor(tester, const Duration(milliseconds: 700));
    expect(find.text(DriverCopy.deliverFailedTitle), findsOneWidget);
    expect(
      find.text(
        'Bu teslimat farklı litre ya da irsaliye numarasıyla zaten bildirilmiş.',
      ),
      findsOneWidget,
    );
    expect(find.text(DriverCopy.opFix), findsOneWidget);
    expect(find.text(DriverCopy.opDiscard), findsOneWidget);
    expect(find.byType(SuccessCheck), findsNothing);
    handle.dispose();
    await finish(tester);
  });

  testWidgets(
    'imza alınamadı + konum izni yok: ön sayfa kendiliğinden, "Devam" '
    'ile sistem izni ve konum; zorunluyken "Konumsuz devam et" yok',
    (tester) async {
      await boot(
        tester,
        before: (h) => h.location.perm = DriverLocationPermission.notDetermined,
        seedDraft: summaryDraft,
      );
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text(DriverCopy.primerLocationTitle), findsOneWidget);
      expect(find.text(DriverCopy.locationSkip), findsNothing);
      await tester.tap(find.text(DriverCopy.primerContinue));
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(h.location.requests, 1);
      expect(find.textContaining('Konum alındı'), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('ayrıntıdan "Düzelt": reddedilen teslim değerleriyle özete döner, '
      'konum eklenip yeniden gönderilir; eski işlem kalkar', (tester) async {
    final handle = tester.ensureSemantics();
    phoneSize(tester, const Size(400, 1400));
    h = await real(tester, DriverHarness.create);
    c = h.container();
    await tester.runAsync(() => DriverHarness.login(c, 'sofor'));
    await tester.runAsync(
      () => c.read(driverListProvider(DriverTab.today).future),
    );
    id = inTransit();
    // Konumsuz "imza alınamadı" → sunucu reddeder.
    final rejected = await real(
      tester,
      () => c
          .read(driverCommandsProvider)
          .deliver(
            draft: DeliverDraft(
              shipmentId: id,
              code: DriverShipmentRow.shipmentCode(id),
              litersText: '9950',
              documentNo: 'IRS-77',
              photos: [DraftPhoto(path: photo())],
              waiver: const SignatureWaiver(SignatureWaiverReason.noRecipient),
              savedAt: DateTime.now().toUtc(),
            ),
            liters: 9950,
          ),
    );
    await pumpUntil(
      tester,
      () =>
          c.read(driverOpsProvider)[id]?.deliver?.status ==
          OutboxStatus.needsAttention,
    );
    await tester.pumpWidget(
      driverTestApp(container: c, initialLocation: '/driver/shipments/$id'),
    );
    await pumpUntil(tester, () => c.read(driverShipmentProvider(id)).hasValue);
    await pumpFor(tester, const Duration(milliseconds: 700));
    expect(find.text(DriverCopy.deliverFailedTitle), findsOneWidget);
    expect(
      find.text(
        'İmza alınamadığında en az bir teslim fotoğrafı ve teslim konumu gerekir.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text(DriverCopy.opFix));
    await pumpUntil(
      tester,
      () => find.byType(DeliverFlowPage).evaluate().isNotEmpty,
    );
    await pumpFor(tester, const Duration(milliseconds: 900));
    expect(find.text(DriverCopy.stepSummary), findsOneWidget);
    expect(find.text('IRS-77'), findsOneWidget);
    expect(find.textContaining('Konum alındı'), findsOneWidget);
    tester.semantics.tap(find.semantics.byLabel(DriverCopy.slideDeliver));
    await pumpUntil(
      tester,
      () => c.read(driverOpsProvider)[id]?.deliver?.status == OutboxStatus.done,
    );
    await pumpFor(tester, const Duration(milliseconds: 900));
    expect(find.text(DriverCopy.deliverSentTitle), findsOneWidget);
    expect(await real(tester, () => h.outbox.get(rejected.id)), isNull);
    expect(shipment()['status'], 2);
    expect(shipment()['signatureWaiverLabel'], 'Alıcı yok / tanka teslim');
    handle.dispose();
    await finish(tester);
  });

  testWidgets('yalnızca yaklaşık konum: "Hassas konum kapalı" + ayarlar', (
    tester,
  ) async {
    await boot(
      tester,
      before: (h) {
        h.location.approximate = true;
        h.location.accuracy = 1200;
      },
      seedDraft: summaryDraft,
    );
    expect(find.text(DriverCopy.locationApproximate), findsOneWidget);
    await tester.tap(find.text(DriverCopy.locationOpenSettings));
    await tester.pump();
    expect(h.location.settingsOpened, 1);
    await finish(tester);
  });

  testWidgets('kamera izni reddedildi: uyarı + "Ayarları aç"', (tester) async {
    await boot(
      tester,
      before: (h) => h.camera.next = CaptureStatus.denied,
      seedDraft: (sid) => DeliverDraft(
        shipmentId: sid,
        code: DriverShipmentRow.shipmentCode(sid),
        step: DeliverStep.photos,
        litersText: '100',
        documentNo: 'IRS-1',
        savedAt: DateTime.now().toUtc(),
      ),
    );
    await tester.tap(find.text(DriverCopy.photoTake));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text(DriverCopy.cameraDenied), findsOneWidget);
    await finish(tester);
  });

  testWidgets('çıkarken: "Taslak olarak sakla" taslağı korur', (tester) async {
    await boot(tester);
    await tester.tap(key('5'));
    await tester.pump();
    await tester.tap(find.byTooltip(DriverCopy.close));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text(DriverCopy.leaveTitle), findsOneWidget);
    await tester.tap(find.text(DriverCopy.leaveKeep));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.byType(DeliverFlowPage), findsNothing);
    final d = DeliverDraftStore(
      PrefsStore(h.prefs),
      h.files,
    ).get('u-sofor', id);
    expect(d?.litersText, '5');
    await finish(tester);
  });

  for (final b in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'erişilebilirlik: litre ve özet, ${b.name}, ${scale}x, 360×640',
        (tester) async {
          final handle = tester.ensureSemantics();
          await boot(
            tester,
            brightness: b,
            textScale: scale,
            size: const Size(360, 640),
          );
          expect(tester.takeException(), isNull);
          await expectA11y(tester);
          await finish(tester);

          await boot(
            tester,
            brightness: b,
            textScale: scale,
            size: const Size(360, 640),
            seedDraft: summaryDraft,
          );
          expect(find.text(DriverCopy.headSummary), findsOneWidget);
          expect(tester.takeException(), isNull);
          await expectA11y(tester);
          await tester.drag(find.byType(ListView).last, const Offset(0, -500));
          await pumpFor(tester, const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          await expectA11y(tester);
          handle.dispose();
          await finish(tester);
        },
      );
    }
  }
}
