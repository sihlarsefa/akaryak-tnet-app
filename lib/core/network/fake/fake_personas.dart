import '../../auth/permissions.dart';
import '../../models/json.dart';
import '../../models/me_access.dart';
import '../../utils/turkish_text.dart';

/// Sahte kipte giriş yapılabilen demo kullanıcı (spec D.3 M0a). Yalnızca sahte kip: şifre `demo`,
/// SMS kodu `123456`. Kullanıcı adı = anahtar (`musteri`, `sofor` …).
class FakePersona {
  const FakePersona({
    required this.key,
    required this.displayName,
    required this.phone,
    required this.persona,
    required this.roles,
    required this.summary,
    required this.pages,
    this.stationId,
    this.customerId,
    this.customerUserRole,
    this.bayiRoleCodes = const [],
    this.roleNames,
    this.capabilities = const {},
    this.requiresTwoFactor = false,
  });

  /// Giriş adı ve dev menüsü anahtarı.
  final String key;
  final String displayName;

  /// 10 haneli cep telefonu (5XXXXXXXXX): "Telefonla giriş".
  final String phone;
  final Persona persona;
  final List<String> roles;

  /// Dev menüsünde gösterilen kısa açıklama.
  final String summary;

  /// `"Page:Perm"`.
  final Set<String> pages;
  final int? stationId;
  final int? customerId;

  /// 1 Talep eden, 2 Onaylayan, 3 Yönetici.
  final int? customerUserRole;
  final List<String> bayiRoleCodes;

  /// Özel rol adları (şablonsuz rol `role:{Id}` kodu taşır; adı bayi verir).
  final List<String>? roleNames;

  /// Yetkinlik → tutar sınırı (null = sınırsız).
  final Map<String, double?> capabilities;

  /// Şifreden sonra SMS kodu ister (merkez).
  final bool requiresTwoFactor;

  String get userId => 'u-$key';
  String get userName => key;
  String get email => '$key@demo.akaryakitnet.local';

  /// `0532 *** ** 01`.
  String get phoneMasked =>
      '0${phone.substring(0, 3)} *** ** ${phone.substring(8)}';

  bool can(String page, [String perm = Perm.view]) =>
      pages.contains('$page:$perm');

  bool hasCap(String code) =>
      persona == Persona.platform || capabilities.containsKey(code);

  List<String> get bayiRoleNames =>
      roleNames ?? [for (final c in bayiRoleCodes) BayiRoleCodes.name(c)];

  /// `GET me/access` gövdesi.
  JsonMap meAccessJson({
    String? stationTitle,
    String? customerTitle,
    String accessVersion = '1',
  }) => {
    'userId': userId,
    'userName': userName,
    'displayName': displayName,
    'email': email,
    'phoneMasked': phoneMasked,
    'persona': persona.code,
    'roles': roles,
    'stationId': stationId,
    'stationTitle': stationTitle,
    'customerId': customerId,
    'customerTitle': customerTitle,
    'customerUserRole': customerUserRole,
    'bayiRoleCodes': bayiRoleCodes,
    'bayiRoleNames': bayiRoleNames,
    'pages': pages.toList()..sort(),
    'capabilities': [
      for (final e in capabilities.entries) {'code': e.key, 'limit': e.value},
    ],
    'delegations': const <Object>[],
    'accessVersion': accessVersion,
  };
}

/// Bayi rolü şablonlarının sayfa harfleri (sunucu `BayiRoleTemplates.cs` ile aynı):
/// G Görür · E Ekler · D Düzenler · S Siler · I İnceler · T hepsi.
abstract final class FakeRoleTemplates {
  static const stationPages = [
    Pg.stationQuoteDesk,
    Pg.stationQuotes,
    Pg.stationOrders,
    Pg.stationShipments,
    Pg.stationShipmentBoard, //
    Pg.stationCustomers,
    Pg.stationReports,
    Pg.stationFieldOrders,
    Pg.stationFieldApprovals,
    Pg.stationPricing,
    Pg.stationProfitability,
    Pg.stationStaff,
    Pg.stationRoles,
    Pg.stationSettings,
    Pg.stationApprovals,
    Pg.stationFinance, Pg.stationLeads, Pg.stationPayments,
  ];

  static Map<String, String> _every(
    String letters, {
    List<String> except = const [],
  }) => {
    for (final p in stationPages)
      if (!except.contains(p)) p: letters,
  };

