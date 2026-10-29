// Test derlemesi (TestFlight: `AKN_ENV=test`, `API_MODE=live`): canlı → demo → canlı döngüsü, oturum
// denetleyicisiyle (arayüzsüz). Canlı API kayıtçı bir adaptördür (ağ yok) ve bu kez girişi kabul eder:
// canlı oturum canlı belirteçle canlıya gider, çıkışı canlıda kapanır; demo oturumunun hiçbir isteği
// canlıya gitmez ve sahte sunucu canlı belirteci hiç görmez; sonraki canlı girişte demo belirteci yoktur.
import 'dart:convert';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/storage/secure_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/demo_live_harness.dart';

ResponseBody _json(int status, Object? body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json; charset=utf-8'],
  },
);

/// Sahte sunucunun belirteçleri (`fa.<persona>.<n>.<x>`, `fr.<persona>.<n>.<x>`) ve demo öneki.
final _fakeToken = RegExp(r'\bf[ar]\.[a-z]+\.\d+\.|demo:');

/// Canlı API'nin belirteçleri (`la-<n>`, `lr-<n>`).
final _liveToken = RegExp(r'\bl[ar]-\d+\b');

/// Sahte yığından geçen isteklerin başlık ve gövdesi (yetki ara katmanından sonra).
class _Spy extends Interceptor {
  final List<String> seen = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    seen.add('${options.path} ${options.headers} ${jsonEncode(options.data)}');
    handler.next(options);
  }
}

void main() {
  test('canlı → demo → canlı: her dünya yalnızca kendi belirtecini görür', () async {
    final h = await DemoLiveHarness.create();
    final musteri = fakePersonas.firstWhere((p) => p.key == 'musteri');
    final liveMe = {
      ...h.server.world.meAccess(musteri),
      'userId': 'live-guid-1',
      'userName': 'ahmet',
    };
    var logins = 0;
    final base = h.live.fallback!;
    h.live.fallback = (o) {
      final path = o.uri.path;
      if (path.endsWith('/app/config')) return base(o);
      if (path.endsWith('/auth/login')) {
        logins++;
        return _json(200, {
          'status': 'ok',
          'tokens': {
            'accessToken': 'la-$logins',
            'accessExpiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 15))
                .toIso8601String(),
            'refreshToken': 'lr-$logins',
            'userId': 'live-guid-1',
          },
        });
      }
      if (path.endsWith('/me/access')) return _json(200, liveMe);
      if (path.endsWith('/auth/logout') || path.endsWith('/devices/current')) {
        return _json(200, const {});
      }
      return _json(404, {
        'title': 'Bulunamadı',
        'status': 404,
        'code': 'not_found',
      });
    };
    final c = h.container();
    addTearDown(c.dispose);
    final s = c.read(sessionControllerProvider.notifier);
    await s.restore();

    // 1) Canlı giriş: belirteç önek almaz; oturum istekleri canlı belirteçle canlıya gider.
    expect(await s.loginWithPassword('ahmet', 'gizli'), isA<LoginSucceeded>());
    expect(c.read(tokenStoreProvider).isDemo, isFalse);
    expect(h.secure.values[SecureKeys.refresh], 'lr-1');
    expect(
      h.live.requests
          .lastWhere((r) => r.path.endsWith('/me/access'))
          .header('authorization'),
      'Bearer la-1',
    );

    // 2) Canlı çıkış: canlı sunucuda kapanır (canlı belirteçle); demo oturumu yoktu, ortam aynı.
    await s.signOut();
    expect(
      h.live.requests
          .singleWhere((r) => r.path.endsWith('/auth/logout'))
          .header('authorization'),
      'Bearer la-1',
    );
    expect(h.secure.values.containsKey(SecureKeys.refresh), isFalse);
    expect(c.read(appEnvProvider).isFake, isFalse);

    // 3) Demo oturumu: canlıya sıfır istek; sahte yığın canlı belirteci hiç taşımaz.
    final beforeDemo = h.live.requests.length;
    expect(c.read(demoSessionProvider.notifier).start(), isTrue);
    final spy = _Spy();
    c.read(dioProvider).interceptors.add(spy);
    expect(await s.loginWithPassword('musteri', 'demo'), isA<LoginSucceeded>());
    expect(h.secure.values[SecureKeys.refresh], startsWith('demo:'));
    await c
        .read(apiClientProvider)
        .get<Object?>('notifications/unread-count', parse: (j) => j);
    await s.signOut();
    expect(
      h.live.requests.length,
      beforeDemo,
      reason: 'canlı API\'ye giden: ${h.livePaths.skip(beforeDemo)}',
    );
    expect(spy.seen, isNotEmpty);
    expect(spy.seen.where(_liveToken.hasMatch), isEmpty);
    expect(c.read(appEnvProvider).isFake, isFalse);
    expect(h.secure.values.containsKey(SecureKeys.refresh), isFalse);

    // 4) Yeniden canlı giriş: canlıya gider; hiçbir canlı istek sahte belirteç taşımamıştır.
    expect(await s.loginWithPassword('ahmet', 'gizli'), isA<LoginSucceeded>());
    expect(h.secure.values[SecureKeys.refresh], 'lr-2');
    expect(c.read(tokenStoreProvider).isDemo, isFalse);
    for (final r in h.live.requests) {
      expect(
        _fakeToken.hasMatch('${r.headers} ${jsonEncode(r.body)}'),
        isFalse,
        reason: '${r.method} ${r.path}',
      );
    }
  });
}
