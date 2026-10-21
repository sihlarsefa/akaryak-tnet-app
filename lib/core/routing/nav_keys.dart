import 'package:flutter/widgets.dart';

/// Kök gezgin anahtarı. Ayrıntı ve sihirbaz sayfaları alt menünün üstünde tam ekran açılsın diye
/// rotalarda `parentNavigatorKey: rootNavigatorKey` kullanılır:
///
/// ```dart
/// GoRoute(path: '/orders', builder: …, routes: [
///   GoRoute(path: ':id', parentNavigatorKey: rootNavigatorKey, builder: …),
/// ])
/// ```
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);
