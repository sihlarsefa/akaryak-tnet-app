import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../copy.dart';

/// İlk girişte bir kez gösterilen ipucu kartı ("Teslimatı kaydırarak onaylayın"); "Anladım" ile kapanır.
class DriverTipCard extends StatelessWidget {
  const DriverTipCard({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Semantics(
      container: true,
      child: AknCard(
        color: c.brandSoft,
        borderColor: c.brandLine,
        shadow: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AknIconBox(
                  icon: Icons.swipe_right_rounded,
                  tone: AknTone.brand,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(DriverCopy.tipTitle, style: t.bodyStrong),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DriverCopy.tipBody,
                        style: t.bodySmall.copyWith(color: c.text),
                      ),
                    ],
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
