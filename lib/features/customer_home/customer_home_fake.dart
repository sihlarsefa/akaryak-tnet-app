import '../../core/auth/permissions.dart';
import '../../core/models/json.dart';
import '../../core/network/fake/fake_personas.dart';
import '../../core/network/fake/fake_server.dart';
import '../../core/network/fake/fake_world.dart';
import '../../core/utils/tr_time.dart';
import '../customer_orders/api.dart';

/// Müşteri ana sayfası sahte uçları (sahibi A2): `home/customer` (`CustomerHomeDto`, spec B.6) ve
/// `customers/me/ordering-status`. Veri ortak dünyadan üretilir; sipariş verildikçe, teklif
/// onaylandıkça ve belge yüklendikçe değişir.
void registerCustomerHomeFakes(FakeServer server) {
  server.get('home/customer', (req) {
    final p = A2Fake.customer(req);
    return customerHomeJson(req.world, p);
  });

  server.get('customers/me/ordering-status', (req) {
    final p = A2Fake.customer(req);
    final w = req.world;
    final asked = req.queryInt('stationId') ?? 0;
    final link = A2Fake.link(w, p.customerId!, asked);
    final stationId = asked > 0 ? asked : ((link?['stationId'] as int?) ?? 0);
    return A2Fake.orderingStatus(w, p.customerId!, stationId);
  });
}

/// Sahte bayi cep numaraları (WhatsApp).
const _stationGsm = {1: '5321230001', 2: '5331230002'};

/// Teslim süresi (gün): en erken / önerilen tarih = bugün + bu süre.
const _leadDays = 1;

/// `CustomerHomeDto` gövdesi.
JsonMap customerHomeJson(FakeWorld w, FakePersona p) {
  final cid = p.customerId!;
  final links = A2Fake.linksOf(w, cid);
  final first = links.isEmpty ? null : links.first;
  final station = first == null ? null : w.station(first['stationId'] as int);
  final today = TrTime.todayStart();
  final date = TrTime.isoDate(TrTime.addDays(today, _leadDays));
  final role = p.customerUserRole ?? 3;
  final canSee = p.can(Pg.customerOrders) || p.can(Pg.customerQuotes);

  final orders = w.ordersOfCustomer(cid);
  final decisions = orders.where((o) => o['status'] == 2).toList()
    ..sort((a, b) => '${a['expiresAt']}'.compareTo('${b['expiresAt']}'));
  final awaiting = orders
      .where((o) => o['status'] == 1 || o['status'] == 5)
      .toList();

  return {
    'customerId': cid,
    'customerTitle': w.customerTitle(cid) ?? '',
    'stationId': first?['stationId'],
    'stationTitle': w.stationTitle(first?['stationId'] as int?),
    'ordering': first == null
        ? A2Fake.orderingStatus(w, cid, 0)
        : A2Fake.orderingStatus(w, cid, first['stationId'] as int),
    'dashboard': {
      'customerId': cid,
      'customerFound': true,
      'customerTitle': w.customerTitle(cid) ?? '',
      'customerIsActive': true,
      'canPurchaseFuel': true,
      'generatedAt': TrTime.isoLocal(TrTime.now()),
      'expiryEnabled': A2Fake.expiryOn(w),
      'expiringWindowMinutes': 60,
      'pendingDecisions': canSee
          ? [for (final o in decisions.take(8)) _dashboardOrder(w, o)]
          : const <Object>[],
      'pendingDecisionTotal': canSee ? decisions.length : 0,
      'pendingDecisionExpiringTotal': canSee
          ? decisions.where((o) {
              final at = A2Fake.instantOf(o['expiresAt']);
              return at != null &&
                  at.difference(TrTime.now()) < const Duration(minutes: 60);
            }).length
          : 0,
      'awaitingStation': canSee
          ? [for (final o in awaiting.take(5)) _dashboardOrder(w, o)]
          : const <Object>[],
      'awaitingQuoteTotal': canSee
          ? awaiting.where((o) => o['status'] == 1).length
          : 0,
      'revisionRequestedTotal': canSee
          ? awaiting.where((o) => o['status'] == 5).length
          : 0,
      ..._shipmentSection(w, p, orders),
      'lastOrder': _lastOrder(orders),
      'stats': _stats(w, cid, orders),
      'statsFailed': false,
    },
    'companyApprovalsWaiting': role >= 2
        ? w.approvals
              .where(
                (a) =>
                    a['type'] == 3 &&
                    a['status'] == 0 &&
                    a['customerId'] == cid,
              )
              .length
        : 0,
    'financeInfoRequests': w.approvals
        .where(
          (a) =>
              (a['type'] == 4 || a['type'] == 6) &&
              a['status'] == 4 &&
              a['customerId'] == cid,
        )
        .length,
    'templates': p.can(Pg.customerCreateOrder)
        ? [
            for (final t in A2Fake.templatesOf(w, cid).take(3))
              A2Fake.templateListItem(w, t),
          ]
        : const <Object>[],
    'station': station == null
        ? null
        : {
            'id': station['id'],
            'title': station['title'],
            'phone': station['phone'],
            'gsm': _stationGsm[station['id']],
            'email': null,
            'city': station['city'],
          },
    'stations': [
      for (final l in links)
        () {
          final s = A2Fake.orderingStatus(w, cid, l['stationId'] as int);
          return {
            'id': l['stationId'],
            'title': w.stationTitle(l['stationId'] as int?) ?? '',
            'canOrder': s['canOrder'],
            'blockReason': s['blockReason'],
          };
        }(),
    ],
    'limits': [for (final l in links) _limit(w, l)],
    'companyApproval': role == 1 ? A2Fake.companyApproval(cid) : null,
    'suggestedDeliveryDate': first == null ? null : date,
    'minDeliveryDate': first == null ? null : date,
    'pendingPaymentDocuments': canSee || p.can(Pg.customerCreateOrder)
        ? _pendingDocuments(w, orders)
        : const <Object>[],
  };
}

