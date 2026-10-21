import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../core/auth/permissions.dart';
import '../../core/models/models.dart';
import '../../core/network/fake/core_fakes.dart';
import '../../core/network/fake/fake_personas.dart';
import '../../core/network/fake/fake_server.dart';
import '../../core/network/fake/fake_world.dart';
import '../../core/utils/tr_time.dart';

/// Şoför sahte uçları (sahibi A7, spec B.10 / D.4). Ortak dünyadaki sevkiyatlar kullanılır; yola çıkış ve
/// teslim durumu ilerletir (Planlandı → Yolda → Kabul bekliyor) ve müşteri tarafı aynı kaydı görür.
/// Kurallar ve Türkçe mesajlar sunucuyla aynıdır (`FulfillmentService.DriverStartAsync` /
/// `DriverDeliverAsync`).
///
/// - GET driver/shipments?scope=active|today|upcoming|history&page&pageSize
/// - GET driver/shipments/{id}
/// - POST driver/shipments/{id}/start, POST driver/shipments/{id}/deliver
///
/// Dünyaya bir kez (sıfırlamada yeniden) iki örnek eklenir: şoförün itirazlı bir teslimatı ("Teslimatı
/// düzelt") ve bayi sahibine atanmış bir teslimat (kendisi teslim eden personel).
void registerDriverFakes(FakeServer server) {
  // `me/access.assignedOpenShipments` ilk girişte doğru olsun (bayi sahibine atanmış teslimat).
  server.world.addLazySeeder(_ensureSeed);
  server.get('driver/shipments', (req) {
    final p = _driver(req);
    final scope = (req.query('scope') ?? 'active').trim();
    final rows = _scoped(req.world, _own(req.world, p), scope);
    return req.paged([for (final s in rows) _row(req.world, s)]);
  });

  server.get('driver/shipments/{id:int}', (req) {
    final p = _driver(req);
    return _detail(req.world, _ownOne(req, p));
  });

  server.post('driver/shipments/{id:int}/start', (req) {
    final p = _driver(req);
    final s = _ownOne(req, p);
    final w = req.world;
    final status = s['status'] as int? ?? 0;
    if (status == 1) return _detail(w, s);
    if (status == 5) throw FakeResponse.business('Bu sevkiyat iptal edildi.');
    if (status != 0) {
      throw FakeResponse.business('Bu sevkiyat zaten teslim edildi.');
    }
    if (!_orderOpen(w, s)) throw FakeResponse.business(_closedOrder);
    final r = req.json;
    final position = _position(r);
    final now = DateTime.now().toUtc();
    final device = TrTime.parseUtc(r.strOrNull('deviceTime'));
    s['status'] = 1;
    s['dispatchedAt'] = FakeWorld.local(_plausible(device, null, now) ?? now);
    s['deviceDispatchedAtUtc'] = device?.toIso8601String();
    s['dispatchedByUserId'] = p.userId;
    s['dispatchLatitude'] = position?.$1;
    s['dispatchLongitude'] = position?.$2;
    s['dispatchAccuracyMeters'] = position?.$3;
    _notifyCustomers(
      w,
      s,
      eventCode: 'shipment.dispatched',
      title: 'Aracınız yola çıktı',
      body:
          '${s['orderNumber']} siparişinizin ${_liters(s['plannedLiters'])} teslimatı yolda.',
      route: '/orders/${s['orderId']}',
      entityType: 'Order',
      entityId: s['orderId'] as int?,
    );
    return _detail(w, s);
  });

  server.post('driver/shipments/{id:int}/deliver', (req) {
    final p = _driver(req);
    final s = _ownOne(req, p);
    final w = req.world;
    final r = req.json;

    final liters = r.decOrNull('deliveredLiters') ?? 0;
    if (liters <= 0) {
      throw FakeResponse.validation({
        'deliveredLiters': ['Teslim edilen litreyi girin.'],
      });
    }
    if (_round3(liters) != liters) {
      throw FakeResponse.business(
        'Teslim edilen litre en çok 3 ondalık olabilir.',
      );
    }
    final doc = r.str('deliveryDocumentNo').trim();
    if (doc.isEmpty) {
      throw FakeResponse.validation({
        'deliveryDocumentNo': ['İrsaliye numarasını girin.'],
      });
    }
    if (doc.length > 100) {
      throw FakeResponse.business(
        'İrsaliye numarası en çok 100 karakter olabilir.',
      );
    }
    final recipient = r.nonEmpty('recipientName');
    final note = r.nonEmpty('note');
    final photoIds = r.strings('photoIds').toSet().toList();
    if (photoIds.length > 20) {
      throw FakeResponse.business('En çok 20 teslim fotoğrafı gönderilebilir.');
    }
    final signatureId = r.nonEmpty('signatureId');
    final waiver = r.objOrNull('signatureWaiver');
    int? waiverReason;
    String? waiverNote;
    if (waiver != null) {
      if (signatureId != null) {
        throw FakeResponse.business(
          'İmza ve imza alınamama nedeni birlikte gönderilemez.',
        );
      }
      waiverReason = waiver.intOrNull('reason');
      if (waiverReason == null || waiverReason < 1 || waiverReason > 3) {
        throw FakeResponse.business('İmza alınamama nedenini seçin.');
      }
      waiverNote = waiver.nonEmpty('note');
      if (waiverReason == 3 && (waiverNote == null || waiverNote.length < 3)) {
        throw FakeResponse.business(
          '"Diğer" seçildiğinde imzanın neden alınamadığını kısaca yazın.',
        );
      }
    }
    final position = _position(r);

    final status = s['status'] as int? ?? 0;
    if (status == 2 || status == 3) {
      final same =
          (s['deliveredLiters'] as num?)?.toDouble() == liters &&
          _sameIgnoringCase(s['deliveryDocumentNo'] as String? ?? '', doc);
      if (same) return _detail(w, s);
      throw FakeResponse.conflict(
        'already_reported',
        'Bu teslimat farklı litre ya da irsaliye numarasıyla zaten bildirilmiş.',
      );
    }
    if (status == 0) {
      throw FakeResponse.business('Teslim bildirmek için önce yola çıkın.');
    }
    if (status == 5) throw FakeResponse.business('Bu sevkiyat iptal edildi.');
    if (!_orderOpen(w, s)) throw FakeResponse.business(_closedOrder);
    final planned = (s['plannedLiters'] as num?)?.toDouble() ?? 0;
    if (liters > planned) {
      throw FakeResponse.business(
        'Teslim edilen litre planlanan litreyi aşamaz.',
      );
    }

    final id = s['id'] as int;
    for (final pid in photoIds) {
      if (!_isEvidence(w, id, pid, AttachmentKind.deliveryPhoto)) {
        throw FakeResponse.business(
          'Teslim fotoğraflarından biri bu sevkiyata ait değil ya da silinmiş; fotoğrafı yeniden ekleyin.',
        );
      }
    }
    final hasSignature =
        signatureId != null &&
        _isEvidence(w, id, signatureId, AttachmentKind.deliverySignature);
    if (signatureId != null && !hasSignature) {
      throw FakeResponse.business(
        'İmza bu sevkiyata ait değil ya da silinmiş; imzayı yeniden alın.',
      );
    }
    final req0 = _requirements();
    final hasGps = position != null;
    if (waiverReason != null && (photoIds.isEmpty || !hasGps)) {
      throw FakeResponse.business(
        'İmza alınamadığında en az bir teslim fotoğrafı ve teslim konumu gerekir.',
      );
    }
    if (req0.photo && photoIds.isEmpty) {
      throw FakeResponse.business('En az bir teslim fotoğrafı ekleyin.');
    }
    if (req0.signature && !hasSignature && waiverReason == null) {
      throw FakeResponse.business(
        'Teslim alanın imzasını alın ya da imza alınamama nedenini seçin.',
      );
    }
    if (req0.gps && !hasGps) {
      throw FakeResponse.business(
        'Teslim konumu gerekli; konum iznini açıp tekrar deneyin.',
      );
    }

    final now = DateTime.now().toUtc();
    final device = TrTime.parseUtc(r.strOrNull('deviceTime'));
    final dispatched = TrTime.parseLocal(s['dispatchedAt'] as String?);
    final plausible = _plausible(device, dispatched, now);
    final waiverText = waiverReason == null
        ? null
        : _waiverText(waiverReason, waiverNote);
    s['status'] = 2;
    s['deliveredLiters'] = liters;
    s['deliveryDocumentNo'] = doc;
    s['recipientName'] = recipient;
    s['deliveryNote'] = waiverText == null
        ? note
        : '[İmza alınamadı: $waiverText] ${note ?? ''}'.trim();
    s['signatureWaiverLabel'] = waiverText;
    s['deliveredAt'] = FakeWorld.local(plausible ?? now);
    s['deviceDeliveredAtUtc'] = device?.toIso8601String();
    s['timeSource'] = plausible != null ? 'device' : 'server';
    s['deliveredLatitude'] = position?.$1;
    s['deliveredLongitude'] = position?.$2;
    s['deliveredAccuracyMeters'] = position?.$3;
    s['reportedByUserId'] = p.userId;
    s['reportedByName'] = p.displayName;
    _notifyCustomers(
      w,
      s,
      eventCode: 'shipment.reported',
      title: 'Teslimatı onaylayın',
      body:
          '${s['orderNumber']} için ${_liters(liters)} teslim edildi. Lütfen kontrol edip onaylayın.',
      route: '/shipments/$id',
      entityType: 'Shipment',
      entityId: id,
      severity: 2,
    );
    _notifyBayi(w, s, actor: p.userId);
    return _detail(w, s);
  });
}

