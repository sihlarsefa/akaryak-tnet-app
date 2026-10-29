// Derleme zamanı koruması (spec D.7): `kFakeApiCompiled` sabiti bu sürecin `AKN_ENV` tanımına uyar.
// Normal test çalışmasında (tanım yok = `dev`) kural tablosu ve sabitin kurala uyumu sınanır. Canlı ve
// test derlemesinin gerçek tanımlarıyla da çalıştırılır (sabit o zaman o derlemedeki değeri alır):
//
//   flutter test test/core/fake_compile_guard_test.dart --dart-define-from-file=env/prod.json
//   flutter test test/core/fake_compile_guard_test.dart --dart-define-from-file=env/test.json
import 'package:akaryakitnet/app/wiring.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/network/fake/fake_api_adapter.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/features/auth/presentation/widgets/demo_accounts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _define = String.fromEnvironment('AKN_ENV', defaultValue: 'dev');

void main() {
  test('kural: canlı ortam adı sahte sunucuyu derlemez', () {
    for (final name in const [
      'prod',
      'production',
      'PROD',
      'Prod',
      'PRODUCTION',
      'Production',
    ]) {
      expect(fakeApiCompiledFor(name), isFalse, reason: name);
    }
    for (final name in const ['dev', 'test', '']) {
      expect(fakeApiCompiledFor(name), isTrue, reason: name);
    }
  });

  test('sabit bu sürecin AKN_ENV tanımına uyar ("$_define")', () {
    expect(kFakeApiCompiled, fakeApiCompiledFor(_define));
  });

  test(
    'canlı derleme tanımlarıyla: sahte sunucu, demo kartı ve demo oturumu yok',
    () {
      expect(kFakeApiCompiled, isFalse);
      final env = AppEnv.fromEnvironment();
      expect(env.isProd, isTrue);
      expect(env.isFake, isFalse);
      expect(env.demoOnDemand, isFalse);
      expect(env.asDemoSession(), same(env));
      final c = ProviderContainer(
        overrides: [
          buildEnvProvider.overrideWithValue(env),
          ...appWiringOverrides(),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(demoLoginsEnabledProvider), isFalse);
      expect(c.read(demoSessionProvider.notifier).start(), isFalse);
      expect(c.read(appEnvProvider).isFake, isFalse);
      expect(
        c.read(dioProvider).httpClientAdapter,
        isNot(isA<FakeApiAdapter>()),
      );
    },
    skip: kFakeApiCompiled
        ? 'yalnızca --dart-define-from-file=env/prod.json ile çalışır'
        : false,
  );

  test(
    'test derlemesi tanımlarıyla: sahte sunucu derlenir, açılış canlı, demo oturumu sunulur',
    () {
      expect(kFakeApiCompiled, isTrue);
      final env = AppEnv.fromEnvironment();
      expect(env.env, AknEnv.test);
      expect(env.isFake, isFalse);
      expect(env.demoOnDemand, isTrue);
      final c = ProviderContainer(
        overrides: [
          buildEnvProvider.overrideWithValue(env),
          ...appWiringOverrides(),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(demoLoginsEnabledProvider), isTrue);
      expect(
        c.read(dioProvider).httpClientAdapter,
        isNot(isA<FakeApiAdapter>()),
      );
      expect(c.read(demoSessionProvider.notifier).start(), isTrue);
      expect(c.read(dioProvider).httpClientAdapter, isA<FakeApiAdapter>());
    },
    skip: _define == 'test'
        ? false
        : 'yalnızca --dart-define-from-file=env/test.json ile çalışır',
  );
}
