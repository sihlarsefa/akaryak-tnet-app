import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/env/app_info.dart';
import 'package:akaryakitnet/core/network/fake/core_fakes.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/storage/secure_store.dart';
import 'package:akaryakitnet/features/bayi/application/bayi_runtime.dart';
import 'package:akaryakitnet/features/bayi/bayi_fake.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bayi testleri için yalıtılmış ortam: yalnızca çekirdek + bayi sahteleri (diğer özelliklerin
/// sahteleri değişse de bu testler etkilenmez), gecikmesiz sunucu, bellek içi depolar, ağ yok.
class BayiHarness {
  BayiHarness._(this.server, this.prefs, this.secure);

  final FakeServer server;
  final SharedPreferences prefs;
  final MemorySecureStore secure;

  FakeWorld get world => server.world;

  static Future<BayiHarness> create({
    Map<String, Object> prefs = const {'akn.onboardingDone': true},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    final server = FakeServer.forTests();
    registerCoreFakes(server);
    registerBayiFakes(server);
    // Paylaşılan uçlar bir mikro görev sonra kaydolur.
    await Future<void>.delayed(Duration.zero);
    return BayiHarness._(server, p, MemorySecureStore());
  }

  List<Override> get overrides => [
    appEnvProvider.overrideWithValue(AppEnv.fakeForTests),
    appInfoProvider.overrideWithValue(AppInfo.test),
    prefsStoreProvider.overrideWithValue(PrefsStore(prefs)),
    secureStoreProvider.overrideWithValue(secure),
    fakeServerProvider.overrideWithValue(server),
    bayiRetryDelaysProvider.overrideWithValue(const []),
  ];

  ProviderContainer container({List<Override> extra = const []}) =>
      ProviderContainer(overrides: [...overrides, ...extra]);

  /// Personayla giriş (sahte şifre `demo`).
  static Future<void> login(ProviderContainer c, String persona) async {
    final outcome = await c
        .read(sessionControllerProvider.notifier)
        .loginWithPassword(persona, 'demo');
    if (outcome is LoginNeedsCode) {
      await c
          .read(sessionControllerProvider.notifier)
          .verifyCode(outcome.challenge.challengeId, '123456');
    }
  }
}
