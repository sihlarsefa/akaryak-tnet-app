import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/auth/access_policy.dart';
import '../core/auth/permissions.dart';
import '../core/auth/session_controller.dart';
import '../core/models/app_config.dart';
import '../core/models/enums.dart';
import '../core/routing/app_routes.dart';
import '../core/routing/route_access.dart';
import '../features/assistant/api.dart';

/// Alt menü hedefleri (spec A.2).
enum DestinationId {
  home,
  deliveries,
  myOrders,
  myShipments,
  approvals,
  quoteDesk,
  bayiOrders,
  dispatch,
  payments,
  finance,
  customers,
  field,
  companyRequests,
  staff,
  documents,
  spending,
  deliveryPoints,
  financeInfo,
  templates,
  limits,
  companyUsers,
  stats,
  assistant,
  notifications,
  profile,
}

/// Bir hedef: tam ad (başlık, "Diğer" sayfası, ekran okuyucu), çubuk adı (en fazla 10 karakter), ikon,
/// kök rota, öncelik ve görünürlük kuralı.
@immutable
class AppDestination {
  const AppDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.path,
    required this.priority,
    required this.visible,
    String? barLabel,
    IconData? selectedIcon,
  }) : barLabel = barLabel ?? label,
       selectedIcon = selectedIcon ?? icon;

  final DestinationId id;

  /// Sayfa adı (v4 §3.2: sayfa başlığı = sekmenin kelimesi): "Onaylar", "Teklifler", "Siparişler",
  /// "Teslimatlar". Sayfa başlıkları, "Diğer" sayfası, ipuçları ve bildirim çağrıları bunu kullanır.
  final String label;

  /// Alt çubuktaki ad (≤ 10 karakter, spec C.7): çoğunlukla [label]; yalnızca uzun adlar kısalır
  /// ("Teslimat", "Bildirim").
  final String barLabel;
  final IconData icon;
  final IconData selectedIcon;

  /// Kök rota (`/orders`).
  final String path;

  /// Genel öncelik (küçük önce).
  final int priority;
  final bool Function(AccessPolicy policy, AppFeatures features) visible;

  /// Bildirimler, Asistan, Profil: "Diğer" sayfasında her zaman bulunur.
  bool get isExtra =>
      id == DestinationId.notifications ||
      id == DestinationId.assistant ||
      id == DestinationId.profile;

  @override
  String toString() => 'AppDestination(${id.name})';
}

bool _always(AccessPolicy p, AppFeatures f) => true;

