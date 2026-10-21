import 'dart:convert';
import 'dart:typed_data';

import '../../../core/models/json.dart';
import '../../../core/network/fake/core_fakes.dart';
import '../../../core/network/fake/fake_personas.dart';
import '../../../core/network/fake/fake_world.dart';
import '../../../core/utils/tr_time.dart';

/// Bayi sahtelerinin torba anahtarları (ortak dünyada yalnızca `bayi.*` anahtarları kullanılır).
abstract final class BayiBags {
  static const seeded = 'bayi.seeded';
  static const settings = 'bayi.settings';
  static const timeline = 'bayi.timeline';
  static const notes = 'bayi.notes';
  static const limitRequests = 'bayi.limitRequests';
  static const staff = 'bayi.staff';
  static const appDrivers = 'bayi.appDrivers';
  static const deskConflicts = 'bayi.deskConflicts';
  static const deskErrors = 'bayi.deskErrors';
  static const passwordResets = 'bayi.passwordResets';
  static const reportedBy = 'bayi.reportedBy';
}

/// Sahte ek şoför ve personel (girişi olmayan hesaplar; plan / atama / Ekip ekranı için).
const fakeExtraStaff = <JsonMap>[
  {
    'userId': 'u-sofor2',
    'displayName': 'Mustafa Er',
    'email': 'mustafa.er@demo.akaryakitnet.local',
    'phoneNumber': '5320000212',
    'role': 'driver',
    'isActive': true,
    'lastLoginHoursAgo': null,
  },
  {
    'userId': 'u-sofor3',
    'displayName': 'Serdar Çınar',
    'email': 'serdar.cinar@demo.akaryakitnet.local',
    'phoneNumber': '5320000213',
    'role': 'driver',
    'isActive': true,
    'lastLoginHoursAgo': 3,
  },
  {
    'userId': 'u-eski',
    'displayName': 'Kerem Balcı',
    'email': 'kerem.balci@demo.akaryakitnet.local',
    'phoneNumber': '5320000214',
    'role': 'viewer',
    'isActive': false,
    'lastLoginHoursAgo': 960,
  },
];

/// Ek verileri bir kez tohumlar (dünya sıfırlanınca yeniden).
void ensureBayiSeed(FakeWorld w) {
  final flag = w.bag<List<bool>>(BayiBags.seeded, () => [false]);
  if (flag.first) return;
  flag[0] = true;
  _seedOrders(w);
  _seedNotes(w);
  _seedLimitRequests(w);
  _seedStaff(w);
  w.bag<Set<String>>(BayiBags.appDrivers, () => {'u-sofor', 'u-sofor3'});
}

DateTime _h(num hours) =>
    TrTime.now().add(Duration(minutes: (hours * 60).round()));

DateTime _todayAt(int hour, [int minute = 0, int dayOffset = 0]) {
  final w = TrTime.wall(TrTime.now());
  return TrTime.fromWall(w.year, w.month, w.day + dayOffset, hour, minute);
}

