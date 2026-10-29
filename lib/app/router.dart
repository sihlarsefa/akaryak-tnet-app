import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/access_policy.dart';
import '../core/auth/session_controller.dart';
import '../core/auth/session_state.dart';
import '../core/env/app_config_controller.dart';
import '../core/env/app_env.dart';
import '../core/models/app_config.dart';
import '../core/push/local_read_marks.dart';
import '../core/routing/app_location.dart';
import '../core/routing/app_routes.dart';
import '../core/routing/nav_keys.dart';
import '../core/routing/route_access.dart';
import '../core/storage/prefs_store.dart';
import '../core/ui/gallery/gallery_route.dart';
import '../core/ui/ui.dart';
import '../features/approvals/api.dart';
import '../features/assistant/api.dart';
import '../features/auth/api.dart';
import '../features/bayi/api.dart';
import '../features/customer_home/api.dart';
import '../features/customer_more/api.dart';
import '../features/customer_orders/api.dart';
import '../features/driver/api.dart';
import '../features/field/api.dart';
import '../features/finance/api.dart';
import '../features/notifications/api.dart';
import '../features/onboarding/api.dart';
import '../features/payments/api.dart';
import '../features/profile/api.dart';
import '../features/stats/api.dart';
import '../features/weather/api.dart';
import 'destinations.dart';
import 'dev/dev_menu.dart';
import 'home_switch.dart';
import 'shell/app_shell.dart';
import 'splash/splash_screen.dart';

/// Açılış animasyonu bitti mi (yönlendirici en az bir tur açılış ekranını gösterir).
final splashDoneProvider = NotifierProvider<SplashDoneController, bool>(
  SplashDoneController.new,
);

class SplashDoneController extends Notifier<bool> {
  @override
  bool build() => false;

  void finish() => state = true;
}

/// Uygulama yönlendiricisi (spec C.4): açılış → güncelleme → tanıtım → giriş → kabuk.
/// Tek `GoRouter` örneği; yetki değişince rota tablosu (`RoutingConfig`) yeniden kurulur, konum korunur.
final appRouterProvider = Provider<AppRouter>((ref) {
  final r = AppRouter(ref);
  ref.onDispose(r.dispose);
  return r;
});

final routerProvider = Provider<GoRouter>(
  (ref) => ref.watch(appRouterProvider).router,
);

class AppRouter {
  AppRouter(this.ref) {
    final env = ref.read(appEnvProvider);
    _devRoutes = env.isFake || env.isDev;
    _layout = ref.read(navLayoutProvider);
    _config = ValueNotifier(_routingConfig(_layout));
    router = GoRouter.routingConfig(
      routingConfig: _config,
      navigatorKey: rootNavigatorKey,
      initialLocation: AppRoutes.splash,
      refreshListenable: _refresh,
      errorBuilder: (context, state) => const _NotFoundPage(),
    );
    router.routerDelegate.addListener(_onRouteChanged);
    // Rota tablosu yönlendirmeden önce güncellenir: giriş anında kabuk hazır olur.
    _subs.addAll([
      ref.listen(sessionControllerProvider, (prev, next) {
        // QA LF-3: çıkışta (ya da oturum kapanınca) bulunulan konum saklanmaz; sonra giren
        // kullanıcı (aynı telefonda başka biri olabilir) kendi ilk sekmesinde açılır.
        if (next is SessionUnauthenticated &&
            (prev is SessionAuthenticated || prev is SessionLocked)) {
          _deferred = null;
          _signedOut = true;
        } else if (next is SessionAuthenticated) {
          _signedOut = false;
        }
        _syncLayout();
        _refresh.ping();
      }),
      ref.listen(navLayoutProvider, (_, _) => _syncLayout()),
      ref.listen(updateStatusProvider, (_, _) => _refresh.ping()),
      ref.listen(serverAvailabilityProvider, (_, _) => _refresh.ping()),
      ref.listen(onboardingDoneProvider, (_, _) => _refresh.ping()),
      ref.listen(splashDoneProvider, (_, _) => _refresh.ping()),
      ref.listen<String?>(pendingDeepLinkProvider, (_, next) {
        if (next != null) _consumePendingLink();
      }),
    ]);
  }

  void _syncLayout() {
    final next = ref.read(navLayoutProvider);
    if (next == _layout) return;
    _layout = next;
    _config.value = _routingConfig(next);
  }

  final Ref ref;
  late final GoRouter router;
  late final ValueNotifier<RoutingConfig> _config;
  final _refresh = _RouterRefresh();
  final List<ProviderSubscription<Object?>> _subs = [];
  late final bool _devRoutes;
  late NavLayout _layout;

