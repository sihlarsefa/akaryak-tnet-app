import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/access_policy.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';

/// Saha sekmesinin kime nasıl göründüğü (spec A.4 A6 "Saha tab by persona").
enum FieldMode {
  /// Saha satış temsilcisi (FieldSales): Formlarım, Ön kayıtlarım, Portföy.
  rep,

  /// Diğer bayi rolleri (satış müdürü, bayi müdürü, sahip, görüntüleyici): Saha ekibi.
  team,

  /// Yalnızca `StationLeads:Gorur` (ör. finans müdürü): yalnızca ön kayıtlar.
  leadsOnly,

  /// Saha sayfalarına yetkisi yok.
  none,
}

/// Saha ekranlarının düğme kuralları (spec A.1; sunucu her zaman ayrıca denetler).
class FieldAccess {
  const FieldAccess(this.policy);

  final AccessPolicy policy;

  String? get userId => policy.access?.userId;
  int? get stationId => policy.access?.stationId;

  FieldMode get mode {
    if (!policy.isBayi && !policy.isPlatform) return FieldMode.none;
    final forms = policy.can(Pg.stationFieldOrders);
    if (forms) return policy.isFieldSales ? FieldMode.rep : FieldMode.team;
    if (policy.can(Pg.stationLeads)) return FieldMode.leadsOnly;
    return FieldMode.none;
  }

  bool get isRep => mode == FieldMode.rep;

  // ---- Saha formları
  bool get canSeeForms => policy.can(Pg.stationFieldOrders);
  bool get canCreateForm => policy.can(Pg.stationFieldOrders, Perm.create);
  bool get canEditForm => policy.can(Pg.stationFieldOrders, Perm.edit);

  /// "E-posta ile gönder": web `EmailForm` ile aynı (Saha Siparişleri "Ekler").
  bool get canEmailForm => policy.can(Pg.stationFieldOrders, Perm.create);

  /// "Dönüşümü yeniden dene" (`StationFieldApprovals:Duzenler`).
  bool get canRetryConversion =>
      policy.can(Pg.stationFieldApprovals, Perm.edit);

  // ---- Ön kayıtlar
  bool get canSeeLeads => policy.can(Pg.stationLeads);
  bool get canCreateLead => policy.can(Pg.stationLeads, Perm.create);
  bool get canEditLead => policy.can(Pg.stationLeads, Perm.edit);

  /// Bayinin tüm ön kayıtları (`lead.viewAll`; sunucu `approve.finance.lead` ile de açar).
  bool get canSeeAllLeads =>
      policy.hasCap(Caps.leadViewAll) || policy.hasCap(Caps.approveFinanceLead);

  /// "Merkeze ilet" (`approve.finance.lead` + Leads ya da Approvals görür).
  bool get canForwardLeadToHq =>
      policy.hasCap(Caps.approveFinanceLead) &&
      (policy.can(Pg.stationLeads) || policy.can(Pg.stationApprovals));

  // ---- Diğer özelliklere geçiş (rota yolları)
  bool get canOpenApprovals =>
      policy.isPlatform ||
      policy.canAny(const [Pg.stationApprovals, Pg.customerApprovals]);
  bool get canOpenBayiOrders => policy.can(Pg.stationOrders);
  bool get canOpenCustomerCard =>
      policy.can(Pg.stationCustomers) || policy.isFieldSales;

  /// Saha sekmesinin başlığı.
  String get title => switch (mode) {
    FieldMode.rep => 'Saha',
    FieldMode.team => 'Saha ekibi',
    FieldMode.leadsOnly => 'Ön kayıtlar',
    FieldMode.none => 'Saha',
  };
}

final fieldAccessProvider = Provider<FieldAccess>(
  (ref) => FieldAccess(ref.watch(accessPolicyProvider)),
);