const _closedOrder = 'Sipariş sevkiyat işlemine kapalı.';

// ------------------------------------------------------------------ Erişim

FakePersona _driver(FakeRequest req) {
  _ensureSeed(req.world);
  final p = req.requireUser();
  if (p.persona != Persona.bayi || !p.can(Pg.stationShipments)) {
    throw FakeResponse.forbidden(
      'Teslimatlarım yalnızca bayi personeline açıktır.',
    );
  }
  return p;
}

List<JsonMap> _own(FakeWorld w, FakePersona p) => [
  for (final s in w.shipments)
    if (s['driverUserId'] == p.userId && s['stationId'] == p.stationId) s,
];

JsonMap _ownOne(FakeRequest req, FakePersona p) {
  final id = req.intParam('id');
  for (final s in _own(req.world, p)) {
    if (s['id'] == id) return s;
  }
  throw FakeResponse.notFound('Sevkiyat bulunamadı.');
}

bool _orderOpen(FakeWorld w, JsonMap s) =>
    w.order(s['orderId'] as int?)?['status'] == OrderStatus.approved.code;

// ------------------------------------------------------------------ Kapsamlar

DateTime? _at(Object? v) => TrTime.parseLocal(v as String?);

List<JsonMap> _scoped(FakeWorld w, List<JsonMap> own, String scope) {
  final today = TrTime.todayStart();
  final tomorrow = today.add(const Duration(days: 1));
  final cutoff = today.subtract(const Duration(days: 30));
  bool inToday(JsonMap s) {
    final at = _at(s['scheduledAt']);
    return at != null && !at.isBefore(today) && at.isBefore(tomorrow);
  }

  int st(JsonMap s) => s['status'] as int? ?? 0;
  final filtered = own.where((s) {
    final status = st(s);
    switch (scope) {
      case 'today':
        return (inToday(s) && status != 5) || status == 1 || status == 4;
      case 'upcoming':
        final at = _at(s['scheduledAt']);
        return status == 0 && at != null && !at.isBefore(tomorrow);
      case 'history':
        final at = _at(s['deliveredAt']) ?? _at(s['scheduledAt']);
        return (status == 2 || status == 3 || status == 5) &&
            at != null &&
            !at.isBefore(cutoff);
      default:
        return status == 0 || status == 1 || status == 4;
    }
  }).toList();
  filtered.sort((a, b) {
    final da = st(a) == 4 ? 0 : 1;
    final db = st(b) == 4 ? 0 : 1;
    if (da != db) return da.compareTo(db);
    if (scope == 'history') {
      final ta = _at(a['deliveredAt']) ?? _at(a['scheduledAt']);
      final tb = _at(b['deliveredAt']) ?? _at(b['scheduledAt']);
      final c = (tb ?? DateTime(0)).compareTo(ta ?? DateTime(0));
      return c != 0 ? c : (b['id'] as int).compareTo(a['id'] as int);
    }
    final ia = st(a) == 1 ? 0 : 1;
    final ib = st(b) == 1 ? 0 : 1;
    if (ia != ib) return ia.compareTo(ib);
    final c = (_at(a['scheduledAt']) ?? DateTime(0)).compareTo(
      _at(b['scheduledAt']) ?? DateTime(0),
    );
    return c != 0 ? c : (a['id'] as int).compareTo(b['id'] as int);
  });
  return filtered;
}

