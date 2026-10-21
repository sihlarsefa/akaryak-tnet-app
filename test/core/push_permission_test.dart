// Bildirim izni (spec C.4, C.7): Android 13+ (API 33) eklentisi henüz sorulmamış izni de "reddedildi"
// bildirir. Uygulama izni bir kez sorduğunu saklar; hiç sormadıysa durum "belirlenmedi" sayılır ve
// ön sayfa açılır. İzin bir kez istenir (yerel bildirimler için ikinci bir sistem penceresi yok).
import 'package:akaryakitnet/core/push/push_permission_primer.dart';
import 'package:akaryakitnet/core/push/push_providers.dart';
import 'package:akaryakitnet/core/push/push_service.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android 13+ davranışı: istenmeden önce `denied`; isteyince kullanıcının seçimi.
class _FakePlatform implements PushPermissionPlatform {
  _FakePlatform({this.sdk = 33, this.answer = AuthorizationStatus.denied});

  final int? sdk;
  AuthorizationStatus answer;
  AuthorizationStatus current = AuthorizationStatus.denied;
  int requests = 0;

  @override
  Future<int?> androidSdkInt() async => sdk;

  @override
  Future<AuthorizationStatus> status() async => current;

  @override
  Future<AuthorizationStatus> request() async {
    requests++;
    current = answer;
    return answer;
  }
}

Future<PrefsStore> _prefs([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return PrefsStore(await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('Android 13+', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('hiç sorulmamış izin "belirlenmedi"; bir kez sorulur', () async {
      final prefs = await _prefs();
      final platform = _FakePlatform(answer: AuthorizationStatus.authorized);
      final push = PushService(
        available: true,
        prefs: prefs,
        permissions: platform,
      );
      expect(await push.permission(), PushPermission.notDetermined);
      expect(await push.requestPermission(), isTrue);
      expect(platform.requests, 1, reason: 'tek sistem penceresi');
      expect(prefs.getBool(PrefKeys.pushPermissionRequested), isTrue);
      expect(await push.permission(), PushPermission.granted);
      await push.dispose();
    });

    test('sorulup reddedilen izin "reddedildi" kalır', () async {
      final prefs = await _prefs();
      final platform = _FakePlatform();
      final push = PushService(
        available: true,
        prefs: prefs,
        permissions: platform,
      );
      expect(await push.requestPermission(), isFalse);
      expect(await push.permission(), PushPermission.denied);
      // Uygulama yeniden açıldı: bilgi tercihlerde.
      final again = PushService(
        available: true,
        prefs: prefs,
        permissions: platform,
      );
      expect(await again.permission(), PushPermission.denied);
      await push.dispose();
      await again.dispose();
    });

    test('Android 12 ve öncesi: "kapalı" kullanıcı ayarıdır', () async {
      final push = PushService(
        available: true,
        prefs: await _prefs(),
        permissions: _FakePlatform(sdk: 32),
      );
      expect(await push.permission(), PushPermission.denied);
      await push.dispose();
    });
  });

  test(
    'iOS: sorulmamış izin zaten "belirlenmedi" gelir; "reddedildi" olduğu gibi',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final platform = _FakePlatform(sdk: null);
      final push = PushService(
        available: true,
        prefs: await _prefs(),
        permissions: platform,
      );
      expect(await push.permission(), PushPermission.denied);
      platform.current = AuthorizationStatus.notDetermined;
      expect(await push.permission(), PushPermission.notDetermined);
      await push.dispose();
    },
  );

  testWidgets(
    'Android 13+: girişten sonra ön sayfa açılır, kabul edince izin istenir',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final prefs = await _prefs({'akn.onboardingDone': true});
      final platform = _FakePlatform(answer: AuthorizationStatus.authorized);
      final container = ProviderContainer(
        overrides: [
          prefsStoreProvider.overrideWithValue(prefs),
          firebaseAvailableProvider.overrideWithValue(true),
          pushServiceProvider.overrideWith(
            (ref) => PushService(
              available: true,
              prefs: prefs,
              permissions: platform,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      bool? shown;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AknTheme.light(),
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async =>
                        shown = await maybeShowPushPrimer(context, ref),
                    child: const Text('aç'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Önemli anları kaçırmayın'), findsOneWidget);
      await tester.tap(find.text('Bildirimlere izin ver'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(shown, isTrue);
      expect(platform.requests, 1);
      expect(prefs.getBool(PrefKeys.pushPrimerShown), isTrue);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
