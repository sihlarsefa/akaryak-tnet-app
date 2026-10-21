import '../../../core/auth/permissions.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';
import '../../../core/models/me_access.dart';
import '../../../core/network/fake/fake_personas.dart';
import '../../../core/network/fake/fake_server.dart';
import '../../../core/network/fake/fake_world.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../../../core/utils/validators.dart';
import 'fake_support.dart';
import 'order_support.dart';
import 'seed.dart';

/// Sevkiyat: pano, öneriler, şoför listesi, plan, şoför ataması, yola çıkar, teslim bildir, iptal ve
/// paylaşılan okuma uçları (liste, sipariş sevkiyatları, ayrıntı).
void registerBayiDispatchFakes(FakeServer s) {
  s.get('shipments/board', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationShipmentBoard, Perm.view)]);
    return _board(req.world, p, days: req.queryInt('days') == 1 ? 1 : 7);
  });

  s.get('shipments/board/suggestions', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationShipmentBoard, Perm.view)]);
    final w = req.world;
    final ships = [
      for (final x in w.shipments)
        if (x['stationId'] == p.stationId) x,
    ]..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final plates = <String, JsonMap>{};
    final drivers = <String, JsonMap>{};
    for (final x in ships) {
      final plate = '${x['vehiclePlate'] ?? ''}'.trim();
      final driver = '${x['driverName'] ?? ''}'.trim();
      if (plate.isNotEmpty) {
        plates.putIfAbsent(plate, () => {'value': plate, 'pair': driver});
      }
      if (driver.isNotEmpty) {
        drivers.putIfAbsent(driver, () => {'value': driver, 'pair': plate});
      }
    }
    return {
      'plates': plates.values.take(20).toList(),
      'drivers': drivers.values.take(20).toList(),
    };
  });

  s.get('stations/me/drivers', (req) {
    final p = bayiUser(req);
    if (isOwnOnly(p)) throw FakeResponse.forbidden();
    requireAny(p, const [
      (Pg.stationShipments, Perm.create),
      (Pg.stationShipmentBoard, Perm.view),
    ]);
    return _drivers(req.server, req.world, p.stationId!);
  });

  s.post('shipments', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationShipments, Perm.create)]);
    if (isOwnOnly(p)) {
      throw FakeResponse.forbidden(
        'Sevkiyat planlama yetkiniz yok (yalnızca kendi sevkiyatlarınızı görebilirsiniz).',
      );
    }
    final w = req.world;
    final r = req.json;
    final o = w.order(r.integer('orderId'));
    if (o == null || o['stationId'] != p.stationId) {
      throw FakeResponse.notFound('Sipariş bulunamadı.');
    }
    if (st(o) != 3) {
      throw FakeResponse.business(
        'Yalnızca onaylanmış siparişe sevkiyat planlanabilir.',
      );
    }
    final liters = r.decOrNull('plannedLiters') ?? 0;
    final plate = r.str('vehiclePlate').trim();
    final driverName = r.str('driverName').trim();
    final scheduled = TrTime.parseLocal(r.strOrNull('scheduledAt'));
    if (liters <= 0 ||
        roundTo(liters, 3) != liters ||
        plate.isEmpty ||
        plate.length > 20 ||
        driverName.isEmpty ||
        driverName.length > 150 ||
        scheduled == null ||
        scheduled.isBefore(TrTime.todayStart())) {
      throw FakeResponse.business(
        'Miktar, plaka, sürücü ve geçerli plan tarihi zorunludur.',
      );
    }
    if (liters > remainingLiters(w, o) + 0.0005) {
      throw FakeResponse.business(
        'Planlanan sevkiyat miktarı siparişin kalan litresini aşıyor.',
      );
    }
    var driverUserId = r.nonEmpty('driverUserId');
    if (driverUserId != null) {
      if (!eligibleDriver(w, p.stationId!, driverUserId)) {
        throw FakeResponse.business(
          'Seçilen şoför bu bayide atanabilir değil; şoför listesini yenileyip tekrar seçin.',
        );
      }
    } else {
      driverUserId = _matchDriver(w, p.stationId!, driverName);
    }
    final id = w.nextId('shipment', start: 5001);
    final ship = w.newShipment(
      id: id,
      orderId: o['id'] as int,
      plannedLiters: liters,
      status: 0,
      scheduledAt: scheduled,
      vehiclePlate: Validators.plate(plate) == null
          ? _fmtPlate(plate)
          : plate.asciiUpper,
      driverName: driverName,
      driverUserId: driverUserId,
    );
    w.shipments.add(ship);
    if (driverUserId != null) {
      notify(
        w,
        userIds: [driverUserId],
        actorId: p.userId,
        category: 'shipments',
        eventCode: 'shipment.assigned',
        title: 'Yeni teslimat atandı',
        body:
            '${o['orderNumber']}, ${_fmtLiters(liters)}, ${o['deliveryPointName']}',
        route: '/driver/shipments/$id',
        entityType: 'Shipment',
        entityId: id,
      );
    }
    notify(
      w,
      userIds: customerUsersWith(o['customerId'] as int, 'CustomerShipments'),
      actorId: p.userId,
      category: 'shipments',
      eventCode: 'shipment.planned',
      title: 'Sevkiyat planlandı',
      body: '${o['orderNumber']} için teslimat planlandı.',
      route: '/orders/${o['id']}',
      entityType: 'Order',
      entityId: o['id'] as int,
    );
    return FakeResponse.noContent();
  });

  s.post('shipments/{id}/assign-driver', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationShipments, Perm.edit)]);
    requireAny(p, const [(Pg.stationShipments, Perm.create)]);
    if (isOwnOnly(p)) {
      throw FakeResponse.forbidden(
        'Şoför atama yetkiniz yok (yalnızca kendi sevkiyatlarınızı görebilirsiniz).',
      );
    }
    final w = req.world;
    final ship = _stationShipment(w, p, req.intParam('id'));
    if (ship['status'] != 0) {
      throw FakeResponse.business(
        'Yalnızca planlı sevkiyatın şoförü değiştirilebilir.',
      );
    }
    final driverId = req.json.nonEmpty('driverUserId');
    if (driverId == null) throw FakeResponse.business('Şoför seçin.');
    if (!eligibleDriver(w, p.stationId!, driverId)) {
      throw FakeResponse.business('Seçilen şoför bu bayide atanabilir değil.');
    }
    final plate = req.json.nonEmpty('vehiclePlate');
    if (plate != null && plate.length > 20) {
      throw FakeResponse.business('Plaka en çok 20 karakter olabilir.');
    }
    final previous = ship['driverUserId'] as String?;
    ship['driverUserId'] = driverId;
    ship['driverName'] = staffName(driverId) ?? ship['driverName'];
    if (plate != null) {
      ship['vehiclePlate'] = Validators.plate(plate) == null
          ? _fmtPlate(plate)
          : plate.asciiUpper;
    }
    if (previous != driverId) {
      notify(
        w,
        userIds: [driverId],
        actorId: p.userId,
        category: 'shipments',
        eventCode: 'shipment.assigned',
        title: 'Yeni teslimat atandı',
        body:
            '${ship['orderNumber']}, ${_fmtLiters((ship['plannedLiters'] as num).toDouble())}',
        route: '/driver/shipments/${ship['id']}',
        entityType: 'Shipment',
        entityId: ship['id'] as int,
      );
      if (previous != null) {
        notify(
          w,
          userIds: [previous],
          actorId: p.userId,
          category: 'shipments',
          eventCode: 'shipment.unassigned',
          title: 'Teslimat başka şoföre verildi',
          body: '${ship['orderNumber']} artık listenizde değil.',
          route: '/driver',
          entityType: 'Shipment',
          entityId: ship['id'] as int,
        );
      }
    }
    return FakeResponse.noContent();
  });

  s.post('shipments/{id}/dispatch', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationShipments, Perm.edit)]);
    final w = req.world;
    final ship = _stationShipment(w, p, req.intParam('id'));
    _requireOwn(p, ship);
    if (ship['status'] != 0) {
      throw FakeResponse.business(
        'Yalnızca planlı sevkiyat yola çıkarılabilir.',
      );
    }
    ship['status'] = 1;
    ship['dispatchedAt'] = FakeWorld.local(TrTime.now());
    final o = w.order(ship['orderId'] as int);
    if (o != null) {
      notify(
        w,
        userIds: customerUsersWith(o['customerId'] as int, 'CustomerShipments'),
        actorId: p.userId,
        category: 'shipments',
        eventCode: 'shipment.dispatched',
        title: 'Aracınız yola çıktı',
        body: '${o['orderNumber']} siparişinizin teslimatı yolda.',
        route: '/orders/${o['id']}',
        entityType: 'Order',
        entityId: o['id'] as int,
      );
    }
    return FakeResponse.noContent();
  });

  s.post('shipments/{id}/report', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationShipments, Perm.edit)]);
    final w = req.world;
    final ship = _stationShipment(w, p, req.intParam('id'));
    _requireOwn(p, ship);
    final status = ship['status'] as int;
    if (status != 1 && status != 4) {
      throw FakeResponse.business('Bu sevkiyat için teslimat bildirilemez.');
    }
    final liters = req.json.decOrNull('deliveredLiters') ?? 0;
    final doc = req.json.str('deliveryDocumentNo').trim();
    final planned = (ship['plannedLiters'] as num).toDouble();
    if (liters <= 0 ||
        roundTo(liters, 3) != liters ||
        liters > planned ||
        doc.isEmpty ||
        doc.length > 100) {
      throw FakeResponse.business(
        'Teslim edilen litre planı aşamaz; irsaliye/belge numarası zorunludur.',
      );
    }
    ship['deliveredLiters'] = liters;
    ship['deliveryDocumentNo'] = doc;
    ship['deliveredAt'] = FakeWorld.local(TrTime.now());
    ship['status'] = 2;
    w.bag<Map<int, String>>(BayiBags.reportedBy, () => {})[ship['id'] as int] =
        p.userId;
    final o = w.order(ship['orderId'] as int);
    if (o != null) {
      notify(
        w,
        userIds: customerUsersWith(o['customerId'] as int, 'CustomerShipments'),
        actorId: p.userId,
        category: 'shipments',
        eventCode: 'shipment.reported',
        title: 'Teslimatı onaylayın',
        body:
            '${o['orderNumber']} için ${_fmtLiters(liters)} teslim edildi. Kontrol edip onaylayın.',
        route: '/shipments/${ship['id']}',
        severity: 2,
        entityType: 'Shipment',
        entityId: ship['id'] as int,
      );
    }
    return FakeResponse.noContent();
  });

  s.post('shipments/{id}/cancel', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationShipments, Perm.delete)]);
    final w = req.world;
    final ship = _stationShipment(w, p, req.intParam('id'));
    _requireOwn(p, ship);
    if (ship['status'] != 0) {
      throw FakeResponse.business(
        'Yalnızca henüz yola çıkmamış plan iptal edilebilir.',
      );
    }
    ship['status'] = 5;
    final driver = ship['driverUserId'] as String?;
    if (driver != null) {
      notify(
        w,
        userIds: [driver],
        actorId: p.userId,
        category: 'shipments',
        eventCode: 'shipment.cancelled',
        title: 'Teslimat iptal edildi',
        body: '${ship['orderNumber']} planı iptal edildi.',
        route: '/driver',
        entityType: 'Shipment',
        entityId: ship['id'] as int,
      );
    }
    return FakeResponse.noContent();
  });

  // ---- Paylaşılan okuma uçları (başka bir özellik kaydetmediyse) ----
  registerSharedIfAbsent(
    s,
    method: 'GET',
    pattern: 'shipments',
    probePath: 'shipments',
    handler: _list,
  );
  registerSharedIfAbsent(
    s,
    method: 'GET',
    pattern: 'shipments/order/{orderId:int}',
    probePath: 'shipments/order/1',
    handler: _byOrder,
  );
  registerSharedIfAbsent(
    s,
    method: 'GET',
    pattern: 'shipments/{id:int}/detail',
    probePath: 'shipments/1/detail',
    handler: _detail,
  );
}

