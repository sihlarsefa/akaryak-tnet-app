// Tahsilat (spec D.3 A5): yalnızca `allowedTransitions`, `noteRequiredFor` notu, "Dekont ekle" →
// `attachmentPublicId`, yetkisi olmayana durum değiştirme yok, çek / senet durumları, cari ve durum
// süzgeçleri → sorgu parametreleri; C.7 erişilebilirlik matrisi.
import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/features/approvals/api.dart';
import 'package:akaryakitnet/features/payments/presentation/payment_detail_page.dart';
import 'package:akaryakitnet/features/payments/presentation/widgets/payment_cards.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../approvals/a5_test_kit.dart';

Map<String, dynamic> lastPaymentsQuery(A5App app) {
  final r = app.log
      .all('GET', '/payments')
      .lastWhere((o) => o.uri.path.endsWith('/payments'));
  return r.queryParameters;
}

List<int> statusesOf(Map<String, dynamic> q) => [
  for (final v in (q['statuses'] as List? ?? const [])) int.parse('$v'),
];

Future<void> openStatusSheet(WidgetTester tester) async {
  await tapText(tester, 'Durumu değiştir');
  expect(find.text('Ödeme durumu'), findsOneWidget);
}

void main() {
  group('ödeme durumu', () {
    testWidgets('yalnızca izin verilen geçişler listelenir (çek, bekliyor)', (
      tester,
    ) async {
      await pumpA5(tester, persona: 'muhasebe', location: '/payments/12002');
      expect(find.byType(PaymentDetailPage), findsOneWidget);
      await openStatusSheet(tester);
      for (final s in [
        PaymentStatus.documentUploaded,
        PaymentStatus.collected,
        PaymentStatus.cancelled,
      ]) {
        expect(inSheet(find.text(s.label)), findsOneWidget, reason: s.label);
      }
      for (final s in [PaymentStatus.bounced, PaymentStatus.refunded]) {
        expect(inSheet(find.text(s.label)), findsNothing, reason: s.label);
      }
      await finish(tester);
    });

    testWidgets('İptal için gerekçe zorunlu; gerekçeyle kaydedilir', (
      tester,
    ) async {
      final app = await pumpA5(
        tester,
        persona: 'muhasebe',
        location: '/payments/12002',
      );
      await openStatusSheet(tester);
      await tapFinder(
        tester,
        inSheet(find.text(PaymentStatus.cancelled.label)),
      );
      await tapText(tester, 'Durumu kaydet');
      expect(
        find.text('"İptal" için gerekçe girin (en az 3 karakter).'),
        findsOneWidget,
      );
      expect(app.log.all('POST', '/status'), isEmpty);
      await typeInto(tester, 'Gerekçe', 'Müşteri siparişi iptal etti.');
      await tapText(tester, 'Durumu kaydet');
      final req = app.log.last('POST', 'payments/12002/status')!;
      final body = req.data as Map;
      expect(body['toStatus'], PaymentStatus.cancelled.code);
      expect(body['note'], 'Müşteri siparişi iptal etti.');
      expect(body['concurrencyToken'], isNotNull);
      expect(req.headers['Idempotency-Key'], isNotNull);
      expect(find.text('Ödeme durumu'), findsNothing);
      await finish(tester);
    });

    testWidgets(
      '"Dekont ekle" siparişe yükler; ödeme "Belge yüklendi" olur, kayıt tazelenir ve '
      '"Tahsil edildi" ilk denemede (409 olmadan) belgeyle kaydedilir',
      (tester) async {
        final app = await pumpA5(
          tester,
          persona: 'muhasebe',
          location: '/payments/12001',
        );
        final order = app.server.world.order(12001)!;
        expect(order['paymentStatus'], PaymentStatus.pending.code);
        await openStatusSheet(tester);
        await tapText(tester, 'Dekont ekle');
        await pumpFor(tester);
        expect(app.files.lastKind, AttachmentKind.transferReceipt);
        final upload = app.log.last('POST', 'attachments')!;
        final fields = {
          for (final f in (upload.data as FormData).fields) f.key: f.value,
        };
        expect(fields['ownerType'], '${AttachmentOwnerType.order.code}');
        expect(fields['ownerId'], '12001');
        expect(fields['kind'], '${AttachmentKind.transferReceipt.code}');
        final uploaded = app.server.world.attachments.last;
        // Sunucu (sahte de) bekleyen ödemeyi kendiliğinden "Belge yüklendi" yaptı; sayfa kaydı
        // yeniden okudu: "Belge yüklendi" artık seçenek değil, yeni sürüm belirteciyle kaydedilir.
        expect(order['paymentStatus'], PaymentStatus.documentUploaded.code);
        expect(
          inSheet(find.text(PaymentStatus.documentUploaded.label)),
          findsOneWidget,
          reason: 'yalnızca "Şu an" çipi',
        );
        await tapFinder(
          tester,
          inSheet(find.text(PaymentStatus.collected.label)),
        );
        await tapText(tester, 'Durumu kaydet');
        await pumpFor(tester);
        final posts = app.log.all('POST', 'payments/12001/status');
        expect(posts, hasLength(1), reason: 'ilk kayıt 409 almamalı');
        final body = posts.single.data as Map;
        expect(body['toStatus'], PaymentStatus.collected.code);
        expect(body['attachmentPublicId'], uploaded['publicId']);
        expect(order['paymentStatus'], PaymentStatus.collected.code);
        expect(
          find.text('Ödeme durumu'),
          findsNothing,
          reason: 'sayfa kapandı',
        );
        await finish(tester);
      },
    );

    testWidgets(
      'sayfa açıkken belge başka yerden yüklenirse eski sürümle kayıt bir kez yenisiyle denenir',
      (tester) async {
        final app = await pumpA5(
          tester,
          persona: 'muhasebe',
          location: '/payments/12001',
        );
        await openStatusSheet(tester);
        await tapFinder(
          tester,
          inSheet(find.text(PaymentStatus.collected.label)),
        );
        // Müşteri dekontu yükledi (sayfa eski sürümü tutuyor).
        final store = A5FakeStore.of(app.server.world);
        final dekont = {
          'publicId': 'harici-dekont',
          'ownerType': AttachmentOwnerType.order.code,
          'ownerId': 12001,
          'kind': AttachmentKind.transferReceipt.code,
        };
        store.onDocumentUploaded(dekont, null);
        await tapText(tester, 'Durumu kaydet');
        await pumpFor(tester);
        final posts = app.log.all('POST', 'payments/12001/status');
        expect(posts, hasLength(2), reason: '409 → yeni sürümle bir kez');
        expect(
          app.server.world.order(12001)!['paymentStatus'],
          PaymentStatus.collected.code,
        );
        expect(find.text('Ödeme durumu'), findsNothing);
        await finish(tester);
      },
    );

    testWidgets('yetkinliği olmayan (finans) durum değiştiremez', (
      tester,
    ) async {
      await pumpA5(tester, persona: 'finans', location: '/payments/12002');
      expect(find.byType(PaymentDetailPage), findsOneWidget);
      expect(find.text('Durumu değiştir'), findsNothing);
      await finish(tester);
    });
  });

  testWidgets('çek: yalnızca izin verilen durumlar; seçilen durum gönderilir', (
    tester,
  ) async {
    final app = await pumpA5(
      tester,
      persona: 'muhasebe',
      location: '/payments?tab=instruments',
    );
    final card = tester.widget<InstrumentRowCard>(
      find.byType(InstrumentRowCard).first,
    );
    final i = card.instrument;
    expect(i.allowedTransitions, isNotEmpty);
    await tester.tap(find.byType(InstrumentRowCard).first);
    await pumpFor(tester);
    expect(find.text('Durumu değiştir'), findsOneWidget);
    for (final s in InstrumentStatus.values) {
      if (s.isUnknown || s == i.status) continue;
      expect(
        inSheet(find.text(s.label)),
        i.allowedTransitions.contains(s) ? findsOneWidget : findsNothing,
        reason: s.label,
      );
    }
    final to = i.allowedTransitions.firstWhere(
      (s) => !i.noteRequiredFor.contains(s),
    );
    await tapFinder(tester, inSheet(find.text(to.label)));
    await tapText(tester, 'Durumu kaydet');
    final body =
        app.log.last('POST', 'payments/instruments/${i.id}/status')!.data
            as Map;
    expect(body['toStatus'], to.code);
    await finish(tester);
  });

  testWidgets('süzgeçler: durum, gecikenler ve cari sorguya gider', (
    tester,
  ) async {
    final app = await pumpA5(
      tester,
      persona: 'muhasebe',
      location: '/payments',
    );
    expect(statusesOf(lastPaymentsQuery(app)), [1, 2]);
    await tapText(tester, PaymentStatus.collected.label, first: true);
    expect(statusesOf(lastPaymentsQuery(app)), [1, 2, 3]);
    await tapText(tester, 'Gecikenler');
    expect('${lastPaymentsQuery(app)['overdue']}', 'true');
    await tapText(tester, 'Gecikenler');
    expect(lastPaymentsQuery(app)['overdue'], isNull);

    await tapText(tester, 'Cari: tümü');
    expect(find.text('Cari seçin'), findsOneWidget);
    expect(app.log.last('GET', 'bayi/customers'), isNotNull);
    await tapFinder(tester, inSheet(find.text('Anadolu Lojistik A.Ş.')));
    expect(find.text('Cari: Anadolu Lojistik A.Ş.'), findsOneWidget);
    final q = lastPaymentsQuery(app);
    expect(q['customerId'], isNotNull);
    expect(
      find
          .byType(PaymentRowCard)
          .evaluate()
          .every(
            (e) =>
                (e.widget as PaymentRowCard).row.customerId ==
                int.parse('${q['customerId']}'),
          ),
      isTrue,
    );
    await finish(tester);
  });

  group('C.7 Tahsilat', () {
    a11yMatrix('ödemeler', persona: 'muhasebe', location: '/payments');
    a11yMatrix(
      'çek / senet',
      persona: 'muhasebe',
      location: '/payments?tab=instruments',
    );
    a11yMatrix(
      'ödeme ayrıntısı',
      persona: 'muhasebe',
      location: '/payments/12002',
    );
  });
}
