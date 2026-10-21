import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../utils/log.dart';
import 'outbox_op.dart';

/// Bekleyen işlem deposu (spec C.4). Değişiklikler [changes] ile duyurulur (rozet, liste).
abstract interface class OutboxStore {
  Future<void> insert(OutboxOp op);

  Future<void> update(OutboxOp op);

  Future<OutboxOp?> get(String id);

  /// Kullanıcının işlemleri (oluşturma sırasıyla).
  Future<List<OutboxOp>> list(String userId, {Set<OutboxStatus>? statuses});

  Future<void> delete(String id);

  /// [olderThan] süreden eski tamamlanmış işlemleri siler.
  Future<void> purgeDone({Duration olderThan = const Duration(hours: 24)});

  Stream<void> get changes;
}

/// SQLite tabanlı depo (`outbox_ops`).
class SqfliteOutboxStore implements OutboxStore {
  SqfliteOutboxStore(this.db);

  final Database db;
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  void _notify() => _changes.add(null);

  @override
  Future<void> insert(OutboxOp op) async {
    await db.insert(
      'outbox_ops',
      op.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify();
  }

  @override
  Future<void> update(OutboxOp op) async {
    await db.update(
      'outbox_ops',
      op.toRow(),
      where: 'id = ?',
      whereArgs: [op.id],
    );
    _notify();
  }

  @override
  Future<OutboxOp?> get(String id) async {
    final rows = await db.query(
      'outbox_ops',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : OutboxOp.fromRow(rows.first);
  }

  @override
  Future<List<OutboxOp>> list(
    String userId, {
    Set<OutboxStatus>? statuses,
  }) async {
    try {
      final rows = await db.query(
        'outbox_ops',
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'created_at ASC',
      );
      final ops = rows.map(OutboxOp.fromRow);
      return statuses == null
          ? ops.toList()
          : ops.where((o) => statuses.contains(o.status)).toList();
    } catch (e) {
      AppLog.warn('Bekleyen işlemler okunamadı', error: e);
      return const [];
    }
  }

  @override
  Future<void> delete(String id) async {
    await db.delete('outbox_ops', where: 'id = ?', whereArgs: [id]);
    _notify();
  }

  @override
  Future<void> purgeDone({
    Duration olderThan = const Duration(hours: 24),
  }) async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(olderThan)
        .millisecondsSinceEpoch;
    await db.delete(
      'outbox_ops',
      where: 'status = ? AND updated_at < ?',
      whereArgs: [OutboxStatus.done.name, cutoff],
    );
    _notify();
  }
}

/// Bellek içi depo (testler; veritabanı açılamazsa yedek).
class MemoryOutboxStore implements OutboxStore {
  final Map<String, OutboxOp> _ops = {};
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> insert(OutboxOp op) async {
    _ops[op.id] = op;
    _changes.add(null);
  }

  @override
  Future<void> update(OutboxOp op) async {
    if (_ops.containsKey(op.id)) _ops[op.id] = op;
    _changes.add(null);
  }

  @override
  Future<OutboxOp?> get(String id) async => _ops[id];

  @override
  Future<List<OutboxOp>> list(
    String userId, {
    Set<OutboxStatus>? statuses,
  }) async {
    final ops =
        _ops.values
            .where(
              (o) =>
                  o.userId == userId &&
                  (statuses == null || statuses.contains(o.status)),
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return ops;
  }

  @override
  Future<void> delete(String id) async {
    _ops.remove(id);
    _changes.add(null);
  }

  @override
  Future<void> purgeDone({
    Duration olderThan = const Duration(hours: 24),
  }) async {
    final cutoff = DateTime.now().toUtc().subtract(olderThan);
    _ops.removeWhere(
      (_, o) => o.status == OutboxStatus.done && o.updatedAt.isBefore(cutoff),
    );
    _changes.add(null);
  }
}

/// Bootstrap SQLite deposunu verir; varsayılan bellek içi.
final outboxStoreProvider = Provider<OutboxStore>((ref) => MemoryOutboxStore());
