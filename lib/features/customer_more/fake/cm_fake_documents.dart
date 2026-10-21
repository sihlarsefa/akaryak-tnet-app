import '../../../core/auth/permissions.dart';
import '../../../core/models/json.dart';
import '../../../core/network/fake/fake_personas.dart';
import '../../../core/network/fake/fake_server.dart';
import '../../../core/network/fake/fake_world.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import 'cm_fake_support.dart';

/// Belge arşivi (`customers/me/documents`) ve belge verisi (`documents/orders/{id}`, `documents/shipments/{id}`).
void registerCmDocumentFakes(FakeServer s) {
  s.get('customers/me/documents', (req) {
    final p = req.requireUser();
    if (!CmFake.isCustomer(p)) {
      throw FakeResponse.business('Cari bağlamı gerekli.');
    }
    req.requirePage(Pg.customerDocuments);
    return _archive(req, p);
  });

  s.get('documents/orders/{orderId:int}', (req) {
    final p = req.requireUser();
    final o = req.world.order(req.intParam('orderId'));
    _ensureOrderDocAccess(p, o);
    return orderDocumentJson(req.world, o!, p, pricesLoaded: true);
  });

  s.get('documents/shipments/{shipmentId:int}', (req) {
    final p = req.requireUser();
    final w = req.world;
    final sh = w.shipment(req.intParam('shipmentId'));
    if (sh == null) throw FakeResponse.notFound('Sevkiyat bulunamadı.');
    if (CmFake.isCustomer(p)) {
      if (!p.can(Pg.customerDocuments) ||
          !(p.can(Pg.customerShipments) || p.can(Pg.customerOrders))) {
        throw FakeResponse.forbidden();
      }
    }
    if (!CmFake.canSeeShipment(p, sh)) {
      throw FakeResponse.notFound('Sevkiyat bulunamadı.');
    }
    final o = w.order(sh['orderId'] as int)!;
    return {
      'shipment': _docShipment(w, sh),
      'order': orderDocumentJson(w, o, p, pricesLoaded: false),
    };
  });
}

void _ensureOrderDocAccess(FakePersona p, JsonMap? o) {
  if (o == null) throw FakeResponse.notFound('Sipariş bulunamadı.');
  if (CmFake.isCustomer(p)) {
    if (!p.can(Pg.customerDocuments) ||
        !(p.can(Pg.customerOrders) || p.can(Pg.customerQuotes))) {
      throw FakeResponse.forbidden();
    }
    if (o['customerId'] != p.customerId) {
      throw FakeResponse.notFound('Sipariş bulunamadı.');
    }
  } else if (CmFake.isBayi(p)) {
    if (!(p.can(Pg.stationOrders) || p.can(Pg.stationQuotes))) {
      throw FakeResponse.forbidden();
    }
    if (o['stationId'] != p.stationId) {
      throw FakeResponse.notFound('Sipariş bulunamadı.');
    }
  }
}

