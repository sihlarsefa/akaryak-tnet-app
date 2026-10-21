import '../../models/json.dart';
import 'fake_personas.dart';
import 'fake_server.dart';

/// Sahte erişim belirteci kaydı.
class FakeAccess {
  FakeAccess(this.personaKey, this.deviceId, this.expiresAt);
  final String personaKey;
  final String deviceId;
  DateTime expiresAt;
  bool revoked = false;

  bool get expired => DateTime.now().toUtc().isAfter(expiresAt);
}

class _FakeRefresh {
  _FakeRefresh(this.personaKey, this.deviceId);
  final String personaKey;
  final String deviceId;
  bool revoked = false;
}

/// SMS kodu (2FA ya da telefonla giriş). Sahte kipte kod her zaman `123456`.
class FakeChallenge {
  FakeChallenge({
    required this.id,
    required this.personaKey,
    required this.purpose,
    required this.deviceId,
  });
  final String id;

  /// Telefon eşleşmediyse null (yanıt yine aynı biçimde döner, SMS gitmez).
  final String? personaKey;

  /// 1 TwoFactor, 2 OtpLogin.
  final int purpose;
  final String deviceId;
  final DateTime expiresAt = DateTime.now().toUtc().add(
    const Duration(minutes: 5),
  );
  int attempts = 0;
  bool consumed = false;
}

/// Cihaz oturumu (Profil → Oturumlar).
class FakeDeviceSession {
  FakeDeviceSession({
    required this.deviceId,
    required this.platform,
    this.model,
    this.appVersion,
  });
  final String deviceId;
  final String platform;
  final String? model;
  final String? appVersion;
  DateTime lastSeenAt = DateTime.now().toUtc();
  String? pushToken;
  bool pushEnabled = true;
  bool revoked = false;
}

/// Sahte kimlik doğrulama durumu: belirteçler, yenileme, SMS kodları, cihaz oturumları.
class FakeAuth {
  FakeAuth(this.server);

  final FakeServer server;

  /// Sahte kipte geçerli şifre ve SMS kodu.
  static const password = 'demo';
  static const code = '123456';

  /// Sahte kipte değiştirilen şifreler (persona → yeni şifre; QA SC-04). `demo` her zaman geçer,
  /// demo hesapları tek dokunuşla girişte çalışmaya devam eder.
  final Map<String, String> changedPasswords = {};

  /// [personaKey] için [value] geçerli şifre mi (`demo` ya da değiştirilmiş şifre).
  bool acceptsPassword(String personaKey, String value) =>
      value == password || changedPasswords[personaKey] == value;

  /// Erişim belirteci ömrü (gerçek: `Jwt:AccessTokenMinutes` = 15).
  Duration accessLifetime = const Duration(minutes: 15);

  final Map<String, FakeAccess> _access = {};
  final Map<String, _FakeRefresh> _refresh = {};
  final Map<String, FakeChallenge> challenges = {};

  /// persona → cihaz → oturum.
  final Map<String, Map<String, FakeDeviceSession>> sessions = {};
  int _n = 0;

  /// Yenileme çağrısı sayısı (testler: "aynı anda tek yenileme").
  int refreshCalls = 0;

  String _token(String prefix, String key) =>
      '$prefix.$key.${++_n}.${server.random.nextInt(1 << 30).toRadixString(36)}';

  FakeAccess? resolveAccess(String token) => _access[token];

  /// Yeni belirteç çifti (`AuthTokensDto`).
  JsonMap issueTokens(
    FakePersona p, {
    required String deviceId,
    JsonMap? device,
  }) {
    final access = _token('fa', p.key);
    final refresh = _token('fr', p.key);
    final expires = DateTime.now().toUtc().add(accessLifetime);
    _access[access] = FakeAccess(p.key, deviceId, expires);
    _refresh[refresh] = _FakeRefresh(p.key, deviceId);
    final r = JsonReader.of(device);
    final s = sessions.putIfAbsent(p.key, () => {});
    s[deviceId] = FakeDeviceSession(
      deviceId: deviceId,
      platform: r.str('platform', 'ios'),
      model: r.nonEmpty('model'),
      appVersion: r.nonEmpty('appVersion'),
    )..pushToken = r.nonEmpty('pushToken');
    return {
      'accessToken': access,
      'accessExpiresAt': expires.toIso8601String(),
      'refreshToken': refresh,
      'refreshExpiresAt': DateTime.now()
          .toUtc()
          .add(const Duration(days: 30))
          .toIso8601String(),
      'userId': p.userId,
      'displayName': p.displayName,
    };
  }