// ------------------------------------------------------------------ Gövdeler

String? _iso(Object? local) {
  final at = _at(local);
  return at == null ? null : TrTime.isoOffset(at);
}

JsonMap _row(FakeWorld w, JsonMap s) {
  final dp = w.deliveryPoint(s['deliveryPointId'] as int?) ?? const {};
  final status = s['status'] as int? ?? 0;
  final id = s['id'] as int;
  return {
    'id': id,
    'code': s['code'] ?? 'SVK-${id.toString().padLeft(8, '0')}',
    'orderId': s['orderId'],
    'orderNumber': s['orderNumber'],
    'status': status,
    'statusLabel': ShipmentStatus.fromCode(status).label,
    'customerTitle': s['customerName'],
    'productName': s['productName'],
    'plannedLiters': s['plannedLiters'],
    'deliveredLiters': s['deliveredLiters'],
    'scheduledAt': _iso(s['scheduledAt']),
    'deliveryPointName': s['deliveryPointName'] ?? dp['name'],
    'city': dp['city'] ?? s['deliveryCity'],
    'district': dp['district'] ?? s['deliveryDistrict'],
    'hasCoordinates': dp['latitude'] != null && dp['longitude'] != null,
    'vehiclePlate': s['vehiclePlate'],
    'windowStart': dp['windowStart'],
    'windowEnd': dp['windowEnd'],
    'disputeNote': s['disputeNote'],
  };
}

