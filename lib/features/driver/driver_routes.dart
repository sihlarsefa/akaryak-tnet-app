import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_routes.dart';
import '../../core/routing/nav_keys.dart';
import 'presentation/deliver_flow_page.dart';
import 'presentation/driver_home.dart';
import 'presentation/shipment_detail_page.dart';

/// Şoför rotaları (sahibi A7). `/driver` ve `/driver/shipments/:id` derin bağlantı sözleşmesidir
/// (spec C.4); teslim sihirbazı `/driver/shipments/:id/deliver` tam ekran açılır.
List<RouteBase> driverRoutes() => [
  GoRoute(
    path: AppRoutes.driver,
    builder: (context, state) => const DriverHome(),
    routes: [
      GoRoute(
        path: 'shipments/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            ShipmentDetailPage(id: _id(state.pathParameters['id'])),
        routes: [
          GoRoute(
            path: 'deliver',
            parentNavigatorKey: rootNavigatorKey,
            pageBuilder: (context, state) => MaterialPage<void>(
              key: state.pageKey,
              fullscreenDialog: true,
              child: DeliverFlowPage(id: _id(state.pathParameters['id'])),
            ),
          ),
        ],
      ),
    ],
  ),
];

int _id(String? raw) => int.tryParse(raw ?? '') ?? 0;
