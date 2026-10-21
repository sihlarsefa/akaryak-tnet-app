import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/offline/outbox_op.dart';
import '../../../../core/offline/pending_ops_chip.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/driver_ops.dart';
import '../../copy.dart';
import '../../data/driver_outbox.dart';

/// Bekleyen işlemin kullanıcıya görünen aşaması (spec C.4a "Queued vs sent").
enum OpPhase {
  /// Şu an gönderiliyor (çevrimiçi, ilk deneme).
  sending,

  /// Telefonda kayıtlı; bağlantı gelince gönderilecek (çevrimdışı, ertelendi, bağımlı işlem bekleniyor).
  queued,

  /// Sunucu onayladı.
  sent,

  /// Sunucu reddetti: sunucu mesajı + "Düzelt".
  attention,
}

OpPhase opPhaseOf(OutboxOp op, {required bool online}) => switch (op.status) {
  OutboxStatus.done => OpPhase.sent,
  OutboxStatus.needsAttention => OpPhase.attention,
  OutboxStatus.failed => OpPhase.queued,
  OutboxStatus.sending => OpPhase.sending,
  OutboxStatus.pending =>
    online && op.lastError == null && op.dependsOn == null
        ? OpPhase.sending
        : OpPhase.queued,
};

/// Tamamlanan işlem yakın zamanda mı tamamlandı (başarı animasyonu bir kez oynar).
bool isFreshlyDone(
  OutboxOp op, {
  Duration within = const Duration(seconds: 4),
}) =>
    op.status == OutboxStatus.done &&
    DateTime.now().toUtc().difference(op.updatedAt) <= within;

/// Kart üstündeki işlem çipi: "Gönderilmeyi bekliyor" (uyarı + saat), "Gönderiliyor", sunucu onaylayınca
/// kısa bir başarı animasyonu ("Gönderildi"), reddedilince "İlgilenmeniz gerekiyor".
class OpStatusChip extends ConsumerStatefulWidget {
  const OpStatusChip({super.key, required this.op});

  final OutboxOp op;

  @override
  ConsumerState<OpStatusChip> createState() => _OpStatusChipState();
}

