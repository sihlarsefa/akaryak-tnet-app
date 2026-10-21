import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/prefs_store.dart';

/// Biyometrik kilit tercihi (Profil → "Face ID / parmak izi ile kilitle"). Kilit ekranı ve biyometrik
/// doğrulama A1'dedir; bu sağlayıcı yalnızca tercihi tutar, [SessionController] kilitler.
final biometricLockProvider = NotifierProvider<BiometricLockController, bool>(
  BiometricLockController.new,
);

class BiometricLockController extends Notifier<bool> {
  /// Arka planda bu süreden uzun kalınca kilitlenir.
  static const grace = Duration(seconds: 60);

  @override
  bool build() => ref.read(prefsStoreProvider).getBool(PrefKeys.biometricLock);

  Future<void> set(bool enabled) async {
    state = enabled;
    await ref.read(prefsStoreProvider).setBool(PrefKeys.biometricLock, enabled);
  }
}
