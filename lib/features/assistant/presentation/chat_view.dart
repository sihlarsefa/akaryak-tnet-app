import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  /// Buzlu yazma alanının yüksekliği: liste altından kayar, son mesaj alanın hemen üstünde durur.
  double _composerHeight = 132;

  void _onComposerSize(Size size) {
    if (!mounted || (size.height - _composerHeight).abs() < 0.5) return;
    setState(() => _composerHeight = size.height);
  }

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

    // Tasarım v3: mesajlar buzlu yazma alanının altından kayar (alan içeriğin üstünde yüzer); liste
    // altta alanın yüksekliği kadar boşluk bırakır.
    final bottom = _composerHeight + 12;
    return Stack(
      children: [
        Positioned.fill(
          child: FadeThroughSwitcher(
            child: s.isEmpty
                ? _Welcome(
                    key: const ValueKey('welcome'),
                    suggestions: s.suggestions,
                    onAsk: (q) => unawaited(_send(q)),
                    enabled: !s.typing && online,
                    bottomInset: bottom,
                  )
                : _Messages(
                    key: const ValueKey('messages'),
                    state: s,
                    bottomInset: bottom,
                    onRetry: (m) => unawaited(
                      ref.read(assistantChatProvider.notifier).retry(m.id),
                    ),
                    onRate: (m, helpful) => unawaited(_rate(m, helpful)),
                  ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _SizeReporter(
            onSize: _onComposerSize,
            child: ChatComposer(
              key: _composer,
              enabled: !s.typing,
              offline: !online,
              cooldownUntil: s.cooldownUntil,
              onSend: (text) => unawaited(_send(text)),
              onOpenKvkk: _openKvkk,
            ),
          ),
        ),
      ],
    );
  }
}

/// Çocuğunun boyutunu her yerleşimden sonra (değiştiyse) bildirir.
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) => renderObject.onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final s = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(s));
  }
}

class _Messages extends StatelessWidget {
  const _Messages({
    super.key,
    required this.state,
    required this.bottomInset,
    required this.onRetry,
    required this.onRate,
  });

  final ChatState state;
  final double bottomInset;
  final ValueChanged<ChatMessage> onRetry;
  final void Function(ChatMessage m, bool helpful) onRate;

  static const _typingKey = ValueKey<String>('typing');

