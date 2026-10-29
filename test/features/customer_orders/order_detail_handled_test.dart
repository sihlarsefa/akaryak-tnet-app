// Sipariş ayrıntısı, v4 round 2:
// - B12 (§3.5.3): sayfa bir bildirimden (`?focus=quote|documents`) açıldı ama teklif kararı artık
//   verilmiş (başka bir yönetici ya da kendiniz). Sayfa ne olduğunu ve ne zaman olduğunu tek sakin
//   bantta söyler; "Sıradaki işiniz" görev kutusunun ilk işini açar. Karar açıksa ya da sayfa
//   bildirimden açılmadıysa bant yok.
// - A10: karar plakasındaki "Son alımlarınızla kıyas" tek çizgi ve tek cümledir: "+0,60 ₺", "bu teklif
//   42,35" ve "ort." etiketleri yok (rakam bir kez söylenir).
// - B16 (05): StageNow'un son saati teklifin saatiyle karışmasın: "karar için son: bugün 08:26".
import 'package:akaryakitnet/app/tasks/task_inbox.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/a2_support.dart';

void main() {
  late A2Env env;
  late int o2; // karar bekleyen, çek, görsel eksik
  late int o3; // onaylı, yolda

  setUp(() async {
    env = await A2Env.create();
    final w = env.world;
    o2 = w.orders.firstWhere((o) => o['status'] == 2)['id'] as int;
    o3 =
        w.orders.firstWhere(
              (o) => o['status'] == 3 && o['customerId'] == 101,
            )['id']
            as int;
  });

  Future<(ProviderContainer, GoRouter)> openAt(
    WidgetTester tester,
    String location,
  ) async {
    final c = (await tester.runAsync(() => env.signedIn('musteri')))!;
    addTearDown(c.dispose);
    final router = await pumpA2(tester, c, initialLocation: location);
    await pumpUntil(tester, find.byType(AknFlowLine));
    await pumpReal(tester);
    return (c, router);
  }

  Finder handledBanner(String text) => find.descendant(
    of: find.byType(AknBanner),
    matching: find.textContaining(text),
  );

  group('B12 kararı verilmiş teklif (bildirimden açılış)', () {
    testWidgets(
      '?focus=quote, onaylı sipariş: "Bu teklif onaylandı · zaman" ve "Sıradaki işiniz" ilk işi açar',
      (tester) async {
        final (c, router) = await openAt(tester, '/orders/$o3?focus=quote');
        expect(find.byType(AknBanner), findsOneWidget);
        expect(handledBanner('Bu teklif onaylandı · '), findsOneWidget);
        // Sıradaki iş: sayılan ilk görev, bu siparişin değil.
        final next = c
            .read(taskInboxProvider)
            .items
            .firstWhere((t) => t.counts && t.orderId != o3);
        final link = find.widgetWithText(AknButton, nextTaskLabel);
        expect(link, findsOneWidget);
        // `?focus=` kaydırması (AknFocusFlash) bitsin; sonra bağlantı ekranın ortasına gelir.
        await tester.pump(const Duration(seconds: 2));
        await Scrollable.ensureVisible(tester.element(link), alignment: 0.5);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(link);
        await pumpReal(tester, rounds: 10);
        expect(router.state.uri.toString(), next.location);
        await tearDownUi(tester);
      },
    );

    testWidgets('?focus=documents, onaylı ve belge beklenmiyor: aynı bant', (
      tester,
    ) async {
      await openAt(tester, '/orders/$o3?focus=documents');
      expect(handledBanner('Bu teklif onaylandı'), findsOneWidget);
      await tearDownUi(tester);
    });

    testWidgets('?focus=quote, reddedilen sipariş: "Bu teklif reddedildi"', (
      tester,
    ) async {
      final rejected = env.world.orders.firstWhere(
        (o) => o['customerId'] == 101 && o['status'] == 3,
      );
      rejected['status'] = 4;
      await openAt(tester, '/orders/${rejected['id']}?focus=quote');
      expect(handledBanner('Bu teklif reddedildi'), findsOneWidget);
      await tearDownUi(tester);
    });

    testWidgets('bildirimden açılmadıysa bant yok', (tester) async {
      await openAt(tester, '/orders/$o3');
      expect(find.byType(AknBanner), findsNothing);
      await tearDownUi(tester);
    });

    testWidgets('karar hâlâ açıksa bant yok; karar çubuğu yerinde', (
      tester,
    ) async {
      await openAt(tester, '/orders/$o2?focus=quote');
      expect(find.byType(AknBanner), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ActionBar),
          matching: find.widgetWithText(AknButton, 'Çek görselini yükle'),
        ),
        findsOneWidget,
      );
      await tearDownUi(tester);
    });
  });

  testWidgets(
    'A10 kıyas: tek çizgi ve tek cümle; "+0,60 ₺", "bu teklif" ve "ort." yok',
    (tester) async {
      await openAt(tester, '/orders/$o2');
      final plate = find.byType(AknPlate);
      expect(
        find.descendant(
          of: plate,
          matching: find.text('Son alımlarınızla kıyas'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: plate,
          matching: find.textContaining(
            RegExp(r'^Son (iki|üç) alımınızın ortalama'),
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('ort.'), findsNothing);
      expect(find.textContaining('bu teklif'), findsNothing);
      expect(find.textContaining('litre başına'), findsNothing);
      expect(find.textContaining(RegExp(r'^[+−]\d')), findsNothing);
      // Ekran okuyucu çizgideki ortalamayı da duyar.
      expect(
        find.bySemanticsLabel(RegExp(r'alımınızın ortalaması \d')),
        findsOneWidget,
      );
      await tearDownUi(tester);
    },
  );

  testWidgets('B16 (05) StageNow: "… teklif verdi · karar için son: …"', (
    tester,
  ) async {
    await openAt(tester, '/orders/$o2');
    expect(
      find.textContaining(
        RegExp(
          r'teklif verdi · karar için son: (bugün|yarın|\d+ \S+) \d\d:\d\d$',
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining("'e kadar"), findsNothing);
    expect(find.textContaining("'a kadar"), findsNothing);
    await tearDownUi(tester);
  });
}
