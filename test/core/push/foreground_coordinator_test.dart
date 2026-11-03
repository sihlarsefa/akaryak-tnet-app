// Koordinatör (gerçek PushService + sahte FCM / eklenti): ön plan push'u sistem bildirimi olarak
// gösterildiyse uygulama içi balon çıkmaz (aynı push iki kez görünmez); gösterilemediyse (izin yok) balon
// eskisi gibi, "Aç" aynı bloğu açar. Aynı anda gelen adımların her biri ayrı bildirim kalır. Sessiz push
// balonsuz. Yerel bildirim kopyasına dokunuş kilit ekranı dokunuşuyla aynı derin bağlantıyı kurar: bayinin
// "Yeni sipariş"i (`order.finance_approved`) teklif bloğuyla, müşterinin finans onayı odaksız açılır.
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/push/local_notifications.dart';
import 'package:akaryakitnet/core/push/push_payload.dart';
import 'package:akaryakitnet/core/push/push_providers.dart';
import 'package:akaryakitnet/core/push/push_service.dart';
import 'package:akaryakitnet/core/routing/route_access.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/utils/app_messenger.dart';
import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show FlutterLocalNotificationsPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_push.dart';
import '../../support/test_app.dart';
import 'push_test_fakes.dart';

/// Firebase'li PushService (dinleyiciler gerçek; belirteç sabit, ağ yok).
class _TestPush extends PushService {
  _TestPush({
    required super.prefs,
    required super.permissions,
    required super.messaging,
  }) : super(available: true);

  @override
  Future<String?> token() async => 'tok-1';

  @override
  Future<void> deleteToken() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAndroidNotifications plugin;
  late FakeMessaging fcm;

  setUp(() {
    LocalNotifications.debugReset();
    plugin = FakeAndroidNotifications();
    FlutterLocalNotificationsPlatform.instance = plugin;
    fcm = FakeMessaging();
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    LocalNotifications.debugReset();
    await fcm.close();
  });

