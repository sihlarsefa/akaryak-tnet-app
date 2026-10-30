import 'package:flutter/foundation.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/models/models.dart';

/// Personelin bu bayideki rolü (`UserBayiRoleDto`).
@immutable
class StaffRole {
  const StaffRole({
    required this.roleId,
    required this.roleName,
    this.templateCode,
    this.roleIsActive = true,
    this.isRetired = false,
  });

  factory StaffRole.fromJson(JsonReader r) => StaffRole(
    roleId: r.integer('roleId'),
    roleName: r.str('roleName'),
    templateCode: r.nonEmpty('templateCode'),
    roleIsActive: r.boolean('roleIsActive', true),
    isRetired: r.boolean('isRetired'),
  );

  final int roleId;

  /// Sunucunun etiketi (panelle aynı; pasif rolde "Görüntüleyici (pasif)").
  final String roleName;
  final String? templateCode;
  final bool roleIsActive;

  /// Roller v5: pasif (emekli) rol. Yeni atamaya kapalıdır ama yetki vermeye devam eder: gizlenmez,
  /// "(pasif)" etiketiyle gösterilir.
  final bool isRetired;

  /// Rol adı (boşsa şablon adı; pasif rolde " (pasif)" ekiyle).
  String get label => roleName.trim().isNotEmpty
      ? roleName
      : BayiRoleCodes.label(
          BayiRoleCodes.name(templateCode ?? ''),
          passive: isRetired,
        );

  /// Şoför rolü (Teslimatlarım kullanır).
  bool get isDriver => templateCode == BayiRoleCodes.driver;
}

/// `GET stations/me/staff` satırı (`StationStaffDto`). Tarihler UTC.
@immutable
class StaffMember {
  const StaffMember({
    required this.userId,
    required this.displayName,
    this.email = '',
    this.phoneNumber,
    this.isActive = true,
    this.isFieldSales = false,
    this.permissionGroupName,
    this.portfolioCount = 0,
    this.createdAt,
    this.lastLoginAt,
    this.roles = const [],
    this.approverOf = const [],
    this.needsReview = false,
  });

  factory StaffMember.fromJson(JsonReader r) => StaffMember(
    userId: r.str('userId'),
    displayName: r.nonEmpty('displayName') ?? r.str('email'),
    email: r.str('email'),
    phoneNumber: r.nonEmpty('phoneNumber'),
    isActive: r.boolean('isActive', true),
    isFieldSales: r.boolean('isFieldSales'),
    permissionGroupName: r.nonEmpty('permissionGroupName'),
    portfolioCount: r.integer('portfolioCount'),
    createdAt: r.dateUtc('createdAt'),
    lastLoginAt: r.dateUtc('lastLoginAt'),
    roles: List.unmodifiable(r.list('bayiRoles', StaffRole.fromJson)),
    approverOf: List.unmodifiable(r.strings('approverOf')),
    needsReview: r.boolean('needsReview'),
  );

  final String userId;
  final String displayName;
  final String email;
  final String? phoneNumber;
  final bool isActive;
  final bool isFieldSales;
  final String? permissionGroupName;
  final int portfolioCount;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
  final List<StaffRole> roles;

  /// Roller v5: onaycısı olduğu birimler (`management`, `sales`, `finance`; "Onaycı · Finans" çipi).
  final List<String> approverOf;

  /// Roller v5: rolü otomatik taşındı ve pasif, gözden geçirilmeli ("İncelenecek" çipi).
  final bool needsReview;

  /// Onaycı çiplerinin metni ("Onaycı · Finans").
  List<String> get approverLabels => [
    for (final u in approverOf) 'Onaycı · ${ApproverUnits.shortLabel(u)}',
  ];

  /// Gösterilecek rol etiketleri (rol düzeni yoksa eski yetki grubu).
  List<String> get roleLabels {
    final out = <String>[
      for (final r in roles)
        if (r.roleIsActive) r.label,
    ];
    if (out.isEmpty && permissionGroupName != null) {
      out.add(permissionGroupName!);
    }
    if (isFieldSales &&
        !roles.any((r) => r.templateCode == BayiRoleCodes.fieldRep)) {
      out.add('Saha satış');
    }
    return out;
  }

  StaffMember copyWith({bool? isActive}) => StaffMember(
    userId: userId,
    displayName: displayName,
    email: email,
    phoneNumber: phoneNumber,
    isActive: isActive ?? this.isActive,
    isFieldSales: isFieldSales,
    permissionGroupName: permissionGroupName,
    portfolioCount: portfolioCount,
    createdAt: createdAt,
    lastLoginAt: lastLoginAt,
    roles: roles,
    approverOf: approverOf,
    needsReview: needsReview,
  );
}
