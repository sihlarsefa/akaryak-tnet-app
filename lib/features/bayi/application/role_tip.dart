import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/access_policy.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/storage/prefs_store.dart';
import 'bayi_grants.dart';

/// "Nasıl çalışır" (tasarım v4 "Sade" §4 `AknFirstRunHint`): bayi ana sayfasının ilk oturum ipucu;
/// eski rol ipucu ve asistan kartının yerine. Üç adım rol ön ayarına göre, sekme adları alt menünün
/// kelimeleriyle.
abstract final class BayiHintSteps {
  /// v4 tur 2: adımlar yetkilerden seçilir ve bir sekmeyi yalnızca alt menüdeyse adıyla anar (değilse
  /// "Diğer › Onaylar'da"). Depo planlamaz ve şoför atamaz; özel rol teklif vermiyorsa Teklifler'i
  /// duymaz. İkmal birimi (roller v5): teklif, sevkiyat planı ve şoför ataması, yükleme / dolum kaydı;
  /// her adım yetkisi varsa. [inBar]: yol alt menüde mi.
  static List<String> forGrants(
    RolePreset preset,
    BayiGrants g, {
    required bool Function(String path) inBar,
  }) {
    String at(String path, String bar, String more) =>
        inBar(path) ? '$bar sekmesinde' : 'Diğer › $more';
    String from(String path, String bar, String more) =>
        inBar(path) ? '$bar sekmesinden' : 'Diğer › $more';
    switch (preset) {
      case RolePreset.dispatch when !g.planShipment:
        return [
          'Bugünkü yüklemeler ${at(AppRoutes.dispatch, 'Sevkiyat', "Sevkiyat'ta")}.',
          if (g.dispatchOrReport)
            'Yola çıkışı ve teslimi sevkiyatın ayrıntısından bildirin.',
          'Planlama ve şoför ataması sevkiyat ekibindedir.',
        ];
      case RolePreset.supply:
        final quotes = g.quoteOnDesk || g.quoteOnOrder;
        final steps = [
          if (quotes && g.viewDesk)
            'Yeni siparişlere ${from(AppRoutes.quoteDesk, 'Teklifler', "Teklifler'den")} fiyat verin.'
          else if (quotes && g.viewOrders)
            'Yeni siparişlere ${from(AppRoutes.bayiOrders, 'Siparişler', "Siparişler'den")} fiyat verin.',
          if (g.planShipment && g.viewBoard)
            'Müşteri onaylayınca sevkiyatı ${from(AppRoutes.dispatch, 'Sevkiyat', "Sevkiyat'tan")} planlayın'
                '${g.assignDriver ? ' ve şoför atayın' : ''}.',
          if (g.policy.hasCap(Caps.loadingRecord) && g.viewShipments)
            'Bugünkü yüklemeler ve dolum kaydı ${at(AppRoutes.dispatch, 'Sevkiyat', "Sevkiyat'ta")}.',
        ];
        if (steps.length >= 2) return steps;
        return [
          ...steps,
          if (g.viewOrders)
            'Siparişleri ${from(AppRoutes.bayiOrders, 'Siparişler', "Siparişler'den")} izleyin.',
          'Bir değişiklik gerekirse bayi yöneticinize başvurun.',
        ].take(3).toList();
      case RolePreset.owner || RolePreset.generic:
        final quotes = g.quoteOnDesk || g.quoteOnOrder;
        final steps = [
          if (quotes && g.viewDesk)
            'Yeni siparişlere ${from(AppRoutes.quoteDesk, 'Teklifler', "Teklifler'den")} fiyat verin.'
          else if (quotes && g.viewOrders)
            'Yeni siparişlere ${from(AppRoutes.bayiOrders, 'Siparişler', "Siparişler'den")} fiyat verin.',
          if (g.planShipment) 'Müşteri onaylayınca sevkiyatı planlayın.',
          if (g.policy.isApprover && g.viewApprovals)
            'Kararınızı bekleyen talepler ${at(AppRoutes.approvals, 'Onaylar', "Onaylar'da")}.',
        ];
        if (steps.length >= 2) return steps;
        return [
          ...steps,
          if (g.viewOrders)
            'Siparişleri ${from(AppRoutes.bayiOrders, 'Siparişler', "Siparişler'den")} izleyin.',
          'Bir değişiklik gerekirse bayi yöneticinize başvurun.',
        ].take(3).toList();
      default:
        return forPreset(preset);
    }
  }

  static List<String> forPreset(RolePreset preset) => switch (preset) {
    RolePreset.supply => const [
      'Yeni siparişlere Teklifler sekmesinden fiyat verin.',
      'Müşteri onaylayınca sevkiyatı Sevkiyat sekmesinden planlayın ve şoför atayın.',
      'Bugünkü yüklemeler ve dolum kaydı Sevkiyat sekmesinde.',
    ],
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
