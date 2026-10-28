import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/ui.dart';
import '../../application/auth_clock.dart';
import '../../application/auth_errors.dart';
import '../../application/auth_throttle.dart';
import '../../copy.dart';

/// Hata bandı: başlık + Türkçe mesaj; sunucu hatasında "Destek kodu" (dokununca kopyalanır). Yeni bir
/// hata geldiğinde bant üç kez hızla sağa sola sallanır (tasarım v3 §5, sönerek; azaltılmış harekette
/// durur).
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.error, this.margin});

  final AuthErrorInfo error;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final code = error.supportCode;
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: _ShakeOnce(
        key: ValueKey('${error.title}\n${error.message}\n$code'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AknBanner(
              title: error.title,
              message: error.message,
              tone: AknTone.danger,
            ),
            if (code != null) ...[
              const SizedBox(height: 4),
              SupportCodeChip(code: code),
            ],
          ],
        ),
      ),
    );
  }
}

/// İlk çizimde bir kez sallanır: ±6 px, üç salınım, 420 ms, sönerek. Yalnızca öteleme (ölçek yok).
class _ShakeOnce extends StatefulWidget {
  const _ShakeOnce({super.key, required this.child});

  final Widget child;

  @override
  State<_ShakeOnce> createState() => _ShakeOnceState();
}

class _ShakeOnceState extends State<_ShakeOnce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!AknMotion.reduced(context)) unawaited(_c.forward());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      final t = _c.value;
      return Transform.translate(
        offset: Offset(6 * math.sin(t * 6 * math.pi) * (1 - t), 0),
        child: child,
      );
    },
  );
}

/// "Destek kodu: 1a2b3c4d" — destek ekibi hatayı sunucu günlüğünde bu kodla bulur. Hap biçimli kuyu
/// (32 px görünür, 48 dp hedef), kopyala simgesi; basınca hafifçe içe çöker.
class SupportCodeChip extends StatelessWidget {
  const SupportCodeChip({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final text = AuthCopy.supportCode(code);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        button: true,
        label: text,
        hint: AuthCopy.supportCodeHint,
        excludeSemantics: true,
        onTap: () => _copy(),
        child: PressScale(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _copy,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AknSpace.minTap),
              child: Center(
                widthFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: AknRadius.pillAll,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsRegular.copy, size: 15, color: c.dim),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            text,
                            style: t.caption.copyWith(
                              color: c.dim,
                              fontWeight: FontWeight.w600,
                              fontFeatures: AknNumerals.tabular,
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

  Future<void> _copy() async {
    AknHaptics.selection();
    await Clipboard.setData(ClipboardData(text: code));
    AppToast.info(AuthCopy.supportCodeCopied);
  }
}

/// Sunucunun 429 ile istediği bekleme (spec C.7): sunucunun mesajı, yoksa "Çok fazla deneme. 45 sn
/// sonra tekrar deneyin.". Metin sabittir (canlı bölge her saniye okunmasın diye); kalan süre düğmede
/// sayılır.
class ThrottleBanner extends StatelessWidget {
  const ThrottleBanner({super.key, required this.hold, this.margin});

  final AuthHold hold;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: AknBanner(
        title: hold.lockout ? AuthCopy.lockedTitle : AuthCopy.throttledTitle,
        message: hold.message ?? AuthCopy.rateLimited(formatWait(hold.wait)),
        tone: AknTone.warn,
        icon: PhosphorIconsRegular.timer,
      ),
    );
  }
}