  /// Oturum açılmadan istenen konum (giriş sonrası açılır).
  String? _deferred;

  /// Oturum bu çalışmada kapandı (çıkış, iptal): bulunulan konum girişten sonra açılmaz (QA LF-3).
  bool _signedOut = false;

  RoutingConfig _routingConfig(NavLayout layout) => RoutingConfig(
    routes: buildAppRoutes(
      layout,
      devRoutes: _devRoutes,
      onSplashFinished: () => ref.read(splashDoneProvider.notifier).finish(),
    ),
    redirect: (context, state) => _redirect(state.uri),
    redirectLimit: 8,
  );

  String? _redirect(Uri uri) {
    final session = ref.read(sessionControllerProvider);
    final pending = ref.read(pendingDeepLinkProvider);
    final pushLink =
        _deferred == null &&
        pending != null &&
        ref.read(pendingDeepLinkProvider.notifier).fromPush;
    final result = computeRedirect(
      uri: uri,
      session: session,
      update: ref.read(updateStatusProvider),
      availability: ref.read(serverAvailabilityProvider),
      onboardingDone: ref.read(onboardingDoneProvider),
      splashDone: ref.read(splashDoneProvider),
      layout: ref.read(navLayoutProvider),
      // Oturumdan doğrudan: yönlendirme oturum dinleyicisinde çalışır ve Riverpod dinleyicileri
      // türetilmiş sağlayıcılar (accessPolicyProvider) tazelenmeden çağırır; girişten sonra saklanan
      // bağlantı eski (oturumsuz) yetkiyle reddedilirdi.
      policy: AccessPolicy(session.access),
      features: ref.read(appConfigProvider).features,
      devRoutesEnabled: _devRoutes,
      deferred: _deferred ?? pending,
      // Oturum açılmadan dokunulan push: izin yoksa gelen kutusu (spec C.4).
      deferredFallback: pushLink ? AppRoutes.notifications : null,
    );
    if (result.defer != null &&
        !(_signedOut && session is SessionUnauthenticated)) {
      _deferred = result.defer;
    }
    if (result.consumedDeferred) {
      _deferred = null;
      if (pending != null) {
        Future.microtask(
          () => ref.read(pendingDeepLinkProvider.notifier).set(null),
        );
      }
      // v4 §3.5 cold start: go to the first tab, then push the target, so
      // back always ends on Ana sayfa.
      final target = result.location;
      final layout = ref.read(navLayoutProvider);
      if (target != null &&
          target != layout.initialLocation &&
          !isShellLocation(router, target)) {
        _pushAfterFrame(target);
        return layout.initialLocation;
      }
    }
    if (result.denied) _toastAfterFrame('Bu sayfayı açma yetkiniz yok.');
    return result.location;
  }

  /// The cold-start target waiting for the first tab (pushed once the
  /// router has landed there).
  String? _pendingPush;

