import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../utils/log.dart';

/// Cihazdaki SQLite veritabanı (`akn.db`): bekleyen işlemler (`outbox_ops`) ve önbellek (`cache_entries`).
///
/// Açılamazsa (disk dolu, bozuk dosya) uygulama bellek içi depolarla çalışmaya devam eder;
/// yalnızca çevrimdışı kalıcılık kaybolur.
abstract final class LocalDb {
  static const fileName = 'akn.db';
  static const version = 1;

  static Future<Database?> open() async {
    try {
      final dir = await getDatabasesPath();
      return await openDatabase(
        p.join(dir, fileName),
        version: version,
        onCreate: (db, v) => _migrate(db, 0, v),
        onUpgrade: _migrate,
      );
    } catch (e, st) {
      AppLog.error(
        'Yerel veritabanı açılamadı; bellek içi depolar kullanılacak',
        e,
        st,
      );
      return null;
    }
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    if (from < 1) {
      await db.execute('''
        CREATE TABLE outbox_ops (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          type TEXT NOT NULL,
          payload TEXT NOT NULL,
          idempotency_key TEXT NOT NULL,
          depends_on TEXT,
          files TEXT,
          label TEXT,
          status TEXT NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0,
          next_attempt_at INTEGER,
          last_error TEXT,
          result TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )''');
      await db.execute(
        'CREATE INDEX ix_outbox_user_status ON outbox_ops(user_id, status, next_attempt_at)',
      );
      await db.execute('''
        CREATE TABLE cache_entries (
          key TEXT PRIMARY KEY,
          user_id TEXT,
          value TEXT NOT NULL,
          stored_at INTEGER NOT NULL,
          expires_at INTEGER
        )''');
      await db.execute('CREATE INDEX ix_cache_user ON cache_entries(user_id)');
    }
  }
}
