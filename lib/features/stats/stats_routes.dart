import 'package:go_router/go_router.dart';

import '../../core/routing/app_routes.dart';
import 'data/stats_models.dart';
import 'presentation/stats_page.dart';

/// İstatistik rotası (`/stats?period=month|lastMonth|quarter|year`). Erişim `RouteAccess`'tedir
/// (yönetici destesi kitlesi).
List<RouteBase> statsRoutes() => [
  GoRoute(
    path: AppRoutes.stats,
    builder: (context, state) => StatsPage(
      initialPeriod: StatsPeriod.fromKey(state.uri.queryParameters['period']),
    ),
  ),
];
