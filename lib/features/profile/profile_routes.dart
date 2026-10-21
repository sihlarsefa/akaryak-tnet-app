import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_routes.dart';
import '../../core/routing/nav_keys.dart';
import 'presentation/change_password_page.dart';
import 'presentation/delete_account_page.dart';
import 'presentation/edit_profile_page.dart';
import 'presentation/profile_page.dart';
import 'presentation/sessions_page.dart';

/// Profil rotaları (sahibi A8). `/profile` derin bağlantı sözleşmesidir (spec C.4); merkez ve
/// şoför kullanıcılarda alt menü sekmesidir. Alt sayfalar alt menünün üstünde tam ekran açılır.
/// Telefon doğrulama (`/profile/phone`) A1'in rotasıdır.
List<RouteBase> profileRoutes() => [
  GoRoute(
    path: AppRoutes.profile,
    builder: (context, state) => const ProfilePage(),
    routes: [
      GoRoute(
        path: 'edit',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const EditProfilePage(),
      ),
      GoRoute(
        path: 'password',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ChangePasswordPage(),
      ),
      GoRoute(
        path: 'sessions',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SessionsPage(),
      ),
      GoRoute(
        path: 'delete-account',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => MaterialPage<void>(
          key: state.pageKey,
          fullscreenDialog: true,
          child: const DeleteAccountPage(),
        ),
      ),
    ],
  ),
];
