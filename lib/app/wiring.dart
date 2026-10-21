import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/session_cleanup.dart';
import '../core/env/app_env.dart';
import '../core/network/fake/fake_server.dart';
import '../core/network/network_providers.dart';
import '../core/offline/outbox_providers.dart';
import '../features/customer_more/api.dart';
import '../features/driver/api.dart';
import '../features/field/api.dart';
import 'fakes.dart';

/// Uygulama katmanının sağlayıcı bağlantıları: sahte sunucu (tüm özellik sahteleriyle) ve özelliklerin
/// bekleyen işlem işleyicileri. `bootstrap` ve uygulama testleri kullanır.
List<Override> appWiringOverrides({FakeServer? fakeServer}) => [
  // Canlı derlemede (API_MODE=live / AKN_ENV=prod) özellik sahteleri derlemeye girmez.
  if (kFakeApiCompiled)
    fakeServerProvider.overrideWith((ref) => fakeServer ?? buildFakeServer()),
  outboxHandlersProvider.overrideWith(
    (ref) => {...driverOutboxHandlers(ref), ...fieldOutboxHandlers(ref)},
  ),
  // Çıkışta / kullanıcı değişince özelliklerin cihazda bıraktığı kullanıcı verisi (spec D.7).
  sessionCleanupHooksProvider.overrideWith(
    (ref) => [customerMoreSessionCleanup(ref)],
  ),
];
