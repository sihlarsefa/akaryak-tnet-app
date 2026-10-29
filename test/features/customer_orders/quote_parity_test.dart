// Panel eşitliği (sahip: "panel tarafıyla uygulama tamamen birlikte çalışsın"): teklif kararı ve
// teslim kabulü web müşteri sipariş ayrıntısıyla (`CustomerController.OrderDetail`) tek kural. Her
// şirket rolü (eski / rolsüz, Talep eden, Onaylayan, Yönetici) × eşik (yok, altında, üstünde) × yetki
// (Teklifler / Sevkiyatlar "Düzenler" var, yok) için uygulama panelin gösterdiğini gösterir: aynı
// düğmeler, onay kilitliyken aynı not, onay yine denenirse sunucunun aynı metni. "Sıra sizde", rozet
// ve Bende teklifi ya da teslimatı yalnızca kullanılabilir karar varken sayar. Sunucunun yeni alanları
// (`canDecideQuote`, `canApproveQuote`, `approveBlockedReason`, `canAcceptDelivery`) yoksa (yayındaki
// eski API) yedek kural aynı sonucu verir.
import 'dart:convert';
import 'dart:io';

import 'package:akaryakitnet/app/tasks/task_inbox.dart';
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/auth/permissions.dart';
import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/network/fake/fake_parity.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/customer_home/customer_home_fake.dart';
import 'package:akaryakitnet/features/customer_orders/api.dart';
import 'package:akaryakitnet/features/customer_orders/data/order_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/a2_support.dart';

const _msg = OrdersCopy.requesterApproveBlocked;

/// Şirketin onay eşiğine göre teklif.
enum _Th { none, below, above }

/// Panelin kuralı, testte bağımsız yazılmış hâli (sipariş "Onay bekliyor"; onaylı siparişte kabul
/// bekleyen sevkiyat): karar = Teklifler "Düzenler"; onay kilidi = Talep eden ve eşik aşılmış; teslim
/// kabulü = Sevkiyatlar "Düzenler". Şirket rolü yalnızca onay kilidinde anlamlıdır.
({bool decide, bool approve, String? note, bool accept}) _panel(
  int? role,
  _Th th, {
  required bool quotes,
  required bool shipments,
}) {
  final locked = quotes && role == 1 && th == _Th.above;
  return (
    decide: quotes,
    approve: quotes && !locked,
    note: locked ? _msg : null,
    accept: shipments,
  );
}

AccessPolicy _policy(
  int? role, {
  required bool quotes,
  required bool shipments,
}) => AccessPolicy(
  MeAccess.fromJson({
    'userId': 'u-matris',
    'userName': 'matris',
    'persona': Persona.customer.code,
    'roles': ['Customer'],
    'customerId': 101,
    'customerUserRole': role,
    'pages': [
      '${Pg.customerOrders}:${Perm.view}',
      '${Pg.customerQuotes}:${Perm.view}',
      if (quotes) '${Pg.customerQuotes}:${Perm.edit}',
      '${Pg.customerShipments}:${Perm.view}',
      if (shipments) '${Pg.customerShipments}:${Perm.edit}',
    ],
  }),
);

/// Canlı fikstürdeki eşik (10.000 L / 400.000 ₺); "yok" kural kapalıdır.
CompanyApprovalRule _rule(_Th th) => th == _Th.none
    ? const CompanyApprovalRule()
    : const CompanyApprovalRule(
        required: true,
        aboveLitres: 10000,
        aboveAmount: 400000,
      );

/// Siparişin litresi ve son teklifin tutarı: eşik altı ya da üstü.
(double, double) _quote(_Th th) =>
    th == _Th.above ? (15000, 630300) : (5400, 217836);

/// Bir teklif ve bir kabul bekleyen teslimatlık ana sayfa; [fields] sunucunun yeni alanları.
CustomerHomeData _home(
  _Th th,
  ({bool decide, bool approve, String? note, bool accept}) want, {
  required bool fields,
}) {
  final (liters, total) = _quote(th);
  return CustomerHomeData(
    customerId: 101,
    customerTitle: 'Anadolu Lojistik A.Ş.',
    stations: const [StationOption(id: 1, title: 'Demir Petrol')],
    dashboard: CustomerDashboard(
      pendingDecisions: [
        DashboardOrderRow(
          orderId: 1,
          orderNumber: 'SIP-1',
          status: OrderStatus.awaitingApproval,
          quantityLiters: liters,
          latestTotalAmountTry: total,
          productName: 'Motorin',
          canDecideQuote: fields ? want.decide : null,
          canApproveQuote: fields ? want.approve : null,
          approveBlockedReason: fields ? want.note : null,
        ),
      ],
      shipments: [
        DashboardShipmentRow(
          shipmentId: 9,
          orderId: 2,
          orderNumber: 'SIP-2',
          status: ShipmentStatus.reported,
          plannedLiters: 5000,
          productName: 'Motorin',
          canAcceptDelivery: fields ? want.accept : null,
        ),
      ],
    ),
  );
}

