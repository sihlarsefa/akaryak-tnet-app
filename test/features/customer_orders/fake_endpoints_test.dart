// A2 sahte uçları: §B biçimi, durumlu akışlar (sipariş verme → dünya, şirket içi talep, kısmi sonuç,
// aynı anahtarın tekrarı, teklif kararı kuralları, şablonlar) ve JSON → model ayrıştırma.
import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/network/api_client.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/customer_orders/data/customer_orders_repository.dart';
import 'package:akaryakitnet/features/customer_orders/data/form_models.dart';
import 'package:akaryakitnet/features/customer_orders/data/home_models.dart';
import 'package:akaryakitnet/features/customer_orders/data/order_models.dart';
import 'package:akaryakitnet/features/customer_orders/data/payment_models.dart';
import 'package:akaryakitnet/features/customer_orders/data/place_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/a2_support.dart';

void main() {
  late A2Env env;
  late ProviderContainer c;
  late CustomerOrdersRepository repo;
  late ApiClient api;

  Future<void> signIn(String persona) async {
    c = await env.signedIn(persona);
    addTearDown(c.dispose);
    repo = c.read(customerOrdersRepositoryProvider);
    api = c.read(apiClientProvider);
  }

  PlaceOrderRequest request({
    int stationId = 1,
    List<PlaceOrderLine>? lines,
    PaymentSelection? payment,
    String? groupKey,
    String? note,
    int? templateId,
  }) => PlaceOrderRequest(
    stationId: stationId,
    deliveryPointId: 1001,
    requestedDeliveryDate: TrTime.addDays(TrTime.todayStart(), 1),
    lines: lines ?? const [PlaceOrderLine(productId: 1, quantityLiters: 5000)],
    payment: payment,
    paymentGroupKey: groupKey,
    note: note,
    templateId: templateId,
  );

  setUp(() async {
    env = await A2Env.create();
  });

  group('home/customer', () {
    test(
      'Yönetici: bayiler, limitler, şablonlar, belge hatırlatması, öneri tarihi',
      () async {
        await signIn('musteri');
        final home = await repo.home();
        expect(home.customerTitle, 'Anadolu Lojistik A.Ş.');
        expect(home.stations.map((s) => s.id), [1, 2]);
        expect(home.stationId, 1);
        expect(home.station?.title, 'Demir Petrol Akaryakıt Ltd. Şti.');
        expect(home.station?.whatsappNumber, '905321230001');
        expect(home.canOrder, isTrue);
        expect(home.companyApproval, isNull, reason: 'yalnızca Talep eden');
        expect(home.templates, hasLength(3));
        expect(home.templates.first.name, 'Haftalık motorin – Pendik');
        expect(home.limits, hasLength(2));
        final l = home.limits.firstWhere((x) => x.hasLimit);
        expect(l.unit, 'TL');
        expect(l.usedPct, closeTo(47.2, 0.01));
        expect(
          home.limits.firstWhere((x) => !x.hasLimit).periodLabel,
          'Limitsiz',
        );
        expect(home.minDeliveryDate, TrTime.addDays(TrTime.todayStart(), 1));
        expect(home.suggestedDeliveryDate, home.minDeliveryDate);
        expect(home.dashboard.pendingDecisions, isNotEmpty);
        expect(home.dashboard.pendingDecisionTotal, 1);
        expect(home.dashboard.activeShipment?.status, ShipmentStatus.inTransit);
        expect(home.pendingPaymentDocuments, hasLength(1));
        final doc = home.pendingPaymentDocuments.single;
        expect(doc.kind, AttachmentKind.chequeImage);
        expect(doc.target.isUploadable, isTrue);
        expect(doc.target.ownerType, AttachmentOwnerType.order);
      },
    );

    test(
      'Talep eden: şirket içi onay kuralı gelir; Onaylayan bekleyen talebi görür',
      () async {
        await signIn('talep');
        final home = await repo.home();
        expect(home.companyApproval?.required, isTrue);
        expect(home.companyApproval?.aboveLitres, 20000);
        expect(
          home.companyApproval!.predicts(
            totalLiters: 25000,
            estimatedAmount: 1,
          ),
          isTrue,
        );
        expect(
          home.companyApproval!.predicts(
            totalLiters: 5000,
            estimatedAmount: 210000,
          ),
          isFalse,
        );
        expect(home.companyApprovalsWaiting, 0);
      },
    );

    test('Onaylayan şirket içi bekleyen talepleri sayar', () async {
      await signIn('onay');
      final home = await repo.home();
      expect(home.companyApproval, isNull);
      expect(home.companyApprovalsWaiting, 1);
    });

    test('bayi kullanıcısı müşteri ana sayfasını açamaz (403)', () async {
      await signIn('sahip');
      await expectLater(repo.home(), throwsA(isA<ForbiddenFailure>()));
    });
  });

  group('Siparişlerim', () {
    test(
      'bölümler: karar bekleyen / aktif / geçmiş; arama Türkçe duyarsız',
      () async {
        await signIn('musteri');
        final decision = await repo.orders(segment: OrderSegment.decision);
        expect(decision.items, hasLength(1));
        final row = decision.items.single;
        expect(row.status, OrderStatus.awaitingApproval);
        expect(row.quotedUnitPrice, 42.35);
        expect(row.paymentDocumentMissing, isTrue);
        expect(row.expiresAt, isNotNull);
        expect(row.paymentMethodName, 'Çek');
        final active = await repo.orders(segment: OrderSegment.active);
        expect(
          active.items.map((r) => r.status).toSet(),
          everyElement(isIn([OrderStatus.awaitingQuote, OrderStatus.approved])),
        );
        final inTransit = active.items.firstWhere(
          (r) => r.activeShipmentStatus == ShipmentStatus.inTransit,
        );
        expect(inTransit.activeShipmentStatusLabel, 'Yolda');
        final history = await repo.orders(segment: OrderSegment.history);
        expect(history.items.single.status, OrderStatus.completed);
        final search = await repo.orders(
          segment: OrderSegment.active,
          q: 'TUZLA',
        );
        expect(search.items, isNotEmpty);
        expect(
          search.items.every(
            (r) => (r.deliveryPointName ?? '').contains('Tuzla'),
          ),
          isTrue,
        );
      },
    );
  });

  group('sipariş formu ve ödeme seçenekleri', () {
    test(
      'noktalar pencere, tank ve erişim notlarıyla; TimeSpan biçimi',
      () async {
        await signIn('musteri');
        final form = OrderFormOptions.fromJson(await repo.orderFormRaw());
        expect(form.products.map((p) => p.name), contains('Motorin'));
        final pendik = form.point(1001)!;
        expect(pendik.windowLabel, '08:00–18:00');
        expect(pendik.tankCapacityLiters, 30000);
        expect(pendik.accessNotes, contains('güvenliğe'));
        expect(pendik.hasLocation, isTrue);
        expect(form.templates, hasLength(3));
        expect(parseTimeOfDayMinutes('1.00:00:00'), 1440);
        expect(formatTimeOfDay(1440), '24:00');
      },
    );

    test(
      'ödeme seçenekleri: çek şeması, avans bakiyesi, bağlı bayide fiyat',
      () async {
        await signIn('musteri');
        final o = await repo.paymentOptions(stationId: 1, productIds: [1, 2]);
        expect(o.options.enabled, isTrue);
        expect(o.options.defaultMethodCode, 'HAVALE');
        final cek = o.options.method('CEK')!;
        expect(cek.isInstrument, isTrue);
        expect(cek.requiresFinance, isTrue);
        expect(cek.documentKind, AttachmentKind.chequeImage);
        expect(cek.maxTermDays, 180);
        expect(cek.field('amount')?.type, 'money');
        expect(cek.field('dueDate')?.required, isTrue);
        expect(o.options.advanceBalance, 250000);
        expect(o.unitPrices[1], 42.10);
        final kart = o.options.method('KART')!;
        expect(kart.hasInstallments, isTrue);
        expect(kart.termLabel, 'Peşin, taksit seçenekli');
        final other = await repo.paymentOptions(stationId: 2, productIds: [1]);
        expect(other.unitPrices[1], closeTo(42.45, 0.0001));
        expect(other.options.method('CEK'), isNull);
      },
    );
  });

  group('orders/place', () {
    test(
      'doğrudan sipariş: dünyaya eklenir, teklif masasına düşer, şablon kullanıldı işaretlenir',
      () async {
        await signIn('musteri');
        final before = env.world.orders.length;
        final r = await repo.place(
          request(
            payment: const PaymentSelection(methodCode: 'HAVALE', termDays: 0),
            templateId: 703,
          ),
          idempotencyKey: 'k-direct',
        );
        expect(r.kind, PlaceOrderResult.kindOrders);
        expect(r.orders, hasLength(1));
        expect(r.partialError, isNull);
        expect(r.message, startsWith('Sipariş oluşturuldu: SIP-'));
        expect(r.paymentDocument?.kind, AttachmentKind.transferReceipt);
        expect(r.paymentDocument?.required, isFalse);
        expect(env.world.orders.length, before + 1);
        final o = env.world.order(r.orders.single.orderId)!;
        expect(o['status'], 1);
        expect(o['paymentMethodCode'], 'HAVALE');
        expect(o['createdByUserId'], 'u-musteri');
        final templates = await repo.templates();
        expect(templates.first.id, 703, reason: 'son kullanılan öne geçer');
        final bayiNotified = env.world.notifications.any(
          (n) => n['userId'] == 'u-sahip' && n['eventCode'] == 'order.created',
        );
        expect(bayiNotified, isTrue);
      },
    );

    test(
      'aynı anahtar: ikinci istek sipariş oluşturmaz, aynı sonucu döner',
      () async {
        await signIn('musteri');
        final before = env.world.orders.length;
        final a = await repo.place(request(), idempotencyKey: 'k-same');
        final b = await repo.place(request(), idempotencyKey: 'k-same');
        expect(b.orders.single.orderId, a.orders.single.orderId);
        expect(env.world.orders.length, before + 1);
      },
    );

    test('anahtarsız istek reddedilir', () async {
      await signIn('musteri');
      await expectLater(
        api.post('orders/place', body: request().toJson(), parse: (j) => j),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test(
      'çek: finans onayına düşer, belge hedefi zorunlu, grup anahtarı çok satırda',
      () async {
        await signIn('musteri');
        final r = await repo.place(
          request(
            lines: const [
              PlaceOrderLine(productId: 1, quantityLiters: 5000),
              PlaceOrderLine(productId: 2, quantityLiters: 3000),
            ],
            payment: PaymentSelection(
              methodCode: 'CEK',
              termDays: 30,
              details: {
                'serialNo': 'A123',
                'bank': 'Ziraat',
                'drawer': 'Anadolu Lojistik',
                'amount': '344050.00',
                // Vade bugüne göre (teslim + 30 gün civarı); sabit tarih zamanla geçmişte kalırdı.
                'dueDate': TrTime.isoDate(
                  TrTime.addDays(TrTime.todayStart(), 41),
                ),
              },
            ),
          ),
          idempotencyKey: 'k-cek',
        );
        expect(r.orders, hasLength(2));
        expect(r.financePendingCount, 2);
        expect(r.message, contains('finans onayına gönderildi'));
        expect(r.paymentGroupKey, isNotNull);
        expect(
          r.orders.every((o) => o.paymentGroupKey == r.paymentGroupKey),
          isTrue,
        );
        expect(r.paymentDocument?.kind, AttachmentKind.chequeImage);
        expect(r.paymentDocument?.required, isTrue);
        expect(r.paymentDocument?.isUploadable, isTrue);
        final target = await repo.documentTarget(
          methodCode: 'CEK',
          orderIds: r.orders.map((o) => o.orderId),
        );
        expect(target?.ownerId, r.orders.first.orderId);
        expect(
          env.world.approvals.where((a) => a['type'] == 4 && a['status'] == 0),
          hasLength(greaterThanOrEqualTo(3)),
        );
      },
    );

    test('belge gerektirmeyen yöntemde hedef 204 → null', () async {
      await signIn('musteri');
      final r = await repo.place(
        request(
          payment: const PaymentSelection(methodCode: 'NAKIT', termDays: 0),
        ),
        idempotencyKey: 'k-cash',
      );
      final t = await repo.documentTarget(orderIds: [r.orders.single.orderId]);
      expect(t, isNull);
    });

    test(
      'kısmi sonuç: ilk satır oluşur, ikinci satır hatası + failedLineIndex',
      () async {
        await signIn('musteri');
        env.controls.failLineAt = 1;
        final r = await repo.place(
          request(
            lines: const [
              PlaceOrderLine(productId: 1, quantityLiters: 1000),
              PlaceOrderLine(productId: 2, quantityLiters: 2000),
            ],
            payment: const PaymentSelection(methodCode: 'HAVALE', termDays: 0),
          ),
          idempotencyKey: 'k-partial',
        );
        expect(r.isPartial, isTrue);
        expect(r.orders, hasLength(1));
        expect(r.failedLineIndex, 1);
        expect(r.partialError, startsWith('Satır 2:'));
        expect(r.paymentGroupKey, isNotNull);
        // Kalan satır yeni anahtar + aynı grupla.
        final rest = await repo.place(
          request(
            lines: const [PlaceOrderLine(productId: 2, quantityLiters: 2000)],
            payment: const PaymentSelection(methodCode: 'HAVALE', termDays: 0),
            groupKey: r.paymentGroupKey,
          ),
          idempotencyKey: 'k-rest',
        );
        expect(rest.orders.single.paymentGroupKey, r.paymentGroupKey);
      },
    );

    test('ilk satır hatası: 400 ve hiçbir sipariş oluşmaz', () async {
      await signIn('musteri');
      env.controls.failLineAt = 0;
      final before = env.world.orders.length;
      await expectLater(
        repo.place(request(), idempotencyKey: 'k-first'),
        throwsA(isA<BusinessFailure>()),
      );
      expect(env.world.orders.length, before);
    });

    test(
      'kaydedip 500: aynı anahtarla tekrar kaydı döner, çift sipariş yok',
      () async {
        await signIn('musteri');
        env.controls.commitThenServerError = true;
        final before = env.world.orders.length;
        await expectLater(
          repo.place(request(), idempotencyKey: 'k-500'),
          throwsA(isA<ServerFailure>()),
        );
        expect(env.world.orders.length, before + 1);
        final replay = await repo.place(request(), idempotencyKey: 'k-500');
        expect(replay.orders, hasLength(1));
        expect(env.world.orders.length, before + 1);
      },
    );

    test(
      'Talep eden eşik üstü: şirket içi talep + onaycıya bildirim; not talebe yazılır',
      () async {
        await signIn('talep');
        final before = env.world.orders.length;
        final r = await repo.place(
          request(
            lines: const [PlaceOrderLine(productId: 1, quantityLiters: 25000)],
            payment: PaymentSelection(
              methodCode: 'CEK',
              termDays: 30,
              details: {
                'serialNo': 'B1',
                'bank': 'Halkbank',
                'drawer': 'Anadolu',
                'amount': '1052500.00',
                'dueDate': TrTime.isoDate(
                  TrTime.addDays(TrTime.todayStart(), 55),
                ),
              },
            ),
            note: 'Acil ihtiyaç',
          ),
          idempotencyKey: 'k-req',
        );
        expect(r.isCompanyRequest, isTrue);
        expect(
          r.companyRequest?.message,
          contains('şirket içi onaya gönderildi'),
        );
        expect(r.paymentDocument?.isUploadable, isFalse);
        expect(r.paymentDocument?.message, contains('çek görselini'));
        expect(env.world.orders.length, before);
        final req = env.world
            .bag<List<Map<String, dynamic>>>('company.orderRequests', () => [])
            .last;
        expect(req['note'], 'Acil ihtiyaç');
        expect(
          env.world.notifications.any(
            (n) =>
                n['userId'] == 'u-onay' && n['eventCode'] == 'approval.pending',
          ),
          isTrue,
        );
      },
    );

    test('Talep eden eşik altı: doğrudan sipariş, not yok sayılır', () async {
      await signIn('talep');
      final r = await repo.place(
        request(note: 'kullanılmaz'),
        idempotencyKey: 'k-req-small',
      );
      expect(r.kind, PlaceOrderResult.kindOrders);
    });

    test('doğrulama: geçmiş tarih, başka carinin noktası', () async {
      await signIn('musteri');
      await expectLater(
        repo.place(
          PlaceOrderRequest(
            stationId: 1,
            deliveryPointId: 1001,
            requestedDeliveryDate: TrTime.addDays(TrTime.todayStart(), -2),
            lines: const [PlaceOrderLine(productId: 1, quantityLiters: 10)],
          ),
          idempotencyKey: 'k-past',
        ),
        throwsA(
          isA<BusinessFailure>().having(
            (f) => f.message,
            'message',
            'Teslim tarihi bugünden önce olamaz.',
          ),
        ),
      );
      await expectLater(
        repo.place(
          request(
            lines: const [
              PlaceOrderLine(productId: 1, quantityLiters: 10),
              PlaceOrderLine(
                productId: 1,
                quantityLiters: 10,
                deliveryPointId: 1003,
              ),
            ],
          ),
          idempotencyKey: 'k-point',
        ),
        throwsA(
          isA<BusinessFailure>().having(
            (f) => f.message,
            'message',
            'Satır 2: Teslimat noktası geçersiz.',
          ),
        ),
      );
    });
  });

  group('sipariş ayrıntısı ve takip', () {
    test(
      'ayrıntı + takip: adımlar, yoldaki sevkiyat, önceki alımlar',
      () async {
        await signIn('musteri');
        final o2 = env.world.orders.firstWhere((o) => o['status'] == 2);
        final tracking = OrderTracking.fromJson(
          await repo.trackingRaw(o2['id'] as int),
        );
        expect(tracking.steps.map((s) => s.key), [
          'received',
          'quote',
          'approval',
          'dispatch',
          'delivered',
        ]);
        expect(tracking.steps[2].state, TrackingState.current);
        expect(tracking.steps[2].detail, 'Kararınız bekleniyor');
        final cmp = tracking.priceComparison!;
        expect(cmp.currentUnitPriceTry, 42.35);
        expect(cmp.hasHistory, isTrue);
        expect(cmp.previous.first.diffPercent, isNotNull);

        final o3 = env.world.orders.firstWhere(
          (o) => o['status'] == 3 && o['customerId'] == 101,
        );
        final t3 = OrderTracking.fromJson(
          await repo.trackingRaw(o3['id'] as int),
        );
        expect(t3.hasInTransit, isTrue);
        expect(t3.activeShipment?.status, ShipmentStatus.inTransit);
        expect(t3.activeShipment?.vehiclePlate, '41 DMR 101');
        expect(t3.steps[3].state, TrackingState.done);
        expect(t3.canAcceptDeliveries, isTrue);
      },
    );

    test('başka carinin siparişi 404', () async {
      await signIn('musteri');
      final other = env.world.orders.firstWhere((o) => o['customerId'] == 102);
      await expectLater(
        repo.order(other['id'] as int),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  group('teklif kararı', () {
    late int o2;

    setUp(() {
      o2 = env.world.orders.firstWhere((o) => o['status'] == 2)['id'] as int;
    });

    int latestQuote() =>
        ((env.world.order(o2)!['quotes'] as List).last as Map)['id'] as int;

    test('çek görseli yokken onay reddedilir; yüklenince onaylanır', () async {
      await signIn('musteri');
      await expectLater(
        repo.decide(
          o2,
          QuoteAction.approve,
          expectedQuoteId: latestQuote(),
          idempotencyKey: 'd-1',
        ),
        throwsA(
          isA<BusinessFailure>().having(
            (f) => f.message,
            'message',
            startsWith('Çek görseli yüklenmeden teklif onaylanamaz.'),
          ),
        ),
      );
      env.world.attachments.add({
        'publicId': 'p-1',
        'ownerType': 1,
        'ownerId': o2,
        'kind': 1,
        'isActive': true,
      });
      await repo.decide(
        o2,
        QuoteAction.approve,
        expectedQuoteId: latestQuote(),
        idempotencyKey: 'd-2',
      );
      expect(env.world.order(o2)!['status'], 3);
      final sent = env.controls.decisionRequests.last;
      expect(sent.key, 'd-2');
      expect(sent.body['expectedQuoteId'], latestQuote());
    });

    test('ekranda görülen teklif eski: 409 concurrency_conflict', () async {
      await signIn('musteri');
      await expectLater(
        repo.decide(
          o2,
          QuoteAction.reject,
          expectedQuoteId: 1,
          idempotencyKey: 'd-3',
        ),
        throwsA(
          isA<ConflictFailure>().having(
            (f) => f.isConcurrency,
            'isConcurrency',
            isTrue,
          ),
        ),
      );
    });

    test('revize notsuz reddedilir; notlu revize nota yazılır', () async {
      await signIn('musteri');
      await expectLater(
        repo.decide(o2, QuoteAction.revise, idempotencyKey: 'd-4'),
        throwsA(isA<BusinessFailure>()),
      );
      await repo.decide(
        o2,
        QuoteAction.revise,
        note: 'Fiyat yüksek, indirim rica ederiz',
        idempotencyKey: 'd-5',
      );
      final o = env.world.order(o2)!;
      expect(o['status'], 5);
      expect(
        ((o['quotes'] as List).last as Map)['revisionNote'],
        'Fiyat yüksek, indirim rica ederiz',
      );
    });
  });

  group('şablonlar', () {
    test('liste, ayrıntı, siparişten taslak, kaydet, sil', () async {
      await signIn('musteri');
      final list = await repo.templates();
      expect(list.map((t) => t.name), contains('Şantiye ikmali (2 nokta)'));
      final t = await repo.template(702);
      expect(t.lines, hasLength(2));
      expect(t.lines.every((l) => l.isAvailable), isTrue);
      final o3 = env.world.orders.firstWhere(
        (o) => o['status'] == 3 && o['customerId'] == 101,
      );
      final draft = await repo.templateFromOrder(o3['id'] as int);
      expect(draft.id, 0);
      expect(draft.lines.single.productId, 1);
      final saved = await repo.saveTemplate(
        name: 'Yeni şablon',
        lines: [
          for (final l in draft.lines)
            (
              productId: l.productId,
              deliveryPointId: l.deliveryPointId,
              liters: l.quantityLiters,
              stationId: l.stationId,
            ),
        ],
      );
      expect(saved.id, greaterThan(0));
      expect(
        (await repo.templates()).map((x) => x.name),
        contains('Yeni şablon'),
      );
      await repo.deleteTemplate(saved.id);
      expect(
        (await repo.templates()).map((x) => x.name),
        isNot(contains('Yeni şablon')),
      );
    });
  });

  test('ordering-status: bağlı olmayan bayi', () async {
    await signIn('musteri');
    final s = await repo.orderingStatus(99);
    expect(s.canOrder, isFalse);
    expect(s.blockReason, 'Bu bayiyle aktif bağlantınız yok.');
    final ok = await repo.orderingStatus(1);
    expect(ok.canOrder, isTrue);
    expect(ok.stationCustomerId, 501);
  });

  test('PaymentUploadTarget.tryParse: boş gövde (204) null', () {
    expect(PaymentUploadTarget.tryParse(''), isNull);
    expect(PaymentUploadTarget.tryParse(null), isNull);
    expect(CustomerHomeData.fromJson(const {}).stations, isEmpty);
  });
}
