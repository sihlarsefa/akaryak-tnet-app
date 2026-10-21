import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/ui.dart';
import '../../copy.dart';

/// Giriş ekranının turuncu bandı (tasarım v2 §5.2, §7.2; tahta ekran 1): tam genişlikte, köşesiz plaka
/// rengi; ters logo karosu (beyaz kare, turuncu »), "Siparişten teslimata." başlığı, tek siyah 3 px
/// çizgi, altında kelime işareti ("Akaryakıt" siyah, "Net" beyaz) ve "Bayiler ve kurumsal müşteriler
/// için". Bandın üzerindeki her şey siyahtır (turuncuda mürekkep siyah). Durum çubuğu boşluğunu kendisi
/// bırakır; durum çubuğu simgeleri koyudur.
///
/// Bant yalnızca giriş ekranına aittir; kod, kilit, güncelleme ve telefon doğrulama ekranları beyaz
/// sayfalardır ([AuthPageHeader]).
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, this.compact = false});

  /// Büyük yazı ya da kısa ekran: boşluklar daralır, form ilk ekrana yaklaşır.
  final bool compact;

  /// Bandın yüksekliği (390 × 844, 1,0×, durum çubuğu dahil) — tahtadaki ölçü.
  static const double boardHeight = 384;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final page = context.akn;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AknTheme.overlayOnPlate(page.brightness),
      child: ColoredBox(
        color: page.plate,
        child: OnHero(
          child: Builder(
            builder: (context) {
              final c = context.akn;
              final t = context.aknText;
              final headline = TextStyle(
                fontFamily: AknFonts.sans,
                fontSize: 50,
                height: 52 / 50,
                fontWeight: FontWeight.w600,
                letterSpacing: -1.6,
                color: c.onPlate,
                leadingDistribution: TextLeadingDistribution.even,
                locale: AknFonts.locale,
              );
              final subtitle = t.label.copyWith(
                fontSize: 13,
                height: 16 / 13,
                fontWeight: FontWeight.w500,
                color: c.onPlate,
              );
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  AknSpace.page,
                  top + (compact ? 20 : 31),
                  AknSpace.page,
                  compact ? 18 : 22,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: LogoMark(
                        size: compact ? 44 : 56,
                        semanticLabel: null,
                      ),
                    ),
                    SizedBox(height: compact ? 20 : 40),
                    // Başlık en çok 1,2× büyür (iki satır, ekrana sığar); okunuşu tek cümle.
                    Semantics(
                      header: true,
                      label: AuthCopy.tagline,
                      excludeSemantics: true,
                      child: MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.2,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            'Siparişten\nteslimata.',
                            style: headline,
                            maxLines: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // ADR plakasının orta çizgisi: bantta tek kural.
                    SizedBox(height: 3, child: ColoredBox(color: c.onPlate)),
                    const SizedBox(height: 12),
                    if (compact)
                      // Büyük yazı: alt satır kelime işaretinin altına iner, tam genişlikte.
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AknWordmark(fontSize: 22),
                          const SizedBox(height: 6),
                          Text(
                            AuthCopy.bandSubtitle,
                            style: subtitle,
                            textScaler: MediaQuery.textScalerOf(
                              context,
                            ).clamp(maxScaleFactor: 1.5),
                          ),
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const AknWordmark(fontSize: 22),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              // "Bayiler ve kurumsal / müşteriler için": iki satır.
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 150,
                                ),
                                child: Text(
                                  AuthCopy.bandSubtitle,
                                  textAlign: TextAlign.end,
                                  style: subtitle,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ),
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
