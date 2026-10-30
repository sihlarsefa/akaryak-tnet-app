import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/access_policy.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/models/models.dart';
import '../../../core/ui/status.dart';

/// Bayi ekranlarındaki düğmelerin yetki kuralları (spec A.1 "Action → grant" tablosu). Tek kaynak
/// [AccessPolicy.can] / [AccessPolicy.hasCap]'tır; rol adına bakılmaz (bayiler özel rol kurar). Sunucu
/// her işlemi ayrıca denetler: buradaki kural yalnızca düğmeyi gösterir / gizler.
@immutable
class BayiGrants {
  const BayiGrants(this.policy);

  final AccessPolicy policy;

  bool _can(String page, [String perm = Perm.view]) => policy.can(page, perm);

  /// `shipment.ownOnly` (şoför): plan, atama, yola çıkarma, teslim bildirme ve iptal kapalı; şoför
  /// kendi teslimatlarını Teslimatlarım'dan yönetir. Merkez personeli hiçbir zaman ownOnly değildir.
  bool get ownOnly =>
      !policy.isPlatform &&
      (policy.access?.capabilities.any((c) => c.code == Caps.shipmentOwnOnly) ??
          false);

  bool get isFieldSales => policy.isFieldSales;

  // ------------------------------------------------------------------ Teklif

  /// Teklif masası görüntüleme.
  bool get viewDesk => _can(Pg.stationQuoteDesk);

  /// Teklif ver (masa): `StationQuoteDesk:Ekler`. Engel ve finans durumu ayrıca kontrol edilir.
  bool get quoteOnDesk => _can(Pg.stationQuoteDesk, Perm.create);

  /// Teklif ver (sipariş ayrıntısı): `StationQuotes:Ekler`.
  bool get quoteOnOrder => _can(Pg.stationQuotes, Perm.create);

  /// Siparişe teklif verilebilir mi: yetki + durum + finans engeli + masa engeli.
  bool canQuoteOrder(
    OrderStatus status,
    OrderFinanceStatus finance, {
    bool quotingBlocked = false,
  }) =>
      quoteOnOrder &&
      !quotingBlocked &&
      (status == OrderStatus.awaitingQuote ||
          status == OrderStatus.revisionRequested) &&
      !finance.isAwaitingDecision &&
      finance != OrderFinanceStatus.rejected;

  // ------------------------------------------------------------------ Siparişler

  bool get viewOrders => _can(Pg.stationOrders);

  /// Tamamla: `StationOrders:Duzenler` ve kabul edilen litre ≥ sipariş (çağıran kontrol eder).
  bool get completeOrder => _can(Pg.stationOrders, Perm.edit);

  // ------------------------------------------------------------------ Sevkiyat

  /// Sevkiyat panosu (plan, öneriler).
  bool get viewBoard => _can(Pg.stationShipmentBoard);

  /// Sevkiyatlar listesi ve ayrıntısı (`StationShipments` ya da `StationShipmentBoard` Görür).
  bool get viewShipments =>
      _can(Pg.stationShipments) || _can(Pg.stationShipmentBoard);

  /// Sevkiyat planla: `StationShipments:Ekler`; ownOnly hiçbir zaman.
  bool get planShipment => !ownOnly && _can(Pg.stationShipments, Perm.create);

  /// Şoför ata / değiştir: `StationShipments:Ekler` + `Duzenler`; ownOnly hiçbir zaman.
  bool get assignDriver =>
      !ownOnly &&
      _can(Pg.stationShipments, Perm.create) &&
      _can(Pg.stationShipments, Perm.edit);

  /// Yola çıkar / Teslim bildir (personel): `StationShipments:Duzenler`; ownOnly değil.
  bool get dispatchOrReport => !ownOnly && _can(Pg.stationShipments, Perm.edit);

  /// Sevkiyat iptal: `StationShipments:Siler`; ownOnly değil.
  bool get cancelShipment => !ownOnly && _can(Pg.stationShipments, Perm.delete);

  /// Şoför listesi (`stations/me/drivers`): `StationShipments:Ekler` ya da pano görüntüleme.
  bool get listDrivers =>
      !ownOnly &&
      (_can(Pg.stationShipments, Perm.create) || _can(Pg.stationShipmentBoard));

  // ------------------------------------------------------------------ Cariler

  /// Cariler: `StationCustomers:Görür` ya da saha satış (yalnızca kendi portföyü).
  bool get viewCustomers => _can(Pg.stationCustomers) || isFieldSales;

  /// Cari notu: `StationCustomers:Duzenler`.
  bool get addCustomerNote => _can(Pg.stationCustomers, Perm.edit);

  /// Limit talebi: `StationCustomers:Ekler` (bekleyen talep yoksa; sunucu bayrağıyla birlikte).
  bool get requestLimit => _can(Pg.stationCustomers, Perm.create);

  // ------------------------------------------------------------------ Diğer bölümler

  bool get viewApprovals => policy.isPlatform || _can(Pg.stationApprovals);
  bool get viewPayments => _can(Pg.stationPayments);
  bool get viewFinance => _can(Pg.stationFinance);
  bool get viewLeads => _can(Pg.stationLeads);
  bool get viewFieldForms =>
      _can(Pg.stationFieldOrders) || _can(Pg.stationFieldApprovals);
  bool get createFieldForm => _can(Pg.stationFieldOrders, Perm.create);

  // ------------------------------------------------------------------ Ekip

  /// Ekip: `StationStaff:Görür`, saha satış hiçbir zaman (spec A.2).
  bool get viewStaff => !isFieldSales && _can(Pg.stationStaff);

  /// Aktif/pasif, "Şifre bağlantısı gönder" ve "Şifre belirle": `StationStaff:Duzenler`.
  bool get manageStaff => viewStaff && _can(Pg.stationStaff, Perm.edit);

  /// "Şifre belirle" (sahip 2026-10-30): personeli düzenleyebilen herkes, başkasının hesabında (kendi
  /// şifresini Profil'den değiştirir). Bayinin ana hesabının (`isMainAccount`) şifresini yalnızca
  /// kendisi değiştirir: başkasının kartında düğme yok (sunucu yine de 403 döner; ileti sayfada).
  bool setStaffPassword({required bool self, bool mainAccount = false}) =>
      manageStaff && !self && !mainAccount;

  // ------------------------------------------------------------------ Durum lambası

  /// Durum lambası için izleyici (tasarım v2 §10.3): teklif verebilen "Teklif verin", sevkiyat
  /// planlayabilen "Sevkiyat planlayın" lambasını turuncu (sıra sizde) görür.
  StatusViewer get viewer => StatusViewer.bayi(
    canQuote: quoteOnOrder || quoteOnDesk,
    canPlan: planShipment,
    canDecide: viewApprovals,
  );
}

/// Oturumdaki kullanıcının bayi yetkileri.
final bayiGrantsProvider = Provider<BayiGrants>(
  (ref) => BayiGrants(ref.watch(accessPolicyProvider)),
);
