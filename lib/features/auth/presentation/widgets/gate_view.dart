import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// Tam ekran durum düzeni (güncelleme, "Sunucu güncel değil", "Bakımdayız", kilit): üstte sakin işaret,
/// ortada simge + başlık + açıklama, altta eylemler. Büyük yazıda kaydırılır; taşmaz.
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

  final IconData icon;
  final AknTone tone;
  final String title;
  final String message;

  /// Birincil eylem (genellikle [AknButton]).
  final Widget? primary;
  final Widget? secondary;

  /// Eylemlerin altında ek içerik (destek kanalları).
  final Widget? below;

  /// En altta küçük bilgi (sürüm).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final tc = c.tone(tone);
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0.0, constraints.maxHeight - 32),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Center(child: LogoMark(size: 40, semanticLabel: null)),
                const SizedBox(height: 32),
                FadeUp(
                  child: Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: tc.bg,
                        shape: BoxShape.circle,
                        border: Border.all(color: tc.line, width: 2),
                      ),
                      child: Icon(icon, color: tc.fg, size: 44),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text(
                    title,
                    style: t.title,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: t.body.copyWith(color: c.dim),
                  textAlign: TextAlign.center,
                ),
                if (primary != null) ...[const SizedBox(height: 28), primary!],
                if (secondary != null) ...[
                  const SizedBox(height: 8),
                  secondary!,
                ],
                if (below != null) ...[const SizedBox(height: 24), below!],
                if (footer != null) ...[const SizedBox(height: 20), footer!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
