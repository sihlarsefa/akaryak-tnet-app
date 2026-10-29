// Test derlemesi (TestFlight: `AKN_ENV=test`, `API_MODE=live`) için ortam. Canlı API'nin yerinde
// istekleri kaydeden bir adaptör durur (ağ yok; canlı sunucuya hiç bağlanılmaz). Demo oturumu için
// gecikmesiz sahte dünya (tüm özellik sahteleriyle). Kalıcı depolar (güvenli depo, tercihler, önbellek,
// bekleyen işlemler) kapsayıcılar arasında paylaşılır: yeni kapsayıcı = uygulamanın yeniden açılışı.
import 'dart:convert';

import 'package:akaryakitnet/app/fakes.dart';
import 'package:akaryakitnet/app/wiring.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/env/app_info.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/offline/cache_store.dart';
import 'package:akaryakitnet/core/offline/connectivity.dart';
import 'package:akaryakitnet/core/offline/outbox_store.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/storage/secure_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_adapter.dart';

/// Test derlemesinin ortamı, derleme kararıyla ([AppEnv.fromDefines]) kurulur. Adres canlı sunucu değil;
/// istekleri kayıtçı adaptör yanıtlar.
final testBuildEnv = AppEnv.fromDefines(
  aknEnv: 'test',
  apiMode: 'live',
  apiBaseUrl: 'http://live.akaryakitnet.test:3108/',
  portalBaseUrl: 'http://live.akaryakitnet.test:3107/',
);

/// Canlı sunucunun `app/config` yanıtı: asistan kapalı (sahte sunucuda açık), telefonla giriş kapalı.
const liveConfig = <String, Object?>{
  'contractVersion': 'mobile-v1',
  'apiBuild': 'canli-test',
  'minBuild': 1,
  'latestBuild': 1,
  'maintenance': {'active': false},
  'features': {'otpLogin': false, 'assistant': false},
};

/// Canlı API'deki hatalı giriş yanıtının metni.
const liveLoginError = 'Kullanıcı adı veya şifre hatalı.';

ResponseBody _json(int status, Object? body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json; charset=utf-8'],
  },
);

/// Canlı sunucunun yerine geçen yanıtlar: `app/config` canlı sunucu gibi, `auth/login` 401 (hatalı
/// şifre), diğer her şey 401 (oturum yok). Hiçbir yanıt belirteç vermez.
ResponseBody _liveResponse(RequestOptions o) {
  final path = o.uri.path;
  if (path.endsWith('/app/config')) return _json(200, liveConfig);
  if (path.endsWith('/auth/login')) {
    return _json(401, {
      'title': liveLoginError,
      'status': 401,
      'detail': liveLoginError,
      'code': 'unauthorized',
    });
  }
  return _json(401, {
    'title': 'Oturum açmanız gerekiyor.',
    'status': 401,
    'detail': 'Oturum açmanız gerekiyor.',
    'code': 'unauthorized',
  });
}

/// Sahte sunucunun belirteçleri (`fa.<persona>.<n>.<x>`, `fr.<persona>.<n>.<x>`) ve demo öneki.
final _fakeToken = RegExp(r'\bf[ar]\.[a-z]+\.\d+\.|demo:');

class DemoLiveHarness {
  DemoLiveHarness._({
    required this.server,
    required this.live,
    required this.prefs,
    required this.secure,
    required this.cache,
    required this.outbox,
  });

  /// Sahte dünya (demo oturumu).
  final FakeServer server;

  /// Canlı API'nin yerine geçen kayıtçı adaptör.
  final QueueAdapter live;
  final SharedPreferences prefs;
  final MemorySecureStore secure;
  final MemoryCacheStore cache;
  final MemoryOutboxStore outbox;

  static Future<DemoLiveHarness> create({
    Map<String, Object> prefs = const {'akn.onboardingDone': true},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    return DemoLiveHarness._(
      server: buildFakeServer(latency: false),
      live: QueueAdapter()..fallback = _liveResponse,
      prefs: p,
      secure: MemorySecureStore(),
      cache: MemoryCacheStore(),
      outbox: MemoryOutboxStore(),
    );
  }

  List<Override> get overrides => [
    buildEnvProvider.overrideWithValue(testBuildEnv),
    liveHttpAdapterProvider.overrideWithValue(live),
    appInfoProvider.overrideWithValue(AppInfo.test),
    prefsStoreProvider.overrideWithValue(PrefsStore(prefs)),
    secureStoreProvider.overrideWithValue(secure),
    cacheStoreProvider.overrideWithValue(cache),
    outboxStoreProvider.overrideWithValue(outbox),
    // Bağlantı eklentisi testte yok (zaten çevrimiçi sayılır); kapsayıcı erken kapanınca geç gelen
    // eklenti hatası kapanmış akışa yazmasın.
    isOnlineProvider.overrideWithValue(true),
    ...appWiringOverrides(fakeServer: server),
  ];

  ProviderContainer container({List<Override> extra = const []}) =>
      ProviderContainer(overrides: [...overrides, ...extra]);

  /// Canlı adaptörün gördüğü istekler (yollar `api/v1/` sonrası).
  List<String> get livePaths => [
    for (final r in live.requests)
      '${r.method} ${r.uri.path.split('/api/v1/').last}',
  ];

  /// Canlı adaptöre giden ve bir yetki başlığı ya da sahte sunucunun belirtecini (başlıkta ya da
  /// gövdede) taşıyan istekler. Kayıtçı hiç belirteç vermediği için her zaman boş olmalı.
  List<RecordedRequest> get liveRequestsWithTokens => [
    for (final r in live.requests)
      if (r.header('authorization') != null ||
          _fakeToken.hasMatch(jsonEncode(r.body)) ||
          r.headers.values.any((v) => _fakeToken.hasMatch('$v')))
        r,
  ];
}
