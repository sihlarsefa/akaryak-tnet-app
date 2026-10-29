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
import 'entrance.dart';

/// Bekleyen işlemin kullanıcıya görünen aşaması (spec C.4a "Queued vs sent").
enum OpPhase {
  /// Şu an gönderiliyor (çevrimiçi, ilk deneme).
  sending,

  /// Telefonda kayıtlı; bağlantı gelince gönderilecek (çevrimdışı, ertelendi, bağımlı işlem
  /// bekleniyor).
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

/// Kart üstündeki işlem çipi (tasarım v3 §4 durum hapı): "Gönderilmeyi bekliyor" (uyarı),
/// "Gönderiliyor" (dönen » ile gri hap), sunucu onaylayınca kısa bir başarı anı (yeşil hapta
/// çizilen onay, "Gönderildi"), reddedilince "İlgilenmeniz gerekiyor". Aşama değişince çipler
/// yumuşakça yer değiştirir.
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
      ),
      OpPhase.attention => const _PhaseChip(
        key: ValueKey('attention'),
        label: DriverCopy.opAttention,
        tone: AknTone.danger,
      ),
    };
    // Aşama değişince eski çip söner, yenisi hafifçe büyüyerek gelir (v3 §5).
    return AnimatedSwitcher(
      duration: AknMotion.of(context, AknMotion.base),
      switchInCurve: AknMotion.spring,
      switchOutCurve: AknMotion.exit,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1).animate(a),
          alignment: AlignmentDirectional.centerStart.resolve(
            Directionality.of(context),
          ),
          child: child,
        ),
      ),
      child: chip,
    );
  }
}

/// İşlem lambası (§4 durum hapı): uyarı / tehlike aşamaları çekirdek lambadır; gönderilirken aynı
/// hap biçiminde gri kuyu, noktanın yerinde dönen ok başı.
class _PhaseChip extends StatelessWidget {
  const _PhaseChip({
    super.key,
    required this.label,
    required this.tone,
    this.spinner = false,
  });

  final String label;
  final AknTone tone;
  final bool spinner;

  @override
  Widget build(BuildContext context) {
    if (!spinner) {
      return AknLamp(label: label, tone: tone, semanticLabel: label);
    }
    final c = context.akn;
    final tc = c.tone(tone);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: _Pill(
        background: tc.bg,
        leading: ChevronSpinner(size: 12, color: tc.fg, semanticLabel: null),
        label: label,
        color: tc.fg,
      ),
    );
  }
}

