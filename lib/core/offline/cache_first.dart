import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_controller.dart';
import '../network/api_client.dart';
import '../utils/log.dart';

/// Önce önbellek, sonra sunucu (stale-while-revalidate) ayrıntı denetleyicisi: `FutureProvider` yerine
/// geçer, sayfalar aynı `AsyncValue`'yu izler (`.when`, `.future`, `ref.invalidate` aynen çalışır).
///
/// - Sağlayıcının **ilk** kuruluşunda son yanıt ([peek]) varsa hemen gösterilir (`AsyncData`), bir
///   sonraki olay turunda sunucudan tazelenir: tazelenirken değer kalır (`isRefreshing`, sayfada ince
///   "güncelleniyor" çubuğu); tazeleme başarısızsa (çevrimdışı, 429, 503) önbellekteki değer kalır.
/// - Sonraki kuruluşlar (`ref.invalidate`, aşağı çek yenile, kullanıcı değişimi) doğrudan sunucuya
///   gider; Riverpod önceki değeri yükleme boyunca tutar.
/// - Kullanıcı değişince yeniden kurulur (önceki kullanıcının değeri görünmez; önbellek de kullanıcıya
///   özeldir).
abstract class CacheFirstFamilyAsyncNotifier<T, A>
    extends AutoDisposeFamilyAsyncNotifier<T, A> {
  bool _built = false;
  int _gen = 0;
  bool _alive = true;
  DateTime? _cachedAt;

  /// Önbellekteki son yanıt (ağa çıkmaz); yoksa null.
  Future<CachedResponse<T>?> peek(A arg);

  /// Sunucudan (yanıtı önbelleğe yazar).
  Future<T> fetch(A arg);

  /// Gösterilen değer önbellekten geldiyse kaydın zamanı (sunucudan tazelenince null).
  DateTime? get cachedAt => _cachedAt;

  @override
  Future<T> build(A arg) async {
    ref.watch(currentUserIdProvider);
    final gen = ++_gen;
    _alive = true;
    ref.onDispose(() => _alive = false);
    final first = !_built;
    _built = true;
    if (first) {
      CachedResponse<T>? hit;
      try {
        hit = await peek(arg);
      } catch (e) {
        AppLog.debug('Önbellek okunamadı: ${e.runtimeType}');
      }
      if (hit != null && _alive && gen == _gen) {
        _cachedAt = hit.storedAt;
        // Riverpod değeri `build` tamamlanınca yazar; tazeleme bir sonraki olay turunda başlar.
        Timer.run(() => unawaited(_revalidate(gen)));
        return hit.value;
      }
    }
    final value = await fetch(arg);
    _cachedAt = null;
    return value;
  }

  Future<void> _revalidate(int gen) async {
    if (!_alive || gen != _gen) return;
    final previous = state;
    if (!previous.hasValue || previous.isLoading) return;
    state = AsyncLoading<T>().copyWithPrevious(previous);
    try {
      final fresh = await fetch(arg);
      if (!_alive || gen != _gen) return;
      _cachedAt = null;
      state = AsyncData(fresh);
    } catch (e) {
      if (!_alive || gen != _gen) return;
      // İçerik kalır: önbellekteki değer, hata sayfası değil.
      AppLog.debug('Arka plan tazelemesi başarısız: ${e.runtimeType}');
      state = AsyncData(previous.requireValue);
    }
  }
}

/// [CacheFirstFamilyAsyncNotifier]'ın aile anahtarı olmayan eşi (tek kayıt: "Finans bilgisi" gibi).
abstract class CacheFirstAsyncNotifier<T> extends AutoDisposeAsyncNotifier<T> {
  bool _built = false;
  int _gen = 0;
  bool _alive = true;
  DateTime? _cachedAt;

  Future<CachedResponse<T>?> peek();

  Future<T> fetch();

  DateTime? get cachedAt => _cachedAt;

  @override
  Future<T> build() async {
    ref.watch(currentUserIdProvider);
    final gen = ++_gen;
    _alive = true;
    ref.onDispose(() => _alive = false);
    final first = !_built;
    _built = true;
    if (first) {
      CachedResponse<T>? hit;
      try {
        hit = await peek();
      } catch (e) {
        AppLog.debug('Önbellek okunamadı: ${e.runtimeType}');
      }
      if (hit != null && _alive && gen == _gen) {
        _cachedAt = hit.storedAt;
        Timer.run(() => unawaited(_revalidate(gen)));
        return hit.value;
      }
    }
    final value = await fetch();
    _cachedAt = null;
    return value;
  }

  Future<void> _revalidate(int gen) async {
    if (!_alive || gen != _gen) return;
    final previous = state;
    if (!previous.hasValue || previous.isLoading) return;
    state = AsyncLoading<T>().copyWithPrevious(previous);
    try {
      final fresh = await fetch();
      if (!_alive || gen != _gen) return;
      _cachedAt = null;
      state = AsyncData(fresh);
    } catch (e) {
      if (!_alive || gen != _gen) return;
      AppLog.debug('Arka plan tazelemesi başarısız: ${e.runtimeType}');
      state = AsyncData(previous.requireValue);
    }
  }
}

/// Sayfalı listenin ilk sayfası için önbellek: denetleyicinin ömründe **bir kez** önbellekteki ilk sayfayı
/// verir ve hemen ardından listeyi sunucudan tazeletir ([page1]). Liste denetleyicisinin kendisine
/// dokunmadan (`fetchPage` içinde) kullanılır.
class FirstPageCache {
  bool _served = false;

  /// İlk çağrıda önbellekteki sayfa varsa onu döndürür ve bir sonraki olay turunda [revalidate]'i
  /// çağırır; yoksa (ya da sonraki çağrılarda) [network].
  Future<R> page1<R>({
    required Future<CachedResponse<R>?> Function() peek,
    required Future<R> Function() network,
    required void Function() revalidate,
  }) async {
    if (!_served) {
      _served = true;
      CachedResponse<R>? hit;
      try {
        hit = await peek();
      } catch (_) {
        hit = null;
      }
      if (hit != null) {
        Timer.run(revalidate);
        return hit.value;
      }
    }
    return network();
  }

  /// Bir sonraki ilk yükleme yeniden önbellekten başlayabilir.
  void reset() => _served = false;
}
