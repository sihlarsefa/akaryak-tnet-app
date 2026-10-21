import 'dart:convert';

import 'package:akaryakitnet/core/auth/session_events.dart';
import 'package:akaryakitnet/core/auth/token_refresher.dart';
import 'package:akaryakitnet/core/auth/token_store.dart';
import 'package:akaryakitnet/core/env/app_info.dart';
import 'package:akaryakitnet/core/models/auth_models.dart';
import 'package:akaryakitnet/core/network/api_client.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/network/interceptors/app_headers_interceptor.dart';
import 'package:akaryakitnet/core/network/interceptors/auth_interceptor.dart';
import 'package:akaryakitnet/core/storage/secure_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_adapter.dart';

ResponseBody _json(int status, Object? body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json; charset=utf-8'],
  },
);

class _Stack {
  _Stack({required this.adapter}) {
    dio = Dio(BaseOptions(baseUrl: 'http://x/api/v1/'))
      ..httpClientAdapter = adapter;
    refresher = TokenRefresher(
      tokens: tokens,
      events: events,
      call: (rt) async {
        final res = await dio.post<Object?>(
          'auth/refresh',
          data: {'refreshToken': rt, 'deviceId': 'd'},
          options: Options(extra: {ApiExtra.skipAuth: true}),
        );
        final t = AuthResult.fromJson(res.data).tokens;
        if (t == null) {
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
      AppHeadersInterceptor(AppInfo.test),
      AuthInterceptor(
        dio: dio,
        tokens: tokens,
        refresher: refresher,
        events: events,
      ),
    ]);
    api = ApiClient(dio);
    events.stream.listen(received.add);
  }

  final QueueAdapter adapter;
  final tokens = TokenStore(MemorySecureStore());
  final events = SessionEvents();
  final received = <SessionEvent>[];
  late final Dio dio;
  late final TokenRefresher refresher;
  late final ApiClient api;

  Future<void> signIn(
    String access, {
    Duration validFor = const Duration(minutes: 10),
  }) => tokens.save(
    AuthTokens(
      accessToken: access,
      accessExpiresAt: DateTime.now().toUtc().add(validFor),
      refreshToken: 'refresh-1',
      userId: 'u-1',
    ),
  );
}

Map<String, Object?> _tokens(String access) => {
  'status': 'ok',
  'tokens': {
    'accessToken': access,
    'accessExpiresAt': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 15))
        .toIso8601String(),
    'refreshToken': 'refresh-2',
    'userId': 'u-1',
  },
};

