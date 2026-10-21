import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/customer_more/data/customer_more_repository.dart';
import 'package:akaryakitnet/features/customer_more/presentation/finance_info/finance_info_page.dart';
import 'package:akaryakitnet/features/customer_more/presentation/requests/requests_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cm_test_utils.dart';

void main() {
  group('Finans bilgisi', () {
    test('{links, orders} okunur', () async {
      final env = await CmEnv.create();
      addTearDown(env.dispose);
      // Finansın ek bilgi istediği bir sipariş.
      final o = env.world.orders.firstWhere((x) => x['customerId'] == 101);
      o['financeStatus'] = 4;
      final info = await env.container
          .read(customerMoreRepositoryProvider)
          .financeInfo();
      expect(info.links, hasLength(2));
      expect(info.links.where((l) => l.needsReply), hasLength(1));
      expect(info.orders.single.orderNumber, o['orderNumber']);
    });

    testWidgets(
      'bağlantılar ve siparişler; "Yanıtla" istenen türle onay ayrıntısını açar',
      (tester) async {
        final env = (await tester.runAsync(CmEnv.create))!;
        addTearDown(env.dispose);
        final o = env.world.orders.firstWhere((x) => x['customerId'] == 101);
        o['financeStatus'] = 4;
        await pumpCmApp(tester, env, location: '/finance-info');
        await pumpFor(tester, const Duration(seconds: 1));

        expect(find.text('Demir Petrol Akaryakıt Ltd. Şti.'), findsWidgets);
        expect(find.text('Sipariş verebilirsiniz'), findsOneWidget);
        expect(find.text('Kuzey Enerji A.Ş.'), findsOneWidget);
        expect(find.text('Ek bilgi istendi'), findsWidgets);
        expect(find.text('İstenen belge: Vergi levhası'), findsOneWidget);
        expect(
          find.textContaining('Siparişler için istenen bilgiler'),
          findsOneWidget,
        );
        expect(find.text(o['orderNumber'] as String), findsOneWidget);

        await tester.tap(find.widgetWithText(AknButton, 'Yanıtla').first);
        await pumpFor(tester, const Duration(milliseconds: 600));
        // Yer tutucu onay sayfası açılan adresi gösterir ("stub /approvals/…").
        final stub = tester.widget<Text>(
          find.textContaining('stub /approvals/'),
        );
        final uri = Uri.parse(stub.data!.substring('stub '.length));
        expect(uri.path, startsWith('/approvals/'));
        expect(uri.queryParameters['reply'], '1');
        expect(uri.queryParameters['kind'], '10');
        await finish(tester);
      },
    );

    test('yanıt rotası', () {
      expect(financeReplyRoute(9, null), '/approvals/9?reply=1');
    });
  });

  group('Talepler', () {
    testWidgets('liste: dört talep, durum ve sonuç özeti', (tester) async {
      final env = (await tester.runAsync(CmEnv.create))!;
      addTearDown(env.dispose);
      await pumpCmApp(tester, env, location: '/company/requests');
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.byType(RequestCard), findsNWidgets(4));
      expect(find.text('Talep #2987'), findsOneWidget);
      expect(find.textContaining('1 sipariş oluştu'), findsOneWidget);
      expect(find.textContaining('Gerekçe:'), findsOneWidget);
      await finish(tester);
    });

    testWidgets(
      'ayrıntı: satır başına sonuç ve ödeme belgesi durumu; görsel yüklenir',
      (tester) async {
        final env = (await tester.runAsync(CmEnv.create))!;
        addTearDown(env.dispose);
        await pumpCmApp(tester, env, location: '/company/requests/2987');
        await pumpFor(tester, const Duration(seconds: 1));

        final cheque = env.world.orders.firstWhere(
          (o) => o['paymentMethodCode'] == 'CEK' && o['customerId'] == 101,
        );
        expect(
          find.text('Sipariş ${cheque['orderNumber']} oluştu'),
          findsOneWidget,
        );
        expect(find.textContaining('Oluşturulamadı:'), findsOneWidget);
        expect(
          find.text('Başarısız satırları yeni siparişe aktar'),
          findsOneWidget,
        );

        await scrollTo(tester, find.text('Ödeme belgesi'));
        expect(find.text('Bekleniyor'), findsOneWidget);
        await scrollTo(tester, find.text('Görsel yükle'));
        await tester.tap(find.text('Görsel yükle'));
        await pumpFor(tester, const Duration(milliseconds: 600));
        await tester.tap(find.text('Galeriden seç'));
        await pumpFor(tester, const Duration(seconds: 1));
        expect(find.text('Yüklendi'), findsOneWidget);
        final upload = env.requests.lastWhere(
          (r) => r.method == 'POST' && r.path == 'attachments',
        );
        expect(upload.idempotencyKey, isNotNull);
        await finish(tester);
      },
    );

    testWidgets('Talep eden bekleyen talebini geri çeker (onaylı)', (
      tester,
    ) async {
      final env = (await tester.runAsync(
        () => CmEnv.create(persona: 'talep'),
      ))!;
      addTearDown(env.dispose);
      await pumpCmApp(tester, env, location: '/company/requests/3001');
      await pumpFor(tester, const Duration(seconds: 1));
      await tester.tap(find.text('Talebi geri çek'));
      await pumpFor(tester, const Duration(milliseconds: 600));
      await tester.tap(find.widgetWithText(AknButton, 'Geri çek'));
      await pumpFor(tester, const Duration(seconds: 1));
      final r = env.world
          .bag<List<Map<String, dynamic>>>('company.orderRequests', () => [])
          .firstWhere((x) => x['id'] == 3001);
      expect(r['status'], 3);
      expect(find.text('Talep iptal edildi.'), findsOneWidget);
      await finish(tester);
    });
  });
}
