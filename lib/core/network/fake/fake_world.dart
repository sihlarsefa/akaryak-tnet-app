import 'dart:typed_data';

import '../../models/json.dart';
import '../../models/me_access.dart';
import '../../utils/format.dart';
import '../../utils/tr_time.dart';
import '../../utils/turkish_text.dart';
import 'fake_personas.dart';

/// Belge yüklendi dinleyicisi ([FakeWorld.addAttachmentListener]).
typedef FakeAttachmentListener =
    void Function(FakeWorld world, JsonMap attachment, FakePersona? uploadedBy);

/// Sahte kipin ortak, durumlu veri dünyası (spec D.4). Tüm özellik sahteleri aynı dünyayı okur ve
/// değiştirir; böylece uçtan uca akışlar çalışır: müşterinin verdiği sipariş teklif masasına düşer,
/// şoförün teslimatı müşterinin "Teslimatı onaylayın" kartına dönüşür.
///
/// Kayıtlar sunucu DTO alanlarıyla aynı camelCase anahtarlı `Map`'lerdir (tarihler sunucudaki gibi:
/// Türkiye yerel alanlar ofsetsiz, UTC alanlar `Z` ile). Özelliğe özgü ek durum için [bag] kullanılır
/// (`world.bag('field.forms', () => <JsonMap>[])`).
///
/// Sahibi M0a'dır; özellik ajanları kayıt ekleyebilir/güncelleyebilir, alanları yeniden adlandırmaz.
class FakeWorld {
  FakeWorld._();

  /// Tohumlanmış dünya. [now] verilirse tarihler ona göre üretilir (testler).
  factory FakeWorld.seeded({DateTime? now}) => FakeWorld._()..reset(now: now);

  /// Tohumlama anı (UTC).
  late DateTime seededAt;

  final List<JsonMap> stations = [];
  final List<JsonMap> customers = [];

  /// Bayi–cari bağlantıları (StationCustomer): limit, finans durumu, risk.
  final List<JsonMap> links = [];
  final List<JsonMap> products = [];
  final List<JsonMap> deliveryPoints = [];
  final List<JsonMap> orders = [];
  final List<JsonMap> shipments = [];
  final List<JsonMap> approvals = [];

  /// `UserNotificationDto` + `userId`.
  final List<JsonMap> notifications = [];

  /// `AttachmentDto` kayıtları; içerikler [attachmentBytes] içinde.
  final List<JsonMap> attachments = [];
  final Map<String, Uint8List> attachmentBytes = {};

  final Map<String, Object> _bags = {};
  final Map<String, int> _ids = {};

  /// Özelliğe özgü durum torbası (ilk erişimde [create] ile oluşur, [reset] ile silinir).
  T bag<T extends Object>(String key, T Function() create) =>
      _bags.putIfAbsent(key, create) as T;

  /// Tür başına artan kimlik.
  int nextId(String kind, {int start = 1}) {
    final n = (_ids[kind] ?? start - 1) + 1;
    _ids[kind] = n;
    return n;
  }

  // ------------------------------------------------------------------ Sorgular

  FakePersona? persona(String key) => findFakePersona(key);

  FakePersona? personaByUserId(String? userId) => findFakePersona(userId);

  static JsonMap? _byId(List<JsonMap> list, int? id) {
    if (id == null) return null;
    for (final e in list) {
      if (e['id'] == id) return e;
    }
    return null;
  }

  JsonMap? station(int? id) => _byId(stations, id);
  JsonMap? customer(int? id) => _byId(customers, id);
  JsonMap? product(int? id) => _byId(products, id);
  JsonMap? deliveryPoint(int? id) => _byId(deliveryPoints, id);
  JsonMap? order(int? id) => _byId(orders, id);
  JsonMap? shipment(int? id) => _byId(shipments, id);
  JsonMap? approval(int? id) => _byId(approvals, id);

  JsonMap? link(int stationId, int customerId) {
    for (final l in links) {
      if (l['stationId'] == stationId && l['customerId'] == customerId) {
        return l;
      }
    }
    return null;
  }

  String? stationTitle(int? id) => station(id)?['title'] as String?;
  String? customerTitle(int? id) => customer(id)?['title'] as String?;

  List<JsonMap> ordersOfCustomer(int customerId) =>
      orders.where((o) => o['customerId'] == customerId).toList();
  List<JsonMap> ordersOfStation(int stationId) =>
      orders.where((o) => o['stationId'] == stationId).toList();
  List<JsonMap> shipmentsOfOrder(int orderId) =>
      shipments.where((s) => s['orderId'] == orderId).toList();
  List<JsonMap> shipmentsOfDriver(String userId) =>
      shipments.where((s) => s['driverUserId'] == userId).toList();
  List<JsonMap> deliveryPointsOfCustomer(int customerId) =>
      deliveryPoints.where((d) => d['customerId'] == customerId).toList();

  /// Tembel tohumlar: özellik sahtelerinin dünyaya ilk istekte eklediği örnek kayıtlar (ör. şoför
  /// sahtesinin bayi sahibine atadığı teslimat). `me/access` bunları önce çalıştırır ki
  /// `assignedOpenShipments` ilk girişte doğru olsun. Kayıt [reset] ile silinmez (yapılandırmadır).
  final List<void Function(FakeWorld world)> _lazySeeders = [];

  void addLazySeeder(void Function(FakeWorld world) seeder) {
    if (!_lazySeeders.contains(seeder)) _lazySeeders.add(seeder);
  }

  /// Tembel tohumları çalıştırır (her tohum kendi torbasıyla bir kez çalışır).
  void ensureLazySeeds() {
    for (final s in List.of(_lazySeeders)) {
      s(this);
    }
  }

  /// Belge yükleme dinleyicileri (sunucunun `IAttachmentUploadListener` karşılığı; ör. tahsilat
  /// sahtesi bekleyen ödemeyi "Belge yüklendi" yapar). Kayıt [reset] ile silinmez (yapılandırmadır).
  final List<FakeAttachmentListener> _attachmentListeners = [];

  void addAttachmentListener(FakeAttachmentListener listener) {
    if (!_attachmentListeners.contains(listener)) {
      _attachmentListeners.add(listener);
    }
  }

