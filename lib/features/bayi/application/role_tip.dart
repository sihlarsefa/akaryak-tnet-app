import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/access_policy.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/storage/prefs_store.dart';

/// "Nasıl çalışır" (tasarım v4 "Sade" §4 `AknFirstRunHint`): bayi ana sayfasının ilk oturum ipucu;
/// eski rol ipucu ve asistan kartının yerine. Üç adım rol ön ayarına göre, sekme adları alt menünün
/// kelimeleriyle.
abstract final class BayiHintSteps {
  static List<String> forPreset(RolePreset preset) => switch (preset) {
    RolePreset.orderDesk => const [
      'Yeni siparişlere Teklifler sekmesinden fiyat verin.',
      'Önerilen fiyatları tek dokunuşla yazıp teklifleri toplu gönderin.',
      'Müşterinin kararını Siparişler sekmesinden izleyin.',
    ],
    RolePreset.finance => const [
      'Finans onayı bekleyen talepler Onaylar sekmesinde.',
      'Carilerin limit ve risk bilgisi Finans sekmesinde.',
      'Vadesi geçen ödemeler Tahsilat sekmesinde.',
    ],
    RolePreset.accounting => const [
      'Vadesi geçen ödemeler ve kontrol bekleyen belgeler Tahsilat sekmesinde.',
      'Carilerin limit bilgisi Finans sekmesinde.',
      'Siparişlerin ödeme durumu Siparişler sekmesinde.',
    ],
    RolePreset.dispatch => const [
      'Onaylanan siparişleri Sevkiyat sekmesinden planlayın.',
      'Şoför atayın; şoför uygulamayı kullanmıyorsa yola çıkışı ve teslimi siz bildirin.',
      'İtiraz edilen teslimatlar da Sevkiyat sekmesinde.',
    ],
    RolePreset.salesManager => const [
      'Saha ekibinizin formları Saha sekmesinde.',
      'Kararınızı bekleyen talepler Onaylar sekmesinde.',
      'Carilerin limit ve sipariş durumu Cariler sekmesinde.',
    ],
    RolePreset.viewer => const [
      'Siparişleri, sevkiyatları ve carileri görebilirsiniz.',
      'Bir değişiklik gerekirse bayi yöneticinize başvurun.',
    ],
    _ => const [
      'Yeni siparişlere Teklifler sekmesinden fiyat verin.',
      'Müşteri onaylayınca sevkiyatı planlayın.',
      'Kararınızı bekleyen talepler Onaylar sekmesinde.',
    ],
  };
}

/// İlk oturum ipucu görünür mü (kullanıcı başına bir kez; "Anladım" deyince bir daha gösterilmez).
/// Eski rol ipucunun anahtarı korunur: ipucunu kapatmış kullanıcı yenisini de görmez.
final bayiFirstRunHintProvider =
    NotifierProvider<BayiFirstRunHintController, bool>(
      BayiFirstRunHintController.new,
    );

class BayiFirstRunHintController extends Notifier<bool> {
  static const _name = 'bayi.roleTipDismissed';

  @override
  bool build() {
    final user = ref.watch(currentUserIdProvider);
    if (user == null) return false;
    return !ref.read(prefsStoreProvider).getBool(PrefKeys.user(user, _name));
  }

  Future<void> dismiss() async {
    final user = ref.read(currentUserIdProvider);
    state = false;
    if (user == null) return;
    await ref
        .read(prefsStoreProvider)
        .setBool(PrefKeys.user(user, _name), true);
  }
}
