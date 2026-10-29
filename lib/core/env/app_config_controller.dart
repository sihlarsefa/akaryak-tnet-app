import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_config.dart';
import '../network/app_failure.dart';
import '../network/network_providers.dart';
import '../offline/cache_store.dart';
import '../utils/log.dart';
import 'app_env.dart';
import 'app_info.dart';

/// Güncelleme durumu (yönlendirici ve güncelleme ekranı).
enum UpdateStatus {
  none,

  /// Yeni sürüm var; kullanıcı erteleyebilir.
  optional,

  /// Bu sürüm desteklenmiyor (minBuild ya da 426).
  required,
}

/// Sunucunun bu uygulamayı kabul edip etmediği (son canlı `app/config` yanıtına göre).
enum ServerAvailability {
  /// Henüz canlı yanıt yok (çevrimdışı, zaman aşımı, 5xx): engellenmez.
  unknown,

  /// Sunucu bu sözleşmeyi konuşuyor.
  ok,

  /// `maintenance.active`: "Bakımdayız".
  maintenance,

  /// `app/config` 404 (eski API) ya da `contractVersion` farklı: "Sunucu güncel değil".
  outdated;

  /// Uygulama içeriği yerine durum ekranı gösterilir.
  bool get blocks => this == maintenance || this == outdated;
}

/// Son canlı `app/config` yanıtından çıkan sunucu durumu (yönlendirici `/update?reason=` için okur).
final serverAvailabilityProvider =
    NotifierProvider<ServerAvailabilityNotifier, ServerAvailability>(
      ServerAvailabilityNotifier.new,
    );

class ServerAvailabilityNotifier extends Notifier<ServerAvailability> {
  @override
  ServerAvailability build() => ServerAvailability.unknown;

  void set(ServerAvailability value) {
    if (state != value) state = value;
  }
}

/// `GET app/config` (anonim; spec B.3, D.7). Açılışta önce önbellek, sonra sunucu.
///
/// - [load] en fazla [bootTimeout] (3 sn) bekler; geç gelen yanıt yine uygulanır.
/// - Sunucuya ulaşılamazsa önbellek / güvenli varsayılan kalır; 30 sn sonra yeniden denenir.
/// - 404 ya da farklı sözleşme → [ServerAvailability.outdated]; bakım → [ServerAvailability.maintenance].
/// - Test derlemesinde demo oturumu açılınca yapılandırma sahte sunucudan, kapanınca yeniden canlı
///   sunucudan okunur. Önbellek yalnızca canlı yanıtı tutar: demo yapılandırması canlı açılışa taşınmaz;
///   önceki dünyadan geç gelen yanıt uygulanmaz.
final appConfigProvider = NotifierProvider<AppConfigController, AppConfig>(
  AppConfigController.new,
);

class AppConfigController extends Notifier<AppConfig> {
  /// Açılışta `app/config` için en uzun bekleme (spec D.7).
  static const bootTimeout = Duration(seconds: 3);

  /// Ulaşılamayınca yeniden deneme aralığı.
  static const retryDelay = Duration(seconds: 30);

  bool _forcedUpdate = false;
  Future<void>? _inFlight;
  Timer? _retry;
  bool _disposed = false;

  /// Etkin ortamın kuşağı: demo oturumu açılıp kapanınca artar.
  int _generation = 0;

  @override
  AppConfig build() {
    ref.onDispose(() {
      _disposed = true;
      _retry?.cancel();
    });
    // Değişiklik başka bir sağlayıcının okuması sırasında bildirilebilir; tepki bir mikro görev sonra.
    ref.listen<AppEnv>(appEnvProvider, (prev, next) {
      if (prev == null || prev.isFake == next.isFake) return;
      Future.microtask(() => _onWorldChanged(next));
    });
    return AppConfig.fallback;
  }

