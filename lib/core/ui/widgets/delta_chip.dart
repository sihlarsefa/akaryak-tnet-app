import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';
import 'cards.dart' show OnHero;
import 'triangle_glyph.dart';

/// Which way a delta points.
enum AknDeltaDirection { up, down, flat }

/// The delta chip (design v2 §5.1, §6.19): a drawn ▲ / ▼ and the change
/// ("%12,8", "4 puan", "0,44 ₺") in a 24 px chip with 6 px corners.
///
/// * On the plate card (owner decision G): `deltaFill` (#FFF1E8) with the
///   text and arrow in Pas (`brandInk` #C2410C, 4.68:1). The chip is
///   neutral there — no good / bad colour; the sentence after it names the
///   comparison.
/// * On white: a Beton chip with ink text. The arrow takes the ok / danger
///   colour only when [goodForViewer] is known (a falling unit price is good
///   for a customer); otherwise it is ink.
///
/// [onPlate] defaults to "inside a plate" (`OnHero` or a palette whose
/// surface is the plate colour, as on the deck's top card).
class AknDeltaChip extends StatelessWidget {
  const AknDeltaChip({
    super.key,
    required this.label,
    this.direction,
    this.goodForViewer,
    this.onPlate,
    this.semanticLabel,
  });

  /// A chip for a signed change: the sign picks the arrow; [label] is the
  /// formatted absolute change. [positiveIsGood] (when known) colours the
  /// arrow on white.
  factory AknDeltaChip.change(
    num change, {
    Key? key,
    required String label,
    bool? positiveIsGood,
    bool? onPlate,
    String? semanticLabel,
  }) {
    final direction = change > 0
        ? AknDeltaDirection.up
        : change < 0
        ? AknDeltaDirection.down
        : AknDeltaDirection.flat;
    return AknDeltaChip(
      key: key,
      label: label,
      direction: direction,
      goodForViewer: positiveIsGood == null || change == 0
          ? null
          : (change > 0) == positiveIsGood,
      onPlate: onPlate,
      semanticLabel: semanticLabel,
    );
  }

  final String label;

  /// Null or [AknDeltaDirection.flat] draws no arrow.
  final AknDeltaDirection? direction;

  /// True: the change is good for the viewer (green arrow on white); false:
  /// bad (red arrow); null: unknown (ink). Ignored on the plate.
  final bool? goodForViewer;
  final bool? onPlate;
  final String? semanticLabel;

  /// True inside a plate (hero panel or a plate-coloured palette).
  static bool isOnPlate(BuildContext context) {
    final c = context.akn;
    return OnHero.isOn(context) || c.isPlatePalette;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final plate = onPlate ?? isOnPlate(context);
    final fill = plate ? c.deltaFill : c.surfaceAlt;
    final ink = plate ? c.brandInk : c.ink;
    final arrow = plate || goodForViewer == null
        ? ink
        : goodForViewer!
        ? c.ok.fg
        : c.danger.fg;
    final style = t.bodySmall.copyWith(
      fontSize: 14,
      height: 24 / 14,
      fontWeight: FontWeight.w700,
      color: ink,
    );
    final dir = direction;
    final hasArrow =
        dir == AknDeltaDirection.up || dir == AknDeltaDirection.down;
    final spoken = switch (dir) {
      AknDeltaDirection.up => '$label artış',
      AknDeltaDirection.down => '$label düşüş',
      _ => label,
    };
    return Semantics(
      label: semanticLabel ?? spoken,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: fill, borderRadius: AknRadius.tag),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasArrow) ...[
              TriangleGlyph(down: dir == AknDeltaDirection.down, color: arrow),
              const SizedBox(width: 5),
            ],
            Text(label, style: style, maxLines: 1, softWrap: false),
          ],
        ),
      ),
    );
  }
}
