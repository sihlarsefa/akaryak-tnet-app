import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/access_policy.dart';
import '../auth/permissions.dart';
import '../models/app_config.dart';
import '../models/enums.dart';
import 'app_routes.dart';

/// Rota erişim kuralı.
class _Rule {
  const _Rule(this.prefix, this.allowed);
  final String prefix;
  final bool Function(AccessPolicy p, AppFeatures f) allowed;

  bool matches(String path) => path == prefix || path.startsWith('$prefix/');
}

/// Hangi rotayı kim açabilir (derin bağlantı, push yönlendirmesi, özellikler arası bağlantılar; spec C.4).
/// Sunucu ayrıca denetler. İzin verilmeyen push rotası `/notifications`'a düşer. Kurallar sırayla denenir;
/// ilk eşleşen karar verir (özel önekler genel olanlardan önce).
abstract final class RouteAccess {
  static final _rules = <_Rule>[
    // ---------------------------------------------------------------- Müşteri
    _Rule(
      AppRoutes.orderNew,
      (p, f) => p.isCustomer && p.can(Pg.customerCreateOrder, Perm.create),
    ),
    _Rule(
      AppRoutes.orders,
      (p, f) =>
          p.isCustomer &&
          p.canAny(const [Pg.customerOrders, Pg.customerQuotes]),
    ),
    _Rule(
      AppRoutes.shipments,
      (p, f) =>
          p.isCustomer &&
          p.canAny(const [Pg.customerShipments, Pg.customerOrders]),
    ),
    _Rule(
      AppRoutes.companyUsers,
      (p, f) =>
          p.isCustomer &&
          p.customerRole == CustomerUserRole.admin &&
          p.can(Pg.customerCompanyUsers),
    ),
    _Rule(
      AppRoutes.companyRequests,
      (p, f) => p.isCustomer && p.can(Pg.customerOrderRequests),
    ),
    _Rule(
      AppRoutes.financeInfo,
      (p, f) =>
          p.isCustomer &&
          p.canAny(const [Pg.customerCreateOrder, Pg.customerOrders]),
    ),
    _Rule(
      AppRoutes.documents,
      (p, f) => p.isCustomer && p.can(Pg.customerDocuments),
    ),
    _Rule(
      AppRoutes.spending,
      (p, f) => p.isCustomer && p.can(Pg.customerSpending),
    ),
    _Rule(
      AppRoutes.deliveryPoints,
      (p, f) => p.isCustomer && p.can(Pg.customerDeliveryPoints),
    ),
    _Rule(
      AppRoutes.templates,
      (p, f) => p.isCustomer && p.can(Pg.customerCreateOrder),
    ),
    _Rule(AppRoutes.limits, (p, f) => p.isCustomer),

    // ---------------------------------------------------------------- Bayi
    _Rule(
      AppRoutes.bayiStaff,
      (p, f) => p.isBayi && !p.isFieldSales && p.can(Pg.stationStaff),
    ),
    _Rule(AppRoutes.bayiOrders, (p, f) => p.isBayi && p.can(Pg.stationOrders)),
    _Rule(
      AppRoutes.quoteDesk,
      (p, f) => p.isBayi && p.can(Pg.stationQuoteDesk),
    ),
    _Rule(
      AppRoutes.customers,
      (p, f) => p.isBayi && (p.can(Pg.stationCustomers) || p.isFieldSales),
    ),
    _Rule(
      AppRoutes.dispatch,
      (p, f) => p.isBayi && p.can(Pg.stationShipmentBoard),
    ),
    // Teslimatlarım: şoför, kendisine teslimat atanmış personel ya da sevkiyat görebilen bayi personeli
    // (`/driver/**`; liste yalnızca kullanıcının kendi teslimatlarını gösterir).
    _Rule(
      AppRoutes.driver,
      (p, f) => p.isBayi && (p.canSeeDeliveries || p.can(Pg.stationShipments)),
    ),

    // ---------------------------------------------------------------- Onay, finans, tahsilat
    _Rule(
      AppRoutes.approvals,
      (p, f) =>
          p.isPlatform ||
          p.isCustomer ||
          p.canAny(const [Pg.stationApprovals, Pg.customerApprovals]),
    ),
    _Rule(AppRoutes.finance, (p, f) => p.isBayi && p.can(Pg.stationFinance)),
    _Rule(AppRoutes.payments, (p, f) => p.isBayi && p.can(Pg.stationPayments)),

    // ---------------------------------------------------------------- Saha
    _Rule(
      AppRoutes.fieldFormNew,
      (p, f) => p.isBayi && p.can(Pg.stationFieldOrders, Perm.create),
    ),
    _Rule(
      AppRoutes.fieldLeadNew,
      (p, f) => p.isBayi && p.can(Pg.stationLeads, Perm.create),
    ),
    _Rule(
      AppRoutes.field,
      (p, f) =>
          p.isBayi && p.canAny(const [Pg.stationFieldOrders, Pg.stationLeads]),
    ),

    // ---------------------------------------------------------------- Ortak
    _Rule(AppRoutes.assistant, (p, f) => f.assistant),
    _Rule(AppRoutes.stats, (p, f) => statsAudience(p)),
  ];

