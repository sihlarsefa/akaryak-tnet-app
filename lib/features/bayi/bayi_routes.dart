import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/nav_keys.dart';
import '../../core/ui/ui.dart';
import 'copy.dart';
import 'presentation/customers/customer_page.dart';
import 'presentation/customers/customers_page.dart';
import 'presentation/desk/quote_desk_page.dart';
import 'presentation/dispatch/dispatch_page.dart';
import 'presentation/home/home_tasks.dart' show bayiTasksPath;
import 'presentation/home/tasks_page.dart';
import 'presentation/orders/order_detail_page.dart';
import 'presentation/orders/orders_page.dart';
import 'presentation/staff/staff_page.dart';

/// Bayi rotaları (sahibi A4). Yollar spec C.4 derin bağlantı sözleşmesidir: değiştirmeyin.
/// Ayrıntı sayfaları `parentNavigatorKey: rootNavigatorKey` ile alt menünün üstünde tam ekran açılır;
/// kök rota alt menüdeyse kabuk onu sekmeye yerleştirir.
///
/// - `/quote-desk` (`?customerId=` ile cari süzgeci), `/bayi/orders`, `/bayi/orders/:id`,
///   `/customers`, `/customers/:id`, `/dispatch`, `/bayi/staff` (Ekip; StationStaff:Görür),
///   `/bayi/tasks` (Tüm işler; ana sayfa kartının alt satırı itilir, hiçbir zaman sekme değil).
List<RouteBase> bayiRoutes() => [
  GoRoute(path: '/quote-desk', builder: buildQuoteDeskPage),
  GoRoute(
    path: '/bayi/orders',
    builder: (context, state) => const BayiOrdersPage(),
    routes: [
      GoRoute(
        path: ':id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          return id == null
              ? const _Missing()
              : BayiOrderDetailPage(orderId: id);
        },
      ),
    ],
  ),
  GoRoute(
    path: '/customers',
    builder: (context, state) => const BayiCustomersPage(),
    routes: [
      GoRoute(
        path: ':id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          return id == null
              ? const _Missing()
              : BayiCustomerPage(customerId: id);
        },
      ),
    ],
  ),
  GoRoute(path: '/dispatch', builder: (context, state) => const DispatchPage()),
  GoRoute(path: '/bayi/staff', builder: (context, state) => const StaffPage()),
  GoRoute(
    path: bayiTasksPath,
    builder: (context, state) => const BayiTasksPage(),
  ),
];

class _Missing extends StatelessWidget {
  const _Missing();

  @override
  Widget build(BuildContext context) => const AppScaffold(
    title: 'Kayıt',
    body: EmptyState(
      title: BayiCopy.notFoundTitle,
      message: BayiCopy.notFoundMessage,
      illustration: AknIllustration.search,
    ),
  );
}
