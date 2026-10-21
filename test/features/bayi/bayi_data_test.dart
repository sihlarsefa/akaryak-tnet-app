// Bayi veri katmanı: sahte uçlar (§B biçimi) → depo → modeller. Ağ yok; yalıtılmış sahte sunucu.
import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/bayi/data/bayi_json.dart';
import 'package:akaryakitnet/features/bayi/data/bayi_repository.dart';
import 'package:akaryakitnet/features/bayi/data/customer_models.dart';
import 'package:akaryakitnet/features/bayi/data/desk_models.dart';
import 'package:akaryakitnet/features/bayi/data/dispatch_models.dart';
import 'package:akaryakitnet/features/bayi/data/order_models.dart';
import 'package:akaryakitnet/features/bayi/fake/desk_fake.dart';
import 'package:akaryakitnet/features/bayi/fake/fake_support.dart';
import 'package:akaryakitnet/features/bayi/fake/staff_fake.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bayi_harness.dart';

Future<(BayiHarness, ProviderContainer, BayiRepository)> _as(
  String persona,
) async {
  final h = await BayiHarness.create();
  final c = h.container();
  addTearDown(c.dispose);
  await BayiHarness.login(c, persona);
  return (h, c, c.read(bayiRepositoryProvider));
}

void main() {
  group('BayiJson', () {
    test('teslim penceresi: TimeSpan ve HH:mm', () {
      expect(BayiJson.windowTime('08:00:00'), '08:00');
      expect(BayiJson.windowTime('1.00:00:00'), '24:00');
      expect(BayiJson.windowTime('24:00'), '24:00');
      expect(BayiJson.windowTime(' '), isNull);
      expect(BayiJson.windowLabel('08:00:00', '18:00'), '08:00–18:00');
      expect(BayiJson.windowLabel(null, '17:00'), '17:00 öncesi');
    });
  });

  group('Ana sayfa bölümleri (yetkiye göre)', () {
    test('bayi sahibi tüm bölümleri görür', () async {
      final (_, _, repo) = await _as('sahip');
      final home = (await repo.home()).data;
      expect(home.stationTitle, isNotEmpty);
      expect(home.desk, isNotNull);
      expect(home.shipments, isNotNull);
      expect(home.approvals, isNotNull);
      expect(home.collections, isNotNull);
      expect(home.finance, isNotNull);
      expect(home.leads, isNotNull);
      expect(home.field, isNotNull);
      expect(home.setup, isNotNull);
      expect(home.sales, isNotNull);
      expect(home.desk!.expiryEnabled, isTrue);
      expect(home.desk!.openForQuote, greaterThan(0));
      expect(home.setup!.checks.first.portalPath, startsWith('/'));
      expect(home.sales!.days, hasLength(7));
      expect(home.collections!.overdueCount, greaterThan(0));
    });

    test(
      'depo: sevkiyat ve sipariş özeti var; tahsilat, finans, kurulum yok',
      () async {
        final (_, _, repo) = await _as('depo');
        final home = (await repo.home()).data;
        expect(home.shipments, isNotNull);
        expect(home.desk, isNotNull, reason: 'StationOrders:Gorur');
        expect(home.collections, isNull);
        expect(home.finance, isNull);
        expect(home.setup, isNull);
        expect(home.approvals, isNull);
      },
    );

    test('görüntüleyici: tahsilat ve finans yok', () async {
      final (_, _, repo) = await _as('izleyici');
      final home = (await repo.home()).data;
      expect(home.collections, isNull);
      expect(home.finance, isNull);
      expect(home.setup, isNull);
      expect(home.desk, isNotNull);
      expect(home.sales, isNotNull);
    });

    test('şoför: sevkiyat ve satış bölümü hiç yok', () async {
      final (_, _, repo) = await _as('sofor');
      final home = (await repo.home()).data;
      expect(home.shipments, isNull);
      expect(home.sales, isNull);
      expect(home.desk, isNull);
      expect(home.isEmpty, isTrue);
    });

    test(
      'saha temsilcisi: saha bölümü kendi portföyüyle, kurulum ve satış yok',
      () async {
        final (_, _, repo) = await _as('saha');
        final home = (await repo.home()).data;
        expect(home.isFieldSales, isTrue);
        expect(home.field, isNotNull);
        expect(home.field!.portfolioCount, 2);
        expect(home.setup, isNull);
        expect(home.sales, isNull);
      },
    );
  });

  group('Teklif masası', () {
    test('satırlar öneri, ödeme çipi ve geri sayımla gelir', () async {
      final (_, _, repo) = await _as('siparis');
      final page = (await repo.quoteDesk(
        view: DeskView.all,
        sort: DeskSort.expiry,
      )).page;
      expect(page.header.expiryEnabled, isTrue);
      expect(page.header.canSubmit, isTrue);
      expect(page.rows, isNotEmpty);
      expect(page.rows.every((r) => r.secondsLeft != null), isTrue);
      final withRecent = page.rows.firstWhere((r) => r.recentPrices.isNotEmpty);
      expect(withRecent.suggestedSource, 'last');
      expect(
        withRecent.suggestedUnitPrice,
        withRecent.recentPrices.first.unitPriceTry,
      );
      final revision = page.rows.firstWhere((r) => r.isRevision);
      expect(revision.latestRevisionNote, isNotNull);
      expect(page.rows.first.payChip, isNotNull);
      expect(page.counts.all, page.totalCount);
      final facets = await repo.quoteDeskFacets();
      expect(
        facets.customers.fold<int>(0, (s, f) => s + f.count),
        page.totalCount,
      );
    });

    test(
      'süre dolumu kapalıyken geri sayım yok, "süresi yaklaşan" tümüne düşer',
      () async {
        final (h, _, repo) = await _as('siparis');
        setExpiryEnabled(h.world, false);
        final page = (await repo.quoteDesk(
          view: DeskView.expiringSoon,
          sort: DeskSort.expiry,
        )).page;
        expect(page.header.expiryEnabled, isFalse);
        expect(page.view, DeskView.all);
        expect(page.counts.expiringSoon, isNull);
        expect(page.rows.every((r) => r.secondsLeft == null), isTrue);
      },
    );

    test(
      'toplu gönderim: satır başına sonuç (gönderildi, finansa, geçersiz, çakışma, hata)',
      () async {
        final (h, _, repo) = await _as('siparis');
        final page = (await repo.quoteDesk(
          view: DeskView.all,
          sort: DeskSort.newest,
        )).page;
        final marmara = page.rows.firstWhere((r) => r.customerId == 102);
        final others = page.rows.where((r) => r.customerId != 102).toList();
        expect(others.length, greaterThanOrEqualTo(3));
        injectDeskOutcome(h.world, others[1].orderId, outcome: 'conflict');
        injectDeskOutcome(h.world, others[2].orderId, outcome: 'error');
        final day = BayiJson.isoDate(TrTime.addDays(TrTime.todayStart(), 1));
        final results = await repo.submitQuotes([
          DeskSubmitItem(
            orderId: others[0].orderId,
            unitPrice: 41.95,
            deliveryDate: day,
          ),
          DeskSubmitItem(
            orderId: marmara.orderId,
            unitPrice: 42.10,
            deliveryDate: day,
          ),
          DeskSubmitItem(
            orderId: others[1].orderId,
            unitPrice: 41.9,
            deliveryDate: day,
          ),
          DeskSubmitItem(
            orderId: others[2].orderId,
            unitPrice: 41.9,
            deliveryDate: day,
          ),
          const DeskSubmitItem(
            orderId: 999999,
            unitPrice: 41.9,
            deliveryDate: '2000-01-01',
          ),
        ], idempotencyKey: 'desk-test-key-1');
        expect(
          [for (final r in results) r.outcome],
          [
            DeskOutcome.quoted,
            DeskOutcome.routedToFinance,
            DeskOutcome.conflict,
            DeskOutcome.error,
            DeskOutcome.invalid,
          ],
        );
        expect(results[4].message, 'Teslim tarihi bugünden önce olamaz.');
        // Teklif verilen ve finansa giden masadan düşer.
        final after = (await repo.quoteDesk(
          view: DeskView.all,
          sort: DeskSort.newest,
        )).page;
        final ids = after.rows.map((r) => r.orderId).toSet();
        expect(ids.contains(others[0].orderId), isFalse);
        expect(ids.contains(marmara.orderId), isFalse);
        expect(ids.contains(others[1].orderId), isTrue);
        expect(after.header.financeHeld, greaterThan(page.header.financeHeld));
        // Müşteri tarafı: sipariş "Onay bekleniyor".
        final order = await repo.order(others[0].orderId);
        expect(order.status, OrderStatus.awaitingApproval);
        expect(order.currentQuote?.unitPriceTry, 41.95);
      },
    );

    test('aynı anahtarla tekrar: sunucu ikinci kez işlemez', () async {
      final (_, _, repo) = await _as('siparis');
      final page = (await repo.quoteDesk(
        view: DeskView.all,
        sort: DeskSort.newest,
      )).page;
      final row = page.rows.firstWhere((r) => r.customerId != 102);
      final day = BayiJson.isoDate(TrTime.addDays(TrTime.todayStart(), 1));
      final item = DeskSubmitItem(
        orderId: row.orderId,
        unitPrice: 41.5,
        deliveryDate: day,
      );
      final first = await repo.submitQuotes([
        item,
      ], idempotencyKey: 'same-key-123');
      final again = await repo.submitQuotes([
        item,
      ], idempotencyKey: 'same-key-123');
      expect(first.single.outcome, DeskOutcome.quoted);
      expect(again.single.outcome, DeskOutcome.quoted, reason: 'kayıtlı yanıt');
      final order = await repo.order(row.orderId);
      expect(order.quotes, hasLength(1));
    });

    test('görüntüleyici masayı görür ama gönderemez', () async {
      final (_, _, repo) = await _as('izleyici');
      final page = (await repo.quoteDesk(
        view: DeskView.all,
        sort: DeskSort.expiry,
      )).page;
      expect(page.header.canSubmit, isFalse);
      await expectLater(
        repo.submitQuotes([
          DeskSubmitItem(
            orderId: page.rows.first.orderId,
            unitPrice: 40,
            deliveryDate: BayiJson.isoDate(TrTime.todayStart()),
          ),
        ], idempotencyKey: 'viewer-key-1'),
        throwsA(isA<ForbiddenFailure>()),
      );
    });
  });

  group('Siparişler', () {
    test('liste, sayılar ve segment süzgeci aynı tanımı kullanır', () async {
      final (_, _, repo) = await _as('sahip');
      final counts = await repo.orderCounts();
      expect(counts.of(BayiOrderSegment.toPlan), greaterThan(0));
      for (final seg in [
        BayiOrderSegment.awaitingQuote,
        BayiOrderSegment.toPlan,
        BayiOrderSegment.disputed,
      ]) {
        final page = await repo.orders(
          BayiOrdersFilter(segment: seg),
          pageSize: 100,
        );
        expect(page.totalCount, counts.of(seg), reason: seg.key);
      }
      final toPlan = await repo.orders(
        const BayiOrdersFilter(segment: BayiOrderSegment.toPlan),
      );
      expect(toPlan.items.every((o) => o.remainingLiters > 0), isTrue);
      expect(toPlan.items.first.createdAt, isNotNull);
    });

    test('ayrıntı, zaman çizelgesi ve sevkiyatlar', () async {
      final (_, _, repo) = await _as('sahip');
      final page = await repo.orders(
        const BayiOrdersFilter(segment: BayiOrderSegment.disputed),
      );
      final id = page.items.first.id;
      final order = await repo.order(id);
      final timeline = await repo.orderTimeline(id);
      final f = await repo.fulfillment(id);
      expect(order.status, OrderStatus.approved);
      expect(timeline.first.toStatus, OrderStatus.awaitingQuote);
      expect(timeline.any((t) => t.toStatus == OrderStatus.approved), isTrue);
      expect(
        f.shipments.any((s) => s.status == ShipmentStatus.disputed),
        isTrue,
      );
      expect(f.canManage, isTrue);
    });

    test('tarih ve cari süzgeci', () async {
      final (_, _, repo) = await _as('sahip');
      final all = await repo.orders(const BayiOrdersFilter(), pageSize: 100);
      final c102 = await repo.orders(
        const BayiOrdersFilter(customerId: 102),
        pageSize: 100,
      );
      expect(c102.items.every((o) => o.customerId == 102), isTrue);
      expect(c102.totalCount, lessThan(all.totalCount));
      final today = TrTime.todayStart();
      final created = await repo.orders(
        BayiOrdersFilter(createdFrom: today, createdTo: today),
        pageSize: 100,
      );
      expect(
        created.items.every((o) => TrTime.isSameDay(o.createdAt!, today)),
        isTrue,
      );
    });
  });

  group('Cariler', () {
    test(
      'bayi personeli tüm carileri, saha temsilcisi portföyünü görür',
      () async {
        final (_, _, owner) = await _as('sahip');
        final all = await owner.customers();
        expect(all.totalCount, 4);
        final (_, _, rep) = await _as('saha');
        final mine = await rep.customers();
        expect(mine.totalCount, 2);
        final card = await rep.customerSummary(mine.items.first.customerId);
        expect(card.isPortfolioView, isTrue);
        expect(card.notes, isEmpty);
        expect(card.actions.canAddNote, isFalse);
        expect(card.actions.canRequestLimit, isFalse);
      },
    );

    test(
      '360 kartı: limit, tahsilat, finans kartı, bekleyen limit talebi, teslimat noktaları',
      () async {
        final (_, _, repo) = await _as('sahip');
        final card = await repo.customerSummary(102);
        expect(card.limit, isNotNull);
        expect(card.limit!.usagePct, greaterThan(80));
        expect(card.collections, isNotNull);
        expect(card.financeCard?.stationCustomerId, card.stationCustomerId);
        expect(card.pendingLimitRequest, isNotNull);
        expect(
          card.actions.canRequestLimit,
          isFalse,
          reason: 'bekleyen talep var',
        );
        expect(card.deliveryPoints.first.window, '08:00–17:00');
        expect(card.deliveryPoints.first.tankCapacityLiters, 40000);
      },
    );

    test('not ekle (aynı anahtar tek not) ve limit talebi', () async {
      final (_, _, repo) = await _as('mudur');
      final note = await repo.addNote(
        101,
        'Ödeme günü değişti.',
        idempotencyKey: 'note-key-1',
      );
      await repo.addNote(
        101,
        'Ödeme günü değişti.',
        idempotencyKey: 'note-key-1',
      );
      final notes = await repo.notes(101);
      expect(notes.first.id, note.id);
      expect(notes.where((n) => n.body == 'Ödeme günü değişti.'), hasLength(1));
      await repo.createLimitRequest(
        103,
        const LimitRequestDraft(
          limitPeriod: 'Aylık',
          limitType: 'Litre',
          limitAmount: 400000,
          reason: 'Hasat dönemi tüketimi artıyor.',
        ),
      );
      final card = await repo.customerSummary(103);
      expect(card.pendingLimitRequest?.amount, 400000);
      await expectLater(
        repo.createLimitRequest(
          103,
          const LimitRequestDraft(limitPeriod: 'Limitsiz', reason: 'Tekrar'),
        ),
        throwsA(isA<BusinessFailure>()),
      );
    });

    test('limit talebi: sipariş masası yetkisiz (403)', () async {
      final (_, _, repo) = await _as('siparis');
      await expectLater(
        repo.createLimitRequest(
          101,
          const LimitRequestDraft(
            limitPeriod: 'Limitsiz',
            reason: 'Deneme talebi',
          ),
        ),
        throwsA(isA<ForbiddenFailure>()),
      );
    });
  });

  group('Sevkiyat', () {
    test(
      'pano: planlanacak siparişler kovalarda, şoför hesabı bilgisiyle',
      () async {
        final (_, _, repo) = await _as('sevkiyat');
        final board = await repo.board();
        expect(board.orders, isNotEmpty);
        expect(board.orders.every((o) => o.remainingLiters > 0), isTrue);
        expect(board.buckets.map((b) => b.bucket), contains(BoardBucket.today));
        expect(board.shipments.any((s) => s.isAppDriver), isTrue);
        expect(board.shipments.any((s) => !s.isAppDriver), isTrue);
        expect(board.orders.first.window, isNotNull);
        final sug = await repo.boardSuggestions();
        expect(sug.plates, isNotEmpty);
      },
    );

    test(
      'şoför listesi: önce Şoför rolü, telefon ve uygulama bilgisi',
      () async {
        final (_, _, repo) = await _as('sevkiyat');
        final drivers = await repo.drivers();
        final firstStaff = drivers.indexWhere((d) => !d.isDriverRole);
        expect(drivers.take(firstStaff).every((d) => d.isDriverRole), isTrue);
        expect(drivers.any((d) => d.isDriverRole && d.hasActiveDevice), isTrue);
        expect(
          drivers.any((d) => d.isDriverRole && !d.hasActiveDevice),
          isTrue,
        );
        expect(drivers.every((d) => d.phone != null), isTrue);
      },
    );

    test('plan: kalan litreyi aşamaz; şoför hesabıyla planlanır', () async {
      final (_, _, repo) = await _as('sevkiyat');
      final board = await repo.board();
      final order = board.orders.first;
      final at = TrTime.addDays(
        TrTime.todayStart(),
        1,
      ).add(const Duration(hours: 9));
      await expectLater(
        repo.planShipment(
          PlanShipmentDraft(
            orderId: order.orderId,
            plannedLiters: order.remainingLiters + 1,
            vehiclePlate: '41 ABC 123',
            driverName: 'Ahmet Kurt',
            scheduledAt: at,
            driverUserId: 'u-sofor',
          ),
          idempotencyKey: 'plan-key-over',
        ),
        throwsA(isA<BusinessFailure>()),
      );
      await repo.planShipment(
        PlanShipmentDraft(
          orderId: order.orderId,
          plannedLiters: order.remainingLiters,
          vehiclePlate: '41abc123',
          driverName: 'Ahmet Kurt',
          scheduledAt: at,
          driverUserId: 'u-sofor',
        ),
        idempotencyKey: 'plan-key-ok',
      );
      final f = await repo.fulfillment(order.orderId);
      final planned = f.shipments.last;
      expect(planned.status, ShipmentStatus.planned);
      expect(planned.vehiclePlate, '41 ABC 123');
      final after = await repo.board();
      expect(after.orders.any((o) => o.orderId == order.orderId), isFalse);
    });

    test(
      'yola çıkar → teslim bildir; ayrıntıda kanıt ve eylem bayrakları',
      () async {
        final (_, _, repo) = await _as('sevkiyat');
        final board = await repo.board();
        final planned = board.shipments.firstWhere(
          (s) => s.status == ShipmentStatus.planned,
        );
        final before = await repo.shipmentDetail(planned.id);
        expect(before.viewerSide, 'bayi');
        expect(before.actions.canDispatch, isTrue);
        expect(before.actions.canReassign, isTrue);
        expect(before.actions.canCancel, isTrue);
        await repo.dispatch(planned.id);
        final moving = await repo.shipmentDetail(planned.id);
        expect(moving.status, ShipmentStatus.inTransit);
        expect(moving.actions.canReport, isTrue);
        await expectLater(
          repo.report(
            planned.id,
            deliveredLiters: planned.plannedLiters + 1,
            deliveryDocumentNo: 'IRS-1',
          ),
          throwsA(isA<BusinessFailure>()),
        );
        await repo.report(
          planned.id,
          deliveredLiters: planned.plannedLiters,
          deliveryDocumentNo: 'IRS-1',
        );
        final done = await repo.shipmentDetail(planned.id);
        expect(done.status, ShipmentStatus.reported);
        expect(done.reportedByName, 'Okan Yıldız');
      },
    );

    test(
      'depo yola çıkarabilir ama planlayamaz; sipariş masası salt okunur',
      () async {
        final (_, _, depot) = await _as('depo');
        final board = await depot.board();
        final planned = board.shipments.firstWhere(
          (s) => s.status == ShipmentStatus.planned,
        );
        final detail = await depot.shipmentDetail(planned.id);
        expect(detail.actions.canDispatch, isTrue);
        expect(detail.actions.canReassign, isFalse);
        expect(detail.actions.canCancel, isFalse);
        await expectLater(
          depot.planShipment(
            PlanShipmentDraft(
              orderId: board.orders.first.orderId,
              plannedLiters: 100,
              vehiclePlate: '41 ABC 123',
              driverName: 'Ahmet Kurt',
              scheduledAt: TrTime.now().add(const Duration(hours: 2)),
            ),
            idempotencyKey: 'depot-plan',
          ),
          throwsA(isA<ForbiddenFailure>()),
        );
        final (_, _, desk) = await _as('siparis');
        final d2 = await desk.shipmentDetail(planned.id);
        expect(
          d2.actions.canDispatch ||
              d2.actions.canReport ||
              d2.actions.canCancel ||
              d2.actions.canReassign,
          isFalse,
        );
      },
    );

    test('şoför değiştir ve iptal', () async {
      final (_, _, repo) = await _as('sevkiyat');
      final board = await repo.board();
      final planned = board.shipments.firstWhere(
        (s) => s.status == ShipmentStatus.planned,
      );
      await repo.assignDriver(
        planned.id,
        driverUserId: 'u-sofor2',
        vehiclePlate: '34 XY 1234',
        idempotencyKey: 'assign-1',
      );
      final d = await repo.shipmentDetail(planned.id);
      expect(d.driverUserId, 'u-sofor2');
      expect(d.isAppDriver, isFalse);
      expect(d.vehiclePlate, '34 XY 1234');
      await repo.cancelShipment(planned.id);
      expect(
        (await repo.shipmentDetail(planned.id)).status,
        ShipmentStatus.cancelled,
      );
    });

    test('Sevkiyatlar listesi: itirazlı ve bugünkü yüklemeler', () async {
      final (_, _, repo) = await _as('depo');
      final disputes = await repo.shipments(
        const ShipmentListFilter(hasDispute: true),
      );
      expect(disputes.items, isNotEmpty);
      expect(disputes.items.every((s) => s.disputeNote != null), isTrue);
      final loads = await repo.shipments(
        ShipmentListFilter.todayLoadingsFilter(),
      );
      final today = TrTime.todayStart();
      expect(loads.items, isNotEmpty);
      expect(
        loads.items.every(
          (s) =>
              TrTime.isSameDay(s.scheduledAt!, today) &&
              (s.status == ShipmentStatus.planned ||
                  s.status == ShipmentStatus.inTransit),
        ),
        isTrue,
      );
      final accepted = await repo.shipments(
        const ShipmentListFilter(statuses: {ShipmentStatus.accepted}),
      );
      expect(
        accepted.items.every((s) => s.status == ShipmentStatus.accepted),
        isTrue,
      );
      expect(accepted.countAccepted, accepted.totalFiltered);
    });
  });

  group('Ekip', () {
    test('liste, pasifleştir, şifre bağlantısı', () async {
      final (h, _, repo) = await _as('sahip');
      final staff = await repo.staff();
      expect(staff.length, greaterThan(10));
      final driver = staff.firstWhere((m) => m.userId == 'u-sofor2');
      expect(driver.roles.single.isDriver, isTrue);
      expect(driver.lastLoginAt, isNull);
      await repo.setStaffActive('u-sofor2', false);
      expect(
        (await repo.staff()).firstWhere((m) => m.userId == 'u-sofor2').isActive,
        isFalse,
      );
      await expectLater(
        repo.sendPasswordReset('u-sofor2'),
        throwsA(isA<BusinessFailure>()),
      );
      await repo.sendPasswordReset('u-sofor3');
      expect(fakePasswordResets(h.world), ['u-sofor3']);
      await expectLater(
        repo.setStaffActive('u-sahip', false),
        throwsA(isA<BusinessFailure>()),
      );
    });

    test('Ekip yetkisi olmayan: 403', () async {
      final (_, _, repo) = await _as('sevkiyat');
      await expectLater(repo.staff(), throwsA(isA<ForbiddenFailure>()));
    });
  });
}
