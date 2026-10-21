import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env/app_config_controller.dart';
import '../../../core/models/models.dart';
import '../../../core/offline/cache_store.dart';

/// Sipariş ekranlarının sunucu ayarları: süre dolumu açık mı (`features.orderExpiry`) ve sunucu
/// saatiyle cihaz saati arasındaki fark (geri sayım sunucu saatine göre).
@immutable
class OrderingConfig {
  const OrderingConfig({this.orderExpiry, this.serverSkew = Duration.zero});

  /// `AppConfigDto.features.orderExpiry`; eski sunucuda yok (null) → ekranın kendi alanı kullanılır.
  final bool? orderExpiry;

  /// sunucu saati − cihaz saati.
  final Duration serverSkew;

  /// Cihaz saatine göre geri sayım hedefi: sunucudaki an − fark.
  DateTime deviceDeadline(DateTime serverInstant) =>
      serverInstant.subtract(serverSkew);

  /// Süre dolumu açık mı: önce uygulama ayarı, yoksa [fallback] (takip / panel alanı).
  bool expiryEnabled(bool fallback) => orderExpiry ?? fallback;
}

/// `app/config` önbelleğinden okunur (çekirdek her açılışta yazar): ek istek yok. Fark, yanıtın
/// `serverTimeUtc` değeri ile önbelleğe yazıldığı an arasından hesaplanır.
final orderingConfigProvider = FutureProvider<OrderingConfig>((ref) async {
  ref.watch(appConfigProvider);
  final entry = await ref.read(cacheStoreProvider).read(CacheKeys.appConfig);
  if (entry == null) return const OrderingConfig();
  final r = JsonReader.of(entry.value);
  final features = r.obj('features');
  final expiry = features.boolOrNull('orderExpiry');
  final server = r.dateUtc('serverTimeUtc');
  var skew = Duration.zero;
  if (server != null) {
    skew = server.difference(entry.storedAt);
    // Önemsiz farkları ve bozuk değerleri yok say.
    if (skew.abs() < const Duration(seconds: 5) ||
        skew.abs() > const Duration(days: 2)) {
      skew = Duration.zero;
    }
  }
  return OrderingConfig(orderExpiry: expiry, serverSkew: skew);
});

/// Senkron okuma (yüklenmediyse varsayılan).
final orderingConfigValueProvider = Provider<OrderingConfig>(
  (ref) =>
      ref.watch(orderingConfigProvider).valueOrNull ?? const OrderingConfig(),
);
