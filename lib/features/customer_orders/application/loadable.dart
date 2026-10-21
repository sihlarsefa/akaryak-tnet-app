import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/cache_store.dart';
import '../../../core/storage/prefs_store.dart';
import '../../../core/storage/user_drafts.dart';

/// Önbellekli ekran verisi: ilk yüklemede iskelet, yenilemede içerik kalır (üstte ince çubuk),
/// çevrimdışıyken son kayıt "Son güncelleme" ile gösterilir (spec C.4a, C.6).
@immutable
class Loadable<T> {
  const Loadable({
    this.data,
    this.loading = false,
    this.error,
    this.updatedAt,
    this.fromCache = false,
  });

  const Loadable.initial() : this(loading: true);

  final T? data;

  /// İlk yükleme ya da arka plan yenilemesi sürüyor.
  final bool loading;

  /// Son denemenin hatası (veri varsa içerik yine gösterilir).
  final AppFailure? error;

  /// Verinin sunucudan alındığı an (önbellekten geldiyse kayıt anı).
  final DateTime? updatedAt;

  /// Veri önbellekten; sunucudan tazelenemedi.
  final bool fromCache;

  bool get hasData => data != null;
  bool get isFirstLoad => loading && data == null;
  bool get showError => error != null && data == null;
  bool get refreshing => loading && data != null;

  Loadable<T> copyWith({
    T? data,
    bool? loading,
    AppFailure? error,
    bool clearError = false,
    DateTime? updatedAt,
    bool? fromCache,
  }) => Loadable<T>(
    data: data ?? this.data,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    updatedAt: updatedAt ?? this.updatedAt,
    fromCache: fromCache ?? this.fromCache,
  );
}

/// A2 önbellek ve tercih anahtarları (kullanıcıya özel; çıkışta silinir).
abstract final class A2Keys {
  static String home(String uid) => CacheKeys.user(uid, 'a2.home');
  static String orderForm(String uid) => CacheKeys.user(uid, 'a2.orderForm');
  static String ordersPage(String uid, String segment) =>
      CacheKeys.user(uid, 'a2.orders.$segment');
  static String order(String uid, int id) =>
      CacheKeys.user(uid, 'a2.order.$id');
  static String recentOrders(String uid) =>
      CacheKeys.user(uid, 'a2.order.recent');

  /// İstem dışı çıkışta korunur (bekleyen gönderim anahtarı dahil; `UserDrafts`).
  static String wizard(String uid) =>
      CacheKeys.user(uid, UserDrafts.orderWizard);

  // Tercihler
  static String tipFirstOrder(String uid) =>
      PrefKeys.user(uid, 'a2.tipFirstOrder');
  static String assistantCardDismissed(String uid) =>
      PrefKeys.user(uid, 'a2.assistantCard');
  static String lastPoint(String uid) => PrefKeys.user(uid, 'a2.lastPoint');
  static String lastMethod(String uid) => PrefKeys.user(uid, 'a2.lastMethod');
  static String lastStation(String uid) => PrefKeys.user(uid, 'a2.lastStation');
  static String firstOrderDone(String uid) =>
      PrefKeys.user(uid, 'a2.firstOrderDone');
  static String cameraPrimerAccepted(String uid) =>
      PrefKeys.user(uid, 'a2.cameraPrimerOk');
  static String cameraPrimerDeclinedAt(String uid) =>
      PrefKeys.user(uid, 'a2.cameraPrimerNo');
}

/// Sipariş verisi değişti (sipariş verildi, karar verildi, belge yüklendi): ana sayfa ve
/// Siparişlerim açıksa kendini tazeler (kapalı sağlayıcıyı kurmaz).
final a2DataRevisionProvider = NotifierProvider<A2DataRevision, int>(
  A2DataRevision.new,
);

class A2DataRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// En çok bu kadar açılmış sipariş (ayrıntı + takip) çevrimdışı saklanır (spec C.4a).
const kRecentOrderCacheLimit = 20;

/// Oturumdaki kullanıcı yoksa önbellek işlemleri atlanır.
String? a2UserId(Ref ref) => ref.read(currentUserIdProvider);

/// Açılmış sipariş önbelleğini en son [kRecentOrderCacheLimit] kayıtla sınırlar.
Future<void> rememberRecentOrder(
  CacheStore cache,
  String uid,
  int orderId,
) async {
  final key = A2Keys.recentOrders(uid);
  final entry = await cache.read(key);
  final ids = <int>[
    orderId,
    ...?(entry?.value as List?)
        ?.map((e) => e is int ? e : int.tryParse('$e'))
        .whereType<int>()
        .where((id) => id != orderId),
  ];
  final keep = ids.take(kRecentOrderCacheLimit).toList();
  for (final stale in ids.skip(kRecentOrderCacheLimit)) {
    await cache.remove(A2Keys.order(uid, stale));
  }
  await cache.write(key, keep, userId: uid);
}
