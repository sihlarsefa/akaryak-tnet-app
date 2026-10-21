import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../env/app_config_controller.dart';
import '../models/auth_models.dart';
import '../models/me_access.dart';
import '../network/app_failure.dart';
import '../network/interceptors/auth_interceptor.dart';
import '../network/network_providers.dart';
import '../offline/cache_store.dart';
import '../storage/prefs_store.dart';
import '../storage/user_drafts.dart';
import '../utils/app_messenger.dart';
import '../utils/external_activity.dart';
import '../utils/log.dart';
import 'access_policy.dart';
import 'auth_repository.dart';
import 'lock_settings.dart';
import 'session_cleanup.dart';
import 'session_events.dart';
import 'session_state.dart';

/// Oturum denetleyicisi (spec C.4).
///
/// - Açılış: [restore] yenileme belirteci varsa son `me/access`i önbellekten hemen açar (çevrimdışı
///   açılış), arka planda belirteci ve yetkileri tazeler.
/// - Giriş: [loginWithPassword] / [sendOtp] + [verifyCode] (2FA ve telefonla giriş aynı kod ekranı).
/// - Yetkiler öne gelince, 15 dakikada bir ve 403 sonrası yeniden okunur ([refreshAccess]).
/// - Yenileme başarısızsa "Oturumunuz sona erdi" ile çıkış; 426'da güncelleme ekranı.
/// - Biyometrik kilit açıksa açılışta ve arka planda 60 sn'den uzun kalınca kilitlenir.
final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Anlık erişim politikası (giriş yoksa [AccessPolicy.signedOut]).
final accessPolicyProvider = Provider<AccessPolicy>((ref) {
  final s = ref.watch(sessionControllerProvider);
  return AccessPolicy(s.access);
});

/// Oturumdaki kullanıcının kimliği (yoksa null).
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(sessionControllerProvider).access?.userId,
);

/// Çıkışın nedeni (spec D.7). Kullanıcı çıkarsa kullanıcı verisinin tümü silinir. Yeniden giriş
/// gerekiyorsa yarım işler ([UserDrafts]: teslim taslakları, sipariş sihirbazı ve sonucu belirsiz
/// gönderimin anahtarı, saha taslakları) korunur; aynı kullanıcı girince kaldığı yerden sürer, başka
/// kullanıcı girerse silinir. Belirteçler, yetkiler, önbellek, görseller, bildirimler ve rozet her
/// durumda silinir.
enum SignOutReason {
  /// "Çıkış yap", tüm cihazlardan çıkış, hesap kapatma.
  explicit,

  /// Oturum sona erdi ya da sunucuda kapatıldı (yenileme reddedildi).
  expired,

  /// Kilit ekranında "Şifreyle giriş yap".
  lockFallback,

  /// Şifre ya da telefon değişti; yeniden giriş.
  securityChanged;

  /// Yarım işler korunur (yalnızca kullanıcı çıkmadıysa).
  bool get keepsDrafts => this != explicit;
}

class SessionController extends Notifier<SessionState> {
  static const sessionExpiredMessage =
      'Oturumunuz sona erdi. Lütfen yeniden giriş yapın.';
  static const sessionRevokedMessage =
      'Oturumunuz kapatıldı. Lütfen yeniden giriş yapın.';
  static const accessRefreshInterval = Duration(minutes: 15);

  /// Uygulamanın açtığı dış etkinlikten (kamera, paylaşım, tarayıcı) dönüşte kilit için hoşgörü.
  static const externalActivityGrace = Duration(minutes: 10);

  Timer? _periodic;
  Timer? _forbiddenDebounce;
  DateTime? _pausedAt;
  bool _pausedForExternal = false;
  DateTime? _lastAccessFetch;
  bool _signingOut = false;

