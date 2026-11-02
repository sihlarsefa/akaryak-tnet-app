// Stale-while-revalidate helpers (2026-11-02): the cache-first detail notifier shows the cached value
// at once, refreshes in the background ("güncelleniyor" = isRefreshing with the old value), keeps the
// value when the refresh fails, and goes to the network on invalidate / pull-to-refresh. The first-page
// cache serves a list's cached page once per controller and then revalidates.
import 'dart:async';

import 'package:akaryakitnet/core/network/api_client.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/offline/cache_first.dart';
import 'package:akaryakitnet/core/offline/revalidate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Detail extends CacheFirstFamilyAsyncNotifier<String, int> {
  static final cached = <int, CachedResponse<String>>{};
  static final answers = <Completer<String>>[];
  static int fetches = 0;

  @override
  Future<CachedResponse<String>?> peek(int arg) async => cached[arg];

  @override
  Future<String> fetch(int arg) {
    fetches++;
    final c = Completer<String>();
    answers.add(c);
    return c.future;
  }
}

final _detail = AsyncNotifierProvider.autoDispose.family<_Detail, String, int>(
  _Detail.new,
);

Future<void> _turn() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  setUp(() {
    _Detail.cached.clear();
    _Detail.answers.clear();
    _Detail.fetches = 0;
  });

  group('CacheFirstFamilyAsyncNotifier', () {
    test('cache hit: the cached value at once, then refreshing, then the fresh value', () async {
      final at = DateTime.now().toUtc().subtract(const Duration(minutes: 10));
      _Detail.cached[1] = CachedResponse('old', storedAt: at);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final sub = c.listen(_detail(1), (_, _) {});
      addTearDown(sub.close);
      expect(await c.read(_detail(1).future), 'old');
      expect(_Detail.fetches, 0, reason: 'nothing waited for the network');
      expect(c.read(_detail(1).notifier).cachedAt, at);
      await _turn();
      final refreshing = c.read(_detail(1));
      expect(refreshing.isRefreshing, isTrue, reason: '"güncelleniyor"');
      expect(refreshing.value, 'old', reason: 'content stays');
      expect(_Detail.fetches, 1);
      _Detail.answers.single.complete('new');
      await _turn();
      expect(c.read(_detail(1)).value, 'new');
      expect(c.read(_detail(1)).isRefreshing, isFalse);
      expect(c.read(_detail(1).notifier).cachedAt, isNull);
    });

    test('the background refresh fails (429, offline): the cached value stays, no error page', () async {
      _Detail.cached[2] = CachedResponse('old', storedAt: DateTime.now().toUtc());
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final sub = c.listen(_detail(2), (_, _) {});
      addTearDown(sub.close);
      await c.read(_detail(2).future);
      await _turn();
      _Detail.answers.single.completeError(RateLimitedFailure(const Duration(seconds: 1)));
      await _turn();
      final s = c.read(_detail(2));
      expect(s.hasError, isFalse);
      expect(s.value, 'old');
    });

    test('no cache: from the network; invalidate (pull-to-refresh) goes to the network again', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final sub = c.listen(_detail(3), (_, _) {});
      addTearDown(sub.close);
      final first = c.read(_detail(3).future);
      await _turn();
      _Detail.answers.single.complete('a');
      expect(await first, 'a');
      // A cache entry appears later; the provider still refreshes from the server.
      _Detail.cached[3] = CachedResponse('cached', storedAt: DateTime.now().toUtc());
      c.invalidate(_detail(3));
      final second = c.read(_detail(3).future);
      await _turn();
      expect(c.read(_detail(3)).value, 'a', reason: 'previous value while loading');
      _Detail.answers.last.complete('b');
      expect(await second, 'b');
      expect(_Detail.fetches, 2);
    });
  });

  group('FirstPageCache', () {
    test('serves the cached page once, schedules the revalidation, then always the network', () async {
      final cache = FirstPageCache();
      var revalidations = 0;
      var networks = 0;
      Future<String> load() => cache.page1<String>(
        peek: () async => CachedResponse('cached', storedAt: DateTime.now().toUtc()),
        network: () async {
          networks++;
          return 'net';
        },
        revalidate: () => revalidations++,
      );
      expect(await load(), 'cached');
      expect(revalidations, 0, reason: 'after the list state was set');
      await _turn();
      expect(revalidations, 1);
      expect(await load(), 'net');
      expect(networks, 1);
      cache.reset();
      expect(await load(), 'cached');
    });

    test('no cached page: straight to the network, no extra revalidation', () async {
      final cache = FirstPageCache();
      var revalidations = 0;
      final r = await cache.page1<String>(
        peek: () async => null,
        network: () async => 'net',
        revalidate: () => revalidations++,
      );
      expect(r, 'net');
      await _turn();
      expect(revalidations, 0);
    });
  });

  test('Freshness: only data older than the TTL is stale', () {
    final now = DateTime.utc(2026, 11, 2, 10);
    expect(Freshness.isStale(null, Freshness.list, now: now), isTrue);
    expect(Freshness.isStale(now.subtract(const Duration(minutes: 1)), Freshness.list, now: now), isFalse);
    expect(Freshness.isStale(now.subtract(const Duration(minutes: 3)), Freshness.list, now: now), isTrue);
    expect(Freshness.isStale(now.subtract(const Duration(seconds: 30)), Freshness.decision, now: now), isFalse);
    expect(Freshness.isStale(now.subtract(const Duration(seconds: 50)), Freshness.decision, now: now), isTrue);
  });
}
