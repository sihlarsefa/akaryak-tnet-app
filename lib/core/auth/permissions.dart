/// Sunucu yetki sabitleri (AkaryakitNet.Core/Constants). Değerleri değiştirmeyin; yalnızca ekleyin.
library;

/// Yetki kodları (`PermissionCodes`).
abstract final class Perm {
  static const view = 'Gorur';
  static const create = 'Ekler';
  static const edit = 'Duzenler';
  static const delete = 'Siler';
  static const inspect = 'Inceler';

  static const all = [view, create, edit, delete, inspect];
}

/// Sayfa kodları (`PageCodes`). `me/access` yalnızca mobil sayfaları döndürür ([mobileStationPages],
/// [mobileCustomerPages], [hoApprovals]).
abstract final class Pg {
  // Bayi
  static const stationQuoteDesk = 'StationQuoteDesk';
  static const stationQuotes = 'StationQuotes';
  static const stationOrders = 'StationOrders';
  static const stationShipments = 'StationShipments';
  static const stationShipmentBoard = 'StationShipmentBoard';
  static const stationCustomers = 'StationCustomers';
  static const stationReports = 'StationReports';
  static const stationFieldOrders = 'StationFieldOrders';
  static const stationFieldApprovals = 'StationFieldApprovals';
  static const stationPricing = 'StationPricing';
  static const stationProfitability = 'StationProfitability';
  static const stationStaff = 'StationStaff';
  static const stationRoles = 'StationRoles';
  static const stationSettings = 'StationSettings';
  static const stationApprovals = 'StationApprovals';
  static const stationFinance = 'StationFinance';
  static const stationLeads = 'StationLeads';
  static const stationPayments = 'StationPayments';

  // Müşteri
  static const customerOrders = 'CustomerOrders';
  static const customerQuotes = 'CustomerQuotes';
  static const customerCreateOrder = 'CustomerCreateOrder';
  static const customerShipments = 'CustomerShipments';
  static const customerDeliveryPoints = 'CustomerDeliveryPoints';
  static const customerReports = 'CustomerReports';
  static const customerSpending = 'CustomerSpending';
  static const customerDocuments = 'CustomerDocuments';
  static const customerCompanyUsers = 'CustomerCompanyUsers';
  static const customerOrderRequests = 'CustomerOrderRequests';
  static const customerApprovals = 'CustomerApprovals';

  // Merkez
  static const hoApprovals = 'HoApprovals';

  /// `me/access` içindeki bayi sayfaları (spec B.3).
  static const mobileStationPages = [
    stationQuoteDesk,
    stationQuotes,
    stationOrders,
    stationShipments,
    stationShipmentBoard,
    stationCustomers, //
    stationReports,
    stationFieldOrders,
    stationFieldApprovals,
    stationApprovals,
    stationFinance,
    stationLeads,
    stationPayments, stationStaff,
  ];

  /// `me/access` içindeki müşteri sayfaları (spec B.3).
  static const mobileCustomerPages = [
    customerOrders,
    customerQuotes,
    customerCreateOrder,
    customerShipments,
    customerDeliveryPoints, //
    customerReports,
    customerSpending,
    customerDocuments,
    customerCompanyUsers,
    customerOrderRequests,
    customerApprovals,
  ];
}

/// Kimlik rolleri (`Roles`).
abstract final class Roles {
  static const admin = 'Admin';
  static const headOffice = 'HeadOffice';
  static const station = 'Station';
  static const customer = 'Customer';

  /// Saha satış personeli (Station ile birlikte verilir).
  static const fieldSales = 'FieldSales';

  static const all = [admin, headOffice, station, customer, fieldSales];
}

/// Bayi rolü şablon kodları (`BayiRoleTemplateCodes`). Özel rollerde kod olmayabilir.
///
/// Roller v5: [active] 7 etkin şablon (Bayi yöneticisi, Satış müdürü, Satış temsilcisi, Finans birimi,
/// İkmal birimi, Muhasebe birimi, Şoför), [passive] 6 pasif şablon. Pasif rol yeni atamaya kapalıdır ama
/// mevcut kullanıcısına yetki vermeye devam eder: uygulama pasif kodları da tanır (ön ayar, ipucu).
abstract final class BayiRoleCodes {
  static const owner = 'owner';
  static const manager = 'manager';
  static const financeManager = 'finance_manager';
  static const financeSpecialist = 'finance_specialist';
  static const accounting = 'accounting';
  static const salesManager = 'sales_manager';
  static const fieldRep = 'field_rep';
  static const orderDesk = 'order_desk';
  static const dispatch = 'dispatch';
  static const driver = 'driver';
  static const depot = 'depot';
  static const viewer = 'viewer';