// ------------------------------------------------------------------ Yardımcılar

String _fmtPlate(String raw) {
  final s = raw.asciiUpper.replaceAll(RegExp(r'[^0-9A-Z]'), '');
  final m = RegExp(r'^(\d{2})([A-Z]{1,3})(\d{2,5})$').firstMatch(s);
  return m == null ? raw.asciiUpper : '${m[1]} ${m[2]} ${m[3]}';
}

String _fmtLiters(double v) {
  final s = v.toStringAsFixed(0);
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '$b L';
}

JsonMap _stationShipment(FakeWorld w, FakePersona p, int id) {
  final ship = w.shipment(id);
  if (ship == null || ship['stationId'] != p.stationId) {
    throw FakeResponse.notFound('Sevkiyat bulunamadı.');
  }
  return ship;
}

void _requireOwn(FakePersona p, JsonMap ship) {
  if (isOwnOnly(p) && ship['driverUserId'] != p.userId) {
    throw FakeResponse.forbidden('Bu sevkiyat size atanmamış.');
  }
}

String? _matchDriver(FakeWorld w, int stationId, String name) {
  // Sunucu gibi Türkçe kültürle büyük/küçük harf duyarsız eşleşir.
  String n(String s) =>
      TurkishText.lower(s.trim().replaceAll(RegExp(r'\s+'), ' '));
  final matches = [
    for (final row in stationStaff(w, stationId))
      if (row['isActive'] == true &&
          (row['roleCodes'] as List).contains('driver') &&
          n(row['displayName'] as String) == n(name))
        row['userId'] as String,
  ];
  return matches.length == 1 ? matches.first : null;
}