  static final Map<String, Map<String, String>> pages = {
    BayiRoleCodes.owner: _every('T'),
    BayiRoleCodes.manager: {
      ..._every('T'),
      Pg.stationRoles: 'G',
      Pg.stationStaff: 'G',
      Pg.stationSettings: 'GD',
      Pg.stationFieldApprovals: 'GDI',
      Pg.stationFinance: 'G',
      Pg.stationLeads: 'G',
      Pg.stationPayments: 'G',
    },
    BayiRoleCodes.financeManager: {
      Pg.stationFinance: 'T',
      Pg.stationPayments: 'GDI',
      Pg.stationApprovals: 'T',
      Pg.stationCustomers: 'GDI', //
      Pg.stationOrders: 'G',
      Pg.stationQuotes: 'G',
      Pg.stationReports: 'G',
      Pg.stationQuoteDesk: 'G',
      Pg.stationPricing: 'G',
      Pg.stationProfitability: 'G',
      Pg.stationFieldApprovals: 'GD',
      Pg.stationLeads: 'GI',
      Pg.stationSettings: 'G',
    },
    BayiRoleCodes.financeSpecialist: {
      Pg.stationFinance: 'GEDI',
      Pg.stationApprovals: 'GE',
      Pg.stationCustomers: 'GI',
      Pg.stationOrders: 'G', //
      Pg.stationQuotes: 'G',
      Pg.stationReports: 'G',
      Pg.stationLeads: 'GI',
      Pg.stationPayments: 'G',
    },
    BayiRoleCodes.accounting: {
      Pg.stationPayments: 'T',
      Pg.stationOrders: 'GI',
      Pg.stationQuotes: 'G',
      Pg.stationCustomers: 'G', //
      Pg.stationReports: 'G', Pg.stationFinance: 'G', Pg.stationApprovals: 'G',
    },
    BayiRoleCodes.salesManager: {
      Pg.stationFieldOrders: 'T',
      Pg.stationFieldApprovals: 'GD',
      Pg.stationCustomers: 'GDI',
      Pg.stationLeads: 'T', //
      Pg.stationApprovals: 'GE',
      Pg.stationOrders: 'G',
      Pg.stationQuotes: 'G',
      Pg.stationReports: 'G',
      Pg.stationProfitability: 'G',
      Pg.stationPricing: 'G',
      Pg.stationStaff: 'G',
    },
    BayiRoleCodes.fieldRep: {
      Pg.stationFieldOrders: 'GED',
      Pg.stationLeads: 'GED',
      Pg.stationApprovals: 'G',
    },
    BayiRoleCodes.orderDesk: {
      Pg.stationQuoteDesk: 'T',
      Pg.stationQuotes: 'T',
      Pg.stationOrders: 'T',
      Pg.stationCustomers: 'G', //
      Pg.stationShipments: 'G',
      Pg.stationShipmentBoard: 'G',
      Pg.stationReports: 'G',
      Pg.stationApprovals: 'G',
      Pg.stationPayments: 'G',
    },
    BayiRoleCodes.dispatch: {
      Pg.stationShipmentBoard: 'T',
      Pg.stationShipments: 'T',
      Pg.stationOrders: 'G',
      Pg.stationCustomers: 'G',
    },
    BayiRoleCodes.driver: {Pg.stationShipments: 'GD'},
    BayiRoleCodes.depot: {
      Pg.stationShipments: 'GD',
      Pg.stationShipmentBoard: 'G',
      Pg.stationOrders: 'G',
    },
    BayiRoleCodes.viewer: _every(
      'G',
      except: const [
        Pg.stationPricing,
        Pg.stationProfitability,
        Pg.stationStaff,
        Pg.stationRoles,
        Pg.stationSettings, //
        Pg.stationFinance, Pg.stationPayments,
      ],
    ),
  };

  static List<String> _perms(String letters) {
    if (letters == 'T') return Perm.all;
    return [
      for (final p in Perm.all)
        if (letters.contains(_letter[p]!)) p,
    ];
  }

  static const _letter = {
    Perm.view: 'G',
    Perm.create: 'E',
    Perm.edit: 'D',
    Perm.delete: 'S',
    Perm.inspect: 'I',
  };

  /// Rol şablonlarının mobil sayfa yetkileri (birleşim). Sunucu `me/access` yalnızca mobil sayfaları döndürür.
  static Set<String> grants(List<String> roleCodes) {
    final out = <String>{};
    for (final code in roleCodes) {
      final map = pages[code] ?? const {};
      map.forEach((page, letters) {
        if (!Pg.mobileStationPages.contains(page)) return;
        for (final perm in _perms(letters)) {
          out.add('$page:$perm');
        }
      });
    }
    return out;
  }