  /// Roller v5: İkmal birimi (Sipariş masası, Sevkiyat planlama ve Depo / dolum şablonlarının birleşimi).
  static const supply = 'supply';

  /// Tüm kodlar. Sıra sahte personel listesinin `roleId` değerini verir: yalnızca sona ekleyin.
  static const all = [
    owner,
    manager,
    financeManager,
    financeSpecialist,
    accounting,
    salesManager, //
    fieldRep, orderDesk, dispatch, driver, depot, viewer, supply,
  ];

  /// Roller v5 etkin şablonları (7; panelin sırasıyla).
  static const active = [
    owner,
    salesManager,
    fieldRep,
    financeManager,
    supply,
    accounting,
    driver,
  ];

  /// Roller v5 pasif şablonları (6): yeni atamaya kapalı; mevcut atamalar çalışmaya devam eder.
  static const passive = [
    manager,
    financeSpecialist,
    orderDesk,
    dispatch,
    depot,
    viewer,
  ];

  /// Pasif rolün ad eki (sunucu `BayiRoleDisplay.RetiredSuffix`).
  static const passiveSuffix = ' (pasif)';

  /// Pasif şablon kodu mu.
  static bool isPassive(String? code) => passive.contains(code);

  /// Pasif şablonun kullanıcılarının taşındığı etkin şablon (sunucu `ReplacedBy`): Bayi müdürü → Bayi
  /// yöneticisi, Finans / kredi uzmanı → Finans birimi, Sipariş masası / Sevkiyat / Depo → İkmal birimi.
  /// Görüntüleyicide ve etkin kodlarda null.
  static String? replacedBy(String? code) => switch (code) {
    manager => owner,
    financeSpecialist => financeManager,
    orderDesk || dispatch || depot => supply,
    _ => null,
  };

  /// Şablonun Türkçe adı, sunucunun adıyla aynı (bilinmeyen kod olduğu gibi döner). Pasif şablonlar eski
  /// adlarını korur.
  static String name(String code) => switch (code) {
    owner => 'Bayi yöneticisi',
    manager => 'Bayi müdürü',
    financeManager => 'Finans birimi',
    financeSpecialist => 'Finans / kredi uzmanı',
    accounting => 'Muhasebe birimi',
    salesManager => 'Satış müdürü',
    fieldRep => 'Satış temsilcisi',
    orderDesk => 'Sipariş masası / operasyon',
    dispatch => 'Sevkiyat planlama',
    driver => 'Şoför',
    depot => 'Depo / dolum',
    viewer => 'Görüntüleyici',
    supply => 'İkmal birimi',
    _ => code,
  };

  /// Rolün ekran etiketi (sunucu `BayiRoleDisplay.Label`): pasif rolde ad + " (pasif)"; ek iki kez
  /// eklenmez.
  static String label(String name, {required bool passive}) =>
      passive && !name.endsWith(passiveSuffix) ? '$name$passiveSuffix' : name;
}

/// Roller v5 "her birimde 1 onaycı": onay akışı olan bayi birimleri (`BayiApproverUnits`). Birimin etkin
/// onaycısı varsa birimin `approve.*` kodlarıyla bayide yalnızca o imzalar (`me/access`
/// `signingCapabilities`); onaycı yoksa yetkinliği olan herkes imzalar. İkmal ve Muhasebe biriminin onay
/// akışı yoktur.
abstract final class ApproverUnits {
  static const management = 'management';
  static const sales = 'sales';
  static const finance = 'finance';

  /// Panelin "Birim onaycıları" sırası.
  static const all = [management, sales, finance];

  /// Kısa ad: Ekip'teki "Onaycı · Finans" çipi (sunucu `ShortLabel`).
  static String shortLabel(String unit) => switch (unit) {
    management => 'Bayi yöneticisi',
    sales => 'Satış',
    finance => 'Finans',
    _ => unit,
  };

  /// Panel adı (sunucu `Label`): "Finans birimi onaycısı".
  static String label(String unit) => switch (unit) {
    management => 'Bayi yöneticisi onaycısı',
    sales => 'Satış onaycısı',
    finance => 'Finans birimi onaycısı',
    _ => unit,
  };