JsonMap _detail(FakeWorld w, JsonMap s) {
  final dp = w.deliveryPoint(s['deliveryPointId'] as int?) ?? const {};
  final id = s['id'] as int;
  final status = s['status'] as int? ?? 0;
  final open = _orderOpen(w, s);
  final note = s['deliveryNote'] as String?;
  final waiver = s['signatureWaiverLabel'] as String?;
  return {
    ..._row(w, s),
    'address': s['deliveryAddress'] ?? dp['address'],
    'latitude': dp['latitude'],
    'longitude': dp['longitude'],
    'contactName': dp['contactName'],
    'contactPhone': dp['contactPhone'],
    'accessNotes': dp['accessNotes'],
    'tankCapacityLiters': dp['tankCapacityLiters'],
    'deliveryDocumentNo': s['deliveryDocumentNo'],
    'recipientName': s['recipientName'],
    'deliveryNote': _stripWaiver(note),
    'signatureWaiverLabel': waiver,
    'dispatchedAt': _iso(s['dispatchedAt']),
    'deliveredAt': _iso(s['deliveredAt']),
    'attachments': [
      for (final a in w.attachments)
        if (a['ownerType'] == AttachmentOwnerType.shipment.code &&
            a['ownerId'] == id &&
            a['isActive'] == true)
          a,
    ],
    'requirements': {
      'photo': _requirements().photo,
      'signature': _requirements().signature,
      'gps': _requirements().gps,
    },
    'actions': {
      'canStart': open && status == 0,
      'canDeliver': open && (status == 1 || status == 4),
    },
  };
}

({bool photo, bool signature, bool gps}) _requirements() {
  final f = JsonReader.of(fakeAppConfig()['features']);
  return (
    photo: f.boolean('deliveryPhotoRequired'),
    signature: f.boolean('deliverySignatureRequired'),
    gps: f.boolean('deliveryGpsRequired'),
  );
}

String? _stripWaiver(String? note) {
  if (note == null || !note.startsWith('[İmza alınamadı: ')) return note;
  final end = note.indexOf(']');
  if (end < 0) return note;
  final rest = note.substring(end + 1).trim();
  return rest.isEmpty ? null : rest;
}