  /// Müşteri operasyon grubu: tüm müşteri sayfaları × Görür/Ekler/Düzenler.
  static Set<String> customerGrants() => {
    for (final page in Pg.mobileCustomerPages)
      for (final perm in const [Perm.view, Perm.create, Perm.edit])
        '$page:$perm',
  };

  /// Platform: her şey (sunucuda HasAsync platforma her zaman true döner) + HoApprovals.
  static Set<String> platformGrants() => {
    for (final page in [...Pg.mobileStationPages, ...Pg.mobileCustomerPages])
      for (final perm in Perm.all) '$page:$perm',
    '${Pg.hoApprovals}:${Perm.view}',
  };

  static final Map<String, Map<String, double?>> capabilities = {
    BayiRoleCodes.owner: {
      for (final c in Caps.bayiAssignable)
        if (c != Caps.shipmentOwnOnly && c != Caps.leadCreate) c: null,
    },
    BayiRoleCodes.manager: {
      Caps.approveFieldManager: null,
      Caps.approveFieldSenior: null,
      Caps.approveFinanceOrder: null, //
      Caps.approveOrderExecutive: null,
      Caps.costsView: null,
      Caps.leadViewAll: null,
      Caps.fieldStrategicFlag: null,
      Caps.approvalsDelegate: null,
    },
    BayiRoleCodes.financeManager: {
      Caps.approveFinanceOrder: null,
      Caps.approveFinanceOnboarding: null,
      Caps.approveFinanceLead: null, //
      Caps.approveFieldSenior: null,
      Caps.financeRiskReportPull: null,
      Caps.financeProfileEdit: null,
      Caps.financeRulesEdit: null,
      Caps.approvalsChainEdit: null,
      Caps.approvalsDelegate: null,
      Caps.costsView: null,
      Caps.leadViewAll: null,
    },
    BayiRoleCodes.financeSpecialist: {
      Caps.approveFinanceOrder: 1000000,
      Caps.approveFinanceOnboarding: 1000000,
      Caps.approveFinanceLead: 1000000, //
      Caps.financeRiskReportPull: null,
      Caps.financeProfileEdit: null,
      Caps.leadViewAll: null,
    },
    BayiRoleCodes.accounting: {
      Caps.paymentStatusUpdate: null,
      Caps.paymentInstrumentManage: null,
    },
    BayiRoleCodes.salesManager: {
      Caps.approveFieldManager: null,
      Caps.costsView: null,
      Caps.leadViewAll: null,
    },
    BayiRoleCodes.fieldRep: {Caps.leadCreate: null},
    BayiRoleCodes.orderDesk: {},
    BayiRoleCodes.dispatch: {Caps.shipmentAssign: null},
    BayiRoleCodes.driver: {Caps.shipmentOwnOnly: null},
    BayiRoleCodes.depot: {Caps.loadingRecord: null},
    BayiRoleCodes.viewer: {},
  };
}

/// Bayi personeli.
FakePersona _bayi(
  String key,
  String name,
  String phone,
  String role,
  String summary, {
  List<String> roles = const [Roles.station],
}) => FakePersona(
  key: key,
  displayName: name,
  phone: phone,
  persona: Persona.bayi,
  roles: roles,
  summary: summary,
  stationId: 1,
  bayiRoleCodes: [role],
  pages: FakeRoleTemplates.grants([role]),
  capabilities: FakeRoleTemplates.capabilities[role] ?? const {},
);

/// Müşteri (cari) şirket kullanıcısı.
FakePersona _customer(
  String key,
  String name,
  String phone,
  int companyRole,
  String summary,
) => FakePersona(
  key: key,
  displayName: name,
  phone: phone,
  persona: Persona.customer,
  roles: const [Roles.customer],
  summary: summary,
  customerId: 101,
  customerUserRole: companyRole,
  // Yönetici teslimat noktasını pasifleştirebilir (demo: "Pasifleştir" görünür).
  pages: {
    ...FakeRoleTemplates.customerGrants(),
    if (companyRole == 3) '${Pg.customerDeliveryPoints}:${Perm.delete}',
  },
  capabilities: companyRole >= 2
      ? const {Caps.approveCompanyOrder: null}
      : const {},
);

