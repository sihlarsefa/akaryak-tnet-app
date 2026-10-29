import 'dart:convert';
import 'dart:math';

import '../../core/auth/permissions.dart';
import '../../core/models/enums.dart';
import '../../core/models/json.dart';
import '../../core/models/me_access.dart';
import '../../core/network/fake/fake_parity.dart';
import '../../core/network/fake/fake_personas.dart';
import '../../core/network/fake/fake_server.dart';
import '../../core/network/fake/fake_world.dart';
import '../../core/utils/tr_time.dart';
import '../../core/utils/turkish_text.dart';
import 'copy.dart';

/// Testlerin sahte `orders/place` davranışını yönlendirdiği denetimler (dünya torbasında).
class CustomerOrdersFakeControls {
  CustomerOrdersFakeControls._();

  static CustomerOrdersFakeControls of(FakeWorld world) =>
      world.bag('a2.controls', CustomerOrdersFakeControls._);

  /// Bu sıradaki satır oluşturulamaz (0 = hiçbir şey oluşmaz → 400; ≥ 1 = kısmi sonuç). Tek sefer.
  int? failLineAt;
  String failMessage =
      'Bayinin bu ürün için tanımlı fiyatı yok; bayinizle görüşün.';

  /// Sipariş(ler) oluşur ve sonuç kaydedilir, ama yanıt 500 döner (istemci zaman aşımı gibi). Tek sefer.
  bool commitThenServerError = false;

  /// Sıradaki `orders/place` isteklerine verilecek hazır yanıtlar (işlenmeden).
  final List<FakeResponse> queued = [];

  /// Gelen `orders/place` istekleri (gövde + anahtar).
  final List<({String? key, JsonMap body})> placeRequests = [];

  /// Gelen karar istekleri.
  final List<({String path, String? key, JsonMap body})> decisionRequests = [];

  void reset() {
    failLineAt = null;
    commitThenServerError = false;
    queued.clear();
    placeRequests.clear();
    decisionRequests.clear();
  }
}

/// A2 sahte verisi ve JSON üreticileri (müşteri ana sayfası da kullanır).
abstract final class A2Fake {
  static const _shortMethod = {
    'NAKIT': 'Nakit',
    'HAVALE': 'Havale',
    'KART': 'Kart',
    'DBS': 'DBS',
    'CEK': 'Çek',
    'SENET': 'Senet',
    'ACIK_HESAP': 'Açık hesap',
    'TEMINAT': 'Teminat',
    'UTTS': 'UTTS',
    'AVANS': 'Avans',
  };

  static String methodShortName(String? code) =>
      _shortMethod[code] ?? (code ?? '');

  // ------------------------------------------------------------------ Kapsam

  static FakePersona customer(FakeRequest req) {
    final p = req.requireUser();
    if (p.persona != Persona.customer || p.customerId == null) {
      throw FakeResponse.forbidden(
        'Hesabınız bir cariye bağlı değil; bu işlem için yetkiniz yok.',
      );
    }
    return p;
  }