  /// Yükleme kaydedildikten sonra (`POST attachments`) dinleyicilere haber verir.
  void notifyAttachmentUploaded(JsonMap attachment, FakePersona? uploadedBy) {
    for (final l in List.of(_attachmentListeners)) {
      l(this, attachment, uploadedBy);
    }
  }

  /// Personanın `me/access` gövdesi (spec B.3: `isFieldSales`, `isStationOwner`,
  /// `assignedOpenShipments` dahil).
  JsonMap meAccess(FakePersona p) {
    ensureLazySeeds();
    final assigned = shipments
        .where(
          (s) =>
              s['driverUserId'] == p.userId &&
              const {0, 1, 4}.contains(s['status']),
        )
        .length;
    return {
      ...p.meAccessJson(
        stationTitle: stationTitle(p.stationId),
        customerTitle: customerTitle(p.customerId),
      ),
      'isFieldSales': p.roles.contains('FieldSales'),
      'isStationOwner': p.persona == Persona.bayi && p.key == 'sahip',
      'assignedOpenShipments': p.persona == Persona.bayi ? assigned : 0,
      if (p.persona == Persona.customer)
        'customerUserRoleLabel': switch (p.customerUserRole) {
          1 => 'Talep eden',
          2 => 'Onaylayan',
          _ => 'Yönetici',
        },
    };
  }

  /// Kullanıcının okunmamış bildirim sayısı.
  int unreadNotifications(String userId) => notifications
      .where((n) => n['userId'] == userId && n['readAt'] == null)
      .length;

  /// Personanın kararını bekleyen onaylar (Onaylarım rozeti).
  int approvalsWaitingFor(FakePersona p) =>
      approvals.where((a) => canDecide(p, a)).length;

  /// Persona bu onay talebinde karar verebilir mi (açık + uygun onaycı).
  bool canDecide(FakePersona p, JsonMap a) {
    final open = a['status'] == 0;
    final eligible =
        (a['eligibleUserIds'] as List?)?.contains(p.userId) ?? false;
    return open &&
        (eligible || (p.persona == Persona.platform && a['escalated'] == true));
  }

  /// Bildirim ekler (sahte "push"). Rota uygulama derin bağlantısıdır (`/orders/12`).
  JsonMap addNotification({
    required String userId,
    required String category,
    required String eventCode,
    required String title,
    required String body,
    int severity = 0,
    String? route,
    String? entityType,
    int? entityId,
    DateTime? at,
    bool read = false,
  }) {
    final created = (at ?? DateTime.now()).toUtc();
    final n = <String, dynamic>{
      'id': nextId('notification', start: 50001),
      'userId': userId,
      'category': category,
      'eventCode': eventCode,
      'title': title,
      'body': body,
      'severity': severity,
      'route': route,
      'entityType': entityType,
      'entityId': entityId,
      'createdAt': created.toIso8601String(),
      'readAt': read ? created.toIso8601String() : null,
    };
    notifications.insert(0, n);
    return n;
  }

  // ------------------------------------------------------------------ Tohum

  /// Dünyayı baştan tohumlar.
  void reset({DateTime? now}) {
    seededAt = (now ?? DateTime.now()).toUtc();
    for (final l in [
      stations,
      customers,
      links,
      products,
      deliveryPoints,
      orders,
      shipments,
      approvals,
      notifications,
      attachments,
    ]) {
      l.clear();
    }
    attachmentBytes.clear();
    _bags.clear();
    _ids.clear();
    _seedMasterData();
    _seedOrders();
    _seedApprovals();
    _seedNotifications();
  }

  DateTime _h(num hours) =>
      seededAt.add(Duration(minutes: (hours * 60).round()));

  /// Performans senaryosu (spec D.7.8, `integration_test/perf_test.dart`): [stationId] bayisine
  /// [count] adet teklif bekleyen sipariş ekler; teklif masası ve sipariş listesi 100+ satırla kaydırılır.
  /// Normal tohumlamada çağrılmaz.
  void addBulkPendingOrders(int count, {int stationId = 1}) {
    final points = [
      for (final dp in deliveryPoints)
        if (links.any(
          (l) =>
              l['stationId'] == stationId &&
              l['customerId'] == dp['customerId'],
        ))
          dp,
    ];
    if (points.isEmpty || products.isEmpty) return;
    for (var i = 0; i < count; i++) {
      final dp = points[i % points.length];
      final product = products[i % products.length];
      orders.add(
        newOrder(
          id: nextId('order'),
          customerId: dp['customerId'] as int,
          stationId: stationId,
          deliveryPointId: dp['id'] as int,
          productId: product['id'] as int,
          liters: 5000.0 + (i % 12) * 1000,
          status: 1,
          createdAt: _h(-(i % 48) - 1),
          expiresAt: _h(2 + i % 40),
          requestedDeliveryDate: _h(24 + (i % 5) * 24),
          createdByUserId: 'u-musteri',
        ),
      );
    }
  }

  /// Türkiye yerel, ofsetsiz (eski DTO alanları).
  static String local(DateTime instant) => TrTime.isoLocal(instant);

  /// UTC (`Z`).
  static String utc(DateTime instant) => instant.toUtc().toIso8601String();

  /// Bugünün Türkiye saatiyle [hour]:[minute] anı (+[dayOffset] gün).
  DateTime _todayAt(int hour, [int minute = 0, int dayOffset = 0]) {
    final w = TrTime.wall(seededAt);
    return TrTime.fromWall(w.year, w.month, w.day + dayOffset, hour, minute);
  }