/// Başarı anı: yeşil hapta küçük çizilen onay ve "Gönderildi".
class _SentChip extends StatelessWidget {
  const _SentChip({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return Semantics(
      label: DriverCopy.opSent,
      excludeSemantics: true,
      child: _Pill(
        background: c.ok.bg,
        leading: const SuccessCheck(
          size: 16,
          haptic: false,
          burst: false,
          semanticLabel: null,
        ),
        label: DriverCopy.opSent,
        color: c.ok.fg,
      ),
    );
  }
}

/// Lamba ölçüsünde hap: 26 px yüksek (yazıyla büyür), solda işaret, 12/16 700 etiket.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.background,
    required this.leading,
    required this.label,
    required this.color,
  });

  final Color background;
  final Widget leading;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AknRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: t.captionStrong.copyWith(
                fontSize: 12,
                height: 16 / 12,
                letterSpacing: 0.1,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// İşlemin sonucu (ayrıntı ekranının alt çubuğu ve teslim sonucu; tasarım v3 §4 yumuşak tonlu
/// kuyu): gönderiliyor (gri kuyu, dönen ») / kaydedildi (uyarı tonu + saat simgesi, başarı işareti
/// asla) / gönderildi (yeşil kuyuda çizilen başarı işareti) / reddedildi (kırmızı kuyu, sunucu
/// mesajı + eylemler). Aşama değişince zemin rengi kayarak değişir, simge yaylanarak yer
/// değiştirir.
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
        deliver ? DriverCopy.queuedDeliverTitle : DriverCopy.queuedStartTitle,
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
        key: const ValueKey('sending'),
        size: 20,
        color: c.ink,
        semanticLabel: null,
      ),
      OpPhase.sent => const SuccessCheck(
        key: ValueKey('sent'),
        size: 32,
        burst: false,
        semanticLabel: null,
      ),
      OpPhase.queued => Icon(
        PhosphorIconsRegular.clock,
        key: const ValueKey('queued'),
        color: tc.fg,
        size: 22,
      ),
      OpPhase.attention => Icon(
        PhosphorIconsRegular.warningCircle,
        key: const ValueKey('attention'),
        color: tc.fg,
        size: 22,
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
          icon: PhosphorIconsRegular.arrowClockwise,
          size: AknButtonSize.small,
          onPressed: () => unawaited(commands.retry(op.id)),
        ),
      if (phase == OpPhase.attention && onFix != null)
        AknButton(
          label: DriverCopy.opFix,
          icon: PhosphorIconsRegular.pencilSimple,
          size: AknButtonSize.small,
          onPressed: onFix,
        ),
      if (phase == OpPhase.attention && onFix == null)
        AknButton.secondary(
          label: DriverCopy.opRetry,
          icon: PhosphorIconsRegular.arrowClockwise,
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
    final duration = AknMotion.of(context, AknMotion.base);

    return Semantics(
      container: true,
      liveRegion: true,
      child: AnimatedContainer(
        duration: duration,
        curve: AknMotion.standard,
        padding: EdgeInsets.fromLTRB(
          12,
          compact ? 12 : 14,
          14,
          compact ? 12 : 14,
        ),
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
                // İşaret beyaz bir dairede: tonlu kuyunun üstünde net okunur.
                AnimatedContainer(
                  duration: duration,
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.isDark ? c.surfaceRaised : c.surface,
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedSwitcher(
                    duration: AknMotion.of(context, AknMotion.iconSwap),
                    switchInCurve: AknMotion.pop,
                    transitionBuilder: (child, a) =>
                        ScaleTransition(scale: a, child: child),
                    child: leading,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: t.bodyStrong.copyWith(
                            color: c.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (body != null &&
                            (!compact || phase == OpPhase.attention)) ...[
                          const SizedBox(height: 2),
                          Text(body, style: t.bodySmall.copyWith(color: c.ink)),
                        ],
                        if (retryLine != null)
                          Text(
                            retryLine,
                            style: t.caption.copyWith(
                              color: c.dim,
                              fontFeatures: AknNumerals.tabular,
                            ),
                          ),
                      ],
                    ),
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

/// Ana sayfadaki bekleyen işlem şeridi (tasarım v3 §4 yumuşak tonlu kuyu): "2 işlem gönderilmeyi
/// bekliyor" / "1 işlem ilgilenmenizi bekliyor"; tonun simgesi beyaz dairede (ilgi bekleyende
/// uygulamada hafifçe nefes alır), sağda "Göster" ve ok. Basınca küçülür; dokununca bekleyen
/// işlemler sayfası açılır. Belirince yumuşakça yükselir.
class DriverOutboxStrip extends ConsumerWidget {
  const DriverOutboxStrip({
    super.key,
    this.margin = EdgeInsets.zero,
    this.showOfflineWaiting = true,
  });

  final EdgeInsetsGeometry margin;

  /// Çevrimdışıyken bekleyenler de gösterilsin mi (ana sayfada eşitleme satırı söyler: false).
  final bool showOfflineWaiting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summarizeDriverOps(ref.watchDriverOps());
    if (s.waiting == 0 && s.attention == 0) return const SizedBox.shrink();
    final online = ref.watchOnline();
    final attention = s.attention > 0;
    if (!attention && !online && !showOfflineWaiting) {
      return const SizedBox.shrink();
    }
    final tone = attention ? AknTone.danger : AknTone.warn;
    final c = context.akn;
    final t = context.aknText;
    final tc = c.tone(tone);
    final text = attention
        ? DriverCopy.opsAttention(s.attention)
        : online
        ? DriverCopy.opsWaiting(s.waiting)
        : DriverCopy.opsWaitingOffline(s.waiting);
    final icon = Icon(
      attention
          ? PhosphorIconsRegular.warningCircle
          : (online
                ? PhosphorIconsRegular.cloudArrowUp
                : PhosphorIconsRegular.clock),
      size: 20,
      color: tc.fg,
    );
    final glyph = SizedBox.square(
      dimension: 36,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.isDark ? c.surfaceRaised : c.surface,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: attention
              ? AknAmbient(
                  period: AknMotion.breathe,
                  reverse: true,
                  child: icon,
                  builder: (context, v, child) =>
                      Transform.scale(scale: 1 + 0.12 * v, child: child),
                )
              : icon,
        ),
      ),
    );
    return Padding(
      padding: margin,
      child: DriverFadeUp(
        offset: 10,
        child: Semantics(
          button: true,
          label: text,
          onTap: () => showPendingOpsSheet(context),
          excludeSemantics: true,
          child: PressScale(
            child: Material(
              color: tc.bg,
              shape: RoundedRectangleBorder(
                borderRadius: AknRadius.card,
                side: BorderSide(color: tc.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  AknHaptics.selection();
                  showPendingOpsSheet(context);
                },
                splashFactory: NoSplash.splashFactory,
                highlightColor: tc.line.withValues(alpha: 0.5),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: context.minTap),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      10,
                      10,
                      8,
                      10,
                    ),
                    child: Row(
                      children: [
                        glyph,
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            text,
                            style: t.label.copyWith(color: c.ink),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DriverCopy.opsShow,
                          style: t.label.copyWith(
                            color: c.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Icon(
                          PhosphorIconsRegular.caretRight,
                          size: 18,
                          color: c.ink,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
