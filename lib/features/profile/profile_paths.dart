import '../../core/routing/app_routes.dart';

/// Profil özelliğinin yolları (çekirdek [AppRoutes]'ta olmayanlar).
abstract final class ProfilePaths {
  static const edit = '${AppRoutes.profile}/edit';
  static const password = '${AppRoutes.profile}/password';
  static const sessions = '${AppRoutes.profile}/sessions';
  static const deleteAccount = '${AppRoutes.profile}/delete-account';
}
