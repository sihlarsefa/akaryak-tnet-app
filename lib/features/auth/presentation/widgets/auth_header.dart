import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/ui.dart';
import '../../copy.dart';

/// Giriş ekranının üst alanı (F2GO giriş düzeni, sahip kararı 2026-10-21): kompakt turuncu geçiş,
/// ortada beyaz logo karosu + "AkaryakıtNet" ve tek satır alt yazı. Durum çubuğunun arkasından başlar
/// (açık simgeler). Altındaki beyaz sayfa ([LoginSheet]) bu alana [sheetOverlap] kadar biner.
///
/// Kod, kilit, güncelleme ve telefon doğrulama ekranları beyaz sayfalardır ([AuthPageHeader]).
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, this.compact = false});

  /// Büyük yazı ya da kısa ekran: alan biraz daralır.
  final bool compact;

  /// Durum çubuğunun altındaki yükseklik (F2GO: 112).
  static const double bodyHeight = 140;

  /// Beyaz sayfanın üst alana bindiği yükseklik (F2GO: 46).
  static const double sheetOverlap = 44;

  static const Color _white = Color(0xFFFFFFFF);

  /// Açık temada yumuşak geçiş: açık turuncu → turuncu → koyu turuncu.
  static const _lightStops = [
    Color(0xFFFF9A5C),
    Color(0xFFF7742F),
    Color(0xFFE8590C),
  ];

  @override
  Widget build(BuildContext context) {
    // viewPadding: üst katmanlar dolguyu tüketmiş olsa da durum çubuğu payı doğru gelir.
    final top = math.max(
      MediaQuery.paddingOf(context).top,
      MediaQuery.viewPaddingOf(context).top,
    );
    final c = context.akn;
    final dark = c.brightness == Brightness.dark;
    final colors = dark ? [c.heroStart, c.heroMid, c.heroEnd] : _lightStops;
    final body = compact ? bodyHeight - 12 : bodyHeight;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AknTheme.overlayOnBand(c.brightness),
      child: Semantics(
        container: true,
        header: true,
        label: AuthCopy.bandSpoken,
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: top + body),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
                stops: const [0, 0.45, 1],
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.hardEdge,
              children: [
                // Sağ üstte çok hafif beyaz ışık; sol altta sıcak ton.
                const Positioned(
                  top: -110,
                  right: -80,
                  child: _Glow(size: 280, color: Color(0x38FFFFFF)),
                ),
                const Positioned(
                  bottom: -70,
                  left: -60,
                  child: _Glow(size: 220, color: Color(0x2EFFE3D3)),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AknSpace.page,
                    top + 4,
                    AknSpace.page,
                    sheetOverlap + 14,
                  ),
                  child: Center(
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.2,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(11),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x33A33A06),
                                        blurRadius: 14,
                                        offset: Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: LogoMark(
                                    size: 40,
                                    tileColor: _white,
                                    chevronColor: c.logo,
                                    semanticLabel: null,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'AkaryakıtNet',
                                  maxLines: 1,
                                  softWrap: false,
                                  style: TextStyle(
                                    fontFamily: AknFonts.sans,
                                    fontSize: 25,
                                    height: 1.1,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                    color: _white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            AuthCopy.bandSubtitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AknFonts.sans,
                              fontSize: 13,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                              color: Color(0xE0FFFFFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Yumuşak, kenarları kaybolan dairesel ışık.
class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

/// Giriş ekranının beyaz sayfası: üst köşeleri 28 yuvarlak, üst alana [AuthHeader.sheetOverlap] kadar
/// biner, yukarı doğru yumuşak gölge verir; ilk açılışta yumuşakça yukarı kayarak belirir (hareket
/// azaltılmışsa doğrudan görünür).
class LoginSheet extends StatelessWidget {
  const LoginSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? 1 : 0, end: 1),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 560),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Transform.translate(
        offset: Offset(0, -AuthHeader.sheetOverlap + 40 * (1 - v)),
        child: Opacity(opacity: v.clamp(0, 1), child: child),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 28,
              offset: Offset(0, -4),
              spreadRadius: -6,
            ),
            BoxShadow(
              color: Color(0x1AE8590C),
              blurRadius: 36,
              offset: Offset(0, 10),
              spreadRadius: -18,
            ),
          ],
        ),
        child: Padding(padding: const EdgeInsets.only(top: 18), child: child),
      ),
    );
  }
}

/// Beyaz kimlik sayfalarının başı (tasarım v2 §7.2: kod, telefon doğrulama, kilit, güncelleme): solda
/// 40 px logo karosu, altında `display` başlık (30/36) ve tek cümle. Bant yok.
class AuthPageHeader extends StatelessWidget {
  const AuthPageHeader({
    super.key,
    required this.title,
    this.message,
    this.showLogo = true,
    this.liveRegion = false,
  });

  final String title;
  final String? message;

  /// Üstteki 40 px logo karosu (uygulama çubuğu olan sayfalarda gizlenir).
  final bool showLogo;

  /// Durum sayfaları başlığı ekran okuyucuya duyurur.
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLogo) ...[
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: LogoMark(size: 40, semanticLabel: null),
          ),
          const SizedBox(height: 28),
        ],
        Semantics(
          header: true,
          liveRegion: liveRegion,
          child: Text(title, style: t.display.copyWith(color: c.ink)),
        ),
        if (message != null && message!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(message!, style: t.body.copyWith(color: c.dim)),
        ],
      ],
    );
  }
}
