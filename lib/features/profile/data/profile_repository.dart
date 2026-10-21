import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/network_providers.dart';
import 'profile_models.dart';

/// Profil ve hesap uçları (spec B.15 `me/profile`, `me/change-password`; B.3 `me/deletion-request`).
class ProfileRepository {
  ProfileRepository(this._api);

  final ApiClient _api;

  Future<UserProfile> profile() =>
      _api.get('me/profile', parse: UserProfile.fromJson, quiet403: true);

  /// Ad soyad ve telefon. Telefon değişiyorsa [currentPassword] zorunludur. Sunucu reddederse Türkçe
  /// mesajla [BusinessFailure].
  Future<void> updateProfile({
    required String displayName,
    String? phoneNumber,
    String? currentPassword,
  }) => _accountOperation('me/profile', put: true, {
    'displayName': displayName,
    'phoneNumber': phoneNumber,
    'currentPassword': ?currentPassword,
  });

  /// Şifre değiştir. Başarılı olunca sunucu güvenlik damgasını yeniler: tüm mobil oturumlar kapanır.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _accountOperation('me/change-password', {
    'currentPassword': currentPassword,
    'newPassword': newPassword,
  });

  /// Hesap silme talebi (şifreyle yeniden doğrulama; isteğe bağlı neden).
  Future<AccountDeletionResult> requestDeletion({
    required String password,
    String? reason,
  }) => _api.post(
    'me/deletion-request',
    body: {
      'password': password,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    },
    parse: AccountDeletionResult.fromJson,
  );

  /// Eski uçlar 400'de `AccountOperationResult {succeeded:false, errors[]}` döner (ProblemDetails değil);
  /// ortak hata eşlemesi bu gövdeyi okuyamadığı için 400 burada yanıt olarak alınır ve mesajları
  /// [BusinessFailure] olur. 401/403/5xx ve ağ hataları ortak yoldan geçer (belirteç yenileme dahil).
  Future<void> _accountOperation(
    String path,
    Map<String, Object?> body, {
    bool put = false,
  }) async {
    final Response<Object?> res;
    try {
      final options = Options(
        validateStatus: (s) => s != null && ((s >= 200 && s < 300) || s == 400),
      );
      res = put
          ? await _api.dio.put<Object?>(path, data: body, options: options)
          : await _api.dio.post<Object?>(path, data: body, options: options);
    } catch (e) {
      throw AppFailure.from(e);
    }
    final data = res.data;
    if (res.statusCode == 400) {
      if (AccountOperationResult.matches(data)) {
        final r = AccountOperationResult.fromJson(data);
        throw BusinessFailure(
          r.errors.isEmpty ? 'İşlem tamamlanamadı.' : r.errors.join(' '),
          statusCode: 400,
        );
      }
      throw AppFailure.fromResponse(400, data);
    }
    if (AccountOperationResult.matches(data)) {
      final r = AccountOperationResult.fromJson(data);
      if (!r.succeeded) {
        throw BusinessFailure(
          r.errors.isEmpty ? 'İşlem tamamlanamadı.' : r.errors.join(' '),
        );
      }
    }
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(apiClientProvider)),
);
