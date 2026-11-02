import 'dart:async';

import 'package:flutter/foundation.dart';

import '../offline/cache_store.dart';
import '../utils/log.dart';
import '../utils/turkish_text.dart';

/// Önbellekten okunan bir GET yanıtı (ham JSON ya da çözülmüş model).
@immutable
class CachedResponse<T> {
  const CachedResponse(this.value, {required this.storedAt});

  final T value;

  /// Yanıtın alındığı an (UTC): "Son güncelleme" ve tazelik kararı.
  final DateTime storedAt;

  Duration get age => DateTime.now().toUtc().difference(storedAt);
}

/// GET yanıt önbelleği (önce önbellek, sonra sunucu; spec C.4a "çevrimdışı açılış").
///
/// - **Kullanıcıya özel**: anahtar `<userId>:http.<kip>.v1|<yol>?<sıralı sorgu>`; çıkışta ve kullanıcı
///   değişince `CacheStore.clearUser` / `clearSessionData` siler. Kullanıcısız (anonim) yanıt yazılmaz.
/// - **Kip ayrı**: demo oturumu (sahte dünya) `demo`, canlı API `live` kipinde yazar; iki dünya aynı
///   kaydı hiçbir koşulda paylaşmaz (demo kullanıcı kimlikleri de ayrıdır).
/// - **Yazma geçersiz kılar**: başarılı her POST / PUT / DELETE, etkilediği yol ailelerinin kayıtlarını
///   hemen siler ([WriteInvalidation]); yazmadan önce başlamış bir okumanın geç gelen yanıtı da
///   önbelleğe yazılmaz (eski veri geri gelmez).
/// - Yalnızca çağıranın istediği yanıtlar yazılır (`ApiClient.get(cache: true)`): ilk sayfalar,
///   varsayılan süzgeçler, ayrıntılar. Arama sorguları yazılmaz.
/// - **Birikmez**: süresi geçmiş kayıtlar (bir kez açılıp bir daha okunmayan ayrıntılar) kullanıcının
///   yazmalarında en çok [purgeEvery]'de bir silinir.
class ResponseCache {
  ResponseCache({
    required CacheStore store,
    required this.mode,
    required String? Function() userId,
    this.maxAge = const Duration(days: 3),
    this.purgeEvery = const Duration(hours: 6),
  }) : _store = store,
       _userId = userId;

  /// `live` ya da `demo`.
  final String mode;

  /// Bundan eski kayıt gösterilmez (silinir).
  final Duration maxAge;

  /// Süresi geçmiş kayıtların silinme sıklığı (kullanıcı başına).
  final Duration purgeEvery;

  final CacheStore _store;
  final String? Function() _userId;

  String? _purgedFor;
  DateTime? _purgedAt;

  /// Yakın zamandaki geçersiz kılmalar: bu andan önce başlamış okuma bu önekleri yazamaz.
  final List<({String prefix, DateTime at})> _invalidated = [];

  static const _version = 'v1';

  /// Etkin ortamın kipi.
  static String modeOf({required bool fake}) => fake ? 'demo' : 'live';

  /// Oturumdaki kullanıcı (belirteç deposundan; yoksa null).
  String? get currentUser => _userId();

  String _scope(String uid) => CacheKeys.user(uid, 'http.$mode.$_version|');

  /// Önbellek anahtarı (sorgu anahtarları sıralı; liste değerleri tekrarlı).
  String keyFor(String uid, String path, Map<String, dynamic>? query) =>
      '${_scope(uid)}${canonical(path, query)}';

  /// `yol?a=1&b=2` (anahtarlar sıralı); boş sorguda yalnızca yol.
  static String canonical(String path, Map<String, dynamic>? query) {
    final p = path.startsWith('/') ? path.substring(1) : path;
    if (query == null || query.isEmpty) return p;
    final keys = query.keys.toList()..sort();
    final parts = <String>[];
    for (final k in keys) {
      final v = query[k];
      if (v is Iterable) {
        for (final e in v) {
          parts.add(
            '${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent('$e')}',
          );
        }
      } else {
        parts.add(
          '${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent('$v')}',
        );
      }
    }
    return parts.isEmpty ? p : '$p?${parts.join('&')}';
  }