  @override
  SessionState build() {
    final sub = ref.read(sessionEventsProvider).stream.listen(_onEvent);
    ref.onDispose(() {
      sub.cancel();
      _periodic?.cancel();
      _forbiddenDebounce?.cancel();
    });
    return const SessionUnknown();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  // ------------------------------------------------------------------ Açılış

  /// Kayıtlı oturumu geri yükler. Hata fırlatmaz.
  Future<void> restore() async {
    final tokens = ref.read(tokenStoreProvider);
    await tokens.load();
    if (!tokens.hasRefreshToken) {
      state = const SessionUnauthenticated();
      return;
    }
    final userId = tokens.userId;
    final cached = userId == null ? null : await _readCachedAccess(userId);
    if (cached != null) {
      state = _openState(cached, fromCache: true);
      _startTimers();
      unawaited(refreshAccess(force: true));
      return;
    }
    try {
      final access = await _repo.meAccess();
      await _cacheAccess(access);
      state = _openState(access);
      _startTimers();
    } on AppFailure catch (f) {
      if (f is UnauthorizedFailure) {
        await _clearLocal(userId, keepDrafts: true);
        state = const SessionUnauthenticated(message: sessionExpiredMessage);
      } else {
        // Çevrimdışı ve önbellek yok: giriş ekranı; belirteç bir sonraki açılış için korunur.
        state = SessionUnauthenticated(
          message: f is OfflineFailure ? f.message : null,
        );
      }
    }
  }

  SessionState _openState(MeAccess access, {bool fromCache = false}) =>
      ref.read(biometricLockProvider)
      ? SessionLocked(access)
      : SessionAuthenticated(access, fromCache: fromCache);

  // ------------------------------------------------------------------ Giriş

  /// Kullanıcı adı / e-posta + şifre. 2FA gerekiyorsa [LoginNeedsCode]. Hatalar [AppFailure].
  Future<LoginOutcome> loginWithPassword(
    String userNameOrEmail,
    String password,
  ) async {
    final result = await _repo.login(userNameOrEmail, password);
    return _complete(result);
  }

  /// Telefonla giriş: SMS kodu gönderir.
  Future<OtpChallenge> sendOtp(String phone) => _repo.sendOtp(phone);

  /// Kodu doğrular (2FA ve telefonla giriş).
  Future<LoginOutcome> verifyCode(String challengeId, String code) async {
    final result = await _repo.verify(challengeId, code);
    return _complete(result);
  }

  Future<LoginOutcome> _complete(AuthResult result) async {
    if (result.needsCode) return LoginNeedsCode(result.challenge!);
    final t = result.tokens;
    if (!result.isOk || t == null) {
      throw const UnknownFailure('Giriş tamamlanamadı. Lütfen tekrar deneyin.');
    }
    final tokens = ref.read(tokenStoreProvider);
    final previousUser = tokens.userId;
    await tokens.save(t);
    try {
      final access = await _repo.meAccess();
      if (previousUser != null && previousUser != access.userId) {
        // Kullanıcı değişti: önceki kullanıcının önbelleği, görselleri ve bildirimleri temizlenir.
        await ref.read(cacheStoreProvider).clearUser(previousUser);
        await ref.read(prefsStoreProvider).clearUser(previousUser);
        await ref.read(cacheStoreProvider).clearSessionData();
        await ref.read(sessionCleanupProvider)(previousUser);
      }
      await _settleKeptDrafts(access.userId);
      await _cacheAccess(access);
      state = SessionAuthenticated(access);
      _startTimers();
      return LoginSucceeded(access);
    } catch (e) {
      await tokens.clear();
      throw AppFailure.from(e);
    }
  }

  // ------------------------------------------------------------------ Yetkiler

  /// `me/access` yeniden okur (sessiz; hata fırlatmaz). [force] değilse 60 sn içinde tekrar gitmez.
  Future<void> refreshAccess({bool force = false}) async {
    final current = state;
    if (current is! SessionAuthenticated && current is! SessionLocked) return;
    final last = _lastAccessFetch;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 60)) {
      return;
    }
    _lastAccessFetch = DateTime.now();
    try {
      final access = await _repo.meAccess();
      await _cacheAccess(access);
      final now = state;
      if (now is SessionLocked) {
        state = SessionLocked(access);
      } else if (now is SessionAuthenticated) {
        state = SessionAuthenticated(access);
      }
    } on AppFailure catch (f) {
      AppLog.debug('me/access yenilenemedi: ${f.runtimeType}');
    }
  }

  // ------------------------------------------------------------------ Kilit

  void lock() {
    final s = state;
    if (s is SessionAuthenticated) state = SessionLocked(s.me);
  }

  /// Kilit ekranı biyometrik doğrulamadan sonra çağırır.
  void unlock() {
    final s = state;
    if (s is SessionLocked) state = SessionAuthenticated(s.me);
  }

  // ------------------------------------------------------------------ Çıkış

  /// Çıkış: sunucuda oturumu kapatır (en fazla 5 sn beklenir), belirteçleri ve kullanıcı önbelleğini siler.
  ///
  /// Erişim belirteci dolmuşsa yalnızca çıkmak için yenileme yapılmaz: yenileme belirteci anonim
  /// `auth/revoke` ile iptal edilir (spec B.3, D.7). "Tüm cihazlardan çık" oturum ister (`auth/logout`).
  Future<void> signOut({
    String? message,
    bool allDevices = false,
    bool callServer = true,
    SignOutReason reason = SignOutReason.explicit,
  }) async {
    if (_signingOut) return;
    _signingOut = true;
    try {
      final tokens = ref.read(tokenStoreProvider);
      final refresh = tokens.refreshToken;
      if (callServer && refresh != null && refresh.isNotEmpty) {
        try {
          final expired = tokens.accessExpiresWithin(
            AuthInterceptor.refreshMargin,
          );
          await (expired && !allDevices
                  ? _repo.revoke(refresh)
                  : _repo.logout(allDevices: allDevices))
              .timeout(const Duration(seconds: 5));
        } catch (_) {
          // Sunucuya ulaşılamasa da yerel oturum kapanır.
        }
      }
      await _clearLocal(
        tokens.userId,
        keepDrafts: reason.keepsDrafts && !allDevices,
      );
      state = SessionUnauthenticated(message: message);
    } finally {
      _signingOut = false;
    }
  }

  /// Yerel oturum verisi (spec D.7): belirteçler, önbellek (yetkiler dahil), kullanıcı tercihleri,
  /// görsel önbelleği, gösterilen bildirimler ve uygulama simgesi rozeti. Bekleyen işlemler kalır;
  /// yalnızca sahibinin oturumunda çalışır (silmek için Profil → "Yine de çık").
  ///
  /// [keepDrafts] (istem dışı çıkış): kullanıcının yarım işleri ([UserDrafts]) kalır ve sahibi
  /// [PrefKeys.draftsOwner]'a yazılır; girişte [_settleKeptDrafts] karar verir.
  Future<void> _clearLocal(String? userId, {bool keepDrafts = false}) async {
    _periodic?.cancel();
    _periodic = null;
    _lastAccessFetch = null;
    await ref.read(tokenStoreProvider).clear();
    final cache = ref.read(cacheStoreProvider);
    final prefs = ref.read(prefsStoreProvider);
    final keep = keepDrafts && userId != null;
    final keepCache = keep
        ? UserDrafts.cacheKeyPrefixes(userId)
        : const <String>{};
    if (userId != null) {
      await cache.clearUser(userId, keepPrefixes: keepCache);
      await prefs.clearUser(
        userId,
        keep: keep ? UserDrafts.prefKeys(userId) : const {},
      );
    }
    await cache.clearSessionData(keepPrefixes: keepCache);
    if (keep) {
      await prefs.setString(PrefKeys.draftsOwner, userId);
    } else {
      // "Çıkış yap": önceden korunmuş yarım işler de gider.
      await _dropKeptDrafts(except: null);
    }
    try {
      await ref.read(sessionCleanupProvider)(userId);
    } catch (e) {
      AppLog.debug('Oturum temizliği tamamlanamadı: $e');
    }
  }

  /// Girişte: istem dışı çıkışta korunan yarım işler aynı kullanıcınınsa sürer, başkasınınsa silinir.
  Future<void> _settleKeptDrafts(String userId) =>
      _dropKeptDrafts(except: userId);

  Future<void> _dropKeptDrafts({required String? except}) async {
    final prefs = ref.read(prefsStoreProvider);
    final owner = prefs.getString(PrefKeys.draftsOwner);
    if (owner == null) return;
    if (owner != except) {
      await ref.read(cacheStoreProvider).clearUser(owner);
      await prefs.clearUser(owner);
    }
    await prefs.setString(PrefKeys.draftsOwner, null);
  }

  // ------------------------------------------------------------------ Yaşam döngüsü

  /// Uygulama yaşam döngüsü (kabuk çağırır).
  void handleLifecycle(AppLifecycleState lifecycle) {
    switch (lifecycle) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (_pausedAt == null) {
          _pausedAt = DateTime.now();
          // Kamera, paylaşım sayfası, tarayıcı: uygulamanın açtığı dış etkinlikten dönüş kilitlemez
          // (uzun süre dışarıda kalınırsa yine kilitlenir).
          _pausedForExternal = ExternalActivity.active;
        }
      case AppLifecycleState.resumed:
        final pausedAt = _pausedAt;
        final grace = _pausedForExternal
            ? externalActivityGrace
            : BiometricLockController.grace;
        _pausedAt = null;
        _pausedForExternal = false;
        if (pausedAt != null &&
            ref.read(biometricLockProvider) &&
            DateTime.now().difference(pausedAt) > grace) {
          lock();
        }
        unawaited(refreshAccess());
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _startTimers() {
    _periodic?.cancel();
    _periodic = Timer.periodic(
      accessRefreshInterval,
      (_) => unawaited(refreshAccess(force: true)),
    );
  }

  void _onEvent(SessionEvent event) {
    switch (event) {
      case SessionExpiredEvent(:final reason):
        final s = state;
        if (s is SessionAuthenticated || s is SessionLocked) {
          unawaited(
            signOut(
              message: reason == 'session_revoked'
                  ? sessionRevokedMessage
                  : sessionExpiredMessage,
              callServer: false,
              reason: SignOutReason.expired,
            ),
          );
        }
      case ForbiddenEvent(:final quiet, :final message):
        if (!quiet) {
          ref
              .read(appMessengerProvider)
              .warning(message ?? 'Bu işlem için yetkiniz yok.');
        }
        _forbiddenDebounce?.cancel();
        _forbiddenDebounce = Timer(
          const Duration(seconds: 2),
          () => unawaited(refreshAccess()),
        );
      case UpdateRequiredEvent():
        ref.read(appConfigProvider.notifier).markUpdateRequired();
      case TokensRefreshedEvent():
        break;
    }
  }

  // ------------------------------------------------------------------ Önbellek

  Future<MeAccess?> _readCachedAccess(String userId) async {
    final entry = await ref
        .read(cacheStoreProvider)
        .read(CacheKeys.user(userId, CacheKeys.meAccess));
    if (entry == null) return null;
    final access = MeAccess.fromJson(entry.value);
    return access.userId == userId ? access : null;
  }

  Future<void> _cacheAccess(MeAccess access) => ref
      .read(cacheStoreProvider)
      .write(
        CacheKeys.user(access.userId, CacheKeys.meAccess),
        access.toJson(),
        userId: access.userId,
      );
}
