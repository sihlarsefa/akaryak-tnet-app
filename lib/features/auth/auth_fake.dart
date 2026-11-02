import '../../core/models/json.dart';
import '../../core/network/fake/core_fakes.dart';
import '../../core/network/fake/fake_auth.dart';
import '../../core/network/fake/fake_personas.dart';
import '../../core/network/fake/fake_phones.dart';
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

  /// Sayaçlar (testler).
  int otpSends = 0;
  int resends = 0;

  /// Telefonla giriş kodunun SMS ile gittiği personalar (gönderim sırasıyla; testler). Numara uygun bir
  /// hesapta değilse ya da birden çok uygun hesapta ise SMS gitmez, liste büyümez.
  final List<String> otpSmsTo = [];

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
/// - `auth/otp/send`: telefon başına 10 dakikada 3 kod; kod hesabında bu numara kayıtlı uygun hesaba
///   gider ([FakePhones]: merkez, demo / tohum ve pasif hesap hariç; numara iki uygun hesaptaysa SMS
///   gitmez). Ayrı telefon doğrulaması yok (2026-11; `me/phone/verify*` uçları kaldırıldı),
/// - `auth/challenge/resend`: 60 sn bekleme, yeni kod,
/// - `me/access`: `phoneMasked` hesaptaki numaradan; `phoneVerified` = geçerli bir cep numarası kayıtlı
///   (yalnızca eski sürümler için),
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

  /// Telefon başına gönderim sınırı (otp/send).
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
    if (p == null || !s.auth.acceptsPassword(p.key, r.str('password'))) {
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
    final match = FakePhones.otpTarget(s.world, phone);
    if (match != null) ctl.otpSmsTo.add(match.key);
    final deviceId = JsonReader(r.map('device')).str('deviceId', 'fake-device');
    final c = s.auth.createChallenge(match, purpose: 2, deviceId: deviceId);
    // Eşleşme olmasa da aynı biçim (numara ifşa edilmez).
    return challengeJson(c, FakePhones.mask(phone));
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

  // ------------------------------------------------------------------ Erişim
  s.get('me/access', (req) {
    final p = req.requireUser();
    final phone = FakePhones.of(req.world, p);
    return {
      ...s.world.meAccess(p),
      'phoneMasked': phone == null ? null : FakePhones.mask(phone),
      // Sunucu 2026-11: "geçerli bir cep numarası kayıtlı" (ayrı doğrulama yok; eski sürümler için).
      'phoneVerified': phone != null,
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
