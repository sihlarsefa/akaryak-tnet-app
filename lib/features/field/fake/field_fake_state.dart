import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../../core/auth/permissions.dart';
import '../../../core/models/json.dart';
import '../../../core/models/me_access.dart';
import '../../../core/network/fake/core_fakes.dart';
import '../../../core/network/fake/fake_personas.dart';
import '../../../core/network/fake/fake_server.dart';
import '../../../core/network/fake/fake_world.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';

/// Saha sahte verisinin durumu (ortak dünyanın `field.state` torbasında). Formlar `field.forms`
/// torbasındaki listede `FieldOrderFormDto` anahtarlarıyla tutulur (başka özellik sahteleri okuyabilir);
/// iç alanlar `_` ile başlar (`_createdBy`, `_repId`, `_approvalId`, `_financeApprovalId`).
class FieldFakeState {
  FieldFakeState._(this.world, this.forms, this.leads);

  final FakeWorld world;
  final List<JsonMap> forms;
  final List<JsonMap> leads;

  /// Bayi 1'in satış temsilcileri (`field-orders/reps`).
  final List<JsonMap> reps = [
    {'id': 31, 'name': 'Deniz Koç', 'extra': null, '_userId': 'u-saha'},
    {'id': 32, 'name': 'Murat Şen', 'extra': null, '_userId': null},
    {'id': 33, 'name': 'Selda Ak', 'extra': 'pasif', '_userId': null},
  ];

  static FieldFakeState of(FakeWorld world) =>
      world.bag<FieldFakeState>('field.state', () => _create(world));

  static FieldFakeState _create(FakeWorld world) {
    final forms = world.bag<List<JsonMap>>('field.forms', () => <JsonMap>[]);
    final leads = world.bag<List<JsonMap>>('field.leads', () => <JsonMap>[]);
    final s = FieldFakeState._(world, forms, leads);
    if (forms.isEmpty) s._seedForms();
    if (leads.isEmpty) s._seedLeads();
    return s;
  }

  // ─────────────────────────────────────────────────────────── Referans veriler

  static const stationId = 1;
  static const locations = ['İZMİT', 'ALİAĞA', 'KIRIKKALE', 'BATMAN'];
  static const locationLabels = {
    'İZMİT': 'İzmit',
    'ALİAĞA': 'Aliağa (İzmir)',
    'KIRIKKALE': 'Kırıkkale',
    'BATMAN': 'Batman',
  };

  /// Ürün → İzmit Tüpraş ₺/m³ (KDV dahil). Diğer lokasyonlar +150 ₺/m³ adımlarla.
  static const tuprasIzmit = {1: 38400.0, 2: 40900.0, 3: 35300.0};

  /// Ürün → pompa ₺/L (KDV dahil).
  static const pump = {1: 43.90, 2: 46.75, 3: 40.10};

  /// Ürün → varsayılan bindirim ₺/m³ (KDV hariç).
  static const bindirim = {1: 1000.0, 2: 1100.0, 3: 900.0};

  static double? tupras(int productId, String location) {
    final base = tuprasIzmit[productId];
    if (base == null) return null;
    final i = locations.indexOf(location);
    return base + (i < 0 ? 0 : i * 150);
  }

  /// Referans fiyatın günü: İzmit ve Aliağa bugün, diğerleri dün (bayat referans uyarısı).
  static DateTime tuprasDay(String location) {
    final today = TrTime.todayStart();
    return location == 'İZMİT' || location == 'ALİAĞA'
        ? today
        : TrTime.addDays(today, -1);
  }

  /// Ödeme yöntemleri (`PaymentMethodOptionDto`).
  static List<JsonMap> paymentMethods() => [
    _method('HAVALE', 'Havale / EFT', min: 0, max: 0, kind: 3),
    _method('NAKIT', 'Nakit', min: 0, max: 0),
    _method(
      'CEK',
      'Çek',
      deferred: true,
      finance: true,
      min: 30,
      max: 90,
      def: 30,
      kind: 1,
      required: true,
      fields: [
        {'key': 'bank', 'label': 'Banka', 'type': 'text', 'maxLength': 60},
        {'key': 'serialNo', 'label': 'Çek no', 'type': 'text', 'maxLength': 30},
        {'key': 'dueDate', 'label': 'Çek vadesi', 'type': 'date'},
      ],
    ),
    _method(
      'SENET',
      'Senet',
      deferred: true,
      finance: true,
      min: 30,
      max: 60,
      def: 30,
      kind: 2,
      required: true,
    ),
    _method(
      'ACIK_HESAP',
      'Açık hesap',
      deferred: true,
      min: 15,
      max: 60,
      def: 30,
    ),
    _method('DBS', 'DBS', deferred: true, min: 30, max: 90, def: 45),
    _method('KART', 'Kredi / banka kartı', min: 0, max: 0),
  ];

