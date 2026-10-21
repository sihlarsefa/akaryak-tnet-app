import '../../../core/auth/permissions.dart';
import '../../../core/models/json.dart';
import '../../../core/models/me_access.dart';
import '../../../core/network/fake/fake_personas.dart';
import '../../../core/network/fake/fake_server.dart';
import '../../../core/network/fake/fake_world.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';

/// A3 sahtelerinin ortak yardımcıları (sunucu kurallarının sade kopyaları).
abstract final class CmFake {
  /// Dünyadaki ofsetsiz Türkiye yerel değer → `+03:00` (yeni DTO'lar).
  static String? offset(Object? local) {
    final t = TrTime.parseLocal(local as String?);
    return t == null ? null : TrTime.isoOffset(t);
  }

  static DateTime? instant(Object? local) =>
      TrTime.parseLocal(local as String?);

  static bool isCustomer(FakePersona p) => p.persona == Persona.customer;
  static bool isBayi(FakePersona p) => p.persona == Persona.bayi;
  static bool isPlatform(FakePersona p) => p.persona == Persona.platform;
  static bool ownOnly(FakePersona p) =>
      isBayi(p) && p.capabilities.containsKey(Caps.shipmentOwnOnly);

  /// Sevkiyatı görebilir mi (B7 kuralları; görünmeyen 404 olur).
  static bool canSeeShipment(FakePersona p, JsonMap sh) {
    if (isPlatform(p)) return true;
    if (isCustomer(p)) {
      return sh['customerId'] == p.customerId &&
          (p.can(Pg.customerShipments) || p.can(Pg.customerOrders));
    }
    if (isBayi(p)) {
      if (sh['stationId'] != p.stationId) return false;
      if (ownOnly(p)) return sh['driverUserId'] == p.userId;
      return p.can(Pg.stationShipments) || p.can(Pg.stationShipmentBoard);
    }
    return false;
  }

  /// Sevkiyat sırası (iptaller hariç, kimlik sırası; 1 tabanlı).
  static ({int seq, int count}) seqOf(FakeWorld w, JsonMap sh) {
    final list =
        w
            .shipmentsOfOrder(sh['orderId'] as int)
            .where((s) => s['status'] != 5)
            .toList()
          ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
    final i = list.indexWhere((s) => s['id'] == sh['id']);
    return (seq: i < 0 ? 0 : i + 1, count: list.length);
  }

  /// Bayilerin belge bilgileri (sahte; gerçek veri değildir).
  static JsonMap stationParty(FakeWorld w, int? stationId) {
    final s = w.station(stationId) ?? const <String, dynamic>{};
    final extra = _stationExtra[stationId] ?? const <String, String>{};
    return {
      'title': s['title'] ?? '',
      'legalTitle': null,
      'code': s['code'],
      'taxNumber': extra['taxNumber'],
      'taxOffice': extra['taxOffice'],
      'epdkLicenseNo': extra['epdk'],
      'address': extra['address'],
      'district': s['district'],
      'city': s['city'],
      'phone': Fmt.phone(s['phone'] as String?),
      'email': extra['email'],
      'contactName': null,
      'erpCode': null,
      'note': extra['note'],
    };
  }

  static JsonMap customerParty(FakeWorld w, int? customerId) {
    final c = w.customer(customerId) ?? const <String, dynamic>{};
    return {
      'title': c['title'] ?? '',
      'legalTitle': null,
      'code': 'C-${customerId ?? 0}',
      'taxNumber': c['taxNumber'],
      'taxOffice': _customerTaxOffice[customerId],
      'epdkLicenseNo': null,
      'address': _customerAddress[customerId],
      'district': c['district'],
      'city': c['city'],
      'phone': Fmt.phone(c['phone'] as String?),
      'email': c['email'],
      'contactName': _customerContact[customerId],
      'erpCode': null,
      'note': null,
    };
  }

  static const Map<int, Map<String, String>> _stationExtra = {
    1: {
      'taxNumber': '2650012345',
      'taxOffice': 'Gebze',
      'epdk': 'BAY/939-62/12345',
      'address': 'Güzeller OSB, D-100 Karayolu No:1',
      'email': 'satis@demirpetrol.example',
      'note': 'Teslimat günü saat 17:00’ye kadar sipariş verin.',
    },
    2: {
      'taxNumber': '5730098765',
      'taxOffice': 'Tuzla',
      'epdk': 'BAY/940-11/54321',
      'address': 'Aydınlı Sanayi Bölgesi, 3. Cadde No:8',
      'email': 'siparis@kuzeyenerji.example',
    },
  };

  static const Map<int, String> _customerTaxOffice = {
    101: 'Pendik',
    102: 'İzmit',
    103: 'Nilüfer',
    104: 'Körfez',
  };

