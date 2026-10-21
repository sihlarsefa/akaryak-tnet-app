import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_controller.dart';
import '../auth/session_state.dart';
import '../models/unread_count.dart';
import '../network/network_providers.dart';
import '../utils/log.dart';
import 'push_providers.dart';

/// Zil ve Onaylarım rozetleri (`GET notifications/unread-count`).
///
/// Oturum açılınca okunur; push gelince, uygulama öne gelince ve ön plandayken düzenli yoklanır
/// (push yoksa 60 sn, varsa 5 dk). Bildirimler ekranı okundu işaretleyince [refresh] çağırır.
final unreadCountProvider =
    NotifierProvider<UnreadCountController, UnreadCount>(
      UnreadCountController.new,
    );

class UnreadCountController extends Notifier<UnreadCount> {
  Timer? _timer;
  bool _foreground = true;
  bool _disposed = false;
  Future<void>? _inFlight;

  @override
  UnreadCount build() {
    ref.listen<SessionState>(sessionControllerProvider, (prev, next) {
      final was = prev?.access?.userId;
      final now = next.access?.userId;
      if (now == null) {
        _stop();
        state = UnreadCount.zero;
      } else if (was != now ||
          (prev is SessionLocked && next is SessionAuthenticated)) {
        unawaited(refresh());
        _schedule();
      }
    });
    // Sağlayıcı oturum açıkken oluşturulduysa ilk okuma derleme bittikten sonra yapılır.
    if (ref.read(currentUserIdProvider) != null) {
      Future.microtask(() {
        if (_disposed) return;
        unawaited(refresh());
        _schedule();
      });
    }
    ref.listen(pushEventsProvider, (_, _) => unawaited(refresh()));
    ref.onDispose(() {
      _disposed = true;
      _stop();
    });
    return UnreadCount.zero;
  }

  Duration get _interval => ref.read(firebaseAvailableProvider)
      ? const Duration(minutes: 5)
      : const Duration(seconds: 60);

  void _schedule() {
    _timer?.cancel();
    if (!_foreground) return;
    _timer = Timer.periodic(_interval, (_) => unawaited(refresh()));
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Sayaçları sunucudan okur (eşzamanlı çağrılar birleşir). Hata fırlatmaz; önceki değer kalır.
  Future<void> refresh() {
    final running = _inFlight;
    if (running != null) return running;
    final f = _load();
    _inFlight = f;
    return f.whenComplete(() => _inFlight = null);
  }

  Future<void> _load() async {
    if (ref.read(sessionControllerProvider) is! SessionAuthenticated) return;
    try {
      final count = await ref
          .read(apiClientProvider)
          .get(
            'notifications/unread-count',
            parse: UnreadCount.fromJson,
            quiet403: true,
          );
      if (!_disposed) state = count;
    } catch (e) {
      AppLog.debug('Okunmamış sayısı alınamadı: $e');
    }
  }

  /// Yerel düzeltme (okundu işaretlendi) — sunucu yanıtı beklenmeden rozet güncellenir.
  void adjust({int notifications = 0, int approvals = 0}) {
    state = UnreadCount(
      notifications: (state.notifications + notifications).clamp(0, 1 << 30),
      approvals: (state.approvals + approvals).clamp(0, 1 << 30),
    );
  }

  /// Uygulama yaşam döngüsü (kabuk çağırır): arka planda yoklama durur.
  void handleLifecycle(AppLifecycleState lifecycle) {
    final fg = lifecycle == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    if (fg) {
      unawaited(refresh());
      if (ref.read(currentUserIdProvider) != null) _schedule();
    } else {
      _stop();
    }
  }
}