  static List<JsonMap> linksOf(FakeWorld w, int customerId) =>
      w.links.where((l) => l['customerId'] == customerId).toList()
        ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));

  /// Bayi bağlantısı (0 = varsayılan = ilk bağlantı).
  static JsonMap? link(FakeWorld w, int customerId, int stationId) {
    final links = linksOf(w, customerId);
    if (links.isEmpty) return null;
    if (stationId <= 0) return links.first;
    for (final l in links) {
      if (l['stationId'] == stationId) return l;
    }
    return null;
  }

  // ------------------------------------------------------------------ Zaman

  /// Ofsetsiz Türkiye yerel değere `+03:00` ekler (yeni DTO biçimi).
  static String? trOffset(Object? local) {
    final s = local?.toString();
    if (s == null || s.isEmpty) return null;
    if (s.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(s)) return s;
    return '$s+03:00';
  }

  static DateTime? instantOf(Object? local) =>
      TrTime.parseLocal(local?.toString());

  static String local(DateTime instant) => TrTime.isoLocal(instant);

  /// Teklif / karar penceresi: min(şimdi + 3 sa, gün sonu) (sunucu `OrderExpiryCalculator`).
  static DateTime expiryFrom(DateTime now) {
    final later = now.add(const Duration(hours: 3));
    final w = TrTime.wall(now);
    final end = TrTime.fromWall(w.year, w.month, w.day, 23, 59, 59);
    return later.isBefore(end) ? later : end;
  }

  // ------------------------------------------------------------------ Fiyat, ödeme, onay kuralı

  static double unitPrice(FakeWorld w, int stationId, int productId) {
    final p = w.product(productId);
    final base = (p?['listPrice'] as num?)?.toDouble() ?? 0;
    final offset = stationId == 2 ? 0.35 : 0.0;
    return double.parse((base + offset).toStringAsFixed(4));
  }

  static JsonMap _field(
    String key,
    String label, {
    String type = 'text',
    bool required = false,
    int? maxLength,
    String? placeholder,
  }) => {
    'key': key,
    'label': label,
    'type': type,
    'required': required,
    'maxLength': maxLength,
    'options': null,
    'placeholder': placeholder,
    'choices': null,
  };

  static JsonMap _method(
    String code,
    String name, {
    bool deferred = false,
    bool finance = false,
    int? docKind,
    bool docRequired = false,
    List<int> installments = const [],
    int minTerm = 0,
    int maxTerm = 0,
    int? defaultTerm,
    List<JsonMap> fields = const [],
    String? hint,
  }) => {
    'code': code,
    'name': name,
    'shortName': _shortMethod[code],
    'isDeferred': deferred,
    'requiresFinance': finance,
    'documentKind': docKind,
    'documentRequired': docRequired,
    'allowsInstallments': installments.isNotEmpty,
    'installmentOptions': installments,
    'minTermDays': minTerm,
    'maxTermDays': maxTerm,
    'defaultTermDays': defaultTerm,
    'fields': fields,
    'hint': hint,
  };

  /// Bayinin yöntemleri (katalog ∩ bayi ∩ cari kartı; sahte).
  static List<JsonMap> methods(int stationId) {
    final transfer = _method(
      'HAVALE',
      'Havale / EFT (peşin)',
      docKind: 3,
      fields: [
        _field('bank', 'Banka', maxLength: 80),
        _field('transferDate', 'Gönderim tarihi', type: 'date'),
      ],
      hint: 'Dekont yüklenince ödeme "Belge yüklendi" olur.',
    );
    final card = _method(
      'KART',
      'Kredi / banka kartı (POS)',
      docKind: 4,
      installments: stationId == 2 ? const [1, 3] : const [1, 3, 6],
      hint: 'Kart bilgisi istenmez; ödeme teslimatta POS ile alınır.',
    );
    if (stationId == 2) return [transfer, card];
    return [
      transfer,
      _method(
        'CEK',
        'Çek',
        deferred: true,
        finance: true,
        docKind: 1,
        docRequired: true,
        minTerm: 1,
        maxTerm: 180,
        defaultTerm: 30,
        fields: [
          _field('serialNo', 'Çek no', required: true, maxLength: 40),
          _field('bank', 'Banka', required: true, maxLength: 80),
          _field('branch', 'Şube', maxLength: 80),
          _field('drawer', 'Keşideci', required: true, maxLength: 150),
          _field('amount', 'Tutar', type: 'money', required: true),
          _field('dueDate', 'Vade tarihi', type: 'date', required: true),
        ],
        hint:
            'Çek görseli zorunlu; sipariş grubu başına tek çek portföye alınır.',
      ),
      _method(
        'SENET',
        'Senet',
        deferred: true,
        finance: true,
        docKind: 2,
        docRequired: true,
        minTerm: 1,
        maxTerm: 180,
        defaultTerm: 30,
        fields: [
          _field('debtor', 'Borçlu', required: true, maxLength: 150),
          _field('guarantor', 'Kefil', maxLength: 150),
          _field('amount', 'Tutar', type: 'money', required: true),
          _field('dueDate', 'Vade tarihi', type: 'date', required: true),
        ],
      ),
      _method(
        'ACIK_HESAP',
        'Açık hesap (cari vadeli)',
        deferred: true,
        finance: true,
        minTerm: 7,
        maxTerm: 60,
        defaultTerm: 30,
        hint:
            'Cari hesaba vadeli borç; vade finansın izin verdiği süreyi aşamaz.',
      ),
      card,
      _method('AVANS', 'Ön ödemeli bakiye'),
      _method(
        'NAKIT',
        'Nakit (peşin)',
        fields: [
          _field('note', 'Tahsilat notu', type: 'textarea', maxLength: 300),
        ],
      ),
    ];
  }

  static JsonMap? method(int stationId, String? code) {
    for (final m in methods(stationId)) {
      if (m['code'] == code) return m;
    }
    return null;
  }

  /// Ön ödemeli bakiye (bayi 1).
  static double? advanceBalance(FakeWorld w, int stationId) => stationId == 1
      ? w.bag<Map<String, double>>('a2.advance', () => {'1': 250000})['1']
      : null;

  /// Şirket içi onay ayarı (cari 101).
  static JsonMap companyApproval(int customerId) => customerId == 101
      ? {
          'required': true,
          'aboveLitres': 20000.0,
          'aboveAmount': 750000.0,
          'text':
              'Talep eden kullanıcıların toplam 20.000 litrenin veya tahmini '
              '750.000 ₺ tutarın üstündeki siparişleri şirket içi onaya düşer.',
        }
      : {
          'required': false,
          'aboveLitres': null,
          'aboveAmount': null,
          'text': '',
        };

  /// Sipariş verilebilirlik.
  static JsonMap orderingStatus(FakeWorld w, int customerId, int stationId) {
    final l = link(w, customerId, stationId);
    if (l == null) {
      final none = linksOf(w, customerId).isEmpty;
      return {
        'stationId': stationId,
        'customerId': customerId,
        'stationCustomerId': null,
        'canOrder': false,
        'blockReason': none
            ? 'Bağlı bayi bulunamadı. Sipariş verebilmek için bayinizin sizi cari olarak eklemesi gerekir.'
            : 'Bu bayiyle aktif bağlantınız yok.',
        'isGrandfathered': false,
        'profileStatus': null,
        'infoRequested': false,
        'openApprovalRequestId': null,
      };
    }
    final status = (l['financeStatus'] as int?) ?? 1;
    final blocked = l['orderingBlocked'] as String?;
    return {
      'stationId': l['stationId'],
      'customerId': customerId,
      'stationCustomerId': l['id'],
      'canOrder': blocked == null,
      'blockReason': blocked,
      'isGrandfathered': false,
      'profileStatus': status,
      'infoRequested': l['infoRequested'] == true,
      'openApprovalRequestId': l['openApprovalRequestId'],
    };
  }

  // ------------------------------------------------------------------ Şablonlar

  static List<JsonMap> templates(FakeWorld w) => w.bag<List<JsonMap>>(
    'a2.templates',
    () {
      final now = w.seededAt;
      return [
        {
          'id': 701,
          'customerId': 101,
          'name': 'Haftalık motorin – Pendik',
          'lines': [
            {
              'productId': 1,
              'deliveryPointId': 1001,
              'quantityLiters': 15000.0,
              'stationId': 1,
            },
          ],
          'lastUsedAt': now.subtract(const Duration(days: 3)).toIso8601String(),
          'createdAt': now.subtract(const Duration(days: 40)).toIso8601String(),
        },
        {
          'id': 702,
          'customerId': 101,
          'name': 'Şantiye ikmali (2 nokta)',
          'lines': [
            {
              'productId': 1,
              'deliveryPointId': 1001,
              'quantityLiters': 10000.0,
              'stationId': 1,
            },
            {
              'productId': 1,
              'deliveryPointId': 1002,
              'quantityLiters': 8000.0,
              'stationId': 1,
            },
          ],
          'lastUsedAt': now.subtract(const Duration(days: 9)).toIso8601String(),
          'createdAt': now.subtract(const Duration(days: 50)).toIso8601String(),
        },
        {
          'id': 703,
          'customerId': 101,
          'name': 'Benzin – Pendik',
          'lines': [
            {
              'productId': 2,
              'deliveryPointId': 1001,
              'quantityLiters': 5000.0,
              'stationId': 1,
            },
          ],
          'lastUsedAt': null,
          'createdAt': now.subtract(const Duration(days: 60)).toIso8601String(),
        },
      ];
    },
  );

  static List<JsonMap> templatesOf(FakeWorld w, int customerId) {
    final list = templates(
      w,
    ).where((t) => t['customerId'] == customerId).toList();
    int key(JsonMap t) {
      final at = DateTime.tryParse('${t['lastUsedAt'] ?? ''}');
      return at?.millisecondsSinceEpoch ?? 0;
    }

    list.sort((a, b) {
      final c = key(b).compareTo(key(a));
      if (c != 0) return c;
      return '${b['createdAt']}'.compareTo('${a['createdAt']}');
    });
    return list;
  }

  static String _templateSummary(FakeWorld w, List<Object?> lines) {
    final liters = lines.fold<double>(
      0,
      (s, l) => s + ((JsonReader.asMap(l)['quantityLiters'] as num?) ?? 0),
    );
    final products = {
      for (final l in lines)
        w.product(JsonReader.asMap(l)['productId'] as int?)?['name'],
    }.whereType<String>().toList();
    final points = {
      for (final l in lines) JsonReader.asMap(l)['deliveryPointId'],
    }.length;
    final name = products.length == 1
        ? products.first
        : '${products.length} ürün';
    return '$name ${fmtInt(liters)} L, $points nokta';
  }

  static String fmtInt(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }

  static JsonMap templateListItem(FakeWorld w, JsonMap t) {
    final lines = (t['lines'] as List?) ?? const [];
    return {
      'id': t['id'],
      'name': t['name'],
      'lineCount': lines.length,
      'totalLiters': lines.fold<double>(
        0,
        (s, l) => s + ((JsonReader.asMap(l)['quantityLiters'] as num?) ?? 0),
      ),
      'summary': _templateSummary(w, lines),
      'lastUsedAt': t['lastUsedAt'],
      'createdAt': t['createdAt'],
    };
  }

  static JsonMap templateDto(FakeWorld w, JsonMap t, int customerId) {
    final linkIds = {for (final l in linksOf(w, customerId)) l['stationId']};
    JsonMap line(Object? raw) {
      final l = JsonReader.asMap(raw);
      final p = w.product(l['productId'] as int?);
      final dp = w.deliveryPoint(l['deliveryPointId'] as int?);
      final stationId = l['stationId'] as int?;
      String? reason;
      if (p == null) {
        reason = 'Ürün artık satışta değil.';
      } else if (dp == null ||
          dp['isActive'] == false ||
          dp['customerId'] != customerId) {
        reason = 'Teslimat noktası pasif.';
      } else if (stationId != null && !linkIds.contains(stationId)) {
        reason = 'Bayiyle aktif bağlantınız yok.';
      }
      return {
        'id': 0,
        'productId': l['productId'],
        'productCode': p?['code'] ?? '',
        'productName': p?['name'] ?? '',
        'deliveryPointId': l['deliveryPointId'],
        'deliveryPointName': dp?['name'] ?? '',
        'deliveryPointAddress': dp?['address'] ?? '',
        'quantityLiters': l['quantityLiters'],
        'stationId': stationId,
        'stationTitle': w.stationTitle(stationId),
        'isAvailable': reason == null,
        'unavailableReason': reason,
      };
    }

    return {
      'id': t['id'],
      'customerId': customerId,
      'name': t['name'],
      'lastUsedAt': t['lastUsedAt'],
      'createdAt': t['createdAt'],
      'updatedAt': null,
      'lines': [for (final raw in (t['lines'] as List? ?? const [])) line(raw)],
    };
  }

  static void markTemplateUsed(FakeWorld w, int? id, int customerId) {
    if (id == null) return;
    for (final t in templates(w)) {
      if (t['id'] == id && t['customerId'] == customerId) {
        t['lastUsedAt'] = DateTime.now().toUtc().toIso8601String();
      }
    }
  }

  // ------------------------------------------------------------------ Teslimat noktaları

  static JsonMap deliveryPointDto(JsonMap dp) => {
    'id': dp['id'],
    'customerId': dp['customerId'],
    'name': dp['name'],
    'city': dp['city'] ?? '',
    'district': dp['district'] ?? '',
    'address': dp['address'] ?? '',
    'isActive': dp['isActive'] ?? true,
    'latitude': dp['latitude'],
    'longitude': dp['longitude'],
    'contactName': dp['contactName'],
    'contactPhone': dp['contactPhone'],
    'deliveryWindowStart': _timeSpan(
      dp['windowStart'] ?? dp['deliveryWindowStart'],
    ),
    'deliveryWindowEnd': _timeSpan(dp['windowEnd'] ?? dp['deliveryWindowEnd']),
    'tankCapacityLiters': dp['tankCapacityLiters'],
    'accessNotes': dp['accessNotes'],
    'hasLocation': dp['latitude'] != null && dp['longitude'] != null,
  };

  static String? _timeSpan(Object? v) {
    final s = v?.toString();
    if (s == null || s.isEmpty) return null;
    if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(s)) {
      return s == '24:00' ? '1.00:00:00' : '${s.padLeft(5, '0')}:00';
    }
    return s;
  }

  static List<JsonMap> activePoints(FakeWorld w, int customerId) => w
      .deliveryPointsOfCustomer(customerId)
      .where((d) => d['isActive'] != false)
      .toList();

  // ------------------------------------------------------------------ Sipariş satırları

  static JsonMap? latestQuote(JsonMap o) {
    final quotes = (o['quotes'] as List?)?.map(JsonReader.asMap).toList();
    if (quotes == null || quotes.isEmpty) return null;
    return quotes.reduce(
      (a, b) => ((a['version'] as int?) ?? 0) >= ((b['version'] as int?) ?? 0)
          ? a
          : b,
    );
  }

  static bool hasPaymentImage(FakeWorld w, int orderId) => w.attachments.any(
    (a) =>
        a['ownerType'] == 1 &&
        a['ownerId'] == orderId &&
        a['isActive'] == true &&
        (a['kind'] == 1 || a['kind'] == 2),
  );

  static const _openStatuses = {0, 1, 2, 3, 5};

  static bool documentMissing(FakeWorld w, JsonMap o) {
    final code = o['paymentMethodCode'];
    if (code != 'CEK' && code != 'SENET') return false;
    if (o['paymentStatus'] != 1) return false;
    if (!_openStatuses.contains(o['status'])) return false;
    return !hasPaymentImage(w, o['id'] as int);
  }

  /// Süre dolumu açık mı (testler kapatabilir).
  static bool expiryOn(FakeWorld w) =>
      w.bag<Map<String, bool>>('a2.expiry', () => {'on': true})['on'] ?? true;

  static JsonMap? activeShipment(FakeWorld w, int orderId) {
    final list = w.shipmentsOfOrder(orderId);
    for (final s in const [1, 2, 4, 0]) {
      for (final x in list) {
        if (x['status'] == s) return x;
      }
    }
    return null;
  }

  // ------------------------------------------------------------------ Panel eşitliği

  /// Talep edenin şirket içi onay kuralı teklif onayında (sunucu `OrderService.ApproveAsync` →
  /// `RequiresCompanyApproverAsync` → `CustomerApprovalRules.RequiresApproval`): yalnızca siparişin
  /// carisinin Talep eden kullanıcısı (Onaylayan, Yönetici ve rolü boş eski kullanıcı değil); eşik
  /// [companyApproval] (litre ya da son sürüm teklifin tutarı; tutar bilinmiyorsa ve litre eşiği
  /// yoksa güvenli taraf: onay gerekir).
  static bool requiresCompanyApprover(FakePersona p, JsonMap o) {
    if (p.persona != Persona.customer || p.customerId != o['customerId']) {
      return false;
    }
    if (p.customerUserRole != 1) return false;
    final rule = companyApproval(o['customerId'] as int);
    if (rule['required'] != true) return false;
    final liters = (o['quantityLiters'] as num).toDouble();
    final total = (latestQuote(o)?['totalAmountTry'] as num?)?.toDouble();
    final litres = (rule['aboveLitres'] as num?)?.toDouble();
    if (litres != null && liters > litres) return true;
    final amount = (rule['aboveAmount'] as num?)?.toDouble();
    if (amount != null) return total == null ? litres == null : total > amount;
    return false;
  }

  /// Panel eşitliği alanları (sunucu `CustomerOrderActionEvaluator`, web müşteri sipariş
  /// ayrıntısının değerleri): `canDecideQuote` (Onay bekliyor + yönetim ya da Teklifler "Düzenler"),
  /// `canApproveQuote` (karar ve şirket içi kilit yok), `approveBlockedReason` (kilitliyken sunucunun
  /// ret metni), `canAcceptDelivery` (carinin "Onaylandı" siparişinde kabul bekleyen sevkiyat ve
  /// Sevkiyatlar "Düzenler"; rol aranmaz). Bayi görüntüleyende değerlendirilmez (boş); alanlar
  /// kapalıysa ([FakeParity.on], yayındaki eski API) hiç yazılmaz.
  static JsonMap orderActions(FakeWorld w, FakePersona p, JsonMap o) {
    if (!FakeParity.on(w)) return const {};
    if (!FakeParity.evaluates(p, o['customerId'] as int?)) {
      return const {
        'canDecideQuote': null,
        'canApproveQuote': null,
        'approveBlockedReason': null,
        'canAcceptDelivery': null,
      };
    }
    final platform = p.persona == Persona.platform;
    final status = o['status'] as int?;
    final decide =
        status == 2 && (platform || p.can(Pg.customerQuotes, Perm.edit));
    final blocked = decide && !platform && requiresCompanyApprover(p, o);
    final reported = w
        .shipmentsOfOrder(o['id'] as int)
        .any((s) => s['status'] == 2);
    return {
      'canDecideQuote': decide,
      'canApproveQuote': decide && !blocked,
      'approveBlockedReason': blocked
          ? OrdersCopy.requesterApproveBlocked
          : null,
      'canAcceptDelivery':
          p.persona == Persona.customer &&
          status == 3 &&
          reported &&
          p.can(Pg.customerShipments, Perm.edit),
    };
  }

  /// Ana sayfanın karar satırları (`DashboardOrderRowDto`): yalnızca teklif alanları.
  static JsonMap quoteActions(FakeWorld w, FakePersona p, JsonMap o) {
    final a = orderActions(w, p, o);
    return {
      for (final k in const [
        'canDecideQuote',
        'canApproveQuote',
        'approveBlockedReason',
      ])
        if (a.containsKey(k)) k: a[k],
    };
  }

  static JsonMap orderRow(FakeWorld w, JsonMap o, {FakePersona? viewer}) {
    final q = latestQuote(o);
    final status = o['status'] as int;
    final finance = (o['financeStatus'] as int?) ?? 0;
    final shipment = activeShipment(w, o['id'] as int);
    final showExpiry =
        expiryOn(w) &&
        const {1, 5, 2}.contains(status) &&
        finance != 1 &&
        finance != 4;
    return {
      'id': o['id'],
      'orderNumber': o['orderNumber'],
      'status': status,
      'statusLabel': OrderStatus.fromCode(status).label,
      'stationId': o['stationId'],
      'stationTitle': o['stationTitle'],
      'productName': o['productName'],
      'quantityLiters': o['quantityLiters'],
      'deliveryPointName': o['deliveryPointName'],
      'requestedDeliveryDate': trOffset(o['requestedDeliveryDate']),
      'expiresAt': showExpiry ? trOffset(o['expiresAt']) : null,
      'quotedUnitPrice': q?['unitPriceTry'],
      'quotedTotal': q?['totalAmountTry'],
      'financeStatus': finance,
      'financeLabel': OrderFinanceStatus.fromCode(finance).label,
      'paymentMethodCode': o['paymentMethodCode'],
      'paymentMethodName': o['paymentMethodCode'] == null
          ? null
          : methodShortName(o['paymentMethodCode'] as String?),
      'paymentStatus': o['paymentStatus'] ?? 0,
      'paymentStatusLabel': PaymentStatus.fromCode(
        o['paymentStatus'] as int?,
      ).label,
      'activeShipmentStatus': shipment?['status'],
      'activeShipmentStatusLabel': shipment == null
          ? null
          : ShipmentStatus.fromCode(shipment['status'] as int?).label,
      'createdAt': trOffset(o['createdAt']),
      'paymentDueDate': trOffset(o['paymentDueDate']),
      'paymentDocumentMissing': documentMissing(w, o),
      if (viewer != null) ...orderActions(w, viewer, o),
    };
  }

  static bool canSeeOrder(FakePersona p, JsonMap o) {
    if (p.persona == Persona.platform) return true;
    if (p.persona == Persona.customer) return o['customerId'] == p.customerId;
    if (p.persona == Persona.bayi) {
      return o['stationId'] == p.stationId &&
          (p.can(Pg.stationOrders) || p.can(Pg.stationQuotes));
    }
    return false;
  }

  static JsonMap orderOr404(FakeRequest req) {
    final p = req.requireUser();
    final o = req.world.order(req.intParam('id'));
    if (o == null || !canSeeOrder(p, o)) {
      throw FakeResponse.notFound('Sipariş bulunamadı.');
    }
    return o;
  }

  static JsonMap orderDetail(FakeWorld w, JsonMap o, {FakePersona? viewer}) {
    final q = latestQuote(o);
    return {
      ...o,
      'statusDisplay': OrderStatus.fromCode(o['status'] as int?).label,
      'latestUnitPriceTry': q?['unitPriceTry'],
      'latestTotalAmountTry': q?['totalAmountTry'],
      'latestRevisionNote': q?['revisionNote'],
      if (viewer != null) ...orderActions(w, viewer, o),
    };
  }

  // ------------------------------------------------------------------ Durum geçmişi

  static List<JsonMap> history(FakeWorld w, int orderId) => w
      .bag<Map<int, List<JsonMap>>>('a2.history', () => {})
      .putIfAbsent(orderId, () => []);

  static void addHistory(
    FakeWorld w,
    int orderId,
    int from,
    int to, {
    String? note,
    String? userId,
  }) => history(w, orderId).add({
    'fromStatus': from,
    'toStatus': to,
    'note': note,
    'changedByUserId': userId,
    'changedAt': local(DateTime.now().toUtc()),
  });

  static DateTime? _lastAt(FakeWorld w, int orderId, int to) {
    DateTime? last;
    for (final h in history(w, orderId)) {
      if (h['toStatus'] != to) continue;
      final at = instantOf(h['changedAt']);
      if (at != null && (last == null || at.isAfter(last))) last = at;
    }
    return last;
  }

  // ------------------------------------------------------------------ Takip

  static JsonMap trackingShipment(JsonMap s) {
    final created = TrTime.parseUtc(s['createdAt']?.toString());
    final status = s['status'] as int? ?? 0;
    return {
      'id': s['id'],
      'code': s['code'] ?? 'SVK-${s['id'].toString().padLeft(8, '0')}',
      'plannedLiters': s['plannedLiters'],
      'deliveredLiters': s['deliveredLiters'],
      'vehiclePlate': s['vehiclePlate'] ?? '',
      'driverName': s['driverName'] ?? '',
      'scheduledAt': s['scheduledAt'],
      'status': status,
      'deliveryDocumentNo': s['deliveryDocumentNo'],
      'disputeNote': s['disputeNote'],
      'plannedAt': created == null ? s['scheduledAt'] : local(created),
      'dispatchedAt': s['dispatchedAt'],
      'deliveredAt': s['deliveredAt'],
      'acceptedAt': s['acceptedAt'],
      'disputedAt': status == 4 ? (s['disputedAt'] ?? s['deliveredAt']) : null,
      'cancelledAt': status == 5
          ? (s['cancelledAt'] ?? s['scheduledAt'])
          : null,
      'isDispatched': const {1, 2, 3, 4}.contains(status),
    };
  }

  static String _vehicle(JsonMap s) {
    final plate = '${s['vehiclePlate'] ?? ''}'.trim();
    final driver = '${s['driverName'] ?? ''}'.trim();
    if (plate.isEmpty) return driver;
    return driver.isEmpty ? plate : '$plate, $driver';
  }

  static String _num(num v, {int fraction = 0}) {
    final fixed = v.toStringAsFixed(fraction);
    final parts = fixed.split('.');
    final intPart = fmtInt(int.parse(parts[0]));
    return parts.length > 1 ? '$intPart,${parts[1]}' : intPart;
  }

  static String _dayText(Object? local) {
    final at = instantOf(local);
    if (at == null) return '';
    final w0 = TrTime.wall(at);
    return '${w0.day.toString().padLeft(2, '0')}.${w0.month.toString().padLeft(2, '0')}.${w0.year}';
  }

  static JsonMap tracking(FakeWorld w, JsonMap o, FakePersona viewer) {
    final id = o['id'] as int;
    final status = o['status'] as int;
    final latest = latestQuote(o);
    final rawShipments = w.shipmentsOfOrder(id);
    final shipments = rawShipments.map(trackingShipment).toList()
      ..sort((a, b) => '${b['plannedAt']}'.compareTo('${a['plannedAt']}'));
    final active = rawShipments.where((s) => s['status'] != 5).toList();
    final dispatched = active
        .where((s) => const {1, 2, 3, 4}.contains(s['status']))
        .toList();
    final accepted = active
        .where((s) => s['status'] == 3)
        .fold<double>(0, (t, s) => t + ((s['deliveredLiters'] as num?) ?? 0));
    final ordered = (o['quantityLiters'] as num).toDouble();
    final closed = status == 4 || status == 6;
    final approvedOrLater = status == 3 || status == 7;

    JsonMap step(String key, String label, String icon) => {
      'key': key,
      'label': label,
      'icon': icon,
      'state': 0,
      'at': null,
      'atIsDateOnly': false,
      'detail': null,
    };

    final received = step('received', 'Sipariş alındı', 'fa-file-text-o')
      ..['state'] = 2
      ..['at'] = o['createdAt'];

    final quote = step('quote', 'Teklif', 'fa-try');
    if (status == 5) {
      final at = _lastAt(w, id, 5);
      quote['state'] = 1;
      quote['at'] = at == null ? null : local(at);
      quote['detail'] = 'Revize istendi, yeni fiyat bekleniyor';
    } else if (status == 0 || status == 1) {
      quote['state'] = 1;
      quote['detail'] = o['financeStatus'] == 1
          ? 'Finans onayı bekleniyor'
          : 'Bayi fiyat hazırlıyor';
    } else if (latest != null) {
      final v = (latest['version'] as int?) ?? 1;
      quote['state'] = 2;
      quote['at'] = latest['createdAt'];
      quote['detail'] =
          '${_num(latest['unitPriceTry'] as num, fraction: 2)} ₺/L${v > 1 ? ', v$v' : ''}';
    } else if (closed) {
      quote['state'] = 3;
      quote['detail'] = OrderStatus.fromCode(status).label;
    } else {
      quote['state'] = 2;
    }

    final approval = step('approval', 'Onay', 'fa-gavel');
    if (approvedOrLater) {
      final at = _lastAt(w, id, 3);
      approval['state'] = 2;
      approval['at'] = at == null ? (latest?['createdAt']) : local(at);
      approval['detail'] = 'Teklif onaylandı';
    } else if (status == 2) {
      approval['state'] = 1;
      approval['at'] = latest?['createdAt'];
      approval['detail'] = 'Kararınız bekleniyor';
    } else if (closed && quote['state'] == 2) {
      approval['state'] = 3;
      approval['detail'] = status == 4
          ? 'Teklif reddedildi'
          : 'Karar süresi doldu';
    }

    final dispatch = step('dispatch', 'Yola çıktı', 'fa-truck');
    if (dispatched.isNotEmpty || status == 7) {
      dispatch['state'] = 2;
      final times =
          dispatched
              .map((s) => instantOf(s['dispatchedAt']))
              .whereType<DateTime>()
              .toList()
            ..sort();
      if (times.isNotEmpty) {
        dispatch['at'] = local(times.first);
      } else if (dispatched.isNotEmpty) {
        dispatch['at'] = dispatched.first['scheduledAt'];
        dispatch['atIsDateOnly'] = true;
      }
      final inTransit = dispatched.where((s) => s['status'] == 1).toList();
      final lead = inTransit.isNotEmpty
          ? inTransit.first
          : (dispatched.isEmpty ? null : dispatched.first);
      if (lead != null) {
        dispatch['detail'] =
            '${_vehicle(lead)}${dispatched.length > 1 ? ', ${dispatched.length} araç' : ''}';
      }
    } else if (status == 3) {
      dispatch['state'] = 1;
      final planned = active.where((s) => s['status'] == 0).toList()
        ..sort(
          (a, b) => '${a['scheduledAt']}'.compareTo('${b['scheduledAt']}'),
        );
      dispatch['detail'] = planned.isEmpty
          ? 'Sevkiyat planlanıyor'
          : '${_vehicle(planned.first)}, ${_dayText(planned.first['scheduledAt'])} planlandı';
    }

    final delivered = step('delivered', 'Teslim edildi', 'fa-flag-checkered');
    if (status == 7) {
      final times =
          active
              .map((s) => instantOf(s['acceptedAt']))
              .whereType<DateTime>()
              .toList()
            ..sort();
      delivered['state'] = 2;
      delivered['at'] = times.isEmpty ? null : local(times.last);
      delivered['detail'] =
          '${_num(accepted > 0 ? accepted : ordered)} L teslim alındı';
    } else if (status == 3 && dispatched.isNotEmpty) {
      delivered['state'] = 1;
      final reported = active.where((s) => s['status'] == 2).length;
      final disputed = active.where((s) => s['status'] == 4).length;
      if (reported > 0) {
        delivered['detail'] = 'Teslim kabulünüz bekleniyor';
      } else if (disputed > 0) {
        delivered['detail'] = 'İtiraz bayide inceleniyor';
      } else if (accepted > 0) {
        delivered['detail'] =
            '${_num(accepted)} / ${_num(ordered)} L teslim alındı';
      } else {
        delivered['detail'] = 'Araç yolda';
      }
    }

    final events = <JsonMap>[];
    for (final s in rawShipments) {
      final vehicle = _vehicle(s);
      final created = TrTime.parseUtc(s['createdAt']?.toString());
      events.add({
        'at': created == null ? s['scheduledAt'] : local(created),
        'icon': 'fa-calendar',
        'title': 'Sevkiyat planlandı',
        'note': '$vehicle, ${_num(s['plannedLiters'] as num)} L',
        'tone': 'info',
      });
      if (s['dispatchedAt'] != null) {
        events.add({
          'at': s['dispatchedAt'],
          'icon': 'fa-truck',
          'title': 'Araç yola çıktı',
          'note': vehicle,
          'tone': 'warn',
        });
      }
      if (s['deliveredAt'] != null) {
        final doc = s['deliveryDocumentNo'];
        events.add({
          'at': s['deliveredAt'],
          'icon': 'fa-map-marker',
          'title': 'Teslimat bildirildi',
          'note':
              '${_num((s['deliveredLiters'] as num?) ?? 0)} L${doc == null ? '' : ', irsaliye $doc'}',
          'tone': 'info',
        });
      }
      if (s['acceptedAt'] != null) {
        events.add({
          'at': s['acceptedAt'],
          'icon': 'fa-check',
          'title': 'Teslim alındı',
          'note': '${_num((s['deliveredLiters'] as num?) ?? 0)} L, $vehicle',
          'tone': 'ok',
        });
      }
    }
    events.sort((a, b) => '${b['at']}'.compareTo('${a['at']}'));

    JsonMap? comparison;
    if (latest != null) {
      final current = (latest['unitPriceTry'] as num).toDouble();
      final prev = <JsonMap>[];
      final others =
          w.orders
              .where(
                (x) =>
                    x['id'] != id &&
                    x['customerId'] == o['customerId'] &&
                    x['productId'] == o['productId'] &&
                    (x['status'] == 3 || x['status'] == 7),
              )
              .toList()
            ..sort(
              (a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'),
            );
      for (final x in others) {
        if (prev.length >= 5) break;
        final selected = ((x['quotes'] as List?) ?? const [])
            .map(JsonReader.asMap)
            .where((q) => q['isSelected'] == true)
            .toList();
        if (selected.isEmpty) continue;
        final price = (selected.first['unitPriceTry'] as num).toDouble();
        if (price <= 0) continue;
        prev.add({
          'orderId': x['id'],
          'orderNumber': x['orderNumber'],
          'orderedAt': x['createdAt'],
          'stationTitle': x['stationTitle'],
          'quantityLiters': x['quantityLiters'],
          'unitPriceTry': price,
          'diffPercent': _diff(current, price),
        });
      }
      double? avg;
      if (prev.isNotEmpty) {
        final sum = prev.fold<double>(
          0,
          (s, p) => s + (p['unitPriceTry'] as double),
        );
        avg = double.parse((sum / prev.length).toStringAsFixed(4));
      }
      final prices = [for (final p in prev) p['unitPriceTry'] as double];
      comparison = {
        'currentUnitPriceTry': current,
        'previous': prev,
        'lastUnitPriceTry': prev.isEmpty ? null : prev.first['unitPriceTry'],
        'lastDiffPercent': prev.isEmpty ? null : prev.first['diffPercent'],
        'averageUnitPriceTry': avg,
        'averageDiffPercent': avg == null ? null : _diff(current, avg),
        'minUnitPriceTry': prices.isEmpty ? null : prices.reduce(min),
        'maxUnitPriceTry': prices.isEmpty ? null : prices.reduce(max),
        'hasHistory': prev.isNotEmpty,
      };
    }

    return {
      'orderId': id,
      'status': status,
      'steps': [received, quote, approval, dispatch, delivered],
      'shipments': shipments,
      'events': events,
      'orderedLiters': ordered,
      'acceptedLiters': accepted,
      'inProcessLiters': active
          .where((s) => const {0, 1, 2, 4}.contains(s['status']))
          .fold<double>(0, (t, s) => t + ((s['plannedLiters'] as num?) ?? 0)),
      'awaitingAcceptanceCount': active.where((s) => s['status'] == 2).length,
      'canAcceptDeliveries':
          viewer.persona == Persona.customer &&
          viewer.customerId == o['customerId'] &&
          status == 3,
      'expiryEnabled': expiryOn(w),
      'priceComparison': comparison,
    };
  }

  static double _diff(double current, double reference) => reference <= 0
      ? 0
      : double.parse(
          ((current - reference) / reference * 100).toStringAsFixed(1),
        );

  // ------------------------------------------------------------------ Belge hedefi

  static JsonMap? documentTarget(FakeWorld w, List<JsonMap> orders) {
    if (orders.isEmpty) return null;
    String? method;
    for (final o in orders) {
      final c = o['paymentMethodCode'] as String?;
      if (c != null) {
        method = c;
        break;
      }
    }
    final (int, bool, String)? doc = switch (method) {
      'CEK' => (1, true, 'Çek görseli'),
      'SENET' => (2, true, 'Senet görseli'),
      'HAVALE' => (3, false, 'Havale / EFT dekontu'),
      _ => null,
    };
    if (doc == null) return null;
    final first = orders.first['id'] as int;
    return {
      'ownerType': 1,
      'ownerTypeLabel': 'Sipariş',
      'ownerId': first,
      'kind': doc.$1,
      'kindLabel': doc.$3,
      'required': doc.$2,
      'canUpload': true,
      'message': null,
      'orderId': first,
    };
  }

  // ------------------------------------------------------------------ Şirket içi talepler

  /// Şirket içi sipariş talepleri (`CustomerOrderRequestDto` biçiminde). A3 (Talepler) ve A5
  /// (Onaylarım) ile ortak torba (A-INT birleştirme).
  static List<JsonMap> companyRequests(FakeWorld w) =>
      w.bag<List<JsonMap>>('company.orderRequests', () => []);

  // ------------------------------------------------------------------ Bildirim (sahte push)

  static void notifyStation(
    FakeWorld w, {
    required int stationId,
    required String code,
    required String title,
    required String body,
    required int orderId,
    required bool Function(FakePersona p) audience,
    String category = 'orders',
    String? actorUserId,
  }) {
    for (final p in fakePersonas) {
      if (p.persona != Persona.bayi || p.stationId != stationId) continue;
      if (p.userId == actorUserId) continue;
      if (p.capabilities.containsKey(Caps.shipmentOwnOnly)) continue;
      if (!audience(p)) continue;
      w.addNotification(
        userId: p.userId,
        category: category,
        eventCode: code,
        title: title,
        body: body,
        route: '/bayi/orders/$orderId',
        entityType: 'Order',
        entityId: orderId,
      );
    }
  }

  static bool quoteCapable(FakePersona p) =>
      p.can(Pg.stationQuoteDesk, Perm.create) ||
      p.can(Pg.stationQuotes, Perm.create);

  static String money(double v) {
    final fixed = v.toStringAsFixed(2).split('.');
    return '${fmtInt(int.parse(fixed[0]))},${fixed[1]} ₺';
  }

  static String uuid(FakeWorld w) {
    final n = w.nextId('a2.group', start: 1);
    final r = Random(n * 7919);
    String hex(int len) =>
        List.generate(len, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
  }
}

/// CustomerOrders sahte uçları (sahibi A2). §B biçiminde JSON (anahtarlar C# camelCase adlarıyla
/// aynı); ortak dünya (`server.world`) okunur ve değiştirilir: verilen sipariş teklif masasına düşer,
/// müşterinin kararı bayiye bildirim olur.
///
/// Uçlar: `customers/me/orders`, `catalog/order-form`, `payments/options`, `orders/place`,
/// `orders/payment-document-target`, `orders/{id}` (+ `tracking`, `timeline`),
/// `orders/{id}/approve|revise|reject`, `customers/me/templates*`.
void registerCustomerOrdersFakes(FakeServer server) {
  _registerLists(server);
  _registerPlace(server);
  _registerDetail(server);
  _registerTemplates(server);
}

void _registerLists(FakeServer server) {
  server.get('customers/me/orders', (req) {
    final p = A2Fake.customer(req);
    if (!p.can(Pg.customerOrders) && !p.can(Pg.customerQuotes)) {
      throw FakeResponse.forbidden();
    }
    final w = req.world;
    final segment = req.query('segment') ?? 'active';
    final statuses = switch (segment) {
      'decision' => const {2},
      'history' => const {4, 6, 7},
      _ => const {0, 1, 3, 5},
    };
    final q = (req.query('q') ?? '').trim();
    final rows = w.ordersOfCustomer(p.customerId!).where((o) {
      if (!statuses.contains(o['status'])) return false;
      if (q.isEmpty) return true;
      return [
        o['orderNumber'],
        o['productName'],
        o['deliveryPointName'],
        o['stationTitle'],
      ].any((v) => TurkishText.matches(v?.toString(), q));
    }).toList();
    if (segment == 'decision') {
      rows.sort((a, b) => '${a['expiresAt']}'.compareTo('${b['expiresAt']}'));
    } else {
      rows.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    }
    return req.paged([for (final o in rows) A2Fake.orderRow(w, o, viewer: p)]);
  });

  server.get('catalog/order-form', (req) {
    final p = A2Fake.customer(req);
    req.requirePage(Pg.customerCreateOrder);
    final w = req.world;
    final cid = p.customerId!;
    final first = A2Fake.link(w, cid, 0);
    return {
      'customerId': cid,
      'linkedStationId': first?['stationId'],
      'linkedStationTitle': w.stationTitle(first?['stationId'] as int?),
      'products': [
        for (final pr in w.products)
          {
            'id': pr['id'],
            'code': pr['code'],
            'name': pr['name'],
            'unit': 'Litre',
            'sortOrder': pr['id'],
            'isActive': true,
          },
      ],
      'deliveryPoints': [
        for (final dp in A2Fake.activePoints(w, cid))
          A2Fake.deliveryPointDto(dp),
      ],
      'templates': [
        for (final t in A2Fake.templatesOf(w, cid))
          A2Fake.templateListItem(w, t),
      ],
    };
  });

  server.get('payments/options', (req) {
    final p = A2Fake.customer(req);
    req.requirePage(Pg.customerCreateOrder);
    final w = req.world;
    final cid = p.customerId!;
    final asked = req.queryInt('stationId') ?? 0;
    final l = A2Fake.link(w, cid, asked);
    final stationId = (l?['stationId'] as int?) ?? asked;
    final ids = <int>{
      for (final raw in req.queryAll('productIds'))
        for (final part in raw.split(','))
          if (int.tryParse(part.trim()) != null) int.parse(part.trim()),
    };
    return {
      'options': {
        'stationId': stationId,
        'customerId': cid,
        'enabled': true,
        'defaultMethodCode': l == null ? null : 'HAVALE',
        'methods': l == null ? const <Object>[] : A2Fake.methods(stationId),
        'blockedReason': l == null ? 'Bu bayiyle aktif bağlantınız yok.' : null,
        'advanceBalance': A2Fake.advanceBalance(w, stationId),
        'linked': l != null,
      },
      'unitPrices': l == null
          ? <String, double>{}
          : {
              for (final id in ids.take(50))
                if (w.product(id) != null)
                  '$id': A2Fake.unitPrice(w, stationId, id),
            },
    };
  });
}

void _registerPlace(FakeServer server) {
  server.post('orders/place', (req) {
    final p = A2Fake.customer(req);
    req.requirePage(Pg.customerCreateOrder, Perm.create);
    final w = req.world;
    final controls = CustomerOrdersFakeControls.of(w);
    final key = req.idempotencyKey;
    final body = JsonReader.asMap(req.body);
    controls.placeRequests.add((key: key, body: body));
    if (key == null || key.isEmpty) {
      throw FakeResponse.validation(const {
        'Idempotency-Key': ['Idempotency-Key başlığı gerekli.'],
      }, 'Idempotency-Key başlığı gerekli.');
    }
    final idem = w.bag<Map<String, JsonMap>>('a2.placeIdempotency', () => {});
    final stored = idem['${p.userId}|$key'];
    if (stored != null) {
      return FakeResponse(200, stored, const {'idempotent-replay': 'true'});
    }
    if (controls.queued.isNotEmpty) throw controls.queued.removeAt(0);
    final result = _place(req, p, w, controls, JsonReader.of(body));
    idem['${p.userId}|$key'] = result;
    if (controls.commitThenServerError) {
      controls.commitThenServerError = false;
      throw FakeResponse.server(
        'Sahte: sipariş kaydedildi ama yanıt ulaşmadı.',
      );
    }
    return result;
  });

  server.get('orders/payment-document-target', (req) {
    final p = A2Fake.customer(req);
    req.requirePage(Pg.customerOrders);
    final w = req.world;
    final ids = <int>{
      for (final raw in req.queryAll('orderIds'))
        for (final part in raw.split(','))
          if (int.tryParse(part.trim()) != null) int.parse(part.trim()),
    };
    final group = req.query('groupKey');
    final own = w.ordersOfCustomer(p.customerId!).where((o) {
      if (ids.isNotEmpty) return ids.contains(o['id']);
      return group != null && o['paymentGroupKey'] == group;
    }).toList()..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
    return A2Fake.documentTarget(w, own) ?? FakeResponse.noContent();
  });
}

JsonMap _place(
  FakeRequest req,
  FakePersona p,
  FakeWorld w,
  CustomerOrdersFakeControls controls,
  JsonReader r,
) {
  final cid = p.customerId!;
  final l = A2Fake.link(w, cid, r.integer('stationId'));
  if (l == null) {
    throw FakeResponse.business(
      A2Fake.linksOf(w, cid).isEmpty
          ? 'Bağlı bayi bulunamadı. Sipariş verebilmek için bayinizin sizi cari olarak eklemesi gerekir.'
          : 'Bu bayiyle aktif bağlantınız yok.',
    );
  }
  final stationId = l['stationId'] as int;
  final ordering = A2Fake.orderingStatus(w, cid, stationId);
  if (ordering['canOrder'] != true) {
    throw FakeResponse.business(
      ordering['blockReason'] as String? ??
          'Bu bayide şu an sipariş veremezsiniz.',
    );
  }
  final lines = r.list('lines', (x) => x);
  if (lines.isEmpty) {
    throw FakeResponse.business('En az bir ürün satırı ekleyin.');
  }
  if (lines.length > 20) {
    throw FakeResponse.business('Tek seferde en çok 20 satır gönderilebilir.');
  }
  final today = TrTime.todayStart();
  final fallbackDate = r.date('requestedDeliveryDate');
  final fallbackPoint = r.integer('deliveryPointId');
  String lineError(int i, String m) =>
      lines.length > 1 ? 'Satır ${i + 1}: $m' : m;
  final resolved =
      <({int productId, int pointId, double liters, DateTime date})>[];
  for (var i = 0; i < lines.length; i++) {
    final x = lines[i];
    final productId = x.integer('productId');
    final pointId = x.intOrNull('deliveryPointId') ?? fallbackPoint;
    final liters = x.dec('quantityLiters');
    final date = x.date('requestedDeliveryDate') ?? fallbackDate;
    final dp = w.deliveryPoint(pointId);
    String? err;
    if (productId <= 0) {
      err = 'Ürün seçin.';
    } else if (w.product(productId) == null) {
      err = 'Ürün bulunamadı veya pasif.';
    } else if (pointId <= 0) {
      err = 'Teslimat noktası seçin.';
    } else if (dp == null ||
        dp['customerId'] != cid ||
        dp['isActive'] == false) {
      err = 'Teslimat noktası geçersiz.';
    } else if (liters <= 0) {
      err = 'Miktar girin.';
    } else if (liters > 999999999 ||
        ((liters * 1000).round() - liters * 1000).abs() > 1e-6) {
      err = 'Miktar pozitif olmalı ve en fazla üç ondalık basamak içermelidir.';
    } else if (date == null) {
      err = 'Teslim tarihi seçin.';
    } else if (TrTime.dayDiff(today, date) < 0) {
      err = 'Teslim tarihi bugünden önce olamaz.';
    }
    if (err != null) throw FakeResponse.business(lineError(i, err));
    resolved.add((
      productId: productId,
      pointId: pointId,
      liters: liters,
      date: date!,
    ));
  }

  final payment = r.objOrNull('payment');
  final methodCode = payment?.nonEmpty('methodCode')?.asciiUpper;
  final method = methodCode == null
      ? null
      : A2Fake.method(stationId, methodCode);
  if (methodCode != null && method == null) {
    throw FakeResponse.business(
      'Seçilen ödeme yöntemi bu bayide kullanılamıyor.',
    );
  }
  final details = payment?.map('details') ?? const <String, dynamic>{};
  final termDays = payment?.intOrNull('termDays');
  final estimate = resolved.fold<double>(
    0,
    (s, x) => s + x.liters * A2Fake.unitPrice(w, stationId, x.productId),
  );
  if (methodCode == 'AVANS') {
    final bal = A2Fake.advanceBalance(w, stationId) ?? 0;
    if (estimate > bal) {
      throw FakeResponse.business(
        'Ön ödemeli bakiye yetersiz: kullanılabilir ${A2Fake.money(bal)}, '
        'tahmini tutar ${A2Fake.money(estimate)}.',
      );
    }
  }
  if (method != null) {
    for (final f in (method['fields'] as List).map(JsonReader.asMap)) {
      final v = '${details[f['key']] ?? ''}'.trim();
      if (f['required'] == true && v.isEmpty) {
        throw FakeResponse.business('${f['label']} zorunludur.');
      }
    }
    if ((method['maxTermDays'] as int) > 0 && termDays == null) {
      throw FakeResponse.business('Vade (gün) seçin.');
    }
  }

  // Talep eden kuralı
  final rule = A2Fake.companyApproval(cid);
  final totalLiters = resolved.fold<double>(0, (s, x) => s + x.liters);
  final aboveLitres = rule['aboveLitres'] as double?;
  final aboveAmount = rule['aboveAmount'] as double?;
  final requires =
      p.customerUserRole == 1 &&
      rule['required'] == true &&
      ((aboveLitres != null && totalLiters > aboveLitres) ||
          (aboveAmount != null && estimate > aboveAmount));
  if (requires) {
    return _companyRequest(
      w,
      p,
      r,
      stationId: stationId,
      resolved: resolved,
      methodCode: methodCode,
      termDays: termDays,
      details: details,
      totalLiters: totalLiters,
      estimate: estimate,
    );
  }

  // Doğrudan siparişler (ilk hatada durulur).
  final clientGroup = r.nonEmpty('paymentGroupKey');
  final groupKey =
      methodCode != null && (resolved.length > 1 || clientGroup != null)
      ? (clientGroup ?? A2Fake.uuid(w))
      : null;
  final now = DateTime.now().toUtc();
  final created = <JsonMap>[];
  String? partialError;
  int? failedIndex;
  final failAt = controls.failLineAt;
  controls.failLineAt = null;
  for (var i = 0; i < resolved.length; i++) {
    final x = resolved[i];
    if (failAt != null && i == failAt) {
      if (created.isEmpty) {
        throw FakeResponse.business(lineError(i, controls.failMessage));
      }
      partialError = lineError(i, controls.failMessage);
      failedIndex = i;
      break;
    }
    created.add(
      _createOrder(
        w,
        p,
        stationId: stationId,
        line: x,
        now: now,
        method: method,
        methodCode: methodCode,
        termDays: termDays,
        installments: payment?.intOrNull('installments'),
        details: details,
        groupKey: groupKey,
      ),
    );
  }
  A2Fake.markTemplateUsed(w, r.intOrNull('templateId'), cid);
  final financePending = created.where((o) => o['financeStatus'] == 1).length;
  final numbers = created.map((o) => o['orderNumber']).toList();
  var message = created.length == resolved.length
      ? (numbers.length == 1
            ? 'Sipariş oluşturuldu: ${numbers.first}'
            : '${numbers.length} sipariş oluşturuldu: ${numbers.join(', ')}')
      : '${numbers.length} sipariş oluşturuldu (${numbers.join(', ')}); '
            'kalan ${resolved.length - created.length} satır gönderilmedi.';
  if (financePending > 0) {
    message = financePending >= created.length
        ? '$message — finans onayına gönderildi; onaylanınca bayi teklif verecek.'
        : '$message — $financePending sipariş finans onayına gönderildi.';
  }
  return {
    'kind': 'orders',
    'orders': [
      for (final o in created)
        {
          'orderId': o['id'],
          'orderNumber': o['orderNumber'],
          'expiresAt': o['expiresAt'],
          'financeStatus': o['financeStatus'],
          'financeReasons': o['financeReasons'],
          'paymentMethodCode': o['paymentMethodCode'],
          'paymentDueDate': o['paymentDueDate'],
          'estimatedAmount': o['estimatedAmount'],
          'paymentGroupKey': o['paymentGroupKey'],
        },
    ],
    'paymentGroupKey': groupKey,
    'financePendingCount': financePending,
    'companyRequest': null,
    'paymentDocument': A2Fake.documentTarget(w, created),
    'partialError': partialError,
    'message': message,
    'failedLineIndex': failedIndex,
  };
}

JsonMap _createOrder(
  FakeWorld w,
  FakePersona p, {
  required int stationId,
  required ({int productId, int pointId, double liters, DateTime date}) line,
  required DateTime now,
  required JsonMap? method,
  required String? methodCode,
  required int? termDays,
  required int? installments,
  required Map<String, dynamic> details,
  required String? groupKey,
}) {
  final cid = p.customerId!;
  final id = w.nextId('order');
  final term = method == null
      ? null
      : ((method['maxTermDays'] as int) > 0 ? termDays : 0);
  final instrumentDue = (methodCode == 'CEK' || methodCode == 'SENET')
      ? TrTime.parseDate('${details['dueDate'] ?? ''}')
      : null;
  final finance = method?['requiresFinance'] == true ? 1 : 0;
  final o = w.newOrder(
    id: id,
    customerId: cid,
    stationId: stationId,
    deliveryPointId: line.pointId,
    productId: line.productId,
    liters: line.liters,
    status: 1,
    createdAt: now,
    expiresAt: A2Fake.expiryFrom(now),
    requestedDeliveryDate: line.date,
    paymentMethodCode: methodCode ?? 'HAVALE',
    paymentTermDays: term,
    paymentStatus: methodCode == null ? 0 : 1,
    financeStatus: finance,
    financeReasons: finance == 1 ? 'Vadeli yöntem (${term ?? 0} gün)' : null,
    createdByUserId: p.userId,
  );
  if (methodCode == null) {
    o['paymentMethodCode'] = null;
    o['paymentMethodName'] = null;
    o['paymentDueDate'] = null;
  } else {
    o['paymentMethodName'] = A2Fake.methodShortName(methodCode);
    if (instrumentDue != null) {
      o['paymentDueDate'] = A2Fake.local(instrumentDue);
    }
  }
  o['estimatedAmount'] = double.parse(
    (line.liters * A2Fake.unitPrice(w, stationId, line.productId))
        .toStringAsFixed(2),
  );
  o['paymentInstallments'] = installments;
  o['paymentDetailJson'] = details.isEmpty ? null : jsonEncode(details);
  o['paymentGroupKey'] = groupKey;
  w.orders.add(o);
  A2Fake.addHistory(w, id, 0, 1, userId: p.userId);
  if (finance == 1) {
    final approvalId = w.nextId('approval');
    w.approvals.add({
      'id': approvalId,
      'type': 4,
      'status': 0,
      'isMirror': true,
      'stationId': stationId,
      'stationTitle': w.stationTitle(stationId),
      'customerId': cid,
      'customerTitle': w.customerTitle(cid),
      'subjectType': 'Order',
      'subjectId': id,
      'subjectNumber': o['orderNumber'],
      'title': 'Sipariş finans onayı',
      'summary': '${A2Fake.methodShortName(methodCode)}, ${term ?? 0} gün vade',
      'amount': o['estimatedAmount'],
      'liters': line.liters,
      'requestedByUserId': p.userId,
      'requestedByName': '${w.customerTitle(cid)} (müşteri siparişi)',
      'createdAt': now.toIso8601String(),
      'dueAt': now.add(const Duration(hours: 8)).toIso8601String(),
      'slaState': 1,
      'currentLevelNo': 1,
      'levelCount': 1,
      'eligibleUserIds': const ['u-finans', 'u-mudur', 'u-sahip'],
    });
    o['financeApprovalRequestId'] = approvalId;
  } else {
    A2Fake.notifyStation(
      w,
      stationId: stationId,
      code: 'order.created',
      title: 'Yeni sipariş',
      body:
          '${w.customerTitle(cid)}, ${o['orderNumber']}, '
          '${A2Fake.fmtInt(line.liters)} L ${o['productName']}',
      orderId: id,
      audience: A2Fake.quoteCapable,
      actorUserId: p.userId,
    );
  }
  return o;
}

JsonMap _companyRequest(
  FakeWorld w,
  FakePersona p,
  JsonReader r, {
  required int stationId,
  required List<({int productId, int pointId, double liters, DateTime date})>
  resolved,
  required String? methodCode,
  required int? termDays,
  required Map<String, dynamic> details,
  required double totalLiters,
  required double estimate,
}) {
  final cid = p.customerId!;
  final id = w.nextId('companyRequest', start: 3100);
  A2Fake.companyRequests(w).add({
    'id': id,
    'concurrencyToken':
        '00000000-0000-4000-8000-${id.toString().padLeft(12, '0')}',
    'customerId': cid,
    'requestedByUserId': p.userId,
    'requestedByName': p.displayName,
    'status': 0,
    'statusLabel': 'Onay bekliyor',
    'totalLiters': totalLiters,
    'estimatedAmount': double.parse(estimate.toStringAsFixed(2)),
    'note': r.nonEmpty('note'),
    'decidedByName': null,
    'decidedAt': null,
    'decisionNote': null,
    'createdOrderIds': <int>[],
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'paymentMethodCode': methodCode,
    'paymentMethodName': methodCode == null
        ? null
        : A2Fake.methodShortName(methodCode),
    'paymentTermDays': termDays,
    'paymentInstallments': null,
    'paymentDetailJson': details.isEmpty ? null : jsonEncode(details),
    'lines': [
      for (final x in resolved)
        {
          'stationId': stationId,
          'productId': x.productId,
          'deliveryPointId': x.pointId,
          'quantityLiters': x.liters,
          'requestedDeliveryDate': A2Fake.local(x.date),
          'estimatedUnitPrice': A2Fake.unitPrice(w, stationId, x.productId),
          'orderId': null,
          'orderNumber': null,
          'error': null,
          'stationTitle': w.stationTitle(stationId),
          'productName': w.product(x.productId)?['name'],
          'deliveryPointName': w.deliveryPoint(x.pointId)?['name'],
        },
    ],
    'canDecide': false,
    'canCancel': true,
  });
  final approvers = [
    for (final x in fakePersonas)
      if (x.customerId == cid &&
          x.userId != p.userId &&
          (x.customerUserRole ?? 3) >= 2)
        x,
  ];
  final approvalId = w.nextId('approval');
  w.approvals.add({
    'id': approvalId,
    'type': 3,
    'status': 0,
    'isMirror': true,
    'stationId': stationId,
    'stationTitle': w.stationTitle(stationId),
    'customerId': cid,
    'customerTitle': w.customerTitle(cid),
    'subjectType': 'CustomerOrderRequest',
    'subjectId': id,
    'subjectNumber': 'TLP-${id.toString().padLeft(5, '0')}',
    'title': 'Şirket içi sipariş talebi',
    'summary': '${A2Fake.fmtInt(totalLiters)} L, ${resolved.length} satır',
    'amount': double.parse(estimate.toStringAsFixed(2)),
    'liters': totalLiters,
    'requestedByUserId': p.userId,
    'requestedByName': p.displayName,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'dueAt': null,
    'slaState': 1,
    'currentLevelNo': 1,
    'levelCount': 1,
    'eligibleUserIds': [for (final a in approvers) a.userId],
  });
  for (final a in approvers) {
    w.addNotification(
      userId: a.userId,
      category: 'approvals',
      eventCode: 'approval.pending',
      title: 'Onayınızı bekleyen talep',
      body:
          '${p.displayName} ${A2Fake.fmtInt(totalLiters)} L sipariş talep etti.',
      route: '/approvals/$approvalId',
      entityType: 'ApprovalRequest',
      entityId: approvalId,
    );
  }
  A2Fake.markTemplateUsed(w, r.intOrNull('templateId'), cid);
  final message =
      'Siparişiniz şirket içi onaya gönderildi (Talep #$id). '
      'Onaylanınca siparişleriniz bayiye iletilir.';
  final (int, String, String, bool)? doc = switch (methodCode) {
    'CEK' => (
      1,
      'Çek görseli',
      'Onaylanınca çek görselini yüklemeniz istenecek',
      true,
    ),
    'SENET' => (
      2,
      'Senet görseli',
      'Onaylanınca senet görselini yüklemeniz istenecek',
      true,
    ),
    'HAVALE' => (
      3,
      'Havale / EFT dekontu',
      'Onaylanınca dekontu yükleyebilirsiniz',
      false,
    ),
    _ => null,
  };
  return {
    'kind': 'companyRequest',
    'orders': const <Object>[],
    'paymentGroupKey': null,
    'financePendingCount': 0,
    'companyRequest': {'id': id, 'message': message},
    'paymentDocument': doc == null
        ? null
        : {
            'ownerType': 1,
            'ownerTypeLabel': 'Sipariş',
            'ownerId': 0,
            'kind': doc.$1,
            'kindLabel': doc.$2,
            'required': doc.$4,
            'canUpload': false,
            'message': doc.$3,
            'orderId': null,
          },
    'partialError': null,
    'message': message,
    'failedLineIndex': null,
  };
}

void _registerDetail(FakeServer server) {
  server.get('orders/{id:int}', (req) {
    final o = A2Fake.orderOr404(req);
    return A2Fake.orderDetail(req.world, o, viewer: req.requireUser());
  });

  server.get('orders/{id:int}/tracking', (req) {
    final o = A2Fake.orderOr404(req);
    return A2Fake.tracking(req.world, o, req.requireUser());
  });

  server.get('orders/{id:int}/timeline', (req) {
    final o = A2Fake.orderOr404(req);
    final h = A2Fake.history(req.world, o['id'] as int);
    // Bayi tarafının geçişleri (teklif, tamamlama; A4 sahtesi) aynı çizelgeye girer (A-INT birleştirme).
    final bayi =
        req.world.bag<Map<int, List<JsonMap>>>(
          'bayi.timeline',
          () => {},
        )[o['id']] ??
        const <JsonMap>[];
    DateTime at(JsonMap e) =>
        TrTime.parseLocal(e['changedAt'] as String?) ?? DateTime(2000);
    return [
      if (h.isEmpty)
        {
          'fromStatus': 0,
          'toStatus': 1,
          'note': null,
          'changedByUserId': o['createdByUserId'],
          'changedAt': o['createdAt'],
        },
      ...h,
      ...bayi,
    ]..sort((a, b) => at(a).compareTo(at(b)));
  });

  for (final action in const ['approve', 'reject', 'revise']) {
    server.post('orders/{id:int}/$action', (req) => _decide(req, action));
  }
}

JsonMap _decide(FakeRequest req, String action) {
  final p = A2Fake.customer(req);
  req.requirePage(Pg.customerQuotes, Perm.edit);
  final w = req.world;
  final controls = CustomerOrdersFakeControls.of(w);
  final body = JsonReader.asMap(req.body);
  controls.decisionRequests.add((
    path: req.path,
    key: req.idempotencyKey,
    body: body,
  ));
  final o = w.order(req.intParam('id'));
  if (o == null || o['customerId'] != p.customerId) {
    throw FakeResponse.notFound('Sipariş bulunamadı.');
  }
  final r = JsonReader.of(body);
  final note = r.nonEmpty('note');
  if (action == 'revise' && note == null) {
    throw FakeResponse.business('Revize açıklaması zorunludur.');
  }
  final latest = A2Fake.latestQuote(o);
  final expected = r.intOrNull('expectedQuoteId');
  if (expected != null && latest != null && latest['id'] != expected) {
    throw FakeResponse.conflict(
      'concurrency_conflict',
      'Teklif güncellendi; güncel teklifi görüp yeniden karar verin.',
    );
  }
  if (o['status'] != 2) {
    throw FakeResponse.business(
      'Sipariş onay/red/revize için uygun durumda değil.',
    );
  }
  if (latest == null) {
    throw FakeResponse.business('Onaylanacak teklif bulunamadı.');
  }
  if (action == 'approve') {
    // Şirket içi onay kuralı, ilk denetim (sunucu `OrderService.ApproveAsync`): talep edenin eşik
    // üstü teklifini yalnızca Onaylayan ya da Yönetici onaylar (web, API ve mobil aynı metin);
    // revize ve red bu kurala tabi değildir.
    if (A2Fake.requiresCompanyApprover(p, o)) {
      throw FakeResponse.business(OrdersCopy.requesterApproveBlocked);
    }
    if (A2Fake.documentMissing(w, o)) {
      final label = o['paymentMethodCode'] == 'SENET'
          ? 'Senet görseli'
          : 'Çek görseli';
      throw FakeResponse.business(
        '$label yüklenmeden teklif onaylanamaz. Sipariş detayındaki Ödeme '
        'kartından ${TurkishText.lower(label)} ekleyip yeniden onaylayın.',
      );
    }
    if (o['paymentMethodCode'] == 'AVANS') {
      final bal = A2Fake.advanceBalance(w, o['stationId'] as int) ?? 0;
      final total = (latest['totalAmountTry'] as num).toDouble();
      if (total > bal) {
        throw FakeResponse.business(
          'Ön ödemeli bakiye yetersiz: kullanılabilir ${A2Fake.money(bal)}, '
          'teklif tutarı ${A2Fake.money(total)}.',
        );
      }
    }
  }
  final from = o['status'] as int;
  final to = switch (action) {
    'approve' => 3,
    'reject' => 4,
    _ => 5,
  };
  o['status'] = to;
  if (to == 3) {
    for (final q in (o['quotes'] as List).map(JsonReader.asMap)) {
      q['isSelected'] = q['id'] == latest['id'];
    }
  }
  if (to == 5) {
    latest['revisionNote'] = note;
    o['expiresAt'] = A2Fake.local(A2Fake.expiryFrom(DateTime.now().toUtc()));
  }
  A2Fake.addHistory(w, o['id'] as int, from, to, note: note, userId: p.userId);
  final (title, code) = switch (to) {
    3 => ('Teklif onaylandı', 'order.approved'),
    4 => ('Teklif reddedildi', 'order.rejected'),
    _ => ('Revize istendi', 'order.revision_requested'),
  };
  A2Fake.notifyStation(
    w,
    stationId: o['stationId'] as int,
    code: code,
    title: title,
    body: '${o['customerTitle']}, ${o['orderNumber']}',
    orderId: o['id'] as int,
    category: 'quotes',
    audience: (x) =>
        A2Fake.quoteCapable(x) ||
        (to == 3 && x.can(Pg.stationShipments, Perm.create)),
    actorUserId: p.userId,
  );
  return {
    'message': switch (to) {
      3 => 'Sipariş onaylandı.',
      4 => 'Sipariş reddedildi.',
      _ => 'Revize talebi iletildi.',
    },
  };
}

void _registerTemplates(FakeServer server) {
  server.get('customers/me/templates', (req) {
    final p = A2Fake.customer(req);
    req.requirePage(Pg.customerCreateOrder);
    final w = req.world;
    return [
      for (final t in A2Fake.templatesOf(w, p.customerId!))
        A2Fake.templateListItem(w, t),
    ];
  });

  server.get('customers/me/templates/{id:int}', (req) {
    final p = A2Fake.customer(req);
    req.requirePage(Pg.customerCreateOrder);
    final w = req.world;
    final id = req.intParam('id');
    final t = A2Fake.templates(w)
        .where((x) => x['id'] == id && x['customerId'] == p.customerId)
        .firstOrNull;
    if (t == null) throw FakeResponse.notFound('Şablon bulunamadı.');
    return A2Fake.templateDto(w, t, p.customerId!);
  });

  server.post('customers/me/templates', (req) {
    final p = A2Fake.customer(req);
    req.requirePage(Pg.customerCreateOrder, Perm.create);
    final w = req.world;
    final r = req.json;
    final name = r.str('name').trim();
    if (name.isEmpty) throw FakeResponse.business('Şablon adı zorunludur.');
    if (name.length > 100) {
      throw FakeResponse.business('Şablon adı en çok 100 karakter olabilir.');
    }
    final lines = r.list('lines', (x) => x);
    if (lines.isEmpty) {
      throw FakeResponse.business('Şablonda en az bir satır olmalı.');
    }
    final all = A2Fake.templates(w);
    final id = r.intOrNull('id');
    var t = id == null || id == 0
        ? null
        : all
              .where((x) => x['id'] == id && x['customerId'] == p.customerId)
              .firstOrNull;
    if (t == null) {
      if (A2Fake.templatesOf(w, p.customerId!).length >= 20) {
        throw FakeResponse.business('En çok 20 şablon kaydedebilirsiniz.');
      }
      t = {
        'id': w.nextId('template', start: 710),
        'customerId': p.customerId,
        'lastUsedAt': null,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };
      all.add(t);
    }
    t['name'] = name;
    t['lines'] = [
      for (final x in lines)
        {
          'productId': x.integer('productId'),
          'deliveryPointId': x.integer('deliveryPointId'),
          'quantityLiters': x.dec('quantityLiters'),
          'stationId': x.intOrNull('stationId'),
        },
    ];
    return A2Fake.templateDto(w, t, p.customerId!);
  });

  server.delete('customers/me/templates/{id:int}', (req) {
    final p = A2Fake.customer(req);
    req.requirePage(Pg.customerCreateOrder, Perm.create);
    final all = A2Fake.templates(req.world);
    final id = req.intParam('id');
    final before = all.length;
    all.removeWhere((x) => x['id'] == id && x['customerId'] == p.customerId);
    if (all.length == before) throw FakeResponse.notFound('Şablon bulunamadı.');
    return {'message': 'Şablon silindi.'};
  });

  server.post('customers/me/templates/from-order', (req) {
    final p = A2Fake.customer(req);
    req.requirePage(Pg.customerCreateOrder);
    final w = req.world;
    final orderId = req.queryInt('orderId');
    JsonMap? source;
    if (orderId == null) {
      final own = w.ordersOfCustomer(p.customerId!)
        ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
      source = own.firstOrNull;
    } else {
      source = w.order(orderId);
    }
    if (source == null || source['customerId'] != p.customerId) {
      throw FakeResponse.notFound('Sipariş bulunamadı.');
    }
    final draft = {
      'id': 0,
      'customerId': p.customerId,
      'name': '${source['productName']} – ${source['deliveryPointName']}',
      'lines': [
        {
          'productId': source['productId'],
          'deliveryPointId': source['deliveryPointId'],
          'quantityLiters': source['quantityLiters'],
          'stationId': source['stationId'],
        },
      ],
      'lastUsedAt': null,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    return A2Fake.templateDto(w, draft, p.customerId!);
  });

  server.post('customers/me/templates/{id:int}/mark-used', (req) {
    final p = A2Fake.customer(req);
    A2Fake.markTemplateUsed(req.world, req.intParam('id'), p.customerId!);
    return {'message': 'Şablon kullanımı kaydedildi.'};
  });
}