  /// Uygulama gibi: koordinatör başlar; balonlar listede. [persona] verilirse giriş yapılır.
  Future<(ProviderContainer, List<AppMessage>)> launch({
    TargetPlatform platform = TargetPlatform.android,
    AuthorizationStatus status = AuthorizationStatus.authorized,
    String? persona,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    final h = await TestHarness.create(
      prefs: const {'akn.onboardingDone': true},
    );
    final c = h.container(
      extra: [
        firebaseAvailableProvider.overrideWithValue(true),
        pushServiceProvider.overrideWith((ref) {
          final s = _TestPush(
            prefs: PrefsStore(h.prefs),
            permissions: FakePushPlatform(current: status, answer: status),
            messaging: fcm,
          );
          ref.onDispose(s.dispose);
          return s;
        }),
      ],
    );
    addTearDown(c.dispose);
    final balloons = <AppMessage>[];
    final sub = c.read(appMessengerProvider).stream.listen(balloons.add);
    addTearDown(() => sub.cancel());
    c.read(pushCoordinatorProvider);
    for (var i = 0; i < 400 && !fcm.messages.hasListener; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(fcm.messages.hasListener, isTrue);
    if (persona != null) {
      final s = c.read(sessionControllerProvider.notifier);
      await s.restore();
      final outcome = await s.loginWithPassword(persona, 'demo');
      if (outcome is LoginNeedsCode) {
        await s.verifyCode(outcome.challenge.challengeId, '123456');
      }
      await pumpEventQueue();
    }
    return (c, balloons);
  }

  Future<void> settle() async {
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await pumpEventQueue();
  }

  group('ön plan push\'u', () {
    test(
      'Android: aynı anda gelen her adım ayrı sistem bildirimi; balon yok',
      () async {
        final (_, balloons) = await launch(persona: 'sahip');
        const steps = [
          (4711, 'order.finance_approved', 'Yeni sipariş: SIP-1'),
          (4712, 'order.quote_ready', 'Teklif hazır: SIP-1'),
          (4713, 'order.approved', 'Teklif onaylandı: SIP-1'),
          (4714, 'shipment.planned', 'Sevkiyat planlandı: SIP-1'),
          (4715, 'order.completed', 'Sipariş tamamlandı: SIP-1'),
        ];
        for (final (id, type, title) in steps) {
          fcm.messages.add(
            businessPush(
              notificationId: id,
              type: type,
              title: title,
              body: '$title — ayrıntı',
            ),
          );
        }
        await settle();
        expect(plugin.shown.map((n) => n.title), [for (final s in steps) s.$3]);
        expect(plugin.shown.map((n) => n.id).toSet(), hasLength(5));
        expect(balloons, isEmpty);
      },
    );

    test('iOS: bandı sistem gösterir; yerel kopya ve balon yok', () async {
      final (_, balloons) = await launch(platform: TargetPlatform.iOS);
      expect(fcm.presentation, (alert: true, badge: true, sound: true));
      fcm.messages.add(businessPush());
      await settle();
      expect(plugin.shown, isEmpty);
      expect(balloons, isEmpty);
    });

    test(
      'izin yoksa uygulama içi balon (eskisi gibi): metin, başlık ve "Aç" teklif bloğunu açar',
      () async {
        final (_, balloons) = await launch(
          status: AuthorizationStatus.denied,
          persona: 'sahip',
        );
        fcm.messages.add(businessPush());
        await settle();
        expect(plugin.shown, isEmpty);
        expect(balloons, hasLength(1));
        final b = balloons.single;
        expect(b.title, 'Yeni sipariş: SIP-20261102-12');
        expect(
          b.text,
          'Marmara İnşaat · Motorin 30.000 L — finans onaylı, teklif bekliyor.',
        );
        expect(b.route, '/bayi/orders/12?focus=quote');
      },
    );

    test('iOS izin yoksa da balon', () async {
      final (_, balloons) = await launch(
        platform: TargetPlatform.iOS,
        status: AuthorizationStatus.denied,
      );
      fcm.messages.add(businessPush());
      await settle();
      expect(balloons, hasLength(1));
      expect(plugin.shown, isEmpty);
    });

    test('sessiz push: ne sistem bildirimi ne balon', () async {
      final (_, balloons) = await launch();
      fcm.messages.add(silentPush());
      await settle();
      expect(plugin.shown, isEmpty);
      expect(balloons, isEmpty);
    });
  });

  group('yerel bildirim kopyasına dokunuş', () {
    test(
      'bayi (teklif verebilir): "Yeni sipariş" teklif bloğuyla açılır — kilit ekranı dokunuşu gibi',
      () async {
        final (c, _) = await launch(persona: 'sahip');
        expect(c.read(accessPolicyProvider).quotesOrders, isTrue);
        fcm.messages.add(businessPush());
        await settle();
        plugin.tap(plugin.shown.single.payload);
        await settle();
        expect(c.read(pendingDeepLinkProvider), '/bayi/orders/12?focus=quote');
        expect(c.read(pendingDeepLinkProvider.notifier).fromPush, isFalse);

        // FCM'in dokunuşu (arka plan / kilit ekranı) aynı yeri açar.
        c.read(pendingDeepLinkProvider.notifier).take();
        fcm.opened.add(businessPush());
        await settle();
        expect(c.read(pendingDeepLinkProvider), '/bayi/orders/12?focus=quote');
      },
    );

    test(
      'müşteri: finans onayı odaksız açılır; eski düz rota verisi de açılır',
      () async {
        final (c, _) = await launch(persona: 'musteri');
        final copy = const PushPayload(
          type: 'order.finance_approved',
          notificationId: 77,
          route: '/orders/12',
          category: 'orders',
          title: 'Finans onaylandı: SIP-1',
        ).toLocalPayload();
        plugin.tap(copy);
        await settle();
        expect(c.read(pendingDeepLinkProvider), '/orders/12');

        c.read(pendingDeepLinkProvider.notifier).take();
        plugin.tap('/orders/12002');
        await settle();
        expect(c.read(pendingDeepLinkProvider), '/orders/12002');
      },
    );

    test(
      'oturum bilinmeden (soğuk açılış) dokunuş: rota odakla saklanır, yetki oturumda denetlenir',
      () async {
        final (c, _) = await launch();
        plugin.tap(
          const PushPayload(
            type: 'order.finance_approved',
            notificationId: 4711,
            route: '/bayi/orders/12',
          ).toLocalPayload(),
        );
        await settle();
        expect(c.read(pendingDeepLinkProvider), '/bayi/orders/12?focus=quote');
        expect(c.read(pendingDeepLinkProvider.notifier).fromPush, isTrue);
      },
    );
  });
}
