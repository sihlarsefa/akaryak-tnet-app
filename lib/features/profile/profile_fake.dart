import '../../core/models/json.dart';
import '../../core/models/me_access.dart';
import '../../core/network/fake/fake_auth.dart' show FakeDeviceSession;
import '../../core/network/fake/fake_personas.dart';
import '../../core/network/fake/fake_server.dart';
import '../../core/network/fake/fake_world.dart';
import '../../core/utils/validators.dart';

/// Profil sahte uçlarının anahtarları (sunucu örneği başına; testler).
class ProfileFakeControls {
  ProfileFakeControls._();

  static final _byServer = Expando<ProfileFakeControls>('profileFakeControls');

  static ProfileFakeControls of(FakeServer server) =>
      _byServer[server] ??= ProfileFakeControls._();

  /// Hesap silme talepleri (persona anahtarı → gerekçe).
  final Map<String, String?> deletionRequests = {};
  int passwordChanges = 0;
  int profileUpdates = 0;
}

/// Profil sahte uçları (sahibi A8). Çekirdek sahtelerin üzerine:
/// - `GET|PUT me/profile` (`UserProfileDto`; telefon değişince mevcut şifre ve oturumların kapanması),
/// - `POST me/change-password` (400'de `AccountOperationResult`; başarıda tüm oturumlar kapanır),
/// - `POST me/deletion-request {reason, password}` → 202 `{requestId, scheduledFor, message}` (şifre,
///   son şirket yöneticisi / bayi sahibi / merkez kuralları),
/// - `GET auth/sessions`: ilk istekte personaya ikinci bir cihaz (tablet) eklenir.
/// Sahte kipte şifre her zaman `demo`dur (değiştirilse de).
void registerProfileFakes(FakeServer s) {
  final ctl = ProfileFakeControls.of(s);

  Map<String, JsonMap> edits(FakeWorld w) =>
      w.bag<Map<String, JsonMap>>('profile.edits', () => {});

  JsonMap profileJson(FakeWorld w, FakePersona p) {
    final e = edits(w)[p.key] ?? const {};
    final org = p.persona == Persona.customer
        ? w.customerTitle(p.customerId)
        : w.stationTitle(p.stationId);
    final (role, label) = switch (p.persona) {
      Persona.customer => ('Customer', 'Müşteri'),
      Persona.platform => ('HeadOffice', 'Merkez'),
      _ =>
        p.roles.contains('FieldSales')
            ? ('FieldSales', 'Saha satış personeli')
            : ('Station', 'Bayi'),
    };
    return {
      'userId': p.userId,
      'userName': p.userName,
      'email': p.email,
      'displayName': e['displayName'] ?? p.displayName,
      'phoneNumber': e.containsKey('phoneNumber')
          ? e['phoneNumber']
          : '0${p.phone}',
      'role': role,
      'roleLabel': label,
      'organizationTitle': org,
      'organizationCode': null,
      'lastLoginAtUtc': DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 2))
          .toIso8601String(),
      'createdAtUtc': '2025-03-01T08:00:00Z',
      'emailConfirmed': true,
      'twoFactorRequired': p.requiresTwoFactor,
    };
  }

  FakeResponse failed(List<String> errors) => FakeResponse(400, {
    'succeeded': false,
    'errors': errors,
    'invalidToken': false,
  });

  JsonMap ok() => {
    'succeeded': true,
    'errors': <String>[],
    'invalidToken': false,
  };

  s.get('me/profile', (req) => profileJson(req.world, req.requireUser()));

  s.put('me/profile', (req) {
    final p = req.requireUser();
    final r = req.json;
    final name = r.str('displayName').trim();
    if (name.isEmpty) throw failed(['Ad soyad zorunludur.']);
    if (name.length > 150) {
      throw failed(['Ad soyad en fazla 150 karakter olabilir.']);
    }
    final rawPhone = r.nonEmpty('phoneNumber');
    final current = profileJson(req.world, p);
    String? digits(Object? v) =>
        v == null ? null : Validators.normalizePhone('$v');
    final changed = digits(rawPhone) != digits(current['phoneNumber']);
    if (changed) {
      if (rawPhone != null && Validators.normalizePhone(rawPhone) == null) {
        throw failed([
          'Cep telefonu 05xx xxx xx xx biçiminde, SMS alabilen bir Türkiye GSM numarası olmalıdır.',
        ]);
      }
      if (!s.auth.acceptsPassword(p.key, r.str('currentPassword'))) {
        throw failed([
          'Telefon numarasını değiştirmek için mevcut şifrenizi doğru girin.',
        ]);
      }
    }
    ctl.profileUpdates++;
    edits(req.world)[p.key] = {'displayName': name, 'phoneNumber': rawPhone};
    if (changed) s.auth.revokeAll(p.key);
    return ok();
  });

  s.post('me/change-password', (req) {
    final p = req.requireUser();
    final r = req.json;
    final current = r.str('currentPassword');
    final next = r.str('newPassword');
    if (current.isEmpty || next.isEmpty) {
      throw failed(['Mevcut ve yeni şifre zorunludur.']);
    }
    if (current == next) {
      throw failed(['Yeni şifre mevcut şifreden farklı olmalıdır.']);
    }
    if (!s.auth.acceptsPassword(p.key, current)) {
      throw failed(['Mevcut şifre hatalı.']);
    }
    final errors = [
      if (next.length < 8) 'Şifre en az 8 karakter olmalıdır.',
      if (!RegExp(r'\d').hasMatch(next)) 'Şifre en az bir rakam içermelidir.',
      if (!RegExp(r'[a-zçğıöşü]').hasMatch(next))
        'Şifre en az bir küçük harf içermelidir.',
      if (!RegExp(r'[A-ZÇĞİÖŞÜ]').hasMatch(next))
        'Şifre en az bir büyük harf içermelidir.',
    ];
    if (errors.isNotEmpty) throw failed(errors);
    ctl.passwordChanges++;
    // QA SC-04: yeni şifreyle giriş de kabul edilir (`demo` geçerli kalır).
    s.auth.changedPasswords[p.key] = next;
    // Sunucu güvenlik damgasını yeniler: tüm mobil oturumlar kapanır.
    s.auth.revokeAll(p.key);
    return ok();
  });

  s.post('me/deletion-request', (req) {
    final p = req.requireUser();
    final r = req.json;
    if (!s.auth.acceptsPassword(p.key, r.str('password'))) {
      throw FakeResponse.validation({
        'password': ['Şifre hatalı.'],
      }, 'Şifre hatalı.');
    }
    if (p.persona == Persona.platform) {
      throw FakeResponse.business(
        'Merkez hesapları uygulamadan silinemez; merkez yöneticinize başvurun.',
      );
    }
    // Bayinin ana hesabı (`Station.UserId`; sunucu rol koduna değil hesaba bakar): roller v5'te Bayi
    // yöneticisi rolü başka personele de verilebilir, onların hesabı silinebilir.
    if (p.persona == Persona.bayi && p.key == 'sahip') {
      throw FakeResponse.business(
        'Bayi sahibi hesabı uygulamadan silinemez. Bayi kaydınızın kapatılması için merkezle görüşün.',
      );
    }
    if (p.persona == Persona.customer && (p.customerUserRole ?? 3) == 3) {
      final others = fakePersonas.where(
        (x) =>
            x.key != p.key &&
            x.customerId == p.customerId &&
            (x.customerUserRole ?? 3) == 3 &&
            !ctl.deletionRequests.containsKey(x.key),
      );
      if (others.isEmpty) {
        throw FakeResponse.business(
          'Şirketinizin tek yöneticisi sizsiniz. Hesabınızı silmeden önce başka bir kullanıcıyı Yönetici yapın.',
        );
      }
    }
    ctl.deletionRequests[p.key] = r.nonEmpty('reason');
    s.auth.revokeAll(p.key);
    final n = req.world.nextId('deletion', start: 4100000001);
    return FakeResponse.accepted({
      'requestId': 'SIL-$n',
      'scheduledFor': DateTime.now()
          .toUtc()
          .add(const Duration(days: 14))
          .toIso8601String(),
      'message':
          'Hesabınız kapatıldı. Kişisel verileriniz en geç 30 gün içinde silinecek.',
    });
  });

  s.get('auth/sessions', (req) {
    final p = req.requireUser();
    final seeded = req.world.bag<Set<String>>(
      'profile.sessionsSeeded',
      () => {},
    );
    final devices = s.auth.sessions.putIfAbsent(p.key, () => {});
    if (seeded.add(p.key)) {
      devices.putIfAbsent(
        'fake-tablet-${p.key}',
        () =>
            FakeDeviceSession(
                deviceId: 'fake-tablet-${p.key}',
                platform: 'android',
                model: 'Samsung Galaxy Tab S9',
                appVersion: '1.0.0',
              )
              ..lastSeenAt = DateTime.now().toUtc().subtract(
                const Duration(days: 2),
              ),
      );
    }
    final current = req.header('x-device-id');
    return [
      for (final d in devices.values.where((d) => !d.revoked))
        {
          'deviceId': d.deviceId,
          'platform': d.platform,
          'model': d.model,
          'appVersion': d.appVersion,
          'lastSeenAt': d.lastSeenAt.toIso8601String(),
          'current': d.deviceId == current,
        },
    ];
  });
}