void _seedOrders(FakeWorld w) {
  int oid() => w.nextId('order', start: 12001);
  int qid() => w.nextId('quote', start: 30001);
  int sid() => w.nextId('shipment', start: 5001);

  JsonMap quote(
    double price,
    double liters,
    DateTime delivery,
    DateTime at, {
    bool selected = false,
    String? note,
  }) => w.newQuote(
    id: qid(),
    version: 1,
    unitPrice: price,
    liters: liters,
    deliveryDate: delivery,
    createdAt: at,
    selected: selected,
    revisionNote: note,
  );

  // Teklif bekleyenler (masa).
  w.orders.add(
    w.newOrder(
      id: oid(),
      customerId: 102,
      stationId: 1,
      deliveryPointId: 1003,
      productId: 1,
      liters: 18000,
      status: 1,
      createdAt: _h(-1),
      expiresAt: _h(23),
      requestedDeliveryDate: _h(48),
      paymentMethodCode: 'ACIK_HESAP',
      paymentTermDays: 30,
    ),
  );
  w.orders.add(
    w.newOrder(
      id: oid(),
      customerId: 101,
      stationId: 1,
      deliveryPointId: 1001,
      productId: 2,
      liters: 4000,
      status: 1,
      createdAt: _h(-0.3),
      expiresAt: _h(23.7),
      requestedDeliveryDate: _h(24),
      paymentMethodCode: 'KART',
      createdByUserId: 'u-talep',
    ),
  );
  final revId = oid();
  w.orders.add(
    w.newOrder(
      id: revId,
      customerId: 104,
      stationId: 1,
      deliveryPointId: 1005,
      productId: 1,
      liters: 12000,
      status: 5,
      createdAt: _h(-10),
      expiresAt: _h(6),
      requestedDeliveryDate: _h(24),
      quotes: [
        quote(
          41.95,
          12000,
          _h(24),
          _h(-8),
          note: 'Teslim 06:00 olabilir mi? 41,70 ₺/L olursa onaylıyoruz.',
        ),
      ],
    ),
  );

  // Planlanacaklar (pano).
  w.orders.add(
    w.newOrder(
      id: oid(),
      customerId: 103,
      stationId: 1,
      deliveryPointId: 1004,
      productId: 1,
      liters: 9000,
      status: 3,
      createdAt: _h(-30),
      expiresAt: _h(-6),
      requestedDeliveryDate: _todayAt(0),
      quotes: [quote(41.40, 9000, _todayAt(0), _h(-28), selected: true)],
    ),
  );
  final a2 = oid();
  w.orders.add(
    w.newOrder(
      id: a2,
      customerId: 104,
      stationId: 1,
      deliveryPointId: 1005,
      productId: 1,
      liters: 16000,
      status: 3,
      createdAt: _h(-28),
      expiresAt: _h(-4),
      requestedDeliveryDate: _todayAt(0, 0, 1),
      paymentMethodCode: 'DBS',
      paymentTermDays: 45,
      quotes: [quote(41.55, 16000, _todayAt(0, 0, 1), _h(-26), selected: true)],
    ),
  );
  w.orders.add(
    w.newOrder(
      id: oid(),
      customerId: 101,
      stationId: 1,
      deliveryPointId: 1002,
      productId: 2,
      liters: 5000,
      status: 3,
      createdAt: _h(-60),
      expiresAt: _h(-36),
      requestedDeliveryDate: _todayAt(0, 0, -1),
      quotes: [quote(44.10, 5000, _todayAt(0, 0, -1), _h(-58), selected: true)],
      createdByUserId: 'u-musteri',
    ),
  );
  final disputedOrder = oid();
  w.orders.add(
    w.newOrder(
      id: disputedOrder,
      customerId: 102,
      stationId: 1,
      deliveryPointId: 1003,
      productId: 1,
      liters: 7000,
      status: 3,
      createdAt: _h(-70),
      expiresAt: _h(-46),
      requestedDeliveryDate: _todayAt(0, 0, -2),
      paymentMethodCode: 'CEK',
      paymentTermDays: 60,
      financeStatus: 2,
      quotes: [quote(41.80, 7000, _todayAt(0, 0, -2), _h(-68), selected: true)],
    ),
  );
  final completed = oid();
  w.orders.add(
    w.newOrder(
      id: completed,
      customerId: 104,
      stationId: 1,
      deliveryPointId: 1005,
      productId: 1,
      liters: 6000,
      status: 7,
      createdAt: _h(-24 * 15),
      expiresAt: _h(-24 * 14),
      requestedDeliveryDate: _todayAt(0, 0, -14),
      paymentMethodCode: 'ACIK_HESAP',
      paymentTermDays: 7,
      quotes: [
        quote(
          41.20,
          6000,
          _todayAt(0, 0, -14),
          _h(-24 * 15 + 2),
          selected: true,
        ),
      ],
    ),
  );

  w.shipments.addAll([
    w.newShipment(
      id: sid(),
      orderId: a2,
      plannedLiters: 6000,
      status: 0,
      scheduledAt: _todayAt(10, 0, 1),
      vehiclePlate: '41 KRF 220',
      driverName: 'Mustafa Er',
      driverUserId: 'u-sofor2',
    ),
    w.newShipment(
      id: sid(),
      orderId: disputedOrder,
      plannedLiters: 7000,
      status: 4,
      scheduledAt: _todayAt(9, 0, -2),
      dispatchedAt: _todayAt(9, 20, -2),
      deliveredLiters: 6800,
      deliveredAt: _todayAt(11, 5, -2),
      vehiclePlate: '41 DMR 104',
      driverName: 'Serdar Çınar',
      driverUserId: 'u-sofor3',
      deliveryDocumentNo: 'IRS-779001',
      recipientName: 'Serkan Polat',
      disputeNote:
          'Sayaçta 6.650 L görünüyor; irsaliyedeki 6.800 L ile uyuşmuyor. Lütfen kontrol edin.',
    ),
    w.newShipment(
      id: sid(),
      orderId: completed,
      plannedLiters: 6000,
      status: 3,
      scheduledAt: _todayAt(8, 0, -14),
      dispatchedAt: _todayAt(8, 10, -14),
      deliveredLiters: 6000,
      deliveredAt: _todayAt(9, 40, -14),
      acceptedAt: _todayAt(10, 0, -14),
      vehiclePlate: '41 KRF 220',
      driverName: 'Mustafa Er',
      driverUserId: 'u-sofor2',
      deliveryDocumentNo: 'IRS-770551',
      recipientName: 'Volkan Ateş',
    ),
  ]);
  // Vadesi geçmiş tahsilat (tamamlanmış sipariş, açık hesap 7 gün).
  final c = w.order(completed);
  if (c != null) {
    c['paymentDueDate'] = FakeWorld.local(_todayAt(0, 0, -7));
    c['paymentStatus'] = 1;
  }

  // Kanıt ekleri: bildirilmiş teslimatın fotoğrafı ve imzası, itirazlı teslimatın itiraz fotoğrafı.
  final reported = w.shipments.where((s) => s['status'] == 2).firstOrNull;
  final sofor = findFakePersona('sofor');
  if (reported != null) {
    fakeAttachment(
      w,
      ownerType: 10,
      ownerId: reported['id'] as int,
      kind: 30,
      fileName: 'teslim-1.png',
      contentType: 'image/png',
      bytes: _photoPng,
      uploadedBy: sofor,
    );
    fakeAttachment(
      w,
      ownerType: 10,
      ownerId: reported['id'] as int,
      kind: 31,
      fileName: 'imza.png',
      contentType: 'image/png',
      bytes: _signaturePng,
      uploadedBy: sofor,
    );
  }
  final disputed = w.shipments.where((s) => s['status'] == 4).firstOrNull;
  if (disputed != null) {
    fakeAttachment(
      w,
      ownerType: 10,
      ownerId: disputed['id'] as int,
      kind: 30,
      fileName: 'teslim-sayac.png',
      contentType: 'image/png',
      bytes: _photoPng,
    );
    fakeAttachment(
      w,
      ownerType: 10,
      ownerId: disputed['id'] as int,
      kind: 32,
      fileName: 'itiraz-sayac.png',
      contentType: 'image/png',
      bytes: _photoPng,
    );
  }
}

