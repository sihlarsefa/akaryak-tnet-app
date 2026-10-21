import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/cache_store.dart';
import '../../../core/offline/connectivity.dart';
import '../../../core/utils/log.dart';
import '../../customer_orders/api.dart' show Loadable;
import '../data/stats_models.dart';
import '../data/stats_repository.dart';
import 'stats_scope.dart';

/// Önbellek ve tercih anahtarları.
abstract final class StatsKeys {
  /// Son başarılı yanıt (kullanıcı + uç + kapsam + dönem başına; çıkışta silinir).
  static String cache(
    String uid,
    String endpoint,
    StatsScope scope,
    StatsPeriod period,
  ) => CacheKeys.user(uid, 'stats.$endpoint.${scope.name}.${period.key}');

  /// Destenin "kaydırılabilir" ipucu bu cihazda bir kez gösterildi.
  static const deckHint = 'akn.stats.deckHint';
}

/// Yanıt sunucuda yok sayılır: yetki yok (403) ya da uç henüz yayımlanmadı (404). Deste gizlenir.
bool statsDenied(AppFailure? error) =>
    error is ForbiddenFailure || error is NotFoundFailure;

/// Dönemlik istatistik denetleyicisi: önce önbellek (çevrimdışı açılış, "Son güncelleme"), sonra
/// sunucu. Tazeleme sırasında içerik kalır; hata içerik varken yalnızca not olarak gösterilir. Bağlantı
/// geri gelince önbellekten gösterilen veri kendiliğinden tazelenir.
abstract class StatsController<T>
    extends FamilyNotifier<Loadable<T>, StatsPeriod> {
  int _epoch = 0;
  bool _alive = true;
  Future<void>? _inFlight;
  int _inFlightEpoch = -1;
  String? _uid;
  StatsScope _scope = StatsScope.none;

  /// Önbellek anahtarındaki uç adı.
  String get endpoint;

  /// Bu uç bu kapsamda çağrılabilir mi.
  bool accepts(StatsScope scope);

  Future<({T data, Object? raw})> fetch(
    StatsRepository repo,
    StatsPeriod period,
  );

  T parse(Object? raw, StatsPeriod period);

  @override
  Loadable<T> build(StatsPeriod arg) {
    _alive = true;
    ref.onDispose(() => _alive = false);
    _uid = ref.watch(currentUserIdProvider);
    _scope = ref.watch(statsScopeProvider);
    final epoch = ++_epoch;
    ref.listen<bool>(isOnlineProvider, (previous, next) {
      if (previous == false && next && (state.fromCache || state.showError)) {
        unawaited(refresh());
      }
    });
    if (_uid == null) return const Loadable();
    if (!accepts(_scope)) return const Loadable(error: ForbiddenFailure());
    Future.microtask(() => _start(epoch));
    return const Loadable.initial();
  }

  String? get _key {
    final uid = _uid;
    return uid == null ? null : StatsKeys.cache(uid, endpoint, _scope, arg);
  }

  Future<void> _start(int epoch) async {
    if (!_alive || epoch != _epoch) return;
    final key = _key;
    if (key == null) return;
    final cached = await ref.read(cacheStoreProvider).read(key);
    if (!_alive || epoch != _epoch) return;
    if (cached != null && state.data == null) {
      try {
        state = Loadable(
          data: parse(cached.value, arg),
          loading: true,
          updatedAt: cached.storedAt,
          fromCache: true,
        );
      } catch (e) {
        AppLog.warn('İstatistik önbelleği okunamadı', error: e);
      }
    }
    await refresh();
  }

  /// Sunucudan tazeler (eşzamanlı çağrılar birleşir). Hata fırlatmaz.
  Future<void> refresh() {
    final running = _inFlight;
    if (running != null && _inFlightEpoch == _epoch) return running;
    final f = _load();
    _inFlight = f;
    _inFlightEpoch = _epoch;
    return f.whenComplete(() {
      if (identical(_inFlight, f)) _inFlight = null;
    });
  }

  /// Veri yoksa ya da [maxAge]'den eskiyse tazeler (ana sayfaya dönüş, uygulamanın öne gelmesi).
  Future<void> refreshIfStale([Duration maxAge = const Duration(minutes: 3)]) {
    final at = state.updatedAt;
    final stale =
        at == null ||
        state.fromCache ||
        DateTime.now().toUtc().difference(at) > maxAge;
    return stale ? refresh() : Future<void>.value();
  }

  Future<void> _load() async {
    if (!_alive) return;
    final key = _key;
    if (key == null || !accepts(_scope)) return;
    final uid = _uid;
    final epoch = _epoch;
    final period = arg;
    state = state.copyWith(loading: true);
    try {
      final r = await fetch(ref.read(statsRepositoryProvider), period);
      if (!_alive || epoch != _epoch) return;
      state = Loadable(data: r.data, updatedAt: DateTime.now().toUtc());
      await ref
          .read(cacheStoreProvider)
          .write(key, r.raw, userId: uid, ttl: const Duration(days: 3));
    } on AppFailure catch (f) {
      if (!_alive || epoch != _epoch) return;
      if (f is UnknownFailure && f.cancelled) {
        state = state.copyWith(loading: false);
        return;
      }
      if (statsDenied(f)) {
        // Yetki kalktı ya da uç yok: eski veri de gösterilmez.
        state = Loadable(error: f);
        await ref.read(cacheStoreProvider).remove(key);
        return;
      }
      state = state.copyWith(loading: false, error: f);
    }
  }
}