bool _isAppDriver(FakeServer s, FakeWorld w, String? userId) {
  if (userId == null) return false;
  if (w
      .bag<Set<String>>(BayiBags.appDrivers, () => {'u-sofor', 'u-sofor3'})
      .contains(userId)) {
    return true;
  }
  final p = findFakePersona(userId);
  if (p == null) return false;
  return s.auth.sessions[p.key]?.values.any((d) => !d.revoked) ?? false;
}

List<JsonMap> _drivers(FakeServer s, FakeWorld w, int stationId) {
  final staff = stationStaff(w, stationId).where((r) => r['isActive'] == true);
  int active(String userId) => w
      .shipmentsOfDriver(userId)
      .where((x) => const {0, 1, 4}.contains(x['status']))
      .length;
  JsonMap row(JsonMap r, bool driver) => {
    'userId': r['userId'],
    'displayName': r['displayName'],
    'phone': r['phoneNumber'],
    'isDriverRole': driver,
    'hasActiveDevice': _isAppDriver(s, w, r['userId'] as String),
    'activeShipments': active(r['userId'] as String),
  };
  final drivers = <JsonMap>[];
  final others = <JsonMap>[];
  for (final r in staff) {
    final codes = (r['roleCodes'] as List).cast<String>();
    if (codes.contains('driver')) {
      drivers.add(row(r, true));
    } else {
      final p = findFakePersona(r['userId'] as String?);
      if (p != null && p.can(Pg.stationShipments, Perm.edit)) {
        others.add(row(r, false));
      }
    }
  }
  int byName(JsonMap a, JsonMap b) =>
      (a['displayName'] as String).compareTo(b['displayName'] as String);
  return [...drivers..sort(byName), ...others..sort(byName)];
}

