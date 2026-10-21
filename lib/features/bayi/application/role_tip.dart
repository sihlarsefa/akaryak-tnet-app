import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/access_policy.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/storage/prefs_store.dart';

/// İlk girişte bir kez gösterilen, kapatılabilir rol ipucu (spec C.5 Home tarifi).
@immutable
class RoleTip {
  const RoleTip({
    required this.title,
    required this.message,
    this.route,
    this.actionLabel,
  });

  final String title;
  final String message;

  /// İpucunun yönlendirdiği ekran (varsa).
  final String? route;
  final String? actionLabel;

  /// Rol ön ayarına göre ipucu (rol adına değil, alt menü ön ayarına bakılır).
  static RoleTip forPolicy(AccessPolicy p) => switch (p.rolePreset) {
    RolePreset.owner || RolePreset.orderDesk => const RoleTip(
      title: 'Teklif masası tek ekranda',
      message:
          'Bekleyen siparişlere önerilen fiyatları uygulayıp toplu teklif verebilirsiniz.',
      route: '/quote-desk',
      actionLabel: 'Teklif masasını aç',
    ),
    RolePreset.finance => const RoleTip(
      title: "Onaylarım'da bekleyenler",
      message:
          'Finans onayı bekleyen siparişler, ön kayıtlar ve yeni cariler Onaylarım ekranında toplanır.',
      route: '/approvals',
      actionLabel: "Onaylarım'ı aç",
    ),
    RolePreset.accounting => const RoleTip(
      title: 'Tahsilat bir dokunuş uzakta',
      message:
          'Vadesi geçen ödemeler ve kontrol bekleyen belgeler Tahsilat ekranında.',
      route: '/payments',
      actionLabel: "Tahsilat'ı aç",
    ),
    RolePreset.dispatch => const RoleTip(
      title: 'Sevkiyat panosu',
      message:
          'Planlanacak siparişler ve bugünkü sevkiyatlar Sevkiyat ekranında. Şoför uygulamayı '
          'kullanmıyorsa yola çıkışı ve teslimi siz bildirebilirsiniz.',
      route: '/dispatch',
      actionLabel: "Sevkiyat'ı aç",
    ),
    RolePreset.salesManager => const RoleTip(
      title: 'Saha ekibiniz burada',
      message:
          'Saha formlarını, ön kayıtları ve onay bekleyenleri Saha ekranından izleyin.',
      route: '/field',
      actionLabel: "Saha'yı aç",
    ),
    RolePreset.viewer => const RoleTip(
      title: 'Görüntüleme yetkiniz var',
      message:
          'Siparişleri, sevkiyatları ve carileri görebilirsiniz; değişiklik yapmak için yöneticinize başvurun.',
    ),
    _ => const RoleTip(
      title: 'Hoş geldiniz',
      message:
          'Ana sayfa yetkilerinize göre özetlenir; ayrıntı için bölümlere dokunun.',
    ),
  };
}

/// Rol ipucu görünür mü (kullanıcı başına bir kez; kapatınca bir daha gösterilmez).
final bayiRoleTipProvider = NotifierProvider<BayiRoleTipController, bool>(
  BayiRoleTipController.new,
);

class BayiRoleTipController extends Notifier<bool> {
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

/// "Asistana sorun" ana sayfa kartı (kapatılabilir; kullanıcı başına).
final bayiAssistantCardProvider =
    NotifierProvider<BayiAssistantCardController, bool>(
      BayiAssistantCardController.new,
    );

class BayiAssistantCardController extends Notifier<bool> {
  static const _name = 'bayi.assistantCardDismissed';

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
