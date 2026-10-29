// v4 "Sade" §3.4 / §9: ONE task inbox feeds the home hero, the Onaylar badge and Onaylar › Bende, so
// the counts agree by construction (P2), with the fakes (no codes in customer-facing text).
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/app/shell/shell_badges.dart';
import 'package:akaryakitnet/app/tasks/task_inbox.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/push/unread_count_provider.dart';
import 'package:akaryakitnet/features/approvals/api.dart';
import 'package:akaryakitnet/features/bayi/api.dart';
import 'package:akaryakitnet/features/customer_orders/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

Future<ProviderContainer> _signedIn(String key) async {
  final h = await TestHarness.create();
  final c = h.container();
  addTearDown(c.dispose);
  final s = c.read(sessionControllerProvider.notifier);
  final outcome = await s.loginWithPassword(key, 'demo');
  if (outcome is LoginNeedsCode) {
    await s.verifyCode(outcome.challenge.challengeId, '123456');
  }
  expect(c.read(sessionControllerProvider), isA<SessionAuthenticated>());
  return c;
}

Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 400 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ready(), isTrue, reason: 'veri yüklenmedi');
}

/// No order, shipment or request codes in what the customer reads (P4).
final _code = RegExp(r'\b(SIP|SVK|SSF|TLP)-');