  /// Bugünün bir saati, gösterim anına göre (v4 tur 2): [ahead] sonrası çeyrek saate yuvarlanır,
  /// noktanın teslim aralığına ([open]–[close]) sıkıştırılır, ama hiçbir zaman [notBefore]'dan (ya da
  /// şimdiden 15 dk sonrasından) önce değil; gün değişmez (en geç 23:45). Sabit saat ("09:00") gün
  /// içi bir gösterimde geçmişte kalıyor, yoldaki araç "geç kalmış" görünüyordu.
  DateTime _slotToday(
    Duration ahead, {
    required int open,
    required int close,
    DateTime? notBefore,
  }) {
    DateTime quarter(DateTime t) {
      final w = TrTime.wall(t);
      var m = w.hour * 60 + w.minute + (w.second > 0 ? 1 : 0);
      m = ((m + 14) ~/ 15) * 15;
      return TrTime.fromWall(w.year, w.month, w.day, m ~/ 60, m % 60);
    }

    var at = quarter(seededAt.add(ahead));
    final from = _todayAt(open);
    final until = _todayAt(close);
    if (at.isBefore(from)) at = from;
    if (at.isAfter(until)) at = until;
    final soonest = quarter(
      notBefore ?? seededAt.add(const Duration(minutes: 15)),
    );
    if (at.isBefore(soonest)) at = soonest;
    final last = _todayAt(23, 45);
    if (at.isAfter(last)) at = last;
    return at;
  }

  void _seedMasterData() {
    stations.addAll([
      {
        'id': 1,
        'title': 'Demir Petrol Akaryakıt Ltd. Şti.',
        'code': 'DMR-01',
        'city': 'Kocaeli',
        'district': 'Gebze',
        'phone': '02620000001',
      },
      {
        'id': 2,
        'title': 'Kuzey Enerji A.Ş.',
        'code': 'KZY-01',
        'city': 'İstanbul',
        'district': 'Tuzla',
        'phone': '02160000002',
      },
    ]);
    customers.addAll([
      {
        'id': 101,
        'title': 'Anadolu Lojistik A.Ş.',
        'taxNumber': '1234567808',
        'city': 'İstanbul',
        'district': 'Pendik',
        'phone': '02160000101',
        'email': 'satinalma@anadolulojistik.example',
      },
      {
        'id': 102,
        'title': 'Marmara İnşaat Taahhüt Ltd. Şti.',
        'taxNumber': '2345678909',
        'city': 'Kocaeli',
        'district': 'İzmit',
        'phone': '02620000102',
      },
      {
        'id': 103,
        'title': 'Ege Tarım Kooperatifi',
        'taxNumber': '3456789014',
        'city': 'Bursa',
        'district': 'Nilüfer',
        'phone': '02240000103',
      },
      {
        'id': 104,
        'title': 'Körfez Nakliyat ve Ticaret',
        'taxNumber': '4567890128',
        'city': 'Kocaeli',
        'district': 'Körfez',
        'phone': '02620000104',
      },
    ]);
    links.addAll([
      {
        'id': 501,
        'stationId': 1,
        'customerId': 101,
        'limitAmount': 2500000.0,
        'limitType': 'Tutar',
        'limitPeriod': 'Aylık',
        'used': 1180000.0,
        'financeStatus': 1,
        'riskClass': 2,
        'salesRepUserId': null,
      },
      {
        'id': 502,
        'stationId': 1,
        'customerId': 102,
        'limitAmount': 1000000.0,
        'limitType': 'Tutar',
        'limitPeriod': 'Aylık',
        'used': 940000.0,
        'financeStatus': 2,
        'riskClass': 3,
        'salesRepUserId': null,
      },
      {
        'id': 503,
        'stationId': 1,
        'customerId': 103,
        'limitAmount': 300000.0,
        'limitType': 'Litre',
        'limitPeriod': 'Aylık',
        'used': 120000.0,
        'financeStatus': 1,
        'riskClass': 1,
        'salesRepUserId': 'u-saha',
      },
      {
        'id': 504,
        'stationId': 1,
        'customerId': 104,
        'limitAmount': 750000.0,
        'limitType': 'Tutar',
        'limitPeriod': 'Aylık',
        // Kullanılan = Finans kartının açık bakiyesi (vadesi geçen 247.200 ₺; v4 tur 2): ana sayfa,
        // Tahsilat ve Finans aynı tutarı söyler.
        'used': 247200.0,
        'financeStatus': 1,
        'riskClass': 2,
        'salesRepUserId': 'u-saha',
      },
      {
        'id': 505,
        'stationId': 2,
        'customerId': 101,
        'limitAmount': null,
        'limitType': null,
        'limitPeriod': 'Limitsiz',
        'used': 0.0,
        'financeStatus': 1,
        'riskClass': 2,
        'salesRepUserId': null,
      },
    ]);
    products.addAll([
      {'id': 1, 'name': 'Motorin', 'code': 'MOT', 'listPrice': 42.10},
      {
        'id': 2,
        'name': 'Kurşunsuz Benzin 95',
        'code': 'K95',
        'listPrice': 44.85,
      },
      {'id': 3, 'name': 'Kalorifer Yakıtı', 'code': 'KAL', 'listPrice': 38.40},
    ]);
    deliveryPoints.addAll([
      {
        'id': 1001,
        'customerId': 101,
        'name': 'Pendik Lojistik Merkezi',
        'address': 'Kurtköy Mah. Ankara Cad. No:12',
        'city': 'İstanbul',
        'district': 'Pendik',
        'latitude': 40.9119,
        'longitude': 29.3014,
        'contactName': 'Murat Kaya',
        'contactPhone': '5321112233',
        'windowStart': '08:00',
        'windowEnd': '18:00',
        'accessNotes': 'Ana kapıda güvenliğe plaka bildirin; tank arka avluda.',
        'tankCapacityLiters': 30000.0,
        'isDefault': true,
      },
      {
        'id': 1002,
        'customerId': 101,
        'name': 'Tuzla Şantiye',
        'address': 'Aydınlı Mah. Sanayi Cad. No:4',
        'city': 'İstanbul',
        'district': 'Tuzla',
        'latitude': 40.8355,
        'longitude': 29.3290,
        'contactName': 'Kemal Uçar',
        'contactPhone': '5332223344',
        'windowStart': '07:30',
        'windowEnd': '16:30',
        'accessNotes': 'Şantiye girişinde baret zorunlu.',
        'tankCapacityLiters': 15000.0,
        'isDefault': false,
      },
      {
        'id': 1003,
        'customerId': 102,
        'name': 'İzmit Şantiye',
        'address': 'Kozluk Mah. Şehit Cad. No:21',
        'city': 'Kocaeli',
        'district': 'İzmit',
        'latitude': 40.7654,
        'longitude': 29.9408,
        'contactName': 'Serkan Polat',
        'contactPhone': '5343334455',
        'windowStart': '08:00',
        'windowEnd': '17:00',
        'accessNotes': null,
        'tankCapacityLiters': 40000.0,
        'isDefault': true,
      },
      {
        'id': 1004,
        'customerId': 103,
        'name': 'Nilüfer Tesis',
        'address': 'Görükle Mah. Kooperatif Sk. No:3',
        'city': 'Bursa',
        'district': 'Nilüfer',
        'latitude': 40.2130,
        'longitude': 28.9790,
        'contactName': 'Hasan Er',
        'contactPhone': '5354445566',
        'windowStart': '09:00',
        'windowEnd': '17:00',
        'accessNotes': 'Hafta sonu teslimat yok.',
        'tankCapacityLiters': 10000.0,
        'isDefault': true,
      },
      {
        'id': 1005,
        'customerId': 104,
        'name': 'Körfez Garaj',
        'address': 'Hereke Mah. Liman Yolu No:8',
        'city': 'Kocaeli',
        'district': 'Körfez',
        'latitude': 40.7764,
        'longitude': 29.7369,
        'contactName': 'Volkan Ateş',
        'contactPhone': '5365556677',
        'windowStart': '06:00',
        'windowEnd': '22:00',
        'accessNotes': null,
        'tankCapacityLiters': 25000.0,
        'isDefault': true,
      },
    ]);
  }

