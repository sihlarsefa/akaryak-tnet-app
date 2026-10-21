import 'package:dio/dio.dart';

import '../../env/app_info.dart';
import '../idempotency.dart';

/// İstek başlıkları (spec B.2): `X-Device-Id`, `X-App-Platform`, `X-App-Version`, `X-App-Build`,
/// her istekte yeni `X-Correlation-Id`, Türkçe dil tercihi.
class AppHeadersInterceptor extends Interceptor {
  AppHeadersInterceptor(this.info);

  final AppInfo info;

  static const correlationHeader = 'X-Correlation-Id';
  static const idempotencyHeader = 'Idempotency-Key';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final h = options.headers;
    h['X-Device-Id'] = info.deviceId;
    h['X-App-Platform'] = info.platform;
    h['X-App-Version'] = info.appVersion;
    h['X-App-Build'] = '${info.appBuild}';
    h[correlationHeader] = newIdempotencyKey();
    h.putIfAbsent('Accept', () => 'application/json');
    h.putIfAbsent('Accept-Language', () => 'tr-TR');
    handler.next(options);
  }
}
