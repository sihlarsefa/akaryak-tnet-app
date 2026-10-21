import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../env/app_info.dart';
import '../models/auth_models.dart';
import '../models/json.dart';
import '../models/me_access.dart';
import '../network/api_client.dart';
import '../network/network_providers.dart';

/// Oturum uçları (spec B.3). Ekranlar (A1) doğrudan değil [SessionController] üzerinden kullanır.
class AuthRepository {
  AuthRepository(this.api, this.info);

  final ApiClient api;
  final AppInfo info;

  /// Şifreyle giriş. 2FA gerekiyorsa sonuç `twoFactorRequired` + challenge döner.
  Future<AuthResult> login(
    String userNameOrEmail,
    String password, {
    String? pushToken,
  }) => api.post(
    'auth/login',
    anonymous: true,
    body: {
      'userNameOrEmail': userNameOrEmail.trim(),
      'password': password,
      'device': info.toDeviceInfo(pushToken: pushToken).toJson(),
    },
    parse: AuthResult.fromJson,
  );

  /// Telefonla giriş: SMS kodu gönderir. Numara eşleşmese de aynı yanıt döner.
  Future<OtpChallenge> sendOtp(String phone, {String? pushToken}) => api.post(
    'auth/otp/send',
    anonymous: true,
    body: {
      'phone': phone,
      'device': info.toDeviceInfo(pushToken: pushToken).toJson(),
    },
    parse: (j) => OtpChallenge.fromJson(JsonReader.of(j)),
  );

  /// SMS kodunu doğrular (telefonla giriş ve 2FA).
  Future<AuthResult> verify(
    String challengeId,
    String code, {
    String? pushToken,
  }) => api.post(
    'auth/verify',
    anonymous: true,
    body: {
      'challengeId': challengeId,
      'code': code.trim(),
      'device': info.toDeviceInfo(pushToken: pushToken).toJson(),
    },
    parse: AuthResult.fromJson,
  );

  /// Sunucuda oturumu kapatır (yenileme belirteci ve push belirteci silinir).
  Future<void> logout({bool allDevices = false}) =>
      api.post<void>('auth/logout', body: {'allDevices': allDevices});

  /// Erişim belirteci dolmuşken çıkış: yenileme belirtecini anonim iptal eder (her zaman 204).
  Future<void> revoke(String refreshToken) => api.post<void>(
    'auth/revoke',
    anonymous: true,
    body: {'refreshToken': refreshToken, 'deviceId': info.deviceId},
  );

  Future<List<SessionInfo>> sessions() => api.get(
    'auth/sessions',
    parse: (j) => JsonReader.parseList(j, SessionInfo.fromJson),
  );

  Future<void> revokeSession(String deviceId) =>
      api.delete<void>('auth/sessions/${Uri.encodeComponent(deviceId)}');

  Future<MeAccess> meAccess() =>
      api.get('me/access', parse: MeAccess.fromJson, quiet403: true);

  /// Hesap silme talebi → sunucunun Türkçe mesajı.
  Future<String> requestDeletion(String reason) => api.post(
    'me/deletion-request',
    body: {'reason': reason},
    parse: (j) => JsonReader.of(j).str('message', 'Talebiniz alındı.'),
  );

  /// Cihaz kaydı / push belirteci (`PUT devices/current`).
  Future<void> registerDevice({String? pushToken, bool pushEnabled = true}) =>
      api.put<void>(
        'devices/current',
        body: {
          'pushToken': pushToken,
          'pushEnabled': pushEnabled,
          'appVersion': info.appVersion,
          'appBuild': info.appBuild,
          'osVersion': info.osVersion,
          'locale': info.locale,
        },
      );
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) =>
      AuthRepository(ref.watch(apiClientProvider), ref.watch(appInfoProvider)),
);