Object? _archive(FakeRequest req, FakePersona p) {
  final w = req.world;
  final now = TrTime.now();
  final to = TrTime.parseDate(req.query('toDate')) ?? TrTime.startOfDay(now);
  final toWall = TrTime.wall(to);
  var from =
      TrTime.parseDate(req.query('fromDate')) ??
      TrTime.fromWall(toWall.year, toWall.month - 3, toWall.day);
  if (to.difference(from).inDays > 366) {
    from = to.subtract(const Duration(days: 366));
  }
  final end = to.add(const Duration(days: 1));
  final search = req.query('search')?.trim() ?? '';
  final shipmentFilter = req.queryInt('shipment');
  final statuses = CmFake.intsOf(req, 'statuses');

  final rows = <JsonMap>[];
  final orders = w.ordersOfCustomer(p.customerId!).toList()
    ..sort(
      (a, b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String),
    );
  for (final o in orders) {
    final created = CmFake.instant(o['createdAt']);
    if (created == null || created.isBefore(from) || !created.isBefore(end)) {
      continue;
    }
    if (statuses.isNotEmpty && !statuses.contains(o['status'])) continue;
    final ships = w.shipmentsOfOrder(o['id'] as int).toList()
      ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final active = ships.where((s) => s['status'] != 5).length;
    final q = CmFake.currentQuote(o);
    JsonMap row(JsonMap? sh) {
      final status = o['status'] as int;
      final shipStatus = sh?['status'] as int?;
      final approved = status == 3 || status == 7;
      final shipId = sh?['id'] as int?;
      return {
        'orderId': o['id'],
        'orderNumber': o['orderNumber'],
        'orderDate': o['createdAt'],
        'status': status,
        'stationCode': w.station(o['stationId'] as int?)?['code'],
        'stationTitle': o['stationTitle'],
        'productName': o['productName'],
        'quantityLiters': o['quantityLiters'],
        'deliveryPointName': o['deliveryPointName'],
        'deliveryPointCity': o['deliveryCity'],
        'quoteVersion': q?['version'],
        'totalAmountTry': q?['totalAmountTry'],
        'activeShipmentCount': active,
        'shipmentId': shipId,
        'shipmentStatus': shipStatus,
        'scheduledAt': sh?['scheduledAt'],
        'deliveredAt': sh?['deliveredAt'],
        'plannedLiters': sh?['plannedLiters'],
        'deliveredLiters': sh?['deliveredLiters'],
        'vehiclePlate': sh?['vehiclePlate'],
        'deliveryDocumentNo': sh?['deliveryDocumentNo'],
        'hasQuote': q != null,
        'hasShipment': sh != null,
        'isShipmentCancelled': shipStatus == 5,
        'shipmentCode': shipId == null
            ? null
            : 'SVK-${shipId.toString().padLeft(8, '0')}',
        'receiptCode': shipId == null || shipStatus == 5
            ? null
            : 'TT-${shipId.toString().padLeft(8, '0')}',
        'canReconcile': approved && active > 0,
        'canReceipt': sh != null && shipStatus != 5,
        'canWaybill': sh != null,
        'canLabel': sh != null && (shipStatus == 0 || shipStatus == 1),
      };
    }

    final candidates = ships.isEmpty
        ? [row(null)]
        : [for (final sh in ships) row(sh)];
    for (final r in candidates) {
      if (shipmentFilter == 1 && r['shipmentId'] == null) continue;
      if (shipmentFilter == 2 && r['shipmentId'] != null) continue;
      if (search.isNotEmpty &&
          ![
            r['orderNumber'],
            r['shipmentCode'],
            r['receiptCode'],
            r['vehiclePlate'],
            r['deliveryDocumentNo'],
            r['stationTitle'],
            r['productName'],
            r['deliveryPointName'],
          ].any((v) => TurkishText.matches(v?.toString(), search))) {
        continue;
      }
      rows.add(r);
    }
  }
  if (req.query('sort') == 'created:asc') {
    rows.sort(
      (a, b) => (a['orderDate'] as String).compareTo(b['orderDate'] as String),
    );
  } else if (req.query('sort') == 'delivered') {
    rows.sort(
      (a, b) => ((b['deliveredAt'] as String?) ?? '').compareTo(
        (a['deliveredAt'] as String?) ?? '',
      ),
    );
  }
  final skip = (req.queryInt('skip') ?? 0).clamp(0, 1 << 30);
  final take = (req.queryInt('take') ?? 25).clamp(1, 100);
  final page = skip >= rows.length
      ? const <JsonMap>[]
      : rows.sublist(skip, (skip + take).clamp(0, rows.length));
  return {
    'totals': {
      'count': rows.length,
      'orderCount': rows.map((r) => r['orderId']).toSet().length,
      'shipmentCount': rows.where((r) => r['shipmentId'] != null).length,
    },
    'items': page,
  };
}

JsonMap _docShipment(FakeWorld w, JsonMap sh) {
  final seq = CmFake.seqOf(w, sh);
  return {
    'id': sh['id'],
    'orderId': sh['orderId'],
    'code': sh['code'],
    'receiptCode': 'TT-${(sh['id'] as int).toString().padLeft(8, '0')}',
    'seq': sh['status'] == 5 ? 0 : seq.seq,
    'seqCount': seq.count,
    'plannedLiters': sh['plannedLiters'],
    'deliveredLiters': sh['deliveredLiters'],
    'scheduledAt': sh['scheduledAt'],
    'deliveredAt': sh['deliveredAt'],
    'acceptedAt': sh['acceptedAt'],
    'createdAt': sh['createdAt'],
    'vehiclePlate': sh['vehiclePlate'] ?? '',
    'driverName': sh['driverName'] ?? '',
    'deliveryDocumentNo': sh['deliveryDocumentNo'],
    'status': sh['status'],
    'createdByDisplay': 'Okan Yıldız',
    'acceptedByDisplay':
        sh['acceptedByName'] ?? (sh['status'] == 3 ? 'Selin Aydın' : null),
    'disputeNote': sh['disputeNote'],
    'isCancelled': sh['status'] == 5,
  };
}

