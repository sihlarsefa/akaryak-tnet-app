import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/nav_keys.dart';
import '../../core/ui/ui.dart';
import 'copy.dart';
import 'presentation/company_users/company_users_page.dart';
import 'presentation/delivery_points/delivery_point_edit_page.dart';
import 'presentation/delivery_points/delivery_points_page.dart';
import 'presentation/documents/documents_page.dart';
import 'presentation/finance_info/finance_info_page.dart';
import 'presentation/requests/request_detail_page.dart';
import 'presentation/requests/requests_page.dart';
import 'presentation/shipments/shipment_detail_page.dart';
import 'presentation/shipments/shipments_page.dart';
import 'presentation/spending/spending_page.dart';

/// CustomerMore rotaları (sahibi A3). Yollar spec C.4 derin bağlantı sözleşmesidir. Ayrıntı ve form
/// sayfaları `parentNavigatorKey: rootNavigatorKey` ile alt menünün üstünde tam ekran açılır; kök rota
/// alt menüdeyse kabuk onu sekmeye yerleştirir.
///
/// - `/shipments`, `/shipments/:id`
/// - `/documents` (`?orderId=` o siparişin belgelerini açar)
/// - `/spending`
/// - `/company/requests`, `/company/requests/:id`
/// - `/company/users`
/// - `/delivery-points`, `/delivery-points/new`, `/delivery-points/:id`
/// - `/finance-info`
List<RouteBase> customerMoreRoutes() => [
  GoRoute(
    path: '/shipments',
    builder: (context, state) => const ShipmentsPage(),
    routes: [
      GoRoute(
        path: ':id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          return id == null
              ? const _InvalidLink(title: 'Teslimat')
              : ShipmentDetailPage(shipmentId: id);
        },
      ),
    ],
  ),
  GoRoute(
    path: '/documents',
    builder: (context, state) => DocumentsPage(
      orderId: int.tryParse(state.uri.queryParameters['orderId'] ?? ''),
    ),
  ),
  GoRoute(path: '/spending', builder: (context, state) => const SpendingPage()),
  GoRoute(
    path: '/company/requests',
    builder: (context, state) => const RequestsPage(),
    routes: [
      GoRoute(
        path: ':id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          return id == null
              ? const _InvalidLink(title: 'Talep')
              : RequestDetailPage(requestId: id);
        },
      ),
    ],
  ),
  GoRoute(
    path: '/company/users',
    builder: (context, state) => const CompanyUsersPage(),
  ),
  GoRoute(
    path: '/delivery-points',
    builder: (context, state) => const DeliveryPointsPage(),
    routes: [
      GoRoute(
        path: 'new',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage<bool>(
          fullscreenDialog: true,
          child: DeliveryPointEditPage(),
        ),
      ),
      GoRoute(
        path: ':id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          return MaterialPage<bool>(
            fullscreenDialog: true,
            child: id == null
                ? const _InvalidLink(title: CmCopy.pointsTitle)
                : DeliveryPointEditPage(pointId: id),
          );
        },
      ),
    ],
  ),
  GoRoute(
    path: '/finance-info',
    builder: (context, state) => const FinanceInfoPage(),
  ),
];

class _InvalidLink extends StatelessWidget {
  const _InvalidLink({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: title,
    body: const EmptyState(
      title: CmCopy.notFound,
      message: 'Bağlantı eksik ya da hatalı.',
      illustration: AknIllustration.search,
    ),
  );
}
