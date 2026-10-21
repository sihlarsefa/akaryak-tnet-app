import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_routes.dart';
import '../../core/ui/ui.dart';
import 'presentation/onboarding_page.dart';

/// Tanıtım rotası (sahibi A1). Yalnızca ilk açılışta; yönlendirici açılış ekranından buraya gönderir,
/// tamamlanınca girişe geçer. Açılış ekranının lacivertinden sakin bir solmayla gelir.
List<RouteBase> onboardingRoutes() => [
  GoRoute(
    path: AppRoutes.onboarding,
    pageBuilder: (context, state) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: const OnboardingPage(),
      transitionDuration: AknMotion.slow,
      reverseTransitionDuration: AknMotion.fast,
      transitionsBuilder: (context, animation, secondary, child) =>
          AknMotion.reduced(context)
          ? child
          : FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: AknMotion.standard,
              ),
              child: child,
            ),
    ),
  ),
];
