/// Uygulama rotaları (spec C.4 derin bağlantı sözleşmesi, B2 ile ortak). Özellikler arası gezinme
/// yalnızca bu yollarla yapılır: `context.push(AppRoutes.order(12))`.
abstract final class AppRoutes {
  // Açılış ve kimlik
  static const splash = '/splash';
  static const update = '/update';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const loginCode = '/login/code';
  static const locked = '/locked';

  // Ortak
  static const home = '/home';
  static const notifications = '/notifications';
  static const assistant = '/assistant';
  static const profile = '/profile';

  /// Telefon doğrulama (Profil > Güvenlik "Telefonla girişi etkinleştir").
  static const profilePhone = '/profile/phone';

  /// İstatistikler (yönetici destesi kitlesi: bayi yöneticileri, saha temsilcisi, müşteri
  /// yönetici / onaylayan). `?period=month|lastMonth|quarter|year`.
  static const stats = '/stats';

  // Müşteri
  static const orders = '/orders';
  static const orderNew = '/orders/new';
  static String order(int id) => '/orders/$id';
  static const shipments = '/shipments';
  static String shipment(int id) => '/shipments/$id';
  static const companyRequests = '/company/requests';
  static String companyRequest(int id) => '/company/requests/$id';
  static const financeInfo = '/finance-info';
  static const documents = '/documents';
  static const spending = '/spending';
  static const deliveryPoints = '/delivery-points';
  static const templates = '/templates';
  static const limits = '/limits';
  static const companyUsers = '/company/users';

  /// Yeni sipariş: şablondan (`fromTemplate`), şirket içi talepten (`fromRequest`) ya da tekrar (`reorder`).
  static String orderNewFrom({int? template, int? request, int? reorder}) {
    final q = <String, String>{
      if (template != null) 'fromTemplate': '$template',
      if (request != null) 'fromRequest': '$request',
      if (reorder != null) 'reorder': '$reorder',
    };
    return Uri(
      path: orderNew,
      queryParameters: q.isEmpty ? null : q,
    ).toString();
  }

  // Bayi
  static const quoteDesk = '/quote-desk';
  static const bayiOrders = '/bayi/orders';
  static String bayiOrder(int id) => '/bayi/orders/$id';
  static const customers = '/customers';
  static String customer(int id) => '/customers/$id';
  static const dispatch = '/dispatch';

  /// Ekip (bayi personeli).
  static const bayiStaff = '/bayi/staff';

  // Şoför
  static const driver = '/driver';
  static String driverShipment(int id) => '/driver/shipments/$id';

  // Onay, finans, tahsilat
  static const approvals = '/approvals';
  static String approval(int id) => '/approvals/$id';
  static const finance = '/finance';
  static String financeCustomer(int stationCustomerId) =>
      '/finance/customers/$stationCustomerId';
  static const payments = '/payments';
  static String payment(int orderId) => '/payments/$orderId';

  // Saha
  static const field = '/field';
  static const fieldFormNew = '/field/forms/new';
  static String fieldForm(int id) => '/field/forms/$id';
  static const fieldLeadNew = '/field/leads/new';
  static String fieldLead(int id) => '/field/leads/$id';

  // Geliştirme (yalnızca dev ortamı)
  static const dev = '/dev';
  static const devGallery = '/dev/gallery';

  /// Oturum gerektirmeyen rotalar.
  static const publicRoutes = {splash, update, onboarding, login, loginCode};
}
