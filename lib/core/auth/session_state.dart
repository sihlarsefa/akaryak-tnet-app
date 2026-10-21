import 'package:flutter/foundation.dart';

import '../models/auth_models.dart';
import '../models/me_access.dart';

/// Oturum durumu (spec C.4): bilinmiyor → oturum yok → açık(MeAccess) → kilitli.
@immutable
sealed class SessionState {
  const SessionState();

  /// Açık ya da kilitli oturumun erişim bilgisi.
  MeAccess? get access => null;
}

/// Açılışta, oturum geri yüklenirken (açılış ekranı).
final class SessionUnknown extends SessionState {
  const SessionUnknown();
}

/// Giriş gerekli. [message] giriş ekranında gösterilir ("Oturumunuz sona erdi" gibi).
final class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated({this.message});
  final String? message;
}

/// Oturum açık.
final class SessionAuthenticated extends SessionState {
  const SessionAuthenticated(this.me, {this.fromCache = false});
  final MeAccess me;

  /// Yetkiler önbellekten (çevrimdışı açılış); arka planda tazelenir.
  final bool fromCache;

  @override
  MeAccess get access => me;
}

/// Biyometrik kilit ekranı (oturum açık ama içerik gizli).
final class SessionLocked extends SessionState {
  const SessionLocked(this.me);
  final MeAccess me;

  @override
  MeAccess get access => me;
}

/// Giriş denemesinin sonucu.
@immutable
sealed class LoginOutcome {
  const LoginOutcome();
}

/// Giriş tamamlandı; kabuk açılır.
final class LoginSucceeded extends LoginOutcome {
  const LoginSucceeded(this.access);
  final MeAccess access;
}

/// Kod ekranı gerekli (2FA ya da telefonla giriş).
final class LoginNeedsCode extends LoginOutcome {
  const LoginNeedsCode(this.challenge);
  final OtpChallenge challenge;
}
