import '../models/auth_models.dart';
import '../storage/secure_store.dart';

/// Belirteç deposu (spec C.4): erişim belirteci yalnızca bellekte; yenileme belirteci ve kullanıcı
/// kimliği güvenli depoda (`akn.refresh`, `akn.userId`).
///
/// Test derlemesinin demo oturumu (giriş ekranındaki demo kartı; belirteçler uygulama içi sahte
/// sunucunun) yenileme belirtecini [demoTag] önekiyle yazar. Önek belirteçle aynı değerdedir: ayrı bir
/// işaret gibi belirteçten kopamaz, yarıda kalan bir yazma da onu "canlı" gösteremez. Demo oturumu
/// süreçle sınırlıdır: soğuk açılışta [load] önekli belirteci belleğe almaz ([staleDemo]); oturum
/// denetleyicisi demo kullanıcısının yerel verisini siler ve giriş ekranı açılır. Böylece sahte belirteç
/// canlı API'ye hiçbir yoldan (istek başlığı, yenileme, `auth/revoke`) gitmez.
class TokenStore {
  TokenStore(this._secure);

  /// Demo oturumunun yenileme belirtecinin güvenli depodaki öneki.
  static const demoTag = 'demo:';

  final SecureStore _secure;

  String? _access;
  DateTime? _accessExpiresAt;
  String? _refresh;
  String? _userId;
  bool _loaded = false;
  bool _demo = false;
  bool _staleDemo = false;

  String? get accessToken => _access;
  DateTime? get accessExpiresAt => _accessExpiresAt;
  String? get refreshToken => _refresh;
  String? get userId => _userId;
  bool get hasRefreshToken => _refresh != null && _refresh!.isNotEmpty;

  /// Bellekteki belirteçler test derlemesinin demo oturumuna (sahte sunucuya) ait.
  bool get isDemo => _demo;

  /// [load] önceki çalıştırmadan kalan bir demo oturumu buldu: belirteç yüklenmedi, [userId] demo
  /// kullanıcısıdır (yerel verisi silinmeli). [clear] ve [save] sıfırlar.
  bool get staleDemo => _staleDemo;

  /// Erişim belirteci [margin] içinde dolacak mı (yoksa da `true`).
  bool accessExpiresWithin(Duration margin, {DateTime? now}) {
    final exp = _accessExpiresAt;
    if (_access == null || exp == null) return true;
    return exp.isBefore((now ?? DateTime.now().toUtc()).add(margin));
  }

  /// Güvenli depodan yükler (açılışta bir kez). Önekli (demo) belirteç yüklenmez: [staleDemo].
  Future<void> load() async {
    if (_loaded) return;
    final refresh = await _secure.read(SecureKeys.refresh);
    _userId = await _secure.read(SecureKeys.userId);
    if (refresh != null && refresh.startsWith(demoTag)) {
      _refresh = null;
      _staleDemo = true;
    } else {
      _refresh = refresh;
    }
    _loaded = true;
  }

  /// Belirteçleri yazar. [demo]: girişte oturumun türü (test derlemesinin demo oturumu mu); null ise
  /// (yenileme, aynı oturum) önceki tür korunur.
  Future<void> save(AuthTokens tokens, {bool? demo}) async {
    _access = tokens.accessToken;
    _accessExpiresAt = tokens.accessExpiresAt;
    _refresh = tokens.refreshToken;
    _userId = tokens.userId;
    _demo = demo ?? _demo;
    _staleDemo = false;
    _loaded = true;
    await _secure.write(
      SecureKeys.refresh,
      _demo ? '$demoTag${tokens.refreshToken}' : tokens.refreshToken,
    );
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
    _demo = false;
    _staleDemo = false;
    _loaded = true;
    await _secure.delete(SecureKeys.refresh);
    await _secure.delete(SecureKeys.userId);
  }
}
