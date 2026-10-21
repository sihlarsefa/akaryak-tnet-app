import '../../core/routing/app_routes.dart';

/// Şoför rotaları (derin bağlantı sözleşmesi `/driver`, `/driver/shipments/:id`; teslim sihirbazı
/// özelliğe özgüdür).
abstract final class DriverPaths {
  static const home = AppRoutes.driver;

  static String detail(int id) => AppRoutes.driverShipment(id);

  /// "Teslim et" / "Teslimatı düzelt" sihirbazı (tam ekran).
  static String deliver(int id) => '${AppRoutes.driverShipment(id)}/deliver';
}