void main() {
  for (final key in ['musteri', 'onay']) {
    test(
      '$key: ana sayfa sayısı = Onaylar rozeti = Bende (tek sayı)',
      () async {
        final c = await _signedIn(key);
        c.listen(customerTasksProvider, (_, _) {});
        c.listen(destinationBadgesProvider, (_, _) {});
        c.listen(approvalsListProvider(const ApprovalsQuery()), (_, _) {});
        await _until(
          () =>
              c.read(customerHomeProvider).data != null &&
              c.read(approvalsListProvider(const ApprovalsQuery())).hasData,
        );
        final inbox = c.read(customerTasksProvider);
        final count = c.read(taskCountProvider);
        final badge = c.read(
          destinationBadgesProvider,
        )[DestinationId.approvals];
        // Bende renders the same inbox: its counting rows ARE the count.
        expect(count, greaterThan(0));
        expect(badge, count);
        expect(inbox.items.where((t) => t.counts), hasLength(count));
        // The quote decision leads, merged with its missing document.
        final quote = inbox.of(TaskKind.quoteDecision);
        expect(quote, isNotNull);
        expect(quote!.title, 'Teklifi onaylayın');
        // Ids are unique (each order appears once).
        expect(
          inbox.items.map((t) => t.id).toSet(),
          hasLength(inbox.items.length),
        );
        for (final t in inbox.items) {
          expect(_code.hasMatch(t.title), isFalse, reason: t.title);
          expect(_code.hasMatch(t.subtitle ?? ''), isFalse, reason: t.subtitle);
        }
        // Every order is ONE task: the A5 order that the bayi's finance asked
        // a cheque for (finance question + missing document) counts once.
        final orders = [
          for (final t in inbox.items)
            if (t.orderId != null) t.orderId!,
        ];
        expect(orders.toSet(), hasLength(orders.length), reason: '$orders');
        final asked = c
            .read(approvalsListProvider(const ApprovalsQuery()))
            .items
            .where(
              (a) =>
                  a.subjectType == 'Order' &&
                  a.status == ApprovalStatus.infoRequested,
            )
            .map((a) => a.subjectId)
            .toSet();
        expect(asked, isNotEmpty);
        for (final id in asked) {
          final about = inbox.items.where((t) => t.orderId == id).toList();
          expect(about, hasLength(1), reason: 'sipariş $id');
        }
        final merged = inbox.items
            .where(
              (t) => t.note == 'Bayiniz bu siparişin çek görselini istiyor',
            )
            .toList();
        expect(merged, hasLength(1));
        expect(merged.single.title, 'Çek görselini yükleyin');
        expect(asked, contains(merged.single.orderId));
        // The fakes: quote 12002 (+ its cheque), the 12012 cheque the bayi
        // asks for, the reported delivery and Burak Yılmaz's request.
        expect(count, 4);
        // That question is counted on Onaylar: the Diğer dot (Finans bilgisi)
        // does not signal it a second time.
        expect(c.read(destinationBadgesProvider)[DestinationId.financeInfo], 0);
      },
    );
  }

  group('bir sipariş, bir iş (v4 §3.4)', () {
    const station = 'Demir Petrol Akaryakıt Ltd. Şti.';
    CustomerHomeData home({
      List<PendingPaymentDocument> docs = const [],
      List<DashboardShipmentRow> shipments = const [],
      bool twoBayis = false,
    }) => CustomerHomeData(
      customerId: 101,
      customerTitle: 'Anadolu Lojistik A.Ş.',
      stationTitle: station,
      stations: [
        const StationOption(id: 1, title: station),
        if (twoBayis) const StationOption(id: 2, title: 'Körfez Enerji A.Ş.'),
      ],
      dashboard: CustomerDashboard(
        awaitingStation: const [
          DashboardOrderRow(
            orderId: 12012,
            orderNumber: 'SIP-20261029-12012',
            status: OrderStatus.awaitingQuote,
            quantityLiters: 12000,
            productName: 'Motorin',
            stationTitle: station,
            deliveryPointName: 'Pendik Lojistik Merkezi',
            financeStatus: OrderFinanceStatus.infoRequested,
          ),
        ],
        shipments: shipments,
      ),
      pendingPaymentDocuments: docs,
    );
    const cheque = PendingPaymentDocument(
      orderId: 12012,
      orderNumber: 'SIP-20261029-12012',
      stationTitle: station,
      methodName: 'Çek',
      kind: AttachmentKind.chequeImage,
      target: PaymentUploadTarget(),
    );
    const question = ApprovalRow(
      id: 9005,
      type: ApprovalType.orderFinance,
      status: ApprovalStatus.infoRequested,
      stationTitle: station,
      subjectType: 'Order',
      subjectId: 12012,
      liters: 12000,
    );

    test('finans sorusu + aynı siparişin eksik çeki = tek iş, tek sayı', () {
      final tasks = buildCustomerTasks(
        home: home(docs: const [cheque]),
        canDecide: true,
        approvals: const [question],
      );
      expect(tasks, hasLength(1));
      final t = tasks.single;
      expect(t.orderId, 12012);
      expect(t.title, 'Çek görselini yükleyin');
      expect(t.subtitle, 'Motorin 12.000 L · Pendik Lojistik Merkezi');
      expect(t.note, 'Bayiniz bu siparişin çek görselini istiyor');
      expect(t.actionLabel, 'Çek görselini yükle');
      expect(t.location, '/approvals/9005?focus=request');
      expect(TaskInbox(items: tasks).count, 1);
    });

    test('sahipsiz belge siparişiyle anılır ("bayi · Çek" değil)', () {
      final tasks = buildCustomerTasks(
        home: home(docs: const [cheque]),
        canDecide: true,
      );
      final t = tasks.single;
      expect(t.kind, TaskKind.paymentDocument);
      expect(t.subtitle, 'Motorin 12.000 L · Pendik Lojistik Merkezi');
      expect(t.subtitle, isNot(contains('Çek')));
    });

    test('satır sözü: önce fiil, ürün litreden önce, litre bir kez', () {
      const request = ApprovalRow(
        id: 9003,
        type: ApprovalType.companyOrderRequest,
        status: ApprovalStatus.pending,
        requestedByName: 'Burak Yılmaz',
        summary: '30.000 L Motorin · Pendik Lojistik Merkezi',
        amount: 1263000,
        liters: 30000,
      );
      final tasks = buildCustomerTasks(
        home: home(
          twoBayis: true,
          shipments: const [
            DashboardShipmentRow(
              shipmentId: 5002,
              orderId: 12003,
              orderNumber: 'SIP-20261028-12003',
              status: ShipmentStatus.reported,
              plannedLiters: 12000,
              deliveredLiters: 11950,
              stationTitle: station,
              productName: 'Motorin',
              deliveryPointName: 'Pendik Lojistik Merkezi',
            ),
          ],
        ),
        canDecide: true,
        approvals: const [request],
      );
      final r = tasks.firstWhere((t) => t.kind == TaskKind.companyRequest);
      expect(r.title, 'Talebi onaylayın');
      expect(r.subtitle, 'Burak Yılmaz · Motorin 30.000 L');
      expect(r.amount, '1.263.000 ₺');
      // Two bayis: the line says the order first, then the bayi (short).
      final d = tasks.firstWhere((t) => t.kind == TaskKind.deliveryAcceptance);
      expect(d.subtitle, 'Motorin · Pendik Lojistik Merkezi · Demir Petrol');
      expect(d.amount, '11.950 L');
      // One bayi: its name is not repeated on every line (P4).
      final single = buildCustomerTasks(
        home: home(
          shipments: const [
            DashboardShipmentRow(
              shipmentId: 5002,
              orderId: 12003,
              orderNumber: 'SIP-20261028-12003',
              status: ShipmentStatus.reported,
              plannedLiters: 12000,
              deliveredLiters: 11950,
              stationTitle: station,
              productName: 'Motorin',
              deliveryPointName: 'Pendik Lojistik Merkezi',
            ),
          ],
        ),
        canDecide: true,
      ).single;
      expect(single.subtitle, 'Motorin · Pendik Lojistik Merkezi');
      // The server's summary ("ürün · litre · tahmini …") reads the same way.
      final server = buildCustomerTasks(
        home: home(),
        canDecide: true,
        approvals: const [
          ApprovalRow(
            id: 34,
            type: ApprovalType.companyOrderRequest,
            status: ApprovalStatus.pending,
            requestedByName: 'Selin Aydın',
            summary:
                'Motorin (Euro 5) · 14.000 L · tahmini 599.900,00 ₺ · Not: '
                'Şantiye jeneratörleri',
            amount: 599900,
            liters: 14000,
          ),
        ],
      ).single;
      expect(server.subtitle, 'Selin Aydın · Motorin (Euro 5) 14.000 L');
      expect(server.amount, '599.900 ₺');
    });

    test('bayi adı kısa yazılır', () {
      expect(taskCompanyName(station), 'Demir Petrol');
      expect(taskCompanyName('Körfez Nakliyat ve Ticaret'), 'Körfez Nakliyat');
      expect(taskCompanyName(null), '');
    });
  });

  test('talep: yalnızca kendi işleri (karar yok); taslak sayılmaz', () async {
    final c = await _signedIn('talep');
    c.listen(customerTasksProvider, (_, _) {});
    await _until(() => c.read(customerHomeProvider).data != null);
    final inbox = c.read(customerTasksProvider);
    expect(inbox.of(TaskKind.quoteDecision), isNull);
    expect(inbox.of(TaskKind.deliveryAcceptance), isNull);
    for (final t in inbox.items.where((t) => t.kind == TaskKind.draft)) {
      expect(t.counts, isFalse);
    }
  });

  test('sahip: rozet = kahramanın onay satırı = Bende', () async {
    final c = await _signedIn('sahip');
    c.listen(bayiTaskQueuesProvider, (_, _) {});
    c.listen(destinationBadgesProvider, (_, _) {});
    c.listen(approvalsListProvider(const ApprovalsQuery()), (_, _) {});
    await _until(
      () =>
          c.read(bayiHomeProvider).data != null &&
          c.read(unreadCountProvider).approvals > 0 &&
          c.read(approvalsListProvider(const ApprovalsQuery())).hasData,
    );
    final badge = c.read(destinationBadgesProvider)[DestinationId.approvals]!;
    final row = c.read(bayiTaskQueuesProvider).of(TaskKind.approvals);
    expect(row, isNotNull);
    expect(row!.count, badge);
    expect(row.title, startsWith('Kararınızı bekleyen $badge talep'));
    // The quotes queue leads with the most urgent order and "Teklif ver".
    final quotes = c.read(bayiTaskQueuesProvider).of(TaskKind.quotes);
    expect(quotes?.actionLabel, 'Teklif ver');
  });

  // Area C's approvals_fake re-registers notifications/unread-count, so `approvals` is the A5
  // store's Bende count (spec §8 C).
  test(
    'sahip: Bende sayısı rozetle aynı (fake: alan C eşitler, spec §8 C)',
    () async {
      final c = await _signedIn('sahip');
      c.listen(approvalsListProvider(const ApprovalsQuery()), (_, _) {});
      await _until(
        () =>
            c.read(unreadCountProvider).approvals > 0 &&
            c.read(approvalsListProvider(const ApprovalsQuery())).hasData,
      );
      expect(
        c.read(approvalsListProvider(const ApprovalsQuery())).totalCount,
        c.read(unreadCountProvider).approvals,
      );
    },
  );

  group('sıralama ve dil', () {
    test(
      'engelleyen → 60 dk içinde → gecikmiş → en yakın → sayı; taslak sonda',
      () {
        final now = DateTime.utc(2026, 10, 29, 9);
        final sorted = sortTasks([
          const TaskItem(
            id: 'big',
            kind: TaskKind.plan,
            title: 'p',
            route: '/',
            count: 9,
          ),
          TaskItem(
            id: 'later',
            kind: TaskKind.quoteDecision,
            title: 'q',
            route: '/',
            deadline: now.add(const Duration(hours: 5)),
          ),
          const TaskItem(
            id: 'late',
            kind: TaskKind.approvals,
            title: 'a',
            route: '/',
            overdue: 2,
          ),
          TaskItem(
            id: 'soon',
            kind: TaskKind.quotes,
            title: 's',
            route: '/',
            deadline: now.add(const Duration(minutes: 41)),
          ),
          const TaskItem(
            id: 'blocked',
            kind: TaskKind.orderingBlocked,
            title: 'b',
            route: '/',
            tone: TaskTone.danger,
          ),
          const TaskItem(
            id: 'draft',
            kind: TaskKind.draft,
            title: 'd',
            route: '/',
            tone: TaskTone.neutral,
            counts: false,
          ),
        ], now: now);
        expect(sorted.map((t) => t.id), [
          'blocked',
          'soon',
          'late',
          'later',
          'big',
          'draft',
        ]);
      },
    );

    test('sayıdan sonra iyelik eki', () {
      expect(numeralPossessive(1), "1'i");
      expect(numeralPossessive(2), "2'si");
      expect(numeralPossessive(3), "3'ü");
      expect(numeralPossessive(4), "4'ü");
      expect(numeralPossessive(6), "6'sı");
      expect(numeralPossessive(9), "9'u");
      expect(numeralPossessive(10), "10'u");
      expect(numeralPossessive(40), "40'ı");
      expect(numeralPossessive(100), "100'ü");
    });

    test('odak bağlantısı', () {
      const t = TaskItem(
        id: 'x',
        kind: TaskKind.quoteDecision,
        title: 'Teklifi onaylayın',
        route: '/orders/12002',
        focus: 'quote',
      );
      expect(t.location, '/orders/12002?focus=quote');
    });
  });
}