  /// Demo oturumu açıldı ya da kapandı: o dünyanın sunucusu yeniden okunur.
  void _onWorldChanged(AppEnv env) {
    if (_disposed) return;
    _generation++;
    _retry?.cancel();
    _inFlight = null;
    ref
        .read(serverAvailabilityProvider.notifier)
        .set(ServerAvailability.unknown);
    // Canlı dünyaya dönüş: sahte sunucunun yapılandırması hemen bırakılır; önbellekteki son canlı yanıt
    // (yoksa güvenli varsayılan) geçer, ardından canlı sunucu okunur.
    if (!env.isFake) state = _withForced(AppConfig.fallback);
    unawaited(load());
  }

  /// Önbellek + sunucu. Hata fırlatmaz; en fazla [timeout] bekler (istek arka planda sürer ve
  /// tamamlanınca uygulanır).
  Future<void> load({Duration timeout = bootTimeout}) async {
    final generation = _generation;
    // Önbellek canlı sunucunun son yanıtıdır; demo oturumunda kullanılmaz.
    if (!ref.read(appEnvProvider).demoSession) {
      final cached = await ref
          .read(cacheStoreProvider)
          .read(CacheKeys.appConfig);
      if (cached != null && state.fromCache && generation == _generation) {
        state = _withForced(AppConfig.fromJson(cached.value, fromCache: true));
      }
    }
    var running = _inFlight;
    if (running == null) {
      late final Future<void> f;
      f = _fetch().whenComplete(() {
        if (identical(_inFlight, f)) _inFlight = null;
      });
      _inFlight = running = f;
    }
    try {
      await running.timeout(timeout);
    } on TimeoutException {
      AppLog.debug(
        'app/config ${timeout.inSeconds} sn içinde gelmedi; önbellek kullanılıyor',
      );
    }
  }

  Future<void> _fetch() async {
    _retry?.cancel();
    final generation = _generation;
    final demo = ref.read(appEnvProvider).demoSession;
    final info = ref.read(appInfoProvider);
    final api = ref.read(apiClientProvider);
    try {
      final json = await api.get<Object?>(
        'app/config',
        query: {'platform': info.platform},
        anonymous: true,
        parse: (j) => j,
      );
      // Bu arada dünya değiştiyse (demo oturumu açıldı ya da kapandı) yanıt uygulanmaz.
      if (_disposed || generation != _generation) return;
      final config = AppConfig.fromJson(json);
      state = _withForced(config);
      ref
          .read(serverAvailabilityProvider.notifier)
          .set(
            config.maintenance.active
                ? ServerAvailability.maintenance
                : config.contractMatches
                ? ServerAvailability.ok
                : ServerAvailability.outdated,
          );
      if (!demo) {
        await ref.read(cacheStoreProvider).write(CacheKeys.appConfig, json);
      }
    } catch (e) {
      if (_disposed || generation != _generation) return;
      final f = AppFailure.from(e);
      if (f is NotFoundFailure) {
        // Mobil v1 uçları yok: eski API.
        ref
            .read(serverAvailabilityProvider.notifier)
            .set(ServerAvailability.outdated);
      } else {
        AppLog.warn(
          'app/config alınamadı; önbellek/varsayılan kullanılıyor',
          error: f,
        );
        _retry = Timer(retryDelay, () => unawaited(load()));
      }
    }
  }

  AppConfig _withForced(AppConfig c) {
    if (!_forcedUpdate) return c;
    final build = ref.read(appInfoProvider).appBuild;
    return c.copyWith(
      minBuild: max(c.minBuild, build + 1),
      latestBuild: max(c.latestBuild, build + 1),
    );
  }

  /// 426 alındı: bu derlemeden yüksek minBuild varsayılır (güncelleme ekranı açılır).
  void markUpdateRequired() {
    _forcedUpdate = true;
    state = _withForced(state);
  }
}

/// Bu derleme için güncelleme durumu.
final updateStatusProvider = Provider<UpdateStatus>((ref) {
  final config = ref.watch(appConfigProvider);
  final build = ref.watch(appInfoProvider).appBuild;
  if (config.requiresUpdate(build)) return UpdateStatus.required;
  if (config.hasOptionalUpdate(build)) return UpdateStatus.optional;
  return UpdateStatus.none;
});
