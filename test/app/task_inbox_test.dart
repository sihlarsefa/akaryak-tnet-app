// v4 "Sade" §3.4 / §9: ONE task inbox feeds the home hero, the Onaylar badge and Onaylar › Bende, so
// the counts agree by construction (P2), with the fakes (no codes in customer-facing text).
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/app/shell/shell_badges.dart';
import 'package:akaryakitnet/app/tasks/task_inbox.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/network/fake/fake_parity.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/push/unread_count_provider.dart';
import 'package:akaryakitnet/features/approvals/api.dart';
import 'package:akaryakitnet/features/bayi/api.dart';
import 'package:akaryakitnet/features/bayi/application/bayi_grants.dart';
import 'package:akaryakitnet/features/bayi/application/role_tip.dart';
import 'package:akaryakitnet/features/customer_orders/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

Future<ProviderContainer> _signedIn(String key, {FakeWorld? world}) async {
  final h = await TestHarness.create(world: world);
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

/// A task line as read (the words inside each fact are bound with no-break
/// spaces, v4 A17).
String _plain(String? s) => (s ?? '').replaceAll('\u00A0', ' ');

void main() {
  // Roller v5 öncesi akış (eski sunucu, geçiş yapılmamış bayi / cari): şirket içi talepler (9003) ve
  // birim onaycısı olmayan bayi (müdür ve sahip de karar verir). Roller v5 dünyası
  // test/app/roles_v5_test.dart içinde.
  setUpAll(() {
    FakeWorld.defaultCompanyApprovals = true;
    FakeWorld.defaultV5Station = false;
  });
  tearDownAll(() {
    FakeWorld.defaultCompanyApprovals = false;
    FakeWorld.defaultV5Station = true;
  });

  for (final key in ['musteri', 'onay']) {
    test('$key: ana sayfa sayısı = Onaylar rozeti = Bende (tek sayı)', () async {
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
      final badge = c.read(destinationBadgesProvider)[DestinationId.approvals];
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
      // Not kimin istediğini söyler (başlık neyin istendiğini söyler; v4 tur 2).
      final merged = inbox.items
          .where((t) => t.note == 'Demir Petrol istiyor')
          .toList();
      expect(merged, hasLength(1));
      expect(merged.single.title, 'Çek görselini yükleyin');
      expect(asked, contains(merged.single.orderId));
      // The fakes: quote 12002 (+ its cheque), the 24.000 L quote over the
      // company threshold (a manager's and an approver's to approve, panel
      // parity), the 12012 cheque the bayi asks for, the reported delivery
      // and Burak Yılmaz's request.
      expect(count, 5);
      expect(
        inbox.items.where((t) => t.kind == TaskKind.quoteDecision),
        hasLength(2),
      );
      // That question is counted on Onaylar: the Diğer dot (Finans bilgisi)
      // does not signal it a second time.
      expect(c.read(destinationBadgesProvider)[DestinationId.financeInfo], 0);
    });
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
        decider: CustomerDecider.full,
        approvals: const [question],
      );
      expect(tasks, hasLength(1));
      final t = tasks.single;
      expect(t.orderId, 12012);
      expect(t.title, 'Çek görselini yükleyin');
      expect(_plain(t.subtitle), 'Motorin 12.000 L · Pendik Lojistik Merkezi');
      expect(t.note, 'Demir Petrol istiyor');
      // Satır talebin açıldığı anı değil, hiç zaman yazmaz (bayinin ne zaman istediği bilinmez).
      expect(t.time, isNull);
      expect(t.actionLabel, 'Çek görselini yükle');
      expect(t.location, '/approvals/9005?focus=request');
      expect(TaskInbox(items: tasks).count, 1);
    });

    test('sahipsiz belge siparişiyle anılır ("bayi · Çek" değil)', () {
      final tasks = buildCustomerTasks(
        home: home(docs: const [cheque]),
        decider: CustomerDecider.full,
      );
      final t = tasks.single;
      expect(t.kind, TaskKind.paymentDocument);
      expect(_plain(t.subtitle), 'Motorin 12.000 L · Pendik Lojistik Merkezi');
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
        decider: CustomerDecider.full,
        approvals: const [request],
      );
      final r = tasks.firstWhere((t) => t.kind == TaskKind.companyRequest);
      expect(r.title, 'Talebi onaylayın');
      expect(_plain(r.subtitle), 'Burak Yılmaz · Motorin 30.000 L');
      expect(r.amount, '1.263.000 ₺');
      // Two bayis: the line says the order first, then the bayi (short).
      final d = tasks.firstWhere((t) => t.kind == TaskKind.deliveryAcceptance);
      expect(
        _plain(d.subtitle),
        'Motorin · Pendik Lojistik Merkezi · Demir Petrol',
      );
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
        decider: CustomerDecider.full,
      ).single;
      expect(_plain(single.subtitle), 'Motorin · Pendik Lojistik Merkezi');
      // The server's summary ("ürün · litre · tahmini …") reads the same way.
      final server = buildCustomerTasks(
        home: home(),
        decider: CustomerDecider.full,
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
      expect(
        _plain(server.subtitle),
        'Selin Aydın · Motorin (Euro 5) 14.000 L',
      );
      expect(server.amount, '599.900 ₺');
    });

    test('bayi adı kısa yazılır', () {
      expect(taskCompanyName(station), 'Demir Petrol');
      expect(taskCompanyName('Körfez Nakliyat ve Ticaret'), 'Körfez Nakliyat');
      expect(taskCompanyName(null), '');
    });
  });

  // Panel eşitliği (web müşteri sipariş ayrıntısı): talep edenin Teklifler ve Sevkiyatlar "Düzenler"
  // yetkisi var (Müşteri Operasyon grubu). Panel gibi eşik altı teklifi (12002, 8.000 L) onaylar ve
  // teslimatı kabul eder; şirketin onay eşiğini (20.000 L / 750.000 ₺) aşan teklif onaylayanındır:
  // sayılmaz, eksik belgesi de onun işi olmaz (revize / red sipariş sayfasında açık).
  test(
    'talep: eşik altı teklif ve teslimat onun işi, eşik üstü teklif onaylayanın; taslak sayılmaz',
    () async {
      final c = await _signedIn('talep');
      c.listen(customerTasksProvider, (_, _) {});
      await _until(() => c.read(customerHomeProvider).data != null);
      final inbox = c.read(customerTasksProvider);
      final dash = c.read(customerHomeProvider).data!.dashboard;
      final below = dash.pendingDecisions.firstWhere(
        (r) => r.quantityLiters == 8000,
      );
      final above = dash.pendingDecisions.firstWhere(
        (r) => r.quantityLiters == 24000,
      );
      // Sunucunun değerleri (yeni API): eşik altında onay açık, üstünde panelin notu.
      expect(below.canApproveQuote, isTrue);
      expect(above.canDecideQuote, isTrue);
      expect(above.canApproveQuote, isFalse);
      expect(above.approveBlockedReason, OrdersCopy.requesterApproveBlocked);
      final quotes = [
        for (final t in inbox.items)
          if (t.kind == TaskKind.quoteDecision) t,
      ];
      expect(quotes.map((t) => t.orderId), [below.orderId]);
      expect(inbox.items.where((t) => t.orderId == above.orderId), isEmpty);
      expect(inbox.of(TaskKind.deliveryAcceptance), isNotNull);
      // Eşik altı teklifin eksik çeki teklifle tek iş; sahipsiz belge kalmaz.
      expect(quotes.single.actionKind, TaskActionKind.uploadDocument);
      expect(inbox.of(TaskKind.paymentDocument), isNull);
      for (final t in inbox.items.where((t) => t.kind == TaskKind.draft)) {
        expect(t.counts, isFalse);
      }
    },
  );

  // v4 tur 2: talep eden de tek sayı görür — ana sayfa = Diğer › Onaylar rozeti = Bende. Panel
  // eşitliği: sayı, panelde kullanılabilir kararı olanlardır (eşik altı teklif, teslimat, bayinin
  // istediği çek); eşik üstü teklif onay bekleyenlerdedir ama sayılmaz.
  test(
    'talep: ana sayfa = Onaylar rozeti = Bende; eşik üstü teklif sayılmaz',
    () async {
      final c = await _signedIn('talep');
      c.listen(customerTasksProvider, (_, _) {});
      c.listen(destinationBadgesProvider, (_, _) {});
      c.listen(approvalsListProvider(const ApprovalsQuery()), (_, _) {});
      await _until(
        () =>
            c.read(customerHomeProvider).data != null &&
            c.read(approvalsListProvider(const ApprovalsQuery())).hasData,
      );
      final inbox = c.read(customerTasksProvider);
      final badge = c.read(destinationBadgesProvider)[DestinationId.approvals];
      expect(badge, inbox.count);
      expect(c.read(taskCountProvider), inbox.count);
      // Bende'nin satırları kahramanın sayılan işleridir; bayinin istediği belge onun işidir.
      expect(inbox.items.where((t) => t.counts), hasLength(inbox.count));
      expect(inbox.of(TaskKind.financeQuestion), isNotNull);
      final waiting = c.read(customerHomeProvider).data!.dashboard;
      expect(waiting.pendingDecisionTotal, 2);
      expect(
        inbox.items.where((t) => t.kind == TaskKind.quoteDecision),
        hasLength(1),
      );
      // 12002 (+ çeki), bildirilen teslimat, bayinin istediği 12012 çeki.
      expect(inbox.count, 3);
    },
  );

  // Yayındaki eski API panel değerlerini göndermez: yedek kural (Teklifler / Sevkiyatlar "Düzenler",
  // şirket rolü ve ana sayfanın onay eşiği) aynı işleri, aynı sırayla verir.
  for (final key in ['talep', 'onay', 'musteri']) {
    test('$key (eski API, alanlar yok): aynı işler, aynı sayı', () async {
      Future<List<String>> ids({required bool fields}) async {
        final world = FakeWorld.seeded();
        FakeParity.set(world, value: fields);
        final c = await _signedIn(key, world: world);
        c.listen(customerTasksProvider, (_, _) {});
        c.listen(approvalsListProvider(const ApprovalsQuery()), (_, _) {});
        await _until(
          () =>
              c.read(customerHomeProvider).data != null &&
              c.read(approvalsListProvider(const ApprovalsQuery())).hasData,
        );
        final rows = c.read(customerHomeProvider).data!.dashboard;
        for (final r in rows.pendingDecisions) {
          expect(r.canApproveQuote == null, !fields, reason: '${r.orderId}');
        }
        return [
          for (final t in c.read(customerTasksProvider).items)
            if (t.counts) t.id,
        ];
      }

      final server = await ids(fields: true);
      final fallback = await ids(fields: false);
      expect(fallback, server);
      expect(server, isNotEmpty);
    });
  }

  // v4 tur 2 (H4, M2): teklif işi teklif ekleme yetkisidir, masayı görmek değil; itiraz işi sevkiyata
  // dokunabilenindir. Finans "Sıradaki işiniz"de teklif veremeyeceği siparişi açmaz; izleyiciye
  // yapamayacağı iş söylenmez.
  for (final key in ['finans', 'izleyici']) {
    test(
      '$key: teklif ve itiraz işi yok, "Sıradaki işiniz" teklif açmaz',
      () async {
        final c = await _signedIn(key);
        c.listen(bayiTaskQueuesProvider, (_, _) {});
        c.listen(taskWaitingPathsProvider, (_, _) {});
        await _until(() => c.read(bayiHomeProvider).data != null);
        final policy = c.read(accessPolicyProvider);
        expect(policy.quotesOrders, isFalse);
        final inbox = c.read(bayiTaskQueuesProvider);
        expect(inbox.of(TaskKind.quotes), isNull);
        if (key == 'izleyici') expect(inbox.of(TaskKind.disputes), isNull);
        expect(inbox.next()?.kind, isNot(TaskKind.quotes));
        for (final p in c.read(taskWaitingPathsProvider)) {
          expect(p, isNot(startsWith('/bayi/orders/')), reason: p);
        }
      },
    );
  }

  test('sahip: teklif ve itiraz işi var (yetkisi var)', () async {
    final c = await _signedIn('sahip');
    c.listen(bayiTaskQueuesProvider, (_, _) {});
    await _until(() => c.read(bayiHomeProvider).data != null);
    expect(c.read(accessPolicyProvider).quotesOrders, isTrue);
    expect(c.read(bayiTaskQueuesProvider).of(TaskKind.quotes), isNotNull);
  });

  // v4 tur 2 (L1): ilk oturum ipucu rolün yapabildiğini söyler; sekmeyi yalnızca alt menüdeyse adıyla
  // anar. Depo planlamaz, şoför atamaz; özel rol teklif vermiyorsa Teklifler'i duymaz.
  test('ipucu adımları yetkiden: depo planlamaz; sahipte üç adım', () async {
    final depo = await _signedIn('depo');
    final steps = BayiHintSteps.forGrants(
      depo.read(accessPolicyProvider).rolePreset,
      depo.read(bayiGrantsProvider),
      inBar: (path) => path == '/dispatch',
    );
    expect(steps.join(' '), isNot(contains('planlayın')));
    expect(steps.join(' '), isNot(contains('Şoför atayın')));
    final sahip = await _signedIn('sahip');
    final owner = BayiHintSteps.forGrants(
      sahip.read(accessPolicyProvider).rolePreset,
      sahip.read(bayiGrantsProvider),
      inBar: (path) => path == '/quote-desk' || path == '/approvals',
    );
    expect(owner, [
      'Yeni siparişlere Teklifler sekmesinden fiyat verin.',
      'Müşteri onaylayınca sevkiyatı planlayın.',
      'Kararınızı bekleyen talepler Onaylar sekmesinde.',
    ]);
    final elsewhere = BayiHintSteps.forGrants(
      sahip.read(accessPolicyProvider).rolePreset,
      sahip.read(bayiGrantsProvider),
      inBar: (_) => false,
    );
    expect(elsewhere.last, "Kararınızı bekleyen talepler Diğer › Onaylar'da.");
  });

  test('"Sıradaki işiniz" web portalında yapılan işi açmaz', () {
    const inbox = TaskInbox(
      items: [
        TaskItem(
          id: 'tupras-today',
          kind: TaskKind.tuprasToday,
          title: 'Bugünün Tüpraş fiyatını girin',
          route: '/home',
          external: true,
        ),
        TaskItem(
          id: 'approvals',
          kind: TaskKind.approvals,
          title: 'Kararınızı bekleyen 2 talep',
          route: '/approvals',
        ),
      ],
    );
    expect(inbox.next()?.id, 'approvals');
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

  // v4 B5 (sunucu gerçeği, ApprovalInboxService.ActionableAsync): Bende ve rozet yalnızca
  // görüntüleyenin hareket edebileceği talepleri sayar. Ek bilgi bekleyen talep yanıtı verecek
  // tarafındadır (saha temsilcisi, cari); onaylayanın Bende'sine yalnızca 48 saat yanıt gelmezse
  // döner. "Bende 8"in ikisi başkasını bekliyordu.
  group('Bende yalnızca sıranız olanlar (v4 B5)', () {
    Iterable<Object?> ids(List<Map<String, dynamic>> rows) =>
        rows.map((a) => a['id']);

    test(
      'başkasının yanıtını bekleyen talep Bende\'de yok, yanıtlayanınkinde var',
      () {
        final world = FakeWorld.seeded();
        final store = A5FakeStore.of(world);
        for (final key in ['sahip', 'finans', 'mudur']) {
          final p = findFakePersona(key)!;
          final bende = store.inbox(p, 0);
          expect(bende, isNotEmpty, reason: key);
          for (final a in bende) {
            final waitsOnOthers =
                a['status'] == ApprovalStatus.infoRequested.code &&
                a['requestedByUserId'] != p.userId;
            expect(waitsOnOthers, isFalse, reason: '$key: ${a['id']}');
          }
          expect(ids(bende), isNot(contains(9004)), reason: key);
          expect(ids(bende), isNot(contains(9005)), reason: key);
        }
        // Yanıtı verecek olanlar: vergi levhası saha temsilcisinden, çek cariden.
        expect(ids(store.inbox(findFakePersona('saha')!, 0)), contains(9004));
        expect(
          ids(store.inbox(findFakePersona('musteri')!, 0)),
          contains(9005),
        );
        // Ek bilgiyi isteyen (finans) talebi Kararlarım'da bulur (sunucu DecidedByMe).
        expect(ids(store.inbox(findFakePersona('finans')!, 2)), contains(9004));
      },
    );

    test('48 saattir yanıt gelmeyen talep onaylayanın Bende\'sine döner', () {
      final world = FakeWorld.seeded();
      final store = A5FakeStore.of(world);
      final sahip = findFakePersona('sahip')!;
      expect(ids(store.inbox(sahip, 0)), isNot(contains(9004)));
      store.extraOf(world.approval(9004)!).infoRequest!['at'] = FakeWorld.utc(
        DateTime.now().toUtc().subtract(
          const Duration(hours: A5FakeStore.infoReminderHours + 1),
        ),
      );
      expect(ids(store.inbox(sahip, 0)), contains(9004));
    });

    for (final key in ['sahip', 'finans']) {
      test('$key: rozet = Bende = ana sayfanın onay satırı', () async {
        final c = await _signedIn(key);
        c.listen(bayiTaskQueuesProvider, (_, _) {});
        c.listen(approvalsListProvider(const ApprovalsQuery()), (_, _) {});
        await _until(
          () =>
              c.read(bayiHomeProvider).data != null &&
              c.read(unreadCountProvider).approvals > 0 &&
              c.read(approvalsListProvider(const ApprovalsQuery())).hasData,
        );
        final badge = c.read(unreadCountProvider).approvals;
        final list = c.read(approvalsListProvider(const ApprovalsQuery()));
        expect(list.totalCount, badge);
        expect(list.items, hasLength(badge));
        expect(
          c.read(bayiTaskQueuesProvider).of(TaskKind.approvals)?.count,
          badge,
        );
        final me = c.read(currentUserIdProvider);
        for (final r in list.items) {
          expect(
            r.status == ApprovalStatus.infoRequested &&
                r.requestedByUserId != me,
            isFalse,
            reason: 'Bende ${r.id}',
          );
        }
      });
    }
  });

  group('v4 tur 2', () {
    test('çok ürünlü talep tek ürün söylemez: "30.000 L · 2 ürün"', () async {
      final c = await _signedIn('onay');
      c.listen(customerTasksProvider, (_, _) {});
      await _until(
        () =>
            c.read(customerHomeProvider).data != null &&
            c.read(approvalsListProvider(const ApprovalsQuery())).hasData,
      );
      final r = c.read(customerTasksProvider).of(TaskKind.companyRequest);
      expect(r, isNotNull);
      expect(_plain(r!.subtitle), 'Burak Yılmaz · 30.000 L · 2 ürün');
      expect(r.subtitle, isNot(contains('Pendik')));
    });

    test('olgu içindeki sözcükler bölünmez boşlukla bağlı (A17)', () {
      const station = 'Demir Petrol Akaryakıt Ltd. Şti.';
      final tasks = buildCustomerTasks(
        home: const CustomerHomeData(
          customerId: 101,
          customerTitle: 'Anadolu Lojistik A.Ş.',
          stationTitle: station,
          stations: [StationOption(id: 1, title: station)],
          dashboard: CustomerDashboard(
            awaitingStation: [
              DashboardOrderRow(
                orderId: 12012,
                orderNumber: 'SIP-20261029-12012',
                status: OrderStatus.awaitingQuote,
                quantityLiters: 12000,
                productName: 'Motorin',
                stationTitle: station,
                deliveryPointName: 'Pendik Lojistik Merkezi',
              ),
            ],
          ),
          pendingPaymentDocuments: [
            PendingPaymentDocument(
              orderId: 12012,
              orderNumber: 'SIP-20261029-12012',
              stationTitle: station,
              methodName: 'Çek',
              kind: AttachmentKind.chequeImage,
              target: PaymentUploadTarget(),
            ),
          ],
        ),
        decider: CustomerDecider.full,
      );
      // Satır yalnızca " · "da kırılır: "Pendik Lojistik / Merkezi" olmaz.
      expect(
        tasks.single.subtitle,
        'Motorin\u00A012.000\u00A0L · Pendik\u00A0Lojistik\u00A0Merkezi',
      );
    });

    test(
      'sahip: Tüpraş fiyatı portalda girilir, kart bunu söyler (B15)',
      () async {
        final c = await _signedIn('sahip');
        c.listen(bayiTaskQueuesProvider, (_, _) {});
        await _until(() => c.read(bayiHomeProvider).data != null);
        final t = c.read(bayiTaskQueuesProvider).of(TaskKind.tuprasToday);
        expect(t, isNotNull, reason: 'sahte veride bugünün fiyatı eksik');
        expect(t!.actionLabel, 'Portalda girin');
        expect(t.external, isTrue);
        expect(t.toAknTask().external, isTrue);
      },
    );

    test('merkez: "Onayınızı bekleyen n talep"', () async {
      final c = await _signedIn('merkez');
      c.listen(platformTasksProvider, (_, _) {});
      await _until(() => c.read(unreadCountProvider).approvals > 0);
      final n = c.read(unreadCountProvider).approvals;
      final t = c.read(platformTasksProvider).of(TaskKind.platformApprovals);
      expect(t?.title, 'Onayınızı bekleyen $n talep');
      expect(t?.title, isNot(startsWith('Onaylayın')));
    });

    test('sıradaki iş: kapanan sayfanın kendisi değil, ilk sayılan iş', () {
      const inbox = TaskInbox(
        items: [
          TaskItem(
            id: 'request-9003',
            kind: TaskKind.companyRequest,
            title: 'Talebi onaylayın',
            route: '/approvals/9003',
            focus: 'request',
          ),
          TaskItem(
            id: 'quote-12002',
            kind: TaskKind.quoteDecision,
            title: 'Teklifi onaylayın',
            route: '/orders/12002',
            focus: 'quote',
          ),
          TaskItem(
            id: 'draft',
            kind: TaskKind.draft,
            title: 'Yarım kalan siparişiniz',
            route: '/orders/new',
            counts: false,
          ),
        ],
      );
      expect(inbox.next()?.id, 'request-9003');
      expect(
        inbox.next(except: '/approvals/9003?focus=request')?.id,
        'quote-12002',
      );
      expect(
        const TaskInbox(
          items: [
            TaskItem(
              id: 'draft',
              kind: TaskKind.draft,
              title: 'Yarım kalan siparişiniz',
              route: '/orders/new',
              counts: false,
            ),
          ],
        ).next(),
        isNull,
      );
      expect(nextTaskLabel, 'Sıradaki işiniz');
    });

    for (final key in ['musteri', 'onay']) {
      test(
        '$key: bekleyen işlerin sayfaları (okunmuş bildirim eylemi korur)',
        () async {
          final c = await _signedIn(key);
          c.listen(taskWaitingPathsProvider, (_, _) {});
          await _until(
            () =>
                c.read(customerHomeProvider).data != null &&
                c.read(approvalsListProvider(const ApprovalsQuery())).hasData,
          );
          final paths = c.read(taskWaitingPathsProvider);
          final inbox = c.read(customerTasksProvider);
          for (final t in inbox.items.where((t) => t.counts)) {
            expect(paths, contains(taskPath(t.route)), reason: t.id);
          }
          // Teklif 12002, Burak Yılmaz'ın talebi (9003) ve bildirilen teslimat.
          final quote = inbox.of(TaskKind.quoteDecision)!;
          expect(paths, contains('/orders/${quote.orderId}'));
          expect(paths, contains('/approvals/9003'));
          expect(paths.any((p) => p.startsWith('/shipments/')), isTrue);
          expect(paths, isNot(contains('/orders/new')));
        },
      );
    }

    test(
      'sahip: teklif bekleyen siparişler ve Bende talepleri bekleyen sayfalardır',
      () async {
        final c = await _signedIn('sahip');
        c.listen(taskWaitingPathsProvider, (_, _) {});
        await _until(
          () =>
              c.read(bayiHomeProvider).data != null &&
              c.read(approvalsListProvider(const ApprovalsQuery())).hasData,
        );
        final paths = c.read(taskWaitingPathsProvider);
        final quotes = c.read(bayiTaskQueuesProvider).of(TaskKind.quotes)!;
        expect(paths, contains('/bayi/orders/${quotes.orderId}'));
        for (final r
            in c.read(approvalsListProvider(const ApprovalsQuery())).items) {
          expect(paths, contains('/approvals/${r.id}'));
        }
        // Başkasının yanıtını bekleyen ek bilgi talebi beklemez (B5).
        expect(paths, isNot(contains('/approvals/9004')));
      },
    );
  });

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
