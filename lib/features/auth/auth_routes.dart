import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_routes.dart';
import '../../core/ui/ui.dart';
import 'presentation/code_page.dart';
import 'presentation/locked_page.dart';
import 'presentation/login_page.dart';
import 'presentation/phone_verification_page.dart';
import 'presentation/update_page.dart';
import 'presentation/widgets/server_status.dart';

/// Kimlik özelliğinin yolları (çekirdek [AppRoutes]'ta olmayanlar).
abstract final class AuthRoutes {
  /// Telefon doğrulama (Profil > Güvenlik "Telefonla girişi etkinleştir"; spec C.4 derin bağlantı).
  static const phone = '/profile/phone';

  /// Güncelleme ekranı varyantı: `/update?reason=maintenance`.
  static String update(UpdateReason reason) =>
      '${AppRoutes.update}?reason=${reason.code}';
}

/// Kimlik rotaları (sahibi A1): giriş (+ kod), güncelleme, kilit, telefon doğrulama. Yönlendirme
/// kuralları `app/router.dart` içindedir (oturum yok → `/login`, kilitli → `/locked`, zorunlu güncelleme →
/// `/update`). Giriş, güncelleme ve kilit sakin bir solmayla açılır (yönlendirme ile değişen kök sayfalar).
List<RouteBase> authRoutes() => [
  GoRoute(
    path: AppRoutes.login,
    pageBuilder: (context, state) => _fade(state, const LoginPage()),
    routes: [
      GoRoute(
        path: 'code',
        builder: (context, state) =>
            CodePage(args: CodePage.argsFrom(state.extra)),
      ),
    ],
  ),
  GoRoute(
    path: AppRoutes.update,
    pageBuilder: (context, state) => _fade(
      state,
      UpdatePage(
        reason: UpdateReason.parse(state.uri.queryParameters['reason']),
      ),
    ),
  ),
  GoRoute(
    path: AppRoutes.locked,
    pageBuilder: (context, state) => _fade(state, const LockedPage()),
  ),
  GoRoute(
    path: AuthRoutes.phone,
    builder: (context, state) => const PhoneVerificationPage(),
  ),
];

Page<void> _fade(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: AknMotion.base,
      reverseTransitionDuration: AknMotion.fast,
      transitionsBuilder: (context, animation, secondary, child) {
        if (AknMotion.reduced(context)) return child;
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: AknMotion.standard,
          ),
          child: child,
        );
      },
    );