JsonMap _board(FakeWorld w, FakePersona p, {required int days}) {
  final today = TrTime.todayStart();
  final tomorrow = TrTime.addDays(today, 1);
  final dayAfter = TrTime.addDays(today, 2);
  final weekday = TrTime.wall(today).weekday; // 1 Pazartesi … 7 Pazar
  final weekEnd = TrTime.addDays(today, 8 - weekday);
  int bucketOf(DateTime d) {
    if (d.isBefore(today)) return 0;
    if (d.isBefore(tomorrow)) return 1;
    if (d.isBefore(dayAfter)) return 2;
    if (d.isBefore(weekEnd)) return 3;
    return 4;
  }

  final orders = <JsonMap>[];
  for (final o in w.ordersOfStation(p.stationId!)) {
    if (st(o) != 3) continue;
    final rest = remainingLiters(w, o);
    if (rest <= 0) continue;
    final totals = shipmentTotals(w, o['id'] as int);
    final requested = local(o['requestedDeliveryDate']) ?? today;
    final q = currentQuote(o);
    final dp = w.deliveryPoint(o['deliveryPointId'] as int?);
    String? span(Object? hhmm) => hhmm == null ? null : '$hhmm:00';
    orders.add({
      'orderId': o['id'],
      'orderNumber': o['orderNumber'],
      'requestedDeliveryDate': o['requestedDeliveryDate'],
      'quoteDeliveryDate': q?['deliveryDate'],
      'quantityLiters': qty(o),
      'allocatedLiters': totals.allocated,
      'acceptedLiters': totals.accepted,
      'openShipmentCount': totals.open,
      'productName': o['productName'],
      'productCode': w.product(o['productId'] as int?)?['code'],
      'customerTitle': o['customerTitle'],
      'customerCode': 'C-${o['customerId']}',
      'deliveryPointName': o['deliveryPointName'],
      'deliveryCity': dp?['city'],
      'deliveryDistrict': dp?['district'],
      'deliveryWindowStart': span(dp?['windowStart']),
      'deliveryWindowEnd': span(dp?['windowEnd']),
      'tankCapacityLiters': dp?['tankCapacityLiters'],
      'contactName': dp?['contactName'],
      'contactPhone': dp?['contactPhone'],
      'bucket': bucketOf(requested),
      'remainingLiters': rest,
    });
  }
  orders.sort((a, b) {
    final ba = a['bucket'] as int;
    final bb = b['bucket'] as int;
    if (ba != bb) return ba.compareTo(bb);
    final da = local(a['requestedDeliveryDate']) ?? today;
    final db = local(b['requestedDeliveryDate']) ?? today;
    return ba == 0 ? db.compareTo(da) : da.compareTo(db);
  });
  final buckets = <int, JsonMap>{};
  for (final o in orders) {
    final b = buckets.putIfAbsent(
      o['bucket'] as int,
      () => {'bucket': o['bucket'], 'count': 0, 'liters': 0.0},
    );
    b['count'] = (b['count'] as int) + 1;
    b['liters'] = (b['liters'] as double) + (o['remainingLiters'] as double);
  }
  final end = TrTime.addDays(today, days);
  final open =
      [
        for (final x in w.shipments)
          if (x['stationId'] == p.stationId &&
              (x['status'] == 0 || x['status'] == 1) &&
              (local(x['scheduledAt']) ?? today).isBefore(end))
            x,
      ]..sort(
        (a, b) => (local(a['scheduledAt']) ?? today).compareTo(
          local(b['scheduledAt']) ?? today,
        ),
      );
  final dps = {for (final d in w.deliveryPoints) d['id']: d};
  final shipments = [
    for (final x in open)
      {
        'id': x['id'],
        'orderId': x['orderId'],
        'orderNumber': x['orderNumber'],
        'status': x['status'],
        'scheduledAt': x['scheduledAt'],
        'plannedLiters': x['plannedLiters'],
        'vehiclePlate': x['vehiclePlate'],
        'driverName': x['driverName'],
        'productName': x['productName'],
        'customerTitle': x['customerName'],
        'deliveryPointName': x['deliveryPointName'],
        'deliveryCity': x['deliveryCity'],
        'deliveryWindowStart': dps[x['deliveryPointId']]?['windowStart'] == null
            ? null
            : '${dps[x['deliveryPointId']]!['windowStart']}:00',
        'deliveryWindowEnd': dps[x['deliveryPointId']]?['windowEnd'] == null
            ? null
            : '${dps[x['deliveryPointId']]!['windowEnd']}:00',
        'driverUserId': x['driverUserId'],
        'driverAccountName': staffName(x['driverUserId'] as String?),
        'isAppDriver': _isAppDriverWorld(w, x['driverUserId'] as String?),
      },
  ];
  double sum(Iterable<JsonMap> rows) => rows.fold<double>(
    0,
    (s, x) => s + (x['plannedLiters'] as num).toDouble(),
  );
  final planned = open.where((x) => x['status'] == 0);
  final transit = open.where((x) => x['status'] == 1);
  final bucketList = buckets.values.toList()
    ..sort((a, b) => (a['bucket'] as int).compareTo(b['bucket'] as int));
  return {
    'station': {
      'id': p.stationId,
      'title': w.stationTitle(p.stationId),
      'code': w.station(p.stationId)?['code'],
      'isActive': true,
    },
    'orders': orders,
    'buckets': bucketList,
    'orderTotal': orders.length,
    'orderTotalLiters': orders.fold<double>(
      0,
      (s, o) => s + (o['remainingLiters'] as double),
    ),
    'shipments': shipments,
    'shipmentsTruncated': false,
    'earlierShipmentsTruncated': false,
    'plannedCount': planned.length,
    'plannedLiters': sum(planned),
    'inTransitCount': transit.length,
    'inTransitLiters': sum(transit),
    'unassignedCount': w.shipments
        .where(
          (x) =>
              x['stationId'] == p.stationId &&
              x['status'] == 0 &&
              x['driverUserId'] == null,
        )
        .length,
  };
}

