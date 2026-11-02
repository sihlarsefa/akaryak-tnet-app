// A TestFlight-like phone for app-level tests: AKN_ENV=test, API_MODE=live, the live Dio stack (real
// interceptors, token refresh, retries), the in-app fake world behind `liveHttpAdapterProvider`, and
// GET app/config answering like production (features.assistant = false). The stores (secure storage,
// prefs, cache, outbox) belong to the [LiveDevice] and survive between launches: a new ProviderScope
// over the same device is "the app reopened".
//
// [ShapingAdapter] shapes the network per request (delay, 429 / 503 with Retry-After, connection
// error) and records every request, so tests can assert "the bar never waits for data" and "the
// second open is served from the cache".
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/app/fakes.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/app/wiring.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/env/app_info.dart';
import 'package:akaryakitnet/core/network/fake/core_fakes.dart';
import 'package:akaryakitnet/core/network/fake/fake_api_adapter.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/offline/cache_store.dart';
import 'package:akaryakitnet/core/offline/connectivity.dart';
import 'package:akaryakitnet/core/offline/outbox_store.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/storage/secure_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The TestFlight build's environment (dual mode: live API + demo cards).
final testFlightEnv = AppEnv.fromDefines(
  aknEnv: 'test',
  apiMode: 'live',
  apiBaseUrl: 'http://live.akaryakitnet.test:3108/',
  portalBaseUrl: 'http://live.akaryakitnet.test:3107/',
);

/// The demo personas (password `demo`; `merkez` asks for a code, `123456`).
const livePersonas = [
  'sahip', // Bayi yöneticisi
  'finans', // Finans birimi
  'satis', // Satış müdürü
  'saha', // Satış temsilcisi
  'ikmal', // İkmal birimi
  'muhasebe', // Muhasebe birimi
  'sofor', // Şoför
  'musteri', // Müşteri · Yönetici
  'merkez', // Merkez (2FA)
];

/// One request seen by [ShapingAdapter].
class SeenRequest {
  SeenRequest(this.method, this.path, this.query, this.at);
  final String method;
  final String path;
  final Map<String, String> query;
  final DateTime at;

  @override
  String toString() =>
      '$method $path${query.isEmpty ? '' : '?${Uri(queryParameters: query).query}'}';
}

/// What to do with a matching request.
class NetRule {
  const NetRule({
    required this.match,
    this.delay = Duration.zero,
    this.status,
    this.retryAfterSeconds,
    this.connectionError = false,
    this.times,
  });

  /// `GET home/bayi`-style matcher on method + relative path (+ query).
  final bool Function(String method, String path, Map<String, String> query)
  match;
  final Duration delay;

  /// Answer with this status (ProblemDetails body) instead of the fake world's answer.
  final int? status;
  final int? retryAfterSeconds;
  final bool connectionError;

  /// Applies to at most this many matching requests (null: all).
  final int? times;
}

/// Wraps [FakeApiAdapter]: records requests and applies [rules] (first match wins).
class ShapingAdapter implements HttpClientAdapter {
  ShapingAdapter(this.server) : _inner = FakeApiAdapter(server);

  final FakeServer server;
  final FakeApiAdapter _inner;
  final List<SeenRequest> seen = [];
  final List<NetRule> rules = [];
  final Map<NetRule, int> _used = {};

  /// Shaped delays in progress: aborted when Dio closes the adapter (the app was killed, or the API
  /// stack was rebuilt for a demo session), so no timer of the test network outlives the widget
  /// tree. The adapter itself stays usable: a rebuilt stack may reuse it.
  final Set<({Timer timer, Completer<bool> done})> _waits = {};

  /// True when the delay ran out, false when it was aborted by [close].
  Future<bool> _delay(Duration d) {
    final done = Completer<bool>();
    late final ({Timer timer, Completer<bool> done}) entry;
    entry = (
      timer: Timer(d, () {
        _waits.remove(entry);
        if (!done.isCompleted) done.complete(true);
      }),
      done: done,
    );
    _waits.add(entry);
    return done.future;
  }

  /// Requests of [method] to [path] (exact relative path).
  List<SeenRequest> to(String path, {String method = 'GET'}) => [
    for (final r in seen)
      if (r.method == method && r.path == path) r,
  ];

  int count(String path, {String method = 'GET'}) =>
      to(path, method: method).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = FakeApiAdapter.relativePath(options.uri);
    final query = options.uri.queryParameters;
    final method = options.method.toUpperCase();
    seen.add(SeenRequest(method, path, query, DateTime.now()));
    for (final rule in rules) {
      if (!rule.match(method, path, query)) continue;
      final used = _used[rule] ?? 0;
      if (rule.times != null && used >= rule.times!) continue;
      _used[rule] = used + 1;
      if (rule.delay > Duration.zero) {
        if (!await _delay(rule.delay)) {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'closed',
          );
        }
      }
      if (rule.connectionError) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'shaped',
        );
      }
      final status = rule.status;
      if (status != null) {
        return ResponseBody.fromString(
          jsonEncode({
            'title': 'shaped',
            'status': status,
            'detail': status == 429
                ? 'Çok fazla istek. Biraz sonra tekrar deneyin.'
                : 'Hizmet geçici olarak kullanılamıyor.',
            'code': status == 429 ? 'rate_limited' : null,
          }),
          status,
          headers: {
            Headers.contentTypeHeader: ['application/problem+json'],
            if (rule.retryAfterSeconds != null)
              'retry-after': ['${rule.retryAfterSeconds}'],
          },
        );
      }
      break;
    }
    return _inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {
    for (final w in [..._waits]) {
      w.timer.cancel();
      if (!w.done.isCompleted) w.done.complete(false);
    }
    _waits.clear();
    _inner.close(force: force);
  }
}

