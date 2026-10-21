import 'dart:typed_data';

import '../../../core/auth/permissions.dart';
import '../../../core/models/json.dart';
import '../../../core/network/fake/core_fakes.dart';
import '../../../core/network/fake/fake_personas.dart';
import '../../../core/network/fake/fake_server.dart';
import '../../../core/network/fake/fake_world.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import 'cm_fake_images.dart';
import 'cm_fake_support.dart';

/// `GET shipments` (her persona için kapsamlı), `GET shipments/{id}/detail`, kabul ve itiraz.
void registerCmShipmentFakes(FakeServer s) {
  s.get('shipments', (req) => _list(req));
  s.get('shipments/{id:int}/detail', (req) {
    final p = req.requireUser();
    final sh = _visible(req, p, req.intParam('id'));
    return shipmentDetailJson(req.world, p, sh);
  });
  s.post('shipments/{id:int}/accept', (req) {
    final p = _customerEditor(req);
    final sh = _visible(req, p, req.intParam('id'));
    if (sh['status'] != 2) {
      throw FakeResponse.business(
        'Yalnızca bildirilen teslimat kabul edilebilir.',
      );
    }
    final w = req.world;
    final order = w.order(sh['orderId'] as int)!;
    final prev = w
        .shipmentsOfOrder(order['id'] as int)
        .where((x) => x['status'] == 3)
        .fold<double>(
          0,
          (sum, x) => sum + ((x['deliveredLiters'] as num?)?.toDouble() ?? 0),
        );
    final delivered = prev + ((sh['deliveredLiters'] as num?)?.toDouble() ?? 0);
    final qty = (order['quantityLiters'] as num).toDouble();
    if (delivered > qty + 0.0001) {
      throw FakeResponse.business('Kabul edilen miktar siparişi aşıyor.');
    }
    sh['status'] = 3;
    sh['acceptedAt'] = FakeWorld.local(DateTime.now());
    sh['acceptedByUserId'] = p.userId;
    sh['acceptedByName'] = p.displayName;
    if ((delivered - qty).abs() < 0.0001) order['status'] = 7;
    _notifyBayi(
      w,
      sh,
      'shipment.accepted',
      'Teslimat kabul edildi',
      '${sh['orderNumber']}, ${sh['code']} müşteri tarafından kabul edildi.',
      severity: 1,
    );
    return null;
  });
  s.post('shipments/{id:int}/dispute', (req) {
    final p = _customerEditor(req);
    final sh = _visible(req, p, req.intParam('id'));
    final note = req.json.str('note').trim();
    if (sh['status'] != 2 || note.isEmpty || note.length > 1000) {
      throw FakeResponse.business(
        'Bildirilen teslimat ve en fazla 1000 karakter açıklama gerekli.',
      );
    }
    sh['status'] = 4;
    sh['disputeNote'] = note;
    _notifyBayi(
      req.world,
      sh,
      'shipment.disputed',
      'Teslimata itiraz edildi',
      '${sh['orderNumber']}, ${sh['code']}: müşteri itiraz etti.',
      severity: 3,
    );
    return null;
  });
}

FakePersona _customerEditor(FakeRequest req) {
  final p = req.requireUser();
  if (!CmFake.isCustomer(p)) throw FakeResponse.forbidden();
  req.requirePage(Pg.customerShipments, Perm.edit);
  return p;
}

JsonMap _visible(FakeRequest req, FakePersona p, int id) {
  final sh = req.world.shipment(id);
  if (sh == null || !CmFake.canSeeShipment(p, sh)) {
    throw FakeResponse.notFound('Sevkiyat bulunamadı.');
  }
  return sh;
}

void _notifyBayi(
  FakeWorld w,
  JsonMap sh,
  String code,
  String title,
  String body, {
  int severity = 0,
}) {
  final route = '/bayi/orders/${sh['orderId']}';
  for (final key in const ['sahip', 'mudur', 'sevkiyat']) {
    w.addNotification(
      userId: 'u-$key',
      category: 'shipments',
      eventCode: code,
      title: title,
      body: body,
      severity: severity,
      route: route,
      entityType: 'Order',
      entityId: sh['orderId'] as int,
    );
  }
  final driver = sh['driverUserId'] as String?;
  if (driver != null) {
    w.addNotification(
      userId: driver,
      category: 'shipments',
      eventCode: code,
      title: title,
      body: body,
      severity: severity,
      route: '/driver/shipments/${sh['id']}',
      entityType: 'Shipment',
      entityId: sh['id'] as int,
    );
  }
}

