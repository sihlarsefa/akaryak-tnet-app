import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/nav_keys.dart';
import 'presentation/finance_card_page.dart';
import 'presentation/finance_customers_page.dart';

/// Finans rotaları (sahibi A5). Yollar spec C.4 derin bağlantı sözleşmesidir:
/// `/finance` (cari finans kartları) ve `/finance/customers/:id` (StationCustomer kimliği).
List<RouteBase> financeRoutes() => [
  GoRoute(
    path: '/finance',
    builder: (context, state) => const FinanceCustomersPage(),
    routes: [
      GoRoute(
        path: 'customers/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return FinanceCardPage(
            key: ValueKey('finance-$id'),
            stationCustomerId: id,
          );
        },
      ),
    ],
  ),
];