String _waiverText(int reason, String? note) {
  final label = switch (reason) {
    1 => 'Alıcı yok / tanka teslim',
    2 => 'İmzadan imtina',
    _ => 'Diğer',
  };
  final clean = (note ?? '').replaceAll('[', '').replaceAll(']', '').trim();
  return clean.isEmpty ? label : '$label – $clean';
}

(double, double, double?)? _position(JsonReader r) {
  final lat = r.decOrNull('latitude');
  final lng = r.decOrNull('longitude');
  if ((lat == null) != (lng == null)) {
    throw FakeResponse.business(
      'Konum eksik: enlem ve boylam birlikte gönderilmelidir.',
    );
  }
  if (lat == null || lng == null) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    throw FakeResponse.business('Konum geçersiz.');
  }
  return (lat, lng, r.decOrNull('accuracyMeters'));
}

/// Cihaz saati [başlangıç − 5 dk, şimdi + 5 dk] aralığında ve en çok 72 saat eskiyse kullanılır.
DateTime? _plausible(DateTime? device, DateTime? notBefore, DateTime now) {
  if (device == null) return null;
  const tolerance = Duration(minutes: 5);
  if (device.isAfter(now.add(tolerance))) return null;
  if (device.isBefore(now.subtract(const Duration(hours: 72)))) return null;
  if (notBefore != null && device.isBefore(notBefore.subtract(tolerance))) {
    return null;
  }
  return device;
}

bool _isEvidence(
  FakeWorld w,
  int shipmentId,
  String publicId,
  AttachmentKind kind,
) {
  for (final a in w.attachments) {
    if (a['publicId'] == publicId) {
      return a['ownerType'] == AttachmentOwnerType.shipment.code &&
          a['ownerId'] == shipmentId &&
          a['kind'] == kind.code &&
          a['isActive'] == true;
    }
  }
  return false;
}

double _round3(double v) => double.parse(v.toStringAsFixed(3));

/// Büyük/küçük harf duyarsız eşitlik (irsaliye numaraları; sunucu OrdinalIgnoreCase).
bool _sameIgnoringCase(String a, String b) =>
    a.length == b.length &&
    RegExp('^${RegExp.escape(a)}\$', caseSensitive: false).hasMatch(b);

String _liters(Object? v) {
  final d = (v as num?)?.toDouble() ?? 0;
  final s = d == d.roundToDouble()
      ? d.round().toString()
      : d.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '');
  final parts = s.split('.');
  final b = StringBuffer();
  final digits = parts[0];
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write('.');
    b.write(digits[i]);
  }
  return '${b.toString()}${parts.length > 1 ? ',${parts[1]}' : ''} L';
}

// ------------------------------------------------------------------ Bildirimler

void _notifyCustomers(
  FakeWorld w,
  JsonMap s, {
  required String eventCode,
  required String title,
  required String body,
  required String route,
  String? entityType,
  int? entityId,
  int severity = 0,
}) {
  for (final p in fakePersonas) {
    if (p.persona != Persona.customer || p.customerId != s['customerId']) {
      continue;
    }
    if (!p.can(Pg.customerShipments) && !p.can(Pg.customerOrders)) continue;
    w.addNotification(
      userId: p.userId,
      category: 'shipments',
      eventCode: eventCode,
      title: title,
      body: body,
      severity: severity,
      route: route,
      entityType: entityType,
      entityId: entityId,
    );
  }
}

void _notifyBayi(FakeWorld w, JsonMap s, {required String actor}) {
  for (final p in fakePersonas) {
    if (p.persona != Persona.bayi || p.stationId != s['stationId']) continue;
    if (p.userId == actor || p.hasCap(Caps.shipmentOwnOnly)) continue;
    if (!p.can(Pg.stationShipments)) continue;
    w.addNotification(
      userId: p.userId,
      category: 'shipments',
      eventCode: 'shipment.reported',
      title: 'Teslimat bildirildi',
      body:
          '${s['orderNumber']} · ${s['customerName']} · müşteri onayı bekleniyor.',
      route: '/bayi/orders/${s['orderId']}',
      entityType: 'Order',
      entityId: s['orderId'] as int?,
    );
  }
}

// ------------------------------------------------------------------ Örnek kayıtlar

class _Seeded {
  const _Seeded();
}

