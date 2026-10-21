import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/models/json.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/connectivity.dart';
import '../../../core/offline/outbox_op.dart';
import '../../../core/offline/outbox_providers.dart';
import '../../../core/offline/outbox_runner.dart';
import '../../../core/offline/outbox_store.dart';
import '../../../core/utils/log.dart';
import '../data/deliver_draft.dart';
import '../data/driver_models.dart';
import '../data/driver_outbox.dart';
import '../data/driver_repository.dart';
import 'driver_home_state.dart';

/// Sunucuda bir şoför sevkiyatı değişti (yola çıkış / teslim onaylandı, push geldi): listeler ve
/// ayrıntılar bunu dinleyip yenilenir. Değer: son değişen sevkiyat ve sayaç.
@immutable
class DriverChange {
  const DriverChange(this.seq, [this.shipmentId]);
  final int seq;
  final int? shipmentId;
}

final driverChangesProvider = NotifierProvider<DriverChanges, DriverChange>(
  DriverChanges.new,
);

class DriverChanges extends Notifier<DriverChange> {
  @override
  DriverChange build() => const DriverChange(0);

  void changed([int? shipmentId]) =>
      state = DriverChange(state.seq + 1, shipmentId);
}

/// Bekleyen işlem işleyicileri (uygulama katmanı `outboxHandlersProvider` içine ekler). Başarılı
/// işlemin sunucu ayrıntısı önbelleğe yazılır ve ekranlar yenilenir.
Map<String, OutboxHandler> buildDriverOutboxHandlers(Ref ref) =>
    DriverOutbox.handlers(
      fileExists: (path) => ref.read(driverFileStoreProvider).exists(path),
      onServerDetail: (id, detail) {
        final uid = ref.read(currentUserIdProvider);
        if (uid != null) {
          unawaited(ref.read(driverRepositoryProvider).saveDetail(uid, detail));
        }
        ref.read(driverChangesProvider.notifier).changed(id);
      },
    );

/// Bir sevkiyatın şoför işlemleri (her türün en yenisi).
@immutable
class DriverShipmentOps {
  const DriverShipmentOps({this.start, this.deliver});

  final OutboxOp? start;
  final OutboxOp? deliver;

  bool get startWaiting => start?.status.isWaiting ?? false;
  bool get deliverWaiting => deliver?.status.isWaiting ?? false;
  bool get startAttention => start?.status == OutboxStatus.needsAttention;
  bool get deliverAttention => deliver?.status == OutboxStatus.needsAttention;
  bool get anyWaiting => startWaiting || deliverWaiting;
  bool get anyAttention => startAttention || deliverAttention;

  /// Kartta gösterilecek işlem: ilgilenilmesi gereken, bekleyen, sonra en yeni tamamlanan.
  OutboxOp? get primary {
    if (deliverAttention) return deliver;
    if (startAttention) return start;
    if (deliverWaiting) return deliver;
    if (startWaiting) return start;
    final d = deliver;
    final s = start;
    if (d == null) return s;
    if (s == null) return d;
    return d.updatedAt.isAfter(s.updatedAt) ? d : s;
  }
}

/// Şoför işlemlerini sevkiyat kimliğine göre gruplar (her türün en yenisi).
Map<int, DriverShipmentOps> groupDriverOps(Iterable<OutboxOp> ops) {
  final starts = <int, OutboxOp>{};
  final delivers = <int, OutboxOp>{};
  for (final op in ops) {
    if (!DriverOutbox.isDriverOp(op)) continue;
    final id = DriverOutbox.shipmentIdOf(op);
    if (id == null) continue;
    final map = op.type == DriverOutbox.start ? starts : delivers;
    final prev = map[id];
    if (prev == null || !op.createdAt.isBefore(prev.createdAt)) map[id] = op;
  }
  return {
    for (final id in {...starts.keys, ...delivers.keys})
      id: DriverShipmentOps(start: starts[id], deliver: delivers[id]),
  };
}

/// Bekleyen ve ilgilenilmesi gereken şoför işlemi sayısı (özet şerit).
({int waiting, int attention}) summarizeDriverOps(
  Map<int, DriverShipmentOps> ops,
) {
  var waiting = 0;
  var attention = 0;
  for (final o in ops.values) {
    if (o.startWaiting) waiting++;
    if (o.deliverWaiting) waiting++;
    if (o.startAttention) attention++;
    if (o.deliverAttention) attention++;
  }
  return (waiting: waiting, attention: attention);
}

