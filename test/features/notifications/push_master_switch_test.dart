// Bildirim ayarları → "Anlık bildirimler — Bildirimler telefonuma gelsin" (sahip isteği 2026-10-30):
// açınca izin hiç sorulmadıysa sistem penceresi, reddedildiyse telefon ayarlarına götüren sayfa;
// kapatınca cihaz kaydı `pushEnabled: false` (bildirim kutusu çalışır). Seçim cihazda saklanır,
// uygulama yeniden açıldığında ve yeniden girişte kalır; kategori anahtarları ana anahtar kapalıyken
// soluk ve kilitli. Ağ yok; sahte sunucu gecikmesiz.
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/network/fake/fake_auth.dart';
import 'package:akaryakitnet/core/push/push_providers.dart';
import 'package:akaryakitnet/core/push/push_service.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/features/notifications/copy.dart';
import 'package:akaryakitnet/features/notifications/presentation/notification_settings_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_push.dart';
import '../../support/test_app.dart';
import '../profile/a8_kit.dart';

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// Firebase yapılandırılmış gibi: [platform] izni, sabit belirteç; ayarlar sayfasının açtığı telefon
/// ayarları [opened]'a yazılır.
List<Override> _pushOn(
  SharedPreferences prefs,
  FakePushPlatform platform, {
  List<String>? opened,
}) => [
  firebaseAvailableProvider.overrideWithValue(true),
  pushServiceProvider.overrideWith((ref) {
    final s = FakePushService(prefs: PrefsStore(prefs), permissions: platform);
    ref.onDispose(s.dispose);
    return s;
  }),
  pushSettingsOpenerProvider.overrideWithValue(() async {
    opened?.add('app-settings');
    return true;
  }),
];

Future<void> _login(ProviderContainer c, String persona) async {
  final s = c.read(sessionControllerProvider.notifier);
  final outcome = await s.loginWithPassword(persona, 'demo');
  if (outcome is LoginNeedsCode) {
    await s.verifyCode(outcome.challenge.challengeId, '123456');
  }
}

FakeDeviceSession? _device(Map<String, Map<String, FakeDeviceSession>> s) =>
    s['musteri']?['test-device'];

/// Ana anahtarın satırı ve anahtarı.
Finder get _masterRow => find.ancestor(
  of: find.text(NotificationsCopy.masterTitle),
  matching: find.byType(InkWell),
);

Switch _master(WidgetTester tester) => tester.widget<Switch>(
  find.descendant(of: _masterRow.first, matching: find.byType(Switch)),
);

/// "Teklifler" kategorisinin anahtarı.
Switch _quotes(WidgetTester tester) => tester.widget<Switch>(
  find.descendant(
    of: find
        .ancestor(of: find.text('Teklifler'), matching: find.byType(InkWell))
        .first,
    matching: find.byType(Switch),
  ),
);

double _categoriesOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.text('Teklifler'),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    )
    .opacity;