bool _isAppDriverWorld(FakeWorld w, String? userId) =>
    userId != null &&
    w
        .bag<Set<String>>(BayiBags.appDrivers, () => {'u-sofor', 'u-sofor3'})
        .contains(userId);

/// `GET shipments` (paylaşılan): bayi kendi bayisi (şoför yalnızca kendisi), cari kendi carisi.
Object _list(FakeRequest req) {
  final p = req.requireUser();
  final w = req.world;
  ensureBayiSeed(w);
  Iterable<JsonMap> scope;
  switch (p.persona) {
    case Persona.bayi:
      requireAny(p, const [
        (Pg.stationShipments, Perm.view),
        (Pg.stationShipmentBoard, Perm.view),
      ]);
      scope = w.shipments.where((x) => x['stationId'] == p.stationId);
      if (isOwnOnly(p)) {
        scope = scope.where((x) => x['driverUserId'] == p.userId);
      }
    case Persona.customer:
      requireAny(p, const [
        (Pg.customerShipments, Perm.view),
        (Pg.customerOrders, Perm.view),
      ]);
      scope = w.shipments.where((x) => x['customerId'] == p.customerId);
    case Persona.platform:
      scope = w.shipments;
    case Persona.unknown:
      throw FakeResponse.forbidden();
  }
  final statuses = queryInts(req, 'statuses');
  final single = req.queryInt('status');
  if (statuses.isEmpty && single != null) statuses.add(single);
  final dispute = req.queryBool('hasDispute');
  final from = queryDate(req, 'scheduledFrom');
  final to = queryDate(req, 'scheduledTo');
  final search = req.query('search')?.trim() ?? '';
  final customerId = req.queryInt('customerId');
  final base = scope.where((x) {
    final at = local(x['scheduledAt']);
    if (from != null && (at == null || at.isBefore(from))) return false;
    if (to != null && (at == null || !at.isBefore(TrTime.addDays(to, 1)))) {
      return false;
    }
    if (dispute != null) {
      final has = '${x['disputeNote'] ?? ''}'.isNotEmpty;
      if (has != dispute) return false;
    }
    if (customerId != null && x['customerId'] != customerId) return false;
    if (search.isNotEmpty &&
        !(textContains(x['code'], search) ||
            textContains(x['orderNumber'], search) ||
            textContains(x['vehiclePlate'], search) ||
            textContains(x['driverName'], search) ||
            textContains(x['customerName'], search) ||
            textContains(x['deliveryDocumentNo'], search))) {
      return false;
    }
    return true;
  }).toList();
  final items = base
      .where((x) => statuses.isEmpty || statuses.contains(x['status']))
      .toList();
  final sort = req.queryInt('sort') ?? 0;
  DateTime at(JsonMap x, String k) => local(x[k]) ?? TrTime.now();
  switch (sort) {
    case 1:
      items.sort(
        (a, b) => at(a, 'scheduledAt').compareTo(at(b, 'scheduledAt')),
      );
    case 2:
      items.sort(
        (a, b) => at(b, 'scheduledAt').compareTo(at(a, 'scheduledAt')),
      );
    case 3:
      items.sort(
        (a, b) => at(b, 'deliveredAt').compareTo(at(a, 'deliveredAt')),
      );
    default:
      items.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
  }
  final page = (req.queryInt('page') ?? 1).clamp(1, 1 << 20);
  final rawSize = req.queryInt('pageSize') ?? 50;
  final size = rawSize <= 25 ? 25 : (rawSize <= 50 ? 50 : 100);
  final start = (page - 1) * size;
  final slice = start >= items.length
      ? const <JsonMap>[]
      : items.sublist(start, (start + size).clamp(0, items.length));
  int count(int status) => base.where((x) => x['status'] == status).length;
  final customer = p.persona == Persona.customer;
  return {
    'filter': {'page': page, 'pageSize': size},
    'items': [for (final x in slice) _listItem(w, x, customer: customer)],
    'totalFiltered': items.length,
    'page': page,
    'pageSize': size,
    'totalPages': items.isEmpty ? 1 : (items.length / size).ceil(),
    'countAll': base.length,
    'countPlanned': count(0),
    'countInTransit': count(1),
    'countReported': count(2),
    'countAccepted': count(3),
    'countDisputed': count(4),
    'countCancelled': count(5),
  };
}