  /// `SIP-yyyyMMdd-NNNNN` (sunucu demo biçimi).
  String orderNumber(int id, DateTime created) {
    final w = TrTime.wall(created);
    final d =
        '${w.year}${w.month.toString().padLeft(2, '0')}${w.day.toString().padLeft(2, '0')}';
    return 'SIP-$d-${id.toString().padLeft(5, '0')}';
  }

  /// Sipariş kaydı (OrderDetailDto alanları + bayi satırı alanları).
  JsonMap newOrder({
    required int id,
    required int customerId,
    required int stationId,
    required int deliveryPointId,
    required int productId,
    required double liters,
    required int status,
    required DateTime createdAt,
    required DateTime expiresAt,
    required DateTime requestedDeliveryDate,
    String paymentMethodCode = 'HAVALE',
    int? paymentTermDays,
    int paymentStatus = 1,
    int financeStatus = 0,
    String? financeReasons,
    List<JsonMap> quotes = const [],
    String? createdByUserId,
  }) {
    final dp = deliveryPoint(deliveryPointId)!;
    final product = this.product(productId)!;
    final unit = (product['listPrice'] as num).toDouble();
    return {
      'id': id,
      'orderNumber': orderNumber(id, createdAt),
      'status': status,
      'customerId': customerId,
      'customerTitle': customerTitle(customerId),
      'stationId': stationId,
      'stationTitle': stationTitle(stationId),
      'productId': productId,
      'productName': product['name'],
      'deliveryPointId': deliveryPointId,
      'deliveryPointName': dp['name'],
      'deliveryAddress': '${dp['address']}, ${dp['district']} / ${dp['city']}',
      'deliveryCity': dp['city'],
      'quantityLiters': liters,
      'requestedDeliveryDate': local(TrTime.startOfDay(requestedDeliveryDate)),
      'expiresAt': local(expiresAt),
      'createdAt': local(createdAt),
      'quotes': quotes,
      'paymentMethodCode': paymentMethodCode,
      'paymentMethodName':
          paymentMethodNames[paymentMethodCode] ?? paymentMethodCode,
      'paymentTermDays': paymentTermDays,
      'paymentDueDate': paymentTermDays == null
          ? null
          : local(
              TrTime.startOfDay(
                requestedDeliveryDate.add(Duration(days: paymentTermDays)),
              ),
            ),
      'paymentInstallments': null,
      'paymentStatus': paymentStatus,
      'paymentGroupKey': null,
      'estimatedAmount': double.parse((liters * unit).toStringAsFixed(2)),
      'financeStatus': financeStatus,
      'financeReasons': financeReasons,
      'financeApprovalRequestId': null,
      'createdByUserId': createdByUserId,
    };
  }

  /// Teklif kaydı (`QuoteDto`).
  JsonMap newQuote({
    required int id,
    required int version,
    required double unitPrice,
    required double liters,
    required DateTime deliveryDate,
    required DateTime createdAt,
    bool selected = false,
    String? revisionNote,
  }) => {
    'id': id,
    'version': version,
    'unitPriceTry': unitPrice,
    'totalAmountTry': double.parse((unitPrice * liters).toStringAsFixed(2)),
    'deliveryDate': local(TrTime.startOfDay(deliveryDate)),
    'revisionNote': revisionNote,
    'isSelected': selected,
    'createdAt': local(createdAt),
  };

  /// Sevkiyat kaydı (ShipmentListItemDto + şoför alanları).
  JsonMap newShipment({
    required int id,
    required int orderId,
    required double plannedLiters,
    required int status,
    required DateTime scheduledAt,
    String vehiclePlate = '41 DMR 101',
    String driverName = 'Ahmet Kurt',
    String? driverUserId = 'u-sofor',
    double? deliveredLiters,
    DateTime? dispatchedAt,
    DateTime? deliveredAt,
    DateTime? acceptedAt,
    String? deliveryDocumentNo,
    String? recipientName,
    String? disputeNote,
  }) {
    final o = order(orderId)!;
    final dp = deliveryPoint(o['deliveryPointId'] as int)!;
    return {
      'id': id,
      'code': 'SVK-${id.toString().padLeft(8, '0')}',
      'orderId': orderId,
      'orderNumber': o['orderNumber'],
      'stationId': o['stationId'],
      'stationName': o['stationTitle'],
      'customerId': o['customerId'],
      'customerName': o['customerTitle'],
      'customerCity': customer(o['customerId'] as int)?['city'],
      'productId': o['productId'],
      'productName': o['productName'],
      'plannedLiters': plannedLiters,
      'deliveredLiters': deliveredLiters,
      'vehiclePlate': vehiclePlate,
      'driverName': driverName,
      'driverUserId': driverUserId,
      'scheduledAt': local(scheduledAt),
      'dispatchedAt': dispatchedAt == null ? null : local(dispatchedAt),
      'deliveredAt': deliveredAt == null ? null : local(deliveredAt),
      'acceptedAt': acceptedAt == null ? null : local(acceptedAt),
      'createdAt': utc(scheduledAt.subtract(const Duration(hours: 20))),
      'deliveryDocumentNo': deliveryDocumentNo,
      'recipientName': recipientName,
      'status': status,
      'disputeNote': disputeNote,
      'orderStatus': o['status'],
      'deliveryPointId': dp['id'],
      'deliveryPointName': dp['name'],
      'deliveryAddress': dp['address'],
      'deliveryCity': dp['city'],
      'deliveryDistrict': dp['district'],
      'requestedDeliveryDate': o['requestedDeliveryDate'],
    };
  }

