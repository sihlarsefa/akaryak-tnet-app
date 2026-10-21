import 'package:dio/dio.dart';

import '../../utils/log.dart';
import 'app_headers_interceptor.dart';

/// Yalnızca debug derlemede: yöntem, yol, durum, süre ve correlation id. Gövde ve belirteç yazılmaz.
class DebugLogInterceptor extends Interceptor {
  static const _startKey = 'akn.startedAt';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _log(response.requestOptions, response.statusCode);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _log(err.requestOptions, err.response?.statusCode, error: err.type.name);
    handler.next(err);
  }

  void _log(RequestOptions o, int? status, {String? error}) {
    final started = o.extra[_startKey] as int?;
    final ms = started == null
        ? '?'
        : '${DateTime.now().millisecondsSinceEpoch - started}';
    final cid = o.headers[AppHeadersInterceptor.correlationHeader] ?? '';
    AppLog.debug(
      '${o.method} ${o.uri.path}${o.uri.hasQuery ? '?…' : ''} → ${status ?? error} (${ms}ms) cid=$cid',
      name: 'http',
    );
  }
}
