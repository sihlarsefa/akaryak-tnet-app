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

  static const all = [
    owner,
    manager,
    financeManager,
    financeSpecialist,
    accounting,
    salesManager, //
    fieldRep, orderDesk, dispatch, driver, depot, viewer,
  ];

  /// Şablonun Türkçe adı (bilinmeyen kod olduğu gibi döner).
  static String name(String code) => switch (code) {
    owner => 'Bayi sahibi',
    manager => 'Bayi müdürü',
    financeManager => 'Finans müdürü',
    financeSpecialist => 'Finans / kredi uzmanı',
    accounting => 'Muhasebe',
    salesManager => 'Satış müdürü',
    fieldRep => 'Saha satış temsilcisi',
    orderDesk => 'Sipariş masası / operasyon',
    dispatch => 'Sevkiyat planlama',
    driver => 'Şoför',
    depot => 'Depo / dolum',
    viewer => 'Görüntüleyici',
    _ => code,
  };
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
