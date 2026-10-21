import 'package:go_router/go_router.dart';

import '../../core/routing/app_routes.dart';
import '../../core/routing/nav_keys.dart';
import 'presentation/notification_settings_page.dart';
import 'presentation/notifications_page.dart';

/// Bildirimler rotaları (sahibi A8). `/notifications` derin bağlantı sözleşmesidir (spec C.4); push
/// rotası açılamazsa uygulama buraya düşer. Kök rota alt menüdeyse (merkez, şoför) kabuk onu sekmeye
/// yerleştirir; tercihler ekranı her durumda tam ekran açılır.
List<RouteBase> notificationsRoutes() => [
  GoRoute(
    path: AppRoutes.notifications,
    builder: (context, state) => const NotificationsPage(),
    routes: [
      GoRoute(
        path: 'settings',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const NotificationSettingsPage(),
      ),
    ],
  ),
];
