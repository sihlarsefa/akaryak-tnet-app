import 'dart:math';

import '../../../core/auth/permissions.dart';
import '../../../core/models/enums.dart' show ApprovalSlaState;
import '../../../core/models/json.dart';
import '../../../core/network/fake/fake_personas.dart';
import '../../../core/network/fake/fake_server.dart';
import '../../../core/network/fake/fake_world.dart';
import '../../../core/utils/tr_time.dart';
import '../../approvals/fake/a5_fake_store.dart' show A5FakeStore;
import 'fake_support.dart';
import 'order_support.dart';
import 'seed.dart';

/// `GET home/bayi`: bölümler yetkiye göre (spec B.7 tablosu; B4 `BayiHomeVisibility`):
/// desk = QuoteDesk|Quotes|Orders · shipments = Shipments|ShipmentBoard, ownOnly hiç ·
/// approvals / collections / finance = Approvals / Payments / Finance · leads = Leads ·
/// field = FieldOrders|FieldApprovals · setup = StationSettings, saha satış hiç ·
/// sales = Orders|Reports, saha satış ve ownOnly hiç.
void registerBayiHomeFakes(FakeServer s) {
  s.get('home/bayi', (req) {
    final p = req.requireUser();
    if (p.persona.code != 'bayi' || p.stationId == null) {
      throw FakeResponse.forbidden();
    }
    ensureBayiSeed(req.world);
    // Onaylar deposu kendi siparişlerini de tohumlar: ana sayfa dünyayı okumadan önce kurulur,
    // bölümler hangi çağrının önce geldiğine bağlı kalmaz.
    A5FakeStore.of(req.world);
    return bayiHomeJson(req.world, p);
  });
}

/// Ana sayfa gövdesi (testler doğrudan da kullanır).
JsonMap bayiHomeJson(FakeWorld w, FakePersona p) {
  bool g(String page) => p.can(page);
  final ownOnly = isOwnOnly(p);
  final field = isFieldSales(p);
  final desk =
      g(Pg.stationQuoteDesk) || g(Pg.stationQuotes) || g(Pg.stationOrders);
  final shipments =
      !ownOnly && (g(Pg.stationShipments) || g(Pg.stationShipmentBoard));
  final setup = !field && templateCan(p, Pg.stationSettings);
  final sales =
      !field && !ownOnly && (g(Pg.stationOrders) || g(Pg.stationReports));
  return {
    'stationId': p.stationId,
    'stationTitle': w.stationTitle(p.stationId),
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'sections': {
      'desk': desk ? _desk(w, p) : null,
      'shipments': shipments ? _shipments(w, p) : null,
      'approvals': g(Pg.stationApprovals) ? _approvals(w, p) : null,
      'collections': g(Pg.stationPayments) ? _collections(w, p) : null,
      'finance': g(Pg.stationFinance) ? _finance(w, p) : null,
      'leads': g(Pg.stationLeads) ? _leads(p) : null,
      'field': g(Pg.stationFieldOrders) || g(Pg.stationFieldApprovals)
          ? _field(w, p)
          : null,
      'setup': setup ? _setup(p) : null,
      'sales': sales ? _sales(w, p) : null,
    },
    'failedSections': const <String>[],
    'isFieldSales': field,
  };
}

JsonMap _dashboardOrder(FakeWorld w, JsonMap o) {
  final q = quotesOf(o).lastOrNull;
  final expires = local(o['expiresAt']);
  return {
    'orderId': o['id'],
    'orderNumber': o['orderNumber'],
    'status': st(o),
    'createdAt': o['createdAt'],
    'updatedAt': o['createdAt'],
    'expiresAt': o['expiresAt'],
    'requestedDeliveryDate': o['requestedDeliveryDate'],
    'quantityLiters': qty(o),
    'productName': o['productName'],
    'customerId': o['customerId'],
    'customerTitle': o['customerTitle'],
    'stationId': o['stationId'],
    'stationTitle': o['stationTitle'],
    'deliveryPointName': o['deliveryPointName'],
    'deliveryCity': o['deliveryCity'],
    'latestVersion': q?['version'],
    'latestUnitPriceTry': q?['unitPriceTry'],
    'latestTotalAmountTry': q?['totalAmountTry'],
    'latestDeliveryDate': q?['deliveryDate'],
    'revisionNote': q?['revisionNote'],
    'financeStatus': fin(o),
    'msLeft': expires == null
        ? 0
        : max(0, expires.difference(TrTime.now()).inMilliseconds),
  };
}

