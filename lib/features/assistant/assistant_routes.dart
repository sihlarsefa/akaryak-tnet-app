import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_routes.dart';
import 'presentation/assistant_page.dart';

/// Asistan rotası (sahibi A8; spec A.6, C.4 `/assistant`). Ana sayfa ikonu, ana sayfa kartı ve "Diğer"
/// sayfası buraya gider; sohbet tam ekran (alttan) açılır ve kapat düğmesi taşır. Yalnızca şoför
/// kullanıcılarda alt menü sekmesidir (kabuk yerleştirir). `features.assistant` kapalıyken yönlendirici
/// açmaz (RouteAccess).
List<RouteBase> assistantRoutes() => [
  GoRoute(
    path: AppRoutes.assistant,
    pageBuilder: (context, state) => MaterialPage<void>(
      key: state.pageKey,
      fullscreenDialog: true,
      child: const AssistantPage(),
    ),
  ),
];
