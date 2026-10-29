import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/cache_store.dart';
import '../data/bayi_repository.dart';
import '../data/home_models.dart';
import '../data/order_models.dart';
import 'bayi_grants.dart';
import 'bayi_runtime.dart';

/// Bayi ana sayfası (`GET home/bayi`). Önce önbellek (çevrimdışı açılış, "Son güncelleme"), sonra sunucu;
/// teklif, sipariş ve sevkiyat değişince sessizce tazelenir.
final bayiHomeProvider =
    NotifierProvider<BayiHomeController, Loadable<BayiHomeData>>(
      BayiHomeController.new,
    );

class BayiHomeController extends Notifier<Loadable<BayiHomeData>> {
  int _epoch = 0;
  String? _userId;

  @override
  Loadable<BayiHomeData> build() {
    _userId = ref.watch(currentUserIdProvider);
    final sub = ref.read(bayiChangesProvider).stream.listen((c) {
      if (c == BayiChange.quotes ||
          c == BayiChange.orders ||
          c == BayiChange.shipments) {
        unawaited(refresh());
      }
    });
    ref.onDispose(sub.cancel);
    if (_userId == null) return const Loadable();
    Future.microtask(() => load(useCache: true));
    return const Loadable.loading();
  }

  String? get _cacheKey =>
      _userId == null ? null : CacheKeys.user(_userId!, CacheKeys.homeBayi);

  /// İlk yükleme: önbellekte kayıt varsa hemen gösterilir, ardından sunucudan tazelenir.
  Future<void> load({bool useCache = false}) async {
    final key = _cacheKey;
    if (key == null) return;
    final epoch = ++_epoch;
    if (useCache && !state.hasData) {
      final cached = await ref.read(cacheStoreProvider).read(key);
      if (epoch != _epoch) return;
      if (cached != null) {
        state = Loadable(
          data: BayiHomeData.fromJson(cached.value),
          refreshing: true,
          updatedAt: cached.storedAt,
          fromCache: true,
        );
      }
    }
    await _fetch(epoch);
  }

  /// Arka planda tazeler (içerik kalır).
  Future<void> refresh() async {
    if (_cacheKey == null) return;
    final epoch = ++_epoch;
    state = state.hasData
        ? state.copyWith(refreshing: true, error: null)
        : const Loadable.loading();
    await _fetch(epoch);
  }

  Future<void> _fetch(int epoch) async {
    try {
      final r = await ref.read(bayiRepositoryProvider).home();
      if (epoch != _epoch) return;
      final now = DateTime.now().toUtc();
      state = Loadable(data: r.data, updatedAt: now);
      final key = _cacheKey;
      if (key != null) {
        await ref
            .read(cacheStoreProvider)
            .write(key, r.raw, userId: _userId, ttl: const Duration(days: 2));
      }
    } catch (e) {
      if (epoch != _epoch) return;
      final f = AppFailure.from(e);
      state = state.hasData
          ? state.copyWith(refreshing: false, loading: false, error: f)
          : Loadable(error: f);
    }
  }
}

/// Ana sayfa "Sipariş hattı"nın sayıları (v4 §5 03): Siparişler sayfasının segment sayıları (`GET
/// bayi/orders/counts`); her durak o segmentin listesini açar ve sayı listeyle aynıdır. Siparişleri
/// göremeyen ya da sayılar yüklenemezse null (hat ana sayfa yükünden çizilir). Ana sayfa her
/// tazelendiğinde yeniden okunur.
final bayiPipelineCountsProvider = FutureProvider.autoDispose<BayiOrderCounts?>(
  (ref) async {
    if (!ref.watch(bayiGrantsProvider.select((g) => g.viewOrders))) {
      return null;
    }
    ref.watch(bayiHomeProvider.select((s) => s.updatedAt));
    try {
      return await ref.read(bayiRepositoryProvider).orderCounts();
    } on Object {
      return null;
    }
  },
);
