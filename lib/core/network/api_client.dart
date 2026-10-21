import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'app_failure.dart';
import 'interceptors/app_headers_interceptor.dart';
import 'interceptors/auth_interceptor.dart';

/// Yanıt gövdesini modele çeviren fonksiyon (`MeAccess.fromJson` gibi).
typedef JsonParser<T> = T Function(Object? json);

/// Mobil API v1 istemcisi (spec C.4). Tek Dio üzerinde çalışır; yollar `api/v1/` köküne göredir
/// (`client.get('me/access', parse: MeAccess.fromJson)`).
///
/// Her hata [AppFailure] olarak fırlatılır; başka tip istisna dışarı çıkmaz.
/// `Idempotency-Key` gereken POST'lar (spec B.2) [idempotencyKey] verir; anahtar kullanıcı niyeti başına
/// `IdempotencyLedger` ile tutulur.
class ApiClient {
  ApiClient(this.dio);

  final Dio dio;

  /// Yükleme zaman aşımı (spec C.4: 120 s).
  static const uploadTimeout = Duration(seconds: 120);

  Future<T> get<T>(
    String path, {
    required JsonParser<T> parse,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
    bool anonymous = false,
    bool quiet403 = false,
  }) => _send(
    () => dio.get<Object?>(
      path,
      queryParameters: _clean(query),
      cancelToken: cancelToken,
      options: _options(anonymous: anonymous, quiet403: quiet403),
    ),
    parse,
  );

  Future<T> post<T>(
    String path, {
    Object? body,
    JsonParser<T>? parse,
    Map<String, dynamic>? query,
    String? idempotencyKey,
    CancelToken? cancelToken,
    bool anonymous = false,
    bool quiet403 = false,
  }) => _send(
    () => dio.post<Object?>(
      path,
      data: body,
      queryParameters: _clean(query),
      cancelToken: cancelToken,
      options: _options(
        anonymous: anonymous,
        quiet403: quiet403,
        idempotencyKey: idempotencyKey,
      ),
    ),
    parse,
  );

  Future<T> put<T>(
    String path, {
    Object? body,
    JsonParser<T>? parse,
    Map<String, dynamic>? query,
    String? idempotencyKey,
    CancelToken? cancelToken,
  }) => _send(
    () => dio.put<Object?>(
      path,
      data: body,
      queryParameters: _clean(query),
      cancelToken: cancelToken,
      options: _options(idempotencyKey: idempotencyKey),
    ),
    parse,
  );

  Future<T> delete<T>(
    String path, {
    Object? body,
    JsonParser<T>? parse,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) => _send(
    () => dio.delete<Object?>(
      path,
      data: body,
      queryParameters: _clean(query),
      cancelToken: cancelToken,
      options: _options(),
    ),
    parse,
  );

  /// Çok parçalı yükleme (ilerleme ile). Yenileme gerekirse form klonlanıp bir kez tekrar gönderilir.
  Future<T> upload<T>(
    String path, {
    required FormData form,
    required JsonParser<T> parse,
    String? idempotencyKey,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) => _send(
    () => dio.post<Object?>(
      path,
      data: form,
      cancelToken: cancelToken,
      onSendProgress: onProgress,
      options: _options(
        idempotencyKey: idempotencyKey,
      ).copyWith(sendTimeout: uploadTimeout, receiveTimeout: uploadTimeout),
    ),
    parse,
  );

  /// İkili içerik (PDF, görsel).
  Future<Uint8List> bytes(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    try {
      final res = await dio.get<List<int>>(
        path,
        queryParameters: _clean(query),
        cancelToken: cancelToken,
        options: _options().copyWith(
          responseType: ResponseType.bytes,
          receiveTimeout: uploadTimeout,
        ),
      );
      final data = res.data;
      return data is Uint8List ? data : Uint8List.fromList(data ?? const []);
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<T> _send<T>(
    Future<Response<Object?>> Function() call,
    JsonParser<T>? parse,
  ) async {
    final Response<Object?> res;
    try {
      res = await call();
    } catch (e) {
      throw AppFailure.from(e);
    }
    try {
      if (parse == null) return null as T;
      return parse(res.data);
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw const UnknownFailure('Sunucudan beklenmeyen bir yanıt alındı.');
    }
  }

  static Options _options({
    bool anonymous = false,
    bool quiet403 = false,
    String? idempotencyKey,
  }) => Options(
    headers: {AppHeadersInterceptor.idempotencyHeader: ?idempotencyKey},
    extra: {
      if (anonymous) ApiExtra.skipAuth: true,
      if (quiet403) ApiExtra.quiet403: true,
    },
  );

  /// Null ve boş değerleri sorgudan atar; listeler `a=1&a=2` olarak gider.
  static Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    final out = <String, dynamic>{};
    query.forEach((k, v) {
      if (v == null) return;
      if (v is String && v.trim().isEmpty) return;
      if (v is Iterable && v.isEmpty) return;
      out[k] = v is Iterable
          ? v.map((e) => '$e').toList()
          : (v is bool ? '$v' : v);
    });
    return out;
  }
}