  static const paymentMethodNames = {
    'NAKIT': 'Nakit',
    'HAVALE': 'Havale / EFT',
    'KART': 'Kredi / banka kartı',
    'DBS': 'DBS',
    'CEK': 'Çek',
    'SENET': 'Senet',
    'ACIK_HESAP': 'Açık hesap',
    'TEMINAT': 'Teminat mektubu',
    'UTTS': 'Taşıt tanıma (UTTS)',
    'AVANS': 'Ön ödemeli bakiye',
  };

  void _seedOrders() {
    _ids['order'] = 12000;
    _ids['quote'] = 30000;
    _ids['shipment'] = 5000;
    int oid() => nextId('order');
    int qid() => nextId('quote');

    final o1 = oid();
    orders.add(
      newOrder(
        id: o1,
        customerId: 101,
        stationId: 1,
        deliveryPointId: 1001,
        productId: 1,
        liters: 15000,
        status: 1,
        createdAt: _h(-2),
        expiresAt: _h(22),
        requestedDeliveryDate: _h(24),
        createdByUserId: 'u-musteri',
      ),
    );

    final o2 = oid();
    orders.add(
      newOrder(
        id: o2,
        customerId: 101,
        stationId: 1,
        deliveryPointId: 1002,
        productId: 1,
        liters: 8000,
        status: 2,
        createdAt: _h(-5),
        expiresAt: _h(3),
        requestedDeliveryDate: _h(24),
        paymentMethodCode: 'CEK',
        paymentTermDays: 30,
        financeStatus: 2,
        createdByUserId: 'u-musteri',
        quotes: [
          newQuote(
            id: qid(),
            version: 1,
            unitPrice: 42.35,
            liters: 8000,
            deliveryDate: _h(24),
            createdAt: _h(-1),
          ),
        ],
      ),
    );

    final o3 = oid();
    orders.add(
      newOrder(
        id: o3,
        customerId: 101,
        stationId: 1,
        deliveryPointId: 1001,
        productId: 1,
        liters: 20000,
        status: 3,
        createdAt: _h(-26),
        expiresAt: _h(-2),
        requestedDeliveryDate: _h(0),
        paymentMethodCode: 'ACIK_HESAP',
        paymentTermDays: 30,
        createdByUserId: 'u-musteri',
        quotes: [
          newQuote(
            id: qid(),
            version: 1,
            unitPrice: 41.90,
            liters: 20000,
            deliveryDate: _h(0),
            createdAt: _h(-24),
            selected: true,
          ),
        ],
      ),
    );

    final o4 = oid();
    orders.add(
      newOrder(
        id: o4,
        customerId: 101,
        stationId: 1,
        deliveryPointId: 1001,
        productId: 2,
        liters: 5000,
        status: 7,
        createdAt: _h(-24 * 8),
        expiresAt: _h(-24 * 7),
        requestedDeliveryDate: _h(-24 * 7),
        paymentStatus: 3,
        createdByUserId: 'u-musteri',
        quotes: [
          newQuote(
            id: qid(),
            version: 1,
            unitPrice: 44.20,
            liters: 5000,
            deliveryDate: _h(-24 * 7),
            createdAt: _h(-24 * 8 + 2),
            selected: true,
          ),
        ],
      ),
    );

    final o5 = oid();
    orders.add(
      newOrder(
        id: o5,
        customerId: 102,
        stationId: 1,
        deliveryPointId: 1003,
        productId: 1,
        liters: 25000,
        status: 1,
        createdAt: _h(-3),
        expiresAt: _h(45),
        requestedDeliveryDate: _h(48),
        paymentMethodCode: 'CEK',
        paymentTermDays: 60,
        financeStatus: 1,
        financeReasons: 'Vadeli yöntem (60 gün); limit aşımı 120.000 TL',
        createdByUserId: null,
      ),
    );

    final o6 = oid();
    orders.add(
      newOrder(
        id: o6,
        customerId: 103,
        stationId: 1,
        deliveryPointId: 1004,
        productId: 3,
        liters: 6000,
        status: 5,
        createdAt: _h(-20),
        expiresAt: _h(4),
        requestedDeliveryDate: _h(48),
        quotes: [
          newQuote(
            id: qid(),
            version: 1,
            unitPrice: 39.80,
            liters: 6000,
            deliveryDate: _h(48),
            createdAt: _h(-18),
            revisionNote: 'Fiyat 39,50 ₺/L olursa onaylıyoruz.',
          ),
        ],
      ),
    );

    final o7 = oid();
    orders.add(
      newOrder(
        id: o7,
        customerId: 102,
        stationId: 1,
        deliveryPointId: 1003,
        productId: 1,
        liters: 8000,
        status: 3,
        createdAt: _h(-30),
        expiresAt: _h(-6),
        requestedDeliveryDate: _h(0),
        paymentMethodCode: 'DBS',
        paymentTermDays: 45,
        quotes: [
          newQuote(
            id: qid(),
            version: 1,
            unitPrice: 41.75,
            liters: 8000,
            deliveryDate: _h(0),
            createdAt: _h(-28),
            selected: true,
          ),
        ],
      ),
    );

    final o8 = oid();
    orders.add(
      newOrder(
        id: o8,
        customerId: 101,
        stationId: 1,
        deliveryPointId: 1002,
        productId: 1,
        liters: 12000,
        status: 3,
        createdAt: _h(-50),
        expiresAt: _h(-30),
        requestedDeliveryDate: _h(-20),
        paymentMethodCode: 'HAVALE',
        paymentStatus: 2,
        createdByUserId: 'u-musteri',
        quotes: [
          newQuote(
            id: qid(),
            version: 1,
            unitPrice: 41.60,
            liters: 12000,
            deliveryDate: _h(-20),
            createdAt: _h(-48),
            selected: true,
          ),
        ],
      ),
    );

    final o9 = oid();
    orders.add(
      newOrder(
        id: o9,
        customerId: 104,
        stationId: 1,
        deliveryPointId: 1005,
        productId: 1,
        liters: 10000,
        status: 1,
        createdAt: _h(-23.3),
        expiresAt: _h(0.7),
        requestedDeliveryDate: _h(24),
      ),
    );

    // Panel eşitliği (şirket içi onay eşiği teklif onayında): Anadolu Lojistik'in eşiği 20.000 L /
    // 750.000 ₺ (`A2Fake.companyApproval`); bu teklif ikisini de aşar (24.000 L · 1.006.800 ₺). Yönetici
    // ve onaylayan onaylar; talep eden (Burak Yılmaz) yalnızca revize ister ya da reddeder, sırası
    // değildir ("Onaylayanın kararı bekleniyor"). Talep edenin eşik altı teklifi 12002 (8.000 L).
    final o10 = oid();
    orders.add(
      newOrder(
        id: o10,
        customerId: 101,
        stationId: 1,
        deliveryPointId: 1001,
        productId: 1,
        liters: 24000,
        status: 2,
        createdAt: _h(-7),
        expiresAt: _h(20),
        requestedDeliveryDate: _h(48),
        paymentMethodCode: 'ACIK_HESAP',
        paymentTermDays: 30,
        createdByUserId: 'u-musteri',
        quotes: [
          newQuote(
            id: qid(),
            version: 1,
            unitPrice: 41.95,
            liters: 24000,
            deliveryDate: _h(48),
            createdAt: _h(-2),
          ),
        ],
      ),
    );

    int sid() => nextId('shipment');
    // Yoldaki araç 40 dk önce çıktı, ~70 dk sonra Pendik'te (08:00–18:00); planlı sevkiyat ~4 saat
    // sonra İzmit'te (08:00–17:00), yoldakinden en az 45 dk sonra. Saatler gösterim anına göredir:
    // ana sayfa, bildirim ve şoför ekranı aynı, geçmişte kalmamış saati söyler (v4 tur 2).
    final arrival = _slotToday(const Duration(minutes: 70), open: 8, close: 18);
    var left = seededAt.subtract(const Duration(minutes: 40));
    final latestStart = arrival.subtract(const Duration(minutes: 30));
    if (left.isAfter(latestStart)) left = latestStart;
    final planned = _slotToday(
      const Duration(hours: 4),
      open: 8,
      close: 17,
      notBefore: arrival.add(const Duration(minutes: 45)),
    );
    shipments.addAll([
      newShipment(
        id: sid(),
        orderId: o3,
        plannedLiters: 10000,
        status: 1,
        scheduledAt: arrival,
        // Varıştan önce yola çıktı: bildirim "Varış …" der, saati çelişmez.
        dispatchedAt: left,
      ),
      newShipment(
        id: sid(),
        orderId: o7,
        plannedLiters: 8000,
        status: 0,
        scheduledAt: planned,
        vehiclePlate: '41 DMR 102',
      ),
      newShipment(
        id: sid(),
        orderId: o8,
        plannedLiters: 12000,
        status: 2,
        scheduledAt: _todayAt(14, 0, -1),
        dispatchedAt: _todayAt(14, 10, -1),
        deliveredLiters: 11950,
        deliveredAt: _todayAt(15, 40, -1),
        deliveryDocumentNo: 'IRS-778812',
        recipientName: 'Kemal Uçar',
      ),
      newShipment(
        id: sid(),
        orderId: o4,
        plannedLiters: 5000,
        status: 3,
        scheduledAt: _todayAt(10, 0, -7),
        dispatchedAt: _todayAt(10, 15, -7),
        deliveredLiters: 5000,
        deliveredAt: _todayAt(11, 30, -7),
        acceptedAt: _todayAt(12, 5, -7),
        deliveryDocumentNo: 'IRS-771020',
        recipientName: 'Murat Kaya',
      ),
      newShipment(
        id: sid(),
        orderId: o3,
        plannedLiters: 10000,
        status: 0,
        scheduledAt: _todayAt(10, 0, 1),
        vehiclePlate: '41 DMR 103',
      ),
    ]);
  }

