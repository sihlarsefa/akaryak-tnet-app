import '../models/auth_models.dart';
import '../network/app_failure.dart';
import '../utils/log.dart';
import 'session_events.dart';
import 'token_store.dart';

/// Yenilemenin sonucu.
enum RefreshResult {
  /// Yeni belirteçler kaydedildi.
  refreshed,

  /// Yenileme belirteci geçersiz / iptal: oturum bitti.
  invalid,

  /// Geçici hata (çevrimdışı, zaman aşımı, 5xx): oturum korunur, istek başarısız döner.
  transient,
}

/// Aynı anda tek yenileme (spec C.4): eşzamanlı 401'ler aynı isteği bekler, sonra bir kez tekrar dener.
class TokenRefresher {
  TokenRefresher({required this.tokens, required this.call, this.events});

  final TokenStore tokens;

  /// `POST auth/refresh` çağrısı (yetki ara katmanını atlar).
  final Future<AuthTokens> Function(String refreshToken) call;
  final SessionEvents? events;

  Future<RefreshResult>? _inFlight;

  /// Şu an bir yenileme sürüyor mu.
  bool get isRefreshing => _inFlight != null;

  /// Yenileme yapar; sürmekte olan varsa onu bekler.
  Future<RefreshResult> refresh() {
    final running = _inFlight;
    if (running != null) return running;
    final f = _run();
    _inFlight = f;
    return f.whenComplete(() {
      if (identical(_inFlight, f)) _inFlight = null;
    });
  }

  Future<RefreshResult> _run() async {
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      return RefreshResult.invalid;
    }
    try {
      final next = await call(refreshToken);
      if (!next.isValid) return RefreshResult.invalid;
      await tokens.save(next);
      events?.emit(const TokensRefreshedEvent());
      return RefreshResult.refreshed;
    } catch (e) {
      final f = AppFailure.from(e);
      AppLog.warn('Belirteç yenilenemedi: ${f.runtimeType}');
      return switch (f) {
        UnauthorizedFailure() ||
        ForbiddenFailure() ||
        ValidationFailure() ||
        BusinessFailure() ||
        NotFoundFailure() => RefreshResult.invalid,
        _ => RefreshResult.transient,
      };
    }
  }
}