class _OpStatusChipState extends ConsumerState<OpStatusChip> {
  bool _celebrate = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (isFreshlyDone(widget.op)) _startCelebration();
  }

  @override
  void didUpdateWidget(OpStatusChip old) {
    super.didUpdateWidget(old);
    final was = old.op.status;
    final now = widget.op.status;
    if (now == OutboxStatus.done && was != OutboxStatus.done) {
      _startCelebration();
      SemanticsService.sendAnnouncement(
        View.of(context),
        widget.op.type == DriverOutbox.deliver
            ? DriverCopy.deliverSentTitle
            : DriverCopy.startSentTitle,
        Directionality.of(context),
      );
    }
  }

  void _startCelebration() {
    _celebrate = true;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _celebrate = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watchOnline();
    final phase = opPhaseOf(widget.op, online: online);
    final Widget chip = switch (phase) {
      OpPhase.sent when _celebrate => const _SentChip(key: ValueKey('sent')),
      OpPhase.sent => const SizedBox.shrink(key: ValueKey('none')),
      OpPhase.sending => const _PhaseChip(
        key: ValueKey('sending'),
        label: DriverCopy.opSending,
        tone: AknTone.info,
        spinner: true,
      ),
      OpPhase.queued => const _PhaseChip(
        key: ValueKey('queued'),
        label: DriverCopy.opWaiting,
        tone: AknTone.warn,
        icon: Icons.schedule_rounded,
      ),
      OpPhase.attention => const _PhaseChip(
        key: ValueKey('attention'),
        label: DriverCopy.opAttention,
        tone: AknTone.danger,
        icon: Icons.error_outline_rounded,
      ),
    };
    return AnimatedSwitcher(
      duration: AknMotion.of(context, AknMotion.base),
      child: chip,
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.spinner = false,
  });

  final String label;
  final AknTone tone;
  final IconData? icon;
  final bool spinner;

  @override
  Widget build(BuildContext context) {
    final tc = context.akn.tone(tone);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: tc.bg,
          borderRadius: AknRadius.pillAll,
          border: Border.all(color: tc.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner)
              ChevronSpinner(size: 12, color: tc.fg, semanticLabel: null)
            else if (icon != null)
              Icon(icon, size: 14, color: tc.fg),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.aknText.captionStrong.copyWith(color: tc.fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SentChip extends StatelessWidget {
  const _SentChip({super.key});

  @override
  Widget build(BuildContext context) {
    final tc = context.akn.ok;
    return Semantics(
      label: DriverCopy.opSent,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 2, 9, 2),
        decoration: BoxDecoration(
          color: tc.bg,
          borderRadius: AknRadius.pillAll,
          border: Border.all(color: tc.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SuccessCheck(size: 18, haptic: false, semanticLabel: null),
            const SizedBox(width: 4),
            Text(
              DriverCopy.opSent,
              style: context.aknText.captionStrong.copyWith(color: tc.fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// İşlemin sonucu (ayrıntı ekranının alt çubuğu ve teslim sonucu): gönderiliyor / kaydedildi (uyarı +
/// saat ikonu, başarı işareti asla) / gönderildi (çizilen başarı işareti) / reddedildi (sunucu mesajı +
/// eylemler).
class OpOutcomePanel extends ConsumerWidget {
  const OpOutcomePanel({
    super.key,
    required this.op,
    this.onFix,
    this.onDiscard,
    this.compact = false,
  });

  final OutboxOp op;

  /// "Düzelt" (reddedilen teslim).
  final VoidCallback? onFix;

  /// "Vazgeç".
  final VoidCallback? onDiscard;

  /// Alt çubukta tek satır görünüm.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watchOnline();
    final phase = opPhaseOf(op, online: online);
    final deliver = op.type == DriverOutbox.deliver;
    final c = context.akn;
    final t = context.aknText;
    final commands = ref.read(driverCommandsProvider);

    final (AknTone tone, String title, String? body) = switch (phase) {
      OpPhase.sending => (AknTone.info, DriverCopy.sendingTitle, null),
      OpPhase.queued => (
        AknTone.warn,
        DriverCopy.queuedTitle,
        deliver ? DriverCopy.queuedDeliverBody : DriverCopy.queuedStartBody,
      ),
      OpPhase.sent => (
        AknTone.ok,
        deliver ? DriverCopy.deliverSentTitle : DriverCopy.startSentTitle,
        deliver ? DriverCopy.deliverSentBody : DriverCopy.startSentBody,
      ),
      OpPhase.attention => (
        AknTone.danger,
        deliver ? DriverCopy.deliverFailedTitle : DriverCopy.startFailedTitle,
        op.lastError,
      ),
    };
    final tc = c.tone(tone);
    final Widget leading = switch (phase) {
      OpPhase.sending => ChevronSpinner(
        size: 22,
        color: tc.fg,
        semanticLabel: null,
      ),
      OpPhase.sent => const SuccessCheck(size: 36, semanticLabel: null),
      OpPhase.queued => Icon(Icons.schedule_rounded, color: tc.fg, size: 24),
      OpPhase.attention => Icon(
        Icons.error_outline_rounded,
        color: tc.fg,
        size: 24,
      ),
    };
    final next = op.nextAttemptAt;
    final retryLine = phase == OpPhase.queued && next != null && online
        ? DriverCopy.nextAttempt(Fmt.time(next))
        : null;

    final actions = <Widget>[
      if (phase == OpPhase.queued && online)
        AknButton.ghost(
          label: DriverCopy.opRetry,
          icon: Icons.refresh_rounded,
          size: AknButtonSize.small,
          onPressed: () => unawaited(commands.retry(op.id)),
        ),
      if (phase == OpPhase.attention && onFix != null)
        AknButton(
          label: DriverCopy.opFix,
          icon: Icons.edit_rounded,
          size: AknButtonSize.small,
          onPressed: onFix,
        ),
      if (phase == OpPhase.attention && onFix == null)
        AknButton.secondary(
          label: DriverCopy.opRetry,
          icon: Icons.refresh_rounded,
          size: AknButtonSize.small,
          onPressed: () => unawaited(commands.retry(op.id)),
        ),
      if (phase == OpPhase.attention && onDiscard != null)
        AknButton.ghost(
          label: DriverCopy.opDiscard,
          size: AknButtonSize.small,
          onPressed: onDiscard,
        ),
    ];

    return Semantics(
      container: true,
      liveRegion: true,
      child: AnimatedContainer(
        duration: AknMotion.of(context, AknMotion.base),
        padding: EdgeInsets.all(compact ? 12 : 16),
        decoration: BoxDecoration(
          color: tc.bg,
          borderRadius: AknRadius.card,
          border: Border.all(color: tc.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 36, height: 36, child: Center(child: leading)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: t.bodyStrong.copyWith(color: tc.fg)),
                      if (body != null && !compact) ...[
                        const SizedBox(height: 2),
                        Text(body, style: t.bodySmall.copyWith(color: c.text)),
                      ],
                      if (body != null && compact && phase == OpPhase.attention)
                        Text(body, style: t.bodySmall.copyWith(color: c.text)),
                      if (retryLine != null)
                        Text(
                          retryLine,
                          style: t.caption.copyWith(color: c.text),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ana sayfadaki bekleyen işlem şeridi: "2 işlem gönderilmeyi bekliyor" / "1 işlem ilgilenmenizi
/// bekliyor"; dokununca bekleyen işlemler sayfası açılır.
class DriverOutboxStrip extends ConsumerWidget {
  const DriverOutboxStrip({super.key, this.margin = EdgeInsets.zero});

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summarizeDriverOps(ref.watchDriverOps());
    if (s.waiting == 0 && s.attention == 0) return const SizedBox.shrink();
    final online = ref.watchOnline();
    final attention = s.attention > 0;
    final tone = attention ? AknTone.danger : AknTone.warn;
    final tc = context.akn.tone(tone);
    final text = attention
        ? DriverCopy.opsAttention(s.attention)
        : online
        ? DriverCopy.opsWaiting(s.waiting)
        : DriverCopy.opsWaitingOffline(s.waiting);
    return Padding(
      padding: margin,
      child: Semantics(
        button: true,
        label: text,
        onTap: () => showPendingOpsSheet(context),
        excludeSemantics: true,
        child: Material(
          color: tc.bg,
          shape: RoundedRectangleBorder(
            borderRadius: AknRadius.card,
            side: BorderSide(color: tc.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showPendingOpsSheet(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AknSpace.minTap),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      attention
                          ? Icons.error_outline_rounded
                          : (online
                                ? Icons.cloud_upload_outlined
                                : Icons.schedule_rounded),
                      size: 20,
                      color: tc.fg,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text,
                        style: context.aknText.label.copyWith(color: tc.fg),
                      ),
                    ),
                    Text(
                      DriverCopy.opsShow,
                      style: context.aknText.label.copyWith(color: tc.fg),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 20, color: tc.fg),
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
