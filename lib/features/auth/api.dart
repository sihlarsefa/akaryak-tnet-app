/// Kimlik özelliği (sahibi A1). Diğer özellikler yalnızca bu dosyayı içe aktarır.
///
/// - Rotalar: `/login` (+ `/login/code`), `/update` (`?reason=`), `/locked`. Ayrı telefon doğrulaması
///   yok (2026-11): telefonla giriş hesapta kayıtlı numarayla çalışır.
/// - Profil (A8): [biometricAuthenticatorProvider] / [biometricSupportProvider] kilit anahtarının cihaz
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
export 'data/server_gate.dart' show ServerGate, ServerGateKind;
export 'presentation/widgets/server_status.dart' show UpdateReason;
