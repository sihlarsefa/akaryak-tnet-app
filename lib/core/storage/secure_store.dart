import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/log.dart';

/// Güvenli depo anahtarları (spec C.4). Erişim belirteci asla diske yazılmaz (yalnızca bellekte).
abstract final class SecureKeys {
  /// Yenileme belirteci.
  static const refresh = 'akn.refresh';

  /// Kurulum başına cihaz kimliği (uuid v4); `X-Device-Id` başlığı.
  static const deviceId = 'akn.deviceId';

  /// Son oturumun kullanıcı kimliği (önbellek anahtarı, çevrimdışı açılış).
  static const userId = 'akn.userId';

  /// Uygulamanın tüm güvenli anahtarları (ilk açılışta silinir; bkz. [FirstLaunch]).
  static const all = [refresh, deviceId, userId];
}

/// Kurulumdan sonraki ilk açılış (spec D.7): iOS Anahtar Zinciri uygulama silinip yeniden kurulunca da
/// durur; eski kurulumun yenileme belirteci ve cihaz kimliği yeni kuruluma taşınmasın diye `akn.*`
/// güvenli anahtarları bir kez silinir. İşaret `shared_preferences`'tadır (kaldırmayla silinir).
abstract final class FirstLaunch {
  static const marker = 'akn.installed';

  /// Kurulumun ilk açılışıysa güvenli anahtarları siler ve true döner.
  static Future<bool> wipeIfFresh({
    required bool Function(String key) hasPref,
    required Future<void> Function(String key) markPref,
    required SecureStore secure,
  }) async {
    if (hasPref(marker)) return false;
    for (final k in SecureKeys.all) {
      await secure.delete(k);
    }
    await markPref(marker);
    return true;
  }
}

/// Anahtar/değer güvenli depo arayüzü (testlerde [MemorySecureStore]).
abstract interface class SecureStore {
  Future<String?> read(String key);

  /// `null` değer anahtarı siler.
  Future<void> write(String key, String? value);

  Future<void> delete(String key);

  Future<void> deleteAll();

  /// Açılışta okunabilirliği doğrular; bozuksa temizler (F2GO GuvenliDepolama.kontrolEt).
  Future<void> verifyReadable();
}

/// iOS Keychain / Android EncryptedSharedPreferences (F2GO `guvenli_depolama.dart` uyarlaması).
///
/// - iOS: `first_unlock_this_device` — cihaz ilk kilit açılışından sonra arka planda (push ile açılış)
///   okunabilir; yedeklerle başka cihaza taşınmaz.
/// - Uygulama depoya yazarken çökerse depo okunamaz hale gelebilir: her okuma hata verir ve kullanıcı
///   ancak yeniden kurunca düzelir. Açılışta [verifyReadable] bozuk depoyu temizler; kullanıcı yalnızca
///   yeniden giriş yapar. Cihaz kilitliyken (iOS -25308) veri bozuk değildir, temizlenmez.
class FlutterSecureStore implements SecureStore {
  FlutterSecureStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
            aOptions: AndroidOptions(
              encryptedSharedPreferences: true,
              resetOnError: true,
            ),
          );

  final FlutterSecureStorage _storage;

  /// iOS errSecInteractionNotAllowed: cihaz kilitliyken Keychain geçici olarak okunamaz.
  static const _iosDeviceLocked = -25308;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      AppLog.warn('Güvenli depo okunamadı ($key)', error: e);
      return null;
    }
  }

  @override
  Future<void> write(String key, String? value) async {
    try {
      if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    } catch (e) {
      AppLog.warn('Güvenli depoya yazılamadı ($key)', error: e);
    }
  }

  @override
  Future<void> delete(String key) => write(key, null);

  @override
  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      AppLog.warn('Güvenli depo temizlenemedi', error: e);
    }
  }

  @override
  Future<void> verifyReadable() async {
    try {
      await _storage.readAll();
    } on PlatformException catch (e) {
      if (e.details == _iosDeviceLocked ||
          (e.message ?? '').contains('$_iosDeviceLocked')) {
        return;
      }
      AppLog.warn('Güvenli depo okunamadı, temizleniyor', error: e);
      await deleteAll();
    } on MissingPluginException {
      // Test ortamı.
    } catch (e) {
      AppLog.warn('Güvenli depo okunamadı, temizleniyor', error: e);
      await deleteAll();
    }
  }
}

/// Bellek içi güvenli depo (testler ve önizleme).
class MemorySecureStore implements SecureStore {
  MemorySecureStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<void> deleteAll() async => values.clear();

  @override
  Future<void> verifyReadable() async {}
}