JsonMap _desk(FakeWorld w, FakePersona p) {
  final mine = w.ordersOfStation(p.stationId!);
  final expiry = expiryEnabled(w);
  bool deskable(JsonMap o) =>
      (st(o) == 1 || st(o) == 5) &&
      !financeHeld(o) &&
      fin(o) != 5 &&
      !isExpired(w, o);
  final awaiting = mine.where((o) => st(o) == 1 && deskable(o)).toList()
    ..sort(
      (a, b) => (local(a['createdAt']) ?? TrTime.now()).compareTo(
        local(b['createdAt']) ?? TrTime.now(),
      ),
    );
  final revision = mine.where((o) => st(o) == 5 && deskable(o)).length;
  final customer = mine.where((o) => st(o) == 2 && !financeHeld(o)).length;
  final soon = TrTime.now().add(const Duration(minutes: 60));
  final expiring = expiry
      ? (mine.where((o) {
          if (!(deskable(o) || (st(o) == 2 && !financeHeld(o)))) return false;
          final e = local(o['expiresAt']);
          return e != null && e.isBefore(soon) && e.isAfter(TrTime.now());
        }).toList()..sort(
          (a, b) => local(a['expiresAt'])!.compareTo(local(b['expiresAt'])!),
        ))
      : <JsonMap>[];
  return {
    'awaitingQuote': awaiting.length,
    'revisionRequested': revision,
    'expiringSoon': expiry ? expiring.length : null,
    'awaitingCustomer': customer,
    'expiringWindowMinutes': 60,
    'expiring': [for (final o in expiring.take(5)) _dashboardOrder(w, o)],
    'awaitingQuoteList': [
      for (final o in awaiting.take(5)) _dashboardOrder(w, o),
    ],
    'expiryEnabled': expiry,
    'financeHeld': mine
        .where((o) => (st(o) == 1 || st(o) == 5) && financeHeld(o))
        .length,
  };
}

JsonMap _dashboardShipment(FakeWorld w, JsonMap x) {
  final at = local(x['scheduledAt']);
  final overdue =
      x['status'] == 0 && at != null && at.isBefore(TrTime.todayStart());
  return {
    'shipmentId': x['id'],
    'orderId': x['orderId'],
    'orderNumber': x['orderNumber'],
    'status': x['status'],
    'scheduledAt': x['scheduledAt'],
    'plannedLiters': x['plannedLiters'],
    'deliveredLiters': x['deliveredLiters'],
    'deliveredAt': x['deliveredAt'],
    'vehiclePlate': x['vehiclePlate'],
    'driverName': x['driverName'],
    'deliveryDocumentNo': x['deliveryDocumentNo'],
    'disputeNote': x['disputeNote'],
    'updatedAt': x['scheduledAt'],
    'customerId': x['customerId'],
    'customerTitle': x['customerName'],
    'stationId': x['stationId'],
    'stationTitle': x['stationName'],
    'productName': x['productName'],
    'deliveryPointName': x['deliveryPointName'],
    'deliveryCity': x['deliveryCity'],
    'isOverdue': overdue,
  };
}

JsonMap _shipments(FakeWorld w, FakePersona p) {
  final mine = [
    for (final x in w.shipments)
      if (x['stationId'] == p.stationId) x,
  ];
  final today = TrTime.todayStart();
  final tomorrow = TrTime.addDays(today, 1);
  bool isToday(JsonMap x) {
    final at = local(x['scheduledAt']);
    return at != null && !at.isBefore(today) && at.isBefore(tomorrow);
  }

  final todayRows = mine.where((x) => isToday(x) && x['status'] != 5).toList()
    ..sort(
      (a, b) => local(a['scheduledAt'])!.compareTo(local(b['scheduledAt'])!),
    );
  final disputes = mine.where((x) => x['status'] == 4).toList();
  return {
    'plannedDue': mine.where((x) {
      final at = local(x['scheduledAt']);
      return x['status'] == 0 && at != null && at.isBefore(tomorrow);
    }).length,
    'planned': mine.where((x) => x['status'] == 0).length,
    'inTransit': mine.where((x) => x['status'] == 1).length,
    'reported': mine.where((x) => x['status'] == 2).length,
    'disputes': disputes.length,
    'today': [for (final x in todayRows.take(8)) _dashboardShipment(w, x)],
    'disputeList': [for (final x in disputes.take(5)) _dashboardShipment(w, x)],
    'unassignedDriver': mine.where((x) {
      final o = w.order(x['orderId'] as int?);
      return x['status'] == 0 &&
          x['driverUserId'] == null &&
          o != null &&
          st(o) == 3;
    }).length,
  };
}