/// Oturumdaki kullanıcının şoför işlemleri (kapsayıcıdan okuma: testler, komutlar). Ekranlar
/// [DriverWatch.watchDriverOps] kullanır: türetilmiş sağlayıcı bir ekranın yapımı sırasında yeniden
/// hesaplanıp kardeş rotaları yapım ortasında kirletmesin diye değer kaynak sağlayıcıdan türetilir.
final driverOpsProvider = Provider<Map<int, DriverShipmentOps>>(
  (ref) => groupDriverOps(
    ref.watch(outboxOpsProvider).valueOrNull ?? const <OutboxOp>[],
  ),
);

/// Ekranların şoför verisini kaynak sağlayıcılardan türetmesi.
extension DriverWatch on WidgetRef {
  /// Şoför işlemleri, sevkiyata göre.
  Map<int, DriverShipmentOps> watchDriverOps() => groupDriverOps(
    watch(outboxOpsProvider).valueOrNull ?? const <OutboxOp>[],
  );

  /// Bağlantı (bilinmiyorsa çevrimiçi).
  bool watchOnline() => watch(connectivityProvider).valueOrNull ?? true;
}

/// Yola çıkış ve teslim komutları: işlemi kuyruğa yazar ve hemen göndermeyi dener (çevrimdışıysa
/// sırada kalır). Ekranlar işlemin durumunu `driverOpsProvider` ile izler.
class DriverCommands {
  DriverCommands(this.ref);

  final Ref ref;

  OutboxRunner get _runner => ref.read(outboxRunnerProvider);
  OutboxStore get _store => ref.read(outboxStoreProvider);

  String _uid() =>
      ref.read(currentUserIdProvider) ??
      (throw const UnauthorizedFailure('unauthorized'));

  Future<List<OutboxOp>> _opsOf(int shipmentId, String type) async {
    final all = await _store.list(_uid());
    return [
      for (final o in all)
        if (o.type == type && DriverOutbox.shipmentIdOf(o) == shipmentId) o,
    ];
  }

  /// "Yola çık". Bekleyen bir yola çıkış zaten varsa onu döndürür.
  Future<OutboxOp> start({
    required int shipmentId,
    required String code,
    DriverPosition? position,
    DateTime? deviceTime,
  }) async {
    final waiting = (await _opsOf(
      shipmentId,
      DriverOutbox.start,
    )).where((o) => o.status.isWaiting);
    if (waiting.isNotEmpty) return waiting.last;
    return _runner.enqueue(
      type: DriverOutbox.start,
      label: DriverOutbox.startLabel(code),
      payload: DriverOutbox.startPayload(
        shipmentId: shipmentId,
        code: code,
        deviceTime: deviceTime ?? DateTime.now(),
        position: position,
      ),
    );
  }

  /// "Teslim et". Taslağın dosyaları işleme devredilir; bekleyen yola çıkış varsa ona bağlanır.
  /// Taslak bir reddedilen işlemi düzeltiyorsa ([DeliverDraft.fixOpId]) eski işlem kaldırılır.
  Future<OutboxOp> deliver({
    required DeliverDraft draft,
    required double liters,
    DriverPosition? position,
    DateTime? deviceTime,
  }) async {
    final uid = _uid();
    final waitingDeliver = (await _opsOf(
      draft.shipmentId,
      DriverOutbox.deliver,
    )).where((o) => o.status.isWaiting && o.id != draft.fixOpId);
    if (waitingDeliver.isNotEmpty) return waitingDeliver.last;

    final pendingStart = (await _opsOf(
      draft.shipmentId,
      DriverOutbox.start,
    )).where((o) => o.status != OutboxStatus.done).toList();
    final files = draft.localFiles;
    final op = await _runner.enqueue(
      type: DriverOutbox.deliver,
      label: DriverOutbox.deliverLabel(draft.code),
      files: files,
      dependsOn: pendingStart.isEmpty ? null : pendingStart.last.id,
      payload: DriverOutbox.deliverPayload(
        draft: draft,
        liters: liters,
        deviceTime: deviceTime ?? DateTime.now(),
        position: position,
      ),
    );

    // Düzeltilen eski işlem: kayıt silinir; yeni işleme geçmeyen dosyaları da silinir.
    final fixId = draft.fixOpId;
    if (fixId != null) {
      final old = await _store.get(fixId);
      if (old != null) {
        await _store.delete(fixId);
        ref
            .read(driverFileStoreProvider)
            .deleteAll(old.files.where((f) => !files.contains(f)));
      }
    }
    await ref
        .read(deliverDraftStoreProvider)
        .remove(uid, draft.shipmentId, keep: files.toSet());
    ref.read(driverDraftsProvider.notifier).reload();
    return op;
  }