void _seedNotes(FakeWorld w) {
  final notes = w.bag<Map<int, List<JsonMap>>>(BayiBags.notes, () => {});
  JsonMap n(int customerId, String body, String by, num hoursAgo) => {
    'id': w.nextId('bayi.note', start: 801),
    'stationId': 1,
    'customerId': customerId,
    'body': body,
    'createdAt': _h(-hoursAgo).toIso8601String(),
    'createdByUserId': 'u-$by',
    'createdByDisplay': findFakePersona(by)?.displayName ?? by,
    'canDelete': false,
  };
  notes[101] = [
    n(
      101,
      'Kasım için aylık 60.000 L motorin planladıklarını söylediler; fiyat teklifini erken bekliyorlar.',
      'mudur',
      20,
    ),
    n(
      101,
      'Tuzla şantiyesinde tank değişiyor; 15 Kasım sonrası kapasite 25.000 L olacak.',
      'satis',
      72,
    ),
  ];
  notes[102] = [
    n(
      102,
      'Çek vadeleri 60 günü geçmesin; finans müdürü onayladı.',
      'finans',
      48,
    ),
  ];
}

void _seedLimitRequests(FakeWorld w) {
  final list = w.bag<List<JsonMap>>(BayiBags.limitRequests, () => []);
  list.add({
    'id': w.nextId('bayi.limit', start: 701),
    'stationId': 1,
    'customerId': 102,
    'requestedLimitType': 'Tutar',
    'requestedLimitPeriod': 'Aylık',
    'requestedLimitAmount': 1500000.0,
    'reason': 'Kış sezonu şantiye tüketimi artıyor.',
    'status': 0,
    'createdAt': _h(-30).toIso8601String(),
  });
}