JsonMap _dashboardOrder(FakeWorld w, JsonMap o) {
  final q = A2Fake.latestQuote(o);
  final dp = w.deliveryPoint(o['deliveryPointId'] as int?);
  final expires = A2Fake.instantOf(o['expiresAt']);
  return {
    'orderId': o['id'],
    'orderNumber': o['orderNumber'],
    'status': o['status'],
    'createdAt': o['createdAt'],
    'updatedAt': null,
    'expiresAt': o['expiresAt'],
    'requestedDeliveryDate': o['requestedDeliveryDate'],
    'quantityLiters': o['quantityLiters'],
    'productName': o['productName'],
    'customerId': o['customerId'],
    'customerTitle': o['customerTitle'],
    'stationId': o['stationId'],
    'stationTitle': o['stationTitle'],
    'deliveryPointName': o['deliveryPointName'],
    'deliveryCity': dp?['city'],
    'latestVersion': q?['version'],
    'latestUnitPriceTry': q?['unitPriceTry'],
    'latestTotalAmountTry': q?['totalAmountTry'],
    'latestDeliveryDate': q?['deliveryDate'],
    'revisionNote': q?['revisionNote'],
    'msLeft': expires == null
        ? 0
        : expires.difference(TrTime.now()).inMilliseconds,
  };
}

Map<String, Object?> _shipmentSection(
  FakeWorld w,
  FakePersona p,
  List<JsonMap> orders,
) {
  if (!p.can(Pg.customerShipments)) {
    return {
      'shipments': const <Object>[],
      'plannedShipmentTotal': 0,
      'inTransitShipmentTotal': 0,
      'reportedShipmentTotal': 0,
      'disputedShipmentTotal': 0,
    };
  }
  final ids = {for (final o in orders) o['id']};
  final open =
      w.shipments
          .where(
            (s) =>
                ids.contains(s['orderId']) &&
                const {0, 1, 2, 4}.contains(s['status']),
          )
          .toList()
        ..sort(
          (a, b) => '${a['scheduledAt']}'.compareTo('${b['scheduledAt']}'),
        );
  int count(int status) => open.where((s) => s['status'] == status).length;
  return {
    'shipments': [
      for (final s in open.take(8))
        {
          'shipmentId': s['id'],
          'orderId': s['orderId'],
          'orderNumber': s['orderNumber'],
          'status': s['status'],
          'scheduledAt': s['scheduledAt'],
          'plannedLiters': s['plannedLiters'],
          'deliveredLiters': s['deliveredLiters'],
          'deliveredAt': s['deliveredAt'],
          'vehiclePlate': s['vehiclePlate'],
          'driverName': s['driverName'],
          'deliveryDocumentNo': s['deliveryDocumentNo'],
          'disputeNote': s['disputeNote'],
          'updatedAt': null,
          'customerId': s['customerId'],
          'customerTitle': s['customerName'],
          'stationId': s['stationId'],
          'stationTitle': s['stationName'],
          'productName': s['productName'],
          'deliveryPointName': s['deliveryPointName'],
          'deliveryCity': s['deliveryCity'],
          'isOverdue': false,
        },
    ],
    'plannedShipmentTotal': count(0),
    'inTransitShipmentTotal': count(1),
    'reportedShipmentTotal': count(2),
    'disputedShipmentTotal': count(4),
  };
}