/// `GET stats/bayi` (kapsam `station` ya da `own`), dönem başına.
final bayiStatsProvider =
    NotifierProvider.family<
      BayiStatsController,
      Loadable<BayiStats>,
      StatsPeriod
    >(BayiStatsController.new);

class BayiStatsController extends StatsController<BayiStats> {
  @override
  String get endpoint => 'bayi';

  @override
  bool accepts(StatsScope scope) => scope.isBayi;

  @override
  Future<({BayiStats data, Object? raw})> fetch(
    StatsRepository repo,
    StatsPeriod period,
  ) => repo.bayi(period);

  @override
  BayiStats parse(Object? raw, StatsPeriod period) =>
      BayiStats.fromJson(raw, period: period);
}

/// `GET stats/customer`, dönem başına.
final customerStatsProvider =
    NotifierProvider.family<
      CustomerStatsController,
      Loadable<CustomerStats>,
      StatsPeriod
    >(CustomerStatsController.new);

class CustomerStatsController extends StatsController<CustomerStats> {
  @override
  String get endpoint => 'customer';

  @override
  bool accepts(StatsScope scope) => scope == StatsScope.customer;

  @override
  Future<({CustomerStats data, Object? raw})> fetch(
    StatsRepository repo,
    StatsPeriod period,
  ) => repo.customer(period);

  @override
  CustomerStats parse(Object? raw, StatsPeriod period) =>
      CustomerStats.fromJson(raw, period: period);
}

/// Yönetici destesi görünür mü: kapsam var ve sunucu bu ayın istatistiklerini reddetmedi (403 / 404)
/// ya da hiçbir bölüm göndermemiş değil. Yüklenirken true (deste iskelet gösterir). Müşteri ana
/// sayfası harcama eğrisini deste görünürken gizler (aynı veri iki kez görünmez).
final canSeeStatsDeckProvider = Provider<bool>((ref) {
  final scope = ref.watch(statsScopeProvider);
  if (scope == StatsScope.none) return false;
  if (scope.isBayi) {
    return !ref.watch(
      bayiStatsProvider(StatsPeriod.month).select(
        (s) =>
            (statsDenied(s.error) && s.data == null) ||
            (s.data?.isBlank ?? false),
      ),
    );
  }
  return !ref.watch(
    customerStatsProvider(StatsPeriod.month).select(
      (s) =>
          (statsDenied(s.error) && s.data == null) ||
          (s.data?.isBlank ?? false),
    ),
  );
});

/// Saha temsilcisinin form sayıları ("Saha formlarım" kartının yedeği; `team` boşsa).
final statsFieldSummaryProvider =
    FutureProvider.autoDispose<StatsFieldSummary?>((ref) async {
      ref.watch(currentUserIdProvider);
      try {
        return await ref.read(statsRepositoryProvider).fieldSummary();
      } on AppFailure {
        return null;
      }
    });

/// Bu ayın istatistiklerini tazeler (ana sayfa "aşağı çek yenile" ile birlikte çağrılabilir).
Future<void> refreshManagerStats(WidgetRef ref) async {
  final scope = ref.read(statsScopeProvider);
  if (scope == StatsScope.none) return;
  if (scope.isBayi) {
    await ref.read(bayiStatsProvider(StatsPeriod.month).notifier).refresh();
  } else {
    await ref.read(customerStatsProvider(StatsPeriod.month).notifier).refresh();
  }
}