  void _seedApprovals() {
    _ids['approval'] = 9000;
    JsonMap a({
      required int type,
      required int status,
      required String subjectType,
      required int subjectId,
      String? subjectNumber,
      required String title,
      String? summary,
      double? amount,
      double? liters,
      int? customerId,
      required String requestedByUserId,
      required String requestedByName,
      required DateTime createdAt,
      DateTime? dueAt,
      int slaState = 1,
      required List<String> eligible,
    }) => {
      'id': nextId('approval'),
      'type': type,
      'status': status,
      'isMirror': type <= 3,
      'stationId': 1,
      'stationTitle': stationTitle(1),
      'customerId': customerId,
      'customerTitle': customerTitle(customerId),
      'subjectType': subjectType,
      'subjectId': subjectId,
      'subjectNumber': subjectNumber,
      'title': title,
      'summary': summary,
      'amount': amount,
      'liters': liters,
      'requestedByUserId': requestedByUserId,
      'requestedByName': requestedByName,
      'createdAt': utc(createdAt),
      'dueAt': dueAt == null ? null : utc(dueAt),
      'slaState': slaState,
      'currentLevelNo': 1,
      'levelCount': 1,
      'eligibleUserIds': [for (final k in eligible) 'u-$k'],
    };

    final financeOrder = orders.firstWhere((o) => o['financeStatus'] == 1);
    final fa = a(
      type: 4,
      status: 0,
      subjectType: 'Order',
      subjectId: financeOrder['id'] as int,
      subjectNumber: financeOrder['orderNumber'] as String,
      title: 'Sipariş finans onayı',
      summary: 'Çek · 60 gün vade · limit aşımı 120.000 ₺',
      amount: financeOrder['estimatedAmount'] as double,
      liters: 25000,
      customerId: 102,
      requestedByUserId: 'u-system',
      requestedByName: 'Marmara İnşaat (müşteri siparişi)',
      createdAt: _h(-3),
      dueAt: _h(5),
      slaState: 2,
      // finansuzman: 1.000.000 ₺ sınırı bu tutarın altında → karar düğmesi yok, "Tutar onay sınırınızı
      // aşıyor" (A-INT persona).
      eligible: ['finans', 'mudur', 'sahip', 'finansuzman'],
    );
    financeOrder['financeApprovalRequestId'] = fa['id'];
    approvals.addAll([
      fa,
      a(
        type: 1,
        status: 0,
        subjectType: 'FieldOrderForm',
        subjectId: 7001,
        subjectNumber: 'SF-2026-00007',
        title: 'Saha formu kârlılık onayı',
        summary: 'Ege Tarım Kooperatifi · 18.000 L · Bayi yöneticisi onayı',
        amount: 702000,
        liters: 18000,
        customerId: 103,
        requestedByUserId: 'u-saha',
        requestedByName: 'Deniz Koç',
        createdAt: _h(-1.5),
        dueAt: _h(22.5),
        eligible: ['satis', 'mudur', 'sahip'],
      ),
      a(
        type: 3,
        status: 0,
        subjectType: 'CustomerOrderRequest',
        subjectId: 3001,
        subjectNumber: 'TLP-00031',
        title: 'Şirket içi sipariş talebi',
        // Sunucunun biçimi (CompanyOrderRequestApprovalSource.OpenCommand): ürünler · toplam litre ·
        // tahmini tutar · not. Talep iki ürün (20.000 L motorin + 10.000 L kalorifer yakıtı) ve iki
        // noktadır (A5 deposu, 3001); satır tek ürün ve tek nokta söylemez (v4 B11).
        summary:
            'Motorin, Kalorifer Yakıtı · 30.000 L · tahmini 1.263.000,00 ₺ · '
            'Not: Ay sonu stok için; iki noktaya ayrı teslim.',
        amount: 1263000,
        liters: 30000,
        customerId: 101,
        requestedByUserId: 'u-talep',
        requestedByName: 'Burak Yılmaz',
        createdAt: _h(-0.5),
        eligible: ['onay', 'musteri'],
      ),
      a(
        type: 7,
        status: 4,
        subjectType: 'CustomerLead',
        subjectId: 8001,
        subjectNumber: 'ONK-00008',
        title: 'Ön kayıt finans onayı',
        summary: 'Başkent Yapı Market · vergi levhası bekleniyor',
        customerId: null,
        requestedByUserId: 'u-saha',
        requestedByName: 'Deniz Koç',
        createdAt: _h(-28),
        dueAt: _h(20),
        slaState: 1,
        eligible: ['finans', 'sahip'],
      ),
    ]);
  }

