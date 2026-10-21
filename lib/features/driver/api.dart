/// Şoför özelliği (sahibi A7). Diğer özellikler yalnızca bu dosyayı içe aktarır.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/offline/outbox_runner.dart';
import 'application/driver_ops.dart';

export 'driver_paths.dart' show DriverPaths;
export 'driver_routes.dart' show driverRoutes;
export 'presentation/assigned_deliveries_card.dart' show AssignedDeliveriesCard;
export 'presentation/driver_home.dart' show DriverHome;

/// Şoför bekleyen işlem işleyicileri: `driver.start`, `driver.deliver` (spec C.4).
/// Uygulama katmanı bunları `outboxHandlersProvider` içine ekler.
Map<String, OutboxHandler> driverOutboxHandlers(Ref ref) =>
    buildDriverOutboxHandlers(ref);
