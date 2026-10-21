import 'dart:async';
import 'dart:io';

import '../models/json.dart';
import '../network/api_client.dart';
import '../network/app_failure.dart';
import '../network/idempotency.dart';
import '../utils/log.dart';
import 'backoff.dart';
import 'outbox_op.dart';
import 'outbox_store.dart';

/// İşleyicinin bağlamı.
class OutboxContext {
  OutboxContext._(this._runner, this._op, this.dependencyResult);

  final OutboxRunner _runner;
  OutboxOp _op;

  /// Bağımlı olunan işlemin sonucu (`dependsOn`), ör. `{'leadId': 8012}`.
  final JsonMap? dependencyResult;

  /// Bu deneme bir `concurrency_conflict` sonrasındaki tek tekrar mı (spec D.7): işleyici kaydı yeniden
  /// okuyup güncel `concurrencyToken` ile göndermelidir.
  bool get isConflictRetry =>
      _op.payload[OutboxRunner.conflictRetryKey] == true;

  ApiClient get api => _runner.api;

  /// Güncel gövde ([savePayload] sonrası dahil).
  JsonMap get payload => _op.payload;

  /// Ara ilerlemeyi kalıcı yazar (ör. yüklenen fotoğraf kimlikleri); tekrar deneme kaldığı yerden sürer.
  Future<void> savePayload(JsonMap payload) async {
    _op = _op.copyWith(payload: payload);
    await _runner.store.update(_op);
  }

  /// Alt istek için kalıcı Idempotency-Key (ör. her fotoğraf yüklemesi). İlk çağrıda üretilir ve
  /// gövdeye (`_keys`) yazılır; tekrar denemeler aynı anahtarı kullanır.
  Future<String> subKey(String name) async {
    final keys = Map<String, dynamic>.of(
      JsonReader.asMap(_op.payload['_keys']),
    );
    final existing = keys[name];
    if (existing is String) return existing;
    final key = newIdempotencyKey();
    keys[name] = key;
    await savePayload({..._op.payload, '_keys': keys});
    return key;
  }
}

/// İşlem işleyicisi: başarıda sunucu sonucunu (bağımlı işlemler için) döndürür; hatada [AppFailure]
/// fırlatır. İşleyiciler idempotent olmalıdır: aynı işlem birden çok kez çalışabilir; ana istek
/// `op.idempotencyKey`, alt istekler [OutboxContext.subKey] kullanır.
typedef OutboxHandler =
    Future<JsonMap?> Function(OutboxOp op, OutboxContext ctx);

/// Bekleyen işlemleri sırayla gönderir (spec C.4).
///
/// - Bağlantı gelince, uygulama öne gelince ve 30 sn'de bir çalışır ([runOnce]; aynı anda tek çalışma).
/// - Geçici hata (çevrimdışı, zaman aşımı, 5xx, 429, işlem sürüyor) → `failed` + 5 sn / 15 sn / 1 dk /
///   5 dk / 15 dk bekleme; sunucu `Retry-After` verdiyse büyük olanı. Çevrimdışıysa tur durur; bağlantı
///   gelince bekleme sıfırlanır ([retryWaiting]).
/// - 409 `concurrency_conflict` → bir kez yeniden okuyup tekrar ([OutboxContext.isConflictRetry]), sonra
///   `needsAttention`.
/// - 401 → işlem bekler (oturum yenilenince ya da yeniden girişte sürer). 426 → bekler.
/// - 400/403/404/409 → `needsAttention` + sunucu mesajı; kullanıcı düzeltir, yeniden dener ya da vazgeçer.
/// - `dependsOn`: bağımlı olunan işlem bitmeden çalışmaz; onun sonucu bağlamda okunur.
class OutboxRunner {
  /// Gövdedeki işaret: `concurrency_conflict` sonrası tek "yeniden oku ve tekrar dene" yapıldı.
  static const conflictRetryKey = '_conflictRetry';

  OutboxRunner({
    required this.store,
    required this.api,
    required this.handlers,
    required this.currentUserId,
    DateTime Function()? clock,
    bool Function()? isOnline,
  }) : _clock = clock ?? _utcNow,
       _isOnline = isOnline ?? _always;

  static DateTime _utcNow() => DateTime.now().toUtc();
  static bool _always() => true;

  final OutboxStore store;
  final ApiClient api;
  final Map<String, OutboxHandler> handlers;
  final String? Function() currentUserId;
  final DateTime Function() _clock;
  final bool Function() _isOnline;

  Future<void>? _running;
  bool _again = false;
  int _seq = 0;

  /// Yeni işlem ekler ve hemen göndermeyi dener (çevrimdışıysa sırada kalır).
  Future<OutboxOp> enqueue({
    required String type,
    required JsonMap payload,
    String? dependsOn,
    List<String> files = const [],
    String? label,
    String? idempotencyKey,
    bool runNow = true,
  }) async {
    final uid = currentUserId();
    if (uid == null) throw const UnauthorizedFailure('unauthorized');
    final now = _clock();
    final op = OutboxOp(
      id: '${now.microsecondsSinceEpoch.toRadixString(36)}-${(_seq++).toRadixString(36)}',
      userId: uid,
      type: type,
      payload: payload,
      idempotencyKey: idempotencyKey ?? newIdempotencyKey(),
      dependsOn: dependsOn,
      files: files,
      label: label,
      createdAt: now,
      updatedAt: now,
    );
    await store.insert(op);
    if (runNow) unawaited(runOnce());
    return op;
  }