void main() {
  test(
    'eşzamanlı 401\'ler tek yenileme yapar, sonra her istek bir kez yeni belirteçle tekrarlanır',
    () async {
      var refreshCalls = 0;
      final adapter = QueueAdapter();
      adapter.fallback = (o) async {
        if (o.path.endsWith('auth/refresh')) {
          refreshCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return _json(200, _tokens('new-access'));
        }
        final auth = o.headers['Authorization'];
        if (auth == 'Bearer old-access') {
          return _json(401, {'code': 'token_expired', 'detail': 'Süre doldu'});
        }
        if (auth == 'Bearer new-access') return _json(200, {'path': o.path});
        return _json(401, {'code': 'unauthorized'});
      };
      final s = _Stack(adapter: adapter);
      await s.signIn('old-access');

      final results = await Future.wait([
        s.api.get('orders/1', parse: (j) => j),
        s.api.get('orders/2', parse: (j) => j),
        s.api.get('orders/3', parse: (j) => j),
      ]);

      expect(refreshCalls, 1);
      expect(results.map((r) => (r! as Map)['path']), [
        'orders/1',
        'orders/2',
        'orders/3',
      ]);
      // `RequestOptions.path` göreli yoldur ('orders/1'); gerçek adres API köküyle birleşir
      // (`/api/v1/orders/1`). A-INT doğrulaması (M0b notu).
      expect(
        adapter.requests.map((r) => r.uri.path),
        contains('/api/v1/orders/1'),
      );
      expect(s.tokens.accessToken, 'new-access');
      expect(s.tokens.refreshToken, 'refresh-2');
      // 3 ilk deneme + 1 yenileme + 3 tekrar.
      expect(adapter.requests, hasLength(7));
      expect(
        adapter.requests.where(
          (r) => r.header('Authorization') == 'Bearer new-access',
        ),
        hasLength(3),
      );
      await Future<void>.delayed(Duration.zero);
      expect(s.received.whereType<SessionExpiredEvent>(), isEmpty);
      expect(s.received.whereType<TokensRefreshedEvent>(), hasLength(1));
    },
  );

  test('süresi dolmak üzere olan belirteç istekten önce yenilenir', () async {
    var refreshCalls = 0;
    final adapter = QueueAdapter()
      ..fallback = (o) {
        if (o.path.endsWith('auth/refresh')) {
          refreshCalls++;
          return _json(200, _tokens('fresh'));
        }
        return _json(200, {'auth': o.headers['Authorization']});
      };
    final s = _Stack(adapter: adapter);
    await s.signIn('stale', validFor: const Duration(seconds: 5));
    final r = await s.api.get('me/access', parse: (j) => j);
    expect(refreshCalls, 1);
    expect((r! as Map)['auth'], 'Bearer fresh');
  });

  test(
    'yenileme reddedilirse oturum bitti olayı yayınlanır ve istek 401 ile düşer',
    () async {
      final adapter = QueueAdapter()
        ..fallback = (o) {
          if (o.path.endsWith('auth/refresh')) {
            return _json(401, {'code': 'unauthorized'});
          }
          return _json(401, {'code': 'token_expired'});
        };
      final s = _Stack(adapter: adapter);
      await s.signIn('old');
      await expectLater(
        s.api.get('orders', parse: (j) => j),
        throwsA(isA<UnauthorizedFailure>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(s.received.whereType<SessionExpiredEvent>(), hasLength(1));
    },
  );

  test(
    'yenileme ağ hatası verirse oturum korunur, istek çevrimdışı hatasıyla düşer',
    () async {
      final adapter = QueueAdapter()
        ..fallback = (o) {
          if (o.path.endsWith('auth/refresh')) {
            throw DioException.connectionError(
              requestOptions: o,
              reason: 'yok',
            );
          }
          return _json(401, {'code': 'token_expired'});
        };
      final s = _Stack(adapter: adapter);
      await s.signIn('old');
      await expectLater(
        s.api.get('orders', parse: (j) => j),
        throwsA(isA<OfflineFailure>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(s.received.whereType<SessionExpiredEvent>(), isEmpty);
      expect(s.tokens.hasRefreshToken, isTrue);
    },
  );

  test(
    'session_revoked yenilemeden çıkış olayı yayınlar; 403 ve 426 bildirilir',
    () async {
      final adapter = QueueAdapter()
        ..problem(401, 'session_revoked', 'Oturum kapatıldı')
        ..problem(403, 'forbidden', 'Yetki yok')
        ..problem(426, 'app_update_required', 'Güncelleyin');
      final s = _Stack(adapter: adapter);
      await s.signIn('a');
      await expectLater(
        s.api.get('x', parse: (j) => j),
        throwsA(isA<UnauthorizedFailure>()),
      );
      await expectLater(
        s.api.get('y', parse: (j) => j),
        throwsA(isA<ForbiddenFailure>()),
      );
      await expectLater(
        s.api.get('z', parse: (j) => j),
        throwsA(isA<UpdateRequiredFailure>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        s.received.whereType<SessionExpiredEvent>().single.reason,
        'session_revoked',
      );
      expect(s.received.whereType<ForbiddenEvent>(), hasLength(1));
      expect(s.received.whereType<UpdateRequiredEvent>(), hasLength(1));
    },
  );

  test(
    'istek başlıkları: cihaz, platform, sürüm, derleme, correlation id, Idempotency-Key',
    () async {
      final adapter = QueueAdapter()
        ..json(200, {})
        ..json(200, {});
      final s = _Stack(adapter: adapter);
      await s.signIn('tok');
      await s.api.post<void>(
        'orders/place',
        body: {'a': 1},
        idempotencyKey: 'key-1',
      );
      await s.api.get('me/access', parse: (j) => j);
      final first = adapter.requests[0];
      final second = adapter.requests[1];
      expect(first.header('X-Device-Id'), 'test-device');
      expect(first.header('X-App-Platform'), 'ios');
      expect(first.header('X-App-Build'), '1');
      expect(first.header('Idempotency-Key'), 'key-1');
      expect(first.header('Authorization'), 'Bearer tok');
      expect(second.header('Idempotency-Key'), isNull);
      expect(
        first.header('X-Correlation-Id'),
        isNot(second.header('X-Correlation-Id')),
      );
    },
  );
}
