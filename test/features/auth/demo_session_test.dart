// Test derlemesi (TestFlight: `AKN_ENV=test`, `API_MODE=live`) uçtan uca, bütün uygulamayla (`AknApp`):
// giriş ekranında canlı form ve demo kartları birlikte (sahip kararı); form canlı API'ye gider; demo
// kartı o oturum için uygulamayı sahte dünyaya geçirir (canlı API'ye sıfır istek, şerit "DEMO", ana sayfa
// açılır, push kaydı sahte sunucuya); çıkışta uygulama canlı kipe döner; demo oturumundayken kapanıp
// yeniden açılan uygulama sahte belirteci canlı API'ye hiç göndermez. Canlı API kayıtçı bir adaptördür
// (ağ yok).
import 'dart:async';

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/app_overlays.dart';
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/app/dev/dev_menu.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/offline/cache_store.dart';
import 'package:akaryakitnet/core/routing/app_routes.dart';
import 'package:akaryakitnet/core/routing/route_access.dart';
import 'package:akaryakitnet/core/storage/secure_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/auth/presentation/widgets/demo_accounts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/a11y.dart' show settleIo;
import '../../support/demo_live_harness.dart';
import 'auth_test_support.dart';

/// Etiketi alanın üstünde duran metin alanı.
Finder _field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(AknTextField)),
  matching: find.byType(TextField),
);

/// Köşe şeridinin çizdiği yazı ("TEST", "DEMO"); şerit yoksa null.
String? _ribbon(WidgetTester tester) {
  final paints = find.descendant(
    of: find.byType(EnvRibbon),
    matching: find.byType(CustomPaint),
  );
  for (final e in paints.evaluate()) {
    final painter = (e.widget as CustomPaint).painter;
    if (painter != null &&
        painter.runtimeType.toString() == '_CornerRibbonPainter') {
      return (painter as dynamic).label as String;
    }
  }
  return null;
}

/// Uygulamayı açar (açılış animasyonu biter, giriş ekranı gelir) ve kapsayıcıyı döndürür.
Future<ProviderContainer> _launch(
  WidgetTester tester,
  DemoLiveHarness h,
) async {
  await tester.pumpWidget(
    ProviderScope(overrides: h.overrides, child: const AknApp()),
  );
  await pumpFor(tester, const Duration(seconds: 2));
  return ProviderScope.containerOf(
    tester.element(find.byType(AknApp)),
    listen: false,
  );
}

/// Canlı formdan giriş denemesi.
Future<void> _liveLogin(WidgetTester tester, String user) async {
  await tester.enterText(_field('Kullanıcı adı'), user);
  await tester.enterText(_field('Şifre'), 'gizli-sifre');
  await tapVisible(tester, find.text('Giriş yap'));
  await pumpFor(tester, const Duration(milliseconds: 600));
}

/// Demo kartına dokunur ve oturum açılana kadar bekler.
Future<void> _demoLogin(
  WidgetTester tester,
  ProviderContainer c,
  String name,
) async {
  await tapVisible(tester, find.text(name));
  await pumpUntil(tester, () => isSignedIn(c));
  await pumpFor(tester, const Duration(seconds: 2));
  await settleIo(tester);
}

