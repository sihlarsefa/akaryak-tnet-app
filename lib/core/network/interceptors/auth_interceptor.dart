import 'package:dio/dio.dart';

import '../../auth/session_events.dart';
import '../../auth/token_refresher.dart';
import '../../auth/token_store.dart';
import '../app_failure.dart';

/// İsteğe özel ayarlar (`Options(extra: {...})`).
abstract final class ApiExtra {
  /// Yetki başlığı eklenmez, 401'de yenileme yapılmaz (giriş, OTP, yenileme, app/config).
  static const skipAuth = 'akn.skipAuth';

  /// Yenilemeden sonraki tekrar (ikinci kez denenmez).
  static const retried = 'akn.retried';

  /// 403'te genel "yetkiniz yok" bildirimi gösterilmez (ekran kendisi gösterir).
  static const quiet403 = 'akn.quiet403';
}

/// Bearer belirteci ekler; 401 `token_expired` / `unauthorized` alınca tek bir yenileme yapar
/// (eşzamanlı istekler bekler), sonra isteği bir kez tekrar dener. Yenileme başarısızsa
/// "Oturumunuz sona erdi" ile çıkış olayı yayınlar. 403 ve 426'yı oturum denetleyicisine bildirir.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.dio,
    required this.tokens,
    required this.refresher,
    required this.events,
  });

  final Dio dio;
  final TokenStore tokens;
  final TokenRefresher refresher;
  final SessionEvents events;

  /// Erişim belirteci bu süre içinde dolacaksa istekten önce yenilenir.
  static const refreshMargin = Duration(seconds: 30);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[ApiExtra.skipAuth] == true) {
      handler.next(options);
      return;
    }
    if (tokens.hasRefreshToken && tokens.accessExpiresWithin(refreshMargin)) {
      final result = await refresher.refresh();
      if (result == RefreshResult.invalid) {
        events.emit(const SessionExpiredEvent('refresh_failed'));
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            error: const UnauthorizedFailure('refresh_failed'),
          ),
        );
        return;
      }
    }
    final access = tokens.accessToken;
    if (access != null) options.headers['Authorization'] = 'Bearer $access';
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final status = err.response?.statusCode;
    final anonymous = options.extra[ApiExtra.skipAuth] == true;

    if (status == 426) events.emit(const UpdateRequiredEvent());
    if (status == 403 && !anonymous) {
      events.emit(
        ForbiddenEvent(quiet: options.extra[ApiExtra.quiet403] == true),
      );
    }
    if (status != 401 || anonymous || options.extra[ApiExtra.retried] == true) {
      handler.next(err);
      return;
    }

    final failure = AppFailure.fromResponse(401, err.response?.data);
    final reason = failure is UnauthorizedFailure
        ? failure.reason
        : 'unauthorized';
    if (reason == 'session_revoked') {
      events.emit(const SessionExpiredEvent('session_revoked'));
      handler.next(err);
      return;
    }

    // Başka bir istek bu arada yenilediyse yeniden yenilemeden yeni belirteçle dene.
    final used = options.headers['Authorization'];
    final current = tokens.accessToken;
    final result = current != null && used != 'Bearer $current'
        ? RefreshResult.refreshed
        : await refresher.refresh();

    switch (result) {
      case RefreshResult.refreshed:
        try {
          handler.resolve(await _retry(options));
        } on DioException catch (e) {
          handler.next(e);
        }
      case RefreshResult.invalid:
        events.emit(SessionExpiredEvent(reason));
        handler.next(err);
      case RefreshResult.transient:
        handler.next(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: const OfflineFailure(),
          ),
        );
    }
  }

  Future<Response<dynamic>> _retry(RequestOptions o) {
    var data = o.data;
    if (data is FormData) data = data.clone();
    final headers = Map<String, dynamic>.of(o.headers);
    final access = tokens.accessToken;
    if (access != null) headers['Authorization'] = 'Bearer $access';
    return dio.fetch<dynamic>(
      o.copyWith(
        data: data,
        headers: headers,
        extra: {...o.extra, ApiExtra.retried: true},
      ),
    );
  }
}
