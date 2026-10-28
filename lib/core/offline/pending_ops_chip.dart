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
///
/// Tasarım v3: tonlu yumuşak kuyu (hap, 1 px ton çizgisi); belirirken solup büyüyerek gelir, durum
/// değişince simge ve metin yumuşakça yer değiştirir, gönderilmeyi beklerken yükleme oku hafifçe
/// süzülür (ortam hareketi); basınca küçülür.
class PendingOpsChip extends ConsumerWidget {
  const PendingOpsChip({super.key, this.margin = EdgeInsets.zero});

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = ref.watch(pendingOpsCountProvider);
    final attention = ref.watch(attentionOpsCountProvider);
    final hidden = waiting == 0 && attention == 0;
    Widget child = const SizedBox.shrink(key: ValueKey('none'));
    if (!hidden) {
      final offline = !ref.watch(isOnlineProvider);
      final tone = attention > 0 ? AknTone.danger : AknTone.warn;
      final text = attention > 0
          ? '$attention işlem ilgilenmenizi bekliyor'
          : offline
          ? '$waiting işlem bağlantı gelince gönderilecek'
          : '$waiting işlem gönderilmeyi bekliyor';
      child = Padding(
        key: const ValueKey('chip'),
        padding: margin,
        child: _Chip(
          text: text,
          tone: tone,
          attention: attention > 0,
          bob: attention == 0 && !offline,
        ),
      );
    }
    return AnimatedSwitcher(
      duration: AknMotion.of(context, AknMotion.base),
      switchInCurve: AknMotion.emphasizedCurve,
      switchOutCurve: AknMotion.exit,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(a),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.text,
    required this.tone,
    required this.attention,
    required this.bob,
  });

  final String text;
  final AknTone tone;
  final bool attention;

  /// The upload arrow drifts while operations wait to be sent.
  final bool bob;

  @override
  Widget build(BuildContext context) {
    final colors = context.akn.tone(tone);
    final base = AknMotion.of(context, AknMotion.base);
    Widget glyph = Icon(
      attention
          ? PhosphorIconsRegular.warningCircle
          : PhosphorIconsRegular.cloudArrowUp,
      size: 18,
      color: colors.fg,
    );
    if (bob) {
      glyph = AknAmbient(
        period: AknMotion.breathe,
        reverse: true,
        restValue: 0.5,
        child: glyph,
        builder: (context, t, child) =>
            Transform.translate(offset: Offset(0, 1.5 - 3 * t), child: child),
      );
    }
    return Semantics(
      button: true,
      label: text,
      child: PressScale(
        child: Material(
          color: colors.bg,
          shape: StadiumBorder(side: BorderSide(color: colors.line)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            splashFactory: NoSplash.splashFactory,
            highlightColor: colors.line.withValues(alpha: 0.5),
            onTap: () {
              AknHaptics.selection();
              unawaited(showPendingOpsSheet(context));
            },
            // 48 dp dokunma hedefi (spec C.7).
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    AknDriverMode.maybeOf(context)?.minTap ?? AknSpace.minTap,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: base,
                      switchInCurve: AknMotion.pop,
                      transitionBuilder: (child, a) =>
                          ScaleTransition(scale: a, child: child),
                      child: KeyedSubtree(
                        key: ValueKey(attention),
                        child: glyph,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: AnimatedSwitcher(
                        duration: base,
                        child: Text(
                          text,
                          key: ValueKey(text),
                          style: context.aknText.label.copyWith(
                            color: colors.fg,
                          ),
                        ),
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
        for (final (i, op) in ops.indexed)
          _Arrive(
            index: i,
            child: AknListTile(
              leadingIcon: op.status == OutboxStatus.needsAttention
                  ? PhosphorIconsRegular.warningCircle
                  : PhosphorIconsRegular.clock,
              leadingTone: op.status == OutboxStatus.needsAttention
                  ? AknTone.danger
                  : AknTone.warn,
              title: op.label ?? op.type,
              subtitle: [
                [
                  op.status.label,
                  if (op.nextAttemptAt != null &&
                      op.status == OutboxStatus.failed)
                    'sonraki deneme ${Fmt.time(op.nextAttemptAt)}',
                ].join(', '),
                if (op.lastError != null) op.lastError!,
              ].join('\n'),
              subtitleMaxLines: 4,
              padding: const EdgeInsets.symmetric(vertical: 8),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _OpAction(
                    tooltip: 'Tekrar dene',
                    icon: PhosphorIconsRegular.arrowClockwise,
                    onPressed: op.status == OutboxStatus.sending
                        ? null
                        : () => unawaited(runner.retry(op.id)),
                  ),
                  if (op.status == OutboxStatus.needsAttention)
                    _OpAction(
                      tooltip: 'Vazgeç',
                      icon: PhosphorIconsRegular.trash,
                      danger: true,
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
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A row action: a round 40 px well button (48 px target) with a light
/// haptic.
class _OpAction extends StatelessWidget {
  const _OpAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final press = onPressed;
    final target = AknDriverMode.maybeOf(context)?.minTap ?? AknSpace.minTap;
    return IconButton(
      tooltip: tooltip,
      onPressed: press == null
          ? null
          : () {
              AknHaptics.light();
              press();
            },
      constraints: BoxConstraints(minWidth: target, minHeight: target),
      style: IconButton.styleFrom(
        backgroundColor: danger ? c.danger.bg : c.surfaceAlt,
        disabledBackgroundColor: c.surfaceAlt,
        foregroundColor: danger ? c.danger.fg : c.ink,
        disabledForegroundColor: c.faint,
        fixedSize: const Size(40, 40),
        minimumSize: const Size(40, 40),
        shape: const CircleBorder(),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}

/// A row's entrance in the sheet: fades in and rises 12 px, 55 ms after the
/// previous row (capped). The structure never changes, so the row inside is
/// never rebuilt from scratch.
class _Arrive extends StatelessWidget {
  const _Arrive({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const each = 420;
    final delay = 55 * index.clamp(0, 8);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AknMotion.of(context, Duration(milliseconds: each + delay)),
      curve: Interval(
        delay / (each + delay),
        1,
        curve: AknMotion.emphasizedCurve,
      ),
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - v)),
          child: child,
        ),
      ),
    );
  }
}