void main() {
  group('kural (saf): rol × eşik × yetki = panel', () {
    const roles = <(String, int?)>[
      ('eski (rolsüz)', null),
      ('Talep eden', 1),
      ('Onaylayan', 2),
      ('Yönetici', 3),
    ];
    for (final (name, role) in roles) {
      for (final th in _Th.values) {
        for (final (quotes, shipments) in const [
          (true, true),
          (false, true),
          (true, false),
          (false, false),
        ]) {
          test('$name · eşik ${th.name} · Teklifler ${quotes ? 'Düzenler' : 'yok'} · '
              'Sevkiyatlar ${shipments ? 'Düzenler' : 'yok'}', () {
            final want = _panel(role, th, quotes: quotes, shipments: shipments);
            final policy = _policy(role, quotes: quotes, shipments: shipments);
            // Sunucu şirket içi kuralı yalnızca talep edene gönderir (`home/customer`).
            final decider = CustomerDecider.of(
              policy,
              companyRule: role == 1 ? _rule(th) : null,
            );
            final (liters, total) = _quote(th);

            // 1. Yedek kural (yayındaki eski API: alan yok).
            final fallback = decider.quote(
              status: OrderStatus.awaitingApproval,
              liters: liters,
              total: total,
            );
            expect(fallback.canDecide, want.decide, reason: 'karar');
            expect(fallback.canApprove, want.approve, reason: 'onay');
            expect(fallback.blockedReason, want.note, reason: 'not');
            expect(fallback.approveBlocked, want.note != null);
            expect(fallback.yourMove, want.approve, reason: 'sıra sizde');
            expect(decider.acceptsDelivery(eligible: true), want.accept);

            // 2. Sunucunun değerleri aynen (görüntüleyenin yerel verisi ne derse desin).
            for (final local in [decider, CustomerDecider.full]) {
              final server = local.quote(
                status: OrderStatus.awaitingApproval,
                liters: liters,
                total: total,
                canDecideQuote: want.decide,
                canApproveQuote: want.approve,
                approveBlockedReason: want.note,
              );
              expect(server, fallback);
              expect(
                local.acceptsDelivery(server: want.accept, eligible: true),
                want.accept,
              );
            }

            // 3. Sayılar (ana sayfa = Onaylar rozeti = Bende): teklif onay açıkken, teslimat
            // kabul edilebilirken; alanlar olsa da olmasa da aynı.
            for (final fields in [true, false]) {
              final tasks = buildCustomerTasks(
                home: _home(th, want, fields: fields),
                decider: decider,
              );
              expect(
                tasks.where((t) => t.kind == TaskKind.quoteDecision),
                hasLength(want.approve ? 1 : 0),
                reason: 'teklif (alanlar: $fields)',
              );
              expect(
                tasks.where((t) => t.kind == TaskKind.deliveryAcceptance),
                hasLength(want.accept ? 1 : 0),
                reason: 'teslimat (alanlar: $fields)',
              );
            }
          });
        }
      }
    }

    test(
      'onaylayan ve yönetici, kural gelse de kilitlenmez (rol eşiğe tabi değil)',
      () {
        for (final role in [null, 2, 3]) {
          final decider = CustomerDecider.of(
            _policy(role, quotes: true, shipments: true),
            companyRule: _rule(_Th.above),
          );
          final (liters, total) = _quote(_Th.above);
          final r = decider.quote(
            status: OrderStatus.awaitingApproval,
            liters: liters,
            total: total,
          );
          expect(r.canApprove, isTrue, reason: 'rol $role');
        }
      },
    );

    test(
      'talep eden, kural bilinmiyor (eski API, ana sayfa yok): onay panel gibi açık ama sayılmaz; '
      'sunucu reddederse kilit',
      () {
        final decider = CustomerDecider.of(
          _policy(1, quotes: true, shipments: true),
        );
        final (liters, total) = _quote(_Th.below);
        final r = decider.quote(
          status: OrderStatus.awaitingApproval,
          liters: liters,
          total: total,
        );
        expect(r.canDecide, isTrue);
        expect(r.canApprove, isTrue, reason: 'panel: kural okunamazsa açık');
        expect(r.certain, isFalse);
        expect(r.yourMove, isFalse, reason: 'ölü "Sıra sizde" yok');
        final tasks = buildCustomerTasks(
          home: _home(_Th.below, (
            decide: true,
            approve: true,
            note: null,
            accept: true,
          ), fields: false),
          decider: decider,
        );
        expect(tasks.where((t) => t.kind == TaskKind.quoteDecision), isEmpty);
        final refused = r.refused(_msg);
        expect(refused.canDecide, isTrue);
        expect(refused.canApprove, isFalse);
        expect(refused.blockedReason, _msg);
        expect(refused.approveBlocked, isTrue);
      },
    );

    test('"Onay bekliyor" dışında karar yok; finans kilidi teklifi saymaz', () {
      for (final s in OrderStatus.values) {
        if (s == OrderStatus.awaitingApproval) continue;
        expect(
          CustomerDecider.full.quote(status: s, liters: 1000),
          QuoteRights.none,
          reason: s.name,
        );
      }
      for (final finance in [
        OrderFinanceStatus.pending,
        OrderFinanceStatus.infoRequested,
      ]) {
        final home = CustomerHomeData(
          customerId: 101,
          customerTitle: 'Anadolu Lojistik A.Ş.',
          dashboard: CustomerDashboard(
            pendingDecisions: [
              DashboardOrderRow(
                orderId: 1,
                orderNumber: 'SIP-1',
                status: OrderStatus.awaitingApproval,
                quantityLiters: 5000,
                financeStatus: finance,
                canDecideQuote: true,
                canApproveQuote: true,
              ),
            ],
          ),
        );
        expect(
          buildCustomerTasks(home: home, decider: CustomerDecider.full),
          isEmpty,
          reason: finance.name,
        );
      }
    });

    test('ayrıntı: tutar en yüksek sürümdeki teklifin (panelin ifadesi)', () {
      final decider = CustomerDecider.of(
        _policy(1, quotes: true, shipments: true),
        companyRule: _rule(_Th.below),
      );
      OrderDetail detail(double v1, double v2) => OrderDetail.fromJson({
        'id': 7,
        'orderNumber': 'SIP-7',
        'status': 2,
        'quantityLiters': 5000,
        'customerId': 101,
        'stationId': 1,
        'productId': 1,
        'deliveryPointId': 1001,
        'quotes': [
          {'id': 2, 'version': 2, 'unitPriceTry': 16, 'totalAmountTry': v2},
          {'id': 1, 'version': 1, 'unitPriceTry': 160, 'totalAmountTry': v1},
        ],
      });
      // v1 800.000 ₺ → revize → v2 80.000 ₺: eşik (400.000 ₺) altında, onay açık.
      expect(decider.quoteOfDetail(detail(800000, 80000)).canApprove, isTrue);
      expect(decider.quoteOfDetail(detail(80000, 800000)).blockedReason, _msg);
    });

    test(
      'teslim kabulü: sunucunun değeri; yoksa onaylı siparişte kabul bekleyen ve yetki',
      () {
        ShipmentListItem item(int status, int orderStatus, {bool? flag}) =>
            ShipmentListItem.fromJson(
              JsonReader.of({
                'id': 1,
                'orderId': 2,
                'orderNumber': 'SIP-2',
                'plannedLiters': 1000,
                'status': status,
                'orderStatus': orderStatus,
                'canAcceptDelivery': ?flag,
              }),
              customer: true,
            );
        final yes = CustomerDecider.of(
          _policy(1, quotes: false, shipments: true),
        );
        final no = CustomerDecider.of(
          _policy(3, quotes: true, shipments: false),
        );
        expect(yes.acceptsListItem(item(2, 3)), isTrue);
        expect(
          yes.acceptsListItem(item(2, 7)),
          isFalse,
          reason: 'sipariş kapalı',
        );
        expect(yes.acceptsListItem(item(1, 3)), isFalse, reason: 'yolda');
        expect(no.acceptsListItem(item(2, 3)), isFalse);
        expect(no.acceptsListItem(item(2, 3, flag: true)), isTrue);
        expect(yes.acceptsListItem(item(2, 3, flag: false)), isFalse);
        // Bayi listesi alanı okumaz (sunucu bayide boş bırakır).
        final bayi = ShipmentListItem.fromJson(
          JsonReader.of({
            'id': 1,
            'orderId': 2,
            'orderNumber': 'SIP-2',
            'plannedLiters': 1000,
            'status': 2,
            'canAcceptDelivery': true,
          }),
        );
        expect(bayi.canAcceptDelivery, isNull);
        // Siparişler satırı: etkin sevkiyat kabul bekliyor.
        CustomerOrderRow row(int status, int? shipment, {bool? flag}) =>
            CustomerOrderRow.fromJson(
              JsonReader.of({
                'id': 3,
                'orderNumber': 'SIP-3',
                'status': status,
                'activeShipmentStatus': shipment,
                'canAcceptDelivery': ?flag,
              }),
            );
        expect(yes.acceptsOrderRow(row(3, 2)), isTrue);
        expect(yes.acceptsOrderRow(row(3, 1)), isFalse);
        expect(no.acceptsOrderRow(row(3, 2)), isFalse);
        expect(no.acceptsOrderRow(row(3, 1, flag: true)), isTrue);
      },
    );
  });

  // Eşik türleri ayrı ayrı (panel eşitliği incelemesi): yalnızca litre, yalnızca tutar, ikisi birden,
  // "her sipariş" (litre 0) ve tutarı bilinmeyen teklif. Panelin kuralı
  // (`CustomerApprovalRules.RequiresApproval`, sınırda eşit = altında) testte bağımsız yazılmış
  // hâliyle; üç yüzey (ana sayfa satırı, Siparişler satırı, sipariş ayrıntısı) kendi tutarıyla (son
  // teklif sürümü) aynı kararı verir. Yeni API'nin değerleri aynen okunur ve sayılar ("Sıra sizde" =
  // Onaylar rozeti = Bende) iki yanıtta da aynıdır.
  group('eşik türü (litre / tutar) × rol × yetki = panel', () {
    const litres = CompanyApprovalRule(required: true, aboveLitres: 10000);
    const amount = CompanyApprovalRule(required: true, aboveAmount: 400000);
    const both = CompanyApprovalRule(
      required: true,
      aboveLitres: 10000,
      aboveAmount: 400000,
    );
    const every = CompanyApprovalRule(required: true, aboveLitres: 0);
    // (ad, şirketin kuralı, siparişin litresi, son teklifin tutarı, talep edende onay kilidi)
    const cases = <(String, CompanyApprovalRule, double, double?, bool)>[
      ('eşik yok', CompanyApprovalRule(), 50000, 2000000, false),
      ('litre eşiği · altında (eşit)', litres, 10000, 2000000, false),
      ('litre eşiği · üstünde', litres, 10001, 1000, true),
      ('tutar eşiği · altında (eşit)', amount, 90000, 400000, false),
      ('tutar eşiği · üstünde', amount, 100, 400000.01, true),
      ('litre + tutar · litre altı, tutar üstü', both, 5000, 500000, true),
      ('litre + tutar · litre üstü, tutar altı', both, 15000, 100000, true),
      ('litre + tutar · ikisi de altında', both, 5000, 200000, false),
      ('her sipariş (litre 0)', every, 1, 10, true),
      (
        'tutar eşiği · tutar bilinmiyor (güvenli taraf)',
        amount,
        100,
        null,
        true,
      ),
      ('litre + tutar · tutar bilinmiyor, litre altı', both, 100, null, false),
    ];

    for (final (name, rule, liters, total, locks) in cases) {
      for (final role in const <int?>[null, 1, 2, 3]) {
        test('$name · rol ${role ?? 'yok (eski)'}', () {
          for (final quotes in const [true, false]) {
            final locked = quotes && role == 1 && locks;
            final want = QuoteRights(
              canDecide: quotes,
              canApprove: quotes && !locked,
              blockedReason: locked ? _msg : null,
            );
            final why = 'Teklifler ${quotes ? 'Düzenler' : 'yok'}';
            final decider = CustomerDecider.of(
              _policy(role, quotes: quotes, shipments: true),
              // Sunucu kuralı yalnızca talep edene gönderir (`home/customer` → `companyApproval`).
              companyRule: role == 1 ? rule : null,
            );

            // 1. Yayındaki eski API (alan yok): her yüzey kendi tutarıyla.
            final home = DashboardOrderRow(
              orderId: 1,
              orderNumber: 'SIP-1',
              status: OrderStatus.awaitingApproval,
              quantityLiters: liters,
              latestTotalAmountTry: total,
            );
            final row = CustomerOrderRow.fromJson(
              JsonReader.of({
                'id': 1,
                'orderNumber': 'SIP-1',
                'status': 2,
                'quantityLiters': liters,
                'quotedTotal': ?total,
              }),
            );
            final detail = OrderDetail.fromJson({
              'id': 1,
              'orderNumber': 'SIP-1',
              'status': 2,
              'quantityLiters': liters,
              'customerId': 101,
              // Son sürüm belirler: ilk sürümün tutarı eşiğin öbür yanında.
              'quotes': [
                if (total != null) ...[
                  {
                    'id': 1,
                    'version': 1,
                    'unitPriceTry': 1,
                    'totalAmountTry': total > 400000 ? 1000 : 9000000,
                  },
                  {
                    'id': 2,
                    'version': 2,
                    'unitPriceTry': 1,
                    'totalAmountTry': total,
                  },
                ],
              ],
            });
            for (final (surface, got) in [
              ('ana sayfa', decider.quoteOfRow(home)),
              ('Siparişler', decider.quoteOfOrder(row)),
              ('ayrıntı', decider.quoteOfDetail(detail)),
            ]) {
              expect(got, want, reason: '$surface · $why');
              expect(got.yourMove, want.canApprove, reason: '$surface · $why');
              expect(got.approveBlocked, locked, reason: '$surface · $why');
            }

            // 2. Yeni API: sunucunun değerleri aynen (görüntüleyenin yerel kuralı ne derse desin).
            for (final local in [
              decider,
              CustomerDecider.full,
              CustomerDecider.of(
                _policy(1, quotes: true, shipments: true),
                companyRule: every,
              ),
            ]) {
              expect(
                local.quote(
                  status: OrderStatus.awaitingApproval,
                  liters: liters,
                  total: total,
                  canDecideQuote: want.canDecide,
                  canApproveQuote: want.canApprove,
                  approveBlockedReason: want.blockedReason,
                ),
                want,
                reason: 'sunucu · $why',
              );
            }

            // 3. Sayı: teklif yalnızca onay açıkken; alanlar olsa da olmasa da aynı.
            for (final fields in [true, false]) {
              final tasks = buildCustomerTasks(
                home: CustomerHomeData(
                  customerId: 101,
                  customerTitle: 'Anadolu Lojistik A.Ş.',
                  dashboard: CustomerDashboard(
                    pendingDecisions: [
                      DashboardOrderRow(
                        orderId: 1,
                        orderNumber: 'SIP-1',
                        status: OrderStatus.awaitingApproval,
                        quantityLiters: liters,
                        latestTotalAmountTry: total,
                        canDecideQuote: fields ? want.canDecide : null,
                        canApproveQuote: fields ? want.canApprove : null,
                        approveBlockedReason: fields
                            ? want.blockedReason
                            : null,
                      ),
                    ],
                  ),
                ),
                decider: decider,
              );
              expect(
                tasks.where((t) => t.kind == TaskKind.quoteDecision),
                hasLength(want.canApprove ? 1 : 0),
                reason: 'sayı · $why · alanlar: $fields',
              );
            }
          }
        });
      }
    }
  });

  group('canlı fikstür (sandbox): sunucunun değerleri = yedek kural', () {
    Map<String, dynamic> load(String name) =>
        jsonDecode(File('test/contract/fixtures/$name.json').readAsStringSync())
            as Map<String, dynamic>;

    /// Yayındaki eski API'nin yanıtı: panel eşitliği alanları silinmiş kopya.
    Map<String, dynamic> withoutFields(Map<String, dynamic> raw) {
      final copy = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
      final dash = copy['dashboard'] as Map<String, dynamic>;
      for (final key in ['pendingDecisions', 'awaitingStation', 'shipments']) {
        for (final r in (dash[key] as List).cast<Map<String, dynamic>>()) {
          r
            ..remove('canDecideQuote')
            ..remove('canApproveQuote')
            ..remove('approveBlockedReason')
            ..remove('canAcceptDelivery');
        }
      }
      return copy;
    }

    for (final (home, access, quotes) in const [
      // Talep eden (eşik 10.000 L / 400.000 ₺): yalnızca 5.400 L'lik iki teklif onun.
      ('home-customer.requester', 'me-access.talep', [357, 327]),
      // Yönetici: sekiz teklifin hepsi.
      (
        'home-customer',
        'me-access.musteri',
        [386, 372, 371, 357, 356, 342, 341, 327],
      ),
    ]) {
      test('$home ($access): satır satır aynı karar, aynı kutu', () {
        final raw = load(home);
        final policy = AccessPolicy(MeAccess.fromJson(load(access)));
        final server = CustomerHomeData.fromJson(raw);
        final old = CustomerHomeData.fromJson(withoutFields(raw));
        final decider = CustomerDecider.of(
          policy,
          companyRule: server.companyApproval,
        );
        final rows = server.dashboard.pendingDecisions;
        expect(rows, hasLength(8));
        for (var i = 0; i < rows.length; i++) {
          final legacy = old.dashboard.pendingDecisions[i];
          expect(rows[i].canDecideQuote, isNotNull);
          expect(legacy.canDecideQuote, isNull);
          expect(
            decider.quoteOfRow(legacy),
            decider.quoteOfRow(rows[i]),
            reason: '${rows[i].orderId}',
          );
        }
        List<int?> quoteIds(CustomerHomeData h) => [
          for (final t in buildCustomerTasks(home: h, decider: decider))
            if (t.kind == TaskKind.quoteDecision) t.orderId,
        ];
        List<String> deliveries(CustomerHomeData h) => [
          for (final t in buildCustomerTasks(home: h, decider: decider))
            if (t.kind == TaskKind.deliveryAcceptance) t.id,
        ];
        expect(quoteIds(server), unorderedEquals(quotes));
        expect(quoteIds(old), unorderedEquals(quotes));
        // Eşik üstü teklif onaylayanındır; not sunucunun ret metni.
        for (final r in rows.where((r) => !quotes.contains(r.orderId))) {
          expect(decider.quoteOfRow(r).approveBlocked, isTrue);
          expect(r.approveBlockedReason, _msg);
        }
        // Teslimat: rol aranmaz; kabul bekleyen tek sevkiyat görüntüleyenin işi.
        expect(deliveries(server), ['delivery-1']);
        expect(deliveries(old), ['delivery-1']);
      });
    }
  });

  group('sipariş ayrıntısı: karar çubuğu ve aşama (panel eşitliği)', () {
    late A2Env env;

    setUp(() async {
      env = await A2Env.create();
    });

    /// Talep edenin eşik altı teklifi (8.000 L · 338.800 ₺, çekli).
    int below() => env.world.orders.firstWhere((o) => o['status'] == 2)['id'];

    /// Şirketin onay eşiğini (20.000 L / 750.000 ₺) aşan teklif (24.000 L · 1.006.800 ₺).
    int above() => env.world.orders.firstWhere(
      (o) => o['customerId'] == 101 && o['quantityLiters'] == 24000,
    )['id'];

    /// Kabul bekleyen sevkiyatı olan onaylı sipariş.
    int reported() =>
        env.world.shipments.firstWhere((s) => s['status'] == 2)['orderId'];

    /// Personanın yetkisini test boyunca kaldırır (oturum açmadan önce).
    void revoke(String persona, String page) {
      final p = findFakePersona(persona)!;
      final grant = '$page:${Perm.edit}';
      final had = p.pages.remove(grant);
      addTearDown(() {
        if (had) p.pages.add(grant);
      });
    }

    /// 12002'nin çek görseli yüklenmiş olsun (onay belgeye takılmasın).
    void addCheque(int orderId) => env.world.attachments.add({
      'publicId': 'p-cek-$orderId',
      'ownerType': 1,
      'ownerId': orderId,
      'kind': 1,
      'kindLabel': 'Çek görseli',
      'fileName': 'cek.jpg',
      'contentType': 'image/jpeg',
      'sizeBytes': 2048,
      'isActive': true,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });

    Future<ProviderContainer> open(
      WidgetTester tester,
      String persona,
      int id,
    ) async {
      final c = (await tester.runAsync(() => env.signedIn(persona)))!;
      addTearDown(c.dispose);
      await pumpA2(tester, c, initialLocation: '/orders/$id');
      await pumpUntil(tester, find.byType(AknFlowLine));
      await pumpReal(tester);
      return c;
    }

    Finder dock() => find.byType(ActionBar);

    List<String> dockLabels(WidgetTester tester) => [
      for (final b in tester.widgetList<AknButton>(
        find.descendant(of: dock(), matching: find.byType(AknButton)),
      ))
        b.label,
    ];

    StageNow stage(WidgetTester tester) =>
        tester.widget<StageNow>(find.byType(StageNow));

    Future<void> approveViaRecap(WidgetTester tester) async {
      await tester.tap(
        find.descendant(
          of: dock(),
          matching: find.widgetWithText(AknButton, OrdersCopy.approve),
        ),
      );
      await pumpReal(tester);
      expect(find.text('Teklifi onaylıyor musunuz?'), findsOneWidget);
      await tester.tap(find.widgetWithText(AknButton, OrdersCopy.approve).last);
      await pumpReal(tester, rounds: 10);
    }

    for (final fields in [true, false]) {
      final api = fields ? 'yeni API' : 'eski API, alanlar yok';

      testWidgets(
        'talep · eşik üstü ($api): onay yok; birincil "Revize iste", "Reddet" ve panelin notu; '
        'aşama "Onaylayanın kararı bekleniyor"; revize gider',
        (tester) async {
          FakeParity.set(env.world, value: fields);
          final id = above();
          await open(tester, 'talep', id);
          // Eski API'de kural ana sayfadan gelir: ana sayfa yüklenince çubuk kilitlenir.
          await pumpUntil(
            tester,
            find.descendant(of: dock(), matching: find.text(_msg)),
          );
          expect(dockLabels(tester), [OrdersCopy.revise, OrdersCopy.reject]);
          expect(
            find.descendant(of: dock(), matching: find.text(_msg)),
            findsOneWidget,
          );
          expect(stage(tester).sentence, OrdersCopy.approverDecides);
          expect(stage(tester).yourMove, isFalse);
          // Revize panel gibi açık.
          await tester.tap(
            find.descendant(
              of: dock(),
              matching: find.widgetWithText(AknButton, OrdersCopy.revise),
            ),
          );
          await pumpReal(tester);
          await tester.tap(
            find.widgetWithText(
              AknChip,
              QuoteDecisionPresets.revisionReasons.first,
            ),
          );
          await tester.pump();
          await tester.tap(
            find.widgetWithText(AknButton, OrdersCopy.revise).last,
          );
          await pumpReal(tester, rounds: 10);
          expect(env.world.order(id)!['status'], 5);
          await tearDownUi(tester);
        },
      );

      testWidgets(
        'talep · eşik altı ($api): onay açık (çek yüklü); "Teklifi onayla" onaylar',
        (tester) async {
          FakeParity.set(env.world, value: fields);
          final id = below();
          addCheque(id);
          await open(tester, 'talep', id);
          await pumpUntil(
            tester,
            find.descendant(
              of: dock(),
              matching: find.widgetWithText(AknButton, OrdersCopy.approve),
            ),
          );
          expect(dockLabels(tester), [
            OrdersCopy.approve,
            OrdersCopy.revise,
            OrdersCopy.reject,
          ]);
          expect(find.text(_msg), findsNothing);
          expect(stage(tester).yourMove, isTrue);
          await approveViaRecap(tester);
          expect(env.world.order(id)!['status'], 3);
          await tearDownUi(tester);
        },
      );

      for (final persona in ['onay', 'musteri']) {
        testWidgets(
          '$persona · eşik üstü ($api): onay açık (rol eşiğe tabi değil); onaylar',
          (tester) async {
            FakeParity.set(env.world, value: fields);
            final id = above();
            await open(tester, persona, id);
            expect(dockLabels(tester), [
              OrdersCopy.approve,
              OrdersCopy.revise,
              OrdersCopy.reject,
            ]);
            expect(find.text(_msg), findsNothing);
            expect(stage(tester).sentence, 'Teklifi onaylayın');
            await approveViaRecap(tester);
            expect(env.world.order(id)!['status'], 3);
            await tearDownUi(tester);
          },
        );
      }

      for (final persona in ['talep', 'onay']) {
        testWidgets(
          '$persona · Teklifler "Düzenler" yok ($api): karar çubuğu yok; panelin uyarısı',
          (tester) async {
            FakeParity.set(env.world, value: fields);
            revoke(persona, Pg.customerQuotes);
            await open(tester, persona, above());
            expect(dock(), findsNothing);
            expect(stage(tester).yourMove, isFalse);
            expect(stage(tester).detail, OrdersCopy.noDecisionRight);
            await tearDownUi(tester);
          },
        );
      }

      testWidgets(
        'talep · teslimat ($api): rol aranmaz, "Teslimatı onayla"; Sevkiyatlar yetkisi yoksa '
        'panelin uyarısı',
        (tester) async {
          FakeParity.set(env.world, value: fields);
          await open(tester, 'talep', reported());
          expect(
            find.widgetWithText(AknButton, OrdersCopy.confirmDelivery),
            findsOneWidget,
          );
          expect(find.text(OrdersCopy.noAcceptRight), findsNothing);
          await tearDownUi(tester);
        },
      );

      testWidgets(
        'talep · Sevkiyatlar "Düzenler" yok ($api): kabul düğmesi yok',
        (tester) async {
          FakeParity.set(env.world, value: fields);
          revoke('talep', Pg.customerShipments);
          await open(tester, 'talep', reported());
          expect(
            find.widgetWithText(AknButton, OrdersCopy.confirmDelivery),
            findsNothing,
          );
          expect(find.text(OrdersCopy.noAcceptRight), findsOneWidget);
          await tearDownUi(tester);
        },
      );
    }

    testWidgets(
      'eski API, kural bilinmiyor: onay panel gibi açık ama sayılmaz; sunucu reddedince metni '
      'gösterilir ve çubuk kilitli onaya döner',
      (tester) async {
        FakeParity.set(env.world, value: false);
        // Ana sayfa şirket içi kuralı gönderemedi (sunucu: ayar okunamadı).
        env.server.get('home/customer', (req) {
          final j = customerHomeJson(req.world, A2Fake.customer(req));
          j['companyApproval'] = null;
          return j;
        });
        final id = above();
        final c = await open(tester, 'talep', id);
        await pumpReal(tester);
        expect(dockLabels(tester), [
          OrdersCopy.approve,
          OrdersCopy.revise,
          OrdersCopy.reject,
        ]);
        // Ölü "Sıra sizde" yok: kural bilinmeden talep edenin teklifi sayılmaz.
        expect(c.read(customerHomeProvider).data?.companyApproval, isNull);
        expect(
          c
              .read(customerTasksProvider)
              .items
              .where((t) => t.kind == TaskKind.quoteDecision),
          isEmpty,
        );
        await approveViaRecap(tester);
        await pumpUntil(
          tester,
          find.descendant(of: dock(), matching: find.text(_msg)),
        );
        expect(dockLabels(tester), [OrdersCopy.revise, OrdersCopy.reject]);
        expect(stage(tester).sentence, OrdersCopy.approverDecides);
        expect(env.world.order(id)!['status'], 2);
        expect(env.controls.decisionRequests.last.path, endsWith('/approve'));
        await tearDownUi(tester);
      },
    );

    test('sahte sunucu panelin kuralını uygular (bayraklar ve onay reddi)', () {
      // Sahte sunucu web ve API ile aynı kuralı uygular (OrderService.ApproveAsync).
      final talep = findFakePersona('talep')!;
      final o = env.world.order(above())!;
      expect(A2Fake.requiresCompanyApprover(talep, o), isTrue);
      expect(
        A2Fake.requiresCompanyApprover(findFakePersona('onay')!, o),
        isFalse,
      );
      expect(
        A2Fake.requiresCompanyApprover(talep, env.world.order(below())!),
        isFalse,
      );
      final actions = A2Fake.orderActions(env.world, talep, o);
      expect(actions['canDecideQuote'], isTrue);
      expect(actions['canApproveQuote'], isFalse);
      expect(actions['approveBlockedReason'], _msg);
      FakeParity.set(env.world, value: false);
      expect(A2Fake.orderActions(env.world, talep, o), isEmpty);
    });
  });

  group('Siparişler (panel eşitliği)', () {
    late A2Env env;

    setUp(() async {
      env = await A2Env.create();
    });

    for (final fields in [true, false]) {
      testWidgets(
        'talep (${fields ? 'yeni API' : 'eski API, alanlar yok'}): eşik altı satır Pas iş satırı, '
        'eşik üstü satır "Onaylayanın kararı bekleniyor"; bant "1 teklif onayınızı bekliyor"',
        (tester) async {
          FakeParity.set(env.world, value: fields);
          final c = (await tester.runAsync(() => env.signedIn('talep')))!;
          addTearDown(c.dispose);
          await pumpA2(tester, c, initialLocation: '/orders?segment=decision');
          final big = env.world.orders.firstWhere(
            (o) => o['customerId'] == 101 && o['quantityLiters'] == 24000,
          )['id'];
          final small = env.world.orders.firstWhere(
            (o) => o['status'] == 2,
          )['id'];
          await pumpUntil(tester, find.text('1 teklif onayınızı bekliyor'));
          await pumpUntil(
            tester,
            find.descendant(
              of: find.byKey(ValueKey('order-row-$big')),
              matching: find.text(OrdersCopy.approverDecides),
            ),
          );
          await pumpReal(tester);
          expect(find.text('1 teklif onayınızı bekliyor'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(ValueKey('order-row-$big')),
              matching: find.text(OrdersCopy.approverDecides),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byKey(ValueKey('order-row-$small')),
              matching: find.text('Çek görselini yükleyin'),
            ),
            findsOneWidget,
          );
          await tearDownUi(tester);
        },
      );
    }
  });
}