  static JsonMap _method(
    String code,
    String name, {
    bool deferred = false,
    bool finance = false,
    int min = 0,
    int max = 0,
    int? def,
    int? kind,
    bool required = false,
    List<JsonMap> fields = const [],
  }) => {
    'code': code,
    'name': name,
    'shortName': name,
    'isDeferred': deferred,
    'requiresFinance': finance,
    'documentKind': kind,
    'documentRequired': required,
    'allowsInstallments': false,
    'installmentOptions': const <int>[],
    'minTermDays': min,
    'maxTermDays': max,
    'defaultTermDays': def,
    'fields': fields,
    'hint': deferred ? 'Vade boyunca finans takibinde' : null,
  };

  static String methodName(String? code) {
    if (code == null) return 'Belirtilmemiş';
    for (final m in paymentMethods()) {
      if (m['code'] == code) return m['name'] as String;
    }
    return code;
  }

  static JsonMap? method(String? code) {
    for (final m in paymentMethods()) {
      if (m['code'] == code) return m;
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────── Kişi kuralları

  /// Saha satış temsilcisi kaydı (kullanıcıya bağlı).
  JsonMap? repOf(FakePersona p) {
    for (final r in reps) {
      if (r['_userId'] == p.userId) return r;
    }
    return null;
  }

  static bool isFieldSales(FakePersona p) => p.roles.contains(Roles.fieldSales);

  /// Maliyet görünürlüğü (web `FieldOrderCostAccess`): platform; temsilcide kapalı (ShowProfitToReps);
  /// diğerlerinde FieldApprovals Düzenler, FieldOrders İnceler ya da `costs.view`.
  static bool showCosts(FakePersona p) {
    if (p.persona == Persona.platform) return true;
    if (isFieldSales(p)) return false;
    return p.can(Pg.stationFieldApprovals, Perm.edit) ||
        p.can(Pg.stationFieldOrders, Perm.inspect) ||
        p.hasCap(Caps.costsView);
  }

  /// Formu görebilir mi (temsilci yalnızca kendi formlarını).
  bool canSeeForm(FakePersona p, JsonMap f) {
    if (p.persona == Persona.platform) return true;
    if (p.stationId != f['stationId']) return false;
    if (isFieldSales(p)) {
      return f['_createdBy'] == p.userId || f['_repId'] == repOf(p)?['id'];
    }
    return true;
  }

  /// Portföy (temsilcinin carileri).
  List<int> portfolioOf(FakePersona p) => [
    for (final l in world.links)
      if (l['stationId'] == stationId && l['salesRepUserId'] == p.userId)
        l['customerId'] as int,
  ];

  /// Cari bu kullanıcıya açık mı (temsilci: portföy; diğerleri: bayinin aktif bağlantısı).
  void ensureCustomer(FakePersona p, int customerId) {
    if (customerId <= 0) throw FakeResponse.business('Cari seçin.');
    if (world.link(stationId, customerId) == null) {
      throw FakeResponse.business('Cari bu bayiye aktif olarak bağlı değil.');
    }
    if (isFieldSales(p) && !portfolioOf(p).contains(customerId)) {
      throw FakeResponse.business('Bu cari portföyünüzde değil.');
    }
  }

  // ─────────────────────────────────────────────────────────── Numaralar

  // Tohum numaralarıyla çakışmasın diye 10'dan başlar.
  int _formSeq = 10;
  int _leadSeq = 10;

  int nextFormId() => world.nextId('field.form', start: 7101);

  /// Saha onay talepleri kendi aralığından numaralanır (çekirdek 9001–9004, onaylar sahtesi 9005–9013
  /// kimliklerini doğrudan verir; çakışmasın).
  int nextApprovalId() => world.nextId('field.approval', start: 9601);
  int nextLeadId() => world.nextId('field.lead', start: 8101);
  int nextLineId() => world.nextId('field.line', start: 71001);

  String nextFormNumber() {
    final w = TrTime.wall(TrTime.now());
    final day =
        '${w.year}${w.month.toString().padLeft(2, '0')}${w.day.toString().padLeft(2, '0')}';
    return 'SSF-$day-${(++_formSeq).toString().padLeft(6, '0')}';
  }

  String nextLeadNumber() {
    final w = TrTime.wall(TrTime.now());
    final day =
        '${w.year}${w.month.toString().padLeft(2, '0')}${w.day.toString().padLeft(2, '0')}';
    return 'ONK-$day-${(++_leadSeq).toString().padLeft(6, '0')}';
  }

  static final _rng = Random();

  static String newToken() {
    String h(int n) =>
        List.generate(n, (_) => _rng.nextInt(16).toRadixString(16)).join();
    return '${h(8)}-${h(4)}-4${h(3)}-a${h(3)}-${h(12)}';
  }

  /// 9 hanelik önekten geçerli VKN (GİB algoritması; sahte veride kullanılır).
  static String vkn(String nine) {
    var sum = 0;
    for (var i = 0; i < 9; i++) {
      final tmp = (int.parse(nine[i]) + 9 - i) % 10;
      var v = tmp * (1 << (9 - i)) % 9;
      if (tmp != 0 && v == 0) v = 9;
      sum += v;
    }
    return '$nine${(10 - sum % 10) % 10}';
  }

  /// Başka bayide kayıtlı (sahte) VKN'ler: "Merkeze ilet" akışı için.
  static final elsewhereVkns = {vkn('765432109'), vkn('112233445')};

  // ─────────────────────────────────────────────────────────── Form kaydı

  DateTime _h(num hours) =>
      world.seededAt.add(Duration(minutes: (hours * 60).round()));

  /// Yeni form kaydı (sunucu `FieldOrderFormDto` anahtarları).
  JsonMap newForm({
    required int id,
    required String number,
    required int customerId,
    required List<JsonMap> lines,
    required String createdBy,
    required int? repId,
    int status = 0,
    int paymentTermDays = 0,
    String? paymentMethodCode,
    DateTime? createdAt,
    DateTime? submittedAt,
    DateTime? decidedAt,
    String? decidedByName,
    String? decisionNote,
    int? requiredLevel,
    int financeStatus = 0,
    String? financeReasons,
    DateTime? shipDate,
    String? note,
  }) {
    final creator = world.personaByUserId(createdBy);
    final rep = repId == null
        ? null
        : reps.where((r) => r['id'] == repId).firstOrNull;
    final ship = shipDate ?? TrTime.addDays(TrTime.todayStart(), 1);
    return {
      'id': id,
      'concurrencyToken': newToken(),
      'formNumber': number,
      'stationId': stationId,
      'stationTitle': world.stationTitle(stationId),
      'customerId': customerId,
      'customerTitle': world.customerTitle(customerId),
      'salesRepresentativeId': repId,
      'salesRepresentativeName': rep?['name'],
      'createdByName': creator?.displayName ?? rep?['name'],
      'status': status,
      'paymentTermDays': paymentTermDays,
      'note': note,
      'createdAt': FakeWorld.utc(createdAt ?? _h(-1)),
      'submittedAt': submittedAt == null ? null : FakeWorld.utc(submittedAt),
      'decidedAt': decidedAt == null ? null : FakeWorld.utc(decidedAt),
      'decidedByName': decidedByName,
      'decisionNote': decisionNote,
      'convertedOrderIds': <int>[],
      'requiredApprovalLevel': requiredLevel,
      'pricingModel': 1,
      'shipDate': FakeWorld.local(ship),
      'paymentMethodCode': paymentMethodCode,
      'paymentMethodName': methodName(paymentMethodCode),
      'paymentDetails': <String, String>{},
      'paymentDueDate': FakeWorld.local(TrTime.addDays(ship, paymentTermDays)),
      'distributorName': 'Petrol Ofisi',
      'terminalName': 'İzmit Körfez Terminali',
      'refineryLocation': 'İZMİT',
      'transportKm': null,
      'transportTotal': null,
      'isCombinedShipment': false,
      'combinedTruckLiters': null,
      'combinedTruckCost': null,
      'collateralRatioPercent': 0,
      'strategicExceptionRequested': false,
      'exceptionJustification': null,
      'financeStatus': financeStatus,
      'financeReasons': financeReasons,
      'financeApprovalRequestId': null,
      'lines': lines,
      'approvals': <JsonMap>[],
      '_createdBy': createdBy,
      '_repId': repId,
      '_approvalId': null,
      '_financeApprovalId': null,
      // Gönderim anındaki maliyet anlık görüntüsü (yalnızca maliyet görebilene açılır).
      '_minProfitPercent': null,
    }..addAll(totals(lines));
  }

  /// Satır kaydı (`FieldOrderLineDto`).
  JsonMap newLine({
    required int productId,
    required int deliveryPointId,
    required double liters,
    required double price,
    DateTime? date,
    double? tuprasM3,
    double? pumpPrice,
    double? bindirimM3,
    int? orderId,
    String location = 'İZMİT',
  }) {
    final product = world.product(productId);
    final dp = world.deliveryPoint(deliveryPointId);
    final reference = tupras(productId, location);
    final t = tuprasM3 ?? reference;
    final invoiceM3 = price * 1000;
    final order = world.order(orderId);
    return {
      'id': nextLineId(),
      'productId': productId,
      'productName': product?['name'] ?? 'Ürün',
      'deliveryPointId': deliveryPointId,
      'deliveryPointName': dp?['name'] ?? 'Teslimat noktası',
      'quantityLiters': liters,
      'requestedDeliveryDate': FakeWorld.local(
        date ?? TrTime.addDays(TrTime.todayStart(), 1),
      ),
      'proposedUnitPrice': price,
      'referenceUnitPrice': (product?['listPrice'] as num?)?.toDouble(),
      'orderId': orderId,
      'orderNumber': order?['orderNumber'],
      'tuprasPriceM3': t,
      'tuprasOverridden':
          tuprasM3 != null && (tuprasM3 - (reference ?? 0)).abs() >= 0.01,
      'pumpPricePerLiter': pumpPrice ?? pump[productId],
      'bindirimM3': bindirimM3,
      'priceEntryMode': 0,
      'profitPercent': null,
      'invoicePriceM3': round(invoiceM3, 2),
      'tuprasDiffPercent': t == null
          ? null
          : round((invoiceM3 - t) / t * 100, 2),
      'pumpDiscountPercent': pump[productId] == null
          ? null
          : round(
              ((pumpPrice ?? pump[productId]!) * 1000 - invoiceM3) /
                  ((pumpPrice ?? pump[productId]!) * 1000) *
                  100,
              2,
            ),
    };
  }

  static JsonMap totals(List<JsonMap> lines) {
    var liters = 0.0;
    var amount = 0.0;
    for (final l in lines) {
      final q = (l['quantityLiters'] as num).toDouble();
      liters += q;
      amount += q * (l['proposedUnitPrice'] as num).toDouble();
    }
    return {'totalLiters': liters, 'totalAmount': round(amount, 2)};
  }

  static double round(num v, int digits) {
    final f = pow(10, digits).toDouble();
    return (v * f).roundToDouble() / f;
  }

  // ─────────────────────────────────────────────────────────── Tohum

  void _seedForms() {
    final today = TrTime.todayStart();
    final tomorrow = TrTime.addDays(today, 1);
    final ordersOf103 = world.orders
        .where((o) => o['customerId'] == 103)
        .toList();
    final orderFor7003 = ordersOf103.isEmpty
        ? null
        : ordersOf103.last['id'] as int;

    // Onaylarım'daki 9002 (kârlılık, yönetici bandı) bu formu gösterir.
    final f1 = newForm(
      id: 7001,
      number: 'SF-2026-00007',
      customerId: 103,
      createdBy: 'u-saha',
      repId: 31,
      status: 1,
      requiredLevel: 1,
      paymentMethodCode: 'ACIK_HESAP',
      paymentTermDays: 30,
      createdAt: _h(-1.6),
      submittedAt: _h(-1.5),
      shipDate: tomorrow,
      lines: [
        newLine(
          productId: 3,
          deliveryPointId: 1004,
          liters: 10000,
          price: 38.90,
          date: tomorrow,
        ),
        newLine(
          productId: 1,
          deliveryPointId: 1004,
          liters: 8000,
          price: 39.125,
          date: tomorrow,
        ),
      ],
    );
    f1['_approvalId'] = _approvalIdFor('FieldOrderForm', 7001, type: 1);
    f1['_minProfitPercent'] = 5.42;

    // Onaylarım'daki 9006 (saha formu finans onayı; onaylar sahtesi tohumlar).
    final f2 = newForm(
      id: 7002,
      number: 'SF-2026-00011',
      customerId: 104,
      createdBy: 'u-saha',
      repId: 31,
      status: 2,
      requiredLevel: 0,
      paymentMethodCode: 'ACIK_HESAP',
      paymentTermDays: 30,
      createdAt: _h(-9.5),
      submittedAt: _h(-9),
      financeStatus: 1,
      financeReasons: 'Vadeli yöntem (Açık hesap) · Limit kullanımı %86',
      shipDate: tomorrow,
      lines: [
        newLine(
          productId: 1,
          deliveryPointId: 1005,
          liters: 20000,
          price: 42.00,
          date: tomorrow,
        ),
      ],
    );
    f2['_financeApprovalId'] = 9006;
    f2['financeApprovalRequestId'] = 9006;
    f2['_minProfitPercent'] = 6.35;
    f2['approvals'] = [
      _trailEntry(0, 'Otomatik', 0, 'Otomatik onay', null, null, _h(-9)),
    ];

    final f3 = newForm(
      id: 7003,
      number: 'SSF-${_day(_h(-48))}-000001',
      customerId: 103,
      createdBy: 'u-saha',
      repId: 31,
      status: 4,
      requiredLevel: 0,
      paymentMethodCode: 'HAVALE',
      createdAt: _h(-49),
      submittedAt: _h(-48.5),
      decidedAt: _h(-48.5),
      decidedByName: 'Otomatik onay',
      lines: [
        newLine(
          productId: 3,
          deliveryPointId: 1004,
          liters: 6000,
          price: 39.80,
          orderId: orderFor7003,
        ),
      ],
    );
    f3['convertedOrderIds'] = [?orderFor7003];
    f3['_minProfitPercent'] = 6.8;
    f3['approvals'] = [
      _trailEntry(0, 'Otomatik', 0, 'Otomatik onay', null, null, _h(-48.5)),
    ];

    // Onaylarım'daki 9012 (satış müdürü reddetti).
    final f4 = newForm(
      id: 6998,
      number: 'SF-2026-00004',
      customerId: 104,
      createdBy: 'u-saha',
      repId: 31,
      status: 3,
      requiredLevel: 1,
      paymentMethodCode: 'ACIK_HESAP',
      paymentTermDays: 45,
      createdAt: _h(-81),
      submittedAt: _h(-80),
      decidedAt: _h(-76),
      decidedByName: 'Emre Çelik',
      decisionNote: 'Fiyat barem alt sınırının altında; yeniden fiyatlayın.',
      lines: [
        newLine(
          productId: 1,
          deliveryPointId: 1005,
          liters: 9000,
          price: 40.2222,
        ),
      ],
    );
    f4['_approvalId'] = 9012;
    f4['_minProfitPercent'] = 4.6;
    f4['approvals'] = [
      _trailEntry(
        1,
        'Bayi yöneticisi',
        2,
        'Reddedildi',
        'Emre Çelik',
        'Fiyat barem alt sınırının altında; yeniden fiyatlayın.',
        _h(-76),
      ),
    ];

    // Finans ek bilgi istedi ("Yanıtla").
    final f5 = newForm(
      id: 7005,
      number: 'SSF-${_day(_h(-26))}-000002',
      customerId: 104,
      createdBy: 'u-saha',
      repId: 31,
      status: 2,
      requiredLevel: 0,
      paymentMethodCode: 'CEK',
      paymentTermDays: 45,
      createdAt: _h(-27),
      submittedAt: _h(-26),
      financeStatus: 4,
      financeReasons: 'Vadeli yöntem (Çek) · Vade 45 gün',
      shipDate: TrTime.addDays(today, 2),
      lines: [
        newLine(
          productId: 1,
          deliveryPointId: 1005,
          liters: 15000,
          price: 42.40,
        ),
      ],
    );
    f5['_minProfitPercent'] = 6.1;
    f5['approvals'] = [
      _trailEntry(0, 'Otomatik', 0, 'Otomatik onay', null, null, _h(-26)),
    ];
    f5['_financeApprovalId'] = _ensureFinanceApproval(f5);
    f5['financeApprovalRequestId'] = f5['_financeApprovalId'];

    final f6 = newForm(
      id: 7006,
      number: 'SSF-${_day(_h(-5))}-000004',
      customerId: 102,
      createdBy: 'u-mudur',
      repId: 32,
      status: 1,
      requiredLevel: 2,
      paymentMethodCode: 'DBS',
      paymentTermDays: 60,
      createdAt: _h(-5.5),
      submittedAt: _h(-5),
      lines: [
        newLine(
          productId: 1,
          deliveryPointId: 1003,
          liters: 20000,
          price: 41.30,
        ),
      ],
    );
    f6['_minProfitPercent'] = 4.4;

    final f7 = newForm(
      id: 7007,
      number: 'SSF-${_day(_h(-2))}-000005',
      customerId: 101,
      createdBy: 'u-mudur',
      repId: 32,
      paymentMethodCode: 'HAVALE',
      createdAt: _h(-2),
      lines: [
        newLine(
          productId: 2,
          deliveryPointId: 1001,
          liters: 5000,
          price: 44.70,
        ),
      ],
    );

    // Onaylı ama dönüşümü yarıda kalmış form ("Dönüşümü yeniden dene").
    final f8 = newForm(
      id: 7008,
      number: 'SSF-${_day(_h(-9))}-000006',
      customerId: 103,
      createdBy: 'u-saha',
      repId: 31,
      status: 2,
      requiredLevel: 1,
      paymentMethodCode: 'HAVALE',
      createdAt: _h(-9.5),
      submittedAt: _h(-9),
      decidedAt: _h(-8),
      decidedByName: 'Emre Çelik',
      decisionNote:
          'Fiyat uygun. Dönüşüm hatası: Teslimat noktası için uygun sevkiyat '
          'penceresi bulunamadı; sipariş açılamadı.',
      lines: [
        newLine(
          productId: 1,
          deliveryPointId: 1004,
          liters: 7000,
          price: 41.60,
          date: tomorrow,
        ),
      ],
    );
    f8['_noAutoConvert'] = true;
    f8['_minProfitPercent'] = 5.6;
    f8['approvals'] = [
      _trailEntry(
        1,
        'Bayi yöneticisi',
        1,
        'Onaylandı',
        'Emre Çelik',
        'Fiyat uygun.',
        _h(-8),
      ),
    ];

    // Temsilcinin taslağı.
    final f9 = newForm(
      id: 7009,
      number: 'SSF-${_day(_h(-3))}-000003',
      customerId: 104,
      createdBy: 'u-saha',
      repId: 31,
      paymentMethodCode: 'HAVALE',
      createdAt: _h(-3),
      shipDate: tomorrow,
      note: 'Müşteri haftaya ikinci teslimat için teklif bekliyor.',
      lines: [
        newLine(
          productId: 1,
          deliveryPointId: 1005,
          liters: 12000,
          price: 41.95,
          date: tomorrow,
        ),
      ],
    );
    forms.addAll([f1, f2, f3, f4, f5, f6, f7, f8, f9]);
  }

  static JsonMap _trailEntry(
    int level,
    String levelLabel,
    int decision,
    String decisionLabel,
    String? approver,
    String? note,
    DateTime at,
  ) => {
    'level': level,
    'levelLabel': levelLabel,
    'decision': decision,
    'decisionLabel': decisionLabel,
    'approverName': approver,
    'note': note,
    'marginPercent': null,
    'decidedAt': FakeWorld.utc(at),
  };

  static String _day(DateTime instant) {
    final w = TrTime.wall(instant);
    return '${w.year}${w.month.toString().padLeft(2, '0')}${w.day.toString().padLeft(2, '0')}';
  }

  int? _approvalIdFor(String subjectType, int subjectId, {required int type}) {
    for (final a in world.approvals) {
      if (a['subjectType'] == subjectType &&
          a['subjectId'] == subjectId &&
          a['type'] == type) {
        return a['id'] as int;
      }
    }
    return null;
  }

  /// 7005'in "ek bilgi istendi" finans talebi (Onaylarım'da "Yanıtla").
  int _ensureFinanceApproval(JsonMap form) {
    final existing = _approvalIdFor(
      'FieldOrderForm',
      form['id'] as int,
      type: 5,
    );
    if (existing != null) return existing;
    final a = addApproval(
      type: 5,
      status: 4,
      form: form,
      title: 'Saha formu finans onayı',
      summary: '${form['customerTitle']} · çek, 45 gün vade',
      eligible: const ['finans', 'sahip'],
      createdAt: _h(-26),
    );
    a['infoRequest'] = {
      'note': 'Çekin ön yüz fotoğrafını ve son 3 aylık cari ekstresini iletin.',
      'requiredAttachmentKind': 1,
      'requiredKindLabel': 'Çek görseli',
      'requestedAt': FakeWorld.utc(_h(-20)),
    };
    return a['id'] as int;
  }

  /// Ortak dünyaya saha onay talebi ekler (Onaylarım'da görünür).
  JsonMap addApproval({
    required int type,
    required int status,
    required JsonMap form,
    required String title,
    required String summary,
    required List<String> eligible,
    DateTime? createdAt,
  }) {
    final created = createdAt ?? DateTime.now().toUtc();
    final a = <String, dynamic>{
      'id': nextApprovalId(),
      'type': type,
      'status': status,
      'isMirror': type <= 3,
      'stationId': stationId,
      'stationTitle': world.stationTitle(stationId),
      'customerId': form['customerId'],
      'customerTitle': form['customerTitle'],
      'subjectType': 'FieldOrderForm',
      'subjectId': form['id'],
      'subjectNumber': form['formNumber'],
      'title': title,
      'summary': summary,
      'amount': form['totalAmount'],
      'liters': form['totalLiters'],
      'requestedByUserId': form['_createdBy'],
      'requestedByName': form['createdByName'],
      'createdAt': FakeWorld.utc(created),
      'dueAt': FakeWorld.utc(created.add(const Duration(hours: 24))),
      'slaState': 1,
      'currentLevelNo': 1,
      'levelCount': 1,
      'eligibleUserIds': [for (final k in eligible) 'u-$k'],
    };
    world.approvals.add(a);
    return a;
  }

  // ─────────────────────────────────────────────────────────── Ön kayıtlar

  void _seedLeads() {
    leads.addAll([
      // Onaylarım'daki 9004 (ek bilgi istendi: vergi levhası).
      newLead(
        id: 8001,
        number: 'ONK-00008',
        createdBy: 'u-saha',
        status: 3,
        companyTitle: 'Başkent Yapı Market',
        taxNumber: vkn('555666777'),
        city: 'Ankara',
        district: 'Çankaya',
        createdAt: _h(-30),
        submittedAt: _h(-28),
        decisionNote:
            'Vergi levhası okunmuyor; güncel ve net bir görüntü yükleyin.',
        approvalId: 9004,
        monthly: {1: 40000},
        kvkk: true,
        limit: 250000,
        methods: const ['HAVALE', 'CEK'],
      ),
      // Onaylarım'daki 9008 (onaylar sahtesi tohumlar).
      newLead(
        id: 8002,
        number: 'ONK-00012',
        createdBy: 'u-saha',
        status: 1,
        companyTitle: 'Yıldız Hırdavat Ltd. Şti.',
        taxNumber: vkn('481516234'),
        city: 'Kocaeli',
        district: 'Gebze',
        createdAt: _h(-20),
        submittedAt: _h(-18),
        approvalId: 9008,
        monthly: {1: 12000, 2: 2000},
        kvkk: true,
        limit: 150000,
        collateralPct: 150,
      ),
      // Onaylarım'daki 9009 (VKN başka bayide kayıtlı → "Merkeze ilet").
      newLead(
        id: 8003,
        number: 'ONK-00014',
        createdBy: 'u-saha',
        status: 2,
        companyTitle: 'Akdeniz Gıda Dağıtım A.Ş.',
        taxNumber: vkn('765432109'),
        city: 'Antalya',
        district: 'Muratpaşa',
        createdAt: _h(-44),
        submittedAt: _h(-40),
        approvalId: 9009,
        monthly: {1: 25000},
        kvkk: true,
        limit: 300000,
      ),
      newLead(
        id: 8004,
        number: 'ONK-${_day(_h(-60))}-000002',
        createdBy: 'u-mudur',
        status: 6,
        companyTitle: 'Ege Lojistik Hizmetleri',
        taxNumber: vkn('135792468'),
        city: 'İzmir',
        district: 'Bornova',
        createdAt: _h(-62),
        submittedAt: _h(-60),
        decisionNote: 'Risk raporu olumsuz; teminat önerisi yetersiz.',
        monthly: {1: 30000},
        kvkk: true,
      ),
      newLead(
        id: 8005,
        number: 'ONK-${_day(_h(-6))}-000001',
        createdBy: 'u-saha',
        status: 0,
        companyTitle: 'Marmara Beton Ltd. Şti.',
        taxNumber: vkn('246813579'),
        city: 'Kocaeli',
        district: 'Dilovası',
        createdAt: _h(-6),
        monthly: {1: 15000},
      ),
      newLead(
        id: 8006,
        number: 'ONK-${_day(_h(-240))}-000004',
        createdBy: 'u-saha',
        status: 5,
        companyTitle: 'Kuzey Gıda A.Ş.',
        taxNumber: vkn('202122232'),
        city: 'Sakarya',
        district: 'Adapazarı',
        createdAt: _h(-260),
        submittedAt: _h(-250),
        convertedAt: _h(-240),
        monthly: {1: 22000},
        kvkk: true,
      )..addAll({
        'customerCode': 'C-1088',
        'inviteEmail': 'muhasebe@kuzeygida.example',
        'inviteExpiresAt': FakeWorld.local(_h(-240 + 72)),
        'inviteCandidates': [
          'muhasebe@kuzeygida.example',
          'info@kuzeygida.example',
        ],
      }),
    ]);
    // Finansa gitmiş ön kayıtların vergi levhası yüklü (8001'inki okunmuyor: yeniden istenir).
    for (final id in const [8002, 8003, 8004, 8006]) {
      fakeAttachment(
        world,
        ownerType: 5,
        ownerId: id,
        kind: 10,
        fileName: 'vergi-levhasi.pdf',
        contentType: 'application/pdf',
        bytes: _samplePdf(),
        uploadedBy: world.persona(id == 8004 ? 'mudur' : 'saha'),
      );
    }
  }

  static Uint8List _samplePdf() => Uint8List.fromList(
    utf8.encode(
      '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n'
      '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n'
      '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\n'
      'trailer<</Root 1 0 R>>\n%%EOF\n',
    ),
  );

  /// Ön kayıt kaydı (`LeadDetailDto` anahtarları).
  JsonMap newLead({
    required int id,
    required String number,
    required String createdBy,
    required int status,
    required String companyTitle,
    required String taxNumber,
    String? city,
    String? district,
    DateTime? createdAt,
    DateTime? submittedAt,
    DateTime? convertedAt,
    String? decisionNote,
    int? approvalId,
    Map<int, double> monthly = const {},
    bool kvkk = false,
    double? limit = 500000,
    List<String> methods = const ['HAVALE'],
    double? collateralPct,
  }) {
    final creator = world.personaByUserId(createdBy);
    final rep = reps.where((r) => r['_userId'] == createdBy).firstOrNull;
    return {
      'id': id,
      'stationId': stationId,
      'concurrencyToken': newToken(),
      'companyTitle': companyTitle,
      'taxNumber': taxNumber,
      'taxOffice': city == null ? null : '$city Vergi Dairesi',
      'city': city,
      'district': district,
      'address': null,
      'sector': null,
      'foundedYear': null,
      'phone': null,
      'email': null,
      'website': null,
      'vehicleCount': null,
      'vehicleTypes': null,
      'hasTank': false,
      'tankCapacityLiters': null,
      'products': [
        for (final e in monthly.entries)
          {
            'productId': e.key,
            'productName': world.product(e.key)?['name'],
            'monthlyLiters': e.value,
            'committedMonthlyLiters': null,
          },
      ],
      'contractMonths': null,
      'firstOrderProductId': null,
      'firstOrderLiters': null,
      'firstShipDate': null,
      'requestedMethodCodes': [...methods],
      'requestedTermDays': 30,
      'requestedLimitAmount': limit,
      'collateralRatioPercent': collateralPct,
      'collateralOfferKind': null,
      'collateralOfferAmount': null,
      'collateralOfferNote': null,
      'currentDistributor': 'Shell',
      'currentTerminal': null,
      'currentPriceNote': null,
      'priceExpectation': null,
      'visitNote': null,
      'visitLatitude': null,
      'visitLongitude': null,
      'visitAccuracyMeters': null,
      'visitAt': FakeWorld.local(
        TrTime.startOfDay(createdAt ?? DateTime.now()),
      ),
      'deliveryPointName': null,
      'deliveryPointCity': null,
      'deliveryPointDistrict': null,
      'deliveryPointAddress': null,
      'contacts': [
        {
          'id': id * 10 + 1,
          'name': 'Hakan Uysal',
          'title': 'Genel müdür',
          'phone': '05320001122',
          'email':
              'hakan@${TurkishText.searchKey(companyTitle.split(' ').first)}.example',
          'isPrimary': true,
          'isInviteRecipient': true,
        },
      ],
      'kvkkConsent': kvkk,
      'kvkkConsentMethod': kvkk ? 'Islak imzalı form' : null,
      'leadNumber': number,
      'stationTitle': world.stationTitle(stationId),
      'status': status,
      'salesRepresentativeId': rep?['id'],
      'salesRepName': rep?['name'] ?? creator?.displayName,
      'createdByUserId': createdBy,
      'createdAt': FakeWorld.utc(createdAt ?? DateTime.now()),
      'submittedAt': submittedAt == null ? null : FakeWorld.utc(submittedAt),
      'kvkkConsentAt': kvkk ? FakeWorld.utc(createdAt ?? DateTime.now()) : null,
      'kvkkDocumentVersion': kvkk ? '1.0' : null,
      'existsElsewhere': elsewhereVkns.contains(taxNumber),
      'customerId': null,
      'convertedAt': convertedAt == null ? null : FakeWorld.utc(convertedAt),
      'decisionNote': decisionNote,
      'approvalRequestId': approvalId,
      'customerCode': null,
      'inviteEmail': null,
      'inviteExpiresAt': null,
      'customerHasPortalUser': false,
      'inviteCandidates': <String>[],
      'isForwardedToHq': false,
    };
  }
}
