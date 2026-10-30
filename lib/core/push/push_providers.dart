import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_repository.dart';
import '../auth/session_controller.dart';
import '../auth/session_state.dart';
import '../env/app_config_controller.dart';
import '../routing/route_access.dart';
import '../storage/prefs_store.dart';
import '../utils/app_messenger.dart';
import '../utils/log.dart';
import 'push_focus.dart';
import 'push_payload.dart';
import 'push_service.dart';

/// Firebase başlatıldı mı (bootstrap geçersiz kılar). false iken push kapalı, gelen kutusu yoklanır.
final firebaseAvailableProvider = Provider<bool>((ref) => false);

final pushServiceProvider = Provider<PushService>((ref) {
  PrefsStore? prefs;
  try {
    prefs = ref.watch(prefsStoreProvider);
  } catch (_) {
    // Tercihler yok (bazı testler): izin "bir kez soruldu" bilgisi saklanmaz.
    prefs = null;
  }
  final s = PushService(
    available: ref.watch(firebaseAvailableProvider),
    prefs: prefs,
  );
  ref.onDispose(s.dispose);
  return s;
});

/// Push olayları (spec C.4). Özellikler olay koduna / varlığa göre sağlayıcılarını tazeler:
///
/// ```dart
/// ref.listen(pushEventsProvider, (_, next) {
///   final p = next.valueOrNull?.payload;
///   if (p != null && p.entityType == 'Order' && p.entityId == orderId) ref.invalidateSelf();
/// });
/// ```
final pushEventsProvider = StreamProvider<PushEvent>(
  (ref) => ref.watch(pushServiceProvider).events,
);

/// Bildirim ayarları → "Anlık bildirimler" ("Bildirimler telefonuma gelsin") ana anahtarı: kullanıcı
/// bu telefona push istiyor mu. Varsayılan açık; seçim cihazda saklanır ([PrefKeys.pushOptIn]) ve
/// uygulama yeniden açıldığında, çıkışta ve yeniden girişte kalır. Kapalıyken cihaz kaydı
/// `pushEnabled: false` gider (bu telefona push gelmez); bildirim kutusu ve zil çalışmaya devam eder.
final pushOptInProvider = NotifierProvider<PushOptIn, bool>(PushOptIn.new);

class PushOptIn extends Notifier<bool> {
  @override
  bool build() => _prefs?.getBool(PrefKeys.pushOptIn, fallback: true) ?? true;

  PrefsStore? get _prefs {
    try {
      return ref.read(prefsStoreProvider);
    } catch (_) {
      // Tercihler yok (bazı testler): anahtar açık sayılır.
      return null;
    }
  }

  Future<void> _sync = Future<void>.value();

  /// Son anahtar değişikliğinin cihaz kaydı (arka planda sürer; testler bekler).
  Future<void> get pendingSync => _sync;

  /// Seçimi kaydeder; cihaz kaydı arkada güncellenir (belirteç iOS'ta gecikebilir, sayfa beklemez).
  Future<void> _save(bool on) async {
    state = on;
    await _prefs?.setBool(PrefKeys.pushOptIn, on);
    _sync = syncDevice();
  }

  /// Anahtarı açar. İzin hiç sorulmadıysa sistem penceresi açılır. Seçim kaydedilir ve cihaz kaydı
  /// `pushEnabled: true` olur; izin reddedilmiş olsa da (iOS o hâlde bildirimi göstermez) telefon
  /// ayarlarından izin verilince bildirimler hemen gelir. Döner: izin durumu —
  /// [PushPermission.denied] ise sayfa telefon ayarlarını önerir.
  Future<PushPermission> turnOn() async {
    final push = ref.read(pushServiceProvider);
    var permission = await push.permission();
    if (permission == PushPermission.notDetermined) {
      await push.requestPermission();
      permission = await push.permission();
    }
    await _save(true);
    return permission;
  }

  /// Anahtarı kapatır: cihaz kaydı `pushEnabled: false` (bu telefona push gelmez).
  Future<void> turnOff() => _save(false);

  /// Bu cihazın kaydı (`PUT devices/current`): `pushEnabled` = anahtar açık ve belirteç var. [user]
  /// verilmezse o anki oturum. Kayıt, başladığı oturumun API'sine gider: push belirteci beklenirken
  /// oturum değişirse (çıkış; test derlemesinde demo oturumunun bitişi) gönderilmez. Demo oturumunda
  /// kayıt sahte sunucuya gider; canlı sunucuya hiçbir şey kaydedilmez. Hata fırlatmaz.
  Future<void> syncDevice({String? user, String? token}) async {
    final who = user ?? ref.read(currentUserIdProvider);
    if (who == null) return;
    try {
      final repo = ref.read(authRepositoryProvider);
      final t = token ?? await ref.read(pushServiceProvider).token();
      if (ref.read(currentUserIdProvider) != who) return;
      await repo.registerDevice(pushToken: t, pushEnabled: state && t != null);
    } catch (e) {
      AppLog.debug('Cihaz kaydı güncellenemedi: $e');
    }
  }
}