/// `OrderDocumentDto` (sahte; dünyadaki sipariş, teklif ve sevkiyatlardan).
JsonMap orderDocumentJson(
  FakeWorld w,
  JsonMap o,
  FakePersona viewer, {
  required bool pricesLoaded,
}) {
  final id = o['id'] as int;
  final status = o['status'] as int;
  final quotes = ((o['quotes'] as List?) ?? const []).cast<JsonMap>().toList()
    ..sort((a, b) => (a['version'] as int).compareTo(b['version'] as int));
  final docQuotes = <JsonMap>[];
  for (var i = 0; i < quotes.length; i++) {
    final q = quotes[i];
    final prev = i == 0 ? null : quotes[i - 1];
    docQuotes.add({
      ...q,
      'unitPriceDelta': prev == null
          ? null
          : double.parse(
              ((q['unitPriceTry'] as num) - (prev['unitPriceTry'] as num))
                  .toStringAsFixed(4),
            ),
    });
  }
  final selected = docQuotes.where((q) => q['isSelected'] == true).firstOrNull;
  final ships = w.shipmentsOfOrder(id).toList()
    ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
  final liters = CmFake.liters(w, id);
  final dp =
      w.deliveryPoint(o['deliveryPointId'] as int?) ??
      const <String, dynamic>{};
  final timeline = _timeline(w, o, quotes, ships);
  JsonMap? approved;
  for (final t in timeline) {
    if (t['toStatus'] == 3) approved = t;
  }
  final isApproved = status == 3 || status == 7;
  final selectedQuote = pricesLoaded ? selected : null;
  final accepted = liters.accepted;
  String? hm(Object? v) => v is String && v.isNotEmpty
      ? (v == '24:00' ? '1.00:00:00' : '$v:00')
      : null;
  return {
    'id': id,
    'orderNumber': o['orderNumber'],
    'status': status,
    'statusLabel': _orderStatusLabel(status),
    'quantityLiters': o['quantityLiters'],
    'requestedDeliveryDate': o['requestedDeliveryDate'],
    'createdAt': o['createdAt'],
    'expiresAt': o['expiresAt'],
    'expiryEnabled': true,
    'productCode': w.product(o['productId'] as int?)?['code'] ?? '',
    'productName': o['productName'],
    'productUnit': 'Litre',
    'station': CmFake.stationParty(w, o['stationId'] as int?),
    'customer': CmFake.customerParty(w, o['customerId'] as int?),
    'distributorBrand': 'Petrol Ofisi',
    'distributorTitle': 'Petrol Ofisi A.Ş.',
    'deliveryPointName': o['deliveryPointName'],
    'deliveryPointCity': dp['city'] ?? o['deliveryCity'] ?? '',
    'deliveryPointDistrict': dp['district'] ?? '',
    'deliveryPointAddress': dp['address'] ?? '',
    'deliveryAddressSnapshot': o['deliveryAddress'],
    'deliveryAddress': o['deliveryAddress'],
    'deliveryPointContactName': dp['contactName'],
    'deliveryPointContactPhone': dp['contactPhone'],
    'deliveryWindowStart': hm(dp['windowStart']),
    'deliveryWindowEnd': hm(dp['windowEnd']),
    'deliveryPointTankLiters': dp['tankCapacityLiters'],
    'deliveryPointLatitude': dp['latitude'],
    'deliveryPointLongitude': dp['longitude'],
    'deliveryPointAccessNotes': dp['accessNotes'],
    'pricesLoaded': pricesLoaded,
    'quotes': pricesLoaded ? docQuotes : const <Object>[],
    'selectedQuote': selectedQuote,
    'shipments': [for (final sh in ships) _docShipment(w, sh)],
    'acceptedLiters': accepted,
    'inProcessLiters': liters.inProcess,
    'remainingLiters': ((o['quantityLiters'] as num) - accepted).clamp(0, 1e12),
    'activeShipmentCount': ships.where((s) => s['status'] != 5).length,
    'timeline': timeline,
    'approvedEvent': approved,
    'viewerCanManage': CmFake.isBayi(viewer),
    'viewerIsPlatform': CmFake.isPlatform(viewer),
    'printedAt': FakeWorld.local(DateTime.now()),
    'printedBy': viewer.displayName,
    'isApproved': isApproved,
    'isVoid': status == 4 || status == 6,
    'canReconcile': isApproved && ships.any((s) => s['status'] != 5),
    'acceptedAmountTry': selectedQuote == null
        ? null
        : double.parse(
            (accepted * (selectedQuote['unitPriceTry'] as num)).toStringAsFixed(
              2,
            ),
          ),
    'paymentMethodCode': o['paymentMethodCode'],
    'paymentMethodName': o['paymentMethodName'],
    'paymentTermDays': o['paymentTermDays'],
    'paymentDueDate': o['paymentDueDate'],
    'paymentInstallments': o['paymentInstallments'],
    'paymentStatus': o['paymentStatus'],
    'financeStatus': o['financeStatus'],
    'paymentDetails': pricesLoaded
        ? CmFake.paymentDetails(w, o)
        : const <Object>[],
    'hasPayment': (o['paymentMethodCode'] as String?)?.isNotEmpty ?? false,
    'paymentLine': CmFake.paymentLine(o),
    'paymentMethodDisplay': o['paymentMethodName'] ?? 'Belirtilmemiş',
    'paymentStatusText': CmFake.paymentStatusText(o) ?? 'Belirtilmemiş',
  };
}

