import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/access_policy.dart';
import '../core/auth/permissions.dart';
import '../core/auth/session_controller.dart';
import '../core/auth/session_state.dart';
import '../features/bayi/api.dart';
import '../features/customer_orders/api.dart';
import '../features/driver/api.dart';
import '../features/field/api.dart';
import '../features/stats/api.dart';

/// Oturum hazır olur olmaz (soğuk açılışta kayıtlı oturum, girişte `me/access` sonrası) rolün ana
/// sayfa verisi ve bu ayın istatistikleri istenir: ana sayfa açılış ekranının (1 s) bitmesini, deste
/// ana sayfa verisini beklemez (eskiden ana sayfa → istatistik zinciri seri gidiyordu).
///
/// Ana sayfa sağlayıcıları açık kalır (keepAlive): sayfa kurulunca aynı sağlayıcıya abone olur, istek
/// yinelenmez (uçuştaki aynı okuma da tek istektir). Kullanıcı başına bir kez; kullanıcı değişince yeni
/// kullanıcı için yeniden.
final sessionPrefetchProvider = Provider<SessionPrefetcher>((ref) {
  final p = SessionPrefetcher(ref);
  ref.onDispose(p.dispose);
  ref.listen<SessionState>(
    sessionControllerProvider,
    (_, next) => p.onSession(next),
    fireImmediately: true,
  );
  return p;
});

class SessionPrefetcher {
  SessionPrefetcher(this.ref);

  final Ref ref;
  String? _doneFor;
  final List<ProviderSubscription<Object?>> _holds = [];
  Timer? _release;
  bool _disposed = false;

  /// Bir sonraki karede ısıtılacak oturum (aynı karede birden çok oturum değişimi tek ısıtma).
  AccessPolicy? _pending;

  /// Kendiliğinden kapanan (autoDispose) ana sayfa bu süre açık tutulur: sayfa kurulup abone olana kadar.
  static const holdAutoDispose = Duration(seconds: 20);

  void onSession(SessionState s) {
    final access = s.access;
    if (access == null) {
      _doneFor = null;
      _pending = null;
      _releaseHolds();
      return;
    }
    if (_doneFor == access.userId) return;
    _doneFor = access.userId;
    // Dinleyicinin içinde sağlayıcı kurulmaz (türetilmiş sağlayıcılar henüz tazelenmedi): bir sonraki
    // karede (açılış ekranı çizilirken; en geç birkaç ms). Kare geri çağrısı, oturumu değiştiren
    // çağrının bölgesinden (zone) bağımsızdır: yükleme her zaman uygulamanın kendi bölgesinde döner.
    final first = _pending == null;
    _pending = AccessPolicy(access);
    if (!first) return;
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      final p = _pending;
      _pending = null;
      if (_disposed || p == null) return;
      _warm(p);
    });
    binding.ensureVisualUpdate();
  }

  void _warm(AccessPolicy p) {
    try {
      if (!p.isSignedIn || p.isPlatform) return;
      if (p.isCustomer) {
        ref.read(customerHomeProvider);
        ref.read(customerStatsProvider(StatsPeriod.month));
        // Ortadaki "Sipariş ver": sipariş formu hazır olsun.
        if (p.can(Pg.customerCreateOrder, Perm.create)) {
          ref.read(orderFormProvider);
        }
        return;
      }
      if (!p.isBayi) return;
      if (p.isDriverOnly) {
        ref.read(driverListProvider(DriverTab.today));
        return;
      }
      if (p.isFieldSales) {
        _hold(fieldHomeProvider);
      } else {
        ref.read(bayiHomeProvider);
      }
      if (statsScopeFor(p).isBayi) {
        ref.read(bayiStatsProvider(StatsPeriod.month));
      }
    } catch (_) {
      // Ön yükleme yalnızca hız içindir; sayfa kendi yüklemesini yapar.
    }
  }

  void _hold(ProviderListenable<Object?> provider) {
    _holds.add(ref.listen<Object?>(provider, (_, _) {}));
    _release?.cancel();
    _release = Timer(holdAutoDispose, _releaseHolds);
  }

  void _releaseHolds() {
    _release?.cancel();
    _release = null;
    for (final h in _holds) {
      h.close();
    }
    _holds.clear();
  }

  void dispose() {
    _disposed = true;
    _pending = null;
    _releaseHolds();
  }
}
