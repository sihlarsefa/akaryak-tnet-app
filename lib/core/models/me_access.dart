import 'package:flutter/foundation.dart';

import '../utils/turkish_text.dart';
import 'enums.dart';
import 'json.dart';

/// Kullanıcının uygulamadaki kimliği.
enum Persona {
  customer('customer', 'Müşteri'),
  bayi('bayi', 'Bayi'),
  platform('platform', 'Merkez'),
  unknown('unknown', 'Bilinmiyor');

  const Persona(this.code, this.label);
  final String code;
  final String label;

  static Persona fromCode(String? code) {
    for (final p in values) {
      if (p.code == code?.trim().asciiLower) return p;
    }
    return unknown;
  }
}

/// Bayi rolü yetkinliği (`akn:cap`): kod + isteğe bağlı tutar sınırı (boş = sınırsız).
@immutable
class Capability {
  const Capability(this.code, [this.limit]);

  factory Capability.fromJson(JsonReader r) =>
      Capability(r.str('code'), r.decOrNull('limit'));

  final String code;
  final double? limit;

  JsonMap toJson() => {'code': code, 'limit': limit};

  @override
  bool operator ==(Object other) =>
      other is Capability && other.code == code && other.limit == limit;

  @override
  int get hashCode => Object.hash(code, limit);
}

/// Bu kullanıcıya verilmiş onay vekâleti.
@immutable
class Delegation {
  const Delegation({
    required this.fromUserName,
    required this.approvalType,
    this.validTo,
  });

  factory Delegation.fromJson(JsonReader r) => Delegation(
    fromUserName: r.str('fromUserName'),
    approvalType: r.enumOf('approvalType', ApprovalType.fromCode),
    validTo: r.dateUtc('validTo'),
  );

  final String fromUserName;
  final ApprovalType approvalType;
  final DateTime? validTo;

  JsonMap toJson() => {
    'fromUserName': fromUserName,
    'approvalType': approvalType.code,
    'validTo': validTo?.toIso8601String(),
  };
}

/// `GET me/access` (spec B.3 `MeAccessDto`). Ne gösterileceğine yalnızca bu karar verir:
/// sayfa yetkileri `"PageCode:PermCode"` (ör. `StationOrders:Gorur`) ve yetkinlikler.
/// Rol adına göre karar verilmez (bayiler özel rol oluşturur); bkz. `AccessPolicy`.
@immutable
class MeAccess {
  const MeAccess({
    required this.userId,
    required this.userName,
    required this.displayName,
    this.email,
    this.phoneMasked,
    required this.persona,
    this.roles = const [],
    this.stationId,
    this.stationTitle,
    this.customerId,
    this.customerTitle,
    this.customerUserRoleCode,
    this.bayiRoleCodes = const [],
    this.bayiRoleNames = const [],
    this.pages = const {},
    this.capabilities = const [],
    this.delegations = const [],
    this.accessVersion,
    this.isFieldSalesFlag = false,
    this.isStationOwner = false,
    this.assignedOpenShipments = 0,
    this.phoneVerified = false,
    this.customerUserRoleLabel,
    this.signingCapabilities,
    this.approverUnits = const [],
    this.companyApprovalsEnabled,
  });