  /// "Şimdi dene": bekleyen / ertelenen işlemi hemen gönderir.
  Future<void> retry(String opId) => _runner.retry(opId);

  /// Ertelenmiş (geri çekilmede) şoför işlemlerini hemen dener: başka bir istek başarılı olduysa
  /// bağlantı gelmiş demektir.
  Future<void> nudge() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final now = DateTime.now().toUtc();
    final ops = await _store.list(uid);
    for (final o in ops) {
      if (DriverOutbox.isDriverOp(o) &&
          o.status == OutboxStatus.failed &&
          (o.nextAttemptAt?.isAfter(now) ?? false)) {
        await _runner.retry(o.id);
      }
    }
  }

  /// "Vazgeç": işlemi ve dosyalarını siler. Bekleyen yola çıkış silinirse ona bağlı teslim de
  /// sırada kalmasın diye bağı kaldırılır (teslim kendi başına denenir).
  Future<void> discard(String opId) async {
    final op = await _store.get(opId);
    if (op == null) return;
    if (op.type == DriverOutbox.start) {
      final uid = ref.read(currentUserIdProvider);
      if (uid != null) {
        for (final d in await _store.list(uid)) {
          if (d.dependsOn == opId && d.status != OutboxStatus.done) {
            await _store.update(_withoutDependency(d));
          }
        }
      }
    }
    await _runner.discard(opId);
  }

  static OutboxOp _withoutDependency(OutboxOp d) => OutboxOp(
    id: d.id,
    userId: d.userId,
    type: d.type,
    payload: d.payload,
    idempotencyKey: d.idempotencyKey,
    files: d.files,
    label: d.label,
    status: d.status == OutboxStatus.needsAttention
        ? OutboxStatus.pending
        : d.status,
    attempts: d.attempts,
    nextAttemptAt: d.nextAttemptAt,
    lastError: d.lastError,
    result: d.result,
    createdAt: d.createdAt,
    updatedAt: DateTime.now().toUtc(),
  );

  /// Reddedilen teslim işleminden düzeltme taslağı kurar ve kaydeder.
  Future<DeliverDraft?> draftForFix(String opId) async {
    final op = await _store.get(opId);
    if (op == null || op.type != DriverOutbox.deliver) return null;
    final draft = DriverOutbox.draftFromDeliverOp(op);
    try {
      await ref.read(deliverDraftStoreProvider).save(_uid(), draft);
      ref.read(driverDraftsProvider.notifier).reload();
    } catch (e) {
      AppLog.warn('Düzeltme taslağı kaydedilemedi', error: e);
    }
    return draft;
  }

  /// Sahipsiz teslim dosyalarını siler (ör. çıkışta silinen taslakların fotoğrafları). Taslaklar ve
  /// bekleyen işlemler dosyalarını korur; yalnızca 3 günden eski dosyalara bakılır.
  Future<void> sweepFiles() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    try {
      final keep = <String>{
        for (final d in ref.read(deliverDraftStoreProvider).all(uid).values)
          ...d.localFiles,
        for (final o in await _store.list(uid)) ...o.files,
      };
      await ref.read(driverFileStoreProvider).sweep(keep);
    } catch (e) {
      AppLog.debug('Teslim dosyaları temizlenemedi: $e');
    }
  }

  /// İşlemin sunucu yanıtı (tamamlandıysa).
  static JsonMap? resultOf(OutboxOp? op) =>
      op?.status == OutboxStatus.done ? op?.result : null;
}

final driverCommandsProvider = Provider<DriverCommands>(DriverCommands.new);
