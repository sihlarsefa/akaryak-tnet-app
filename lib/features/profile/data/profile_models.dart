import 'package:flutter/foundation.dart';

import '../../../core/models/json.dart';

/// `GET me/profile` (`UserProfileDto`). Tarihler UTC.
@immutable
class UserProfile {
  const UserProfile({
    required this.userId,
    required this.userName,
    required this.email,
    required this.displayName,
    this.phoneNumber,
    this.role,
    this.roleLabel,
    this.organizationTitle,
    this.organizationCode,
    this.lastLoginAt,
    this.createdAt,
    this.emailConfirmed = false,
    this.twoFactorRequired = false,
  });

  factory UserProfile.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return UserProfile(
      userId: r.str('userId'),
      userName: r.str('userName'),
      email: r.str('email'),
      displayName: r.str('displayName'),
      phoneNumber: r.nonEmpty('phoneNumber'),
      role: r.nonEmpty('role'),
      roleLabel: r.nonEmpty('roleLabel'),
      organizationTitle: r.nonEmpty('organizationTitle'),
      organizationCode: r.nonEmpty('organizationCode'),
      lastLoginAt: r.dateUtc('lastLoginAtUtc'),
      createdAt: r.dateUtc('createdAtUtc'),
      emailConfirmed: r.boolean('emailConfirmed'),
      twoFactorRequired: r.boolean('twoFactorRequired'),
    );
  }

  final String userId;
  final String userName;
  final String email;
  final String displayName;
  final String? phoneNumber;
  final String? role;
  final String? roleLabel;
  final String? organizationTitle;
  final String? organizationCode;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;
  final bool emailConfirmed;

  /// Girişte SMS kodu isteniyor (telefon boş bırakılamaz).
  final bool twoFactorRequired;
}

/// `me/profile` PUT ve `me/change-password` sonucu (`AccountOperationResult`): hata mesajları Türkçe.
@immutable
class AccountOperationResult {
  const AccountOperationResult({
    required this.succeeded,
    this.errors = const [],
  });

  factory AccountOperationResult.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return AccountOperationResult(
      succeeded: r.boolean('succeeded'),
      errors: List.unmodifiable(r.strings('errors')),
    );
  }

  final bool succeeded;
  final List<String> errors;

  /// Gövde bu biçimde mi (`succeeded` alanı var).
  static bool matches(Object? json) => JsonReader.of(json).has('succeeded');
}

/// `POST me/deletion-request` → 202 `AccountDeletionResultDto`.
@immutable
class AccountDeletionResult {
  const AccountDeletionResult({
    required this.message,
    this.requestId,
    this.scheduledFor,
  });

  factory AccountDeletionResult.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return AccountDeletionResult(
      message: r.nonEmpty('message') ?? '',
      requestId: r.nonEmpty('requestId'),
      scheduledFor: r.dateUtc('scheduledFor'),
    );
  }

  final String message;

  /// "SIL-XXXXXXXXXX" (destek görüşmesinde kullanılır).
  final String? requestId;

  /// Kişisel verilerin anonimleştirileceği en erken an (UTC).
  final DateTime? scheduledFor;
}