/// Tüm hedefler (spec A.2 tablosu). Görünürlük `me/access` sayfa yetkileri ve yetkinliklerinden gelir,
/// rol adından değil; sunucu ayrıca denetler.
final List<AppDestination> appDestinations = List.unmodifiable([
  AppDestination(
    id: DestinationId.home,
    label: 'Ana sayfa',
    icon: PhosphorIconsRegular.house,
    selectedIcon: PhosphorIconsFill.house,
    path: AppRoutes.home,
    priority: 0,
    visible: (p, f) => !p.isDriverOnly,
  ),
  AppDestination(
    id: DestinationId.deliveries,
    label: 'Teslimatlar',
    barLabel: 'Teslimat',
    icon: PhosphorIconsRegular.truck,
    selectedIcon: PhosphorIconsFill.truck,
    path: AppRoutes.driver,
    priority: 1,
    visible: (p, f) => p.canSeeDeliveries,
  ),
  AppDestination(
    id: DestinationId.myOrders,
    label: 'Siparişler',
    icon: PhosphorIconsRegular.receipt,
    selectedIcon: PhosphorIconsFill.receipt,
    path: AppRoutes.orders,
    priority: 2,
    visible: (p, f) =>
        p.isCustomer && p.canAny(const [Pg.customerOrders, Pg.customerQuotes]),
  ),
  AppDestination(
    id: DestinationId.myShipments,
    label: 'Teslimatlar',
    barLabel: 'Teslimat',
    icon: PhosphorIconsRegular.truck,
    selectedIcon: PhosphorIconsFill.truck,
    path: AppRoutes.shipments,
    priority: 3,
    visible: (p, f) => p.isCustomer && p.can(Pg.customerShipments),
  ),
  AppDestination(
    id: DestinationId.approvals,
    label: 'Onaylar',
    icon: PhosphorIconsRegular.checkCircle,
    selectedIcon: PhosphorIconsFill.checkCircle,
    path: AppRoutes.approvals,
    priority: 4,
    visible: (p, f) =>
        p.isPlatform ||
        p.canAny(const [Pg.stationApprovals, Pg.customerApprovals]),
  ),
  AppDestination(
    id: DestinationId.quoteDesk,
    label: 'Teklifler',
    icon: PhosphorIconsRegular.invoice,
    selectedIcon: PhosphorIconsFill.invoice,
    path: AppRoutes.quoteDesk,
    priority: 5,
    visible: (p, f) => p.isBayi && p.can(Pg.stationQuoteDesk),
  ),
  AppDestination(
    id: DestinationId.bayiOrders,
    label: 'Siparişler',
    icon: PhosphorIconsRegular.receipt,
    selectedIcon: PhosphorIconsFill.receipt,
    path: AppRoutes.bayiOrders,
    priority: 6,
    visible: (p, f) => p.isBayi && p.can(Pg.stationOrders),
  ),
  AppDestination(
    id: DestinationId.dispatch,
    label: 'Sevkiyat',
    icon: PhosphorIconsRegular.truck,
    selectedIcon: PhosphorIconsFill.truck,
    path: AppRoutes.dispatch,
    priority: 7,
    visible: (p, f) => p.isBayi && p.can(Pg.stationShipmentBoard),
  ),
  AppDestination(
    id: DestinationId.payments,
    label: 'Tahsilat',
    icon: PhosphorIconsRegular.wallet,
    selectedIcon: PhosphorIconsFill.wallet,
    path: AppRoutes.payments,
    priority: 8,
    visible: (p, f) => p.isBayi && p.can(Pg.stationPayments),
  ),
  AppDestination(
    id: DestinationId.finance,
    label: 'Finans',
    icon: PhosphorIconsRegular.bank,
    selectedIcon: PhosphorIconsFill.bank,
    path: AppRoutes.finance,
    priority: 9,
    visible: (p, f) => p.isBayi && p.can(Pg.stationFinance),
  ),
  AppDestination(
    id: DestinationId.customers,
    label: 'Cariler',
    icon: PhosphorIconsRegular.usersThree,
    selectedIcon: PhosphorIconsFill.usersThree,
    path: AppRoutes.customers,
    priority: 10,
    visible: (p, f) =>
        p.isBayi && (p.can(Pg.stationCustomers) || p.isFieldSales),
  ),
  AppDestination(
    id: DestinationId.field,
    label: 'Saha',
    icon: PhosphorIconsRegular.identificationBadge,
    selectedIcon: PhosphorIconsFill.identificationBadge,
    path: AppRoutes.field,
    priority: 11,
    visible: (p, f) =>
        p.isBayi && p.canAny(const [Pg.stationFieldOrders, Pg.stationLeads]),
  ),
  AppDestination(
    id: DestinationId.companyRequests,
    label: 'Talepler',
    icon: PhosphorIconsRegular.listChecks,
    selectedIcon: PhosphorIconsFill.listChecks,
    path: AppRoutes.companyRequests,
    priority: 12,
    // Roller v5: şirket içi onay kapalıysa (tek müşteri rolü) Talepler menüde yok; eski talepler bağlantıyla
    // (bildirim) sayfa yetkisiyle açılır.
    visible: (p, f) =>
        p.isCustomer && p.companyApprovals && p.can(Pg.customerOrderRequests),
  ),
  AppDestination(
    id: DestinationId.staff,
    label: 'Ekip',
    icon: PhosphorIconsRegular.users,
    selectedIcon: PhosphorIconsFill.users,
    path: AppRoutes.bayiStaff,
    priority: 13,
    visible: (p, f) => p.isBayi && !p.isFieldSales && p.can(Pg.stationStaff),
  ),
  AppDestination(
    id: DestinationId.documents,
    label: 'Belgeler',
    icon: PhosphorIconsRegular.folder,
    selectedIcon: PhosphorIconsFill.folder,
    path: AppRoutes.documents,
    priority: 20,
    visible: (p, f) => p.isCustomer && p.can(Pg.customerDocuments),
  ),
  AppDestination(
    id: DestinationId.spending,
    label: 'Harcamalar',
    icon: PhosphorIconsRegular.chartLineUp,
    selectedIcon: PhosphorIconsFill.chartLineUp,
    path: AppRoutes.spending,
    priority: 21,
    visible: (p, f) => p.isCustomer && p.can(Pg.customerSpending),
  ),
  AppDestination(
    id: DestinationId.deliveryPoints,
    label: 'Teslimat noktaları',
    barLabel: 'Noktalar',
    icon: PhosphorIconsRegular.mapPin,
    selectedIcon: PhosphorIconsFill.mapPin,
    path: AppRoutes.deliveryPoints,
    priority: 22,
    visible: (p, f) => p.isCustomer && p.can(Pg.customerDeliveryPoints),
  ),
  AppDestination(
    id: DestinationId.financeInfo,
    label: 'Finans bilgisi',
    barLabel: 'Finans',
    icon: PhosphorIconsRegular.wallet,
    selectedIcon: PhosphorIconsFill.wallet,
    path: AppRoutes.financeInfo,
    priority: 23,
    visible: (p, f) =>
        p.isCustomer &&
        p.canAny(const [Pg.customerCreateOrder, Pg.customerOrders]),
  ),
  AppDestination(
    id: DestinationId.templates,
    label: 'Şablonlar',
    icon: PhosphorIconsRegular.bookmarks,
    selectedIcon: PhosphorIconsFill.bookmarks,
    path: AppRoutes.templates,
    priority: 24,
    visible: (p, f) => p.isCustomer && p.can(Pg.customerCreateOrder),
  ),
  AppDestination(
    id: DestinationId.limits,
    label: 'Limitler',
    icon: PhosphorIconsRegular.gauge,
    selectedIcon: PhosphorIconsFill.gauge,
    path: AppRoutes.limits,
    priority: 25,
    visible: (p, f) => p.isCustomer,
  ),
  AppDestination(
    id: DestinationId.companyUsers,
    label: 'Şirket kullanıcıları',
    barLabel: 'Kullanıcı',
    icon: PhosphorIconsRegular.userGear,
    selectedIcon: PhosphorIconsFill.userGear,
    path: AppRoutes.companyUsers,
    priority: 26,
    visible: (p, f) =>
        p.isCustomer &&
        p.customerRole == CustomerUserRole.admin &&
        p.can(Pg.customerCompanyUsers),
  ),
  AppDestination(
    id: DestinationId.stats,
    label: 'İstatistikler',
    barLabel: 'İstatistik',
    icon: PhosphorIconsRegular.chartBar,
    selectedIcon: PhosphorIconsFill.chartBar,
    path: AppRoutes.stats,
    priority: 27,
    // Yönetici destesini görenler (v4 §3.1): bayi yöneticileri, saha, müşteri yönetici / onaylayan.
    visible: (p, f) => RouteAccess.statsAudience(p),
  ),
  AppDestination(
    id: DestinationId.assistant,
    label: 'Asistan',
    // Robot simgesi yok (spec A.6): ana sayfalardaki asistan düğmesiyle aynı sohbet balonu.
    icon: PhosphorIconsRegular.chatCircle,
    selectedIcon: PhosphorIconsFill.chatCircle,
    path: AppRoutes.assistant,
    priority: 30,
    visible: (p, f) => f.assistant,
  ),
  const AppDestination(
    id: DestinationId.notifications,
    label: 'Bildirimler',
    barLabel: 'Bildirim',
    icon: PhosphorIconsRegular.bell,
    selectedIcon: PhosphorIconsFill.bell,
    path: AppRoutes.notifications,
    priority: 31,
    visible: _always,
  ),
  const AppDestination(
    id: DestinationId.profile,
    label: 'Profil',
    icon: PhosphorIconsRegular.user,
    selectedIcon: PhosphorIconsFill.user,
    path: AppRoutes.profile,
    priority: 99,
    visible: _always,
  ),
]);

