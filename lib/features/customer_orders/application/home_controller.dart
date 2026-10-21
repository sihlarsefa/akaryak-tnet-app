import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/cache_store.dart';
import '../../../core/push/push_providers.dart';
import '../../../core/utils/log.dart';
import '../data/customer_orders_repository.dart';
import '../data/form_models.dart';
import '../data/home_models.dart';
import 'loadable.dart';

/// `GET home/customer` (spec B.6): ana sayfa, sihirbazın bayi / tarih / onay kuralı kaynağı.
/// Önce önbellek (çevrimdışı açılış), sonra sunucu. Push gelince ve [refresh] ile tazelenir.
final customerHomeProvider =
    NotifierProvider<CustomerHomeController, Loadable<CustomerHomeData>>(
      CustomerHomeController.new,
    );

class CustomerHomeController extends Notifier<Loadable<CustomerHomeData>> {
  int _epoch = 0;
  bool _alive = true;
  Future<void>? _inFlight;

  @override
  Loadable<CustomerHomeData> build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    final uid = ref.watch(currentUserIdProvider);
    final epoch = ++_epoch;
    ref.listen(a2DataRevisionProvider, (_, _) => unawaited(refresh()));
    ref.listen(pushEventsProvider, (_, next) {
      final p = next.valueOrNull?.payload;
      if (p == null) return;
      unawaited(refresh());
    });
    if (uid == null) return const Loadable();
    Future.microtask(() => _start(uid, epoch));
    return const Loadable.initial();
  }

  Future<void> _start(String uid, int epoch) async {
    if (!_alive) return;
    final cached = await ref.read(cacheStoreProvider).read(A2Keys.home(uid));
    if (!_alive || epoch != _epoch) return;
    if (cached != null && state.data == null) {
      try {
        state = Loadable(
          data: CustomerHomeData.fromJson(cached.value),
          loading: true,
          updatedAt: cached.storedAt,
          fromCache: true,
        );
      } catch (e) {
        AppLog.warn('Ana sayfa önbelleği okunamadı', error: e);
      }
    }
    await refresh();
  }

  /// Sunucudan tazeler (eşzamanlı çağrılar birleşir). Hata fırlatmaz.
  Future<void> refresh() {
    final running = _inFlight;
    if (running != null) return running;
    final f = _load();
    _inFlight = f;
    return f.whenComplete(() => _inFlight = null);
  }

  Future<void> _load() async {
    if (!_alive) return;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final epoch = _epoch;
    state = state.copyWith(loading: true);
    try {
      final raw = await ref.read(customerOrdersRepositoryProvider).homeRaw();
      if (!_alive || epoch != _epoch) return;
      final data = CustomerHomeData.fromJson(raw);
      state = Loadable(data: data, updatedAt: DateTime.now().toUtc());
      await ref
          .read(cacheStoreProvider)
          .write(A2Keys.home(uid), raw, userId: uid);
    } on AppFailure catch (f) {
      if (!_alive || epoch != _epoch) return;
      state = state.copyWith(loading: false, error: f);
    }
  }
}

/// `GET catalog/order-form`: ürünler, teslimat noktaları (pencere, tank, erişim), şablonlar.
/// Önbelleklenir (çevrimdışı ayrıntı ekranı noktanın penceresini ve konumunu buradan okur).
final orderFormProvider =
    NotifierProvider<OrderFormController, Loadable<OrderFormOptions>>(
      OrderFormController.new,
    );

class OrderFormController extends Notifier<Loadable<OrderFormOptions>> {
  int _epoch = 0;
  bool _alive = true;
  Future<void>? _inFlight;

  @override
  Loadable<OrderFormOptions> build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    final uid = ref.watch(currentUserIdProvider);
    final epoch = ++_epoch;
    if (uid == null) return const Loadable();
    Future.microtask(() => _start(uid, epoch));
    return const Loadable.initial();
  }

  Future<void> _start(String uid, int epoch) async {
    if (!_alive) return;
    final cached = await ref
        .read(cacheStoreProvider)
        .read(A2Keys.orderForm(uid));
    if (!_alive || epoch != _epoch) return;
    if (cached != null && state.data == null) {
      try {
        state = Loadable(
          data: OrderFormOptions.fromJson(cached.value),
          loading: true,
          updatedAt: cached.storedAt,
          fromCache: true,
        );
      } catch (_) {}
    }
    await refresh();
  }

  Future<void> refresh() {
    final running = _inFlight;
    if (running != null) return running;
    final f = _load();
    _inFlight = f;
    return f.whenComplete(() => _inFlight = null);
  }

  /// Veri gelene kadar bekler (sihirbaz açılışı).
  Future<OrderFormOptions?> ensure() async {
    if (state.data != null && !state.fromCache) return state.data;
    await refresh();
    return state.data;
  }

  Future<void> _load() async {
    if (!_alive) return;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final epoch = _epoch;
    state = state.copyWith(loading: true);
    try {
      final raw = await ref
          .read(customerOrdersRepositoryProvider)
          .orderFormRaw();
      if (!_alive || epoch != _epoch) return;
      state = Loadable(
        data: OrderFormOptions.fromJson(raw),
        updatedAt: DateTime.now().toUtc(),
      );
      await ref
          .read(cacheStoreProvider)
          .write(A2Keys.orderForm(uid), raw, userId: uid);
    } on AppFailure catch (f) {
      if (!_alive || epoch != _epoch) return;
      state = state.copyWith(loading: false, error: f);
    }
  }
}
