import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import 'auth_header.dart';

/// Tam ekran durum düzeni (tasarım v3: güncelleme, "Sunucu güncel değil", "Bakımdayız", kilit): ortada
/// durumun çizimi ([icon] ve [tone]'dan: yumuşak tonlu iç içe halkalar, ortada dolu bir disk ve beyaz
/// simge; disk hafifçe süzülür, çevresinde küçük noktalar yavaşça döner), altında ortalı `display` başlık
/// ve tek cümle; eylemler başparmağın eriştiği altta (birincil tam genişlik, altında ikincil). Açılışta
/// çizim "pop" ile gelir, yazılar ve eylemler sırayla yukarı kayarak belirir. Büyük yazıda sayfa kayar;
/// taşmaz.
class GateView extends StatelessWidget {
  const GateView({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    required this.message,
    this.primary,
    this.secondary,
    this.below,
    this.footer,
  });

  /// Durumu anlatan simge (çizimin ortasındaki diskte).
  final IconData icon;

  /// Çizimin tonu: [AknTone.brand] turuncu degrade disk, diğerleri tonun dolu rengi.
  final AknTone tone;
  final String title;
  final String message;

  /// Birincil eylem (genellikle [AknButton]).
  final Widget? primary;
  final Widget? secondary;

  /// Cümlenin altında ek içerik (destek kanalları, mağaza notu).
  final Widget? below;

  /// En altta küçük bilgi (sürüm).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    // Çizim büyük yazıda küçülür (başlık ve eylemlere yer kalsın).
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    // Başlık üstte, eylemler altta: en az ekran yüksekliğinde bir sütun, aradaki boşluk ortada kalır;
    // içerik uzarsa sayfa kayar (iç boyut hesabı gerektirmez).
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AknSpace.page,
            24,
            AknSpace.page,
            16,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0.0, constraints.maxHeight - 40),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: AuthPop(
                        child: GateArt(
                          icon: icon,
                          tone: tone,
                          size: large ? 104 : 136,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    AuthRise(
                      delay: const Duration(milliseconds: 60),
                      child: Semantics(
                        header: true,
                        liveRegion: true,
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: t.display.copyWith(color: c.ink),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    AuthRise(
                      delay: const Duration(milliseconds: 100),
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: t.body.copyWith(color: c.dim),
                      ),
                    ),
                    if (below != null) ...[
                      const SizedBox(height: 24),
                      AuthRise(
                        delay: const Duration(milliseconds: 140),
                        child: AknAnimatedSize(
                          alignment: Alignment.topCenter,
                          child: below!,
                        ),
                      ),
                    ],
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 28),
                  child: AuthRise(
                    delay: const Duration(milliseconds: 160),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ?primary,
                        if (secondary != null) ...[
                          const SizedBox(height: 10),
                          secondary!,
                        ],
                        if (footer != null) ...[
                          const SizedBox(height: 12),
                          Center(child: footer),
                        ],
                      ],
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

/// Durum çizimi (tasarım v3 boş / durum çizimleri): [size] boyunda iç içe iki yumuşak halka (tonun
/// kuyusu), ortada dolu bir disk ([AknTone.brand] için turuncu degrade; bilgi ve nötr tonda yüzen beyaz
/// disk, ink simge ve turuncu noktalar; diğerlerinde tonun dolu rengi) ve içinde simge. Disk yavaşça süzülür (±5 px, [AknMotion.float]); çevresindeki üç küçük nokta bandın
/// akış süresinde ([AknMotion.bandDrift]) bir tur döner. Süs; ekran okuyucuda yok.
class GateArt extends StatelessWidget {
  const GateArt({
    super.key,
    required this.icon,
    required this.tone,
    this.size = 136,
  });

  final IconData icon;
  final AknTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final tc = c.tone(tone);
    final brand = tone == AknTone.brand;
    // Bilgi / nötr durumlar (bakım …): grafit disk yerine yüzen beyaz disk, ink simge ve turuncu
    // noktalar — v3 boş durum çizimlerinin "turuncu vurgu + nötr griler" dili.
    final quiet = tone == AknTone.info || tone == AknTone.neutral;
    final disc = size * 0.47;
    final mark = brand || quiet ? c.brand : tc.solid;
    final glyph = brand
        ? c.onBrandFill
        : quiet
        ? c.ink
        : tc.onSolid;
    final List<Color> fill = brand
        ? [c.brandFillStart, c.brandFill]
        : quiet
        ? [c.surfaceRaised, Color.lerp(c.surfaceRaised, c.surfaceAlt, 0.7)!]
        : [Color.lerp(tc.solid, glyph, 0.14)!, tc.solid];
    final glow = quiet
        ? c.shadow.withValues(alpha: c.isDark ? 0.5 : 0.14)
        : mark.withValues(alpha: c.isDark ? 0.3 : 0.32);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Dış halka: kuyunun yarı saydamı; orta halka: kuyu + ince çizgi.
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tc.bg.withValues(alpha: c.isDark ? 0.55 : 0.6),
              ),
            ),
            Container(
              width: size * 0.74,
              height: size * 0.74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tc.bg,
                border: Border.all(color: tc.line),
              ),
            ),
            // Dönen noktalar.
            AknAmbient(
              period: AknMotion.bandDrift,
              curve: Curves.linear,
              builder: (context, t, child) =>
                  Transform.rotate(angle: 2 * math.pi * t, child: child),
              child: SizedBox.square(
                dimension: size,
                child: CustomPaint(
                  painter: _OrbitDots(color: mark, radius: size * 0.43),
                ),
              ),
            ),
            AknAmbient(
              period: AknMotion.float,
              reverse: true,
              builder: (context, t, child) => Transform.translate(
                offset: Offset(0, -5 * t + 2),
                child: child,
              ),
              child: Container(
                width: disc,
                height: disc,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Sol üstten hafif bir ışık: disk düz değil, dolgun görünür.
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: fill,
                  ),
                  border: quiet && c.isDark ? Border.all(color: c.line) : null,
                  boxShadow: [
                    BoxShadow(
                      color: glow,
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                      spreadRadius: -6,
                    ),
                  ],
                ),
                child: Icon(icon, size: disc * 0.46, color: glyph),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Halkanın üstünde üç küçük nokta (farklı boy ve saydamlıkta).
class _OrbitDots extends CustomPainter {
  _OrbitDots({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const dots = [(-0.62, 4.5, 0.9), (1.35, 3.2, 0.55), (2.6, 2.6, 0.4)];
    for (final (angle, r, alpha) in dots) {
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        r,
        Paint()..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbitDots old) =>
      old.color != color || old.radius != radius;
}