JsonMap? _lastOrder(List<JsonMap> orders) {
  if (orders.isEmpty) return null;
  final o = [...orders]
    ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
  final x = o.first;
  return {
    'orderId': x['id'],
    'orderNumber': x['orderNumber'],
    'status': x['status'],
    'createdAt': x['createdAt'],
    'quantityLiters': x['quantityLiters'],
    'productName': x['productName'],
    'stationTitle': x['stationTitle'],
    'deliveryPointName': x['deliveryPointName'],
  };
}

JsonMap _stats(FakeWorld w, int cid, List<JsonMap> orders) {
  final now = TrTime.wall(TrTime.now());
  bool inMonth(JsonMap o, int monthsAgo) {
    final at = A2Fake.instantOf(o['createdAt']);
    if (at == null) return false;
    final d = TrTime.wall(at);
    final m = DateTime(now.year, now.month - monthsAgo);
    return d.year == m.year && d.month == m.month;
  }

  double amount(JsonMap o) {
    final q = A2Fake.latestQuote(o);
    return ((q?['totalAmountTry'] as num?) ?? 0).toDouble();
  }

  final done = orders.where((o) => o['status'] == 3 || o['status'] == 7);
  final month = done.where((o) => inMonth(o, 0)).toList();
  final prev = done.where((o) => inMonth(o, 1)).toList();
  return {
    'generatedAt': TrTime.isoLocal(TrTime.now()),
    'monthStart': TrTime.isoLocal(TrTime.fromWall(now.year, now.month)),
    'monthOrders': month.length,
    'monthLiters': month.fold<double>(
      0,
      (s, o) => s + (o['quantityLiters'] as num),
    ),
    'monthAmount': month.fold<double>(0, (s, o) => s + amount(o)),
    'prevMonthOrders': prev.length,
    'prevMonthLiters': prev.fold<double>(
      0,
      (s, o) => s + (o['quantityLiters'] as num),
    ),
    'prevMonthAmount': prev.fold<double>(0, (s, o) => s + amount(o)),
    'limits': [
      for (final l in A2Fake.linksOf(w, cid))
        () {
          final x = _limit(w, l);
          return {
            'linkId': l['id'],
            'stationId': x['stationId'],
            'stationTitle': x['stationTitle'],
            'customerId': cid,
            'customerTitle': w.customerTitle(cid) ?? '',
            'erpCode': null,
            'limitType': x['type'],
            'limitPeriod': x['period'],
            'limitAmount': x['amount'],
            'hasLimit': x['hasLimit'],
            'isUnlimited': x['hasLimit'] != true,
            'unit': x['unit'],
            'used': x['used'],
            'remaining': x['remaining'],
            'usedPercent': x['usedPct'],
            'periodLabel': x['periodLabel'],
          };
        }(),
    ],
    'limitsTruncated': false,
  };
}

JsonMap _limit(FakeWorld w, JsonMap l) {
  final amount = (l['limitAmount'] as num?)?.toDouble();
  final used = ((l['used'] as num?) ?? 0).toDouble();
  final type = l['limitType'] as String?;
  final period = l['limitPeriod'] as String?;
  final has = amount != null && period != 'Limitsiz';
  final unit = type == 'Litre' ? 'L' : 'TL';
  return {
    'stationId': l['stationId'],
    'stationTitle': w.stationTitle(l['stationId'] as int?) ?? '',
    'type': type,
    'period': period,
    'periodLabel': switch (period) {
      'Günlük' => 'Bugün',
      'Haftalık' => 'Bu hafta',
      'Aylık' => 'Bu ay',
      'Limitli' => 'Dönemsiz (toplam)',
      _ => 'Limitsiz',
    },
    'amount': has ? amount : null,
    'used': used,
    'remaining': has ? (amount - used).clamp(0, double.infinity) : null,
    'usedPct': has && amount > 0
        ? double.parse((used / amount * 100).toStringAsFixed(1))
        : 0,
    'unit': unit,
    'hasLimit': has,
  };
}

List<JsonMap> _pendingDocuments(FakeWorld w, List<JsonMap> orders) {
  final seen = <Object?>{};
  final out = <JsonMap>[];
  final missing = orders.where((o) => A2Fake.documentMissing(w, o)).toList()
    ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
  for (final o in missing) {
    final group = o['paymentGroupKey'] ?? 'order:${o['id']}';
    if (!seen.add(group)) continue;
    final cheque = o['paymentMethodCode'] == 'CEK';
    out.add({
      'orderId': o['id'],
      'orderNumber': o['orderNumber'],
      'stationTitle': o['stationTitle'],
      'methodCode': o['paymentMethodCode'],
      'methodName': A2Fake.methodShortName(o['paymentMethodCode'] as String?),
      'kind': cheque ? 1 : 2,
      'kindLabel': cheque ? 'Çek görseli' : 'Senet görseli',
      'required': true,
      'target': A2Fake.documentTarget(w, [o]),
    });
    if (out.length >= 10) break;
  }
  return out;
}
