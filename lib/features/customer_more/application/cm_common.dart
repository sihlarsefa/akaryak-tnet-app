import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/idempotency.dart';
import '../../../core/offline/cache_store.dart';

/// A3 eylemlerinin Idempotency-Key defteri (spec C.4a: niyet başına bir anahtar; kullanıcı değişince sıfırlanır).
final cmLedgerProvider = Provider<IdempotencyLedger>((ref) {
  ref.watch(currentUserIdProvider);
  return IdempotencyLedger(lifetime: const Duration(hours: 24));
});

/// Önbellek anahtarları (kullanıcıya özel; çıkışta `CacheStore.clearUser` siler).
abstract final class CmCacheKeys {
  static const deliveryPoints = 'cm.deliveryPoints';
  static const documentsFirstPage = 'cm.documents.p1';
}

/// Sunucudan ya da (çevrimdışıyken) önbellekten gelen veri.
@immutable
class Loaded<T> {
  const Loaded(this.value, {this.fromCache = false, this.storedAt});

  final T value;

  /// Bağlantı yok; son kayıtlı veri gösteriliyor.
  final bool fromCache;

  /// Önbellek kaydının zamanı ("Son güncelleme hh:mm").
  final DateTime? storedAt;
}

/// Hata bağlantı kaynaklı mı (önbelleğe düşülür).
bool isConnectivityFailure(Object error) {
  final f = AppFailure.from(error);
  return f is OfflineFailure || f is TimeoutFailure;
}

/// Önce önbellek, sonra sunucu (2026-11-02; eskiden yalnızca çevrimdışıyken önbellek). [onCached]
/// verilirse son kayıt sunucu beklenmeden ona verilir (ekran içeriği hemen gösterir, üstte ince
/// "güncelleniyor" çubuğu); ardından sunucu yanıtı döner ve önbelleğe yazılır. Sunucuya ulaşılamazsa
/// ya da geçici bir hata varsa (çevrimdışı, zaman aşımı, 429, 5xx) önbellekteki kayıt döner; önbellekte
/// de yoksa özgün hata fırlar.
Future<Loaded<T>> loadWithCache<T>({
  required CacheStore cache,
  required String? userId,
  required String name,
  required Future<Object?> Function() fetch,
  required T Function(Object? json) parse,
  bool writeCache = true,
  void Function(Loaded<T> cached)? onCached,
}) async {
  final key = userId == null ? null : CacheKeys.user(userId, name);
  if (key != null && writeCache && onCached != null) {
    try {
      final entry = await cache.read(key);
      if (entry != null) {
        onCached(
          Loaded(parse(entry.value), fromCache: true, storedAt: entry.storedAt),
        );
      }
    } catch (_) {
      // Bozuk ya da eski biçimde kayıt: sunucudan yüklenir.
    }
  }
  try {
    final json = await fetch();
    if (key != null && writeCache) {
      await cache.write(key, json, userId: userId);
    }
    return Loaded(parse(json));
  } catch (e) {
    if (key == null || !isFallbackFailure(e)) rethrow;
    final entry = await cache.read(key);
    if (entry == null) rethrow;
    return Loaded(
      parse(entry.value),
      fromCache: true,
      storedAt: entry.storedAt,
    );
  }
}

/// Önbelleğe düşülen hata: bağlantı ve geçici sunucu hataları (çevrimdışı, zaman aşımı, 429, 5xx).
bool isFallbackFailure(Object error) {
  final f = AppFailure.from(error);
  return isConnectivityFailure(error) ||
      f is RateLimitedFailure ||
      f is ServerFailure;
}

/// Sonucu belirsiz durum geçişi (zaman aşımı, 400, 409; spec C.4a): varlığı yeniden okuyup hedef
/// duruma ulaşıldıysa başarı sayar.
bool shouldReconcile(Object error) {
  final f = AppFailure.from(error);
  return f.isUncertain ||
      f is ConflictFailure ||
      f is BusinessFailure ||
      f is ValidationFailure;
}
