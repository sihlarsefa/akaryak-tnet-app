import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/ui.dart';
import '../utils/format.dart';
import 'connectivity.dart';
import 'outbox_op.dart';
import 'outbox_providers.dart';

/// Bekleyen işlem çipi (spec C.4): "2 işlem gönderilmeyi bekliyor" / "1 işlem ilgilenmenizi bekliyor".
/// Dokununca bekleyen işlemler sayfası açılır (tekrar dene / vazgeç). Bekleyen yoksa hiçbir şey çizmez.
class PendingOpsChip extends ConsumerWidget {
  const PendingOpsChip({super.key, this.margin = EdgeInsets.zero});

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = ref.watch(pendingOpsCountProvider);
    final attention = ref.watch(attentionOpsCountProvider);
    if (waiting == 0 && attention == 0) return const SizedBox.shrink();
    final offline = !ref.watch(isOnlineProvider);
    final tone = attention > 0 ? AknTone.danger : AknTone.warn;
    final text = attention > 0
        ? '$attention işlem ilgilenmenizi bekliyor'
        : offline
        ? '$waiting işlem bağlantı gelince gönderilecek'
        : '$waiting işlem gönderilmeyi bekliyor';
    final colors = context.akn.tone(tone);
    return Padding(
      padding: margin,
      child: Semantics(
        button: true,
        label: text,
        child: Material(
          color: colors.bg,
          shape: StadiumBorder(side: BorderSide(color: colors.line)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => showPendingOpsSheet(context),
            // 48 dp dokunma hedefi (spec C.7).
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AknSpace.minTap),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      attention > 0
                          ? Icons.error_outline_rounded
                          : Icons.cloud_upload_outlined,
                      size: 18,
                      color: colors.fg,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        text,
                        style: context.aknText.label.copyWith(color: colors.fg),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bekleyen işlemler sayfası: durum, son hata, "Tekrar dene" ve "Vazgeç".
Future<void> showPendingOpsSheet(BuildContext context) => showAppSheet<void>(
  context: context,
  title: 'Bekleyen işlemler',
  subtitle: 'Bağlantı gelince otomatik gönderilir',
  builder: (_) => const _PendingOpsList(),
);

class _PendingOpsList extends ConsumerWidget {
  const _PendingOpsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ops = (ref.watch(outboxOpsProvider).valueOrNull ?? const <OutboxOp>[])
        .where((o) => o.status != OutboxStatus.done)
        .toList();
    if (ops.isEmpty) {
      return const EmptyState(
        title: 'Bekleyen işlem yok',
        message: 'Tüm işlemleriniz gönderildi.',
        illustration: AknIllustration.inbox,
        compact: true,
      );
    }
    final runner = ref.read(outboxRunnerProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final op in ops)
          AknListTile(
            leadingIcon: op.status == OutboxStatus.needsAttention
                ? Icons.error_outline_rounded
                : Icons.schedule_rounded,
            leadingTone: op.status == OutboxStatus.needsAttention
                ? AknTone.danger
                : AknTone.warn,
            title: op.label ?? op.type,
            subtitle: [
              op.status.label,
              if (op.lastError != null) op.lastError!,
              if (op.nextAttemptAt != null && op.status == OutboxStatus.failed)
                'Sonraki deneme ${Fmt.time(op.nextAttemptAt)}',
            ].join(' · '),
            padding: const EdgeInsets.symmetric(vertical: 8),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Tekrar dene',
                  onPressed: op.status == OutboxStatus.sending
                      ? null
                      : () => unawaited(runner.retry(op.id)),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                if (op.status == OutboxStatus.needsAttention)
                  IconButton(
                    tooltip: 'Vazgeç',
                    onPressed: () async {
                      final ok = await showConfirmSheet(
                        context,
                        title: 'İşlemden vazgeçilsin mi?',
                        message:
                            'Bu işlem sunucuya gönderilmeyecek ve eklenen dosyalar silinecek.',
                        confirmLabel: 'Vazgeç',
                        destructive: true,
                      );
                      if (ok) await runner.discard(op.id);
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
