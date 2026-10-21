import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_events.dart';
import '../auth/token_refresher.dart';
import '../auth/token_store.dart';
import '../env/app_env.dart';
import '../env/app_info.dart';
import '../models/auth_models.dart';
import '../storage/secure_store.dart';
import 'api_client.dart';
import 'fake/core_fakes.dart';
import 'fake/fake_api_adapter.dart';
import 'fake/fake_server.dart';
import 'interceptors/app_headers_interceptor.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/debug_log_interceptor.dart';

/// Güvenli depo. Bootstrap gerçek depoyu verir; testler [MemorySecureStore].
final secureStoreProvider = Provider<SecureStore>((ref) => MemorySecureStore());

/// Belirteç deposu (bellek + güvenli depo).
final tokenStoreProvider = Provider<TokenStore>(
  (ref) => TokenStore(ref.watch(secureStoreProvider)),
);

/// Ağ → oturum olay kanalı.
final sessionEventsProvider = Provider<SessionEvents>((ref) {
  final events = SessionEvents();
  ref.onDispose(events.dispose);
  return events;
});

/// Sahte sunucu (yalnızca `API_MODE=fake`). Uygulama katmanı (`app/fakes.dart`) özellik sahtelerini
/// kaydedip bu sağlayıcıyı geçersiz kılar; kılınmazsa yalnızca çekirdek sahteler vardır.
final fakeServerProvider = Provider<FakeServer>((ref) {
  final server = FakeServer();
  registerCoreFakes(server);
  return server;
});

/// Dio + ara katmanlar + tek yenileme. Ortam değişmedikçe bir kez kurulur.
class ApiStack {
  ApiStack({required this.dio, required this.refresher});
  final Dio dio;
  final TokenRefresher refresher;
}

final apiStackProvider = Provider<ApiStack>((ref) {
  final env = ref.watch(appEnvProvider);
  final info = ref.watch(appInfoProvider);
  final tokens = ref.watch(tokenStoreProvider);
  final events = ref.watch(sessionEventsProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: env.apiV1Url,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    ),
  );
  // Derleme zamanı koruması: canlı derlemede sahte sunucu hiç derlenmez (bkz. [kFakeApiCompiled]).
  if (kFakeApiCompiled && env.isFake) {
    dio.httpClientAdapter = FakeApiAdapter(ref.watch(fakeServerProvider));
  }

  final refresher = TokenRefresher(
    tokens: tokens,
    events: events,
    call: (refreshToken) async {
      final res = await dio.post<Object?>(
        'auth/refresh',
        data: {'refreshToken': refreshToken, 'deviceId': info.deviceId},
        options: Options(extra: {ApiExtra.skipAuth: true}),
      );
      final result = AuthResult.fromJson(res.data);
      final t = result.tokens;
      if (t == null || !t.isValid) {
        throw DioException(
          requestOptions: res.requestOptions,
          response: res,
          type: DioExceptionType.badResponse,
        );
      }
      return t;
    },
  );

  dio.interceptors.addAll([
    AppHeadersInterceptor(info),
    AuthInterceptor(
      dio: dio,
      tokens: tokens,
      refresher: refresher,
      events: events,
    ),
    if (kDebugMode) DebugLogInterceptor(),
  ]);
  ref.onDispose(() => dio.close(force: true));
  return ApiStack(dio: dio, refresher: refresher);
});

final dioProvider = Provider<Dio>((ref) => ref.watch(apiStackProvider).dio);

final tokenRefresherProvider = Provider<TokenRefresher>(
  (ref) => ref.watch(apiStackProvider).refresher,
);

/// Özelliklerin kullandığı API istemcisi.
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(dioProvider)),
);