JsonMap _listItem(FakeWorld w, JsonMap x, {required bool customer}) => {
  'id': x['id'],
  'orderId': x['orderId'],
  'orderNumber': x['orderNumber'],
  'stationId': x['stationId'],
  'stationName': x['stationName'],
  'stationCode': w.station(x['stationId'] as int?)?['code'] ?? '',
  'stationCity': w.station(x['stationId'] as int?)?['city'] ?? '',
  'stationDistrict': w.station(x['stationId'] as int?)?['district'] ?? '',
  'customerId': x['customerId'],
  'customerName': x['customerName'],
  'customerCity': x['customerCity'] ?? '',
  'productId': x['productId'],
  'productName': x['productName'],
  'plannedLiters': x['plannedLiters'],
  'deliveredLiters': x['deliveredLiters'],
  'vehiclePlate': x['vehiclePlate'],
  'driverName': x['driverName'],
  'scheduledAt': x['scheduledAt'],
  'deliveredAt': x['deliveredAt'],
  'deliveryDocumentNo': x['deliveryDocumentNo'],
  'status': x['status'],
  'disputeNote': x['disputeNote'],
  'orderStatus': w.order(x['orderId'] as int?)?['status'] ?? x['orderStatus'],
  'deliveryAddress': x['deliveryAddress'],
  'acceptedAt': x['acceptedAt'],
  'createdAt': x['createdAt'],
  'requestedDeliveryDate': x['requestedDeliveryDate'],
  'deliveryPointName': x['deliveryPointName'],
  'deliveryCity': x['deliveryCity'],
  'deliveryDistrict': x['deliveryDistrict'],
  'driverUserId': customer ? null : x['driverUserId'],
  'code': x['code'],
  'differenceLiters': x['deliveredLiters'] == null
      ? null
      : (x['deliveredLiters'] as num) - (x['plannedLiters'] as num),
};