  /// Bu çalıştırmada döndürülmüş yenileme belirteçleri: aynı belirteç ikinci kez kullanılamaz.
  final Set<String> _spent = {};

  /// Yenileme: eski belirteç geçersizleşir (rotasyon). Geçersizse null.
  ///
  /// Demo uygulama kapatılıp açılınca sahte sunucu bellekten sıfırlanır ve önceki çalıştırmanın
  /// belirteci burada bulunmaz; biçimi doğruysa (`fr.<persona>.…`), bu çalıştırmada harcanmamışsa ve
  /// cihaz oturumu kapatılmamışsa oturum aynı personayla sürer ("Oturumunuz sona erdi" çıkmaz).
  JsonMap? rotate(String refreshToken, String deviceId) {
    refreshCalls++;
    var r = _refresh.remove(refreshToken);
    if (r == null) {
      final parts = refreshToken.split('.');
      if (_spent.contains(refreshToken) ||
          parts.length != 4 ||
          parts[0] != 'fr') {
        return null;
      }
      final restored = findFakePersona(parts[1]);
      if (restored == null ||
          (sessions[restored.key]?[deviceId]?.revoked ?? false)) {
        return null;
      }
      r = _FakeRefresh(restored.key, deviceId);
    }
    _spent.add(refreshToken);
    if (r.revoked) return null;
    final p = findFakePersona(r.personaKey);
    if (p == null) return null;
    final session = sessions[p.key]?[r.deviceId];
    if (session?.revoked ?? false) return null;
    final tokens = issueTokens(
      p,
      deviceId: r.deviceId,
      device: {
        'platform': session?.platform,
        'model': session?.model,
        'appVersion': session?.appVersion,
        'pushToken': session?.pushToken,
      },
    );
    return tokens;
  }

  /// `auth/revoke`: yenileme belirtecinin cihazını kapatır (yoksa hiçbir şey; her zaman 204).
  int revokeCalls = 0;

  void revokeByRefresh(String refreshToken, String deviceId) {
    revokeCalls++;
    final r = _refresh[refreshToken];
    if (r == null || r.deviceId != deviceId) return;
    revokeDevice(r.personaKey, r.deviceId);
  }

  FakeChallenge createChallenge(
    FakePersona? p, {
    required int purpose,
    required String deviceId,
  }) {
    final c = FakeChallenge(
      id: _token('ch', p?.key ?? 'none'),
      personaKey: p?.key,
      purpose: purpose,
      deviceId: deviceId,
    );
    challenges[c.id] = c;
    return c;
  }

  /// Kodu doğrular; başarılıysa persona, değilse Türkçe hata.
  ({FakePersona? persona, String? error}) verify(
    String challengeId,
    String input,
  ) {
    final c = challenges[challengeId];
    if (c == null || c.consumed) {
      return (persona: null, error: 'Kod geçersiz. Yeni kod isteyin.');
    }
    if (DateTime.now().toUtc().isAfter(c.expiresAt)) {
      return (persona: null, error: 'Kodun süresi doldu. Yeni kod isteyin.');
    }
    if (c.attempts >= 5) {
      return (
        persona: null,
        error: 'Çok fazla hatalı deneme. Yeni kod isteyin.',
      );
    }
    c.attempts++;
    if (input.trim() != code || c.personaKey == null) {
      return (persona: null, error: 'Kod hatalı. Tekrar deneyin.');
    }
    c.consumed = true;
    return (persona: findFakePersona(c.personaKey), error: null);
  }

  /// Bir cihazın oturumunu kapatır (belirteçleri geçersiz kılar).
  void revokeDevice(String personaKey, String deviceId) {
    sessions[personaKey]?[deviceId]?.revoked = true;
    for (final a in _access.values) {
      if (a.personaKey == personaKey && a.deviceId == deviceId) {
        a.revoked = true;
      }
    }
    _refresh.removeWhere(
      (_, r) => r.personaKey == personaKey && r.deviceId == deviceId,
    );
  }

  void revokeAll(String personaKey) {
    for (final d in sessions[personaKey]?.keys.toList() ?? const <String>[]) {
      revokeDevice(personaKey, d);
    }
  }

  /// Dev menüsü / testler: tüm erişim belirteçlerinin süresini doldurur (yenileme akışını dener).
  void expireAllAccessTokens() {
    final past = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    for (final a in _access.values) {
      a.expiresAt = past;
    }
  }
}