Object? _list(FakeRequest req) {
  final p = req.requireUser();
  final w = req.world;
  if (CmFake.isCustomer(p)) {
    if (!p.can(Pg.customerShipments) && !p.can(Pg.customerOrders)) {
      throw FakeResponse.forbidden();
    }
  } else if (CmFake.isBayi(p)) {
    if (!p.can(Pg.stationShipments) && !p.can(Pg.stationShipmentBoard)) {
      throw FakeResponse.forbidden();
    }
  }
  var rows = w.shipments.where((sh) => CmFake.canSeeShipment(p, sh)).toList();

  final q = req.query('search')?.trim() ?? '';
  if (q.isNotEmpty) {
    rows = rows
        .where(
          (sh) => [
            sh['orderNumber'],
            sh['code'],
            sh['vehiclePlate'],
            sh['productName'],
            sh['deliveryPointName'],
            sh['deliveryDocumentNo'],
            sh['customerName'],
          ].any((v) => TurkishText.matches(v?.toString(), q)),
        )
        .toList();
  }

  int count(int status) => rows.where((r) => r['status'] == status).length;
  final counts = {
    'countAll': rows.length,
    'countPlanned': count(0),
    'countInTransit': count(1),
    'countReported': count(2),
    'countAccepted': count(3),
    'countDisputed': count(4),
    'countCancelled': count(5),
  };

  // Bayi süzgeçleri (B7 `ShipmentListFilter`): itirazlı, planlanan tarih aralığı (Türkiye günü),
  // cari. Depo "Bugünkü yüklemeler" ve "İtirazlı" bunlarla daralır (A-INT birleştirme).
  final dispute = req.queryBool('hasDispute');
  final from = TrTime.parseDate(req.query('scheduledFrom'));
  final to = TrTime.parseDate(req.query('scheduledTo'));
  final customerId = req.queryInt('customerId');
  if (dispute != null || from != null || to != null || customerId != null) {
    rows = rows.where((x) {
      if (dispute != null &&
          ('${x['disputeNote'] ?? ''}'.isNotEmpty) != dispute) {
        return false;
      }
      final at = TrTime.parseLocal(x['scheduledAt'] as String?);
      if (from != null && (at == null || at.isBefore(from))) return false;
      if (to != null && (at == null || !at.isBefore(TrTime.addDays(to, 1)))) {
        return false;
      }
      if (customerId != null && x['customerId'] != customerId) return false;
      return true;
    }).toList();
  }

  final statuses = CmFake.intsOf(req, 'statuses');
  final single = req.queryInt('status');
  if (statuses.isNotEmpty) {
    rows = rows.where((r) => statuses.contains(r['status'])).toList();
  } else if (single != null) {
    rows = rows.where((r) => r['status'] == single).toList();
  }

  int cmpScheduled(JsonMap a, JsonMap b) =>
      (a['scheduledAt'] as String).compareTo(b['scheduledAt'] as String);
  switch (req.queryInt('sort') ?? 0) {
    case 1:
      rows.sort(cmpScheduled);
    case 2:
      rows.sort((a, b) => cmpScheduled(b, a));
    case 3:
      rows.sort(
        (a, b) => ((b['deliveredAt'] as String?) ?? '').compareTo(
          (a['deliveredAt'] as String?) ?? '',
        ),
      );
    default:
      rows.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
  }

  final page = (req.queryInt('page') ?? 1).clamp(1, 100000);
  final size = (req.queryInt('pageSize') ?? 50).clamp(1, 100);
  final start = (page - 1) * size;
  final slice = start >= rows.length
      ? const <JsonMap>[]
      : rows.sublist(start, (start + size).clamp(0, rows.length));
  final customer = CmFake.isCustomer(p);
  return {
    'filter': {'page': page, 'pageSize': size, 'search': q.isEmpty ? null : q},
    'statusFilter': single,
    'items': [
      for (final r in slice)
        {
          ...r,
          'driverUserId': customer ? null : r['driverUserId'],
          'stationCode': w.station(r['stationId'] as int?)?['code'],
          'orderCreatedAt': w.order(r['orderId'] as int?)?['createdAt'],
          'differenceLiters': r['deliveredLiters'] == null
              ? null
              : (r['deliveredLiters'] as num) - (r['plannedLiters'] as num),
        },
    ],
    'totalFiltered': rows.length,
    'page': page,
    'pageSize': size,
    'totalPages': rows.isEmpty ? 1 : (rows.length / size).ceil(),
    ...counts,
    'stationOptions': const <Object>[],
    'customerOptions': const <Object>[],
    'productOptions': const <Object>[],
    'distributorOptions': const <Object>[],
    'distributorNameOptions': const <Object>[],
    'stationCityOptions': const <Object>[],
    'customerCityOptions': const <Object>[],
    'regionOptions': const <Object>[],
    'zoneOptions': const <Object>[],
    'canFilterStation': false,
    'canFilterCustomer': false,
  };
}

