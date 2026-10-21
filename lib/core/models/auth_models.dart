import 'package:flutter/foundation.dart';

import 'json.dart';

/// Giriş isteğiyle gönderilen cihaz bilgisi (`DeviceInfoDto`).
@immutable
class DeviceInfo {
  const DeviceInfo({
    required this.deviceId,
    required this.platform,
    this.model,
    this.osVersion,
    this.appVersion,
    this.appBuild,
    this.pushToken,
  });

  final String deviceId;

  /// `ios` / `android`.
  final String platform;
  final String? model;
  final String? osVersion;
  final String? appVersion;
  final int? appBuild;
  final String? pushToken;

  DeviceInfo copyWith({String? pushToken}) => DeviceInfo(
    deviceId: deviceId,
    platform: platform,
    model: model,
    osVersion: osVersion,
    appVersion: appVersion,
    appBuild: appBuild,
    pushToken: pushToken ?? this.pushToken,
  );

  JsonMap toJson() => {
    'deviceId': deviceId,
    'platform': platform,
    'model': model,
    'osVersion': osVersion,
    'appVersion': appVersion,
    'appBuild': appBuild,
    'pushToken': pushToken,
  };
}

/// Erişim + yenileme belirteçleri (`AuthTokensDto`). Süreler UTC.
@immutable
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    this.refreshExpiresAt,
    required this.userId,
    this.displayName,
  });

  factory AuthTokens.fromJson(JsonReader r) => AuthTokens(
    accessToken: r.str('accessToken'),
    accessExpiresAt:
        r.dateUtc('accessExpiresAt') ??
        DateTime.now().toUtc().add(const Duration(minutes: 15)),
    refreshToken: r.str('refreshToken'),
    refreshExpiresAt: r.dateUtc('refreshExpiresAt'),
    userId: r.str('userId'),
    displayName: r.nonEmpty('displayName'),
  );

  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;
  final DateTime? refreshExpiresAt;
  final String userId;
  final String? displayName;

  bool get isValid => accessToken.isNotEmpty && refreshToken.isNotEmpty;

  @override
  String toString() => 'AuthTokens(user: $userId, expires: $accessExpiresAt)';
}

/// SMS kodu gönderildi (`OtpChallengeDto`). Hiç kullanıcı eşleşmese de aynı biçimde döner.
@immutable
class OtpChallenge {
  const OtpChallenge({
    required this.challengeId,
    required this.maskedPhone,
    required this.expiresInSeconds,
    required this.resendInSeconds,
  });

  factory OtpChallenge.fromJson(JsonReader r) => OtpChallenge(
    challengeId: r.str('challengeId'),
    maskedPhone: r.str('maskedPhone'),
    expiresInSeconds: r.integer('expiresInSeconds', 300),
    resendInSeconds: r.integer('resendInSeconds', 60),
  );

  final String challengeId;
  final String maskedPhone;
  final int expiresInSeconds;
  final int resendInSeconds;
}

/// Giriş sonucu (`AuthResultDto`): `ok` (belirteçler) ya da `twoFactorRequired` (kod ekranı).
@immutable
class AuthResult {
  const AuthResult({required this.status, this.tokens, this.challenge});

  factory AuthResult.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return AuthResult(
      status: r.str('status', 'ok'),
      tokens: r.objOrNull('tokens') == null
          ? null
          : AuthTokens.fromJson(r.obj('tokens')),
      challenge: r.objOrNull('challenge') == null
          ? null
          : OtpChallenge.fromJson(r.obj('challenge')),
    );
  }

  static const ok = 'ok';
  static const twoFactorRequired = 'twoFactorRequired';

  final String status;
  final AuthTokens? tokens;
  final OtpChallenge? challenge;

  bool get needsCode => status == twoFactorRequired && challenge != null;
  bool get isOk => status == ok && (tokens?.isValid ?? false);
}

/// Açık oturum (`SessionDto`), Profil → Oturumlar.
@immutable
class SessionInfo {
  const SessionInfo({
    required this.deviceId,
    required this.platform,
    this.model,
    this.appVersion,
    this.lastSeenAt,
    this.current = false,
  });

  factory SessionInfo.fromJson(JsonReader r) => SessionInfo(
    deviceId: r.str('deviceId'),
    platform: r.str('platform'),
    model: r.nonEmpty('model'),
    appVersion: r.nonEmpty('appVersion'),
    lastSeenAt: r.dateUtc('lastSeenAt'),
    current: r.boolean('current'),
  );

  final String deviceId;
  final String platform;
  final String? model;
  final String? appVersion;
  final DateTime? lastSeenAt;
  final bool current;
}
