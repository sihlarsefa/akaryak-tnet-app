import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// Asistanın görünümü (spec A.6; tasarım v3): » LogoMark karosu, altında yumuşak sıcak bir gölgeyle
/// hafifçe yükselmiş; yalnızca "yazıyor" iken oklar sakin bir döngüyle yeniden çizilir (ortam hareketi:
/// [AknMotion.ambientOf] açıkken). Robot ya da nabız gibi atan düğme yoktur. Azaltılmış hareket ve ekran
/// okuyucu gezintisinde hiç oynamaz; ekran dışındayken (TickerMode) durur.
class AssistantAvatar extends StatefulWidget {
  const AssistantAvatar({super.key, this.size = 32, this.typing = false});

  final double size;
  final bool typing;

  @override
  State<AssistantAvatar> createState() => _AssistantAvatarState();
}

class _AssistantAvatarState extends State<AssistantAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool get _animate {
    final mq = MediaQuery.maybeOf(context);
    final calm =
        (mq?.disableAnimations ?? false) || (mq?.accessibleNavigation ?? false);
    // Döngü yalnızca ortam hareketi açıkken (testlerde ve azaltılmış harekette kapalı).
    return widget.typing && !calm && AknMotion.ambientOf(context);
  }

  void _sync() {
    if (_animate) {
      if (!_c.isAnimating) _c.repeat();
    } else if (_c.isAnimating || _c.value != 0) {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AssistantAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.typing != widget.typing) _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // Durgun: tam çizili işaret. Yazarken: oklar soluk izden yeniden çizilir (0,35 → 1).
          final v = _c.value;
          final drawing = _c.isAnimating;
          final p = !drawing
              ? 1.0
              : v < 0.75
              ? 0.35 + 0.65 * AknMotion.emphasizedCurve.transform(v / 0.75)
              : 1.0;
          final mark = LogoMark(
            size: widget.size,
            progress: p,
            trackOpacity: drawing ? 0.35 : 0,
            semanticLabel: null,
          );
          // Büyük boylarda (karşılama, aydınlatma) karo sıcak bir gölgeyle yükselir.
          if (widget.size < 28) return mark;
          final c = context.akn;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.size * 0.225),
              boxShadow: [
                BoxShadow(
                  color: c.logo.withValues(alpha: c.isDark ? 0.3 : 0.26),
                  blurRadius: widget.size * 0.45,
                  offset: Offset(0, widget.size * 0.18),
                  spreadRadius: -widget.size * 0.12,
                ),
              ],
            ),
            child: mark,
          );
        },
      ),
    );
  }
}
