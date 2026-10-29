// Tasarım v4 tur 2 (bayi): "sıra sizde" diyen her şey kararın verildiği yeri açar (B7), sayılar
// birbirini tutar (B6), en acil sipariş ilk satırdır (B6), teklif masasında boş alan boş görünür ve
// gönder düğmesinin nasıl açıldığı söylenir (B10), boş masa Siparişler'e götürür ve "Tüm işler" bir
// sayfadır (B18), sipariş ayrıntısında müşteri ve teslim günü bir kez yazılır (A18).
import 'dart:async';

import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/approvals/approvals_fake.dart';
import 'package:akaryakitnet/features/approvals/fake/a5_fake_store.dart';
import 'package:akaryakitnet/features/bayi/application/desk_controller.dart';
import 'package:akaryakitnet/features/bayi/application/orders_controller.dart';
import 'package:akaryakitnet/features/bayi/copy.dart';
import 'package:akaryakitnet/features/bayi/data/order_models.dart';
import 'package:akaryakitnet/features/bayi/fake/seed.dart';
import 'package:akaryakitnet/features/bayi/presentation/desk/desk_row_card.dart';
import 'package:akaryakitnet/features/bayi/presentation/home/order_pipeline.dart';
import 'package:akaryakitnet/features/bayi/presentation/home/tasks_page.dart';
import 'package:akaryakitnet/features/bayi/presentation/orders/orders_page.dart';
import 'package:akaryakitnet/features/bayi/presentation/widgets/bayi_widgets.dart'
    show openDestination;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/bayi_app.dart';

const _phone = Size(390, 844);

Finder _card(int id) =>
    find.byWidgetPredicate((w) => w is BayiOrderCard && w.row.id == id);

/// Bayi 1'in finans onayındaki siparişi (Onaylar'daki "Sipariş finansı" talebinin konusu).
int _financeHeld(FakeWorld w) {
  ensureBayiSeed(w);
  return w.orders.firstWhere(
        (o) => o['stationId'] == 1 && o['financeStatus'] == 1,
      )['id']
      as int;
}

/// Bayi 1'in açık teklif bekleyen siparişlerini teklif bekleyen dışına alır (boş masa).
void _emptyDesk(FakeWorld w) {
  ensureBayiSeed(w);
  for (final o in w.ordersOfStation(1)) {
    if (o['status'] == OrderStatus.awaitingQuote.code ||
        o['status'] == OrderStatus.revisionRequested.code) {
      o['status'] = OrderStatus.expired.code;
    }
  }
}