void main() {
  group('ana anahtar (denetleyici)', () {
    test(
      'kapat → pushEnabled false (belirteç kalır); yeniden açılış ve yeniden girişte kapalı kalır; '
      'aç → pushEnabled true',
      () async {
        final h = await TestHarness.create(
          prefs: const {'akn.onboardingDone': true},
        );
        final platform = FakePushPlatform(
          current: AuthorizationStatus.authorized,
        );
        final c = h.container(extra: _pushOn(h.prefs, platform));
        c.read(pushCoordinatorProvider);
        await c.read(sessionControllerProvider.notifier).restore();
        await _login(c, 'musteri');
        final devices = h.server.auth.sessions;
        await _until(() => _device(devices)?.pushToken != null);
        expect(_device(devices)?.pushEnabled, isTrue);
        expect(c.read(pushOptInProvider), isTrue, reason: 'varsayılan açık');

        final optIn = c.read(pushOptInProvider.notifier);
        await optIn.turnOff();
        await optIn.pendingSync;
        expect(c.read(pushOptInProvider), isFalse);
        expect(h.prefs.getBool(PrefKeys.pushOptIn), isFalse);
        expect(_device(devices)?.pushEnabled, isFalse);
        expect(_device(devices)?.pushToken, 'tok-1');

        // Yeniden giriş: koordinatörün kaydı da anahtara uyar.
        await c.read(sessionControllerProvider.notifier).signOut();
        expect(h.prefs.getBool(PrefKeys.pushOptIn), isFalse, reason: 'çıkış');
        await _login(c, 'musteri');
        await _until(() => _device(devices)?.pushToken != null);
        expect(_device(devices)?.pushEnabled, isFalse);
        c.dispose();

        // Yeniden açılış (yeni kapsayıcı, aynı tercihler): anahtar kapalı, kayıt kapalı.
        final again = h.container(extra: _pushOn(h.prefs, platform));
        addTearDown(again.dispose);
        expect(again.read(pushOptInProvider), isFalse);
        again.read(pushCoordinatorProvider);
        _device(devices)?.pushEnabled = true;
        _device(devices)?.pushToken = null;
        await again.read(sessionControllerProvider.notifier).restore();
        expect(
          again.read(sessionControllerProvider),
          isA<SessionAuthenticated>(),
        );
        await _until(() => _device(devices)?.pushToken != null);
        expect(_device(devices)?.pushEnabled, isFalse);

        // Açınca: izin zaten var, pencere açılmaz; kayıt açık.
        final on = again.read(pushOptInProvider.notifier);
        expect(await on.turnOn(), PushPermission.granted);
        await on.pendingSync;
        expect(platform.requests, 0);
        expect(again.read(pushOptInProvider), isTrue);
        expect(_device(devices)?.pushEnabled, isTrue);
      },
    );

    test('aç: izin hiç sorulmadıysa sistem penceresi bir kez açılır', () async {
      final h = await TestHarness.create(
        prefs: const {
          'akn.onboardingDone': true,
          PrefKeys.pushOptIn: false,
          // Açılış isteği bu testin konusu değil.
          PrefKeys.pushLaunchAsked: true,
        },
      );
      final platform = FakePushPlatform();
      final c = h.container(extra: _pushOn(h.prefs, platform));
      addTearDown(c.dispose);
      await c.read(sessionControllerProvider.notifier).restore();
      await _login(c, 'musteri');
      final optIn = c.read(pushOptInProvider.notifier);
      expect(await optIn.turnOn(), PushPermission.granted);
      await optIn.pendingSync;
      expect(platform.requests, 1);
      expect(_device(h.server.auth.sessions)?.pushToken, 'tok-1');
      expect(_device(h.server.auth.sessions)?.pushEnabled, isTrue);
    });

    test(
      'aç: izin reddedilmişse pencere açılmaz, "reddedildi" döner (sayfa telefon ayarlarını önerir)',
      () async {
        final h = await TestHarness.create(
          prefs: const {
            'akn.onboardingDone': true,
            PrefKeys.pushOptIn: false,
            PrefKeys.pushLaunchAsked: true,
          },
        );
        final platform = FakePushPlatform(current: AuthorizationStatus.denied);
        final c = h.container(extra: _pushOn(h.prefs, platform));
        addTearDown(c.dispose);
        await c.read(sessionControllerProvider.notifier).restore();
        await _login(c, 'musteri');
        final optIn = c.read(pushOptInProvider.notifier);
        expect(await optIn.turnOn(), PushPermission.denied);
        await optIn.pendingSync;
        expect(platform.requests, 0);
        // Seçim açık: telefon ayarlarından izin verilince bildirimler hemen gelir.
        expect(c.read(pushOptInProvider), isTrue);
        expect(_device(h.server.auth.sessions)?.pushEnabled, isTrue);
      },
    );

    test('anahtarın görünen değeri: açık + izin var', () {
      expect(pushSwitchValue(true, PushPermission.granted), isTrue);
      expect(pushSwitchValue(true, null), isTrue, reason: 'izin okunurken');
      expect(pushSwitchValue(false, PushPermission.granted), isFalse);
      expect(pushSwitchValue(true, PushPermission.denied), isFalse);
      expect(pushSwitchValue(true, PushPermission.notDetermined), isFalse);
      expect(pushSwitchValue(true, PushPermission.unavailable), isFalse);
    });
  });

  group('ana anahtar (ekran)', () {
    setUp(fixClock);

    testWidgets(
      'en üstte "Anlık bildirimler"; kapatınca kayıt kapanır ve kategoriler kilitlenir, açınca geri gelir',
      (tester) async {
        setPhoneSize(tester, const Size(390, 844));
        final h = await A8Harness.create();
        final platform = FakePushPlatform(
          current: AuthorizationStatus.authorized,
        );
        await pumpA8(
          tester,
          '/notifications/settings',
          harness: h,
          overrides: _pushOn(h.prefs, platform),
        );
        expect(find.text(NotificationsCopy.masterTitle), findsOneWidget);
        expect(find.text(NotificationsCopy.masterSubtitle), findsOneWidget);
        expect(find.text(NotificationsCopy.pushOffTitle), findsNothing);
        // Ana anahtar kategori kartının üstünde.
        expect(
          tester.getTopLeft(find.text(NotificationsCopy.masterTitle)).dy,
          lessThan(tester.getTopLeft(find.text('Teklifler')).dy),
        );
        expect(_master(tester).value, isTrue);
        expect(find.text(NotificationsCopy.masterOnHint), findsOneWidget);
        expect(_quotes(tester).onChanged, isNotNull);
        expect(_categoriesOpacity(tester), 1);

        await tester.tap(find.byType(Switch).first);
        await pumpFor(tester, const Duration(milliseconds: 600));
        expect(_master(tester).value, isFalse);
        expect(find.text(NotificationsCopy.masterOffHint), findsOneWidget);
        expect(
          _quotes(tester).onChanged,
          isNull,
          reason: 'kategoriler kilitli',
        );
        expect(_quotes(tester).value, isTrue, reason: 'seçim olduğu gibi');
        expect(_categoriesOpacity(tester), lessThan(1));
        expect(find.text(NotificationsCopy.categoriesOffHint), findsOneWidget);
        final device = _device(h.server.auth.sessions);
        expect(device?.pushEnabled, isFalse);
        expect(device?.pushToken, 'tok-1');
        expect(h.prefs.getBool(PrefKeys.pushOptIn), isFalse);
        expect(platform.requests, 0);

        // Satırın tamamı dokunulabilir.
        await tester.tap(find.text(NotificationsCopy.masterTitle));
        await pumpFor(tester, const Duration(milliseconds: 600));
        expect(_master(tester).value, isTrue);
        expect(_quotes(tester).onChanged, isNotNull);
        expect(_device(h.server.auth.sessions)?.pushEnabled, isTrue);
        expect(h.prefs.getBool(PrefKeys.pushOptIn), isTrue);
        expect(tester.takeException(), isNull);
        await finish(tester);
      },
    );

    testWidgets('izin hiç sorulmadıysa: açınca sistem penceresi, sonra açık', (
      tester,
    ) async {
      setPhoneSize(tester, const Size(390, 844));
      final h = await A8Harness.create();
      final platform = FakePushPlatform();
      await pumpA8(
        tester,
        '/notifications/settings',
        harness: h,
        overrides: _pushOn(h.prefs, platform),
      );
      expect(_master(tester).value, isFalse);
      expect(find.text(NotificationsCopy.masterAskHint), findsOneWidget);
      expect(_quotes(tester).onChanged, isNull);
      await tester.tap(find.byType(Switch).first);
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(platform.requests, 1);
      expect(_master(tester).value, isTrue);
      expect(_quotes(tester).onChanged, isNotNull);
      expect(_device(h.server.auth.sessions)?.pushEnabled, isTrue);
      expect(find.text(NotificationsCopy.deniedSheetTitle), findsNothing);
      await finish(tester);
    });

    testWidgets(
      'izin reddedilmişse: açınca telefon ayarlarına götüren sayfa; izin verilip dönünce açık',
      (tester) async {
        setPhoneSize(tester, const Size(390, 844));
        final h = await A8Harness.create();
        final platform = FakePushPlatform(current: AuthorizationStatus.denied);
        final opened = <String>[];
        await pumpA8(
          tester,
          '/notifications/settings',
          harness: h,
          overrides: _pushOn(h.prefs, platform, opened: opened),
        );
        expect(_master(tester).value, isFalse);
        expect(find.text(NotificationsCopy.masterDeniedHint), findsOneWidget);
        await tester.tap(find.byType(Switch).first);
        await pumpFor(tester, const Duration(milliseconds: 800));
        expect(
          platform.requests,
          0,
          reason: 'iOS reddedilen izni yeniden sormaz',
        );
        expect(find.text(NotificationsCopy.deniedSheetTitle), findsOneWidget);
        expect(find.text(NotificationsCopy.deniedSheetMessage), findsOneWidget);
        await tester.tap(find.text(NotificationsCopy.openSettings));
        await pumpFor(tester, const Duration(milliseconds: 800));
        expect(opened, ['app-settings']);
        expect(find.text(NotificationsCopy.deniedSheetTitle), findsNothing);
        expect(_master(tester).value, isFalse);

        // Telefon ayarlarında izin verildi, uygulamaya dönüldü.
        platform.current = AuthorizationStatus.authorized;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumpFor(tester, const Duration(milliseconds: 600));
        expect(_master(tester).value, isTrue);
        expect(find.text(NotificationsCopy.masterOnHint), findsOneWidget);
        expect(_device(h.server.auth.sessions)?.pushEnabled, isTrue);
        expect(tester.takeException(), isNull);
        await finish(tester);
      },
    );

    testWidgets('reddedilmişken "Vazgeç": ayarlar açılmaz, anahtar kapalı', (
      tester,
    ) async {
      setPhoneSize(tester, const Size(390, 844));
      final h = await A8Harness.create();
      final platform = FakePushPlatform(current: AuthorizationStatus.denied);
      final opened = <String>[];
      await pumpA8(
        tester,
        '/notifications/settings',
        harness: h,
        overrides: _pushOn(h.prefs, platform, opened: opened),
      );
      await tester.tap(find.byType(Switch).first);
      await pumpFor(tester, const Duration(milliseconds: 800));
      await tester.tap(find.text(NotificationsCopy.notNow));
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(opened, isEmpty);
      expect(_master(tester).value, isFalse);
      await finish(tester);
    });

    testWidgets('hareket azaltmada da çalışır (geçişler anında)', (
      tester,
    ) async {
      setPhoneSize(tester, const Size(390, 844));
      final h = await A8Harness.create();
      final platform = FakePushPlatform(
        current: AuthorizationStatus.authorized,
      );
      await pumpA8(
        tester,
        '/notifications/settings',
        harness: h,
        reduceMotion: true,
        overrides: _pushOn(h.prefs, platform),
      );
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      await tester.pump();
      expect(_master(tester).value, isFalse);
      expect(
        tester
            .widget<AnimatedOpacity>(
              find
                  .ancestor(
                    of: find.text('Teklifler'),
                    matching: find.byType(AnimatedOpacity),
                  )
                  .first,
            )
            .duration,
        Duration.zero,
      );
      await pumpFor(tester, const Duration(milliseconds: 300));
      await finish(tester);
    });

    a11yMatrix('bildirim ayarları · anlık bildirimler anahtarı', (
      tester,
      scale,
      b,
    ) async {
      final h = await A8Harness.create();
      await pumpA8(
        tester,
        '/notifications/settings',
        harness: h,
        textScale: scale,
        brightness: b,
        overrides: _pushOn(
          h.prefs,
          FakePushPlatform(current: AuthorizationStatus.authorized),
        ),
      );
      expect(find.text(NotificationsCopy.masterTitle), findsOneWidget);
      expect(find.text(NotificationsCopy.masterSubtitle), findsOneWidget);
    });
  });
}
