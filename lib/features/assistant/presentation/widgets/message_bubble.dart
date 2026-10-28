import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/ui.dart';
import '../../copy.dart';
import '../../data/assistant_models.dart';
import 'assistant_avatar.dart';

/// Sohbet satırı (tasarım v3): kullanıcı sağda turuncu degrade balonda (r20, kuyruk köşesi 6; beyaz yazı —
/// degrade koyu turuncudan Pas'a, yazı her yerinde en az 4,5:1), altında sıcak bir parıltı; asistan solda
/// 28 px logo karosuyla beyaz kart balonda (r20, kart gölgesi; koyu temada ince çizgi). Hata yanıtı
/// kırmızı kuyuda simge + ink metin, geri bildirimsiz; gönderilemeyen mesajda "Tekrar dene". Asistan
/// yanıtı uzun basınca kopyalanır.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onRate,
  });

  final ChatMessage message;
  final VoidCallback? onRetry;

  /// Geri bildirim (true = yararlı).
  final ValueChanged<bool>? onRate;

  /// Kullanıcı balonunun degradesi: açıkta #CC4708 → Pas, koyuda Pas → bandın ortası (beyaz yazı AA).
  static LinearGradient userGradient(AknColors c) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [c.brandFillPressed, c.isDark ? c.heroMid : c.brandInk],
  );

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final m = message;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.8;

    if (m.isUser) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Semantics(
                label: '${AssistantCopy.you}: ${m.text}',
                excludeSemantics: true,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
                  decoration: BoxDecoration(
                    gradient: userGradient(c),
                    borderRadius: const BorderRadiusDirectional.only(
                      topStart: Radius.circular(20),
                      topEnd: Radius.circular(20),
                      bottomStart: Radius.circular(20),
                      bottomEnd: Radius.circular(6),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: c.brandFill.withValues(
                          alpha: c.isDark ? 0.22 : 0.3,
                        ),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                        spreadRadius: -6,
                      ),
                    ],
                  ),
                  child: Text(
                    m.text,
                    style: t.body.copyWith(color: c.onBrandFill),
                  ),
                ),
              ),
              if (m.failed)
                _FailedRow(reason: m.failureMessage, onRetry: onRetry),
            ],
          ),
        ),
      );
    }

    final error = m.isError;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth + 38),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 2),
              child: AssistantAvatar(size: 28),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    label: '${AssistantCopy.assistant}: ${m.text}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onLongPress: error
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(text: m.text),
                              );
                              AknHaptics.selection();
                              AppToast.info(AssistantCopy.copied);
                            },
                      child: AssistantBubbleSurface(
                        tone: error ? AknTone.danger : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (error) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(
                                  PhosphorIconsFill.warningCircle,
                                  size: 18,
                                  color: c.danger.fg,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                m.text,
                                style: t.body.copyWith(color: c.ink),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (m.canRate && onRate != null)
                    _FeedbackRow(feedback: m.feedback, onRate: onRate!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asistan balonunun yüzeyi (tasarım v3): beyaz kart, r20 ve avatar tarafında 6'lık kuyruk köşesi, kart
/// gölgesi (koyu temada ince çizgi). [tone] verilirse (hata) tonun kuyusu ve çizgisi.
class AssistantBubbleSurface extends StatelessWidget {
  const AssistantBubbleSurface({super.key, required this.child, this.tone});

  final Widget child;
  final AknTone? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final tc = tone == null ? null : c.tone(tone!);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
      decoration: BoxDecoration(
        color: tc?.bg ?? c.surface,
        borderRadius: const BorderRadiusDirectional.only(
          topStart: Radius.circular(20),
          topEnd: Radius.circular(20),
          bottomStart: Radius.circular(6),
          bottomEnd: Radius.circular(20),
        ),
        border: tc != null
            ? Border.all(color: tc.line)
            : c.isDark
            ? Border.all(color: c.line)
            : null,
        boxShadow: tc == null ? AknShadows.card(c) : null,
      ),
      child: child,
    );
  }
}

class _FailedRow extends StatelessWidget {
  const _FailedRow({this.reason, this.onRetry});

  final String? reason;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (reason != null)
            Text(
              reason!,
              textAlign: TextAlign.end,
              style: t.caption.copyWith(color: c.danger.fg),
            ),
          if (onRetry != null)
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  PhosphorIconsFill.warningCircle,
                  size: 16,
                  color: c.danger.fg,
                ),
                const SizedBox(width: 6),
                Text(
                  AssistantCopy.sendFailed,
                  style: t.label.copyWith(color: c.danger.fg),
                ),
                const SizedBox(width: 4),
                AknButton.ghost(
                  label: AssistantCopy.retry,
                  icon: PhosphorIconsRegular.arrowClockwise,
                  size: AknButtonSize.small,
                  onPressed: onRetry,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _FeedbackRow extends StatelessWidget {
  const _FeedbackRow({required this.feedback, required this.onRate});

  final ChatFeedback feedback;
  final ValueChanged<bool> onRate;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final done =
        feedback == ChatFeedback.helpful || feedback == ChatFeedback.notHelpful;
    return AnimatedSwitcher(
      duration: AknMotion.of(context, AknMotion.base),
      switchInCurve: AknMotion.pop,
      switchOutCurve: AknMotion.exit,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1).animate(a),
          alignment: Alignment.centerLeft,
          child: child,
        ),
      ),
      child: done
          ? Padding(
              key: const ValueKey('thanks'),
              padding: const EdgeInsets.only(top: 8, left: 6),
              child: Semantics(
                liveRegion: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      feedback == ChatFeedback.helpful
                          ? PhosphorIconsFill.thumbsUp
                          : PhosphorIconsFill.thumbsDown,
                      size: 16,
                      color: c.brand,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        AssistantCopy.thanks,
                        style: t.caption.copyWith(color: c.dim),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Wrap(
              key: const ValueKey('ask'),
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 2),
                  child: Text(
                    AssistantCopy.helpfulQuestion,
                    style: t.caption.copyWith(color: c.dim),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AknIconButton(
                      icon: PhosphorIconsRegular.thumbsUp,
                      size: 20,
                      semanticLabel: AssistantCopy.helpful,
                      color: c.dim,
                      onPressed: feedback == ChatFeedback.sending
                          ? null
                          : () => onRate(true),
                    ),
                    AknIconButton(
                      icon: PhosphorIconsRegular.thumbsDown,
                      size: 20,
                      semanticLabel: AssistantCopy.notHelpful,
                      color: c.dim,
                      onPressed: feedback == ChatFeedback.sending
                          ? null
                          : () => onRate(false),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// "Yazıyor" balonu (tasarım v3): 28 px logo karosunun yanında beyaz kart balon; içinde üç nokta sırayla
/// zıplar (ortam hareketi, [AknAmbient]; testlerde ve azaltılmış harekette durur). Balon açılırken
/// küçükten büyüyerek belirir. Azaltılmış harekette ya da ekran okuyucu gezintisinde duran "Yazıyor…"
/// metni.
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  /// Açılış: 0,85'ten taşarak büyür ve belirir (tek seferlik).
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  bool _calm = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mq = MediaQuery.maybeOf(context);
    _calm =
        (mq?.disableAnimations ?? false) || (mq?.accessibleNavigation ?? false);
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _in.value = 1;
    } else {
      _in.forward();
    }
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Semantics(
      liveRegion: true,
      label: AssistantCopy.typing,
      excludeSemantics: true,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 2),
              child: AssistantAvatar(size: 28, typing: true),
            ),
            const SizedBox(width: 10),
            AnimatedBuilder(
              animation: _in,
              builder: (context, child) {
                final v = _in.value;
                return Opacity(
                  opacity: (v * 2.5).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.85 + 0.15 * AknMotion.pop.transform(v),
                    alignment: AlignmentDirectional.bottomStart,
                    child: child,
                  ),
                );
              },
              child: AssistantBubbleSurface(
                child: _calm
                    ? Text(
                        AssistantCopy.typingStatic,
                        style: t.bodySmall.copyWith(color: c.dim),
                      )
                    : SizedBox(
                        height: 22,
                        child: AknAmbient(
                          period: const Duration(milliseconds: 1100),
                          curve: Curves.linear,
                          builder: (context, phase, _) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < 3; i++) ...[
                                if (i > 0) const SizedBox(width: 6),
                                _Dot(phase: phase, index: i),
                              ],
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Zıplayan nokta: döngünün kendine düşen diliminde 5 px yükselip iner, yükselirken turunculaşır.
class _Dot extends StatelessWidget {
  const _Dot({required this.phase, required this.index});

  final double phase;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    // Her nokta döngünün %16'sı kadar geriden gelir; zıplama döngünün ilk %45'inde.
    final local = (phase - index * 0.16) % 1.0;
    final hop = local < 0.45 ? math.sin(local / 0.45 * math.pi) : 0.0;
    return Transform.translate(
      offset: Offset(0, -5 * hop),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Color.lerp(c.dim, c.brand, hop),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