/// Onaylar özeti (v4 §8 B: ana sayfa sahtesi kahramanla aynı şeyi söyler): Onaylar sayfasının deposu
/// (A5) ve onun kuralı — Bende satırları ve `dueAt`tan hesaplanan süre durumu (`approvals/badge` ile
/// aynı). "Kararınızı bekleyen 8 talep · 1'i gecikti" ile Onaylar'ın "Gecikmiş 1"i aynı sayıdır.
JsonMap _approvals(FakeWorld w, FakePersona p) {
  final s = A5FakeStore.of(w);
  final rows = [for (final a in s.inbox(p, 0)) s.row(p, a)];
  return {
    'toMe': rows.length,
    'overdue': rows
        .where((r) => r['slaState'] == ApprovalSlaState.overdue.code)
        .length,
  };
}

JsonMap _collections(FakeWorld w, FakePersona p) {
  final today = TrTime.todayStart();
  final mine = w.ordersOfStation(p.stationId!);
  final overdue = [
    for (final o in mine)
      if ((pay(o) == 1 || pay(o) == 2) &&
          (st(o) == 3 || st(o) == 7) &&
          (local(o['paymentDueDate'])?.isBefore(today) ?? false))
        o,
  ];
  double amount(JsonMap o) =>
      (currentQuote(o)?['totalAmountTry'] as num?)?.toDouble() ??
      (o['estimatedAmount'] as num?)?.toDouble() ??
      0;
  final cheque = mine
      .where((o) => o['paymentMethodCode'] == 'CEK' && pay(o) == 1)
      .toList();
  final instruments = [
    for (final o in cheque)
      {
        'id': 600 + (o['id'] as int) % 100,
        'stationId': o['stationId'],
        'customerId': o['customerId'],
        'customerTitle': o['customerTitle'],
        'orderId': o['id'],
        'orderNumber': o['orderNumber'],
        'kind': 1,
        'serialNo': 'ÇK-${(o['id'] as int) % 10000}',
        'bankName': 'Ziraat Bankası',
        'amount': amount(o),
        'dueDate': FakeWorld.local(TrTime.addDays(today, 4)),
        'status': 2,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
  ];
  return {
    'overdueCount': overdue.length,
    'overdueAmount': overdue.fold<double>(0, (s, o) => s + amount(o)),
    'overdue': [
      for (final o in overdue.take(5))
        {
          'orderId': o['id'],
          'orderNumber': o['orderNumber'],
          'stationId': o['stationId'],
          'stationTitle': o['stationTitle'],
          'customerId': o['customerId'],
          'customerTitle': o['customerTitle'],
          'orderStatus': st(o),
          'methodCode': o['paymentMethodCode'],
          'methodName': o['paymentMethodName'],
          'termDays': o['paymentTermDays'],
          'dueDate': o['paymentDueDate'],
          'paymentStatus': pay(o),
          'financeStatus': fin(o),
          'estimatedAmount': o['estimatedAmount'],
          'amount': amount(o),
          'isOverdue': true,
          'createdAt': o['createdAt'],
        },
    ],
    'instrumentsDueSoonCount': instruments.length,
    'instrumentsDueSoonAmount': instruments.fold<double>(
      0,
      (s, i) => s + (i['amount'] as double),
    ),
    'instrumentsDueSoon': instruments.take(5).toList(),
    'dueSoonDays': 7,
    'documentsAwaitingCheck': mine
        .where((o) => pay(o) == 2 && !{4, 6}.contains(st(o)))
        .length,
    'bounced30d': 1,
  };
}

JsonMap _finance(FakeWorld w, FakePersona p) {
  final links = w.links.where((l) => l['stationId'] == p.stationId).toList();
  final attention = [
    for (final l in links)
      if ((l['financeStatus'] as num?)?.toInt() == 2 ||
          (l['riskClass'] as num?)?.toInt() == 3)
        {
          'stationCustomerId': l['id'],
          'profileId': l['id'],
          'customerId': l['customerId'],
          'customerTitle': w.customerTitle(l['customerId'] as int?),
          'taxNumber': null,
          'status': l['financeStatus'],
          'isGrandfathered': false,
          'riskClass': l['riskClass'],
          'limitAmount': l['limitAmount'],
          'limitUsed': l['used'],
          'limitUnit': l['limitType'] == 'Litre' ? 'L' : 'TL',
          'nextReviewDate': FakeWorld.local(
            TrTime.addDays(TrTime.todayStart(), -3),
          ),
          'isStrategicPricing': false,
          'hasBouncedCheque': l['customerId'] == 102,
          'hasProtestedNote': false,
          'overdueAmount': null,
        },
  ];
  return {
    'pending': 1,
    'infoRequested': 0,
    'reviewOverdue': attention.length,
    'flagged': attention.where((a) => a['hasBouncedCheque'] == true).length,
    'attention': attention,
  };
}

JsonMap _leads(FakePersona p) {
  final all = p.capabilities.containsKey(Caps.leadViewAll);
  return {
    'periodLabel': 'Bu ay',
    'stats': {
      'total': all ? 9 : 4,
      'submitted': all ? 3 : 1,
      'converted': all ? 2 : 1,
      'rejected': all ? 1 : 0,
      'draft': all ? 2 : 1,
      'inFinance': all ? 1 : 1,
      'cancelled': 0,
      'conversionRatePercent': all ? 22.2 : 25.0,
      'byRep': const <Object>[],
    },
  };
}

/// Saha bölümü: saha sahtesinin formlarından (`field.forms` torbası, `field-orders` satır anahtarları;
/// A6). Torba henüz tohumlanmadıysa liste boştur; saha sahtesi ilk isteğinde aynı listeyi doldurur.
JsonMap _field(FakeWorld w, FakePersona p) {
  final rep = isFieldSales(p);
  final all = w.bag<List<JsonMap>>('field.forms', () => <JsonMap>[]);
  bool own(JsonMap f) =>
      f['_createdBy'] == p.userId ||
      f['salesRepresentativeName'] == p.displayName;
  final forms = [
    for (final f in all)
      if ((f['stationId'] ?? p.stationId) == p.stationId && (!rep || own(f))) f,
  ]..sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
  int count(int status) => forms.where((f) => f['status'] == status).length;
  JsonMap row(JsonMap f) {
    final lines = (f['lines'] as List?)?.whereType<Map>() ?? const <Map>[];
    var liters = 0.0;
    double? amount = 0;
    for (final l in lines) {
      final q = (l['quantityLiters'] as num?)?.toDouble() ?? 0;
      final price = (l['proposedUnitPrice'] as num?)?.toDouble();
      liters += q;
      amount = price == null || amount == null ? null : amount + q * price;
    }
    final status = (f['status'] as num?)?.toInt() ?? 0;
    return {
      'id': f['id'],
      'formNumber': f['formNumber'],
      'customerTitle': f['customerTitle'],
      'status': status,
      'statusLabel': switch (status) {
        0 => 'Taslak',
        1 => 'Onay bekliyor',
        2 => 'Onaylandı',
        3 => 'Reddedildi',
        4 => 'Siparişe dönüştü',
        _ => 'İptal edildi',
      },
      'totalLiters': liters,
      'totalAmount': amount == null || amount == 0 ? null : roundTo(amount, 2),
      'createdAt': f['createdAt'],
    };
  }

  final approvalsToMe = w.approvals
      .where((a) => a['type'] == 1 && w.canDecide(p, a))
      .length;
  return {
    'drafts': count(0),
    'pending': count(1),
    'rejected': count(3),
    'converted': count(4),
    'approvalsToMe': rep ? 0 : approvalsToMe,
    'portfolioCount': rep
        ? w.links.where((l) => l['salesRepUserId'] == p.userId).length
        : 0,
    'recent': [for (final f in forms.take(3)) row(f)],
  };
}

JsonMap _setup(FakePersona p) {
  final pricing = p.can(Pg.stationPricing) || templateCan(p, Pg.stationPricing);
  final chains =
      p.capabilities.containsKey(Caps.approvalsChainEdit) ||
      templateCan(p, Pg.stationSettings, 'D');
  final checks = <JsonMap>[
    {
      'key': 'tupras-today',
      'title': 'Bugünün Tüpraş fiyatı girilmedi',
      'state': 3,
      'stateLabel': 'Eksik',
      'count': 1,
      'summary': 'Saha formu barem hesabı dünkü fiyatla çalışıyor.',
      'hint': 'Referans fiyatlar sayfasından bugünün fiyatını girin.',
      'details': const <String>[],
      'isOpen': true,
      'portalPath': pricing ? '/Barem/ReferencePrices' : null,
      'portalLabel': pricing ? 'Barem › Referans fiyatlar' : null,
    },
    {
      'key': 'finance-approvers',
      'title': 'Ön kayıt finans onaycısı tanımlı değil',
      'state': 2,
      'stateLabel': 'Uyarı',
      'count': 1,
      'summary': 'Ön kayıtlar merkez onayına düşüyor.',
      'hint': null,
      'details': const ['Ön kayıt finans onayı (1. kademe)'],
      'isOpen': true,
      'portalPath': chains ? '/Approvals/Chains' : null,
      'portalLabel': chains ? 'Onaylar › Onay zincirleri' : null,
    },
  ];
  return {
    'openCount': checks.length,
    'tuprasMissingToday': true,
    'checks': checks,
  };
}

JsonMap _sales(FakeWorld w, FakePersona p) {
  final today = TrTime.todayStart();
  const base = [6, 4, 7, 5, 8, 3];
  const liters = [52000.0, 31000.0, 64000.0, 40000.0, 71000.0, 26000.0];
  final mine = w.ordersOfStation(p.stationId!);
  final todayOrders = mine.where((o) {
    final c = local(o['createdAt']);
    return c != null && !c.isBefore(today);
  }).toList();
  final days = <JsonMap>[
    for (var i = 0; i < 6; i++)
      {
        'day': FakeWorld.local(TrTime.addDays(today, i - 6)),
        'orders': base[i],
        'liters': liters[i],
        'amount': liters[i] * 42.1,
      },
    {
      'day': FakeWorld.local(today),
      'orders': todayOrders.length,
      'liters': todayOrders.fold<double>(0, (s, o) => s + qty(o)),
      'amount': todayOrders.fold<double>(0, (s, o) => s + qty(o) * 42.1),
    },
  ];
  final byCustomer = <int, JsonMap>{};
  for (final o in mine) {
    if (!(st(o) == 3 || st(o) == 7)) continue;
    final q = currentQuote(o);
    final row = byCustomer.putIfAbsent(
      o['customerId'] as int,
      () => {
        'customerId': o['customerId'],
        'customerTitle': o['customerTitle'],
        'orders': 0,
        'liters': 0.0,
        'amount': 0.0,
      },
    );
    row['orders'] = (row['orders'] as int) + 1;
    row['liters'] = (row['liters'] as double) + qty(o);
    row['amount'] =
        (row['amount'] as double) +
        ((q?['totalAmountTry'] as num?)?.toDouble() ?? 0);
  }
  final top = byCustomer.values.toList()
    ..sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));
  final near = [
    for (final l in w.links)
      if (l['stationId'] == p.stationId &&
          l['limitAmount'] != null &&
          ((l['used'] as num) / (l['limitAmount'] as num)) >= 0.8)
        {
          'linkId': l['id'],
          'stationId': l['stationId'],
          'stationTitle': w.stationTitle(l['stationId'] as int?),
          'customerId': l['customerId'],
          'customerTitle': w.customerTitle(l['customerId'] as int?),
          'limitType': l['limitType'],
          'limitPeriod': l['limitPeriod'],
          'limitAmount': l['limitAmount'],
          'hasLimit': true,
          'isUnlimited': false,
          'unit': l['limitType'] == 'Litre' ? 'L' : 'TL',
          'used': l['used'],
          'remaining': (l['limitAmount'] as num) - (l['used'] as num),
          'usedPercent': roundTo(
            (l['used'] as num) / (l['limitAmount'] as num) * 100,
            1,
          ),
          'periodLabel': l['limitPeriod'],
        },
  ];
  final windowOrders = days.fold<int>(0, (s, d) => s + (d['orders'] as int));
  final windowLiters = days.fold<double>(
    0,
    (s, d) => s + (d['liters'] as double),
  );
  final windowAmount = days.fold<double>(
    0,
    (s, d) => s + (d['amount'] as double),
  );
  return {
    'days': days,
    'windowDays': 7,
    'windowOrders': windowOrders,
    'windowLiters': windowLiters,
    'windowAmount': roundTo(windowAmount, 2),
    'topCustomers': top.take(5).toList(),
    'nearLimit': p.can(Pg.stationCustomers) ? near : const <Object>[],
    'nearLimitTotal': p.can(Pg.stationCustomers) ? near.length : 0,
  };
}