  void _seedNotifications() {
    final o2 = orders.firstWhere((o) => o['status'] == 2);
    final o3 = orders.firstWhere((o) => o['status'] == 3);
    final moving = shipments.firstWhere((s) => s['status'] == 1);
    final reported = shipments.firstWhere((s) => s['status'] == 2);
    final planned = shipments.firstWhere((s) => s['status'] == 0);
    final newest = orders.lastWhere((o) => o['status'] == 1);
    final finance = approvals.firstWhere((a) => a['type'] == 4);
    final field = approvals.firstWhere((a) => a['type'] == 1);
    final company = approvals.firstWhere((a) => a['type'] == 3);

    // v4 (§4): bildirim metinlerinde kod (SIP-, SVK-) ve tutar (₺) yok; kim, ne, nerede ve ne
    // zamana kadar — doğal cümleyle. Bayi kısa adıyla ("Demir Petrol"), uygulamanın her yerindeki
    // gibi; sayılar ve saatler ana sayfa, sipariş ve şoför ekranlarıyla aynıdır (A9, B11): yoldaki
    // litre sevkiyatın planlanan litresi, teslim bildiriminin saati teslim saati. Karar isteyen
    // bildirimde son saat önce gelir: satır iki satırda kesilse de görünür (B17).
    String litres(Object? v) => Fmt.liters((v as num?) ?? 0);
    String product(Object? v) => TurkishText.lower('${v ?? 'yakıt'}');
    String short(Object? v) => TurkishText.shortCompany(v as String?);
    DateTime? localAt(Object? v) => TrTime.parseLocal(v as String?);
    // Sipariş alanları (`expiresAt`, `createdAt`) ofsetsiz Türkiye saatidir.
    // Bildirim dünden kalmışsa bugünkü son saat "bugün" der ("Dün 12:15 · 12:15'e kadar" hangi gün
    // olduğunu söylemiyordu; v4 tur 2).
    String until(Object? v, {Object? stamped}) {
      final at = localAt(v);
      if (at == null) return 'Süresi dolmadan';
      final from = localAt(stamped);
      final prefix = TrTime.dayDiff(seededAt, at) > 0
          ? 'yarın '
          : from != null && TrTime.dayDiff(from, at) != 0
          ? 'bugün '
          : '';
      return '$prefix${TurkishText.timeDative(Fmt.time(at))} kadar';
    }

    void n(
      List<String> keys,
      String category,
      String code,
      String title,
      String body,
      String route, {
      int severity = 0,
      String? entityType,
      int? entityId,
      num hoursAgo = 1,
      DateTime? at,
      bool read = false,
    }) {
      // Olayın kendi anı geçmişteyse o (teslim, yola çıkış); değilse "şimdi − hoursAgo".
      final when = at != null && at.isBefore(seededAt) ? at : _h(-hoursAgo);
      for (final k in keys) {
        addNotification(
          userId: 'u-$k',
          category: category,
          eventCode: code,
          title: title,
          body: body,
          severity: severity,
          route: route,
          entityType: entityType,
          entityId: entityId,
          at: when,
          read: read,
        );
      }
    }

    final arrival = localAt(moving['scheduledAt']);
    n(
      ['musteri', 'talep', 'onay'],
      'shipments',
      'shipment.dispatched',
      'Aracınız yola çıktı',
      '${litres(moving['plannedLiters'])} ${product(moving['productName'])}, '
          '${moving['deliveryPointName']} için yolda.'
          '${arrival == null ? '' : ' Varış ${Fmt.time(arrival)}.'}',
      '/orders/${o3['id']}',
      entityType: 'Order',
      entityId: o3['id'] as int,
      hoursAgo: 3,
      at: localAt(moving['dispatchedAt']),
      read: true,
    );
    n(
      ['musteri', 'onay'],
      'shipments',
      'shipment.reported',
      'Teslimatı onaylayın',
      '${short(reported['stationName'])} '
          '${litres(reported['deliveredLiters'] ?? reported['plannedLiters'])} '
          '${product(reported['productName'])} teslim etti. Kontrol edip onaylayın.',
      '/shipments/${reported['id']}',
      severity: 2,
      entityType: 'Shipment',
      entityId: reported['id'] as int,
      hoursAgo: 18,
      at: localAt(reported['deliveredAt']),
    );
    n(
      ['musteri', 'onay'],
      'quotes',
      'order.quote_ready',
      'Teklif hazır',
      // Bildirim metninde tutar yok (spec A.5: kilit ekranında görünür).
      '${until(o2['expiresAt'])} karar verin: ${short(o2['stationTitle'])}, '
          '${o2['deliveryPointName']} için ${litres(o2['quantityLiters'])} '
          '${product(o2['productName'])} teklifi.',
      '/orders/${o2['id']}',
      severity: 1,
      entityType: 'Order',
      entityId: o2['id'] as int,
      hoursAgo: 1,
    );
    n(
      ['onay', 'musteri'],
      'approvals',
      // Sunucu şirket içi talep için ayrı olay göndermez; onaylayanlara approval.pending gider (spec A.5).
      // Talep iki noktaya iki ürün (20.000 L motorin + 10.000 L kalorifer yakıtı; A5 deposu 3001).
      'approval.pending',
      'Onayınızı bekleyen talep',
      'Burak Yılmaz 2 noktaya 30.000 L yakıt talep etti.',
      '/approvals/${company['id']}',
      entityType: 'ApprovalRequest',
      entityId: company['id'] as int,
      hoursAgo: 0.5,
    );
    n(
      ['sahip', 'mudur', 'siparis', 'izleyici'],
      'orders',
      'order.created',
      'Yeni sipariş',
      '${until(newest['expiresAt'], stamped: newest['createdAt'])} teklif verin: '
          '${short(newest['customerTitle'])} '
          '${litres(newest['quantityLiters'])} ${product(newest['productName'])} istiyor.',
      '/bayi/orders/${newest['id']}',
      entityType: 'Order',
      entityId: newest['id'] as int,
      hoursAgo: 0.4,
      // Sipariş geldiği an (sipariş listesindeki saatle aynı).
      at: localAt(newest['createdAt']),
    );
    n(
      ['finans', 'mudur', 'sahip'],
      'approvals',
      'approval.pending',
      'Finans onayı bekliyor',
      'Marmara İnşaat çekle, 60 gün vadeli ödemek istiyor.',
      '/approvals/${finance['id']}',
      severity: 2,
      entityType: 'ApprovalRequest',
      entityId: finance['id'] as int,
      hoursAgo: 3,
    );
    n(
      ['satis'],
      'approvals',
      'approval.pending',
      'Saha formu onayı bekliyor',
      'Deniz Koç, Ege Tarım Kooperatifi için 18.000 L form gönderdi.',
      '/approvals/${field['id']}',
      entityType: 'ApprovalRequest',
      entityId: field['id'] as int,
      hoursAgo: 1.5,
    );
    n(
      ['sofor'],
      'shipments',
      'shipment.assigned',
      'Yeni teslimat atandı',
      'Bugün ${Fmt.time(TrTime.parseLocal(planned['scheduledAt'] as String?))}, '
          '${planned['deliveryPointName']}: ${litres(planned['plannedLiters'])}.',
      '/driver/shipments/${planned['id']}',
      entityType: 'Shipment',
      entityId: planned['id'] as int,
      hoursAgo: 2,
    );
    n(
      ['sevkiyat', 'depo'],
      'orders',
      'order.approved',
      'Sipariş onaylandı',
      '${o3['customerTitle']} siparişi onaylandı; '
          '${litres(o3['quantityLiters'])} planlanmayı bekliyor.',
      '/dispatch',
      severity: 1,
      entityType: 'Order',
      entityId: o3['id'] as int,
      hoursAgo: 5,
    );
    n(
      ['muhasebe'],
      'payments',
      'payment.bounced',
      'Ödeme durumu güncellendi',
      'Körfez Nakliyat\'ın çeki karşılıksız çıktı. Tahsilat\'ta inceleyin.',
      '/payments',
      severity: 3,
      hoursAgo: 6,
    );
    // Sunucunun sözü ve rotası (NotificationTemplates `lead.updated`, temsilciye: ön kaydın kendisi):
    // demo, gerçek uygulamanın açtığı sayfayı açar (v4 tur 2).
    n(
      ['saha'],
      'field',
      'lead.updated',
      'Ön kayıt ek bilgi istendi',
      'Başkent Yapı Market ön kaydı için finans ek bilgi istedi. '
          'Düzenleyip yeniden gönderin.',
      '/field/leads/8001',
      severity: 2,
      entityType: 'CustomerLead',
      entityId: 8001,
      hoursAgo: 4,
    );
    n(
      ['merkez'],
      'system',
      'system.test',
      'Hoş geldiniz',
      'AkaryakıtNet mobil uygulaması hazır.',
      '/notifications',
      hoursAgo: 24,
      read: true,
    );
  }
}
