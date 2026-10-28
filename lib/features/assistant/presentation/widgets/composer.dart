import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/tr_time.dart';
import '../../copy.dart';
import '../../data/assistant_repository.dart';

/// Mesaj yazma alanı (tasarım v3): buzlu cam çubuk (yüzey %86 + 20 bulanıklık; mesajlar altından kayarken
/// bulanık görünür), hap biçimli çok satırlı alan (en çok 1000 karakter; sınıra yaklaşınca sayaç), turuncu
/// degrade yuvarlak gönder düğmesi (yazınca "pop" ile canlanır, basınca içe çöker ve uçağı fırlatır),
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

class ChatComposerState extends State<ChatComposer>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _tick;

  /// Gönderince kâğıt uçağın kısa uçuşu (tek seferlik).
  late final AnimationController _launch = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

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
    _launch.dispose();
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
    if (!AknMotion.reduced(context)) unawaited(_launch.forward(from: 0));
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
    OutlineInputBorder pill(Color color, double width) => OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(24)),
      borderSide: BorderSide(color: color, width: width),
    );
    final field = TextField(
      controller: _controller,
      focusNode: _focus,
      minLines: 1,
      maxLines: 5,
      maxLength: _max,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      textCapitalization: TextCapitalization.sentences,
      style: t.body.copyWith(color: c.ink, fontSize: 16, height: 22 / 16),
      cursorColor: c.brand,
      decoration: InputDecoration(
        hintText: AssistantCopy.inputHint,
        hintStyle: t.body.copyWith(color: c.dim, fontSize: 16),
        labelText: null,
        counterText: '',
        isDense: true,
        filled: true,
        fillColor: c.isDark ? c.surfaceAlt : c.bg,
        contentPadding: const EdgeInsets.fromLTRB(18, 13, 18, 13),
        border: pill(c.line, 1),
        enabledBorder: pill(c.line, 1),
        focusedBorder: pill(c.brand, 1.5),
      ),
    );
    return DecoratedBox(
      // Gölge kırpmanın dışında: cam çubuk içeriğin üstünde yüzer.
      decoration: BoxDecoration(boxShadow: AknShadows.bar(c)),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surfaceRaised.withValues(alpha: 0.86),
              border: Border(
                top: BorderSide(color: c.line.withValues(alpha: 0.7)),
              ),
            ),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 6),
              child: Padding(
                // Alan 20 px kenarda başlar; gönder diskinin (48 dp hedefte 44 px) ve KVKK bağlantısının
                // sağ kenarı da 20 px kenarda biter.
                padding: const EdgeInsets.fromLTRB(
                  AknSpace.page,
                  10,
                  AknSpace.page - 2,
                  0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AknAnimatedSize(
                      alignment: Alignment.topCenter,
                      child: notice == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  notice,
                                  style: t.caption.copyWith(
                                    color: c.warn.fg,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: AknNumerals.tabular,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: field),
                        const SizedBox(width: 6),
                        _SendButton(
                          enabled: _canSend,
                          launch: _launch,
                          onPressed: _send,
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              AssistantCopy.privacyHint,
                              style: t.caption.copyWith(color: c.dim),
                            ),
                          ),
                          if (length > _max - 200) ...[
                            const SizedBox(width: 8),
                            Text(
                              '$length/$_max',
                              style: t.caption.copyWith(
                                color: length > _max ? c.danger.fg : c.dim,
                                fontWeight: FontWeight.w600,
                                fontFeatures: AknNumerals.tabular,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(start: 6),
                            child: Text(
                              AssistantCopy.aiFooter,
                              style: t.caption.copyWith(color: c.dim),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        AknInlineLink(
                          label: AssistantCopy.kvkk,
                          onTap: widget.onOpenKvkk,
                          style: t.label.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 2),
                      ],
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

/// Gönder düğmesi (tasarım v3): 44 px yuvarlak (48 dp hedef). Gönderilebilirken turuncu degrade, beyaz
/// dolu kâğıt uçak ve sıcak parıltı; değilken kuyu ve soluk simge. Etkinleşince "pop" ile büyür, basınca
/// içe çöker; gönderince uçak sağ üste fırlayıp döner ([launch]).
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.launch,
    required this.onPressed,
  });

  final bool enabled;
  final Animation<double> launch;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final duration = AknMotion.of(context, AknMotion.base);
    return Tooltip(
      message: AssistantCopy.send,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: AssistantCopy.send,
        excludeSemantics: true,
        onTap: enabled ? onPressed : null,
        child: PressScale(
          enabled: enabled,
          scale: 0.9,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled
                ? () {
                    AknHaptics.light();
                    onPressed();
                  }
                : null,
            child: SizedBox.square(
              dimension: AknSpace.minTap,
              child: Center(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(enabled),
                  tween: Tween(begin: enabled ? 0.8 : 1, end: 1),
                  duration: AknMotion.of(context, AknMotion.slow),
                  curve: AknMotion.pop,
                  builder: (context, v, child) =>
                      Transform.scale(scale: v, child: child),
                  child: AnimatedContainer(
                    duration: duration,
                    curve: AknMotion.standard,
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: enabled ? null : c.surfaceAlt,
                      gradient: enabled ? c.buttonGradient : null,
                      boxShadow: enabled ? AknShadows.button(c) : null,
                    ),
                    alignment: Alignment.center,
                    child: AnimatedBuilder(
                      animation: launch,
                      builder: (context, child) {
                        final k = math.sin(math.pi * launch.value);
                        return Transform.translate(
                          offset: Offset(7 * k, -7 * k),
                          child: Opacity(opacity: 1 - 0.7 * k, child: child),
                        );
                      },
                      child: Icon(
                        enabled
                            ? PhosphorIconsFill.paperPlaneRight
                            : PhosphorIconsRegular.paperPlaneRight,
                        size: 20,
                        color: enabled ? c.onBrandFill : c.faint,
                      ),
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