void main() {
  group('B7: finans durağı → karar', () {
    testWidgets(
      'sahip: finans onayındaki siparişte birincil "Finans kararını ver" talebi açar',
      (tester) async {
        late int id;
        final app = await BayiTestApp.start(
          tester,
          persona: 'sahip',
          location: '/bayi/orders',
          size: _phone,
          setup: (h) {
            registerApprovalsFakes(h.server);
            id = _financeHeld(h.world);
          },
        );
        await app.push(tester, '/bayi/orders/$id');
        // StageNow sıranın izleyende olduğunu söyler; satır içi bağlantı yok, birincil alt çubukta.
        expect(find.text(BayiCopy.financeYourMove), findsWidgets);
        expect(find.text('Onay talebini aç'), findsNothing);
        final decide = find.byKey(const ValueKey('order-finance-decide'));
        expect(decide, findsOneWidget);
        expect(find.text(BayiCopy.financeDecide), findsOneWidget);
        await scrollTap(tester, decide);
        expect(find.textContaining('stub:/approvals/'), findsOneWidget);
        await app.finish(tester);
      },
    );

    testWidgets(
      'sipariş masası (karar yetkisi yok): Pas yok, birincil yok, sakin "Onay talebini aç"',
      (tester) async {
        late int id;
        final app = await BayiTestApp.start(
          tester,
          persona: 'siparis',
          location: '/bayi/orders',
          size: _phone,
          setup: (h) {
            registerApprovalsFakes(h.server);
            id = _financeHeld(h.world);
          },
        );
        await app.push(tester, '/bayi/orders/$id');
        expect(find.text(BayiCopy.financeYourMove), findsNothing);
        expect(
          find.byKey(const ValueKey('order-finance-decide')),
          findsNothing,
        );
        expect(find.text('Onay talebini aç'), findsOneWidget);
        await app.finish(tester);
      },
    );

    testWidgets(
      'listede finans satırı izleyenin sırasıysa Pas cümle (Tümü) ya da fiil satırı (segment)',
      (tester) async {
        late int id;
        final app = await BayiTestApp.start(
          tester,
          persona: 'sahip',
          location: '/bayi/orders',
          setup: (h) {
            registerApprovalsFakes(h.server);
            id = _financeHeld(h.world);
          },
        );
        await reveal(tester, _card(id));
        final pips = tester.widget<AknFlowPips>(
          find.descendant(of: _card(id), matching: find.byType(AknFlowPips)),
        );
        expect(pips.sentence, BayiCopy.financeYourMove);
        expect(pips.flow.yourMove, isTrue);
        expect(pips.urgent, isTrue, reason: 'cümle Pas');
        // Finans onayında segmenti: akış satırı yok, fiil satırı Pas.
        app.container
            .read(bayiOrdersProvider.notifier)
            .setSegment(BayiOrderSegment.financeHeld);
        await BayiTestApp.settle(tester);
        final tile = tester.widget<AknListTile>(
          find.descendant(of: _card(id), matching: find.byType(AknListTile)),
        );
        expect(tile.next, BayiCopy.financeYourMove);
        await app.finish(tester);
      },
    );

    // Finans durağı (v4 tur 2, B5 + B7): "sıra sizde" yalnızca Bende'de sipariş finansı talebi
    // varken; durak sayısıyla aynı listeyi açar. Onaylar deposu önce tohumlanır (müşterinin yanıtını
    // bekleyen 9005 siparişi sayımlardan önce dünyada olsun).
    PipelineStop financeStop(WidgetTester tester) => tester
        .widget<OrderPipeline>(find.byType(OrderPipeline))
        .stops
        .firstWhere((s) => s.label == 'Finans');

    testWidgets(
      'sahip: tutulan siparişlerin hepsi kendi kararıysa Finans durağı Onaylar\'ı Sipariş '
      'finansına süzülü açar',
      (tester) async {
        final app = await BayiTestApp.start(
          tester,
          persona: 'sahip',
          location: '/home-bayi',
          setup: (h) {
            registerApprovalsFakes(h.server);
            A5FakeStore.of(h.world);
            // Müşteriden çek bekleyen sipariş (9005) finansta tutulmasın: kalan tek sipariş Bende'de.
            for (final o in h.world.orders) {
              if (o['financeApprovalRequestId'] == 9005) o['financeStatus'] = 0;
            }
          },
        );
        final stop = financeStop(tester);
        expect(stop.kind, PipelineStopKind.yourMove);
        expect(stop.count, 1);
        stop.onTap!();
        await BayiTestApp.settle(tester);
        expect(
          find.text('stub:/approvals?type=${ApprovalType.orderFinance.code}'),
          findsOneWidget,
        );
        await app.finish(tester);
      },
    );

    testWidgets(
      'sahip: biri müşterinin yanıtını bekliyorsa durak Pas kalır ama sayısıyla aynı listeyi '
      '(Finans onayında) açar',
      (tester) async {
        final app = await BayiTestApp.start(
          tester,
          persona: 'sahip',
          location: '/home-bayi',
          setup: (h) {
            registerApprovalsFakes(h.server);
            A5FakeStore.of(h.world);
          },
        );
        final stop = financeStop(tester);
        expect(stop.kind, PipelineStopKind.yourMove);
        expect(stop.count, 2, reason: 'Bende 1 + müşteriyi bekleyen 1');
        stop.onTap!();
        await BayiTestApp.settle(tester);
        expect(find.byType(BayiOrdersPage), findsOneWidget);
        expect(
          app.container.read(bayiOrdersProvider).filter.segment,
          BayiOrderSegment.financeHeld,
        );
        await app.finish(tester);
      },
    );

    testWidgets(
      'sahip: Bende\'de sipariş finansı talebi yoksa Finans durağı sakin (boncuk yok)',
      (tester) async {
        final app = await BayiTestApp.start(
          tester,
          persona: 'sahip',
          location: '/home-bayi',
          setup: (h) {
            registerApprovalsFakes(h.server);
            A5FakeStore.of(h.world);
            // Bekleyen sipariş finansı talebi başkası tarafından karara bağlanmış: sipariş tutulu
            // görünse de Bende'de iş yok.
            for (final a in h.world.approvals) {
              if (a['type'] == ApprovalType.orderFinance.code &&
                  a['status'] == ApprovalStatus.pending.code) {
                a['status'] = ApprovalStatus.approved.code;
              }
            }
          },
        );
        final stop = financeStop(tester);
        expect(stop.kind, PipelineStopKind.waiting);
        expect(stop.isYourMove, isFalse);
        await app.finish(tester);
      },
    );
  });

  group('B6: sayılar ve en acil sipariş', () {
    testWidgets(
      'durum satırı çiplerle aynı: "n sipariş teklifinizi bekliyor · m revize"; Tümü\'de en acil önce',
      (tester) async {
        final app = await BayiTestApp.start(
          tester,
          persona: 'sahip',
          location: '/bayi/orders',
          size: _phone,
        );
        final s = app.container.read(bayiOrdersProvider);
        final quotes = s.counts!.of(BayiOrderSegment.awaitingQuote);
        final revisions = s.counts!.of(BayiOrderSegment.revisionRequested);
        // Bandın tek satırı: çiplerdeki iki sayı da, sığan en uzun sözle (kesilmez).
        final line = AknPageBand.plainStatus(
          tester.widget<AppScaffold>(find.byType(AppScaffold).first).status,
        );
        expect(line, contains('$quotes '));
        expect(line, contains('bekliyor'));
        // Revize sığarsa yazılır ve sayısı çiple aynıdır (sığmazsa çip söyler).
        if (line.contains('revize')) {
          expect(line, contains('$revisions revize'));
        }
        expect(
          find.textContaining(line, findRichText: true),
          findsOneWidget,
          reason: 'satır olduğu gibi görünür',
        );
        // Tümü'de ilk satır, süresi 3 saat içinde dolacak tekliflerin en yakını.
        final rows = s.list.items;
        final now = DateTime.now().toUtc();
        final urgent =
            rows
                .where(
                  (r) =>
                      (r.status == OrderStatus.awaitingQuote ||
                          r.status == OrderStatus.revisionRequested) &&
                      !r.financeStatus.isAwaitingDecision &&
                      r.expiresAt != null &&
                      r.expiresAt!.isAfter(now) &&
                      r.expiresAt!.difference(now) <= const Duration(hours: 3),
                )
                .toList()
              ..sort((a, b) => a.expiresAt!.compareTo(b.expiresAt!));
        expect(urgent, isNotEmpty, reason: 'sahtede 41 dk kalan sipariş var');
        final first = tester.widget<BayiOrderCard>(
          find.byType(BayiOrderCard).first,
        );
        expect(first.row.id, urgent.first.id);
        await app.finish(tester);
      },
    );

    testWidgets(
      'geniş bantta iki sayı da: "n sipariş teklifinizi bekliyor · m revize"',
      (tester) async {
        final app = await BayiTestApp.start(
          tester,
          persona: 'sahip',
          location: '/bayi/orders',
          size: const Size(1400, 900),
        );
        final counts = app.container.read(bayiOrdersProvider).counts!;
        final quotes = counts.of(BayiOrderSegment.awaitingQuote);
        final revisions = counts.of(BayiOrderSegment.revisionRequested);
        expect(revisions, greaterThan(0), reason: 'sahtede revize istenen var');
        final line = AknPageBand.plainStatus(
          tester.widget<AppScaffold>(find.byType(AppScaffold).first).status,
        );
        expect(
          line,
          '$quotes sipariş teklifinizi bekliyor · $revisions revize',
        );
        await app.finish(tester);
      },
    );

    testWidgets(
      'Teklif bekleyen süre sonuna göre sıralanır; bu Filtre rozetine sayılmaz',
      (tester) async {
        final app = await BayiTestApp.start(
          tester,
          persona: 'sahip',
          location: '/bayi/orders?segment=awaitingQuote',
        );
        final f = app.container.read(bayiOrdersProvider).filter;
        expect(f.segment, BayiOrderSegment.awaitingQuote);
        expect(f.effectiveSort, BayiOrderSort.expiry);
        expect(f.advancedCount, 0);
        expect(f.toQuery(page: 1, pageSize: 25)['sort'], 'expiry');
        final rows = app.container.read(bayiOrdersProvider).list.items;
        for (var i = 1; i < rows.length; i++) {
          final a = rows[i - 1].expiresAt;
          final b = rows[i].expiresAt;
          if (a != null && b != null) {
            expect(a.isAfter(b), isFalse, reason: 'süre sonu artan');
          }
        }
        // Kullanıcının seçtiği "En yeni" segmentin doğalından farklı: sayılır.
        expect(f.copyWith(sort: BayiOrderSort.created).advancedCount, 1);
        expect(
          const BayiOrdersFilter().toQuery(page: 1, pageSize: 25)['sort'],
          isNull,
          reason: 'Tümü sunucunun sırası (en yeni)',
        );
        await app.finish(tester);
      },
    );

    test(
      'pinUrgent: yalnızca 3 saat içinde dolacak teklifler öne, en yakını önce',
      () {
        final now = DateTime.utc(2026, 10, 29, 12);
        BayiOrderRow row(int id, OrderStatus s, Duration? left) => BayiOrderRow(
          id: id,
          orderNumber: 'SIP-$id',
          status: s,
          expiresAt: left == null ? null : now.add(left),
        );
        final rows = [
          row(1, OrderStatus.approved, null),
          row(2, OrderStatus.awaitingQuote, const Duration(hours: 22)),
          row(3, OrderStatus.awaitingQuote, const Duration(minutes: 41)),
          row(4, OrderStatus.revisionRequested, const Duration(hours: 2)),
          row(5, OrderStatus.awaitingApproval, const Duration(minutes: 10)),
        ];
        expect(pinUrgent(rows, now: now).map((r) => r.id), [3, 4, 1, 2, 5]);
        expect(pinUrgent([rows[0], rows[1]], now: now).map((r) => r.id), [
          1,
          2,
        ]);
      },
    );
  });

  group('B10 / B18: Teklifler', () {
    testWidgets(
      'boş fiyat alanı boş görünür: tutar yok, öneri hayalette; alt çubuk nasıl açıldığını söyler',
      (tester) async {
        final app = await BayiTestApp.start(
          tester,
          persona: 'siparis',
          location: '/quote-desk',
          size: _phone,
        );
        final s = app.container.read(quoteDeskProvider);
        final row = s.rows.firstWhere((r) => r.offeredUnitPrice != null);
        final card = find.byWidgetPredicate(
          (w) => w is DeskRowCard && w.row.orderId == row.orderId,
        );
        await reveal(tester, card);
        // Fiyat yazılmadan tutar yok; önerilen fiyat yalnızca hayalet düğmede.
        expect(
          find.descendant(of: card, matching: find.textContaining('≈')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text(
              'Öneri ${formatUnitPrice(row.offeredUnitPrice!)}',
            ),
          ),
          findsOneWidget,
        );
        expect(find.text(BayiCopy.deskStartHint), findsOneWidget);
        // Fiyat yazılınca tutar sayar, hayalet çekilir, not kalkar ve gönder düğmesi gelir.
        await tester.enterText(
          find.descendant(of: card, matching: find.byType(TextField)),
          '44,10',
        );
        await BayiTestApp.settle(tester);
        expect(
          find.descendant(of: card, matching: find.textContaining('≈')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.textContaining('Öneri ')),
          findsNothing,
        );
        expect(find.text(BayiCopy.deskStartHint), findsNothing);
        expect(find.byKey(const ValueKey('desk-send')), findsOneWidget);
        await app.finish(tester);
      },
    );

    testWidgets(
      'revize satırında önceki teklif öneri değildir: hayalet yok, "Önerilen fiyatları yaz" yazmaz',
      (tester) async {
        final app = await BayiTestApp.start(
          tester,
          persona: 'siparis',
          location: '/quote-desk',
          size: _phone,
        );
        var s = app.container.read(quoteDeskProvider);
        final revision = s.rows.firstWhere(
          (r) => r.isRevision && r.suggestedSource == 'prev',
        );
        expect(revision.suggestedUnitPrice, isNotNull);
        expect(revision.offeredUnitPrice, isNull);
        final card = find.byWidgetPredicate(
          (w) => w is DeskRowCard && w.row.orderId == revision.orderId,
        );
        await reveal(tester, card);
        expect(
          find.descendant(of: card, matching: find.textContaining('Öneri ')),
          findsNothing,
        );
        app.container.read(quoteDeskProvider.notifier).applySuggestions();
        await BayiTestApp.settle(tester);
        s = app.container.read(quoteDeskProvider);
        expect(s.selected, isNot(contains(revision.orderId)));
        expect(s.draftOf(revision.orderId).price, isNull);
        await app.finish(tester);
      },
    );

    testWidgets('boş Teklifler: "Siparişlere git" Siparişler\'i açar', (
      tester,
    ) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'sahip',
        location: '/quote-desk',
        setup: (h) => _emptyDesk(h.world),
      );
      expect(find.text('Teklif verilecek sipariş yok'), findsOneWidget);
      await scrollTap(tester, find.text('Siparişlere git'));
      expect(find.byType(BayiOrdersPage), findsOneWidget);
      await app.finish(tester);
    });
  });

  group('B18: Tüm işler sayfası', () {
    for (final persona in const ['sahip', 'finans', 'depo']) {
      testWidgets('$persona: /bayi/tasks açılır, çökmez', (tester) async {
        final app = await BayiTestApp.start(
          tester,
          persona: persona,
          location: '/bayi/tasks',
        );
        expect(find.byType(BayiTasksPage), findsOneWidget);
        expect(find.text('Tüm işler'), findsWidgets);
        expect(
          find.byType(AknTaskRow).evaluate().isNotEmpty ||
              find.text('Bekleyen işiniz yok').evaluate().isNotEmpty,
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await app.finish(tester);
      });
    }
  });

  testWidgets(
    'A18: ayrıntıda müşteri ve teslim günü bir kez; StageNow "Teklifinizi bekliyor · … kadar"',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'sahip',
        location: '/bayi/orders?segment=awaitingQuote',
        size: _phone,
      );
      final row = app.container.read(bayiOrdersProvider).list.items.first;
      await app.push(tester, '/bayi/orders/${row.id}');
      expect(find.text('İstenen teslim'), findsNothing);
      expect(
        find.textContaining(
          RegExp('^Teklifinizi bekliyor( · .*\u00A0kadar)?\$'),
        ),
        findsOneWidget,
      );
      // Müşterinin adı yalnızca başlığın üst satırında.
      expect(find.textContaining(row.customerTitle!), findsOneWidget);
      await app.finish(tester);
    },
  );

  // QA SC-01: itilmiş bir sayfadan bir sekme rotasını `push` etmek kabuğu ikinci kez kurar (aynı
  // anahtarlı iki sayfa, çökme). Bayi gezinmesi çekirdeğin kuralına uyar: sekmeye `go`, ayrıntıya
  // `push` (yığın korunur).
  testWidgets('openDestination: sekme rotası sekmeye geçer, ayrıntı itilir', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/home-bayi',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => shell,
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home-bayi',
                  builder: (context, state) => const Text('tab:home'),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/approvals',
                  builder: (context, state) => Text('tab:${state.uri}'),
                  routes: [
                    GoRoute(
                      path: ':id',
                      builder: (context, state) => Text('detail:${state.uri}'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/pushed',
          builder: (context, state) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () =>
                      openDestination(context, '/approvals?type=4'),
                  child: const Text('tab'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    unawaited(router.push('/pushed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('tab'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('tab:/approvals?type=4'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/approvals?type=4',
    );
  });
}
