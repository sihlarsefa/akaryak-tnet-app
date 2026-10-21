// QA logistics-field: şoför akışı gerçek uygulamada (360×640). Bugün → "Teslim et" → litre → irsaliye →
// teslim alan → fotoğraf → imza (çizerek / alınamadı) → özet → kaydır → sonuç → listeye dön; sonra
// sıradaki planlı durakta "Yola çık" → kaydır → yolda. Çevrimdışı: teslim telefona kaydedilir, bağlantı
// gelince tek kez gönderilir (yinelenen işlem yok).
import 'package:akaryakitnet/core/media/signature_pad.dart';
import 'package:akaryakitnet/core/offline/outbox_op.dart';
import 'package:akaryakitnet/core/offline/outbox_providers.dart';
import 'package:akaryakitnet/features/driver/application/driver_ops.dart';
import 'package:akaryakitnet/features/driver/copy.dart';
import 'package:akaryakitnet/features/driver/presentation/deliver_flow_page.dart';
import 'package:akaryakitnet/features/driver/presentation/widgets/litre_keypad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_kit.dart';

Finder _key(String k) => find.descendant(
  of: find.byType(LitreKeypad),
  matching: find.bySemanticsLabel(k),
);

Future<void> _next(WidgetTester tester) async {
  await reveal(tester, find.text(DriverCopy.next));
  await tester.tap(find.text(DriverCopy.next).last);
  await steps(tester, const Duration(milliseconds: 500));
}

/// Teslim sihirbazını litreden özete kadar doldurur.
Future<void> _fillWizard(
  WidgetTester tester, {
  required String liters,
  required String doc,
  bool drawSignature = false,
}) async {
  expect(find.byType(DeliverFlowPage), findsOneWidget);
  noErrors(tester, 'sihirbaz açıldı');
  for (final k in liters.split('')) {
    await tester.ensureVisible(_key(k));
    await tester.pump();
    await tester.tap(_key(k));
    await tester.pump();
  }
  await _next(tester);
  noErrors(tester, 'litre');
  expect(find.text(DriverCopy.stepDocument), findsWidgets);
  await tester.enterText(find.byType(TextField).last, doc);
  await tester.pump();
  await _next(tester);
  noErrors(tester, 'irsaliye');
  final contact = find.textContaining(DriverCopy.recipientUseContact);
  if (contact.evaluate().isNotEmpty) {
    await tester.tap(contact.first);
    await tester.pump();
  } else {
    await tester.enterText(find.byType(TextField).last, 'Murat Kaya');
    await tester.pump();
  }
  await _next(tester);
  noErrors(tester, 'teslim alan');
  await scrollTap(tester, find.text(DriverCopy.photoTake));
  await steps(tester, const Duration(milliseconds: 300));
  expect(find.text(DriverCopy.photoCount(1)), findsOneWidget);
  await _next(tester);
  noErrors(tester, 'fotoğraf');
  if (drawSignature) {
    final pad = find.byType(SignaturePad);
    await reveal(tester, pad);
    final center = tester.getCenter(pad);
    final g = await tester.startGesture(center - const Offset(60, 10));
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(10, 3));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await steps(tester, const Duration(milliseconds: 400));
  } else {
    await scrollTap(tester, find.text(DriverCopy.signatureCantGet));
    await tester.tap(find.bySemanticsLabel(RegExp('^İmzadan imtina')));
    await tester.pump();
    await scrollTap(tester, find.text(DriverCopy.waiverConfirm));
    expect(find.text(DriverCopy.signatureWaived), findsWidgets);
  }
  await _next(tester);
  // İmza PNG'si gerçek G/Ç ile yazılır (sahte zamanda beklemez).
  await until(
    tester,
    () => find.bySemanticsLabel(DriverCopy.slideDeliver).evaluate().isNotEmpty,
  );
  await steps(tester, const Duration(milliseconds: 400));
  noErrors(tester, 'imza');
  // ignore: avoid_print
  print('QA summary step: ${visibleTexts(tester).join(' | ')}');
  expect(find.bySemanticsLabel(DriverCopy.slideDeliver), findsOneWidget);
}

