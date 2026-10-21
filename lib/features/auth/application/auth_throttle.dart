import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_clock.dart';

/// Hangi giriş eyleminin beklemede olduğu.
enum ThrottleScope {
  /// Şifreyle giriş (hesap kilitlenmesi ya da `login` hız sınırı).
  password,

  /// Telefonla giriş kodu (`otp-send` hız sınırı).
  otp,

  /// Telefon doğrulama kodu (`me/phone/verify-start`).
  phoneVerify,
}

/// Sunucunun 429 ile istediği bekleme (spec B.2 `Retry-After`).
@immutable
class AuthHold {
  const AuthHold({
    required this.until,
    required this.wait,
    this.message,
    this.lockout = false,
  });

  /// Bu ana kadar eylem kapalı.
  final DateTime until;

  /// Sunucunun istediği toplam bekleme (bant metni).
  final Duration wait;

  /// Sunucunun Türkçe açıklaması (ör. "Güvenliğiniz için giriş 15 dakika kapatıldı").
  final String? message;

  /// Hesap kilitlenmesi (çok sayıda hatalı şifre) mi, yoksa yalnızca hız sınırı mı.
  final bool lockout;
}

/// Bekleyen eylemler. Ekran kapanıp açılsa da (kod ekranına gidip dönünce) geri sayım sürer; uygulama
/// yeniden açılınca sıfırlanır (sunucu yine uygular).
final authThrottleProvider =
    NotifierProvider<AuthThrottleController, Map<ThrottleScope, AuthHold>>(
      AuthThrottleController.new,
    );

class AuthThrottleController extends Notifier<Map<ThrottleScope, AuthHold>> {
  /// Sunucu süre vermezse.
  static const defaultWait = Duration(seconds: 60);

  @override
  Map<ThrottleScope, AuthHold> build() => const {};

  DateTime _now() => ref.read(authClockProvider)();

  /// [scope] eylemini [wait] kadar kapatır.
  void hold(
    ThrottleScope scope,
    Duration? wait, {
    String? message,
    bool lockout = false,
  }) {
    final w = wait == null || wait <= Duration.zero ? defaultWait : wait;
    state = {
      ...state,
      scope: AuthHold(
        until: _now().add(w),
        wait: w,
        message: message,
        lockout: lockout,
      ),
    };
  }

  void clear(ThrottleScope scope) {
    if (!state.containsKey(scope)) return;
    state = {...state}..remove(scope);
  }

  /// Süresi geçmemiş bekleme (yoksa null).
  AuthHold? active(ThrottleScope scope) {
    final h = state[scope];
    if (h == null) return null;
    return h.until.isAfter(_now()) ? h : null;
  }
}