/// `ShipmentMobileDetailDto` (görüntüleyene göre süzülmüş; cari görünümünde iç alanlar boş).
JsonMap shipmentDetailJson(FakeWorld w, FakePersona p, JsonMap sh) {
  _seedProof(w, sh);
  final order = w.order(sh['orderId'] as int) ?? const <String, dynamic>{};
  final dp =
      w.deliveryPoint(sh['deliveryPointId'] as int?) ??
      const <String, dynamic>{};
  final status = sh['status'] as int? ?? 0;
  final customer = CmFake.isCustomer(p);
  final platform = CmFake.isPlatform(p);
  final side = customer ? 'customer' : (platform ? 'platform' : 'bayi');
  final approved = order['status'] == 3;
  final planned = (sh['plannedLiters'] as num).toDouble();
  final delivered = (sh['deliveredLiters'] as num?)?.toDouble();
  final bayi = CmFake.isBayi(p) && !CmFake.ownOnly(p);
  final editBayi = bayi && p.can(Pg.stationShipments, Perm.edit);
  final editCustomer = customer && p.can(Pg.customerShipments, Perm.edit);
  final note = sh['deliveryNote'] as String?;
  final attachments = [
    for (final a in w.attachments)
      if (a['ownerType'] == 10 &&
          a['ownerId'] == sh['id'] &&
          a['isActive'] == true)
        {
          ...a,
          'canDelete':
              a['uploadedByUserId'] == p.userId &&
              ((a['kind'] == 32 && status == 2) ||
                  ((a['kind'] == 30 || a['kind'] == 31) && status == 1)),
        },
  ];
  String? window(Object? v) => v is String && v.isNotEmpty ? v : null;
  return {
    'id': sh['id'],
    'code': sh['code'],
    'orderId': sh['orderId'],
    'orderNumber': sh['orderNumber'],
    'status': status,
    'statusLabel': _statusLabel(status),
    'viewerSide': side,
    'stationTitle': sh['stationName'],
    'customerTitle': sh['customerName'],
    'productName': sh['productName'],
    'plannedLiters': planned,
    'deliveredLiters': delivered,
    'differenceLiters': delivered == null ? null : delivered - planned,
    'scheduledAt': CmFake.offset(sh['scheduledAt']),
    'dispatchedAt': CmFake.offset(sh['dispatchedAt']),
    'deliveredAt': CmFake.offset(sh['deliveredAt']),
    'deviceDeliveredAtUtc': sh['deliveredAt'] == null
        ? null
        : CmFake.instant(sh['deliveredAt'])?.toIso8601String(),
    'timeSource': sh['deliveredAt'] == null
        ? null
        : (sh['timeSource'] as String? ?? 'device'),
    'acceptedAt': CmFake.offset(sh['acceptedAt']),
    'vehiclePlate': sh['vehiclePlate'],
    'driverUserId': customer ? null : sh['driverUserId'],
    'driverName': sh['driverName'],
    'driverAccountName': customer
        ? null
        : w.personaByUserId(sh['driverUserId'] as String?)?.displayName,
    'isAppDriver': customer ? null : sh['driverUserId'] != null,
    'deliveryDocumentNo': sh['deliveryDocumentNo'],
    'recipientName': sh['recipientName'],
    'deliveryNote': note,
    'signatureWaiverLabel': sh['signatureWaiverLabel'],
    'disputeNote': sh['disputeNote'],
    'deliveredLatitude': customer ? null : sh['deliveredLatitude'],
    'deliveredLongitude': customer ? null : sh['deliveredLongitude'],
    'deliveredAccuracyMeters': customer ? null : sh['deliveredAccuracyMeters'],
    'distanceToDeliveryPointMeters': customer ? null : sh['distanceMeters'],
    'reportedByName': customer
        ? null
        : (delivered == null ? null : sh['driverName']),
    'deliveryPoint': {
      'name': dp['name'] ?? sh['deliveryPointName'],
      'address': dp['address'] ?? sh['deliveryAddress'],
      'city': dp['city'] ?? sh['deliveryCity'],
      'district': dp['district'] ?? sh['deliveryDistrict'],
      'latitude': dp['latitude'],
      'longitude': dp['longitude'],
      'windowStart': window(dp['windowStart']),
      'windowEnd': window(dp['windowEnd']),
    },
    'attachments': attachments,
    'actions': {
      'canDispatch': editBayi && approved && status == 0,
      'canReport': editBayi && approved && (status == 1 || status == 4),
      'canReassign':
          bayi &&
          approved &&
          status == 0 &&
          p.can(Pg.stationShipments, Perm.create) &&
          p.can(Pg.stationShipments, Perm.edit),
      'canCancel':
          bayi &&
          approved &&
          status == 0 &&
          p.can(Pg.stationShipments, Perm.delete),
      'canAccept': editCustomer && approved && status == 2,
      'canDispute': editCustomer && approved && status == 2,
      'canAddDisputePhoto':
          editCustomer && approved && (status == 2 || status == 4),
    },
  };
}