/// Matches `GET <path>` exactly, or every path starting with [prefix].
NetRule getRule(
  String path, {
  bool prefix = false,
  Duration delay = Duration.zero,
  int? status,
  int? retryAfterSeconds,
  bool connectionError = false,
  int? times,
}) => NetRule(
  match: (m, p, _) => m == 'GET' && (prefix ? p.startsWith(path) : p == path),
  delay: delay,
  status: status,
  retryAfterSeconds: retryAfterSeconds,
  connectionError: connectionError,
  times: times,
);

/// A phone: its stores outlive a launch.
class LiveDevice {
  LiveDevice._(this.prefs);

  final SharedPreferences prefs;
  final secure = MemorySecureStore();
  final cache = MemoryCacheStore();
  final outbox = MemoryOutboxStore();

  /// The fake world of the last launch (one world per device: data survives a reopen).
  FakeServer? _server;

  /// The network of the current launch.
  late ShapingAdapter net;

  static Future<LiveDevice> create({bool biometricLock = false}) async {
    SharedPreferences.setMockInitialValues({
      'akn.onboardingDone': true,
      if (biometricLock) 'akn.biometricLock': true,
    });
    return LiveDevice._(await SharedPreferences.getInstance());
  }

  FakeServer get server => _server ??= _buildServer();

  static FakeServer _buildServer() {
    final server = buildFakeServer(latency: false);
    server.get('app/config', (req) {
      final cfg = fakeAppConfig();
      // Production, 2026-11-02: GET /api/v1/app/config → features.assistant = false.
      (cfg['features']! as Map<String, Object?>)['assistant'] = false;
      return cfg;
    }, anonymous: true);
    return server;
  }

  List<Override> overrides({
    List<NetRule> rules = const [],
    List<Override> extra = const [],
  }) {
    net = ShapingAdapter(server)..rules.addAll(rules);
    return [
      buildEnvProvider.overrideWithValue(testFlightEnv),
      liveHttpAdapterProvider.overrideWithValue(net),
      appInfoProvider.overrideWithValue(AppInfo.test),
      prefsStoreProvider.overrideWithValue(PrefsStore(prefs)),
      secureStoreProvider.overrideWithValue(secure),
      cacheStoreProvider.overrideWithValue(cache),
      outboxStoreProvider.overrideWithValue(outbox),
      isOnlineProvider.overrideWithValue(true),
      ...extra,
      ...appWiringOverrides(fakeServer: server),
    ];
  }
}

/// Pumps in 100 ms frames (timers, retries and the splash advance in fake time).
Future<void> pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

/// Opens the app on [device] (a new ProviderScope = a new process).
Future<ProviderContainer> launchApp(
  WidgetTester tester,
  LiveDevice device, {
  List<NetRule> rules = const [],
  List<Override> extra = const [],
  Duration settle = const Duration(seconds: 3),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: device.overrides(rules: rules, extra: extra),
      child: const AknApp(),
    ),
  );
  await pumpFor(tester, settle);
  return ProviderScope.containerOf(tester.element(find.byType(AknApp)));
}

/// Kills the app (the stores stay).
Future<void> killApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await pumpFor(tester, const Duration(milliseconds: 300));
}

/// Signs [user] in through the session controller (as the login page does).
Future<void> signIn(
  WidgetTester tester,
  ProviderContainer c,
  String user, {
  Duration settle = const Duration(seconds: 3),
}) async {
  await tester.runAsync(() async {
    final s = c.read(sessionControllerProvider.notifier);
    final outcome = await s.loginWithPassword(user, 'demo');
    if (outcome is LoginNeedsCode) {
      await s.verifyCode(outcome.challenge.challengeId, '123456');
    }
  });
  await pumpFor(tester, settle);
}

/// The router's current location is inside the tab shell.
bool inShell(ProviderContainer c) {
  final cfg = c.read(routerProvider).routerDelegate.currentConfiguration;
  return cfg.matches.isNotEmpty && cfg.matches.first is ShellRouteMatch;
}

String currentLocation(ProviderContainer c) =>
    c.read(routerProvider).routerDelegate.currentConfiguration.uri.toString();

/// One line for failure messages.
String describeShell(ProviderContainer c) =>
    '${c.read(sessionControllerProvider).runtimeType} at ${currentLocation(c)}, '
    'inShell=${inShell(c)}, '
    'navLayout.bar=${c.read(navLayoutProvider).bar.map((d) => d.id.name).toList()}, '
    'bars=${find.byType(AnimatedBottomBar).evaluate().length}';

/// The session is open (authenticated or locked).
bool sessionOpen(ProviderContainer c) {
  final s = c.read(sessionControllerProvider);
  return s is SessionAuthenticated || s is SessionLocked;
}