  /// İstatistikler (`/stats`) ve ana sayfadaki yönetici destesi kimde görünür (spec R1 §3.1; özellik
  /// `features/stats` kapsamı bundan türetir, sunucu ayrıca denetler):
  /// - müşteri: harcama raporu yetkisi + şirket rolü Yönetici ya da Onaylayan (talep eden görmez),
  /// - saha satış: kendi portföyü,
  /// - bayi: rapor yetkisi olan yönetim rolleri; operasyon ekranları (sipariş masası, sevkiyat / depo,
  ///   yalnızca şoför) görmez.
  static bool statsAudience(AccessPolicy p) {
    if (p.isCustomer) {
      return p.can(Pg.customerSpending) && p.customerRole.canApprove;
    }
    if (!p.isBayi) return false;
    if (p.isFieldSales) return true;
    if (p.isDriverOnly) return false;
    if (p.rolePreset == RolePreset.orderDesk ||
        p.rolePreset == RolePreset.dispatch) {
      return false;
    }
    return p.can(Pg.stationReports);
  }

  /// Merkez kullanıcısının açabileceği rotalar (Onaylarım · Bildirimler · Profil).
  static const _platformPrefixes = [
    AppRoutes.home,
    AppRoutes.approvals,
    AppRoutes.notifications,
    AppRoutes.profile,
  ];

  /// [location] (`/orders/12?x=1`) bu kullanıcıya açık mı. Kuralı olmayan rota açıktır (Ana sayfa,
  /// Bildirimler, Profil).
  static bool isAllowed(
    String location,
    AccessPolicy policy,
    AppFeatures features,
  ) {
    final path = Uri.tryParse(location)?.path ?? location;
    if (policy.isPlatform) {
      return _platformPrefixes.any((p) => path == p || path.startsWith('$p/'));
    }
    for (final r in _rules) {
      if (r.matches(path)) return r.allowed(policy, features);
    }
    return true;
  }

  /// Push rotasını doğrular: izin yoksa ya da rota boşsa `/notifications`.
  static String resolvePushRoute(
    String? route,
    AccessPolicy policy,
    AppFeatures features,
  ) {
    final r = sanitizePushRoute(route);
    return isAllowed(r, policy, features) ? r : AppRoutes.notifications;
  }

  /// Push rotasının biçimi (yetki denetimi yok): boş ya da göreli rota `/notifications`.
  static String sanitizePushRoute(String? route) {
    final r = route?.trim();
    if (r == null || r.isEmpty || !r.startsWith('/')) {
      return AppRoutes.notifications;
    }
    return r;
  }
}

/// Bekleyen derin bağlantı (push dokunuşu, oturum açılmadan gelen bağlantı). Kabuk hazır olunca
/// uygulama katmanı alır ve gider.
final pendingDeepLinkProvider = NotifierProvider<PendingDeepLink, String?>(
  PendingDeepLink.new,
);

class PendingDeepLink extends Notifier<String?> {
  bool _fromPush = false;

  @override
  String? build() => null;

  /// Bekleyen bağlantı, oturum açılmadan dokunulan bir push'tan: yetki oturum açılınca denetlenir,
  /// izin yoksa `/notifications` açılır (spec C.4).
  bool get fromPush => _fromPush && state != null;

  void set(String? location, {bool fromPush = false}) {
    _fromPush = location != null && fromPush;
    state = location;
  }

  /// Bağlantıyı alır ve temizler.
  String? take() {
    final l = state;
    _fromPush = false;
    state = null;
    return l;
  }
}
