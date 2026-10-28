// Bayi ekranlarının widget testi ortamı: yalnızca bayi rotaları + diğer hedefler için basit yer
// tutucular (başka özelliklerin kodu derlenmese de bu testler çalışır), gerçek yönlendirici.
import 'dart:async';

import 'package:akaryakitnet/core/offline/connectivity.dart';
import 'package:akaryakitnet/core/routing/nav_keys.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'bayi_harness.dart';

/// Çevrimiçi / çevrimdışı anahtarı.
final testOnlineProvider = StateProvider<bool>((ref) => true);

/// Bayi dışı hedefler (yalnızca yolu gösterir).
const stubPaths = [
  '/home',
  '/approvals',
  '/approvals/:id',
  '/payments',
  '/payments/:id',
  '/finance',
  '/finance/customers/:id',
  '/field',
  '/field/forms/new',
  '/field/forms/:id',
  '/assistant',
  '/notifications',
];

class BayiTestApp {
  BayiTestApp._(this.harness, this.container, this.router);

  final BayiHarness harness;
  final ProviderContainer container;
  final GoRouter router;

  /// Rotaya gider (yığına ekler) ve yüklenmesini bekler.
  Future<void> push(WidgetTester tester, String location) async {
    unawaited(router.push(location));
    await settle(tester);
  }

  /// Ortamı kurar, personayla giriş yapar ve [location] rotasını açar.
  static Future<BayiTestApp> start(
    WidgetTester tester, {
    required String persona,
    required String location,
    Brightness brightness = Brightness.light,
    double textScale = 1,
    bool reduceMotion = true,
    Size size = const Size(420, 2600),
    void Function(BayiHarness h)? setup,
    Map<String, Object> prefs = const {'akn.onboardingDone': true},
  }) async {
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    late BayiHarness h;
    await tester.runAsync(
      () async => h = await BayiHarness.create(prefs: prefs),
    );
    setup?.call(h);
    final c = h.container(
      extra: [
        isOnlineProvider.overrideWith((ref) => ref.watch(testOnlineProvider)),
      ],
    );
    await tester.runAsync(() => BayiHarness.login(c, persona));
    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/home-bayi',
          builder: (context, state) => const BayiHome(),
        ),
        ...bayiRoutes(),
        for (final p in stubPaths)
          GoRoute(
            path: p,
            builder: (context, state) =>
                Scaffold(appBar: AppBar(), body: Text('stub:${state.uri}')),
          ),
      ],
    );
    AppToast.navigatorKey = rootNavigatorKey;
    await tester.pumpWidget(
      UncontrolledProviderScope(
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
    );
    await settle(tester);
    return BayiTestApp._(h, c, router);
  }

  /// Ağ yanıtları ve animasyonlar için gerçek + sahte zamanı ilerletir.
  static Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 4)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// Ağacı kaldırır ve kapsayıcıyı kapatır.
  Future<void> finish(WidgetTester tester) async {
    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }
}

/// Erişilebilirlik kılavuzları (spec C.7).
Future<void> expectA11y(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// Sayfanın ilk dikey kaydırıcısı (yatay çip satırları atlanır).
final Finder _verticalScrollable = find
    .byWidgetPredicate(
      (w) =>
          w is Scrollable &&
          axisDirectionToAxis(w.axisDirection) == Axis.vertical,
    )
    .first;

/// Henüz kurulmamış ya da kaydırınca kaldırılmış (tembel liste) öğeyi ana kaydırıcıda önce yukarı,
/// sonra aşağı arayıp görünür yapar; kaydırma durulana kadar bekler ([_settleScroll]).
Future<void> reveal(WidgetTester tester, Finder f, {Finder? scrollable}) async {
  for (final delta in const [-300.0, 300.0]) {
    if (f.evaluate().isNotEmpty) break;
    try {
      await tester.scrollUntilVisible(
        f,
        delta,
        scrollable: scrollable ?? _verticalScrollable,
        maxScrolls: 30,
      );
    } on StateError {
      // Bu yönde yok; diğer yöne bak.
    }
  }
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 50));
  await _settleScroll(tester, f);
}

/// Hedefin listesi kayarken (fırlatma) dokunuş yutulur; sürükleme listenin ucunu aştıysa Android
/// kenar esnemesi içeriği ≈400 ms gerer (azaltılmış harekette de) ve hedefin merkezi ekran dışına
/// düşebilir. Liste durup hedef dokunulabilir olana kadar (en çok ≈600 ms) bekler.
Future<void> _settleScroll(WidgetTester tester, Finder f) async {
  bool busy() {
    final found = f.evaluate();
    if (found.isEmpty) return false;
    final scroll = found.first.findAncestorStateOfType<ScrollableState>();
    if (scroll?.position.isScrollingNotifier.value ?? false) return true;
    return f.hitTestable().evaluate().isEmpty;
  }

  for (var i = 0; i < 12 && busy(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Liste içinde görünür olana kadar kaydırır ve dokunur. Üstteki bildirim (toast) dokunuşu yutmasın
/// diye önce kapatılır.
Future<void> scrollTap(
  WidgetTester tester,
  Finder f, {
  Finder? scrollable,
}) async {
  AppToast.dismiss();
  await tester.pump(const Duration(milliseconds: 400));
  await reveal(tester, f, scrollable: scrollable);
  await tester.tap(f, warnIfMissed: false);
  await BayiTestApp.settle(tester);
}