void main() {
  setUp(() => AknMotion.ambient = false);

  testWidgets(
    'giriş ekranı: canlı form ve demo kartları birlikte, demo derlemesindeki sırayla',
    (tester) async {
      setPhoneSize(tester, const Size(390, 844));
      final h = await DemoLiveHarness.create();
      final c = await _launch(tester, h);

      expect(find.text('Hoş geldiniz'), findsOneWidget);
      expect(find.text('Demo hesaplarıyla girin'), findsOneWidget);
      expect(find.text('Kendi hesabınızla girin'), findsOneWidget);
      expect(_field('Kullanıcı adı'), findsOneWidget);
      expect(_field('Şifre'), findsOneWidget);
      expect(find.text('Giriş yap'), findsOneWidget);
      final cards = tester
          .widgetList<DemoPersonaCard>(find.byType(DemoPersonaCard))
          .map((w) => w.account.key)
          .toList();
      expect(cards, [for (final a in demoAccounts()) a.key]);

      final env = c.read(appEnvProvider);
      expect(env.env, AknEnv.test);
      expect(env.isFake, isFalse);
      expect(env.demoOnDemand, isTrue);
      expect(_ribbon(tester), 'TEST');
      // Açılış canlı sunucuyla (yapılandırma ve sunucu yoklaması); sahte dünyaya dokunulmadı.
      expect(h.livePaths, contains('GET app/config'));
      expect(h.server.auth.sessions, isEmpty);
      expect(h.liveRequestsWithTokens, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('canlı form canlı API\'ye gider (sahte dünyaya değil)', (
    tester,
  ) async {
    setPhoneSize(tester, const Size(390, 844));
    final h = await DemoLiveHarness.create();
    final c = await _launch(tester, h);

    await _liveLogin(tester, 'ahmet@firma.com.tr');
    final login = h.live.requests.where((r) => r.path.endsWith('auth/login'));
    expect(login, hasLength(1));
    expect(
      (login.single.body! as Map)['userNameOrEmail'],
      'ahmet@firma.com.tr',
    );
    expect(find.text(liveLoginError), findsOneWidget);
    expect(c.read(sessionControllerProvider), isA<SessionUnauthenticated>());
    expect(c.read(appEnvProvider).isFake, isFalse);
    expect(h.server.auth.sessions, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'demo kartı: sahte dünyada oturum, canlı API\'ye sıfır istek, şerit DEMO, ana sayfa açılır',
    (tester) async {
      setPhoneSize(tester, const Size(390, 844));
      final h = await DemoLiveHarness.create();
      final c = await _launch(tester, h);
      final before = h.live.requests.length;

      await _demoLogin(tester, c, 'Selin Aydın');
      expect(isSignedIn(c), isTrue);
      expect(c.read(sessionControllerProvider).access!.userName, 'musteri');
      expect(
        h.live.requests.length,
        before,
        reason: 'canlı API\'ye giden: ${h.livePaths.skip(before)}',
      );
      final env = c.read(appEnvProvider);
      expect(env.isFake, isTrue);
      expect(env.demoSession, isTrue);
      expect(env.badge, 'Test, sahte API');
      expect(_ribbon(tester), 'DEMO');
      // Ana sayfa (müşteri kabuğu) açıldı; giriş ekranı gitti.
      expect(find.byType(AnimatedBottomBar), findsOneWidget);
      expect(find.byType(DemoPersonaCard), findsNothing);
      expect(find.byType(ErrorState), findsNothing);
      // Push: cihaz kaydı sahte sunucuya gitti; canlıya hiçbir şey kaydedilmedi.
      expect(
        h.server.auth.sessions['musteri']?['test-device']?.pushEnabled,
        isFalse,
      );
      expect(h.livePaths.where((p) => p.contains('devices')), isEmpty);
      // Yapılandırma sahte sunucudan (asistan açık); önbellekte canlı yanıt kalır.
      expect(c.read(appConfigProvider).features.assistant, isTrue);
      final cached = await h.cache.read(CacheKeys.appConfig);
      expect((cached!.value as Map)['apiBuild'], 'canli-test');
      // Belirteç demo olarak yazıldı (soğuk açılışta yüklenmez).
      expect(h.secure.values[SecureKeys.refresh], startsWith('demo:'));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'demo oturumundan çıkış: uygulama canlı kipe döner, sonraki giriş canlı API\'ye gider',
    (tester) async {
      setPhoneSize(tester, const Size(390, 844));
      final h = await DemoLiveHarness.create();
      final c = await _launch(tester, h);
      await _demoLogin(tester, c, 'Selin Aydın');
      expect(c.read(appEnvProvider).demoSession, isTrue);

      await tester.runAsync(
        () => c.read(sessionControllerProvider.notifier).signOut(),
      );
      await pumpFor(tester, const Duration(seconds: 1));
      await settleIo(tester);

      final env = c.read(appEnvProvider);
      expect(env.isFake, isFalse);
      expect(env.demoSession, isFalse);
      expect(_ribbon(tester), 'TEST');
      expect(c.read(sessionControllerProvider), isA<SessionUnauthenticated>());
      expect(h.secure.values.containsKey(SecureKeys.refresh), isFalse);
      // Giriş ekranı yine iki yolla: demo kartları ve canlı form.
      expect(find.text('Demo hesaplarıyla girin'), findsOneWidget);
      expect(find.text('Giriş yap'), findsOneWidget);
      // Yapılandırma yeniden canlı sunucudan.
      expect(c.read(appConfigProvider).features.assistant, isFalse);

      final before = h.live.requests.length;
      await _liveLogin(tester, 'ahmet@firma.com.tr');
      final after = h.livePaths.skip(before).toList();
      expect(after, contains('POST auth/login'));
      expect(find.text(liveLoginError), findsOneWidget);
      expect(h.liveRequestsWithTokens, isEmpty);

      // Kart yine demo oturumu açar.
      await _demoLogin(tester, c, 'Selin Aydın');
      expect(c.read(appEnvProvider).demoSession, isTrue);
      expect(_ribbon(tester), 'DEMO');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'demo oturumundayken kapanıp yeniden açılan uygulama: giriş ekranı canlı kipte, sahte belirteç canlı API\'ye gitmez',
    (tester) async {
      setPhoneSize(tester, const Size(390, 844));
      final h = await DemoLiveHarness.create();
      var c = await _launch(tester, h);
      await _demoLogin(tester, c, 'Selin Aydın');
      expect(h.secure.values[SecureKeys.refresh], startsWith('demo:'));

      // Uygulama kapanır (çıkış yok); aynı depolarla yeniden açılır.
      await tester.pumpWidget(const SizedBox());
      await pumpFor(tester, const Duration(milliseconds: 300));
      final before = h.live.requests.length;
      c = await _launch(tester, h);
      await settleIo(tester);

      expect(c.read(sessionControllerProvider), isA<SessionUnauthenticated>());
      expect(c.read(appEnvProvider).isFake, isFalse);
      expect(_ribbon(tester), 'TEST');
      expect(find.text('Demo hesaplarıyla girin'), findsOneWidget);
      expect(find.text('Giriş yap'), findsOneWidget);
      expect(h.secure.values.containsKey(SecureKeys.refresh), isFalse);
      expect(h.secure.values.containsKey(SecureKeys.userId), isFalse);
      // Açılışın canlı istekleri (yapılandırma, sunucu yoklaması) var; hiçbiri belirteç taşımaz, oturum
      // ucu (yenileme, iptal, me/access) çağrılmaz.
      final startup = h.livePaths.skip(before).toList();
      expect(startup, contains('GET app/config'));
      expect(h.liveRequestsWithTokens, isEmpty);
      expect(
        startup.where((p) => p.contains('auth/') || p.contains('me/')),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'demo oturumunda geliştirici menüsü: persona değişimi sahte dünyada kalır',
    (tester) async {
      setPhoneSize(tester, const Size(390, 844));
      final h = await DemoLiveHarness.create();
      final c = await _launch(tester, h);
      final router = c.read(routerProvider);

      // Canlı kipte `/dev` kapalı: giriş ekranına dönülür.
      router.go(AppRoutes.dev);
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.byType(DevMenuPage), findsNothing);
      expect(find.text('Demo hesaplarıyla girin'), findsOneWidget);

      await _demoLogin(tester, c, 'Selin Aydın');
      final before = h.live.requests.length;
      unawaited(router.push<void>(AppRoutes.dev));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.byType(DevMenuPage), findsOneWidget);

      final burak = find.text('Burak Yılmaz');
      await tester.scrollUntilVisible(
        burak,
        300,
        scrollable: find.descendant(
          of: find.byType(DevMenuPage),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(burak);
      await pumpUntil(
        tester,
        () => c.read(sessionControllerProvider).access?.userName == 'talep',
      );
      await pumpFor(tester, const Duration(seconds: 1));
      expect(c.read(sessionControllerProvider).access?.userName, 'talep');
      expect(c.read(appEnvProvider).demoSession, isTrue);
      expect(
        h.live.requests.length,
        before,
        reason: 'canlı API\'ye giden: ${h.livePaths.skip(before)}',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'giriş ekranında bekleyen canlı bağlantı (push) demo oturumunda açılmaz',
    (tester) async {
      setPhoneSize(tester, const Size(390, 844));
      final h = await DemoLiveHarness.create();
      final c = await _launch(tester, h);
      // Soğuk açılışta canlı sunucunun push'una dokunuldu; oturum henüz yok. (Sahte dünyada da var olan
      // bir sipariş: bağlantı taşınsaydı demo oturumunda açılırdı.)
      final orderId = h.server.world.orders.firstWhere(
        (o) => o['customerId'] == 101,
      )['id'];
      c
          .read(pendingDeepLinkProvider.notifier)
          .set('/orders/$orderId', fromPush: true);
      await tester.pump();

      await _demoLogin(tester, c, 'Selin Aydın');
      expect(c.read(pendingDeepLinkProvider), isNull);
      // Üstteki sayfa (soğuk açılış hedefi ilk sekmenin üstüne açılırdı) ilk sekme.
      expect(
        c
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration
            .last
            .matchedLocation,
        c.read(navLayoutProvider).initialLocation,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
