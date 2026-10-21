import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/nav_keys.dart';
import 'application/wizard_controller.dart';
import 'data/order_models.dart';
import 'presentation/order_detail_page.dart';
import 'presentation/orders_page.dart';
import 'presentation/templates_page.dart';
import 'presentation/wizard/order_wizard_page.dart';

/// CustomerOrders rotaları (sahibi A2). Yollar spec C.4 derin bağlantı sözleşmesidir:
/// `/orders` (`?segment=decision|active|history`), `/orders/new` (`?fromTemplate=`, `?fromRequest=`,
/// `?reorder=`), `/orders/:id`, `/templates`. Ayrıntı ve sihirbaz `rootNavigatorKey` ile alt menünün
/// üstünde tam ekran açılır; sihirbaz tam ekran iletişim kutusudur (açık kapatma düğmesi).
List<RouteBase> customerOrdersRoutes() => [
  GoRoute(
    path: '/orders',
    builder: (context, state) {
      final seg = state.uri.queryParameters['segment'];
      return OrdersPage(
        initialSegment: seg == null ? null : OrderSegment.parse(seg),
      );
    },
    routes: [
      GoRoute(
        path: 'new',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => MaterialPage<void>(
          key: state.pageKey,
          fullscreenDialog: true,
          child: OrderWizardPage(
            launch: WizardLaunch.fromQuery(state.uri.queryParameters),
          ),
        ),
      ),
      GoRoute(
        path: ':id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return OrderDetailPage(key: ValueKey('order-$id'), orderId: id);
        },
      ),
    ],
  ),
  GoRoute(
    path: templatesRoute,
    builder: (context, state) => const TemplatesPage(),
  ),
];