List<JsonMap> _timeline(
  FakeWorld w,
  JsonMap o,
  List<JsonMap> quotes,
  List<JsonMap> ships,
) {
  final status = o['status'] as int;
  final created = CmFake.instant(o['createdAt']) ?? DateTime.now().toUtc();
  final customerName =
      w.personaByUserId(o['createdByUserId'] as String?)?.displayName ??
      (w.customerTitle(o['customerId'] as int?) ?? 'Müşteri');
  final out = <JsonMap>[];
  JsonMap t(int from, int to, DateTime at, String who, [String? note]) => {
    'fromStatus': from,
    'toStatus': to,
    'note': note,
    'changedAt': FakeWorld.local(at),
    'changedByDisplay': who,
  };
  out.add(t(0, 1, created, customerName, 'Sipariş oluşturuldu'));
  var last = 1;
  for (final q in quotes) {
    final at = CmFake.instant(q['createdAt']) ?? created;
    out.add(t(last, 2, at, 'Gizem Şahin', 'Teklif v${q['version']} verildi'));
    last = 2;
    final note = q['revisionNote'] as String?;
    if (note != null && note.isNotEmpty) {
      out.add(t(2, 5, at.add(const Duration(hours: 1)), customerName, note));
      last = 5;
    }
  }
  if (status == 3 || status == 7) {
    final q = quotes.isEmpty ? null : quotes.last;
    final at = (CmFake.instant(q?['createdAt']) ?? created).add(
      const Duration(minutes: 40),
    );
    out.add(t(last, 3, at, customerName, 'Teklif onaylandı'));
    last = 3;
  }
  if (status == 7) {
    DateTime? at;
    for (final s in ships) {
      final a = CmFake.instant(s['acceptedAt']);
      if (a != null && (at == null || a.isAfter(at))) at = a;
    }
    out.add(
      t(
        3,
        7,
        at ?? created.add(const Duration(days: 1)),
        customerName,
        'Tüm litre müşteri tarafından teslim alındı.',
      ),
    );
  }
  if (status == 4) {
    out.add(t(last, 4, created.add(const Duration(hours: 3)), customerName));
  }
  if (status == 6) {
    out.add(
      t(
        last,
        6,
        CmFake.instant(o['expiresAt']) ?? created,
        'Sistem',
        'Teklif süresi doldu',
      ),
    );
  }
  return out;
}

String _orderStatusLabel(int s) => switch (s) {
  0 => 'Oluşturuldu',
  1 => 'Teklif bekleniyor',
  2 => 'Onay bekleniyor',
  3 => 'Onaylandı',
  4 => 'Reddedildi',
  5 => 'Revize istendi',
  6 => 'Süresi doldu',
  7 => 'Tamamlandı',
  _ => 'Bilinmiyor',
};