  /// Oturumdaki kullanıcının son yanıtı; yoksa, süresi geçtiyse ya da okunamazsa null.
  Future<CachedResponse<Object?>?> read(
    String path,
    Map<String, dynamic>? query,
  ) async {
    final uid = currentUser;
    if (uid == null || uid.isEmpty) return null;
    final key = keyFor(uid, path, query);
    final entry = await _store.read(key);
    if (entry == null) return null;
    if (entry.isExpired) {
      await _store.remove(key);
      return null;
    }
    return CachedResponse(entry.value, storedAt: entry.storedAt);
  }

  /// [uid] için yanıtı yazar. Kullanıcı bu arada değiştiyse ya da istek bir geçersiz kılmadan önce
  /// başladıysa ([requestedAt]) yazılmaz.
  Future<void> write(
    String path,
    Map<String, dynamic>? query,
    Object? raw, {
    required String uid,
    required DateTime requestedAt,
  }) async {
    if (uid.isEmpty || currentUser != uid) return;
    final canon = canonical(path, query);
    for (final i in _invalidated) {
      if (canon.startsWith(i.prefix) && requestedAt.isBefore(i.at)) return;
    }
    _purgeExpired(uid);
    await _store.write(keyFor(uid, path, query), raw, ttl: maxAge, userId: uid);
  }

  /// Kullanıcının süresi geçmiş yanıtlarını (en çok [purgeEvery]'de bir) arka planda siler. Süresi
  /// geçmiş kayıt zaten gösterilmez ([read]); silmek yalnızca diskte birikmesini önler.
  void _purgeExpired(String uid) {
    final now = DateTime.now().toUtc();
    final last = _purgedAt;
    if (_purgedFor == uid &&
        last != null &&
        now.difference(last) < purgeEvery) {
      return;
    }
    _purgedFor = uid;
    _purgedAt = now;
    unawaited(() async {
      try {
        await _store.removeExpired(_scope(uid));
      } catch (e) {
        AppLog.debug('Süresi geçmiş yanıtlar silinemedi: ${e.runtimeType}');
      }
    }());
  }

  /// Tek bir yanıtı siler (çözülemeyen eski biçim).
  Future<void> remove(String path, Map<String, dynamic>? query) async {
    final uid = currentUser;
    if (uid == null) return;
    await _store.remove(keyFor(uid, path, query));
  }

  /// Oturumdaki kullanıcının [prefixes] ile başlayan yollarının kayıtlarını siler.
  Future<void> invalidate(Iterable<String> prefixes) async {
    final uid = currentUser;
    final now = DateTime.now().toUtc();
    _invalidated.removeWhere(
      (i) => now.difference(i.at) > const Duration(minutes: 5),
    );
    for (final raw in prefixes) {
      final prefix = raw.startsWith('/') ? raw.substring(1) : raw;
      if (prefix.isEmpty) continue;
      _invalidated.add((prefix: prefix, at: now));
      if (uid != null && uid.isNotEmpty) {
        await _store.removePrefix('${_scope(uid)}$prefix');
      }
    }
  }

  /// Başarılı bir yazmanın ([method] + [path]) etkilediği aileleri geçersiz kılar.
  Future<void> noteWrite(String method, String path) async {
    final prefixes = WriteInvalidation.prefixesFor(method, path);
    if (prefixes.isEmpty) return;
    try {
      await invalidate(prefixes);
    } catch (e) {
      AppLog.debug('Önbellek geçersiz kılınamadı: ${e.runtimeType}');
    }
  }
}

/// Bir yazmanın hangi okumaları eskittiği (yol önekleri; `api/v1/` köküne göre).
///
/// Sunucuda bir sipariş değişikliği ana sayfaları, listeleri, sayıları ve onayları etkiler; aileler
/// bu yüzden geniştir: fazla silmek yalnızca bir sonraki açılışta iskelet demektir, eksik silmek eski
/// veri gösterir.
abstract final class WriteInvalidation {
  /// Okuma sayılan ya da önbellekteki ekranları etkilemeyen yazmalar.
  static const _ignored = [
    'auth/',
    'devices/',
    'app/',
    'assistant/',
    'me/deletion-request',
    'notifications/test',
    'notifications/preferences',
    'field-orders/preview',
    'leads/check-duplicate',
  ];

