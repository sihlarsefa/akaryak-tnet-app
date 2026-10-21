import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/offline/connectivity.dart';
import '../../../core/ui/ui.dart';
import '../../profile/api.dart';
import '../application/assistant_chat_controller.dart';
import '../application/assistant_gate.dart';
import '../copy.dart';
import '../data/assistant_models.dart';
import 'widgets/assistant_avatar.dart';
import 'widgets/composer.dart';
import 'widgets/message_bubble.dart';

/// Sohbet (spec A.6): karşılama + persona başlangıç soruları, mesaj balonları, "yazıyor", geri
/// bildirim, yazma alanı. Yeni yanıt ekran okuyucuya duyurulur.
class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key, required this.gate});

  final GateReady gate;

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final _composer = GlobalKey<ChatComposerState>();

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(assistantChatProvider.notifier).ensureSuggestions(),
    );
  }

  void _announce(String message) {
    final view = View.maybeOf(context);
    if (view == null) return;
    unawaited(
      SemanticsService.sendAnnouncement(view, message, TextDirection.ltr),
    );
  }

  Future<void> _send(String text) =>
      ref.read(assistantChatProvider.notifier).send(text);

  Future<void> _rate(ChatMessage m, bool helpful) async {
    String? comment;
    if (!helpful) {
      comment = await showAppSheet<String>(
        context: context,
        title: AssistantCopy.feedbackTitle,
        builder: (_) => const _FeedbackSheet(),
      );
      if (comment == null) return;
    }
    final f = await ref
        .read(assistantChatProvider.notifier)
        .rate(m.id, helpful: helpful, comment: comment);
    if (f != null) {
      AppToast.error(f.message);
    } else {
      _announce(AssistantCopy.thanks);
    }
  }

  void _openKvkk() {
    final open = ref.read(profileLinkOpenerProvider);
    final target =
        SupportUris.web(widget.gate.disclosure?.legalUrl) ??
        ref.read(legalUrisProvider).ai;
    unawaited(
      open(target).then((ok) {
        if (!ok) AppToast.error(AssistantCopy.linkFailed);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(assistantChatProvider);
    final online = ref.watch(isOnlineProvider);
    ref.listen<ChatState>(assistantChatProvider, (prev, next) {
      final before = prev?.messages.length ?? 0;
      if (next.messages.length > before) {
        final last = next.messages.last;
        if (!last.isUser) {
          _announce('${AssistantCopy.assistant}: ${last.text}');
        }
      }
    });

    return Column(
      children: [
        Expanded(
          child: s.isEmpty
              ? _Welcome(
                  suggestions: s.suggestions,
                  onAsk: (q) => unawaited(_send(q)),
                  enabled: !s.typing && online,
                )
              : _Messages(
                  state: s,
                  onRetry: (m) => unawaited(
                    ref.read(assistantChatProvider.notifier).retry(m.id),
                  ),
                  onRate: (m, helpful) => unawaited(_rate(m, helpful)),
                ),
        ),
        ChatComposer(
          key: _composer,
          enabled: !s.typing,
          offline: !online,
          cooldownUntil: s.cooldownUntil,
          onSend: (text) => unawaited(_send(text)),
          onOpenKvkk: _openKvkk,
        ),
      ],
    );
  }
}

class _Messages extends StatelessWidget {
  const _Messages({
    required this.state,
    required this.onRetry,
    required this.onRate,
  });

  final ChatState state;
  final ValueChanged<ChatMessage> onRetry;
  final void Function(ChatMessage m, bool helpful) onRate;

  @override
  Widget build(BuildContext context) {
    final items = state.messages.reversed.toList();
    final count = items.length + (state.typing ? 1 : 0);
    return ListView.separated(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        if (state.typing && i == 0) {
          return const FadeUp(child: TypingBubble());
        }
        final index = state.typing ? i - 1 : i;
        final m = items[index];
        final bubble = MessageBubble(
          key: ValueKey(m.id),
          message: m,
          onRetry: m.failed ? () => onRetry(m) : null,
          onRate: (helpful) => onRate(m, helpful),
        );
        // Yalnızca en yeni mesaj belirir; kaydırınca yeniden kurulan eski balonlar oynamaz.
        return index == 0
            ? FadeUp(key: ValueKey('in-${m.id}'), child: bubble)
            : bubble;
      },
    );
  }
}

class _Welcome extends ConsumerWidget {
  const _Welcome({
    required this.suggestions,
    required this.onAsk,
    required this.enabled,
  });

  final List<SuggestionGroup>? suggestions;
  final ValueChanged<String> onAsk;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.akn;
    final t = context.aknText;
    final name = ref.watch(
      sessionControllerProvider.select((s) => s.access?.displayName),
    );
    final first = name?.trim().split(RegExp(r'\s+')).first;
    final groups = suggestions;
    final questions = [
      for (final g in groups ?? const <SuggestionGroup>[]) ...g.questions,
    ].take(6).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      children: [
        const Center(child: AssistantAvatar(size: 56)),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            AssistantCopy.greeting(first),
            style: t.title,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AssistantCopy.intro,
          style: t.body.copyWith(color: c.dim),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Text(AssistantCopy.starters, style: t.label.copyWith(color: c.text)),
        const SizedBox(height: 10),
        if (groups == null)
          const Shimmer(
            child: Column(
              children: [
                SkeletonBox(height: 48, radius: 12),
                SizedBox(height: 8),
                SkeletonBox(height: 48, radius: 12),
              ],
            ),
          )
        else
          for (var i = 0; i < questions.length; i++)
            StaggerItem(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _StarterChip(
                  question: questions[i],
                  onTap: enabled ? () => onAsk(questions[i]) : null,
                ),
              ),
            ),
      ],
    );
  }
}

class _StarterChip extends StatelessWidget {
  const _StarterChip({required this.question, this.onTap});

  final String question;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return AknCard(
      onTap: onTap,
      shadow: false,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      semanticLabel: question,
      child: Row(
        children: [
          Icon(Icons.chat_bubble_outline_rounded, size: 18, color: c.brand),
          const SizedBox(width: 10),
          Expanded(child: Text(question, style: t.bodyStrong)),
          Icon(Icons.north_east_rounded, size: 18, color: c.dim),
        ],
      ),
    );
  }
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet();

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AknTextField(
          controller: _text,
          label: AssistantCopy.feedbackTitle,
          helper: AssistantCopy.feedbackHint,
          maxLines: 4,
          minLines: 2,
          maxLength: 500,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 16),
        AknButton(
          label: AssistantCopy.feedbackSend,
          expand: true,
          onPressed: () => Navigator.of(context).pop(_text.text.trim()),
        ),
        AknButton.ghost(
          label: AssistantCopy.feedbackSkip,
          expand: true,
          onPressed: () => Navigator.of(context).pop(''),
        ),
      ],
    );
  }
}
