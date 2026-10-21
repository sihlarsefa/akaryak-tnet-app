import 'package:go_router/go_router.dart';

import 'presentation/limits_page.dart';

/// Müşteri ana sayfası rotaları (sahibi A2). Ana sayfa `/home` altında `HomeSwitch` ile açılır;
/// bu özellik ayrıca Limitlerim'i (`/limits`, spec C.4 derin bağlantı) tanımlar.
List<RouteBase> customerHomeRoutes() => [
  GoRoute(path: limitsRoute, builder: (context, state) => const LimitsPage()),
];