  factory MeAccess.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return MeAccess(
      userId: r.str('userId'),
      userName: r.str('userName'),
      displayName: r.nonEmpty('displayName') ?? r.str('userName'),
      email: r.nonEmpty('email'),
      phoneMasked: r.nonEmpty('phoneMasked'),
      persona: Persona.fromCode(r.strOrNull('persona')),
      roles: List.unmodifiable(r.strings('roles')),
      stationId: r.intOrNull('stationId'),
      stationTitle: r.nonEmpty('stationTitle'),
      customerId: r.intOrNull('customerId'),
      customerTitle: r.nonEmpty('customerTitle'),
      customerUserRoleCode: r.intOrNull('customerUserRole'),
      bayiRoleCodes: List.unmodifiable(r.strings('bayiRoleCodes')),
      bayiRoleNames: List.unmodifiable(r.strings('bayiRoleNames')),
      pages: Set.unmodifiable(r.strings('pages')),
      capabilities: List.unmodifiable(
        r.list('capabilities', Capability.fromJson),
      ),
      delegations: List.unmodifiable(
        r.list('delegations', Delegation.fromJson),
      ),
      accessVersion: r.strOrNull('accessVersion'),
      isFieldSalesFlag: r.boolean('isFieldSales'),
      isStationOwner: r.boolean('isStationOwner'),
      assignedOpenShipments: r.integer('assignedOpenShipments'),
      phoneVerified: r.boolean('phoneVerified'),
      customerUserRoleLabel: r.nonEmpty('customerUserRoleLabel'),
      // Roller v5: alan yoksa ya da null ise "hesaplanmadı" (eski sunucu, müşteri, merkez).
      signingCapabilities: r['signingCapabilities'] is List
          ? List.unmodifiable(
              r.list('signingCapabilities', Capability.fromJson),
            )
          : null,
      approverUnits: List.unmodifiable(r.strings('approverUnits')),
      companyApprovalsEnabled: r.boolOrNull('companyApprovalsEnabled'),
    );
  }

  final String userId;
  final String userName;
  final String displayName;
  final String? email;
  final String? phoneMasked;
  final Persona persona;

  /// Kimlik rolleri: Admin, HeadOffice, Station, Customer, FieldSales.
  final List<String> roles;
  final int? stationId;
  final String? stationTitle;
  final int? customerId;
  final String? customerTitle;

  /// Sunucudaki ham değer (null = Yönetici).
  final int? customerUserRoleCode;

  /// Bayi rolü şablon kodları (owner, manager, finance_manager …); özel rollerde boş olabilir.
  final List<String> bayiRoleCodes;
  final List<String> bayiRoleNames;

  /// `"PageCode:PermCode"`.
  final Set<String> pages;
  final List<Capability> capabilities;
  final List<Delegation> delegations;

  /// Yetki sürümü; değişince menü ve rotalar yeniden kurulur.
  final String? accessVersion;

  /// Sunucunun `isFieldSales` bayrağı (FieldSales rolü). [roles] ile birlikte okunur; bkz.
  /// `AccessPolicy.isFieldSales`.
  final bool isFieldSalesFlag;

  /// Bayinin sahibi (`Station.UserId` = kullanıcı): hesap silme kapalıdır.
  final bool isStationOwner;

  /// Kullanıcıya şoför olarak atanmış açık sevkiyat sayısı (Planlandı, Yolda, İtirazlı). Sıfırdan büyükse
  /// "Teslimatlarım" şoför rolü olmayan personelde de görünür (spec A.2).
  final int assignedOpenShipments;

  /// Profildeki cep telefonu SMS ile doğrulandı (telefonla giriş için gerekli).
  final bool phoneVerified;

  /// Cari kullanıcısında şirket rolünün Türkçe adı ("Talep eden", "Onaylayan", "Yönetici").
  final String? customerUserRoleLabel;

  /// Roller v5: imzada kullanılabilen yetkinlikler. [capabilities] ile aynı biçim; bu bayide birimin
  /// onaycısı başkası olduğu için imzalanamayan `approve.*` kodları yoktur (vekâletler dahil değil). null =
  /// hesaplanmadı (eski sunucu; müşteri ve merkez): [capabilities] geçerlidir.
  final List<Capability>? signingCapabilities;

  /// Roller v5: kullanıcının onaycısı olduğu birimler (`management`, `sales`, `finance`; panelin sırasıyla).
  final List<String> approverUnits;

  /// Roller v5: müşteride şirket içi onay akışı açık mı (false = tek rol, akış kapalı). Bayi ve merkezde
  /// ve eski sunucuda null: eski davranış (açık) geçerlidir.
  final bool? companyApprovalsEnabled;

  /// İmza kararlarında okunacak yetkinlikler ([signingCapabilities] yoksa [capabilities]).
  List<Capability> get signingOrCapabilities =>
      signingCapabilities ?? capabilities;

  /// Şirket içi onay akışı açık mı (null = açık).
  bool get companyApprovals => companyApprovalsEnabled ?? true;

  CustomerUserRole get customerUserRole =>
      CustomerUserRole.fromCode(customerUserRoleCode);

  /// Çalıştığı yerin adı (bayi ya da cari).
  String? get organizationTitle =>
      persona == Persona.customer ? customerTitle : stationTitle;

  JsonMap toJson() => {
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
    'customerUserRole': customerUserRoleCode,
    'bayiRoleCodes': bayiRoleCodes,
    'bayiRoleNames': bayiRoleNames,
    'pages': pages.toList(),
    'capabilities': [for (final c in capabilities) c.toJson()],
    'delegations': [for (final d in delegations) d.toJson()],
    'accessVersion': accessVersion,
    'isFieldSales': isFieldSalesFlag,
    'isStationOwner': isStationOwner,
    'assignedOpenShipments': assignedOpenShipments,
    'phoneVerified': phoneVerified,
    'customerUserRoleLabel': customerUserRoleLabel,
    'signingCapabilities': signingCapabilities == null
        ? null
        : [for (final c in signingCapabilities!) c.toJson()],
    'approverUnits': approverUnits,
    'companyApprovalsEnabled': companyApprovalsEnabled,
  };

  /// Menüyü ve rotaları etkileyen alanların parmak izi (yalnızca bunlar değişince yeniden kurulur).
  String get layoutKey => [
    userId,
    persona.code,
    accessVersion ?? '',
    (roles.toList()..sort()).join(','),
    (pages.toList()..sort()).join(','),
    (capabilities.map((c) => c.code).toList()..sort()).join(','),
    (bayiRoleCodes.toList()..sort()).join(','),
    '${customerUserRoleCode ?? ''}',
    // Atanmış teslimat olup olmaması "Teslimatlarım" sekmesini açar/kapatır (sayı değil).
    assignedOpenShipments > 0 ? 'driver' : '',
    isFieldSalesFlag ? 'fs' : '',
    isStationOwner ? 'own' : '',
    // Roller v5: imza yetkinliği değişince (birim onaycısı atandı / kaldırıldı) Onaylar sekmesi yer
    // değiştirir; şirket içi onay kapanınca Talepler düşer.
    signingCapabilities == null
        ? '-'
        : (signingCapabilities!.map((c) => c.code).toList()..sort()).join(','),
    approverUnits.join(','),
    '${companyApprovalsEnabled ?? ''}',
  ].join('|');
}
