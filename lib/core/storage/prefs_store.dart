import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tercih anahtarları (gizli olmayan küçük ayarlar).
abstract final class PrefKeys {
  /// Tanıtım ekranları görüldü (ilk açılış).
  static const onboardingDone = 'akn.onboardingDone';

  /// Tema: `system` / `light` / `dark`.
  static const themeMode = 'akn.themeMode';

  /// Biyometrik kilit açık.
  static const biometricLock = 'akn.biometricLock';

  /// Bildirim izni ön sayfası gösterildi (müşterinin ilk siparişinden sonraki yedek öneri).
  static const pushPrimerShown = 'akn.pushPrimerShown';

  /// Sistem bildirim izni bir kez soruldu (Android 13+ "sorulmadı" ile "reddedildi"yi ayırmaz).
  static const pushPermissionRequested = 'akn.pushPermissionRequested';

  /// İlk açılıştaki bildirim izni denetimi yapıldı (izin hiç sorulmamışsa sistem penceresi açıldı;
  /// izin zaten verilmiş ya da reddedilmişse yalnızca not edildi). Bir daha bakılmaz.
  static const pushLaunchAsked = 'akn.pushLaunchAsked';

  /// Bildirim ayarları → "Anlık bildirimler" ana anahtarı (varsayılan açık). Cihaza bağlıdır:
  /// uygulama yeniden açıldığında, çıkışta ve yeniden girişte kalır.
  static const pushOptIn = 'akn.pushOptIn';

  /// Son açılan sürüm (isteğe bağlı güncelleme "sonra hatırlat" için).
  static const lastSeenBuild = 'akn.lastSeenBuild';

  /// İsteğe bağlı güncellemenin ertelendiği derleme.
  static const updateSnoozedBuild = 'akn.updateSnoozedBuild';

  /// İstem dışı çıkışta yarım işleri korunan kullanıcı (`UserDrafts`): aynı kullanıcı girerse
  /// sürer, başka kullanıcı girerse silinir.
  static const draftsOwner = 'akn.draftsOwner';

  /// Kullanıcıya özel anahtar (ör. son teslimat noktası): `akn.u.<userId>.<name>`.
  static String user(String userId, String name) => 'akn.u.$userId.$name';
}

/// shared_preferences sarmalayıcısı. Okumalar eşzamanlıdır (bootstrap yükler).
class PrefsStore {
  PrefsStore(this._prefs);

  final SharedPreferences _prefs;

  bool getBool(String key, {bool fallback = false}) =>
      _prefs.getBool(key) ?? fallback;
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  int? getInt(String key) => _prefs.getInt(key);
  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);

  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String? value) =>
      value == null ? _prefs.remove(key) : _prefs.setString(key, value);

  List<String> getStrings(String key) => _prefs.getStringList(key) ?? const [];
  Future<void> setStrings(String key, List<String> value) =>
      _prefs.setStringList(key, value);

  Future<void> remove(String key) => _prefs.remove(key);

  /// Kullanıcıya özel tercihleri siler (çıkış). [keep] içindeki tam anahtarlar kalır (yarım işler,
  /// bkz. `UserDrafts`).
  Future<void> clearUser(String userId, {Set<String> keep = const {}}) async {
    final prefix = 'akn.u.$userId.';
    for (final k
        in _prefs
            .getKeys()
            .where((k) => k.startsWith(prefix) && !keep.contains(k))
            .toList()) {
      await _prefs.remove(k);
    }
  }
}

/// `bootstrap` gerçek örnekle geçersiz kılar; testler `SharedPreferences.setMockInitialValues` sonrası verir.
final prefsStoreProvider = Provider<PrefsStore>(
  (ref) => throw UnimplementedError(
    'prefsStoreProvider bootstrap içinde geçersiz kılınmalı',
  ),
);

/// Tema seçimi (Profil → Tema: Sistem / Açık / Koyu).
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() =>
      switch (ref.read(prefsStoreProvider).getString(PrefKeys.themeMode)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(prefsStoreProvider).setString(
      PrefKeys.themeMode,
      switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
  }
}

/// Tanıtım ekranları görüldü mü (ilk açılışta yönlendirme).
final onboardingDoneProvider = NotifierProvider<OnboardingDoneController, bool>(
  OnboardingDoneController.new,
);

class OnboardingDoneController extends Notifier<bool> {
  @override
  bool build() => ref.read(prefsStoreProvider).getBool(PrefKeys.onboardingDone);

  Future<void> complete() async {
    state = true;
    await ref.read(prefsStoreProvider).setBool(PrefKeys.onboardingDone, true);
  }

  /// Profil → "Tanıtımı yeniden göster".
  Future<void> reset() async {
    state = false;
    await ref.read(prefsStoreProvider).setBool(PrefKeys.onboardingDone, false);
  }
}
