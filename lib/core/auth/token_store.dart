import '../models/auth_models.dart';
import '../storage/secure_store.dart';

/// Belirteç deposu (spec C.4): erişim belirteci yalnızca bellekte; yenileme belirteci ve kullanıcı
/// kimliği güvenli depoda (`akn.refresh`, `akn.userId`).
class TokenStore {
  TokenStore(this._secure);

  final SecureStore _secure;

  String? _access;
  DateTime? _accessExpiresAt;
  String? _refresh;
  String? _userId;
  bool _loaded = false;

  String? get accessToken => _access;
  DateTime? get accessExpiresAt => _accessExpiresAt;
  String? get refreshToken => _refresh;
  String? get userId => _userId;
  bool get hasRefreshToken => _refresh != null && _refresh!.isNotEmpty;

  /// Erişim belirteci [margin] içinde dolacak mı (yoksa da `true`).
  bool accessExpiresWithin(Duration margin, {DateTime? now}) {
    final exp = _accessExpiresAt;
    if (_access == null || exp == null) return true;
    return exp.isBefore((now ?? DateTime.now().toUtc()).add(margin));
  }

  /// Güvenli depodan yükler (açılışta bir kez).
  Future<void> load() async {
    if (_loaded) return;
    _refresh = await _secure.read(SecureKeys.refresh);
    _userId = await _secure.read(SecureKeys.userId);
    _loaded = true;
  }

  Future<void> save(AuthTokens tokens) async {
    _access = tokens.accessToken;
    _accessExpiresAt = tokens.accessExpiresAt;
    _refresh = tokens.refreshToken;
    _userId = tokens.userId;
    _loaded = true;
    await _secure.write(SecureKeys.refresh, tokens.refreshToken);
    await _secure.write(SecureKeys.userId, tokens.userId);
  }

  /// Erişim belirtecini düşürür (bir sonraki istek yenilemeyi tetikler).
  void expireAccess() {
    _access = null;
    _accessExpiresAt = null;
  }

  /// Oturumu siler (cihaz kimliği kalır).
  Future<void> clear() async {
    _access = null;
    _accessExpiresAt = null;
    _refresh = null;
    _userId = null;
    _loaded = true;
    await _secure.delete(SecureKeys.refresh);
    await _secure.delete(SecureKeys.userId);
  }
}
