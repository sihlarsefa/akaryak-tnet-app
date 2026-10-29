// İstatistik widget testi ortamı: yalnızca çekirdek + istatistik sahteleri (diğer özelliklerin sahteleri
// değişse de bu testler etkilenmez), gerçek yönlendirici, desteyi gösteren bir ev sayfası ve diğer
// hedefler için yol gösteren yer tutucular.
import 'dart:async';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/env/app_info.dart';
import 'package:akaryakitnet/core/network/fake/core_fakes.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/offline/connectivity.dart';
import 'package:akaryakitnet/core/routing/nav_keys.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/storage/secure_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/stats/api.dart';
import 'package:akaryakitnet/features/stats/copy.dart';
import 'package:akaryakitnet/features/stats/presentation/deck/manager_stats_deck.dart';
import 'package:akaryakitnet/features/stats/stats_fake.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Çevrimiçi / çevrimdışı anahtarı.
final statsTestOnlineProvider = StateProvider<bool>((ref) => true);

/// İstatistik dışı hedefler (yalnızca yolu gösterir).
const statsStubPaths = [
  '/home',
  '/spending',
  '/limits',
  '/orders',
  '/shipments',
  '/approvals',
  '/customers/:id',
  '/payments',
  '/dispatch',
  '/quote-desk',
  '/field',
  '/notifications',
];

/// Desteyi barındıran ev sayfası.
const hostPath = '/host';

/// Varsayılan tercihler: tanıtım görüldü, deste ipucu gösterildi (sallanma yok).
const statsTestPrefs = <String, Object>{
  'akn.onboardingDone': true,
  StatsKeys.deckHint: true,
};

/// İstatistik uçlarını sarmalar: her isteğin `period` değerini kaydeder; [fail] bir yanıt döndürürse
/// gövde yerine o fırlatılır (403, 404, 500 senaryoları; null → sahte sunucunun normal yanıtı).
class StatsProbe {
  StatsProbe({this.fail});

  final List<String> bayi = [];
  final List<String> customer = [];
  FakeResponse? Function()? fail;

  int get total => bayi.length + customer.length;

  void install(FakeServer s) {
    s.get('stats/bayi', (req) {
      bayi.add(req.query('period') ?? '');
      final f = fail?.call();
      if (f != null) throw f;
      return StatsFake.handleBayi(req);
    });
    s.get('stats/customer', (req) {
      customer.add(req.query('period') ?? '');
      final f = fail?.call();
      if (f != null) throw f;
      return StatsFake.handleCustomer(req);
    });
  }
}

class StatsTestApp {
  StatsTestApp._(this.server, this.container, this.router, this.prefs);

  final FakeServer server;
  final ProviderContainer container;
  final GoRouter router;
  final SharedPreferences prefs;

  FakeWorld get world => server.world;

  /// Ortamı kurar, personayla giriş yapar ve [location] rotasını açar. [probe] girişten sonra kurulur.
  static Future<StatsTestApp> start(
    WidgetTester tester, {
    required String persona,
    String location = hostPath,
    Brightness brightness = Brightness.light,
    double textScale = 1,
    bool reduceMotion = true,
    Size size = const Size(400, 1600),
    void Function(FakeServer server)? setup,
    StatsProbe? probe,
    Map<String, Object> prefs = statsTestPrefs,
    List<Override> overrides = const [],
    GlobalKey? boundaryKey,
    int settleRounds = 14,
  }) async {
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    late SharedPreferences sp;
    late FakeServer server;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(prefs);
      sp = await SharedPreferences.getInstance();
      server = FakeServer.forTests();
      registerCoreFakes(server);
      registerStatsFakes(server);
      await Future<void>.delayed(Duration.zero);
    });
    final c = ProviderContainer(
      overrides: [
        appEnvProvider.overrideWithValue(AppEnv.fakeForTests),
        appInfoProvider.overrideWithValue(AppInfo.test),
        prefsStoreProvider.overrideWithValue(PrefsStore(sp)),
        secureStoreProvider.overrideWithValue(MemorySecureStore()),
        fakeServerProvider.overrideWithValue(server),
        isOnlineProvider.overrideWith(
          (ref) => ref.watch(statsTestOnlineProvider),
        ),
        ...overrides,
      ],
    );
    await tester.runAsync(() => login(c, persona));
    // Giriş sonrası uç değişiklikleri (403, hata) girişi etkilemesin.
    probe?.install(server);
    setup?.call(server);
    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: location,
      routes: [
        GoRoute(
          path: hostPath,
          builder: (context, state) => Scaffold(
            body: ListView(
              key: const ValueKey('host-list'),
              children: const [ManagerStatsDeck(), SizedBox(height: 40)],
            ),
          ),
        ),
        ...statsRoutes(),
        for (final p in statsStubPaths)
          GoRoute(
            path: p,
            builder: (context, state) =>
                Scaffold(appBar: AppBar(), body: Text('stub:${state.uri}')),
          ),
      ],
    );
    AppToast.navigatorKey = rootNavigatorKey;
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(
            routerConfig: router,
            debugShowCheckedModeBanner: false,
            theme: AknTheme.light(),
            darkTheme: AknTheme.dark(),
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            locale: const Locale('tr', 'TR'),
            supportedLocales: const [Locale('tr', 'TR')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                disableAnimations: reduceMotion,
              ),
              child: child!,
            ),
          ),
        ),
      ),
    );
    await settle(tester, rounds: settleRounds);
    return StatsTestApp._(server, c, router, sp);
  }

  /// Personayla giriş (sahte şifre `demo`; merkezde SMS kodu `123456`).
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

  /// Rotaya gider (yığına ekler) ve yüklenmesini bekler.
  Future<void> push(WidgetTester tester, String location) async {
    unawaited(router.push(location));
    await settle(tester);
  }

  /// Bağlantıyı açar / kapatır.
  void setOnline(bool online) =>
      container.read(statsTestOnlineProvider.notifier).state = online;

  /// Ağ yanıtları ve animasyonlar için gerçek + sahte zamanı ilerletir.
  static Future<void> settle(WidgetTester tester, {int rounds = 14}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 4)),
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  /// Ağacı kaldırır ve kapsayıcıyı kapatır.
  Future<void> finish(WidgetTester tester) async {
    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }
}

