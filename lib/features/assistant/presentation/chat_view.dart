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
      padding: const EdgeInsets.fromLTRB(AknSpace.page, 16, AknSpace.page, 16),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, i) {
        if (state.typing && i == 0) {
          return const TypingBubble();
        }
        final index = state.typing ? i - 1 : i;
        final m = items[index];
        final bubble = MessageBubble(
          key: ValueKey(m.id),
          message: m,
          onRetry: m.failed ? () => onRetry(m) : null,
          onRate: (helpful) => onRate(m, helpful),
        );
        // Hareket yok (§8.3): yeni mesaj olduğu yerde belirir.
        return bubble;
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
    // Sola dayalı karşılama (§4.2): 40 px logo karosu, `display` selam, tek cümle; örnek sorular
    // çip olarak (Beton, r10, ink 600).
    return ListView(
      padding: const EdgeInsets.fromLTRB(AknSpace.page, 20, AknSpace.page, 16),
      children: [
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: AssistantAvatar(size: 40),
        ),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text(
            AssistantCopy.greeting(first),
            style: t.display.copyWith(color: c.ink),
            textScaler: MediaQuery.textScalerOf(
              context,
            ).clamp(maxScaleFactor: 1.6),
          ),
        ),
        const SizedBox(height: 8),
        Text(AssistantCopy.intro, style: t.body.copyWith(color: c.dim)),
        const SizedBox(height: 24),
        Text(
          AssistantCopy.starters,
          style: t.label.copyWith(fontWeight: FontWeight.w600, color: c.dim),
        ),
        const SizedBox(height: 8),
        if (groups == null)
          const Shimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 36, width: 240, radius: 10),
                SizedBox(height: 8),
                SkeletonBox(height: 36, width: 200, radius: 10),
              ],
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 0,
            children: [
              for (final q in questions)
                _StarterChip(
                  question: q,
                  onTap: enabled ? () => onAsk(q) : null,
                ),
            ],
          ),
      ],
    );
  }
}

/// Örnek soru çipi (§6.11): Beton dolgu, r10, ink 14/18 600; 36 px görünür, 48 px dokunma alanı.
class _StarterChip extends StatelessWidget {
  const _StarterChip({required this.question, this.onTap});

  final String question;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: question,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: AknRadius.chip,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  question,
                  style: t.label.copyWith(
                    fontSize: 14,
                    height: 18 / 14,
                    fontWeight: FontWeight.w600,
                    color: onTap == null ? c.dim : c.ink,
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
