import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

import '../../../core/utils/log.dart';

/// Cihazın sunduğu doğrulama türü.
enum BiometricKind { face, fingerprint, iris, generic }

/// Doğrulama sonucu.
enum BiometricOutcome {
  success,

  /// Yüz / parmak izi tanınmadı.
  failed,

  /// Kullanıcı ya da sistem iptal etti (uygulama arka plana geçti, zaman aşımı).
  cancelled,

  /// Cihazda biyometri ya da ekran kilidi yok, donanım kullanılamıyor.
  unavailable,

  /// Çok fazla deneme: cihaz geçici olarak kilitledi.
  lockedOut,

  /// Beklenmeyen hata.
  error,
}

/// Cihazın uygulama kilidi için uygunluğu.
@immutable
class BiometricSupport {
  const BiometricSupport({required this.available, this.kind});

  static const none = BiometricSupport(available: false);

  /// Biyometri ya da cihaz şifresiyle doğrulama yapılabilir.
  final bool available;

  /// Kayıtlı biyometri türü; yalnızca cihaz şifresi varsa null.
  final BiometricKind? kind;
}

/// Biyometrik doğrulama (kilit ekranı, Profil'deki kilit anahtarı). Testler sahtesiyle ezer
/// (`biometricAuthenticatorProvider`); gerçek uygulama `local_auth` kullanır.
abstract class BiometricAuthenticator {
  Future<BiometricSupport> support();

  /// [reason] işletim sistemi penceresinde gösterilir. Hata fırlatmaz.
  Future<BiometricOutcome> authenticate(String reason);
}

/// `local_auth` 3.x ile doğrulama. Cihaz şifresine düşmeye izin verilir (`biometricOnly: false`): yüz
/// tanınmazsa işletim sistemi şifre sorar; uygulama içi son çare "Şifreyle giriş yap"tır.
class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  LocalAuthBiometricAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<BiometricSupport> support() async {
    try {
      if (!await _auth.isDeviceSupported()) return BiometricSupport.none;
      final types = await _auth.getAvailableBiometrics();
      return BiometricSupport(available: true, kind: kindOf(types));
    } catch (e) {
      AppLog.debug('Biyometri bilgisi okunamadı: ${e.runtimeType}');
      return BiometricSupport.none;
    }
  }

  @override
  Future<BiometricOutcome> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
        authMessages: turkishAuthMessages,
      );
      return ok ? BiometricOutcome.success : BiometricOutcome.failed;
    } on LocalAuthException catch (e) {
      return outcomeOf(e.code);
    } on PlatformException catch (e) {
      AppLog.debug('Biyometrik doğrulama: ${e.code}');
      return BiometricOutcome.unavailable;
    } on MissingPluginException {
      return BiometricOutcome.unavailable;
    } catch (e) {
      AppLog.debug('Biyometrik doğrulama hatası: ${e.runtimeType}');
      return BiometricOutcome.error;
    }
  }

  /// İşletim sistemi penceresinin Türkçe metinleri (Android başlık/ipucu/vazgeç, iOS vazgeç ve cihaz
  /// şifresine geçiş). Varsayılanlar İngilizcedir.
  static const turkishAuthMessages = <AuthMessages>[
    AndroidAuthMessages(
      signInTitle: 'AkaryakıtNet kilidini açın',
      signInHint: 'Kimliğinizi doğrulayın',
      cancelButton: 'Vazgeç',
    ),
    IOSAuthMessages(
      cancelButton: 'Vazgeç',
      localizedFallbackTitle: 'Cihaz şifresini kullan',
    ),
  ];

  /// Kayıtlı türlerden kullanıcıya söylenecek olan.
  static BiometricKind? kindOf(List<BiometricType> types) {
    if (types.contains(BiometricType.face)) return BiometricKind.face;
    if (types.contains(BiometricType.fingerprint)) {
      return BiometricKind.fingerprint;
    }
    if (types.contains(BiometricType.iris)) return BiometricKind.iris;
    if (types.isNotEmpty) return BiometricKind.generic;
    return null;
  }

  static BiometricOutcome outcomeOf(LocalAuthExceptionCode code) =>
      switch (code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.userRequestedFallback ||
        LocalAuthExceptionCode.authInProgress => BiometricOutcome.cancelled,
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable ||
        LocalAuthExceptionCode.uiUnavailable => BiometricOutcome.unavailable,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout => BiometricOutcome.lockedOut,
        _ => BiometricOutcome.error,
      };
}

final biometricAuthenticatorProvider = Provider<BiometricAuthenticator>(
  (ref) => LocalAuthBiometricAuthenticator(),
);

/// Cihazın uygunluğu (kilit ekranı düğmesi ve öneri sayfası).
final biometricSupportProvider = FutureProvider.autoDispose<BiometricSupport>(
  (ref) => ref.watch(biometricAuthenticatorProvider).support(),
);

/// Kullanıcıya söylenen yöntem adı: iOS'ta "Face ID" / "Touch ID", Android'de "yüz tanıma" /
/// "parmak izi"; tür bilinmiyorsa genel ad.
String biometricMethodName(BiometricKind? kind, {TargetPlatform? platform}) {
  final ios = (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;
  return switch (kind) {
    BiometricKind.face => ios ? 'Face ID' : 'Yüz tanıma',
    BiometricKind.fingerprint => ios ? 'Touch ID' : 'Parmak izi',
    BiometricKind.iris => 'İris tanıma',
    BiometricKind.generic => 'Biyometrik doğrulama',
    null => 'Cihaz şifresi',
  };
}

/// Cümle içi yöntem: "Uygulamayı Face ID ile kilitleyin".
String biometricPhrase(BiometricKind? kind, {TargetPlatform? platform}) {
  final ios = (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;
  return switch (kind) {
    BiometricKind.face => ios ? 'Face ID ile' : 'yüz tanımayla',
    BiometricKind.fingerprint => ios ? 'Touch ID ile' : 'parmak izinizle',
    BiometricKind.iris => 'iris tanımayla',
    BiometricKind.generic => 'biyometrik doğrulamayla',
    null => 'cihaz şifrenizle',
  };
}

/// Kilit ekranındaki ana düğmenin etiketi.
String unlockLabel(BiometricKind? kind, {TargetPlatform? platform}) {
  final ios = (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;
  return switch (kind) {
    BiometricKind.face => ios ? 'Face ID ile aç' : 'Yüz tanımayla aç',
    BiometricKind.fingerprint => ios ? 'Touch ID ile aç' : 'Parmak iziyle aç',
    BiometricKind.iris => 'İris tanımayla aç',
    BiometricKind.generic || null => 'Kilidi aç',
  };
}

IconData biometricIcon(BiometricKind? kind) => switch (kind) {
  BiometricKind.face => Icons.face_rounded,
  BiometricKind.fingerprint => Icons.fingerprint_rounded,
  BiometricKind.iris => Icons.remove_red_eye_outlined,
  BiometricKind.generic || null => Icons.lock_open_rounded,
};