/// Sayfanın ilk dikey kaydırıcısı.
final Finder verticalScrollable = find
    .byWidgetPredicate(
      (w) =>
          w is Scrollable &&
          axisDirectionToAxis(w.axisDirection) == Axis.vertical,
    )
    .first;

/// Öğe görünene kadar ana kaydırıcıyı kaydırır.
Future<void> revealIn(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      f,
      300,
      scrollable: verticalScrollable,
      maxScrolls: 40,
    );
  }
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 50));
}

/// Destenin en üstteki kartı (geçiş sürerken yeni kart).
DeckCardView topCard(WidgetTester tester) => tester
    .widgetList<DeckCardView>(find.byType(DeckCardView))
    .where((v) => v.raised)
    .last;

/// En üstteki kartın kimliği (`DeckCards`).
String topCardId(WidgetTester tester) => topCard(tester).card.id;

/// Destenin şeridi (v4 §4: şerit artık "1 / N" yazmaz; konum [LanePager.index] / [LanePager.count]
/// ve ekran okuyucu etiketinde). Tek kartlı destede şerit yoktur.
final Finder deckPositionText = find.byType(LanePager);

/// Şeritteki konum: (2, 6).
(int, int) deckPosition(WidgetTester tester) {
  final p = tester.widget<LanePager>(find.byType(LanePager));
  return (p.index + 1, p.count);
}

/// "Sonraki kart": destenin kendi ekran okuyucu eylemi (v4: şeritte gizli düğme yok).
Future<void> tapDeckNext(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  final node = tester.getSemantics(
    find.bySemanticsLabel(RegExp(r'karttan \d+\. kart: ')),
  );
  node.owner!.performAction(
    node.id,
    SemanticsAction.customAction,
    CustomSemanticsAction.getIdentifier(
      const CustomSemanticsAction(label: StatsCopy.deckNext),
    ),
  );
  handle.dispose();
  await tester.pump();
}

/// Şeritteki [lane]. çizgiye dokunur (0'dan; etkin çizgi 24, diğerleri 10 geniş, aralık 6).
Future<void> tapDeckLane(WidgetTester tester, int lane) async {
  final (pos, _) = deckPosition(tester);
  final active = pos - 1;
  var left = 0.0;
  for (var i = 0; i < lane; i++) {
    left += (i == active ? 20 : 6) + 10;
  }
  final w = lane == active ? 20.0 : 6.0;
  final origin = tester.getTopLeft(find.byType(LanePager));
  await tester.tapAt(origin + Offset(left + w / 2, 20));
}

/// Destedeki tüm kartların sırası: "Sonraki kart" ile baştan sona dolaşır (hareket azaltma açıkken).
Future<List<String>> deckOrder(WidgetTester tester) async {
  if (deckPositionText.evaluate().isEmpty || deckPosition(tester).$2 < 2) {
    return [topCardId(tester)];
  }
  final (_, n) = deckPosition(tester);
  final ids = <String>[];
  for (var i = 0; i < n; i++) {
    ids.add(topCardId(tester));
    await tapDeckNext(tester);
    await tester.pump(const Duration(milliseconds: 300));
  }
  return ids;
}