void _seedStaff(FakeWorld w) {
  w.bag<Map<String, bool>>(BayiBags.staff, () => {});
}

/// Bayinin (1) personeli: girişi olan bayi personaları + ek hesaplar; pasifleştirmeler torbada.
List<JsonMap> stationStaff(FakeWorld w, int stationId) {
  final overrides = w.bag<Map<String, bool>>(BayiBags.staff, () => {});
  final out = <JsonMap>[];
  for (final p in fakePersonas) {
    if (p.stationId != stationId) continue;
    out.add({
      'userId': p.userId,
      'displayName': p.displayName,
      'email': p.email,
      'phoneNumber': p.phone,
      'isActive': overrides[p.userId] ?? true,
      'isFieldSales': p.roles.contains('FieldSales'),
      'roleCodes': p.bayiRoleCodes,
      'lastLoginHoursAgo': (p.key.length * 5) % 30 + 1,
    });
  }
  if (stationId == 1) {
    for (final e in fakeExtraStaff) {
      out.add({
        ...e,
        'isActive': overrides[e['userId']] ?? e['isActive'],
        'isFieldSales': false,
        'roleCodes': [e['role']],
      });
    }
  }
  return out;
}

/// Kullanıcının görünen adı (persona ya da ek hesap).
String? staffName(String? userId) {
  if (userId == null) return null;
  final p = findFakePersona(userId);
  if (p != null) return p.displayName;
  for (final e in fakeExtraStaff) {
    if (e['userId'] == userId) return e['displayName'] as String;
  }
  return null;
}

/// Sahte sevkiyat fotoğrafı (32×24, sakin arduvaz).
final Uint8List _photoPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAIAAAAUMWhjAAAAgUlEQVR42t3NaQoBAQCA0e8AjuZ4kpKUpWmalGQZW2PsW5omRJLcxCm+P+r9f5xuXxX7/KNim71VrC4vFen5qSI5PlTMdncVk81VxWiVqxikmYpDsaD6gyCKDyrC4V5F0N+qaPXWKhrdpYp6Z6GiFiUqquFcRSWYqii3xypKzVj1A8uAOttzn+HOAAAAAElFTkSuQmCC',
);

/// Sahte imza (beyaz zemin, koyu çizgi).
final Uint8List _signaturePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAIAAAAUMWhjAAAAgUlEQVR42tWVyw3AIAxD2aDH7sD++9FKkUC0KeRjH4q4Pz1C7NLIp/wfcJz1vlwDYZAw44lIjGkGDBVlyFiG/ouAKqtvCmFs9iCvYlq0DMO6yWEVX1QEMO4s8jKCYWfHpNLUwsjG9VYF0wcLBqxwvlTAjfbG4CvzwWB1cscQS18AFw5FZE5KqIc9AAAAAElFTkSuQmCC',
);
