import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../copy.dart';

/// İlk girişte bir kez gösterilen ipucu ("Teslimatı kaydırarak onaylayın"): Beton kuyu (§4.5),
/// mürekkep simge ve yazı, "Anladım" ile kapanır. Turuncu zemin yok.
class DriverTipCard extends StatelessWidget {
  const DriverTipCard({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 6),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: AknRadius.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.swipe_right_outlined, size: 24, color: c.ink),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          DriverCopy.tipTitle,
                          style: t.bodyStrong.copyWith(color: c.ink),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DriverCopy.tipBody,
                        style: t.bodySmall.copyWith(color: c.ink),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
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
