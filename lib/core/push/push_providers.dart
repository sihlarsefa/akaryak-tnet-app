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

/// Push yaşam döngüsü: cihaz kaydı (giriş ve belirteç yenilemede `PUT devices/current`), çıkışta
/// belirteç silme, ön plan bildirimi, dokunulan push → derin bağlantı. Uygulama açılışta bir kez okur.
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

  PushService get _push => ref.read(pushServiceProvider);

  Future<void> start() async {
    final push = _push;
    _subs.add(push.events.listen(_onEvent));
    _subs.add(
      push.tokenRefreshes.listen((t) {
        if (ref.read(currentUserIdProvider) != null) unawaited(_register(t));
      }),
    );
    ref.listen<SessionState>(sessionControllerProvider, (prev, next) {
      final user = next.access?.userId;
      if (next is SessionAuthenticated &&
          user != null &&
          user != _registeredFor) {
        _registeredFor = user;
        unawaited(_register());
      }
      if (next is SessionUnauthenticated && prev?.access != null) {
        _registeredFor = null;
        unawaited(push.deleteToken());
      }
    }, fireImmediately: true);
    await push.start();
  }

  Future<void> _register([String? token]) async {
    try {
      final t = token ?? await _push.token();
      await ref
          .read(authRepositoryProvider)
          .registerDevice(pushToken: t, pushEnabled: t != null);
    } catch (e) {
      AppLog.debug('Cihaz kaydı güncellenemedi: $e');
    }
  }

  void _onEvent(PushEvent e) {
    final p = e.payload;
    switch (e.origin) {
      case PushOrigin.foreground:
        final text = p.body ?? p.title;
        if (text != null) {
          final route = RouteAccess.resolvePushRoute(
            p.route,
            ref.read(accessPolicyProvider),
            ref.read(appConfigProvider).features,
          );
          ref
              .read(appMessengerProvider)
              .show(AppMessage(text, title: p.title, route: route));
        }
      case PushOrigin.tap:
        final pending = ref.read(pendingDeepLinkProvider.notifier);
        final session = ref.read(sessionControllerProvider);
        if (session is SessionAuthenticated || session is SessionLocked) {
          pending.set(
            RouteAccess.resolvePushRoute(
              p.route,
              ref.read(accessPolicyProvider),
              ref.read(appConfigProvider).features,
            ),
          );
        } else {
          // Soğuk açılış: dokunuş oturum geri yüklenmeden gelebilir (kişi henüz bilinmiyor). Rota
          // olduğu gibi saklanır; yönlendirici oturum açılınca kullanıcının yetkisiyle denetler,
          // izin yoksa `/notifications` açar. Şimdi denetlemek her rotayı reddederdi.
          pending.set(RouteAccess.sanitizePushRoute(p.route), fromPush: true);
        }
    }
  }

  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
  }
}
