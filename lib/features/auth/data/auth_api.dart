import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env/app_info.dart';
import '../../../core/models/auth_models.dart';
import '../../../core/models/json.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_providers.dart';

/// Kimlik özelliğinin çekirdek [AuthRepository]'de olmayan uçları (spec B.3):
/// kod yeniden gönderimi ve `app/config` yoklaması.
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
