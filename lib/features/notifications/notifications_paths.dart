import '../../core/routing/app_routes.dart';

/// Bildirimler özelliğinin yolları (çekirdek [AppRoutes]'ta olmayanlar). Profil > Bildirimler bu
/// yolla tercihler ekranını açar.
abstract final class NotificationsPaths {
  /// Bildirim tercihleri (`/notifications/settings`).
  static const settings = '${AppRoutes.notifications}/settings';
}
