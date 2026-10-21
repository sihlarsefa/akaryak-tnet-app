import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/ui.dart';
import '../../copy.dart';
import '../../data/assistant_models.dart';
import 'assistant_avatar.dart';

/// Sohbet balonu: kullanıcı sağda (marka tonunda), asistan solda (LogoMark ile). Hata yanıtı tehlike
/// tonunda ve geri bildirimsiz; gönderilemeyen mesajda "Tekrar dene". Asistan yanıtı uzun basınca
/// kopyalanır.
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

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final m = message;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.82;

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
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  decoration: BoxDecoration(
                    color: c.brandSoft,
                    border: Border.all(color: c.brandLine),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(4),
                    ),
                  ),
                  child: Text(m.text, style: t.body.copyWith(color: c.ink)),
                ),
              ),
              if (m.failed)
                _FailedRow(reason: m.failureMessage, onRetry: onRetry),
            ],
          ),
        ),
      );
    }

    final tone = m.isError ? c.danger : null;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth + 40),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: AssistantAvatar(size: 30),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    label: '${AssistantCopy.assistant}: ${m.text}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onLongPress: m.isError
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(text: m.text),
                              );
                              AknHaptics.selection();
                              AppToast.info(AssistantCopy.copied);
                            },
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        decoration: BoxDecoration(
                          color: tone?.bg ?? c.surface,
                          border: Border.all(color: tone?.line ?? c.line),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(16),
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (m.isError) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.error_outline_rounded,
                                  size: 18,
                                  color: tone!.fg,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                m.text,
                                style: t.body.copyWith(color: c.text),
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
            TextButton.icon(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: c.danger.fg),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(
                '${AssistantCopy.sendFailed} · ${AssistantCopy.retry}',
              ),
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
      child: done
          ? Padding(
              key: const ValueKey('thanks'),
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Semantics(
                liveRegion: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      feedback == ChatFeedback.helpful
                          ? Icons.thumb_up_rounded
                          : Icons.thumb_down_rounded,
                      size: 16,
                      color: c.dim,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(AssistantCopy.thanks, style: t.caption),
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
                  child: Text(AssistantCopy.helpfulQuestion, style: t.caption),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AknIconButton(
                      icon: Icons.thumb_up_outlined,
                      size: 20,
                      semanticLabel: AssistantCopy.helpful,
                      color: c.dim,
                      onPressed: feedback == ChatFeedback.sending
                          ? null
                          : () => onRate(true),
                    ),
                    AknIconButton(
                      icon: Icons.thumb_down_outlined,
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

/// "Yazıyor" balonu: LogoMark okları çizilirken üç nokta sakin bir dalgayla belirir. Azaltılmış
/// harekette duran "Yazıyor…" metni.
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  bool _calm = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mq = MediaQuery.maybeOf(context);
    _calm =
        (mq?.disableAnimations ?? false) || (mq?.accessibleNavigation ?? false);
    if (_calm) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AssistantAvatar(size: 30, typing: true),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.line),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: _calm
                  ? Text(AssistantCopy.typingStatic, style: t.bodySmall)
                  : AnimatedBuilder(
                      animation: _c,
                      builder: (context, _) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < 3; i++) ...[
                            if (i > 0) const SizedBox(width: 5),
                            Opacity(
                              opacity: _dot(i),
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: c.dim,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  double _dot(int i) {
    final phase = (_c.value - i * 0.18) % 1.0;
    return 0.3 + 0.7 * (0.5 + 0.5 * math.sin(phase * 2 * math.pi)).clamp(0, 1);
  }
}
