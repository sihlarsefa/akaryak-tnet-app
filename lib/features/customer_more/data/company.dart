import 'package:flutter/foundation.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';

/// Şirket kullanıcısı (`CompanyUserDto`). `createdAt` ve `lastLoginAt` sunucuda UTC saklanır.
@immutable
class CompanyUser {
  const CompanyUser({
    required this.userId,
    required this.displayName,
    this.email = '',
    this.phoneNumber,
    required this.role,
    this.roleLabel,
    this.isActive = true,
    this.isSelf = false,
    this.createdAt,
    this.lastLoginAt,
    this.invitationPending = false,
    this.invitationQueued = false,
    this.isMainUser = false,
  });

  factory CompanyUser.fromJson(JsonReader r) => CompanyUser(
    userId: r.str('userId'),
    displayName: r.nonEmpty('displayName') ?? r.str('email'),
    email: r.str('email'),
    phoneNumber: r.nonEmpty('phoneNumber'),
    role: CustomerUserRole.fromCode(r.intOrNull('role')),
    roleLabel: r.nonEmpty('roleLabel'),
    isActive: r.boolean('isActive', true),
    isSelf: r.boolean('isSelf'),
    createdAt: r.dateUtc('createdAt'),
    lastLoginAt: r.dateUtc('lastLoginAt'),
    invitationPending: r.boolean('invitationPending'),
    invitationQueued: r.boolean('invitationQueued'),
    isMainUser: r.boolean('isMainUser'),
  );

  final String userId;
  final String displayName;
  final String email;
  final String? phoneNumber;
  final CustomerUserRole role;
  final String? roleLabel;
  final bool isActive;
  final bool isSelf;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  /// Şifre belirleme bağlantısı henüz kullanılmadı (e-posta doğrulanmadı).
  final bool invitationPending;

  /// Ekleme / bağlantı gönderme sonucunda: e-posta kuyruğa alındı.
  final bool invitationQueued;

  /// Roller v5: şirketin ana kullanıcısı (`Customer.UserId`; "Ana kullanıcı" çipi). Onu yalnızca merkez
  /// ya da kendisi pasifleştirebilir.
  final bool isMainUser;

  String get displayRole => roleLabel ?? role.label;
}

/// Rol açıklamaları (web `CompanyUsers.cshtml`). Roller v5: şirket içi onay kapalıyken rol seçimi ve
/// açıklamaları gösterilmez (tek rol); bu metinler eski akış (eski sunucu, geçiş yapılmamış şirket) içindir.
String companyRoleHint(CustomerUserRole role) => switch (role) {
  CustomerUserRole.requester =>
    'Sipariş hazırlar; eşik üstü siparişi onaya gider.',
  CustomerUserRole.approver =>
    'Doğrudan sipariş verir, talepleri onaylar veya reddeder.',
  CustomerUserRole.admin =>
    'Onaylayan yetkileri + kullanıcılar ve onay kuralı.',
  CustomerUserRole.unknown => '',
};

/// Şirket içi onay eşikleri (`CustomerApprovalSettingsDto`); ikisi de boşsa onay kapalı.
@immutable
class ApprovalThresholds {
  const ApprovalThresholds({
    this.aboveLitres,
    this.aboveAmount,
    this.updatedAt,
  });

  factory ApprovalThresholds.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return ApprovalThresholds(
      aboveLitres: r.decOrNull('requireApprovalAboveLitres'),
      aboveAmount: r.decOrNull('requireApprovalAboveAmount'),
      updatedAt: r.dateUtc('updatedAt'),
    );
  }

  final double? aboveLitres;
  final double? aboveAmount;
  final DateTime? updatedAt;

  bool get isConfigured => aboveLitres != null || aboveAmount != null;

  static const maxLitres = 100000000.0;
  static const maxAmount = 100000000000.0;

  /// Sunucu kuralı (`ValidateThresholds`): litre ≥ 0 (0 = her sipariş), tutar > 0.
  static String? validate(double? litres, double? amount) {
    if (litres != null && litres < 0) return 'Litre eşiği negatif olamaz.';
    if (litres != null && litres > maxLitres) return 'Litre eşiği çok büyük.';
    if (amount != null && amount <= 0) {
      return 'Tutar eşiği sıfırdan büyük olmalı.';
    }
    if (amount != null && amount > maxAmount) return 'Tutar eşiği çok büyük.';
    return null;
  }
}
