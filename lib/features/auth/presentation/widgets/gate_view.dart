import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import 'auth_header.dart';

/// Tam ekran durum düzeni (tasarım v2 §7.2: güncelleme, "Sunucu güncel değil", "Bakımdayız", kilit):
/// beyaz sayfa, solda 40 px logo karosu, `display` başlık, tek cümle; eylemler başparmağın eriştiği
/// altta (birincil tam genişlik, altında ikincil). Bant yok, renkli simge dairesi yok. Büyük yazıda
/// sayfa kayar; taşmaz.
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

  /// Durumu anlatan simge (v2'de çizilmez; anlam başlık ve cümlededir).
  final IconData icon;

  /// Durum tonu (v2'de çizilmez; API uyumu için).
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
    // Başlık üstte, eylemler altta: en az ekran yüksekliğinde bir sütun, aradaki boşluk ortada kalır;
    // içerik uzarsa sayfa kayar (iç boyut hesabı gerektirmez).
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AknSpace.page,
            16,
            AknSpace.page,
            16,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0.0, constraints.maxHeight - 32),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AuthPageHeader(
                      title: title,
                      message: message,
                      liveRegion: true,
                    ),
                    if (below != null) ...[const SizedBox(height: 24), below!],
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 28),
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
                        footer!,
                      ],
                    ],
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
