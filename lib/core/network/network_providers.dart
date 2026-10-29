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
import '../utils/log.dart';
import 'api_client.dart';
import 'app_failure.dart';
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

/// Sahte sunucu (yalnızca sahte kipte: `API_MODE=fake` ya da test derlemesinin demo oturumu; ilk
/// kullanımda kurulur, süreç boyunca aynı dünya kalır). Uygulama katmanı (`app/fakes.dart`) özellik
/// sahtelerini kaydedip bu sağlayıcıyı geçersiz kılar; kılınmazsa yalnızca çekirdek sahteler vardır.
final fakeServerProvider = Provider<FakeServer>((ref) {
  final server = FakeServer();
  registerCoreFakes(server);
  return server;
});

/// Canlı kipte Dio'nun HTTP adaptörü: null ise Dio'nun platform adaptörü (gerçek ağ). Testler canlı
/// kipi, sunucuya hiç bağlanmadan, istekleri kaydeden bir adaptörle sınar.
final liveHttpAdapterProvider = Provider<HttpClientAdapter?>((ref) => null);

/// Dio + ara katmanlar + tek yenileme. Etkin ortam değişmedikçe bir kez kurulur; test derlemesinde demo
/// oturumu açılıp kapanınca ([demoSessionProvider]) yeniden kurulur ve eskisi kapanır (kapanmış Dio yeni
/// istek göndermez: eskiyi tutan bir çağrı öbür dünyaya kaçamaz, bağlantı hatası alır).
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
  } else {
    final live = ref.watch(liveHttpAdapterProvider);
    if (live != null) dio.httpClientAdapter = live;
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
      // Yenileme sürerken oturum kapandıysa ya da değiştiyse (çıkış, demo oturumunun bitişi, başka
      // kullanıcıyla giriş) dönen belirteçler kaydedilmez: kapanan oturum depoya geri yazılmaz (sahte
      // belirteç canlı oturuma taşınmaz). Geçici hata sayılır; oturum olayı yayılmaz.
      if (tokens.refreshToken != refreshToken) {
        throw DioException(
          requestOptions: res.requestOptions,
          type: DioExceptionType.cancel,
          error: const UnknownFailure.cancelled(),
        );
      }
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
    // İlk sırada: reddedilen istek için yenileme de denenmez (belirteç gövdede de gitmez).
    if (kFakeApiCompiled && !env.isFake) _DemoSessionGuard(tokens),
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

/// Savunma derinliği (test derlemesi): depo demo oturumunun belirteçlerini (sahte sunucunun) tutarken
/// canlı yığından hiçbir istek çıkmaz; sahte belirteç ne yetki başlığında ne gövdede (yenileme, iptal)
/// canlı API'ye gider. Doğru akışta bu hiç olmaz: demo oturumu sahte yığınla açılır, çıkışta belirteçler
/// ortam canlıya dönmeden silinir, soğuk açılışta demo belirteci yüklenmez ([TokenStore.load]).
class _DemoSessionGuard extends Interceptor {
  _DemoSessionGuard(this.tokens);

  final TokenStore tokens;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!tokens.isDemo) {
      handler.next(options);
      return;
    }
    AppLog.warn('Demo oturumu açıkken canlı API isteği engellendi');
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        error: const UnknownFailure.cancelled(),
      ),
    );
  }
}

final dioProvider = Provider<Dio>((ref) => ref.watch(apiStackProvider).dio);

final tokenRefresherProvider = Provider<TokenRefresher>(
  (ref) => ref.watch(apiStackProvider).refresher,
);

/// Özelliklerin kullandığı API istemcisi.
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(dioProvider)),
);
