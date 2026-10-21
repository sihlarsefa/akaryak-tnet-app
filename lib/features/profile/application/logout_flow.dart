import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/offline/connectivity.dart';
import '../../../core/offline/outbox_op.dart';
import '../../../core/offline/outbox_providers.dart';
import '../../../core/offline/outbox_store.dart';
import '../../../core/ui/ui.dart';
import '../copy.dart';

/// Gönderilmemiş (tamamlanmamış) işlemler.
List<OutboxOp> unsentOps(WidgetRef ref) => [
  for (final o in ref.read(outboxOpsProvider).valueOrNull ?? const <OutboxOp>[])
    if (o.status != OutboxStatus.done) o,
];

/// Kullanıcının tamamlanmamış işlemlerini siler (dosyalarıyla).
Future<void> discardUnsentOps(WidgetRef ref) async {
  final uid = ref.read(currentUserIdProvider);
  if (uid == null) return;
  final runner = ref.read(outboxRunnerProvider);
  final ops = await ref.read(outboxStoreProvider).list(uid);
  for (final o in ops) {
    if (o.status != OutboxStatus.done) await runner.discard(o.id);
  }
}

enum _PendingChoice { sent, discard }

/// Çıkış (spec A.4 A8): bekleyen işlem yoksa kısa onay; varsa "Şimdi gönder" / "Yine de çık (işlemler
/// silinir)" / "Vazgeç". [allDevices] tüm cihazlardan çıkar (`auth/logout {allDevices: true}`).
Future<void> confirmAndSignOut(
  BuildContext context,
  WidgetRef ref, {
  bool allDevices = false,
}) async {
  final pending = unsentOps(ref);
  final session = ref.read(sessionControllerProvider.notifier);
  if (pending.isEmpty) {
    final ok = await showConfirmSheet(
      context,
      title: allDevices
          ? ProfileCopy.signOutAllTitle
          : ProfileCopy.signOutTitle,
      message: allDevices ? ProfileCopy.signOutAllMessage : null,
      confirmLabel: allDevices ? ProfileCopy.signOutAll : ProfileCopy.signOut,
      cancelLabel: ProfileCopy.cancel,
      icon: Icons.logout_rounded,
      destructive: true,
    );
    if (ok) await session.signOut(allDevices: allDevices);
    return;
  }
  final choice = await showAppSheet<_PendingChoice>(
    context: context,
    showClose: false,
    builder: (_) => const _PendingOpsSheet(),
  );
  switch (choice) {
    case _PendingChoice.sent:
      AppToast.success(ProfileCopy.sentAll);
      await session.signOut(allDevices: allDevices);
    case _PendingChoice.discard:
      await discardUnsentOps(ref);
      await session.signOut(allDevices: allDevices);
    case null:
      return;
  }
}

class _PendingOpsSheet extends ConsumerStatefulWidget {
  const _PendingOpsSheet();

  @override
  ConsumerState<_PendingOpsSheet> createState() => _PendingOpsSheetState();
}

class _PendingOpsSheetState extends ConsumerState<_PendingOpsSheet> {
  String? _message;

  Future<void> _sendNow() async {
    if (!ref.read(isOnlineProvider)) {
      setState(() => _message = ProfileCopy.sendOffline);
      return;
    }
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final runner = ref.read(outboxRunnerProvider);
    final store = ref.read(outboxStoreProvider);
    for (final o in await store.list(uid)) {
      if (o.status == OutboxStatus.failed ||
          o.status == OutboxStatus.needsAttention) {
        await runner.retry(o.id);
      }
    }
    await runner.runOnce();
    final left = [
      for (final o in await store.list(uid))
        if (o.status != OutboxStatus.done) o,
    ];
    if (!mounted) return;
    if (left.isEmpty) {
      Navigator.of(context).pop(_PendingChoice.sent);
      return;
    }
    final error = left.map((o) => o.lastError).whereType<String>().firstOrNull;
    setState(
      () =>
          _message = [ProfileCopy.stillPending(left.length), ?error].join(' '),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final ops = [
      for (final o
          in ref.watch(outboxOpsProvider).valueOrNull ?? const <OutboxOp>[])
        if (o.status != OutboxStatus.done) o,
    ];
    final online = ref.watch(isOnlineProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: c.warn.bg, shape: BoxShape.circle),
            child: Icon(Icons.cloud_upload_rounded, color: c.warn.fg, size: 28),
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            ProfileCopy.pendingTitle(ops.length),
            style: t.headline,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          ProfileCopy.pendingMessage,
          style: t.body,
          textAlign: TextAlign.center,
        ),
        if (ops.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final o in ops.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    o.status == OutboxStatus.needsAttention
                        ? Icons.error_outline_rounded
                        : Icons.schedule_rounded,
                    size: 18,
                    color: c.dim,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${o.label ?? o.type} · ${o.status.label}',
                      style: t.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 12),
          AknBanner(tone: AknTone.warn, message: _message!),
        ],
        const SizedBox(height: 20),
        AknButton(
          label: ProfileCopy.sendNow,
          icon: online ? Icons.cloud_upload_rounded : Icons.cloud_off_rounded,
          expand: true,
          showSuccess: false,
          onPressedAsync: _sendNow,
        ),
        const SizedBox(height: 8),
        AknButton.danger(
          label: ProfileCopy.signOutAnyway,
          expand: true,
          onPressed: () => Navigator.of(context).pop(_PendingChoice.discard),
        ),
        AknButton.ghost(
          label: ProfileCopy.cancel,
          expand: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
