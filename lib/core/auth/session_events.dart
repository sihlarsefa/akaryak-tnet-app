import 'dart:async';

/// Ağ katmanından oturum denetleyicisine giden olaylar (döngüsel bağımlılık olmadan).
sealed class SessionEvent {
  const SessionEvent();
}

/// Yenileme başarısız ya da oturum sunucuda sonlandırıldı → çıkış.
final class SessionExpiredEvent extends SessionEvent {
  const SessionExpiredEvent(this.reason);

  /// `token_expired`, `session_revoked`, `unauthorized`, `refresh_failed`.
  final String reason;
}

/// 403 alındı → "Bu işlem için yetkiniz yok." + yetkiler yeniden okunur.
final class ForbiddenEvent extends SessionEvent {
  const ForbiddenEvent({this.message, this.quiet = false});
  final String? message;

  /// İstek sessiz işaretliyse bildirim gösterilmez (yalnızca yetkiler yenilenir).
  final bool quiet;
}

/// 426 alındı → güncelleme ekranı.
final class UpdateRequiredEvent extends SessionEvent {
  const UpdateRequiredEvent();
}

/// Belirteçler yenilendi (cihaz kaydı / push belirteci tazelenebilir).
final class TokensRefreshedEvent extends SessionEvent {
  const TokensRefreshedEvent();
}

/// Yayın kanalı.
class SessionEvents {
  final _controller = StreamController<SessionEvent>.broadcast();

  Stream<SessionEvent> get stream => _controller.stream;

  void emit(SessionEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  Future<void> dispose() => _controller.close();
}
