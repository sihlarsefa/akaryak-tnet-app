import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_location.dart';
import '../../core/routing/app_routes.dart';

/// Şoför rotaları (derin bağlantı sözleşmesi `/driver`, `/driver/shipments/:id`; teslim sihirbazı
/// özelliğe özgüdür).
abstract final class DriverPaths {
  static const home = AppRoutes.driver;

  static String detail(int id) => AppRoutes.driverShipment(id);

  /// "Teslim et" / "Teslimatı düzelt" sihirbazı (tam ekran).
  static String deliver(int id) => '${AppRoutes.driverShipment(id)}/deliver';
}

/// "Listeye dön" (v4 tur 2): Teslimatlar şoförde alt menünün sekmesidir, oraya `go`. Diğer'den açan
/// sahipte ve depoda sekme değildir: kabuksuz köke `go` alt menüyü düşürür, geri tuşu da bir yere
/// gitmez. Bu yüzden yığında listeye kadar geri gelinir; liste yığında yoksa üste açılır.
void backToDriverList(BuildContext context) {
  final router = GoRouter.of(context);
  if (isShellLocation(router, DriverPaths.home)) {
    router.go(DriverPaths.home);
    return;
  }
  bool atList() => router.state.uri.path == DriverPaths.home;
  while (!atList() && router.canPop()) {
    router.pop();
  }
  if (!atList()) unawaited(router.push<Object?>(DriverPaths.home));
}
