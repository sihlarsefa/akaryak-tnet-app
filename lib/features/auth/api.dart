/// Kimlik özelliği (sahibi A1). Diğer özellikler yalnızca bu dosyayı içe aktarır.
///
/// - Rotalar: `/login` (+ `/login/code`), `/update` (`?reason=`), `/locked`, `/profile/phone`.
/// - Profil (A8): `context.push(AuthRoutes.phone)` ile telefon doğrulama; [phoneStatusProvider] doğrulama
///   durumunu, [biometricAuthenticatorProvider] / [biometricSupportProvider] kilit anahtarının cihaz
///   uygunluğunu ve doğrulamasını verir.
/// - Kabuk (A-INT): girişten sonra [maybeShowOptionalUpdate]; bakım / uyumsuz sunucu için
///   `AuthRoutes.update(UpdateReason.maintenance)`.
library;

export 'application/biometric.dart'
    show
        BiometricAuthenticator,
        BiometricKind,
        BiometricOutcome,
        BiometricSupport,
        biometricAuthenticatorProvider,
        biometricIcon,
        biometricMethodName,
        biometricPhrase,
        biometricSupportProvider,
        unlockLabel;
export 'application/update_prompt.dart'
    show maybeShowOptionalUpdate, openStore, storeUriFor;
export 'auth_routes.dart' show AuthRoutes, authRoutes;
export 'data/auth_api.dart' show PhoneStatus;
export 'data/server_gate.dart' show ServerGate, ServerGateKind;
export 'presentation/phone_verification_page.dart' show phoneStatusProvider;
export 'presentation/widgets/server_status.dart' show UpdateReason;
