import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../utils/log.dart';

/// Önbellek kaydı. Süresi geçmiş kayıt da döner ([isExpired]); çevrimdışıyken eski veri gösterilir.
class CacheEntry {
  const CacheEntry({
    required this.value,
    required this.storedAt,
    this.expiresAt,
  });

  /// JSON değeri (Map, List, ilkel).
  final Object? value;
  final DateTime storedAt;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt!);

  /// "Son güncelleme" etiketi için yaş.
  Duration get age => DateTime.now().toUtc().difference(storedAt);
}

/// Anahtar/değer + süre önbelleği (spec C.4): me/access, ana sayfa yükleri, şoför sevkiyatları, portföy.
///
/// Anahtar kuralı: kullanıcıya özel veriler [CacheKeys.user] ile (`<userId>:<ad>`) yazılır ve çıkışta
/// [clearUser] ile silinir.
abstract interface class CacheStore {
  Future<CacheEntry?> read(String key);

  Future<void> write(
    String key,
    Object? value, {
    Duration? ttl,
    String? userId,
  });

  Future<void> remove(String key);

  Future<void> clearUser(String userId);

  /// Oturuma ait her şeyi siler; yalnızca cihaz geneli kayıtlar ([CacheKeys.deviceWide], ör. app/config)
  /// kalır. Çıkışta ve kullanıcı değişince çağrılır (spec D.7).
  Future<void> clearSessionData();

  Future<void> clearAll();
}

/// Önbellek anahtarları.
abstract final class CacheKeys {
  static String user(String userId, String name) => '$userId:$name';

  static const meAccess = 'me.access';
  static const appConfig = 'app.config';

  /// Oturumdan bağımsız, çıkışta silinmeyen kayıtlar.
  static const deviceWide = {appConfig};
  static const homeCustomer = 'home.customer';
  static const homeBayi = 'home.bayi';
  static const driverShipments = 'driver.shipments';
  static const fieldPortfolio = 'field.portfolio';
}

/// SQLite tabanlı önbellek (`cache_entries`).
class SqfliteCacheStore implements CacheStore {
  SqfliteCacheStore(this.db);

  final Database db;

  @override
  Future<CacheEntry?> read(String key) async {
    try {
      final rows = await db.query(
        'cache_entries',
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final r = rows.first;
      final exp = r['expires_at'] as int?;
      return CacheEntry(
        value: jsonDecode(r['value']! as String),
        storedAt: DateTime.fromMillisecondsSinceEpoch(
          r['stored_at']! as int,
          isUtc: true,
        ),
        expiresAt: exp == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(exp, isUtc: true),
      );
    } catch (e) {
      AppLog.warn('Önbellek okunamadı ($key)', error: e);
      return null;
    }
  }

  @override
  Future<void> write(
    String key,
    Object? value, {
    Duration? ttl,
    String? userId,
  }) async {
    try {
      final now = DateTime.now().toUtc();
      await db.insert('cache_entries', {
        'key': key,
        'user_id': userId,
        'value': jsonEncode(value),
        'stored_at': now.millisecondsSinceEpoch,
        'expires_at': ttl == null ? null : now.add(ttl).millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      AppLog.warn('Önbelleğe yazılamadı ($key)', error: e);
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      await db.delete('cache_entries', where: 'key = ?', whereArgs: [key]);
    } catch (_) {}
  }

  @override
  Future<void> clearUser(String userId) async {
    try {
      await db.delete(
        'cache_entries',
        where: 'user_id = ? OR key LIKE ?',
        whereArgs: [userId, '$userId:%'],
      );
    } catch (_) {}
  }

  @override
  Future<void> clearSessionData() async {
    try {
      final keep = CacheKeys.deviceWide.toList();
      await db.delete(
        'cache_entries',
        where: 'key NOT IN (${List.filled(keep.length, '?').join(', ')})',
        whereArgs: keep,
      );
    } catch (_) {}
  }

  @override
  Future<void> clearAll() async {
    try {
      await db.delete('cache_entries');
    } catch (_) {}
  }
}

/// Bellek içi önbellek (testler; veritabanı açılamazsa yedek).
class MemoryCacheStore implements CacheStore {
  final Map<String, (CacheEntry, String?)> _entries = {};

  @override
  Future<CacheEntry?> read(String key) async => _entries[key]?.$1;

  @override
  Future<void> write(
    String key,
    Object? value, {
    Duration? ttl,
    String? userId,
  }) async {
    final now = DateTime.now().toUtc();
    // JSON gidiş-dönüşü: kalıcı depoyla aynı davranış (değiştirilebilir referans tutulmaz).
    final copy = jsonDecode(jsonEncode(value));
    _entries[key] = (
      CacheEntry(
        value: copy,
        storedAt: now,
        expiresAt: ttl == null ? null : now.add(ttl),
      ),
      userId,
    );
  }

  @override
  Future<void> remove(String key) async => _entries.remove(key);

  @override
  Future<void> clearUser(String userId) async => _entries.removeWhere(
    (k, v) => v.$2 == userId || k.startsWith('$userId:'),
  );

  @override
  Future<void> clearSessionData() async =>
      _entries.removeWhere((k, _) => !CacheKeys.deviceWide.contains(k));

  @override
  Future<void> clearAll() async => _entries.clear();
}

/// Bootstrap SQLite deposunu verir; varsayılan bellek içi.
final cacheStoreProvider = Provider<CacheStore>((ref) => MemoryCacheStore());