/// `GET shipments/order/{orderId}` (paylaşılan): `FulfillmentDto`.
Object _byOrder(FakeRequest req) {
  final p = req.requireUser();
  final w = req.world;
  ensureBayiSeed(w);
  final o = w.order(req.intParam('orderId'));
  if (o == null) throw FakeResponse.notFound('Sipariş bulunamadı.');
  var canManage = false;
  var canAccept = false;
  var ownOnly = false;
  switch (p.persona) {
    case Persona.bayi:
      requireAny(p, const [
        (Pg.stationShipments, Perm.view),
        (Pg.stationOrders, Perm.view),
      ]);
      if (o['stationId'] != p.stationId) {
        throw FakeResponse.notFound('Sipariş bulunamadı.');
      }
      ownOnly = isOwnOnly(p);
      canManage = !ownOnly && p.can(Pg.stationShipments, Perm.create);
    case Persona.customer:
      requireAny(p, const [
        (Pg.customerShipments, Perm.view),
        (Pg.customerOrders, Perm.view),
      ]);
      if (o['customerId'] != p.customerId) {
        throw FakeResponse.notFound('Sipariş bulunamadı.');
      }
      canAccept = p.can(Pg.customerShipments, Perm.edit);
    case Persona.platform:
      break;
    case Persona.unknown:
      throw FakeResponse.forbidden();
  }
  final ships = [
    for (final x in w.shipmentsOfOrder(o['id'] as int))
      if (!ownOnly || x['driverUserId'] == p.userId) x,
  ]..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
  if (ownOnly && ships.isEmpty) throw FakeResponse.forbidden();
  return {
    'orderId': o['id'],
    'orderNumber': o['orderNumber'],
    'deliveryAddress': o['deliveryAddress'],
    'orderedLiters': qty(o),
    'acceptedLiters': shipmentTotals(w, o['id'] as int).accepted,
    'canManage': canManage,
    'canAccept': canAccept,
    'isOpen': st(o) == 3,
    'shipments': [
      for (final x in ships)
        {
          'id': x['id'],
          'plannedLiters': x['plannedLiters'],
          'deliveredLiters': x['deliveredLiters'],
          'vehiclePlate': x['vehiclePlate'],
          'driverName': x['driverName'],
          'scheduledAt': x['scheduledAt'],
          'deliveryDocumentNo': x['deliveryDocumentNo'],
          'status': x['status'],
          'disputeNote': x['disputeNote'],
        },
    ],
  };
}