void _ensureSeed(FakeWorld w) => w.bag<_Seeded>('driver.seed', () {
  _seed(w);
  return const _Seeded();
});

DateTime _wallAt(FakeWorld w, int dayOffset, int hour, [int minute = 0]) {
  final d = TrTime.wall(w.seededAt);
  return TrTime.fromWall(d.year, d.month, d.day + dayOffset, hour, minute);
}

void _seed(FakeWorld w) {
  final sofor = findFakePersona('sofor');
  // 1. Şoförün itirazlı teslimatı (dün; müşteri sayaç farkına itiraz etti).
  if (w.deliveryPoint(1005) != null && w.customer(104) != null) {
    final created = _wallAt(w, -3, 9);
    final oid = w.nextId('order');
    w.orders.add(
      w.newOrder(
        id: oid,
        customerId: 104,
        stationId: 1,
        deliveryPointId: 1005,
        productId: 1,
        liters: 6000,
        status: OrderStatus.approved.code,
        createdAt: created,
        expiresAt: created.add(const Duration(hours: 24)),
        requestedDeliveryDate: _wallAt(w, -1, 0),
        paymentMethodCode: 'ACIK_HESAP',
        paymentTermDays: 30,
        quotes: [
          w.newQuote(
            id: w.nextId('quote'),
            version: 1,
            unitPrice: 41.70,
            liters: 6000,
            deliveryDate: _wallAt(w, -1, 0),
            createdAt: created.add(const Duration(hours: 2)),
            selected: true,
          ),
        ],
      ),
    );
    final sid = w.nextId('shipment');
    w.shipments.add(
      w.newShipment(
        id: sid,
        orderId: oid,
        plannedLiters: 6000,
        status: ShipmentStatus.disputed.code,
        scheduledAt: _wallAt(w, -1, 11),
        dispatchedAt: _wallAt(w, -1, 11, 10),
        deliveredLiters: 5800,
        deliveredAt: _wallAt(w, -1, 12, 25),
        deliveryDocumentNo: 'IRS-779104',
        recipientName: 'Volkan Ateş',
        disputeNote:
            'Sayaç fişinde 5.650 L görünüyor; irsaliyedeki 5.800 L ile uyuşmuyor.',
      ),
    );
    fakeAttachment(
      w,
      ownerType: AttachmentOwnerType.shipment.code,
      ownerId: sid,
      kind: AttachmentKind.deliveryPhoto.code,
      fileName: 'teslimat-1.jpg',
      contentType: 'image/jpeg',
      bytes: _sampleJpeg(),
      uploadedBy: sofor,
    );
  }

  // 2. Bayi sahibine atanmış teslimat (kendisi teslim eden personel; yarın sabah).
  if (w.deliveryPoint(1003) != null && w.customer(102) != null) {
    final created = _wallAt(w, -1, 15);
    final oid = w.nextId('order');
    w.orders.add(
      w.newOrder(
        id: oid,
        customerId: 102,
        stationId: 1,
        deliveryPointId: 1003,
        productId: 1,
        liters: 5000,
        status: OrderStatus.approved.code,
        createdAt: created,
        expiresAt: created.add(const Duration(hours: 24)),
        requestedDeliveryDate: _wallAt(w, 1, 0),
        paymentMethodCode: 'HAVALE',
        quotes: [
          w.newQuote(
            id: w.nextId('quote'),
            version: 1,
            unitPrice: 41.85,
            liters: 5000,
            deliveryDate: _wallAt(w, 1, 0),
            createdAt: created.add(const Duration(hours: 1)),
            selected: true,
          ),
        ],
      ),
    );
    w.shipments.add(
      w.newShipment(
        id: w.nextId('shipment'),
        orderId: oid,
        plannedLiters: 5000,
        status: ShipmentStatus.planned.code,
        scheduledAt: _wallAt(w, 1, 8, 30),
        vehiclePlate: '41 DMR 104',
        driverName: 'Mehmet Demir',
        driverUserId: 'u-sahip',
      ),
    );
  }
}

/// Küçük bir örnek teslim fotoğrafı (yumuşak gri-mavi degrade).
Uint8List _sampleJpeg() {
  final image = img.Image(width: 48, height: 36);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, 120 + x, 140 + y, 170);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 70));
}
