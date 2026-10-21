import '../../core/models/json.dart';
import '../../core/models/me_access.dart';
import '../../core/network/fake/core_fakes.dart';
import '../../core/network/fake/fake_auth.dart';
import '../../core/network/fake/fake_personas.dart';
import '../../core/network/fake/fake_server.dart';
import '../../core/utils/turkish_text.dart';
import '../../core/utils/validators.dart';

/// Sahte sunucunun kimlik durumu ve test / geliştirme anahtarları (sunucu örneği başına).
///
/// ```dart
/// AuthFakeControls.of(server).maintenance = true; // giriş ekranı "Bakımdayız"
/// ```
class AuthFakeControls {
  AuthFakeControls._();

  static final _byServer = Expando<AuthFakeControls>('authFakeControls');

  static AuthFakeControls of(FakeServer server) =>
      _byServer[server] ??= AuthFakeControls._();

  /// Hatalı şifre eşiği ve kilit süresi (Identity `MaxFailedAccessAttempts` = 5, 15 dk).
  int lockoutThreshold = 5;
  Duration lockoutDuration = const Duration(minutes: 15);

  /// `otp-send` sınırı: telefon başına 10 dakikada bu kadar kod.
  int otpSendsPerWindow = 3;
  Duration otpSendWindow = const Duration(minutes: 10);

  /// Yeni kod için bekleme (sunucu `ResendCooldownSeconds` = 60).
  Duration resendCooldown = const Duration(seconds: 60);

  /// `app/config`: bakım, sözleşme sürümü, eski API (404).
  bool maintenance = false;
  String? maintenanceMessage;
  String contractVersion = 'mobile-v1';
  bool configMissing = false;

  /// Saat (testler ezer).
  DateTime Function() now = () => DateTime.now().toUtc();

  /// Telefonu doğrulanmış personalar (`me/access.phoneVerified`).
  final Set<String> verifiedPhones = {};

  /// Sayaçlar (testler).
  int otpSends = 0;
  int resends = 0;
  int phoneVerifyStarts = 0;

  final Map<String, int> _failures = {};
  final Map<String, DateTime> _lockedUntil = {};
  final Map<String, List<DateTime>> _sendsByPhone = {};
  final Map<String, DateTime> _resendAt = {};
  final Map<String, String> _masked = {};

  /// Bir kullanıcı adının kilidini ve hatalı deneme sayısını sıfırlar.
  void unlock(String userName) {
    _failures.remove(userName.trim().asciiLower);
    _lockedUntil.remove(userName.trim().asciiLower);
  }
}