  /// Vadesi gelen işlemleri gönderir. Çalışırken gelen çağrı turun sonunda bir tur daha ister.
  Future<void> runOnce() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final f = _drain();
    _running = f;
    return f.whenComplete(() => _running = null);
  }

  /// "Şimdi tekrar dene".
  Future<void> retry(String id) async {
    final op = await store.get(id);
    if (op == null || op.status == OutboxStatus.done) return;
    await store.update(
      op.copyWith(
        status: OutboxStatus.pending,
        clearNextAttempt: true,
        clearError: true,
      ),
    );
    await runOnce();
  }

  /// Bağlantı geri geldi: geçici hatayla bekleyen işlemlerin bekleme süresi sıfırlanır ve hemen
  /// gönderilir (spec D.7; 15 dk geri çekilme bağlantı gelince beklenmez).
  Future<void> retryWaiting() async {
    final uid = currentUserId();
    if (uid == null) return;
    for (final op in await store.list(uid)) {
      if (op.status == OutboxStatus.failed && op.nextAttemptAt != null) {
        await store.update(op.copyWith(clearNextAttempt: true));
      }
    }
    await runOnce();
  }

  /// "Vazgeç": işlemi ve dosyalarını siler.
  Future<void> discard(String id) async {
    final op = await store.get(id);
    if (op == null) return;
    await store.delete(id);
    _deleteFiles(op.files);
  }

  /// Gönderilmeyi bekleyen işlem sayısı (rozet).
  Future<int> waitingCount() async {
    final uid = currentUserId();
    if (uid == null) return 0;
    return (await store.list(uid)).where((o) => o.status.isWaiting).length;
  }

  Future<void> _drain() async {
    do {
      _again = false;
      await _turn();
    } while (_again);
  }

  Future<void> _turn() async {
    final uid = currentUserId();
    if (uid == null || !_isOnline()) return;
    final ops = await store.list(uid);
    final byId = {for (final o in ops) o.id: o};
    final now = _clock();

    for (final candidate in ops.where((o) => o.isDue(now))) {
      var op = candidate;
      JsonMap? depResult;
      if (op.dependsOn != null) {
        final dep = byId[op.dependsOn];
        if (dep == null) {
          await store.update(
            op.copyWith(
              status: OutboxStatus.needsAttention,
              lastError: 'Bağlı olduğu işlem bulunamadı.',
            ),
          );
          continue;
        }
        if (dep.status != OutboxStatus.done) continue;
        depResult = dep.result;
      }
      final handler = handlers[op.type];
      if (handler == null) {
        await store.update(
          op.copyWith(
            status: OutboxStatus.needsAttention,
            lastError: 'Bu işlem türü bu sürümde desteklenmiyor.',
          ),
        );
        continue;
      }

      op = op.copyWith(status: OutboxStatus.sending);
      await store.update(op);
      final ctx = OutboxContext._(this, op, depResult);
      try {
        final result = await handler(ctx._op, ctx);
        final done = ctx._op.copyWith(
          status: OutboxStatus.done,
          result: result,
          clearError: true,
          clearNextAttempt: true,
        );
        await store.update(done);
        byId[op.id] = done;
        _deleteFiles(op.files);
      } catch (e) {
        final f = AppFailure.from(e);
        final current = ctx._op;
        switch (f) {
          case UnauthorizedFailure() || UpdateRequiredFailure():
            await store.update(
              current.copyWith(
                status: OutboxStatus.pending,
                lastError: f.message,
              ),
            );
            return;
          case OfflineFailure():
            await _scheduleRetry(current, f, null);
            return;
          case ConflictFailure(isConcurrency: true)
              when current.payload[conflictRetryKey] != true:
            // Kayıt bu arada değişti: bir kez yeniden okunup güncel belirteçle denenir; yine
            // çakışırsa kullanıcıya bırakılır.
            await store.update(
              current.copyWith(
                status: OutboxStatus.pending,
                payload: {...current.payload, conflictRetryKey: true},
                clearNextAttempt: true,
                lastError: f.message,
              ),
            );
            _again = true;
          case _ when f.isTransient:
            await _scheduleRetry(current, f, f.retryAfter);
          default:
            await store.update(
              current.copyWith(
                status: OutboxStatus.needsAttention,
                lastError: f.message,
              ),
            );
            AppLog.warn(
              'Bekleyen işlem reddedildi: ${op.type} (${f.runtimeType})',
            );
        }
      }
    }
  }

  Future<void> _scheduleRetry(OutboxOp op, AppFailure f, Duration? retryAfter) {
    final attempts = op.attempts + 1;
    return store.update(
      op.copyWith(
        status: OutboxStatus.failed,
        attempts: attempts,
        nextAttemptAt: _clock().add(
          OutboxBackoff.withRetryAfter(attempts, retryAfter),
        ),
        lastError: f.message,
      ),
    );
  }

  static void _deleteFiles(List<String> paths) {
    for (final p in paths) {
      try {
        final f = File(p);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {
        // Dosya zaten yok.
      }
    }
  }
}
