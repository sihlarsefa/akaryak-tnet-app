import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/models/json.dart';
import '../../../core/offline/cache_store.dart';
import '../../../core/utils/tr_time.dart';
import '../data/field_models.dart';
import '../data/field_repository.dart';
import 'field_access.dart';

/// Bir ürünün Tüpraş referans fiyatı, ₺/L (sunucu ₺/m³ verir; ÷ 1000).
@immutable
class TuprasPrice {
  const TuprasPrice({
    required this.productId,
    required this.name,
    required this.perLiter,
    this.previousPerLiter,
  });

  final int productId;
  final String name;
  final double perLiter;

  /// Bu cihazın gördüğü bir önceki günün fiyatı; bilinmiyorsa null (değişim gösterilmez).
  final double? previousPerLiter;

  /// Önceki güne göre değişim (₺/L); önceki fiyat bilinmiyorsa null.
  double? get change =>
      previousPerLiter == null ? null : perLiter - previousPerLiter!;
}

/// Ana sayfadaki "Tüpraş fiyatları" şeridinin verisi (tasarım v2 §6.18): saha fiyat bağlamındaki
/// `tuprasPricesM3` / `tuprasPriceDates`, bayinin varsayılan rafineri lokasyonu için.
@immutable
class TuprasSnapshot {
  const TuprasSnapshot({
    required this.location,
    required this.prices,
    this.locationLabel,
    this.day,
    this.fromCache = false,
  });

  /// Lokasyon kodu ("İZMİT").
  final String location;
  final String? locationLabel;

  /// Fiyatın günü (Türkiye gece yarısı).
  final DateTime? day;
  final List<TuprasPrice> prices;

  /// Bağlantı yokken son kayıttan gösteriliyor.
  final bool fromCache;

  /// Fiyat bugünün mü.
  bool isToday({DateTime? now}) =>
      day != null && TrTime.dayDiff(day!, now ?? TrTime.now()) == 0;

  JsonMap toJson() => {
    'location': location,
    'locationLabel': locationLabel,
    'day': day == null ? null : TrTime.isoDate(day!),
    'prices': [
      for (final p in prices)
        {
          'productId': p.productId,
          'name': p.name,
          'perLiter': p.perLiter,
          'previousPerLiter': p.previousPerLiter,
        },
    ],
  };

  factory TuprasSnapshot.fromJson(Object? json, {bool fromCache = false}) {
    final r = JsonReader.of(json);
    return TuprasSnapshot(
      location: r.str('location'),
      locationLabel: r.nonEmpty('locationLabel'),
      day: TrTime.parseDate(r.nonEmpty('day')),
      fromCache: fromCache,
      prices: List.unmodifiable(
        r.list(
          'prices',
          (p) => TuprasPrice(
            productId: p.integer('productId'),
            name: p.str('name'),
            perLiter: p.dec('perLiter'),
            previousPerLiter: p.decOrNull('previousPerLiter'),
          ),
        ),
      ),
    );
  }
}

/// Tüpraş referans fiyatları. Kaynak `field-orders/options-v2` (saha formları görme yetkisi gerekir;
/// yoksa null ve şerit gizlenir). Uç bir cari ister: [customerHint] (ana sayfa yükündeki bir cari) ya
/// da temsilcinin portföyündeki ilk cari. Önceki günün fiyatı cihazda saklanır; değişim yalnızca o
/// biliniyorsa gösterilir. Bağlantı yokken son kayıt döner.
final tuprasPricesProvider = FutureProvider.autoDispose
    .family<TuprasSnapshot?, int?>((ref, customerHint) async {
      final access = ref.watch(fieldAccessProvider);
      final uid = ref.watch(currentUserIdProvider);
      if (uid == null || !access.canSeeForms) return null;
      final repo = ref.read(fieldRepositoryProvider);
      final cache = ref.read(cacheStoreProvider);
      final lastKey = CacheKeys.user(uid, 'tupras.last');
      Future<TuprasSnapshot?> cached() async {
        final e = await cache.read(lastKey);
        if (e == null) return null;
        try {
          return TuprasSnapshot.fromJson(e.value, fromCache: true);
        } catch (_) {
          return null;
        }
      }

      try {
        var customerId = customerHint;
        if (customerId == null && access.isRep) {
          final page = await repo.portfolio(take: 1);
          customerId = page.items.isEmpty ? null : page.items.first.customerId;
        }
        if (customerId == null) return cached();
        final options = await repo.options(customerId);
        final snapshot = await _snapshot(cache, uid, options);
        if (snapshot != null) {
          await cache.write(
            lastKey,
            snapshot.toJson(),
            userId: uid,
            ttl: const Duration(days: 7),
          );
        }
        return snapshot;
      } catch (_) {
        return cached();
      }
    });

/// Seçeneklerden lokasyonun fiyatları; önceki günün fiyatı cihazdaki geçmişten.
Future<TuprasSnapshot?> _snapshot(
  CacheStore cache,
  String uid,
  FieldOptions o,
) async {
  final location =
      o.location ?? (o.locations.isEmpty ? null : o.locations.first.code);
  if (location == null) return null;
  final products = [
    for (final p in o.products)
      if (p.tuprasPricesM3[location] != null) p,
  ].take(3).toList();
  if (products.isEmpty) return null;
  DateTime? day;
  for (final p in products) {
    final d = p.tuprasPriceDates[location];
    if (d != null && (day == null || d.isAfter(day))) day = d;
  }
  final label = [
    for (final l in o.locations)
      if (l.code == location) l.label,
  ].firstOrNull;

  // Geçmiş: lokasyon başına son gün ve ondan önceki gün (₺/L).
  final historyKey = CacheKeys.user(uid, 'tupras.history.$location');
  final now = {
    for (final p in products) '${p.id}': p.tuprasPricesM3[location]! / 1000,
  };
  final dayIso = day == null ? null : TrTime.isoDate(day);
  Map<String, double> prev = const {};
  String? prevDay;
  final stored = await cache.read(historyKey);
  if (stored != null) {
    final r = JsonReader.of(stored.value);
    Map<String, double> prices(String key) {
      final out = <String, double>{};
      r.map(key).forEach((k, v) {
        final d = JsonReader.toDouble(v);
        if (d != null) out[k] = d;
      });
      return out;
    }

    final storedDay = r.nonEmpty('day');
    if (storedDay != null && dayIso != null && storedDay == dayIso) {
      prev = prices('prev');
      prevDay = r.nonEmpty('prevDay');
    } else if (storedDay != null &&
        dayIso != null &&
        storedDay.compareTo(dayIso) < 0) {
      prev = prices('prices');
      prevDay = storedDay;
    }
  }
  if (dayIso != null) {
    await cache.write(historyKey, {
      'day': dayIso,
      'prices': now,
      'prevDay': prevDay,
      'prev': prev,
    }, userId: uid);
  }
  return TuprasSnapshot(
    location: location,
    locationLabel: label,
    day: day,
    prices: List.unmodifiable([
      for (final p in products)
        TuprasPrice(
          productId: p.id,
          name: p.name,
          perLiter: now['${p.id}']!,
          previousPerLiter: prev['${p.id}'],
        ),
    ]),
  );
}