void main() {
  testWidgets(
    '[QA LF-1] sofor 360×640: litre tuş takımı kaydırmadan tümüyle görünür '
    '(alt raf üstünde)',
    (tester) async {
      final app = await QaApp.start(tester, persona: 'sofor');
      await scrollTap(tester, find.text(DriverCopy.actionDeliver).last);
      await steps(tester, const Duration(milliseconds: 600));
      expect(find.byType(LitreKeypad), findsOneWidget);
      final next = tester.getRect(find.text(DriverCopy.next).last);
      final rects = {
        for (final k in ['1', '4', '7', '0']) k: tester.getRect(_key(k)),
      };
      // ignore: avoid_print
      print('QA keypad rects: $rects next=$next');
      for (final e in rects.entries) {
        expect(
          e.value.bottom,
          lessThanOrEqualTo(next.top),
          reason:
              'tuş "${e.key}" alt rafın altında / ekran dışında: ${e.value} '
              '(İleri düğmesi $next)',
        );
      }
      await app.close(tester);
      // QA LF-1 düzeltildi: tuş takımı alt rafın üstüne sabit.
    },
  );

  testWidgets('sofor 360×640 çevrimiçi: Teslim et → kanıtlar → kaydır → '
      'kaydedildi → listeye dön → sıradaki durakta Yola çık', (tester) async {
    final handle = tester.ensureSemantics();
    final app = await QaApp.start(tester, persona: 'sofor');
    noErrors(tester, 'şoför ana');
    noErrorState('şoför ana');
    final inTransit = app.world.shipments.firstWhere(
      (s) => s['status'] == 1 && s['driverUserId'] == 'u-sofor',
    );
    final id = inTransit['id'] as int;
    final planned = (inTransit['plannedLiters'] as num).toInt();
    expect(find.text(DriverCopy.actionDeliver), findsWidgets);
    await scrollTap(tester, find.text(DriverCopy.actionDeliver).last);
    await steps(tester, const Duration(milliseconds: 600));
    final liters = (planned - 50).toString();
    await _fillWizard(tester, liters: liters, doc: 'irs-qa-1');
    tester.semantics.tap(find.semantics.byLabel(DriverCopy.slideDeliver));
    OutboxOp? op() => app.container.read(driverOpsProvider)[id]?.deliver;
    await until(tester, () => op()?.status == OutboxStatus.done);
    await steps(tester, const Duration(seconds: 1));
    expect(op()?.status, OutboxStatus.done, reason: op()?.lastError);
    expect(find.text(DriverCopy.deliverSentTitle), findsOneWidget);
    noErrors(tester, 'teslim sonucu');
    final s = app.world.shipments.firstWhere((s) => s['id'] == id);
    expect(s['status'], 2);
    expect(s['deliveredLiters'], planned - 50);
    // Bayi "Teslim bildir" irsaliyeyi büyük harfe çevirir (report_sheet.dart:68); şoför akışı da
    // aynı biçimde göndermeli (QA LF-2).
    expect((s['deliveryDocumentNo'] as String).toUpperCase(), 'IRS-QA-1');

    await scrollTap(tester, find.text(DriverCopy.backToList));
    await steps(tester, const Duration(seconds: 1));
    await io(tester);
    noErrors(tester, 'listeye dönüldü');
    expect(find.byType(DeliverFlowPage), findsNothing);

    // Sıradaki planlı durak: Yola çık → ayrıntı → kaydır.
    final next = app.world.shipments.where(
      (s) => s['status'] == 0 && s['driverUserId'] == 'u-sofor',
    );
    if (next.isNotEmpty &&
        find.text(DriverCopy.actionStart).evaluate().isNotEmpty) {
      final nid = next.first['id'] as int;
      await scrollTap(tester, find.text(DriverCopy.actionStart).last);
      await steps(tester, const Duration(milliseconds: 800));
      await io(tester);
      noErrors(tester, 'ayrıntı');
      tester.semantics.tap(find.semantics.byLabel(DriverCopy.slideStart));
      await steps(tester, const Duration(milliseconds: 300));
      final confirm = find.text(DriverCopy.confirmStart);
      if (confirm.evaluate().length > 1) {
        await tester.tap(confirm.last);
      }
      OutboxOp? st() => app.container.read(driverOpsProvider)[nid]?.start;
      await until(tester, () => st()?.status == OutboxStatus.done);
      await steps(tester, const Duration(seconds: 1));
      noErrors(tester, 'yola çıkıldı');
      expect(
        app.world.shipments.firstWhere((s) => s['id'] == nid)['status'],
        1,
        reason: 'yola çıkış kaydedildi (${st()?.lastError})',
      );
    }
    handle.dispose();
    await app.close(tester);
  });

  testWidgets('sofor 360×640 çevrimdışı: teslim telefona kaydedilir; bağlantı '
      'gelince bir kez gönderilir', (tester) async {
    final handle = tester.ensureSemantics();
    final app = await QaApp.start(tester, persona: 'sofor');
    final inTransit = app.world.shipments.firstWhere(
      (s) => s['status'] == 1 && s['driverUserId'] == 'u-sofor',
    );
    final id = inTransit['id'] as int;
    final planned = (inTransit['plannedLiters'] as num).toInt();
    await scrollTap(tester, find.text(DriverCopy.actionDeliver).last);
    await steps(tester, const Duration(milliseconds: 600));
    await _fillWizard(
      tester,
      liters: planned.toString(),
      doc: 'irs-off-1',
      drawSignature: true,
    );
    app.online = false;
    await steps(tester, const Duration(milliseconds: 300));
    tester.semantics.tap(find.semantics.byLabel(DriverCopy.slideDeliver));
    OutboxOp? op() => app.container.read(driverOpsProvider)[id]?.deliver;
    await until(tester, () => op() != null);
    await steps(tester, const Duration(milliseconds: 800));
    expect(find.text(DriverCopy.queuedDeliverTitle), findsOneWidget);
    expect(op()?.status.isWaiting, isTrue);
    expect(app.world.shipments.firstWhere((s) => s['id'] == id)['status'], 1);
    noErrors(tester, 'çevrimdışı sonuç');

    await scrollTap(tester, find.text(DriverCopy.backToList));
    await steps(tester, const Duration(seconds: 1));
    noErrors(tester, 'çevrimdışı liste');

    app.online = true;
    await until(tester, () => op()?.status == OutboxStatus.done);
    await steps(tester, const Duration(seconds: 1));
    await io(tester);
    expect(op()?.status, OutboxStatus.done, reason: op()?.lastError);
    final s = app.world.shipments.firstWhere((s) => s['id'] == id);
    expect(s['status'], 2);
    expect((s['deliveryDocumentNo'] as String).toUpperCase(), 'IRS-OFF-1');
    final all = app.container.read(outboxOpsProvider).valueOrNull ?? [];
    final mine = all.where(
      (o) => o.type.contains('deliver') && '${o.payload}'.contains('$id'),
    );
    expect(mine.where((o) => o.status.isWaiting).length, 0, reason: '$mine');
    expect(
      mine.where((o) => o.status == OutboxStatus.done).length,
      lessThanOrEqualTo(1),
      reason: 'yinelenen teslim işlemi: $mine',
    );
    noErrors(tester, 'gönderildi');
    handle.dispose();
    await app.close(tester);
  });

  testWidgets(
    '[QA LF-2] sofor: irsaliye no küçük harfle yazılsa da büyük harfle '
    'gönderilir (bayi "Teslim bildir" gibi)',
    (tester) async {
      final handle = tester.ensureSemantics();
      final app = await QaApp.start(tester, persona: 'sofor');
      final inTransit = app.world.shipments.firstWhere(
        (s) => s['status'] == 1 && s['driverUserId'] == 'u-sofor',
      );
      final id = inTransit['id'] as int;
      final planned = (inTransit['plannedLiters'] as num).toInt();
      await scrollTap(tester, find.text(DriverCopy.actionDeliver).last);
      await steps(tester, const Duration(milliseconds: 600));
      await _fillWizard(tester, liters: planned.toString(), doc: 'irs-low-9');
      tester.semantics.tap(find.semantics.byLabel(DriverCopy.slideDeliver));
      await until(
        tester,
        () =>
            app.world.shipments.firstWhere((s) => s['id'] == id)['status'] == 2,
      );
      await steps(tester, const Duration(seconds: 1));
      expect(
        app.world.shipments.firstWhere(
          (s) => s['id'] == id,
        )['deliveryDocumentNo'],
        'IRS-LOW-9',
      );
      handle.dispose();
      await app.close(tester);
      // QA LF-2 düzeltildi: irsaliye no büyük harfle gönderilir.
    },
  );
}
