import 'dart:async';

import '../../../core/auth/permissions.dart';
import '../../../core/models/json.dart';
import '../../../core/models/me_access.dart';
import '../../../core/network/fake/fake_personas.dart';
import '../../../core/network/fake/fake_server.dart';
import '../../../core/network/fake/fake_world.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import 'seed.dart';

/// Bayi sahtelerinin ortak yardımcıları. Kurallar sunucuyla aynıdır (spec B.7 / B.10): bayi kapsamı
/// kullanıcının bayisidir, sayfa yetkileri `FakePersona.can`, şoför kapsamı `shipment.ownOnly`.

/// Çağıran bayi personeli (değilse 403). Ek veriler (bayi.* torbaları) ilk istekte tohumlanır.
FakePersona bayiUser(FakeRequest req) {
  final p = req.requireUser();
  if (p.persona != Persona.bayi || p.stationId == null) {
    throw FakeResponse.forbidden();
  }
  ensureBayiSeed(req.world);
  return p;
}

/// Sayfa yetkisi yoksa 403 (sunucunun PermissionAuthorize kuralı).
void requireAny(FakePersona p, List<(String, String)> grants) {
  if (!grants.any((g) => p.can(g.$1, g.$2))) throw FakeResponse.forbidden();
}

/// `shipment.ownOnly` (şoför).
bool isOwnOnly(FakePersona p) =>
    p.persona == Persona.bayi &&
    p.capabilities.containsKey(Caps.shipmentOwnOnly);

bool isFieldSales(FakePersona p) => p.roles.contains(Roles.fieldSales);

/// Rol şablonunun bir sayfadaki harfleri (me/access'in döndürmediği sayfalar için: StationSettings).
bool templateCan(FakePersona p, String page, [String letter = 'G']) {
  for (final code in p.bayiRoleCodes) {
    final letters = FakeRoleTemplates.pages[code]?[page];
    if (letters == null) continue;
    if (letters == 'T' || letters.contains(letter)) return true;
  }
  return false;
}

/// Sipariş süre dolumu açık mı (sahte ayar; testler kapatabilir).
bool expiryEnabled(FakeWorld w) =>
    w.bag<Map<String, Object>>(
      BayiBags.settings,
      () => {'expiryEnabled': true},
    )['expiryEnabled'] ==
    true;

void setExpiryEnabled(FakeWorld w, bool enabled) => w.bag<Map<String, Object>>(
  BayiBags.settings,
  () => {'expiryEnabled': true},
)['expiryEnabled'] = enabled;

// ------------------------------------------------------------------ Zaman

/// Dünyadaki ofsetsiz Türkiye yerel değer → an.
DateTime? local(Object? v) => TrTime.parseLocal(v as String?);

/// Yeni DTO tarihi: Türkiye yerel `+03:00`.
String? offset(DateTime? instant) =>
    instant == null ? null : TrTime.isoOffset(instant);

/// Eski DTO tarihi: ofsetsiz Türkiye yerel.
String? legacy(DateTime? instant) =>
    instant == null ? null : TrTime.isoLocal(instant);

/// UTC (`Z`).
String? utc(DateTime? instant) => instant?.toUtc().toIso8601String();

// ------------------------------------------------------------------ Sorgu

/// Virgüllü ya da tekrarlanan anahtar (`statuses=1,2` ya da `statuses=1&statuses=2`).
List<String> queryList(FakeRequest req, String key) => [
  for (final v in req.queryAll(key))
    for (final part in v.split(','))
      if (part.trim().isNotEmpty) part.trim(),
];

Set<int> queryInts(FakeRequest req, String key) => {
  for (final v in queryList(req, key))
    if (int.tryParse(v) != null) int.parse(v),
};

/// `yyyy-MM-dd` → o günün Türkiye gece yarısı.
DateTime? queryDate(FakeRequest req, String key) =>
    TrTime.parseDate(req.query(key));

/// Türkçe duyarsız "içerir".
bool textContains(Object? haystack, String q) {
  if (q.isEmpty) return true;
  final h = _fold('${haystack ?? ''}');
  return h.contains(_fold(q));
}

String _fold(String s) {
  const map = {
    'İ': 'i', 'I': 'ı', 'Ç': 'c', 'ç': 'c', 'Ğ': 'g', 'ğ': 'g', 'ı': 'i', //
    'Ö': 'o', 'ö': 'o', 'Ş': 's', 'ş': 's', 'Ü': 'u', 'ü': 'u',
  };
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    b.write(map[ch] ?? ch.asciiLower);
  }
  return b.toString();
}

/// Sayfalı `PagedResult` (`page`, `pageSize` ≤ [maxPageSize]).
JsonMap paged(FakeRequest req, List<Object?> all, {int maxPageSize = 100}) {
  final page = (req.queryInt('page') ?? 1).clamp(1, 1 << 20);
  final size = (req.queryInt('pageSize') ?? 25).clamp(1, maxPageSize);
  final start = (page - 1) * size;
  final items = start >= all.length
      ? const <Object?>[]
      : all.sublist(start, (start + size).clamp(0, all.length));
  return {
    'items': items,
    'totalCount': all.length,
    'pageNumber': page,
    'pageSize': size,
    'totalPages': (all.length / size).ceil(),
  };
}

// ------------------------------------------------------------------ Paylaşılan uçlar

/// Paylaşılan (çok personalı) bir uç: başka bir özellik aynı yolu kaydetmediyse kaydeder. Kayıt,
/// tüm özellikler kaydolduktan sonra (bir mikro görevde) yapılır; böylece kayıt sırası önemli olmaz ve
/// başka bir özelliğin aynı uca yazdığı işleyici ezilmez. Bayi sürümü bayi + müşteri personalarını
/// sözleşmeye uygun yanıtlar.
void registerSharedIfAbsent(
  FakeServer s, {
  required String method,
  required String pattern,
  required String probePath,
  required FakeHandler handler,
}) {
  scheduleMicrotask(() async {
    try {
      final r = await s.handle(
        method: method,
        path: probePath,
        uri: Uri.parse('https://fake.akaryakitnet.local/api/v1/$probePath'),
      );
      // Oturumsuz deneme: kayıtlı uç 401 döner, kayıtsız uç 404.
      if (r.status == 404) s.on(method, pattern, handler);
    } catch (_) {
      s.on(method, pattern, handler);
    }
  });
}

// ------------------------------------------------------------------ Bildirim

/// Sahte bildirim (actor hiçbir zaman kendi işlemiyle bildirim almaz).
void notify(
  FakeWorld w, {
  required Iterable<String> userIds,
  required String actorId,
  required String category,
  required String eventCode,
  required String title,
  required String body,
  required String route,
  int severity = 0,
  String? entityType,
  int? entityId,
}) {
  for (final u in userIds.toSet()) {
    if (u == actorId) continue;
    w.addNotification(
      userId: u,
      category: category,
      eventCode: eventCode,
      title: title,
      body: body,
      route: route,
      severity: severity,
      entityType: entityType,
      entityId: entityId,
    );
  }
}

/// Bayinin şu yetkiye sahip personeli (şoför hariç).
List<String> stationUsersWith(int stationId, String page, String perm) => [
  for (final p in fakePersonas)
    if (p.stationId == stationId &&
        p.persona == Persona.bayi &&
        !isOwnOnly(p) &&
        p.can(page, perm))
      p.userId,
];

/// Carinin müşteri kullanıcıları (bu yetkiyle).
List<String> customerUsersWith(int customerId, String page) => [
  for (final p in fakePersonas)
    if (p.customerId == customerId && p.can(page)) p.userId,
];
