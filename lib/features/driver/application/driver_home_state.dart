import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/storage/prefs_store.dart';
import '../data/deliver_draft.dart';

/// İlk girişte bir kez gösterilen ipucu: "Teslimatı kaydırarak onaylayın" (spec C.5 Home tarifi).
/// Cihaz düzeyinde kullanıcı başına saklanır (çıkışta silinmez; ipucu bir daha gösterilmez).
final driverTipVisibleProvider = NotifierProvider<DriverTipController, bool>(
  DriverTipController.new,
);

class DriverTipController extends Notifier<bool> {
  static String keyFor(String userId) => 'akn.driver.slideTipSeen.$userId';

  @override
  bool build() {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return false;
    return !ref.read(prefsStoreProvider).getBool(keyFor(uid));
  }

  Future<void> dismiss() async {
    final uid = ref.read(currentUserIdProvider);
    state = false;
    if (uid != null) {
      await ref.read(prefsStoreProvider).setBool(keyFor(uid), true);
    }
  }
}

/// Kullanıcının yarım kalan teslim taslakları (sevkiyat kimliğine göre; süresi geçenler düşer).
final driverDraftsProvider =
    NotifierProvider<DriverDraftsController, Map<int, DeliverDraft>>(
      DriverDraftsController.new,
    );

class DriverDraftsController extends Notifier<Map<int, DeliverDraft>> {
  @override
  Map<int, DeliverDraft> build() {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const {};
    final store = ref.watch(deliverDraftStoreProvider);
    return store.all(uid);
  }

  /// Taslak değişince (sihirbaz kaydetti, işlem kuyruğa yazıldı, vazgeçildi).
  void reload() {
    final uid = ref.read(currentUserIdProvider);
    state = uid == null
        ? const {}
        : ref.read(deliverDraftStoreProvider).all(uid);
  }
}