  static const Map<int, String> _customerAddress = {
    101: 'Kurtköy Mah. Ankara Cad. No:12',
    102: 'Kozluk Mah. Şehit Cad. No:21',
    103: 'Görükle Mah. Kooperatif Sk. No:3',
    104: 'Hereke Mah. Liman Yolu No:8',
  };

  static const Map<int, String> _customerContact = {
    101: 'Selin Aydın',
    102: 'Serkan Polat',
  };

  /// Ödeme satırı (`PaymentDisplay.Line`): "Çek · 30 gün · vade 20.11.2026".
  static String paymentLine(JsonMap o) {
    final code = o['paymentMethodCode'] as String?;
    if (code == null || code.isEmpty) return 'Belirtilmemiş';
    final name = (o['paymentMethodName'] as String?) ?? code;
    final term = o['paymentTermDays'] as int?;
    final due = TrTime.parseLocal(o['paymentDueDate'] as String?);
    return [
      name,
      if (term != null && term > 0) '$term gün',
      if (due != null) 'vade ${Fmt.date(due)}',
    ].join(' · ');
  }

  /// Ödeme yöntemi ayrıntıları (fiyatlı belgelerde).
  static List<JsonMap> paymentDetails(FakeWorld w, JsonMap o) {
    final code = o['paymentMethodCode'] as String?;
    final due = TrTime.parseLocal(o['paymentDueDate'] as String?);
    final amount = (o['estimatedAmount'] as num?)?.toDouble();
    JsonMap kv(String k, String v) => {'key': k, 'value': v};
    return switch (code) {
      'CEK' => [
        kv('Çek no', '00${4410000 + (o['id'] as int) % 1000}'),
        kv('Banka', 'Türkiye İş Bankası'),
        kv('Keşideci', w.customerTitle(o['customerId'] as int?) ?? '—'),
        if (amount != null) kv('Tutar', Fmt.money(amount)),
        if (due != null) kv('Vade', Fmt.date(due)),
      ],
      'SENET' => [
        kv('Senet no', 'SN-${o['id']}'),
        kv('Borçlu', w.customerTitle(o['customerId'] as int?) ?? '—'),
        if (due != null) kv('Vade', Fmt.date(due)),
      ],
      'DBS' => [kv('DBS bankası', 'Garanti BBVA')],
      _ => const [],
    };
  }

  /// Ödeme durumu metni (`PaymentDisplay.StatusLabel`; kapanmış siparişte bekleyen ödeme "İptal").
  static String? paymentStatusText(JsonMap o) {
    final code = o['paymentMethodCode'] as String?;
    if (code == null || code.isEmpty) return null;
    var status = o['paymentStatus'] as int? ?? 0;
    final orderStatus = o['status'] as int? ?? 0;
    if ((status == 1 || status == 2) &&
        (orderStatus == 4 || orderStatus == 6)) {
      status = 6;
    }
    return switch (status) {
      1 => 'Bekliyor',
      2 => 'Belge yüklendi',
      3 => 'Tahsil edildi',
      4 => 'Karşılıksız',
      5 => 'İade',
      6 => 'İptal',
      _ => null,
    };
  }

  /// Kabul edilen / süreçteki litreler.
  static ({double accepted, double inProcess}) liters(
    FakeWorld w,
    int orderId,
  ) {
    var accepted = 0.0;
    var process = 0.0;
    for (final s in w.shipmentsOfOrder(orderId)) {
      final st = s['status'] as int? ?? 0;
      if (st == 3) {
        accepted += (s['deliveredLiters'] as num?)?.toDouble() ?? 0;
      } else if (st == 0 || st == 1 || st == 2 || st == 4) {
        process += (s['plannedLiters'] as num?)?.toDouble() ?? 0;
      }
    }
    return (accepted: accepted, inProcess: process);
  }

  /// Seçili (onaylanan) ya da son teklif.
  static JsonMap? currentQuote(JsonMap o) {
    final quotes = ((o['quotes'] as List?) ?? const []).cast<JsonMap>();
    if (quotes.isEmpty) return null;
    for (final q in quotes) {
      if (q['isSelected'] == true) return q;
    }
    final sorted = [...quotes]
      ..sort((a, b) => (a['version'] as int).compareTo(b['version'] as int));
    return sorted.last;
  }

  /// Teklif ya da tahmini tutar.
  static double? orderAmount(JsonMap o) {
    final q = currentQuote(o);
    if (q != null) return (q['totalAmountTry'] as num?)?.toDouble();
    return null;
  }

  static int? intOf(Object? v) => v is int ? v : int.tryParse('$v');

  /// Sorgu listesi: tekrarlanan anahtarlar ve virgüllü değerler.
  static List<int> intsOf(FakeRequest req, String key) => [
    for (final raw in req.queryAll(key))
      for (final part in raw.split(',')) ?int.tryParse(part.trim()),
  ];
}
