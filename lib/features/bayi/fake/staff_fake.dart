import '../../../core/auth/permissions.dart';
import '../../../core/models/json.dart';
import '../../../core/network/fake/fake_server.dart';
import '../../../core/network/fake/fake_world.dart';
import 'fake_support.dart';
import 'seed.dart';

/// Ekip: `stations/me/staff` (+ aktif / pasif, şifre bağlantısı).
void registerBayiStaffFakes(FakeServer s) {
  s.get('stations/me/staff', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationStaff, Perm.view)]);
    return [
      for (final r in stationStaff(req.world, p.stationId!)) _dto(req.world, r),
    ];
  });

  s.post('stations/me/staff/{userId}/active', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationStaff, Perm.edit)]);
    final w = req.world;
    final userId = req.params['userId']!;
    final row = _find(w, p.stationId!, userId);
    final active = req.json.boolean('isActive');
    if (!active && userId == p.userId) {
      throw FakeResponse.business('Kendi hesabınızı pasifleştiremezsiniz.');
    }
    if (!active && userId == 'u-sahip') {
      throw FakeResponse.business('Bayi sahibi pasifleştirilemez.');
    }
    w.bag<Map<String, bool>>(
      BayiBags.staff,
      () => {},
    )[row['userId'] as String] = active;
    return {
      'message': active
          ? 'Personel aktifleştirildi.'
          : 'Personel pasifleştirildi.',
    };
  });

  s.post('stations/me/staff/{userId}/send-password-reset', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationStaff, Perm.edit)]);
    final w = req.world;
    final row = _find(w, p.stationId!, req.params['userId']!);
    if (row['isActive'] != true) {
      throw FakeResponse.business(
        'Pasif personele şifre bağlantısı gönderilemez.',
      );
    }
    w
        .bag<List<String>>(BayiBags.passwordResets, () => [])
        .add(row['userId'] as String);
    return {'message': 'Şifre belirleme bağlantısı gönderildi.'};
  });
}

JsonMap _find(FakeWorld w, int stationId, String userId) {
  for (final r in stationStaff(w, stationId)) {
    if (r['userId'] == userId) return r;
  }
  throw FakeResponse.notFound('Personel bulunamadı.');
}

/// `StationStaffDto` (sunucunun aynası). Roller v5: rol adı panelin etiketi (pasif şablonda "(pasif)"),
/// `isRetired`; görüntüleyici ataması geçişte "otomatik taşındı" işaretlidir (`isMigrated`; yerine geçen
/// rol yok) ve personel "İncelenecek" görünür (`needsReview`); birim onaycısında `approverOf`.
JsonMap _dto(FakeWorld w, JsonMap r) {
  final codes = (r['roleCodes'] as List).cast<String>();
  final hours = r['lastLoginHoursAgo'] as int?;
  final now = DateTime.now().toUtc();
  bool retired(String code) => BayiRoleCodes.isPassive(code);
  // Geçişte işaretlenen atama: görüntüleyici (yerine geçen yok; kişi rolünde kalır).
  bool migrated(String code) => w.v5Station && code == BayiRoleCodes.viewer;
  final review = codes.any((c) => migrated(c) && retired(c));
  final persona = w.personaByUserId(r['userId'] as String?);
  return {
    'userId': r['userId'],
    'displayName': r['displayName'],
    'email': r['email'],
    'phoneNumber': r['phoneNumber'],
    'isActive': r['isActive'],
    'isFieldSales': r['isFieldSales'],
    'permissionGroupId': null,
    'permissionGroupName': null,
    'salesRepresentativeId': r['isFieldSales'] == true ? 31 : null,
    'portfolioCount': r['isFieldSales'] == true ? 2 : 0,
    'createdAt': now.subtract(const Duration(days: 180)).toIso8601String(),
    'lastLoginAt': hours == null
        ? null
        : now.subtract(Duration(hours: hours)).toIso8601String(),
    'bayiRoles': [
      for (var i = 0; i < codes.length; i++)
        {
          'userId': r['userId'],
          'stationId': 1,
          // Şablonsuz özel rol `role:{Id}` kodunu taşır: adı bayinin verdiği addır, şablon kodu yoktur.
          'roleId':
              _customRoleId(codes[i]) ??
              100 + BayiRoleCodes.all.indexOf(codes[i]),
          'roleName': _customRoleId(codes[i]) != null
              ? (persona?.bayiRoleNames.elementAtOrNull(i) ?? codes[i])
              : BayiRoleCodes.label(
                  BayiRoleCodes.name(codes[i]),
                  passive: retired(codes[i]),
                ),
          'templateCode': _customRoleId(codes[i]) != null ? null : codes[i],
          'isMigrated': migrated(codes[i]),
          'assignedAt': now
              .subtract(const Duration(days: 90))
              .toIso8601String(),
          'roleIsActive': true,
          'userIsActive': r['isActive'],
          'isRetired': retired(codes[i]),
          'needsReview': migrated(codes[i]) && retired(codes[i]),
        },
    ],
    'hasBayiRoles': codes.isNotEmpty,
    'hasMigratedRoles': codes.any(migrated),
    'approverOf': persona == null
        ? const <String>[]
        : w.approverUnitsOf(persona),
    'needsReview': review,
  };
}

/// Şablonsuz özel rolün kimliği (`role:42` → 42); şablon kodunda null.
int? _customRoleId(String code) =>
    code.startsWith('role:') ? int.tryParse(code.substring(5)) : null;

/// Testler: şifre bağlantısı gönderilen kullanıcılar.
List<String> fakePasswordResets(FakeWorld w) =>
    w.bag<List<String>>(BayiBags.passwordResets, () => []);