AppDestination destinationOf(DestinationId id) =>
    appDestinations.firstWhere((d) => d.id == id);

/// Rol ön ayarının Ana sayfa'dan sonraki sekmeleri (spec A.2 tablosu).
const Map<RolePreset, List<DestinationId>> presetTabs = {
  RolePreset.owner: [
    DestinationId.approvals,
    DestinationId.quoteDesk,
    DestinationId.bayiOrders,
  ],
  RolePreset.finance: [
    DestinationId.approvals,
    DestinationId.finance,
    DestinationId.payments,
  ],
  RolePreset.salesManager: [
    DestinationId.approvals,
    DestinationId.field,
    DestinationId.customers,
  ],
  RolePreset.accounting: [
    DestinationId.payments,
    DestinationId.finance,
    DestinationId.bayiOrders,
  ],
  // Roller v5: İkmal birimi teklif verir, sevkiyatı planlar ve dolumu kaydeder.
  RolePreset.supply: [
    DestinationId.quoteDesk,
    DestinationId.dispatch,
    DestinationId.bayiOrders,
  ],
  RolePreset.orderDesk: [
    DestinationId.quoteDesk,
    DestinationId.bayiOrders,
    DestinationId.dispatch,
  ],
  RolePreset.dispatch: [
    DestinationId.dispatch,
    DestinationId.bayiOrders,
    DestinationId.customers,
  ],
  RolePreset.fieldRep: [DestinationId.field, DestinationId.customers],
  RolePreset.viewer: [
    DestinationId.bayiOrders,
    DestinationId.dispatch,
    DestinationId.customers,
  ],
  RolePreset.customerApprover: [
    DestinationId.myOrders,
    DestinationId.approvals,
  ],
  RolePreset.customerRequester: [
    DestinationId.myOrders,
    DestinationId.myShipments,
  ],
  RolePreset.generic: [],
};

