import 'package:akaryakitnet/app/fakes.dart';
import 'package:akaryakitnet/app/wiring.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/env/app_info.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/storage/secure_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Testler için hazır ortam: sahte kip, gecikmesiz sahte sunucu (tüm özellik sahteleriyle), bellek
/// içi depolar, sahte tercihler. Ağ yok.
class TestHarness {
  TestHarness._(this.server, this.prefs, this.secure);

  final FakeServer server;
  final SharedPreferences prefs;
  final MemorySecureStore secure;

  /// [prefs] başlangıç tercihleri (ör. `{'akn.onboardingDone': true}`).
  static Future<TestHarness> create({
    Map<String, Object> prefs = const {},
    FakeWorld? world,
    MemorySecureStore? secure,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    final server = buildFakeServer(world: world, latency: false);
    return TestHarness._(server, p, secure ?? MemorySecureStore());
  }

  List<Override> get overrides => [
    appEnvProvider.overrideWithValue(AppEnv.fakeForTests),
    appInfoProvider.overrideWithValue(AppInfo.test),
    prefsStoreProvider.overrideWithValue(PrefsStore(prefs)),
    secureStoreProvider.overrideWithValue(secure),
    ...appWiringOverrides(fakeServer: server),
  ];

  ProviderContainer container({List<Override> extra = const []}) =>
      ProviderContainer(overrides: [...overrides, ...extra]);
}