  @override
  Widget build(BuildContext context) {
    final items = state.messages.reversed.toList();
    final count = items.length + (state.typing ? 1 : 0);
    // Tasarım v3: yeni mesaj kayarak ve belirerek gelir (kullanıcınınki sağdan, asistanınki soldan).
    // Öğeler kimlikleriyle eşlenir: yeni mesaj eklenince eskiler yeniden doğmaz, girişleri tekrar
    // oynamaz.
    return ListView.builder(
      reverse: true,
      padding: EdgeInsets.fromLTRB(
        AknSpace.page,
        16,
        AknSpace.page,
        bottomInset,
      ),
      itemCount: count,
      findChildIndexCallback: (key) {
        if (key == _typingKey) return state.typing ? 0 : null;
        if (key is! ValueKey<String>) return null;
        final i = items.indexWhere((m) => m.id == key.value);
        if (i < 0) return null;
        return state.typing ? i + 1 : i;
      },
      itemBuilder: (context, i) {
        if (state.typing && i == 0) {
          return const KeyedSubtree(
            key: _typingKey,
            child: Padding(
              padding: EdgeInsets.only(top: 16),
              child: TypingBubble(),
            ),
          );
        }
        final index = state.typing ? i - 1 : i;
        final m = items[index];
        return KeyedSubtree(
          key: ValueKey<String>(m.id),
          child: Padding(
            padding: EdgeInsets.only(top: i == count - 1 ? 0 : 16),
            child: _MessageIn(
              fromUser: m.isUser,
              child: MessageBubble(
                key: ValueKey(m.id),
                message: m,
                onRetry: m.failed ? () => onRetry(m) : null,
                onRate: (helpful) => onRate(m, helpful),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Bir mesajın girişi (tek seferlik): 420 ms'de belirir, kendi tarafından 28 px yatay ve 10 px dikey
/// kayar, kuyruk köşesinden %92'den büyür. Yapı sabit (bitince sarmalayıcı kalır, durum korunur);
/// azaltılmış harekette doğrudan çizilir.
class _MessageIn extends StatefulWidget {
  const _MessageIn({required this.fromUser, required this.child});

  final bool fromUser;
  final Widget child;

  @override
  State<_MessageIn> createState() => _MessageInState();
}

class _MessageInState extends State<_MessageIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  static final _move = CurveTween(curve: AknMotion.emphasizedCurve);
  static final _fade = CurveTween(
    curve: const Interval(0, 0.45, curve: Curves.easeOut),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else {
      unawaited(_c.forward());
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final side = widget.fromUser ? 1.0 : -1.0;
    final rtl = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final m = _move.evaluate(_c);
        return Opacity(
          opacity: _fade.evaluate(_c),
          child: Transform.translate(
            offset: Offset(28 * side * rtl * (1 - m), 10 * (1 - m)),
            child: Transform.scale(
              scale: 0.92 + 0.08 * m,
              alignment: widget.fromUser
                  ? AlignmentDirectional.bottomEnd.resolve(
                      Directionality.of(context),
                    )
                  : AlignmentDirectional.bottomStart.resolve(
                      Directionality.of(context),
                    ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _Welcome extends ConsumerWidget {
  const _Welcome({
    super.key,
    required this.suggestions,
    required this.onAsk,
    required this.enabled,
    required this.bottomInset,
  });

  final List<SuggestionGroup>? suggestions;
  final ValueChanged<String> onAsk;
  final bool enabled;
  final double bottomInset;

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
    // Sola dayalı karşılama (v3): süzülen 48 px logo karosu, `display` selam, tek cümle; örnek sorular
    // beyaz hap çipler (ince çizgi, ink 600), sırayla gelir; basınca içe çöker.
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AknSpace.page,
        24,
        AknSpace.page,
        bottomInset,
      ),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AknAmbient(
            period: AknMotion.float,
            reverse: true,
            builder: (context, t, child) =>
                Transform.translate(offset: Offset(0, -4 * t), child: child),
            child: const AssistantAvatar(size: 48),
          ),
        ),
        const SizedBox(height: 20),
        FadeUp(
          offset: 14,
          child: Semantics(
            header: true,
            child: Text(
              AssistantCopy.greeting(first),
              style: t.display.copyWith(color: c.ink),
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.6),
            ),
          ),
        ),
        const SizedBox(height: 8),
        FadeUp(
          offset: 14,
          delay: const Duration(milliseconds: 60),
          child: Text(
            AssistantCopy.intro,
            style: t.body.copyWith(color: c.dim),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          AssistantCopy.starters,
          style: t.captionStrong.copyWith(color: c.dim),
        ),
        const SizedBox(height: 10),
        if (groups == null)
          const Shimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 40, width: 240, radius: 20),
                SizedBox(height: 8),
                SkeletonBox(height: 40, width: 200, radius: 20),
              ],
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 0,
            children: [
              for (final (i, q) in questions.indexed)
                _StarterChip(
                  index: i,
                  question: q,
                  onTap: enabled ? () => onAsk(q) : null,
                ),
            ],
          ),
      ],
    );
  }
}

/// Örnek soru çipi (tasarım v3): beyaz hap (ince çizgi, kart gölgesi), solda turuncu kıvılcım, ink 14/20
/// 600; 40 px görünür, 48 px dokunma alanı. Açılışta sırayla yukarı kayarak gelir; basınca içe çöker.
class _StarterChip extends StatelessWidget {
  const _StarterChip({required this.index, required this.question, this.onTap});

  final int index;
  final String question;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final active = onTap != null;
    return FadeUp(
      offset: 12,
      delay: Duration(milliseconds: 80 + 45 * index),
      child: Semantics(
        button: true,
        enabled: active,
        label: question,
        excludeSemantics: true,
        onTap: onTap,
        child: PressScale(
          enabled: active,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap == null
                ? null
                : () {
                    AknHaptics.selection();
                    onTap!();
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: AknRadius.chip,
                    border: Border.all(color: c.line),
                    boxShadow: AknShadows.pressed(c),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          PhosphorIconsFill.sparkle,
                          size: 15,
                          color: active ? c.brand : c.faint,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            question,
                            style: t.label.copyWith(
                              fontSize: 14,
                              height: 20 / 14,
                              color: active ? c.ink : c.dim,
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