/// Alt menünün ortadaki eylemi ("Sipariş ver", "Yeni form").
@immutable
class CenterActionSpec {
  const CenterActionSpec({
    required this.label,
    required this.icon,
    required this.path,
  });
  final String label;
  final IconData icon;
  final String path;
}

/// Hesaplanmış alt menü: çubuktaki hedefler, ortadaki eylem, "Diğer" sayfasındakiler.
@immutable
class NavLayout {
  const NavLayout({required this.bar, this.more = const [], this.center});

  static const empty = NavLayout(bar: []);

  /// "Diğer" sekmesinin ve sayfasının adı (spec C.7).
  static const moreLabel = 'Diğer';

  final List<AppDestination> bar;
  final List<AppDestination> more;
  final CenterActionSpec? center;

  bool get hasMore => more.isNotEmpty;
  bool get isEmpty => bar.isEmpty;

  /// Girişten sonra açılan konum (ilk sekme).
  String get initialLocation => bar.isEmpty ? AppRoutes.home : bar.first.path;

  bool contains(DestinationId id) =>
      bar.any((d) => d.id == id) || more.any((d) => d.id == id);
  bool inBar(DestinationId id) => bar.any((d) => d.id == id);

  /// Rotaları yeniden kurmak gerekip gerekmediğini belirleyen imza.
  String get signature =>
      '${bar.map((d) => d.id.name).join(',')}|${more.map((d) => d.id.name).join(',')}|${center?.path ?? ''}';

  @override
  bool operator ==(Object other) =>
      other is NavLayout && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;

  @override
  String toString() => 'NavLayout($signature)';
}