/// `GET shipments/{id}/detail` (paylaşılan): bayi / cari / merkez görünümü (spec B.10, B7 notları).
Object _detail(FakeRequest req) {
  final p = req.requireUser();
  final w = req.world;
  ensureBayiSeed(w);
  final x = w.shipment(req.intParam('id'));
  if (x == null) throw FakeResponse.notFound('Sevkiyat bulunamadı.');
  final o = w.order(x['orderId'] as int?);
  String side;
  switch (p.persona) {
    case Persona.bayi:
      requireAny(p, const [
        (Pg.stationShipments, Perm.view),
        (Pg.stationShipmentBoard, Perm.view),
      ]);
      if (x['stationId'] != p.stationId) {
        throw FakeResponse.notFound('Sevkiyat bulunamadı.');
      }
      if (isOwnOnly(p) && x['driverUserId'] != p.userId) {
        throw FakeResponse.notFound('Sevkiyat bulunamadı.');
      }
      side = 'bayi';
    case Persona.customer:
      requireAny(p, const [
        (Pg.customerShipments, Perm.view),
        (Pg.customerOrders, Perm.view),
      ]);
      if (x['customerId'] != p.customerId) {
        throw FakeResponse.notFound('Sevkiyat bulunamadı.');
      }
      side = 'customer';
    case Persona.platform:
      side = 'platform';
    case Persona.unknown:
      throw FakeResponse.forbidden();
  }
  final status = x['status'] as int;
  final approved = o == null || st(o) == 3;
  final bayi = side == 'bayi' && !isOwnOnly(p) && approved;
  final customer =
      side == 'customer' && approved && p.can(Pg.customerShipments, Perm.edit);
  final dp = w.deliveryPoint(x['deliveryPointId'] as int?);
  final planned = (x['plannedLiters'] as num).toDouble();
  final delivered = (x['deliveredLiters'] as num?)?.toDouble();
  final note = x['deliveryNote'] as String?;
  final reportedBy =
      w.bag<Map<int, String>>(BayiBags.reportedBy, () => {})[x['id']] ??
      (status >= 2 && status != 5 ? x['driverUserId'] as String? : null);
  final internal = side != 'customer';
  return {
    'id': x['id'],
    'code': x['code'],
    'orderId': x['orderId'],
    'orderNumber': x['orderNumber'],
    'status': status,
    'statusLabel': ShipmentStatus.fromCode(status).label,
    'viewerSide': side,
    'stationTitle': x['stationName'],
    'customerTitle': x['customerName'],
    'productName': x['productName'],
    'plannedLiters': planned,
    'deliveredLiters': delivered,
    'differenceLiters': delivered == null
        ? null
        : roundTo(delivered - planned, 3),
    'scheduledAt': offset(local(x['scheduledAt'])),
    'dispatchedAt': offset(local(x['dispatchedAt'])),
    'deliveredAt': offset(local(x['deliveredAt'])),
    'deviceDeliveredAtUtc': null,
    'timeSource': delivered == null ? null : 'server',
    'acceptedAt': offset(local(x['acceptedAt'])),
    'vehiclePlate': x['vehiclePlate'],
    'driverUserId': internal ? x['driverUserId'] : null,
    'driverName': x['driverName'],
    'driverAccountName': internal
        ? staffName(x['driverUserId'] as String?)
        : null,
    'isAppDriver': internal
        ? _isAppDriver(req.server, w, x['driverUserId'] as String?)
        : null,
    'deliveryDocumentNo': x['deliveryDocumentNo'],
    'recipientName': x['recipientName'],
    'deliveryNote': note,
    'signatureWaiverLabel': null,
    'disputeNote': x['disputeNote'],
    'deliveredLatitude': null,
    'deliveredLongitude': null,
    'deliveredAccuracyMeters': null,
    'distanceToDeliveryPointMeters': internal && delivered != null ? 85 : null,
    'reportedByName': internal ? staffName(reportedBy) : null,
    'deliveryPoint': {
      'name': x['deliveryPointName'],
      'address': dp?['address'] ?? x['deliveryAddress'],
      'city': dp?['city'] ?? x['deliveryCity'],
      'district': dp?['district'] ?? x['deliveryDistrict'],
      'latitude': dp?['latitude'],
      'longitude': dp?['longitude'],
      'windowStart': dp?['windowStart'],
      'windowEnd': dp?['windowEnd'],
    },
    'attachments': [
      for (final a in w.attachments)
        if (a['ownerType'] == 10 &&
            a['ownerId'] == x['id'] &&
            a['isActive'] == true)
          a,
    ],
    'actions': {
      'canDispatch':
          bayi && status == 0 && p.can(Pg.stationShipments, Perm.edit),
      'canReport':
          bayi &&
          (status == 1 || status == 4) &&
          p.can(Pg.stationShipments, Perm.edit),
      'canReassign':
          bayi &&
          status == 0 &&
          p.can(Pg.stationShipments, Perm.create) &&
          p.can(Pg.stationShipments, Perm.edit),
      'canCancel':
          bayi && status == 0 && p.can(Pg.stationShipments, Perm.delete),
      'canAccept': customer && status == 2,
      'canDispute': customer && status == 2,
      'canAddDisputePhoto': customer && (status == 2 || status == 4),
    },
  };
}
