import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/ui.dart';
import '../../application/auth_clock.dart';
import '../../application/auth_errors.dart';
import '../../application/auth_throttle.dart';
import '../../copy.dart';

/// Hata bandı: başlık + Türkçe mesaj; sunucu hatasında "Destek kodu" (dokununca kopyalanır).
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.error, this.margin});

  final AuthErrorInfo error;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final code = error.supportCode;
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AknBanner(
            title: error.title,
            message: error.message,
            tone: AknTone.danger,
          ),
          if (code != null) SupportCodeChip(code: code),
        ],
      ),
    );
  }
}

/// "Destek kodu: 1a2b3c4d" — destek ekibi hatayı sunucu günlüğünde bu kodla bulur.
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
        child: InkWell(
          onTap: _copy,
          borderRadius: AknRadius.chip,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AknSpace.minTap),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_rounded, size: 16, color: c.dim),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      text,
                      style: t.caption.copyWith(
                        color: c.dim,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copy() async {
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
        icon: Icons.timer_outlined,
      ),
    );
  }
}