/// Alt menüyü kurar (spec A.2 "Filling the bottom bar" ve "Bar rules").
///
/// 1. Ana sayfa önce (yalnızca şoför olanlar hariç).
/// 2. Rol ön ayarının görünür sekmeleri, sırayla.
/// 3. Kalan yuvalar genel öncelikle dolar (Asistan / Bildirimler / Profil dahil).
/// 4. Yuva: 4 hedef + "Diğer"; ortada eylem varsa 3 + eylem + "Diğer". Hepsi sığarsa "Diğer" gizlenir.
/// 5. Onaylar yalnızca onaylayanlarda ([AccessPolicy.isApprover]) ana sekmedir; yoksa "Diğer"dedir.
///    v4 §3.1: çubuk girişte sabitlenir — bekleyen onay rozeti çubuğu değiştirmez.
/// 6. Yalnızca şoför: Teslimatlar · Bildirimler · Asistan · Profil. Merkez: Ana sayfa · Onaylar ·
///    Bildirimler · Profil.
NavLayout buildNavLayout(AccessPolicy p, AppFeatures f) {
  if (!p.isSignedIn) return NavLayout.empty;
  AppDestination d(DestinationId id) => destinationOf(id);

  if (p.isPlatform) {
    return NavLayout(
      bar: [
        d(DestinationId.home),
        d(DestinationId.approvals),
        d(DestinationId.notifications),
        d(DestinationId.profile),
      ],
    );
  }

  final extras = [
    for (final e in appDestinations)
      if (e.isExtra && e.visible(p, f)) e,
  ]..sort((a, b) => a.priority.compareTo(b.priority));

  if (p.isDriverOnly) {
    return NavLayout(
      bar: [
        d(DestinationId.deliveries),
        d(DestinationId.notifications),
        if (f.assistant) d(DestinationId.assistant),
        d(DestinationId.profile),
      ],
    );
  }

  CenterActionSpec? center;
  if (p.isCustomer && p.can(Pg.customerCreateOrder, Perm.create)) {
    center = const CenterActionSpec(
      label: 'Sipariş ver',
      icon: PhosphorIconsRegular.plus,
      path: AppRoutes.orderNew,
    );
  } else if (p.isFieldSales && p.can(Pg.stationFieldOrders, Perm.create)) {
    center = const CenterActionSpec(
      label: 'Yeni form',
      icon: PhosphorIconsRegular.filePlus,
      path: AppRoutes.fieldFormNew,
    );
  }

  final primary = [
    for (final e in appDestinations)
      if (!e.isExtra && e.id != DestinationId.home && e.visible(p, f)) e,
  ]..sort((a, b) => a.priority.compareTo(b.priority));

  final approvalsMainTab = p.isApprover;
  bool barEligible(AppDestination e) =>
      e.id != DestinationId.approvals || approvalsMainTab;

  final ordered = <AppDestination>[d(DestinationId.home)];
  for (final id in presetTabs[p.rolePreset] ?? const <DestinationId>[]) {
    final match = primary.where((e) => e.id == id && barEligible(e));
    if (match.isNotEmpty && !ordered.contains(match.first)) {
      ordered.add(match.first);
    }
  }
  for (final e in primary) {
    if (!ordered.contains(e)) ordered.add(e);
  }

  final slots = center == null ? 4 : 3;
  final all = [...ordered, ...extras];
  if (all.length <= slots + 1) return NavLayout(bar: all, center: center);

  final bar = <AppDestination>[];
  final rest = <AppDestination>[];
  for (final e in ordered) {
    if (bar.length < slots && barEligible(e)) {
      bar.add(e);
    } else {
      rest.add(e);
    }
  }
  final remainingExtras = [...extras];
  // Genel öncelik boş yuvaları ek hedeflerle doldurur (ör. depo: Ana sayfa · Sevkiyat · Siparişler · Asistan).
  while (bar.length < slots && remainingExtras.isNotEmpty) {
    bar.add(remainingExtras.removeAt(0));
  }
  return NavLayout(
    bar: bar,
    more: [...rest, ...remainingExtras],
    center: center,
  );
}

/// Oturumdaki kullanıcının alt menüsü (v4 §3.1: girişte sabit). Yalnızca yetki imzası ya da Asistan
/// erişimi değişince yeniden hesaplanır (yönlendirici buna bağlıdır).
final navLayoutProvider = Provider<NavLayout>((ref) {
  ref.watch(sessionControllerProvider.select((s) => s.access?.layoutKey));
  final assistant = ref.watch(assistantEnabledProvider);
  return buildNavLayout(
    ref.read(accessPolicyProvider),
    AppFeatures(assistant: assistant),
  );
});

/// "Diğer" sayfasının grupları (v4 §3.1): müşteride Siparişler · Finans · Şirket · Hesap; bayide İş ·
/// Yönetim · Hesap.
enum MoreGroup {
  orders('Siparişler'),
  finance('Finans'),
  company('Şirket'),
  work('İş'),
  management('Yönetim'),
  account('Hesap');

  const MoreGroup(this.label);

  /// Grup başlığı (13/18 600 dim).
  final String label;
}

/// [d]'nin "Diğer" grubu ([customer]: müşteri kullanıcısı).
MoreGroup moreGroupOf(AppDestination d, {required bool customer}) {
  if (d.isExtra) return MoreGroup.account;
  if (customer) {
    return switch (d.id) {
      DestinationId.financeInfo ||
      DestinationId.limits ||
      DestinationId.spending ||
      DestinationId.documents ||
      DestinationId.stats => MoreGroup.finance,
      DestinationId.companyUsers => MoreGroup.company,
      _ => MoreGroup.orders,
    };
  }
  return switch (d.id) {
    DestinationId.staff || DestinationId.stats => MoreGroup.management,
    _ => MoreGroup.work,
  };
}
