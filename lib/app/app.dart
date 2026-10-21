import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/session_controller.dart';
import '../core/env/app_config_controller.dart';
import '../core/offline/connectivity.dart';
import '../core/offline/outbox_providers.dart';
import '../core/offline/pending_ops_chip.dart';
import '../core/push/app_badge.dart';
import '../core/push/push_providers.dart';
import '../core/push/unread_count_provider.dart';
import '../core/routing/app_location.dart';
import '../core/routing/app_routes.dart';
import '../core/routing/nav_keys.dart';
import '../core/storage/prefs_store.dart';
import '../core/ui/ui.dart';
import '../core/utils/app_messenger.dart';
import 'app_overlays.dart';
import 'router.dart';

/// Uygulama kökü: tema (açık/koyu), Türkçe yerelleştirme, yönlendirici, kabuk bilgisi
/// ([AppChrome]: zil rozeti, çevrimdışı bandı, bekleyen işlemler), uygulama içi bildirimler ve yaşam
/// döngüsü (oturum kilidi, yoklama, bekleyen işlemler).
///
/// Ayrıca (spec C.7, D.7): yazı ölçeği en fazla 2,0× ([MediaQuery.withClampedTextScaling]), kilit
/// açıkken gizlilik örtüsü ([PrivacyCover]), canlı olmayan derlemede "TEST"/"DEMO" şeridi
/// ([EnvRibbon]) ve okunmamış bildirim sayısıyla uygulama simgesi rozeti.
class AknApp extends ConsumerStatefulWidget {
  const AknApp({super.key});

  @override
  ConsumerState<AknApp> createState() => _AknAppState();
}

class _AknAppState extends ConsumerState<AknApp> with WidgetsBindingObserver {
  StreamSubscription<AppMessage>? _messages;
  DateTime? _lastConfigLoad;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppToast.navigatorKey = rootNavigatorKey;
    _messages = ref.read(appMessengerProvider).stream.listen(_showMessage);
    // Arka plan hizmetleri: push, bekleyen işlemler, rozetler.
    ref.read(pushCoordinatorProvider);
    ref.read(outboxRunnerProvider);
    ref.read(unreadCountProvider);
    // Uygulama simgesi rozeti = okunmamış bildirim (çıkışta oturum temizliği sıfırlar).
    ref.listenManual<int>(unreadCountProvider.select((u) => u.notifications), (
      _,
      count,
    ) {
      if (ref.read(currentUserIdProvider) != null) {
        unawaited(ref.read(appBadgeProvider).set(count));
      }
    });
    _lastConfigLoad = DateTime.now();
    unawaited(ref.read(appConfigProvider.notifier).load());
    unawaited(ref.read(sessionControllerProvider.notifier).restore());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messages?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(sessionControllerProvider.notifier).handleLifecycle(state);
    ref.read(unreadCountProvider.notifier).handleLifecycle(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(outboxRunnerProvider).runOnce());
      final last = _lastConfigLoad;
      if (last == null ||
          DateTime.now().difference(last) > const Duration(minutes: 30)) {
        _lastConfigLoad = DateTime.now();
        unawaited(ref.read(appConfigProvider.notifier).load());
      }
    }
  }

  void _showMessage(AppMessage m) {
    final type = switch (m.tone) {
      AppMessageTone.success => AppToastType.success,
      AppMessageTone.warning => AppToastType.warning,
      AppMessageTone.error => AppToastType.error,
      AppMessageTone.info => AppToastType.info,
    };
    final route = m.route;
    AppToast.show(
      m.text,
      title: m.title,
      type: type,
      actionLabel: route == null ? null : 'Aç',
      onAction: route == null
          ? null
          : () => openAppLocation(ref.read(routerProvider), route),
    );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'AkaryakıtNet',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AknTheme.light(),
      darkTheme: AknTheme.dark(),
      themeMode: themeMode,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        // Yazı %200'e kadar büyür (spec C.7); daha büyük sistem ayarı 2,0×'te kesilir.
        maxScaleFactor: 2.0,
        child: PrivacyCover(
          child: EnvRibbon(
            child: _ChromeHost(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
    );
  }
}

/// Çevrimdışı bandına dokununca bekleyen işlemler sayfası (kök gezgin bağlamıyla).
void _openPendingOps() {
  final context = rootNavigatorKey.currentContext;
  if (context != null) showPendingOpsSheet(context);
}

/// Kabuk düzeyi bilgiyi tasarım sistemine verir (zil, çevrimdışı bandı, bekleyen işlemler).
class _ChromeHost extends ConsumerWidget {
  const _ChromeHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(currentUserIdProvider) != null;
    return AppChrome(
      unreadCount: ref.watch(
        unreadCountProvider.select((u) => u.notifications),
      ),
      onOpenNotifications: signedIn
          ? () => openAppLocation(
              ref.read(routerProvider),
              AppRoutes.notifications,
            )
          : null,
      offline: !ref.watch(isOnlineProvider),
      pendingOps: ref.watch(pendingOpsCountProvider),
      onOpenPendingOps: signedIn ? _openPendingOps : null,
      child: child,
    );
  }
}