  void _pushAfterFrame(String target) {
    _pendingPush = target;
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _flushPendingPush() {
    final target = _pendingPush;
    if (target == null) return;
    if (ref.read(sessionControllerProvider) is! SessionAuthenticated) return;
    final here = router.routerDelegate.currentConfiguration.uri.path;
    if (here != ref.read(navLayoutProvider).initialLocation) return;
    _pendingPush = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(sessionControllerProvider) is! SessionAuthenticated) return;
      unawaited(router.push<Object?>(target));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _toastAfterFrame(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = rootNavigatorKey.currentContext;
      AppToast.info(message, context: context);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// v4 §3.5: opening an entity marks its notifications as read locally.
  void _onRouteChanged() {
    final uri = router.routerDelegate.currentConfiguration.uri;
    final location = uri.toString();
    _flushPendingPush();
    Future.microtask(() {
      try {
        ref.read(localReadMarksProvider.notifier).mark(location);
      } on Object {
        // Disposed with the router: nothing to mark.
      }
    });
  }

  /// Kabuk açıkken gelen push dokunuşu: hemen git.
  void _consumePendingLink() {
    if (ref.read(sessionControllerProvider) is! SessionAuthenticated) return;
    final link = ref.read(pendingDeepLinkProvider.notifier).take();
    // Sekme rotaları `go` ile açılır (QA SC-01: `push` kabuğu ikinci kez kurardı).
    if (link != null) openAppLocation(router, link);
  }

  void dispose() {
    for (final s in _subs) {
      s.close();
    }
    router.routerDelegate.removeListener(_onRouteChanged);
    router.dispose();
    _refresh.dispose();
    _config.dispose();
  }
}

/// Yönlendirme kararı.
@immutable
class RedirectResult {
  const RedirectResult(
    this.location, {
    this.defer,
    this.consumedDeferred = false,
    this.denied = false,
  });

  /// v4 §3.5: the asked page is not allowed; [location] is its nearest
  /// allowed parent (a toast says why).
  final bool denied;

  /// Gidilecek konum (null = olduğu yerde kal).
  final String? location;

  /// Girişten sonra açılmak üzere saklanacak konum.
  final String? defer;

  /// Saklanan konum kullanıldı.
  final bool consumedDeferred;
}

/// Saf yönlendirme kuralı (spec C.4; testlerde doğrudan çağrılır).
RedirectResult computeRedirect({
  required Uri uri,
  required SessionState session,
  required UpdateStatus update,
  required bool onboardingDone,
  required bool splashDone,
  required NavLayout layout,
  required AccessPolicy policy,
  required AppFeatures features,
  ServerAvailability availability = ServerAvailability.unknown,
  bool devRoutesEnabled = false,
  String? deferred,
  String? deferredFallback,
}) {
  final path = uri.path.isEmpty ? '/' : uri.path;
  final location = uri.toString();
  final isAuthPage =
      path == AppRoutes.login || path.startsWith('${AppRoutes.login}/');
  final isEntry =
      path == '/' ||
      path == AppRoutes.splash ||
      path == AppRoutes.onboarding ||
      path == AppRoutes.update ||
      path == AppRoutes.locked ||
      isAuthPage;
  // Uygulama içi bir hedef (giriş sonrası açılabilir).
  final isAppTarget = !isEntry && !path.startsWith(AppRoutes.dev);

  RedirectResult stay() => const RedirectResult(null);
  RedirectResult go(String to) => RedirectResult(to == location ? null : to);

  if (path.startsWith(AppRoutes.dev)) {
    return devRoutesEnabled
        ? stay()
        : go(
            session is SessionAuthenticated
                ? layout.initialLocation
                : AppRoutes.splash,
          );
  }

  // 1. Açılış: oturum bilinene ve animasyon bitene kadar.
  if (session is SessionUnknown || !splashDone) {
    if (path == AppRoutes.splash) return stay();
    return RedirectResult(
      AppRoutes.splash,
      defer: isAppTarget ? location : null,
    );
  }

  // 2. Zorunlu güncelleme.
  if (update == UpdateStatus.required) {
    return path == AppRoutes.update ? stay() : go(AppRoutes.update);
  }

  // 3. Oturum yok: ilk açılışta tanıtım, sonra giriş.
  if (session is SessionUnauthenticated) {
    if (!onboardingDone) {
      return path == AppRoutes.onboarding ? stay() : go(AppRoutes.onboarding);
    }
    if (isAuthPage) return stay();
    return RedirectResult(
      AppRoutes.login,
      defer: isAppTarget ? location : null,
    );
  }

  // 3b. Sunucu bakımda ya da bu sürümün sözleşmesini konuşmuyor (oturum açıkken; giriş ekranı bu
  // durumu kendi içinde gösterir). Durum düzelince ilk sekmeye dönülür.
  final gateReason = switch (availability) {
    ServerAvailability.maintenance => 'maintenance',
    ServerAvailability.outdated => 'server',
    _ => null,
  };
  final onGatePage =
      path == AppRoutes.update &&
      const {'maintenance', 'server'}.contains(uri.queryParameters['reason']);
  if (gateReason != null) {
    final target = '${AppRoutes.update}?reason=$gateReason';
    return location == target
        ? stay()
        : RedirectResult(target, defer: isAppTarget ? location : null);
  }
  // Saklanan konum: izin varsa o, yoksa [deferredFallback] (push: gelen kutusu), o da yoksa null.
  String? deferredTarget() {
    final target = deferred;
    if (target == null) return null;
    if (RouteAccess.isAllowed(target, policy, features)) return target;
    final fallback = deferredFallback;
    if (fallback != null && RouteAccess.isAllowed(fallback, policy, features)) {
      return fallback;
    }
    return null;
  }

  if (onGatePage) {
    final target = deferredTarget();
    if (target != null) return RedirectResult(target, consumedDeferred: true);
    return go(layout.initialLocation);
  }

  // 4. Kilitli.
  if (session is SessionLocked) {
    return path == AppRoutes.locked
        ? stay()
        : RedirectResult(
            AppRoutes.locked,
            defer: isAppTarget ? location : null,
          );
  }

  // 5. Oturum açık.
  if (isEntry) {
    final target = deferredTarget();
    if (target != null) return RedirectResult(target, consumedDeferred: true);
    return RedirectResult(
      layout.initialLocation,
      consumedDeferred: deferred != null,
    );
  }
  if (path == AppRoutes.home && !layout.inBar(DestinationId.home)) {
    return go(layout.initialLocation);
  }
  if (!RouteAccess.isAllowed(location, policy, features)) {
    // v4 §3.5: the nearest allowed parent (a tab or list page), else the
    // first tab — with a toast there.
    final parent = allowedParentOf(path, layout, policy, features);
    return RedirectResult(parent ?? layout.initialLocation, denied: true);
  }
  return stay();
}

/// The nearest allowed parent page of [path] (v4 §3.5): `/orders/12/x` →
/// `/orders` when allowed. Only real list / tab pages qualify (the
/// destinations' roots and the bar); null when none is allowed.
String? allowedParentOf(
  String path,
  NavLayout layout,
  AccessPolicy policy,
  AppFeatures features,
) {
  final roots = {for (final d in appDestinations) d.path};
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  for (var n = parts.length - 1; n >= 1; n--) {
    final candidate = '/${parts.sublist(0, n).join('/')}';
    if (!roots.contains(candidate)) continue;
    if (candidate == AppRoutes.home && !layout.inBar(DestinationId.home)) {
      continue;
    }
    if (RouteAccess.isAllowed(candidate, policy, features)) return candidate;
  }
  return null;
}

/// Özelliklerin rotaları (her özellik kendi `<f>_routes.dart` dosyasında tanımlar; spec C.3).
List<RouteBase> featureRouteTable() => [
  ...authRoutes(),
  ...onboardingRoutes(),
  ...customerHomeRoutes(),
  ...customerOrdersRoutes(),
  ...customerMoreRoutes(),
  ...bayiRoutes(),
  ...approvalsRoutes(),
  ...financeRoutes(),
  ...paymentsRoutes(),
  ...fieldRoutes(),
  ...driverRoutes(),
  ...notificationsRoutes(),
  ...assistantRoutes(),
  ...weatherRoutes(),
  ...profileRoutes(),
  ...statsRoutes(),
];

/// Rota tablosu: alt menüdeki hedefler kabuğun sekmeleri olur; diğer özellik rotaları tam ekran açılır.
List<RouteBase> buildAppRoutes(
  NavLayout layout, {
  bool devRoutes = false,
  VoidCallback? onSplashFinished,
}) {
  final byPath = <String, GoRoute>{};
  final other = <RouteBase>[];
  for (final r in featureRouteTable()) {
    if (r is GoRoute && !byPath.containsKey(r.path)) {
      byPath[r.path] = r;
    } else {
      other.add(r);
    }
  }

  final home = GoRoute(
    path: AppRoutes.home,
    builder: (context, state) => const HomeSwitch(),
  );
  final branches = <StatefulShellBranch>[];
  for (final d in layout.bar) {
    final route = d.id == DestinationId.home
        ? home
        : (byPath.remove(d.path) ?? _comingSoonRoute(d));
    branches.add(StatefulShellBranch(routes: [route]));
  }

  return [
    GoRoute(
      path: AppRoutes.splash,
      pageBuilder: (context, state) =>
          NoTransitionPage(child: SplashScreen(onFinished: onSplashFinished)),
    ),
    if (branches.isNotEmpty)
      StatefulShellRoute(
        builder: (context, state, shell) =>
            AppShell(navigationShell: shell, layout: layout),
        navigatorContainerBuilder: (context, shell, children) =>
            FadeThroughIndexedStack(
              index: shell.currentIndex,
              children: children,
            ),
        branches: branches,
      ),
    if (!layout.inBar(DestinationId.home)) home,
    ...byPath.values,
    ...other,
    if (devRoutes) ...[
      GoRoute(
        path: AppRoutes.dev,
        builder: (context, state) => const DevMenuPage(),
      ),
      designGalleryRoute(),
    ],
  ];
}

GoRoute _comingSoonRoute(AppDestination d) => GoRoute(
  path: d.path,
  builder: (context, state) => AppScaffold(
    title: d.label,
    body: EmptyState(
      title: 'Yakında',
      message: '${d.label} ekranı hazırlanıyor.',
    ),
  ),
);

/// Oturum, güncelleme, tanıtım ve açılış değişince yönlendirmeyi yeniden değerlendirir.
class _RouterRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage();

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Sayfa bulunamadı',
    body: EmptyState(
      title: 'Bu sayfa bulunamadı',
      message: 'Bağlantı eski olabilir ya da sayfa kaldırılmış olabilir.',
      illustration: AknIllustration.search,
      actionLabel: 'Ana sayfaya dön',
      onAction: () => GoRouter.of(context).go(AppRoutes.home),
    ),
  );
}
