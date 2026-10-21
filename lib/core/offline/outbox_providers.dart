import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_controller.dart';
import '../network/network_providers.dart';
import 'connectivity.dart';
import 'outbox_op.dart';
import 'outbox_runner.dart';
import 'outbox_store.dart';

/// İşlem türü → işleyici. Uygulama katmanı özelliklerin işleyicileriyle geçersiz kılar
/// (`driver.start`, `driver.deliver`, `field.saveDraft`, `lead.saveDraft`, `lead.upload`).
final outboxHandlersProvider = Provider<Map<String, OutboxHandler>>(
  (ref) => const {},
);

/// Bekleyen işlem gönderici. Bağlantı gelince, öne gelince ve 30 sn'de bir çalışır.
final outboxRunnerProvider = Provider<OutboxRunner>((ref) {
  final runner = OutboxRunner(
    store: ref.watch(outboxStoreProvider),
    api: ref.watch(apiClientProvider),
    handlers: ref.watch(outboxHandlersProvider),
    currentUserId: () => ref.read(currentUserIdProvider),
    isOnline: () => ref.read(isOnlineProvider),
  );

  final timer = Timer.periodic(
    const Duration(seconds: 30),
    (_) => unawaited(runner.runOnce()),
  );
  ref.listen<bool>(isOnlineProvider, (prev, next) {
    // Bağlantı geri geldi: geri çekilme beklenmez.
    if (next && prev == false) unawaited(runner.retryWaiting());
  });
  ref.listen<String?>(currentUserIdProvider, (prev, next) {
    if (next != null && next != prev) unawaited(runner.runOnce());
  });
  ref.onDispose(timer.cancel);
  return runner;
});

/// Kullanıcının tüm bekleyen işlemleri (liste ekranı, Profil → Bekleyen işlemler). Değişince yenilenir.
final outboxOpsProvider = StreamProvider<List<OutboxOp>>((ref) async* {
  final store = ref.watch(outboxStoreProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    yield const [];
    return;
  }
  yield await store.list(userId);
  await for (final _ in store.changes) {
    yield await store.list(userId);
  }
});

/// Gönderilmeyi bekleyen işlem sayısı ("2 işlem gönderilmeyi bekliyor").
final pendingOpsCountProvider = Provider<int>((ref) {
  final ops = ref.watch(outboxOpsProvider).valueOrNull ?? const [];
  return ops.where((o) => o.status.isWaiting).length;
});

/// İlgilenilmesi gereken (sunucunun reddettiği) işlem sayısı.
final attentionOpsCountProvider = Provider<int>((ref) {
  final ops = ref.watch(outboxOpsProvider).valueOrNull ?? const [];
  return ops.where((o) => o.status == OutboxStatus.needsAttention).length;
});

/// Kabuk çağırır: öne gelince bekleyen işlemleri gönder.
void outboxHandleLifecycle(WidgetRef ref, AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    unawaited(ref.read(outboxRunnerProvider).runOnce());
  }
}