  static const _orders = [
    'orders/',
    'bayi/orders',
    'bayi/quote-desk',
    'home/',
    'customers/me/orders',
    'customers/me/order-requests',
    'customers/me/spending',
    'customers/me/ordering-status',
    'shipments',
    'driver/',
    'approvals',
    'payments',
    'finance/',
    'stats/',
  ];

  static const _shipments = [
    'shipments',
    'driver/',
    'orders/',
    'bayi/orders',
    'home/',
    'customers/me/orders',
    'customers/me/shipments',
    'customers/me/documents',
    'payments',
    'stats/',
  ];

  static const _approvals = [
    'approvals',
    'orders/',
    'bayi/orders',
    'bayi/quote-desk',
    'bayi/customers',
    'home/',
    'finance/',
    'payments',
    'leads',
    'field-orders',
    'me/portfolio',
    'customers/me/',
    'stats/',
  ];

  static const _payments = [
    'payments',
    'orders/',
    'bayi/orders',
    'home/',
    'finance/',
    'customers/me/',
    'stats/',
  ];

  static const _customers = [
    'bayi/customers',
    'stations/me/customers',
    'finance/',
    'approvals',
    'home/',
  ];

  static const _field = [
    'field-orders',
    'leads',
    'me/portfolio',
    'bayi/customers',
    'home/',
    'approvals',
    'stats/',
  ];

  static const _attachments = [
    'attachments',
    'orders/',
    'payments',
    'shipments',
    'driver/',
    'customers/me/documents',
    'customers/me/orders',
    'leads',
    'field-orders',
    'home/',
  ];

  /// [method] + [path] (göreli: `orders/12/quote`) yazmasının geçersiz kıldığı önekler.
  static List<String> prefixesFor(String method, String path) {
    final m = method.asciiUpper;
    if (m == 'GET' || m == 'HEAD' || m == 'OPTIONS') return const [];
    var p = path.startsWith('/') ? path.substring(1) : path;
    final q = p.indexOf('?');
    if (q >= 0) p = p.substring(0, q);
    if (p.isEmpty || _ignored.any(p.startsWith)) return const [];
    final out = <String>{};
    if (p.startsWith('orders/') ||
        p.startsWith('bayi/quote-desk') ||
        p.startsWith('customers/me/order-requests') ||
        p.startsWith('customers/me/templates/from-order')) {
      out.addAll(_orders);
    } else if (p.startsWith('shipments') || p.startsWith('driver/')) {
      out.addAll(_shipments);
    } else if (p.startsWith('approvals')) {
      out.addAll(_approvals);
    } else if (p.startsWith('payments')) {
      out.addAll(_payments);
    } else if (p.startsWith('finance/')) {
      out.addAll(_customers);
    } else if (p.startsWith('stations/me/customers') ||
        p.startsWith('bayi/customers')) {
      out.addAll(_customers);
    } else if (p.startsWith('field-orders') || p.startsWith('leads')) {
      out.addAll(_field);
    } else if (p.startsWith('attachments') || p.startsWith('documents/')) {
      out.addAll(_attachments);
    } else if (p.startsWith('stations/me/staff')) {
      out.add('stations/me/staff');
    } else if (p.startsWith('notifications')) {
      out.add('notifications');
    } else if (p.startsWith('customers/me/')) {
      // Teslimat noktaları, şablonlar, şirket kullanıcıları, onay eşikleri: müşteri verisi.
      out
        ..add('customers/me/')
        ..add('home/customer')
        ..add('catalog/');
    } else if (p.startsWith('me/')) {
      out.add('me/');
    } else {
      // Bilinmeyen aile: ilk bölüm (ör. `x/12/y` → `x`).
      out.add(p.split('/').first);
    }
    return out.toList();
  }
}
