import 'package:flutter/foundation.dart';

import '../models/enums.dart';
import '../models/me_access.dart';
import 'permissions.dart';

/// Rol ön ayarı (alt menü sırası; spec A.2). Kodlar tablodaki sırayla denenir; özel rol ve kodsuz
/// kullanıcı [generic] kullanır. Rolü atanmamış bayi sahibi (`isStationOwner`, kod yok) [owner] alır.
///
/// Roller v5: Bayi yöneticisi `owner`, Finans birimi `finance_manager`, Satış temsilcisi `field_rep`,
/// Muhasebe birimi `accounting` kodunu korur; İkmal birimi (`supply`) yeni ön ayardır ve sipariş masası ile
/// sevkiyattan önce denenir (geçiş sırasında ikisini birden tutan kullanıcı İkmal olur). Pasif kodlar
/// (`manager`, `finance_specialist`, `order_desk`, `dispatch`, `depot`, `viewer`) yerinde kalır: pasif
/// rolde çalışmaya devam eden kullanıcının menüsü değişmez.
enum RolePreset {
  owner([BayiRoleCodes.owner, BayiRoleCodes.manager]),
  finance([BayiRoleCodes.financeManager, BayiRoleCodes.financeSpecialist]),
  salesManager([BayiRoleCodes.salesManager]),
  accounting([BayiRoleCodes.accounting]),

  /// İkmal birimi: Teklifler · Sevkiyat · Siparişler; "sıra sizde" Teklif ve Plan.
  supply([BayiRoleCodes.supply]),
  orderDesk([BayiRoleCodes.orderDesk]),
  dispatch([BayiRoleCodes.dispatch, BayiRoleCodes.depot]),
  fieldRep([BayiRoleCodes.fieldRep]),
  viewer([BayiRoleCodes.viewer]),

  /// Müşteri, şirket rolü Onaylayan ya da Yönetici: Siparişler · Onaylar.
  customerApprover([]),

  /// Müşteri, şirket rolü Talep eden: Siparişler · Teslimatlar (Talepler "Diğer"de).
  customerRequester([]),
  generic([]);

  const RolePreset(this.codes);

  /// Bu ön ayarı seçtiren bayi rolü kodları.
  final List<String> codes;
}

/// Ne gösterileceğine karar veren tek yer (spec C.4). Kararlar `me/access` sayfa yetkileri ve
/// yetkinliklerinden verilir, rol adından değil. Sunucu her zaman ayrıca denetler.
@immutable
class AccessPolicy {
  const AccessPolicy(this.access);

  static const signedOut = AccessPolicy(null);

  final MeAccess? access;

  bool get isSignedIn => access != null;
  Persona get persona => access?.persona ?? Persona.unknown;
  bool get isCustomer => persona == Persona.customer;
  bool get isBayi => persona == Persona.bayi;
  bool get isPlatform => persona == Persona.platform;

  /// Saha satış personeli (Station + FieldSales; sunucu ayrıca `isFieldSales` bayrağını verir).
  bool get isFieldSales {
    final a = access;
    if (a == null) return false;
    return a.isFieldSalesFlag || a.roles.contains(Roles.fieldSales);
  }

  /// Kullanıcıya şoför olarak atanmış açık sevkiyat sayısı (`me/access.assignedOpenShipments`).
  int get assignedOpenShipments => access?.assignedOpenShipments ?? 0;

  /// "Teslimatlarım" görünür mü: şoför yetkinliği (`shipment.ownOnly`) ya da kendisine atanmış açık
  /// sevkiyatı olan bayi personeli (kendisi teslim eden sahip, depo …; spec A.2).
  bool get canSeeDeliveries =>
      isBayi &&
      ((access?.capabilities.any((c) => c.code == Caps.shipmentOwnOnly) ??
              false) ||
          assignedOpenShipments > 0);

  /// Onaylarım ana sekme olabilir mi (spec A.2; roller v5 §7): merkez, müşteri (tek rol; şirket
  /// kullanıcıları Onaylar'da bayi finansının bilgi isteklerini yanıtlar) ya da imza yetkinliklerinde
  /// (`signingCapabilities`) bir `approve.*` kodu. İmza yetkinlikleri bu bayide birimin onaycısı başkası
  /// olduğu için imzalayamadığı kodları içermez; alanı göndermeyen eski sunucuda `capabilities` geçerlidir.
  /// Görev ve rozetler zaten sunucunun `canDecide` ve sayılarını izler.
  bool get isApprover {
    final a = access;
    if (a == null) return false;
    if (isPlatform || isCustomer) return true;
    return a.signingOrCapabilities.any((c) => c.code.startsWith('approve.'));
  }