/// Push yaşam döngüsü: ilk açılışta bildirim izni (bir kez), cihaz kaydı (giriş ve belirteç
/// yenilemede `PUT devices/current`, "Anlık bildirimler" anahtarına göre), çıkışta belirteç silme, ön
/// plan bildirimi, dokunulan push → derin bağlantı. Uygulama açılışta bir kez okur.
final pushCoordinatorProvider = Provider<PushCoordinator>((ref) {
  final c = PushCoordinator(ref);
  unawaited(c.start());
  ref.onDispose(c.dispose);
  return c;
});

class PushCoordinator {
  PushCoordinator(this.ref);

  final Ref ref;
  final List<StreamSubscription<Object?>> _subs = [];
  String? _registeredFor;
  bool _launchChecked = false;

  PushService get _push => ref.read(pushServiceProvider);

  Future<void> start() async {
    final push = _push;
    _subs.add(push.events.listen(_onEvent));
    _subs.add(
      push.tokenRefreshes.listen((t) {
        final user = ref.read(currentUserIdProvider);
        if (user != null) unawaited(_register(user, t));
      }),
    );
    ref.listen<SessionState>(sessionControllerProvider, (prev, next) {
      final user = next.access?.userId;
      if (next is SessionAuthenticated &&
          user != null &&
          user != _registeredFor) {
        _registeredFor = user;
        unawaited(_register(user));
      }
      if (next is SessionUnauthenticated && prev?.access != null) {
        _registeredFor = null;
        unawaited(push.deleteToken());
      }
      // İlk açılış izni oturum belli olunca (giriş ekranı ya da açık oturum) sorulur; kilit ekranında
      // biyometrik pencereyle çakışmasın diye kilit açılınca.
      if (!_launchChecked &&
          (next is SessionUnauthenticated || next is SessionAuthenticated)) {
        _launchChecked = true;
        unawaited(_askAtLaunch());
      }
    }, fireImmediately: true);
    await push.start();
  }

  /// İlk açılışta bir kez: izin hiç sorulmadıysa sistem penceresi ([PushService.requestAtFirstLaunch]).
  /// Pencere açık bir oturumda açıldıysa kayıt yeniden gönderilir (izin sonrası belirteç). Girişten
  /// önce verilen izin ayrıca bir şey gerektirmez: giriş, cihazı her zaman kaydeder.
  Future<void> _askAtLaunch() async {
    try {
      final asked = await _push.requestAtFirstLaunch();
      if (!asked) return;
      final session = ref.read(sessionControllerProvider);
      final user = session.access?.userId;
      if (session is SessionAuthenticated && user != null) {
        await _register(user);
      }
    } catch (e) {
      AppLog.debug('Açılışta bildirim izni istenemedi: $e');
    }
  }

  /// [user] için cihaz kaydı ([PushOptIn.syncDevice]: anahtar kapalıysa `pushEnabled: false`).
  Future<void> _register(String user, [String? token]) =>
      ref.read(pushOptInProvider.notifier).syncDevice(user: user, token: token);

  void _onEvent(PushEvent e) {
    final p = e.payload;
    switch (e.origin) {
      case PushOrigin.foreground:
        final text = p.body ?? p.title;
        if (text != null) {
          final policy = ref.read(accessPolicyProvider);
          final route = RouteAccess.resolvePushRoute(
            p.route,
            policy,
            ref.read(appConfigProvider).features,
          );
          // "Aç" de Bildirimler'deki satırla aynı bloğu açar (v4 tur 2).
          ref
              .read(appMessengerProvider)
              .show(
                AppMessage(
                  text,
                  title: p.title,
                  route: withPushFocus(
                    route,
                    p.type,
                    canQuote: !policy.isBayi || policy.quotesOrders,
                  ),
                ),
              );
        }
      case PushOrigin.tap:
        final pending = ref.read(pendingDeepLinkProvider.notifier);
        final session = ref.read(sessionControllerProvider);
        if (session is SessionAuthenticated || session is SessionLocked) {
          final policy = ref.read(accessPolicyProvider);
          pending.set(
            withPushFocus(
              RouteAccess.resolvePushRoute(
                p.route,
                policy,
                ref.read(appConfigProvider).features,
              ),
              p.type,
              canQuote: !policy.isBayi || policy.quotesOrders,
            ),
          );
        } else {
          // Soğuk açılış: dokunuş oturum geri yüklenmeden gelebilir (kişi henüz bilinmiyor). Rota
          // olduğu gibi saklanır; yönlendirici oturum açılınca kullanıcının yetkisiyle denetler,
          // izin yoksa `/notifications` açar. Şimdi denetlemek her rotayı reddederdi.
          pending.set(
            withPushFocus(RouteAccess.sanitizePushRoute(p.route), p.type),
            fromPush: true,
          );
        }
    }
  }

  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
  }
}
