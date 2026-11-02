// Speed layer of the API client (2026-11-02, "veriler çok yavaş"): the user- and mode-scoped GET
// response cache (cache-first screens), in-flight GET dedupe, invalidation after writes, and the
// read retry that honours Retry-After.
import 'dart:async';

import 'package:akaryakitnet/core/network/api_client.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/network/interceptors/read_retry_interceptor.dart';
import 'package:akaryakitnet/core/network/response_cache.dart';
import 'package:akaryakitnet/core/offline/cache_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_adapter.dart';

class _Client {
  _Client({String mode = 'live', this.user = 'u-a', MemoryCacheStore? store})
    : store = store ?? MemoryCacheStore(),
      adapter = QueueAdapter() {
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test/api/v1/'))
      ..httpClientAdapter = adapter;
    api = ApiClient(
      dio,
      dedupeReads: true,
      responses: ResponseCache(
        store: this.store,
        mode: mode,
        userId: () => user,
      ),
    );
  }

  final MemoryCacheStore store;
  final QueueAdapter adapter;
  late final ApiClient api;
  String? user;

  Iterable<String> get keys => store.keys;
}

Object? _raw(Object? j) => j;

void main() {
  group('response cache (cache-first screens)', () {
    test('get(cache: true) writes; peek returns it with the time it was stored', () async {
      final c = _Client();
      c.adapter.json(200, {'items': [1, 2]});
      final fresh = await c.api.get('bayi/orders', query: {'page': 1, 'pageSize': 25}, parse: _raw, cache: true);
      expect(fresh, {'items': [1, 2]});
      final hit = await c.api.peek('bayi/orders', query: {'pageSize': 25, 'page': 1}, parse: _raw);
      expect(hit, isNotNull, reason: 'query order does not matter');
      expect(hit!.value, {'items': [1, 2]});
      expect(hit.age, lessThan(const Duration(seconds: 5)));
      expect(c.adapter.requests, hasLength(1), reason: 'peek never goes to the network');
    });

    test('nothing is cached without cache: true, for anonymous calls, or without a user', () async {
      final c = _Client();
      c.adapter.json(200, {'a': 1});
      await c.api.get('bayi/orders', parse: _raw);
      c.adapter.json(200, {'a': 2});
      await c.api.get('app/config', parse: _raw, anonymous: true, cache: true);
      c.user = null;
      c.adapter.json(200, {'a': 3});
      await c.api.get('home/bayi', parse: _raw, cache: true);
      expect(c.keys, isEmpty);
    });

    test('privacy: entries are per user — user B never sees user A’s response', () async {
      final c = _Client(user: 'u-a');
      c.adapter.json(200, {'owner': 'a'});
      await c.api.get('home/bayi', parse: _raw, cache: true);
      expect(c.keys.single, startsWith('u-a:'), reason: 'clearUser(u-a) removes it at logout');
      c.user = 'u-b';
      expect(await c.api.peek('home/bayi', parse: _raw), isNull);
      // Logout of A (CacheStore.clearUser) removes every response of A.
      await c.store.clearUser('u-a');
      c.user = 'u-a';
      expect(await c.api.peek('home/bayi', parse: _raw), isNull);
    });

    test('privacy: demo (fake world) and live never share entries, even for the same user id', () async {
      final store = MemoryCacheStore();
      final live = _Client(mode: 'live', store: store);
      live.adapter.json(200, {'world': 'live'});
      await live.api.get('home/bayi', parse: _raw, cache: true);
      final demo = _Client(mode: 'demo', store: store);
      expect(await demo.api.peek('home/bayi', parse: _raw), isNull);
      demo.adapter.json(200, {'world': 'demo'});
      await demo.api.get('home/bayi', parse: _raw, cache: true);
      expect((await live.api.peek('home/bayi', parse: _raw))!.value, {'world': 'live'});
      expect((await demo.api.peek('home/bayi', parse: _raw))!.value, {'world': 'demo'});
      expect(store.keys.where((k) => k.contains('http.live.')), hasLength(1));
      expect(store.keys.where((k) => k.contains('http.demo.')), hasLength(1));
    });

    test('a response is not written when the user changed while it was in flight', () async {
      final c = _Client(user: 'u-a');
      final release = c.adapter.held(200, {'owner': 'a'});
      final f = c.api.get('home/bayi', parse: _raw, cache: true);
      await Future<void>.delayed(Duration.zero);
      c.user = 'u-b'; // sign-out + sign-in of someone else
      release.complete();
      await f;
      expect(c.keys, isEmpty);
    });

    test('a response that no longer parses (old build) is a miss and is dropped', () async {
      final c = _Client();
      c.adapter.json(200, {'items': 'not a list'});
      await c.api.get('payments', parse: _raw, cache: true);
      final hit = await c.api.peek<List<Object?>>(
        'payments',
        parse: (j) => (j! as Map)['items'] as List<Object?>,
      );
      expect(hit, isNull);
      expect(c.keys, isEmpty);
    });

    test('expired entries are misses', () async {
      final store = MemoryCacheStore();
      final c = _Client(store: store);
      final cache = ResponseCache(store: store, mode: 'live', userId: () => 'u-a');
      await store.write(
        cache.keyFor('u-a', 'home/bayi', null),
        {'old': true},
        ttl: const Duration(milliseconds: 1),
        userId: 'u-a',
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(await c.api.peek('home/bayi', parse: _raw), isNull);
    });

    test('expired responses do not pile up on disk: a later write of the user purges them', () async {
      final store = MemoryCacheStore();
      final cache = ResponseCache(
        store: store,
        mode: 'live',
        userId: () => 'u-a',
        maxAge: const Duration(milliseconds: 40),
        purgeEvery: Duration.zero,
      );
      final t0 = DateTime.now().toUtc();
      await cache.write('orders/1', null, {'n': 1}, uid: 'u-a', requestedAt: t0);
      await cache.write('orders/2', null, {'n': 2}, uid: 'u-a', requestedAt: t0);
      // Not the response cache: other users' entries and the features' own (offline) keys stay.
      await store.write('u-b:http.live.v1|orders/9', {'n': 9}, ttl: const Duration(milliseconds: 1), userId: 'u-b');
      await store.write('u-a:home.bayi', {'h': 1}, ttl: const Duration(milliseconds: 1), userId: 'u-a');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await cache.write('orders/3', null, {'n': 3}, uid: 'u-a', requestedAt: DateTime.now().toUtc());
      await Future<void>.delayed(Duration.zero);
      expect(store.keys.toSet(), {
        cache.keyFor('u-a', 'orders/3', null),
        'u-b:http.live.v1|orders/9',
        'u-a:home.bayi',
      });
    });
  });

  group('invalidation after writes', () {
    test('a quote (POST orders/{id}/quote) evicts the order, lists, homes and the desk', () async {
      final c = _Client();
      for (final path in [
        'orders/12',
        'orders/12/timeline',
        'bayi/orders',
        'bayi/orders/counts',
        'home/bayi',
        'bayi/quote-desk',
        'stations/me/staff',
      ]) {
        c.adapter.json(200, {'p': path});
        await c.api.get(path, parse: _raw, cache: true);
      }
      c.adapter.empty(204);
      await c.api.post<void>('orders/12/quote', body: {'unitPriceTry': 40});
      final left = [for (final k in c.keys) k.substring(k.indexOf('|') + 1)];
      expect(left, ['stations/me/staff'], reason: 'staff is not affected by an order');
    });

    test('a delivery report evicts shipments, driver lists and orders; staff stays', () async {
      final prefixes = WriteInvalidation.prefixesFor('POST', 'driver/shipments/9/deliver');
      expect(prefixes, containsAll(['shipments', 'driver/', 'orders/', 'bayi/orders', 'home/']));
      expect(prefixes, isNot(contains('stations/me/staff')));
    });

    test('a decision (POST approvals/{id}/decide) evicts approvals, orders, finance and homes', () {
      final prefixes = WriteInvalidation.prefixesFor('POST', 'approvals/5/decide');
      expect(prefixes, containsAll(['approvals', 'orders/', 'bayi/orders', 'finance/', 'home/', 'customers/me/']));
    });

    test('order placed (POST orders/place) evicts the customer lists and home', () {
      final prefixes = WriteInvalidation.prefixesFor('POST', 'orders/place');
      expect(prefixes, containsAll(['customers/me/orders', 'home/', 'orders/']));
    });

    test('reads and session plumbing never invalidate', () {
      for (final w in [
        ('GET', 'orders/12'),
        ('POST', 'auth/refresh'),
        ('PUT', 'devices/current'),
        ('POST', 'assistant/chat'),
        ('POST', 'field-orders/preview-v2'),
        ('POST', 'leads/check-duplicate'),
      ]) {
        expect(WriteInvalidation.prefixesFor(w.$1, w.$2), isEmpty, reason: '$w');
      }
    });

    test('an uncertain write (timeout) also evicts; a 400 does not', () async {
      final c = _Client();
      c.adapter.json(200, {'x': 1});
      await c.api.get('payments', parse: _raw, cache: true);
      c.adapter.problem(400, 'validation', 'Geçersiz');
      await expectLater(c.api.post<void>('payments/12/status'), throwsA(isA<AppFailure>()));
      expect(c.keys, hasLength(1));
      c.adapter.timeout();
      await expectLater(c.api.post<void>('payments/12/status'), throwsA(isA<TimeoutFailure>()));
      expect(c.keys, isEmpty);
    });

    test('a read that started before a write cannot write its stale answer back', () async {
      final c = _Client();
      final release = c.adapter.held(200, {'stale': true});
      final read = c.api.get('bayi/orders', parse: _raw, cache: true);
      await Future<void>.delayed(Duration.zero);
      c.adapter.empty(204);
      await c.api.post<void>('orders/3/complete');
      release.complete();
      await read;
      expect(c.keys, isEmpty);
    });
  });

  group('in-flight GET dedupe', () {
    test('two identical concurrent reads share one request', () async {
      final c = _Client();
      final release = c.adapter.held(200, {'n': 1});
      final a = c.api.get('bayi/orders/counts', parse: _raw);
      final b = c.api.get('bayi/orders/counts', parse: (j) => (j! as Map)['n']);
      await Future<void>.delayed(Duration.zero);
      release.complete();
      expect(await a, {'n': 1});
      expect(await b, 1);
      expect(c.adapter.requests, hasLength(1));
      // Finished: the next read goes to the network again.
      c.adapter.json(200, {'n': 2});
      expect(await c.api.get('bayi/orders/counts', parse: _raw), {'n': 2});
      expect(c.adapter.requests, hasLength(2));
    });

    test('different users, queries or a cancel token never share', () async {
      final c = _Client(user: 'u-a');
      final r1 = c.adapter.held(200, {'u': 'a'});
      final a = c.api.get('home/bayi', parse: _raw);
      await Future<void>.delayed(Duration.zero);
      c.user = 'u-b';
      final r2 = c.adapter.held(200, {'u': 'b'});
      final b = c.api.get('home/bayi', parse: _raw);
      final r3 = c.adapter.held(200, {'q': 2});
      final q = c.api.get('home/bayi', query: {'x': 2}, parse: _raw);
      final r4 = c.adapter.held(200, {'t': 1});
      final t = c.api.get('home/bayi', parse: _raw, cancelToken: CancelToken());
      await Future<void>.delayed(Duration.zero);
      for (final r in [r1, r2, r3, r4]) {
        r.complete();
      }
      expect(await a, {'u': 'a'});
      expect(await b, {'u': 'b'});
      expect(await q, {'q': 2});
      expect(await t, {'t': 1});
      expect(c.adapter.requests, hasLength(4));
    });

    test('a read that started before a write is not shared after it: the list asked for after '
        '"Sipariş ver" has the new order, and the old answer never reaches the cache', () async {
      final c = _Client();
      final release = c.adapter.held(200, {'orders': ['old']});
      final before = c.api.get('customers/me/orders', parse: _raw, cache: true);
      await Future<void>.delayed(Duration.zero);
      c.adapter.json(200, {'orderId': 99});
      await c.api.post<Object?>('orders/place', parse: _raw);
      c.adapter.json(200, {'orders': ['new', 'old']});
      final after = await c.api.get('customers/me/orders', parse: _raw, cache: true);
      expect(after, {'orders': ['new', 'old']});
      release.complete();
      expect(await before, {'orders': ['old']}, reason: 'the first caller still gets its own answer');
      expect(c.adapter.requests.where((r) => r.path.endsWith('customers/me/orders')), hasLength(2));
      final hit = await c.api.peek('customers/me/orders', parse: _raw);
      expect(hit!.value, {'orders': ['new', 'old']});
    });

    test('ApiClient.invalidate also stops sharing the reads in flight under those prefixes', () async {
      final c = _Client();
      final r1 = c.adapter.held(200, {'n': 1});
      final a = c.api.get('bayi/orders/counts', parse: _raw, cache: true);
      await Future<void>.delayed(Duration.zero);
      await c.api.invalidate(['bayi/orders']);
      final r2 = c.adapter.held(200, {'n': 2});
      final b = c.api.get('bayi/orders/counts', parse: _raw, cache: true);
      await Future<void>.delayed(Duration.zero);
      r2.complete();
      r1.complete();
      expect(await b, {'n': 2});
      expect(await a, {'n': 1});
      expect(c.adapter.requests, hasLength(2));
      expect((await c.api.peek('bayi/orders/counts', parse: _raw))!.value, {'n': 2});
    });

    test('a shared failure reaches every caller', () async {
      final c = _Client();
      final release = Completer<void>();
      c.adapter.enqueue((o) async {
        await release.future;
        throw DioException.connectionError(requestOptions: o, reason: 'x');
      });
      final a = c.api.get('home/bayi', parse: _raw);
      final b = c.api.get('home/bayi', parse: _raw);
      await Future<void>.delayed(Duration.zero);
      release.complete();
      await expectLater(a, throwsA(isA<OfflineFailure>()));
      await expectLater(b, throwsA(isA<OfflineFailure>()));
      expect(c.adapter.requests, hasLength(1));
    });
  });

  group('read retry (Retry-After)', () {
    Dio retryDio(QueueAdapter adapter, ReadRetryPolicy policy) {
      final dio = Dio(BaseOptions(baseUrl: 'http://api.test/api/v1/'))
        ..httpClientAdapter = adapter;
      dio.interceptors.add(ReadRetryInterceptor(dio: dio, policy: policy));
      return dio;
    }

    test('429 with Retry-After: waits and retries the GET, the caller gets the data', () async {
      final adapter = QueueAdapter()
        ..problem(429, 'rate_limited', 'Çok fazla istek', headers: {'retry-after': ['1']})
        ..json(200, {'ok': true});
      final api = ApiClient(retryDio(adapter, const ReadRetryPolicy()));
      final sw = Stopwatch()..start();
      expect(await api.get('approvals', parse: _raw), {'ok': true});
      expect(sw.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 900)));
      expect(adapter.requests, hasLength(2));
    });

    test('a Retry-After longer than the cap is not waited for', () async {
      final adapter = QueueAdapter()
        ..problem(429, 'rate_limited', 'Çok fazla istek', headers: {'retry-after': ['60']});
      final api = ApiClient(retryDio(adapter, const ReadRetryPolicy()));
      await expectLater(api.get('approvals', parse: _raw), throwsA(isA<RateLimitedFailure>()));
      expect(adapter.requests, hasLength(1));
    });

    test('503 without a code is retried; 503 with a code (maintenance) is not', () async {
      final adapter = QueueAdapter()
        ..json(503, {'title': 'x', 'status': 503}, headers: {'retry-after': ['0']})
        ..json(200, {'ok': 1});
      final api = ApiClient(retryDio(adapter, const ReadRetryPolicy()));
      expect(await api.get('home/bayi', parse: _raw), {'ok': 1});
      final adapter2 = QueueAdapter()..problem(503, 'maintenance', 'Bakım');
      final api2 = ApiClient(retryDio(adapter2, const ReadRetryPolicy()));
      await expectLater(api2.get('home/bayi', parse: _raw), throwsA(isA<ServerFailure>()));
      expect(adapter2.requests, hasLength(1));
    });

    test('a dropped connection is retried once; writes are never retried here', () async {
      final adapter = QueueAdapter()
        ..connectionError()
        ..json(200, {'ok': 1});
      final api = ApiClient(
        retryDio(adapter, const ReadRetryPolicy(transientDelay: Duration.zero, jitter: Duration.zero)),
      );
      expect(await api.get('home/bayi', parse: _raw), {'ok': 1});
      final writes = QueueAdapter()..problem(429, 'rate_limited', 'x', headers: {'retry-after': ['0']});
      final api2 = ApiClient(retryDio(writes, const ReadRetryPolicy()));
      await expectLater(api2.post<void>('orders/place'), throwsA(isA<RateLimitedFailure>()));
      expect(writes.requests, hasLength(1));
    });

    test('ReadRetryPolicy.none never retries', () async {
      final adapter = QueueAdapter()
        ..problem(429, 'rate_limited', 'x', headers: {'retry-after': ['0']});
      final api = ApiClient(retryDio(adapter, ReadRetryPolicy.none));
      await expectLater(api.get('home/bayi', parse: _raw), throwsA(isA<RateLimitedFailure>()));
      expect(adapter.requests, hasLength(1));
    });
  });

  test('CacheStore.removePrefix removes exactly the prefix (no LIKE wildcards)', () async {
    final s = MemoryCacheStore();
    await s.write('u:http.live.v1|bayi/orders?page=1', 1);
    await s.write('u:http.live.v1|bayi/orders_x', 2);
    await s.write('u:http.live.v1|bayi/ordersX', 3);
    await s.write('u:other', 4);
    await s.removePrefix('u:http.live.v1|bayi/orders?');
    expect(s.keys.toSet(), {'u:http.live.v1|bayi/orders_x', 'u:http.live.v1|bayi/ordersX', 'u:other'});
  });

  test('CacheStore.removeExpired removes only expired entries under the prefix', () async {
    final s = MemoryCacheStore();
    await s.write('u:http.live.v1|a', 1, ttl: const Duration(milliseconds: 1));
    await s.write('u:http.live.v1|b', 2, ttl: const Duration(hours: 1));
    await s.write('u:http.live.v1|c', 3);
    await s.write('u:home.bayi', 4, ttl: const Duration(milliseconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await s.removeExpired('u:http.live.v1|');
    expect(s.keys.toSet(), {'u:http.live.v1|b', 'u:http.live.v1|c', 'u:home.bayi'});
  });
}
