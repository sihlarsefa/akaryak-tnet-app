import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/tr_time.dart';
import '../../copy.dart';
import '../../data/assistant_repository.dart';

/// Mesaj yazma alanı: çok satırlı alan (en çok 1000 karakter; sınıra yaklaşınca sayaç), gönder düğmesi,
/// "Kişisel bilgi paylaşmayın" ipucu ve "Yanıtlar yapay zekâ ile oluşturulur · KVKK" alt bilgisi.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.onSend,
    required this.onOpenKvkk,
    this.enabled = true,
    this.cooldownUntil,
    this.offline = false,
  });

  final ValueChanged<String> onSend;
  final VoidCallback onOpenKvkk;

  /// false: yanıt bekleniyor (gönder kapalı, yazmak açık).
  final bool enabled;

  /// 429 sonrası gönderim bu ana kadar kapalı (geri sayım).
  final DateTime? cooldownUntil;
  final bool offline;

  @override
  State<ChatComposer> createState() => ChatComposerState();
}

class ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _tick;

  static const _max = AssistantRepository.messageMaxLength;

  /// Başlangıç sorusuna dokununca alanı doldurmadan gönderilir; tekrar dene için de kullanılır.
  void clear() => _controller.clear();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _syncTimer();
  }

  @override
  void didUpdateWidget(ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cooldownUntil != widget.cooldownUntil) _syncTimer();
  }

  void _syncTimer() {
    _tick?.cancel();
    final until = widget.cooldownUntil;
    if (until == null || !TrTime.now().isBefore(until)) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (!TrTime.now().isBefore(until)) t.cancel();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  int get _cooldownSeconds {
    final until = widget.cooldownUntil;
    if (until == null) return 0;
    final s = until.difference(TrTime.now()).inSeconds + 1;
    return s > 0 ? s : 0;
  }

  bool get _canSend {
    final text = _controller.text.trim();
    return widget.enabled &&
        !widget.offline &&
        text.isNotEmpty &&
        text.length <= _max &&
        _cooldownSeconds == 0;
  }

  void _send() {
    if (!_canSend) return;
    final text = _controller.text.trim();
    _controller.clear();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final length = _controller.text.characters.length;
    final cooldown = _cooldownSeconds;
    final notice = widget.offline
        ? AssistantCopy.offline
        : cooldown > 0
        ? AssistantCopy.cooldown(cooldown)
        : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AknSpace.page, 10, 12, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (notice != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      notice,
                      style: t.caption.copyWith(color: c.warn.fg),
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: _max,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      textCapitalization: TextCapitalization.sentences,
                      style: t.body.copyWith(color: c.ink, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: AssistantCopy.inputHint,
                        labelText: null,
                        counterText: length > _max - 200 ? null : '',
                        helperText: AssistantCopy.privacyHint,
                        helperMaxLines: 2,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: AknIconButton(
                      icon: Icons.send_rounded,
                      semanticLabel: AssistantCopy.send,
                      color: _canSend ? c.ink : c.faint,
                      onPressed: _canSend ? _send : null,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AssistantCopy.aiFooter,
                      style: t.caption.copyWith(color: c.dim),
                    ),
                  ),
                  const SizedBox(width: 12),
                  AknInlineLink(
                    label: AssistantCopy.kvkk,
                    onTap: widget.onOpenKvkk,
                    style: t.label.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