/// Kimlik sahte uçları (sahibi A1). Çekirdek sahtelerin (`core_fakes.dart`, M0a) üzerine:
/// - `auth/login`: 5 hatalı şifrede 15 dk kilit (429 `rate_limited` + `Retry-After`),
/// - `auth/otp/send`: telefon başına 10 dakikada 3 kod,
/// - `auth/challenge/resend`: 60 sn bekleme, yeni kod,
/// - `me/phone/verify-start` + `me/phone/verify`, `me/access.phoneVerified`,
/// - `app/config`: `maintenance`, `contractVersion`, `apiBuild` (+ eski API için 404).
/// Kod her zaman `123456`, şifre `demo` (çekirdek sahte kimlik).
void registerAuthFakes(FakeServer s) {
  final ctl = AuthFakeControls.of(s);

  JsonMap challengeJson(FakeChallenge c, String masked) {
    ctl._resendAt[c.id] = ctl.now().add(ctl.resendCooldown);
    ctl._masked[c.id] = masked;
    return {
      'challengeId': c.id,
      'maskedPhone': masked,
      'expiresInSeconds': 300,
      'resendInSeconds': ctl.resendCooldown.inSeconds,
    };
  }

  FakeResponse rateLimited(Duration wait, String message) {
    final secs = (wait.inMilliseconds / 1000).ceil().clamp(1, 1 << 30);
    return FakeResponse.problem(
      429,
      'rate_limited',
      message,
      headers: {'retry-after': '$secs'},
    );
  }

  String waitText(Duration d) {
    final secs = (d.inMilliseconds / 1000).ceil();
    return secs < 60 ? '$secs saniye' : '${(secs / 60).ceil()} dakika';
  }

  /// Telefon başına gönderim sınırı (otp/send, me/phone/verify-start).
  void takeSend(String phone) {
    final now = ctl.now();
    final list = ctl._sendsByPhone.putIfAbsent(phone, () => [])
      ..removeWhere((t) => now.difference(t) >= ctl.otpSendWindow);
    if (list.length >= ctl.otpSendsPerWindow) {
      final wait = list.isEmpty
          ? ctl.otpSendWindow
          : ctl.otpSendWindow - now.difference(list.first);
      throw rateLimited(
        wait,
        'Bu numara için çok fazla kod istendi. ${waitText(wait)} sonra tekrar deneyin.',
      );
    }
    list.add(now);
  }

  // ------------------------------------------------------------------ Şifreyle giriş
  s.post('auth/login', (req) {
    final r = req.json;
    final name = r.str('userNameOrEmail').trim().asciiLower;
    final now = ctl.now();
    final locked = ctl._lockedUntil[name];
    if (locked != null && locked.isAfter(now)) {
      final wait = locked.difference(now);
      throw rateLimited(
        wait,
        'Çok fazla hatalı deneme yapıldı. Güvenliğiniz için giriş ${waitText(wait)} kapatıldı; sonra tekrar deneyin.',
      );
    }
    final p = findFakePersona(name);
    if (p == null || r.str('password') != FakeAuth.password) {
      final n = (ctl._failures[name] ?? 0) + 1;
      if (n >= ctl.lockoutThreshold) {
        ctl._failures.remove(name);
        ctl._lockedUntil[name] = now.add(ctl.lockoutDuration);
        throw rateLimited(
          ctl.lockoutDuration,
          'Çok fazla hatalı deneme yapıldı. Güvenliğiniz için giriş ${waitText(ctl.lockoutDuration)} kapatıldı; sonra tekrar deneyin.',
        );
      }
      ctl._failures[name] = n;
      throw FakeResponse.problem(
        401,
        'unauthorized',
        'Kullanıcı adı veya şifre hatalı.',
      );
    }
    ctl.unlock(name);
    final device = r.map('device');
    final deviceId = JsonReader(device).str('deviceId', 'fake-device');
    if (p.requiresTwoFactor) {
      final c = s.auth.createChallenge(p, purpose: 1, deviceId: deviceId);
      return {
        'status': 'twoFactorRequired',
        'tokens': null,
        'challenge': challengeJson(c, p.phoneMasked),
      };
    }
    return {
      'status': 'ok',
      'tokens': s.auth.issueTokens(p, deviceId: deviceId, device: device),
      'challenge': null,
    };
  }, anonymous: true);

  // ------------------------------------------------------------------ Telefonla giriş
  s.post('auth/otp/send', (req) {
    final r = req.json;
    final phone = Validators.normalizePhone(r.str('phone'));
    if (phone == null) {
      throw FakeResponse.validation({
        'phone': ['Geçerli bir cep telefonu girin (5XX XXX XX XX).'],
      });
    }
    takeSend(phone);
    ctl.otpSends++;
    FakePersona? match;
    for (final p in fakePersonas) {
      if ('90${p.phone}' == phone && p.persona != Persona.platform) match = p;
    }
    final deviceId = JsonReader(r.map('device')).str('deviceId', 'fake-device');
    final c = s.auth.createChallenge(match, purpose: 2, deviceId: deviceId);
    // Eşleşme olmasa da aynı biçim (numara ifşa edilmez).
    final ten = phone.substring(2);
    return challengeJson(
      c,
      '0${ten.substring(0, 3)} *** ** ${ten.substring(8)}',
    );
  }, anonymous: true);

  // ------------------------------------------------------------------ Kodu yeniden gönder
  s.post('auth/challenge/resend', (req) {
    final id = req.json.str('challengeId');
    final c = s.auth.challenges[id];
    if (c == null || c.consumed) {
      throw FakeResponse.business(
        'Doğrulama süresi doldu. Girişe dönüp baştan başlayın.',
      );
    }
    final now = ctl.now();
    final at = ctl._resendAt[id];
    if (at != null && at.isAfter(now)) {
      final wait = at.difference(now);
      throw rateLimited(wait, 'Yeni kod için ${waitText(wait)} bekleyin.');
    }
    c.consumed = true;
    ctl.resends++;
    final p = c.personaKey == null ? null : findFakePersona(c.personaKey);
    final next = s.auth.createChallenge(
      p,
      purpose: c.purpose,
      deviceId: c.deviceId,
    );
    return challengeJson(next, ctl._masked[id] ?? p?.phoneMasked ?? '');
  }, anonymous: true);

  // ------------------------------------------------------------------ Telefon doğrulama
  s.post('me/phone/verify-start', (req) {
    final p = req.requireUser();
    takeSend('90${p.phone}');
    ctl.phoneVerifyStarts++;
    final c = s.auth.createChallenge(
      p,
      purpose: 3,
      deviceId: req.header('x-device-id') ?? 'fake-device',
    );
    return challengeJson(c, p.phoneMasked);
  });

  s.post('me/phone/verify', (req) {
    final p = req.requireUser();
    final id = req.json.str('challengeId');
    final c = s.auth.challenges[id];
    if (c == null || c.purpose != 3 || c.personaKey != p.key) {
      throw FakeResponse.business(
        'Doğrulama süresi doldu. Girişe dönüp baştan başlayın.',
      );
    }
    final result = s.auth.verify(id, req.json.str('code'));
    if (result.persona == null) {
      throw FakeResponse.business(result.error ?? 'Kod hatalı.');
    }
    ctl.verifiedPhones.add(p.key);
    return FakeResponse.noContent();
  });

  s.get('me/access', (req) {
    final p = req.requireUser();
    return {
      ...s.world.meAccess(p),
      'phoneVerified': ctl.verifiedPhones.contains(p.key),
    };
  });

  // ------------------------------------------------------------------ Uygulama ayarları
  s.get('app/config', (req) {
    if (ctl.configMissing) {
      throw FakeResponse.notFound('Sahte: app/config yok (eski API).');
    }
    return {
      ...fakeAppConfig(),
      'maintenance': {
        'active': ctl.maintenance,
        'message': ctl.maintenanceMessage,
      },
      'apiBuild': 'fake',
      'contractVersion': ctl.contractVersion,
    };
  }, anonymous: true);
}
