import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../copy.dart';

/// İlk girişte bir kez gösterilen ipucu ("Teslimatı kaydırarak onaylayın"; tasarım v3 §4): beyaz
/// kart (r20, kart gölgesi), solda yumuşak turuncu dairede kaydırma eli — uygulamada el,
/// kaydırıcıyı gösterir gibi sağa süzülüp döner (ortam hareketi) — başlık, açıklama ve "Anladım"
/// ile kapanır.
class DriverTipCard extends StatelessWidget {
  const DriverTipCard({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final hand = Icon(
      PhosphorIconsRegular.handSwipeRight,
      size: 24,
      color: c.brandInk,
    );
    return Semantics(
      container: true,
      child: AknCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox.square(
                  dimension: 44,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.brandSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: AknAmbient(
                        period: AknMotion.breathe,
                        reverse: true,
                        curve: Curves.easeInOutCubic,
                        child: hand,
                        builder: (context, v, child) => Transform.translate(
                          offset: Offset(-3 + 6 * v, 0),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2, right: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            DriverCopy.tipTitle,
                            style: t.bodyStrong.copyWith(
                              color: c.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DriverCopy.tipBody,
                          style: t.bodySmall.copyWith(color: c.dim),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: AknButton.ghost(
                label: DriverCopy.tipDismiss,
                size: AknButtonSize.small,
                onPressed: onDismiss,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
