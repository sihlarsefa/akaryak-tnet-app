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
  });

  factory StaffRole.fromJson(JsonReader r) => StaffRole(
    roleId: r.integer('roleId'),
    roleName: r.str('roleName'),
    templateCode: r.nonEmpty('templateCode'),
    roleIsActive: r.boolean('roleIsActive', true),
  );

  final int roleId;
  final String roleName;
  final String? templateCode;
  final bool roleIsActive;

  /// Rol adı (boşsa şablon adı).
  String get label => roleName.trim().isNotEmpty
      ? roleName
      : BayiRoleCodes.name(templateCode ?? '');

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
  );
}