/// Sahte kipteki tüm demo kullanıcılar (spec D.3'teki 14 persona + merkez + A-INT'in finans uzmanı ve
/// özel rolü).
final List<FakePersona> fakePersonas = List.unmodifiable([
  _customer(
    'musteri',
    'Selin Aydın',
    '5320000101',
    3,
    'Müşteri · şirket yöneticisi',
  ),
  _customer(
    'talep',
    'Burak Yılmaz',
    '5320000102',
    1,
    'Müşteri · talep eden (şirket içi onaya düşer)',
  ),
  _customer('onay', 'Elif Demir', '5320000103', 2, 'Müşteri · onaylayan'),
  _bayi(
    'sahip',
    'Mehmet Demir',
    '5320000201',
    BayiRoleCodes.owner,
    'Bayi sahibi',
  ),
  _bayi(
    'mudur',
    'Ayşe Kaya',
    '5320000202',
    BayiRoleCodes.manager,
    'Bayi müdürü',
  ),
  _bayi(
    'finans',
    'Can Öztürk',
    '5320000203',
    BayiRoleCodes.financeManager,
    'Finans müdürü',
  ),
  _bayi(
    'muhasebe',
    'Zeynep Arslan',
    '5320000204',
    BayiRoleCodes.accounting,
    'Muhasebe / tahsilat',
  ),
  _bayi(
    'satis',
    'Emre Çelik',
    '5320000205',
    BayiRoleCodes.salesManager,
    'Satış müdürü',
  ),
  _bayi(
    'saha',
    'Deniz Koç',
    '5320000206',
    BayiRoleCodes.fieldRep,
    'Saha satış temsilcisi',
    roles: const [Roles.station, Roles.fieldSales],
  ),
  _bayi(
    'siparis',
    'Gizem Şahin',
    '5320000207',
    BayiRoleCodes.orderDesk,
    'Sipariş masası',
  ),
  _bayi(
    'sevkiyat',
    'Okan Yıldız',
    '5320000208',
    BayiRoleCodes.dispatch,
    'Sevkiyat planlama',
  ),
  _bayi(
    'sofor',
    'Ahmet Kurt',
    '5320000209',
    BayiRoleCodes.driver,
    'Şoför (yalnızca kendi teslimatları)',
  ),
  _bayi(
    'depo',
    'Hakan Aksoy',
    '5320000210',
    BayiRoleCodes.depot,
    'Depo / dolum',
  ),
  _bayi(
    'izleyici',
    'Ece Tunç',
    '5320000211',
    BayiRoleCodes.viewer,
    'Görüntüleyici (salt okunur)',
  ),
  // A-INT ek personaları (spec D.7.5): onay sınırı aşılan finans uzmanı ve şablonsuz özel rol.
  _bayi(
    'finansuzman',
    'Seda Yılmaz',
    '5320000212',
    BayiRoleCodes.financeSpecialist,
    'Finans uzmanı (1.000.000 ₺ onay sınırı; üstü "Tutar onay sınırınızı aşıyor")',
  ),
  const FakePersona(
    key: 'ozelrol',
    displayName: 'Kemal Aydın',
    phone: '5320000213',
    persona: Persona.bayi,
    roles: [Roles.station],
    summary: 'Özel rol "Bölge sorumlusu" (şablonsuz: sipariş, sevkiyat, cari)',
    stationId: 1,
    bayiRoleCodes: ['role:42'],
    roleNames: ['Bölge sorumlusu'],
    pages: {
      'StationOrders:Gorur',
      'StationQuotes:Gorur',
      'StationShipments:Gorur',
      'StationShipments:Duzenler',
      'StationShipmentBoard:Gorur',
      'StationCustomers:Gorur',
      'StationReports:Gorur',
      'StationApprovals:Gorur',
    },
  ),
  FakePersona(
    key: 'merkez',
    displayName: 'Merkez Operasyon',
    phone: '5320000301',
    persona: Persona.platform,
    roles: const [Roles.headOffice],
    summary: 'Merkez (şifre + SMS kodu)',
    pages: FakeRoleTemplates.platformGrants(),
    capabilities: {for (final c in Caps.all) c: null},
    requiresTwoFactor: true,
  ),
]);

/// Anahtar, kullanıcı adı, e-posta ya da kullanıcı kimliğiyle persona bulur.
FakePersona? findFakePersona(String? keyOrEmail) {
  final k = keyOrEmail?.trim().asciiLower;
  if (k == null || k.isEmpty) return null;
  for (final p in fakePersonas) {
    if (p.key == k || p.email == k || p.userId == k) return p;
  }
  return null;
}
