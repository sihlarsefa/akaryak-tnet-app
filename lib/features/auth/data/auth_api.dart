import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env/app_info.dart';
import '../../../core/models/auth_models.dart';
import '../../../core/models/json.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_providers.dart';

/// Profildeki cep telefonunun durumu (`GET me/access` içindeki `phoneMasked` + `phoneVerified`).
@immutable
class PhoneStatus {
  const PhoneStatus({this.phoneMasked, this.verified = false});

  factory PhoneStatus.fromAccessJson(Object? json) {
    final r = JsonReader.of(json);
    return PhoneStatus(
      phoneMasked: r.nonEmpty('phoneMasked'),
      verified: r.boolean('phoneVerified'),
    );
  }

  /// `0532 *** ** 01`; profilde telefon yoksa null.
  final String? phoneMasked;

  /// SMS ile doğrulandı (telefonla giriş açık).
  final bool verified;

  bool get hasPhone => phoneMasked != null;
}

/// Kimlik özelliğinin çekirdek [AuthRepository]'de olmayan uçları (spec B.3):
/// kod yeniden gönderimi, telefon doğrulama, `me/access` telefon durumu ve `app/config` yoklaması.
/// Giriş, OTP gönderimi ve kod doğrulama çekirdekteki `SessionController` üzerinden gider.
class AuthApi {
  AuthApi(this._api, this._info);

  final ApiClient _api;
  final AppInfo _info;

  /// `POST auth/challenge/resend` (anonim): aynı amaçla yeni kod. Bekleme süresi dolmadıysa 429.
  Future<OtpChallenge> resendChallenge(String challengeId) => _api.post(
    'auth/challenge/resend',
    anonymous: true,
    body: {'challengeId': challengeId},
    parse: (j) => OtpChallenge.fromJson(JsonReader.of(j)),
  );

  /// `POST me/phone/verify-start`: profildeki telefona doğrulama kodu.
  Future<OtpChallenge> startPhoneVerification() => _api.post(
    'me/phone/verify-start',
    body: const <String, Object?>{},
    parse: (j) => OtpChallenge.fromJson(JsonReader.of(j)),
  );

  /// `POST me/phone/verify` → 204: telefon doğrulandı, telefonla giriş açılır.
  Future<void> verifyPhone(String challengeId, String code) => _api.post<void>(
    'me/phone/verify',
    body: {'challengeId': challengeId, 'code': code.trim()},
  );

  /// `GET me/access` içinden telefon durumu (çekirdek modeli `phoneVerified` taşımaz).
  Future<PhoneStatus> phoneStatus() =>
      _api.get('me/access', parse: PhoneStatus.fromAccessJson, quiet403: true);

  /// `GET app/config?platform=` ham yanıtı (bakım, sözleşme sürümü, destek bağlantısı).
  Future<Object?> appConfig() => _api.get<Object?>(
    'app/config',
    query: {'platform': _info.platform},
    anonymous: true,
    parse: (j) => j,
  );
}

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider), ref.watch(appInfoProvider)),
);