String _statusLabel(int s) => switch (s) {
  0 => 'Planlandı',
  1 => 'Yolda',
  2 => 'Kabul bekliyor',
  3 => 'Teslim alındı',
  4 => 'İtirazlı',
  5 => 'İptal',
  _ => 'Bilinmiyor',
};

/// Tohum anından önce teslim edilmiş sevkiyatlara (bir kez) teslim fotoğrafı ve imza ekler.
void _seedProof(FakeWorld w, JsonMap sh) {
  final seeded = w.bag<Set<int>>('cm.proofSeeded', () => <int>{});
  final id = sh['id'] as int;
  if (seeded.contains(id)) return;
  final status = sh['status'] as int? ?? 0;
  final deliveredAt = CmFake.instant(sh['deliveredAt']);
  if (status < 2 || status == 5 || deliveredAt == null) return;
  seeded.add(id);
  if (!deliveredAt.isBefore(w.seededAt)) return;
  final hasAny = w.attachments.any(
    (a) => a['ownerType'] == 10 && a['ownerId'] == id,
  );
  if (hasAny) return;
  final driver = w.personaByUserId(sh['driverUserId'] as String?);
  for (var i = 0; i < 2; i++) {
    final a = fakeAttachment(
      w,
      ownerType: 10,
      ownerId: id,
      kind: 30,
      fileName: 'teslimat-$id-${i + 1}.jpg',
      contentType: 'image/jpeg',
      bytes: CmFakeImages.deliveryPhoto(id * 10 + i),
      uploadedBy: driver,
    );
    a['createdAt'] = deliveredAt
        .subtract(Duration(minutes: 6 - i))
        .toIso8601String();
    a['canDelete'] = false;
  }
  final sig = fakeAttachment(
    w,
    ownerType: 10,
    ownerId: id,
    kind: 31,
    fileName: 'imza-$id.png',
    contentType: 'image/png',
    bytes: Uint8List.fromList(CmFakeImages.signature()),
    uploadedBy: driver,
  );
  sig['createdAt'] = deliveredAt.toIso8601String();
  sig['canDelete'] = false;
  sh.putIfAbsent('timeSource', () => 'device');
  sh.putIfAbsent(
    'deliveryNote',
    () => 'Tank ölçümü teslim alan yetkiliyle birlikte yapıldı.',
  );
}