  /// Birimin imza yetkinlikleri (sunucu `CapabilitiesOf`).
  static List<String> capabilitiesOf(String unit) => switch (unit) {
    management => const [
      Caps.approveFieldSenior,
      Caps.approveFieldException,
      Caps.approveOrderExecutive,
    ],
    sales => const [Caps.approveFieldManager],
    finance => const [
      Caps.approveFinanceOrder,
      Caps.approveFinanceOnboarding,
      Caps.approveFinanceLead,
    ],
    _ => const [],
  };

  /// Rol satırı: birim onaycısında rolün ardından " · onaycı" (Profil ve "Diğer": "Finans birimi ·
  /// onaycı").
  static String roleLine(String role, List<String> units) =>
      units.isEmpty ? role : '$role · onaycı';

  /// Yetkinliğin birimi (sunucu `UnitOf`); merkez (`approve.limit.hq`, `approve.hq`), cari
  /// (`approve.company.order`) ve onay dışı kodlarda null.
  static String? unitOf(String? capability) {
    for (final u in all) {
      if (capabilitiesOf(u).contains(capability)) return u;
    }
    return null;
  }
}

/// Bayi rolü yetkinlik kodları (`BayiCapabilities`). Platform personeli her yetkinliğe sahiptir.
abstract final class Caps {
  static const approveFieldManager = 'approve.field.manager';
  static const approveFieldSenior = 'approve.field.senior';
  static const approveFieldException = 'approve.field.exception';
  static const approveFinanceOrder = 'approve.finance.order';
  static const approveFinanceOnboarding = 'approve.finance.onboarding';
  static const approveFinanceLead = 'approve.finance.lead';
  static const approveOrderExecutive = 'approve.order.executive';
  static const approveLimitHq = 'approve.limit.hq';
  static const approveCompanyOrder = 'approve.company.order';
  static const approveHq = 'approve.hq';

  static const financeRiskReportPull = 'finance.riskreport.pull';
  static const financeProfileEdit = 'finance.profile.edit';
  static const financeRulesEdit = 'finance.rules.edit';

  static const paymentStatusUpdate = 'payment.status.update';
  static const paymentInstrumentManage = 'payment.instrument.manage';

  static const costsView = 'costs.view';
  static const staffManage = 'staff.manage';
  static const rolesManage = 'roles.manage';

  static const leadCreate = 'lead.create';
  static const leadViewAll = 'lead.viewAll';
  static const fieldStrategicFlag = 'field.strategic.flag';

  static const approvalsChainEdit = 'approvals.chain.edit';
  static const approvalsDelegate = 'approvals.delegate';

  static const shipmentAssign = 'shipment.assign';

  /// Yalnızca kendi sevkiyatları (şoför).
  static const shipmentOwnOnly = 'shipment.ownOnly';
  static const loadingRecord = 'loading.record';

  static const all = [
    approveFieldManager,
    approveFieldSenior,
    approveFieldException,
    approveFinanceOrder,
    approveFinanceOnboarding, //
    approveFinanceLead,
    approveOrderExecutive,
    approveLimitHq,
    approveCompanyOrder,
    approveHq,
    financeRiskReportPull,
    financeProfileEdit,
    financeRulesEdit,
    paymentStatusUpdate,
    paymentInstrumentManage,
    costsView,
    staffManage,
    rolesManage,
    leadCreate,
    leadViewAll,
    fieldStrategicFlag,
    approvalsChainEdit,
    approvalsDelegate, shipmentAssign, shipmentOwnOnly, loadingRecord,
  ];

  /// Bayi rolüne verilebilenler (merkez / cari kodları hariç).
  static const bayiAssignable = [
    approveFieldManager,
    approveFieldSenior,
    approveFieldException,
    approveFinanceOrder,
    approveFinanceOnboarding, //
    approveFinanceLead,
    approveOrderExecutive,
    financeRiskReportPull,
    financeProfileEdit,
    financeRulesEdit,
    paymentStatusUpdate,
    paymentInstrumentManage,
    costsView,
    staffManage,
    rolesManage,
    leadCreate,
    leadViewAll,
    fieldStrategicFlag,
    approvalsChainEdit,
    approvalsDelegate,
    shipmentAssign,
    shipmentOwnOnly,
    loadingRecord,
  ];
}