  /// Kullanıcının onaycısı olduğu birimler (`management`, `sales`, `finance`; panelin sırasıyla).
  List<String> get approverUnits => access?.approverUnits ?? const [];

  /// Müşteride şirket içi onay akışı açık mı (`me/access.companyApprovalsEnabled`; null / eski sunucu =
  /// açık). Kapalıyken rol seçimi, onay eşikleri, rol açıklamaları, Talepler ve talep edenin ana sayfası
  /// gösterilmez (roller v5: tek müşteri rolü).
  bool get companyApprovals => access?.companyApprovals ?? true;

  /// Müşterinin şirket içi rolü. Teklif kararı ve teslim kabulü rolden değil, sunucunun sipariş /
  /// sevkiyat başına verdiği panel değerlerinden okunur (`CustomerDecider`; rol yalnızca talep edenin
  /// şirket içi onay eşiğinde ve yedek kuralda anlamlıdır).
  CustomerUserRole get customerRole =>
      access?.customerUserRole ?? CustomerUserRole.unknown;

  /// Bayide teklif verir mi (v4 tur 2): Teklifler'de ya da sipariş ayrıntısında teklif ekleme
  /// yetkisi (`StationQuoteDesk:Ekler` ya da `StationQuotes:Ekler`). Masayı yalnızca görmek teklif işi
  /// değildir: finans ve izleyici için "Yeni sipariş" bilgidir, "Sıradaki işiniz" teklif açmaz.
  bool get quotesOrders =>
      isBayi &&
      (can(Pg.stationQuoteDesk, Perm.create) ||
          can(Pg.stationQuotes, Perm.create));

  /// Sayfa yetkisi: `can(Pg.stationOrders)` = Görür, `can(Pg.stationOrders, Perm.edit)` = Düzenler.
  bool can(String page, [String perm = Perm.view]) =>
      access?.pages.contains('$page:$perm') ?? false;

  /// Sayfalardan biri için yetki.
  bool canAny(Iterable<String> pages, [String perm = Perm.view]) =>
      pages.any((p) => can(p, perm));

  /// Yetkinlik (platform personeli her yetkinliğe sahiptir).
  bool hasCap(String code) {
    final a = access;
    if (a == null) return false;
    if (a.persona == Persona.platform) return true;
    return a.capabilities.any((c) => c.code == code);
  }

  /// Yetkinliğin tutar sınırı (null = sınırsız ya da yetkinlik yok).
  double? capLimit(String code) {
    for (final c in access?.capabilities ?? const <Capability>[]) {
      if (c.code == code) return c.limit;
    }
    return null;
  }

  /// Yalnızca şoför: `shipment.ownOnly` ve Teklif masası, Siparişler, Sevkiyat panosu, Onaylarım'dan hiçbiri.
  bool get isDriverOnly =>
      isBayi &&
      hasCap(Caps.shipmentOwnOnly) &&
      !canAny(const [
        Pg.stationQuoteDesk,
        Pg.stationOrders,
        Pg.stationShipmentBoard,
        Pg.stationApprovals,
      ]);

  /// Alt menü ön ayarı.
  RolePreset get rolePreset {
    if (isCustomer) {
      return customerRole == CustomerUserRole.requester
          ? RolePreset.customerRequester
          : RolePreset.customerApprover;
    }
    final codes = access?.bayiRoleCodes ?? const <String>[];
    if (!isBayi) return RolePreset.generic;
    if (codes.isEmpty) {
      // Sunucunun eski türetmesi (BayiAccessService): rol ataması olmayan bayi sahibi `owner`
      // şablonunun yetkinliklerini kullanır, ama `bayiRoleCodes` boş gelir. Saha satışçı sahip değil.
      return access!.isStationOwner && !isFieldSales
          ? RolePreset.owner
          : RolePreset.generic;
    }
    for (final preset in RolePreset.values) {
      if (preset.codes.any(codes.contains)) return preset;
    }
    return RolePreset.generic;
  }
}
