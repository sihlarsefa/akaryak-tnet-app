import 'dart:async';

import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';
import 'cards.dart' show OnHero;
import 'triangle_glyph.dart';

/// Which way a delta points.
enum AknDeltaDirection { up, down, flat }

/// The delta chip (design v3 §4): a rounded ▲ / ▼ and the change ("%12,8",
/// "4 puan", "0,44 ₺", 13 w700, tabular) in a 24 px chip with 8 px corners.
/// When it first appears its arrow slides in along its direction.
///
/// * On the plate card: neutral — an ink ▲ / ▼ and value in a `plateLine`
///   outline, no fill (v4 P5: orange is for action and "you are here",
///   never for a healthy statistic; A11). No good / bad colour there; the
///   period line or the sentence after it names the comparison.
/// * On white: a soft tone well. When [goodForViewer] is known (a falling
///   unit price is good for a customer) the chip takes the ok / danger well
///   and ink (`ToneColors.bg` + `fg`); otherwise it is a `surfaceAlt` chip
///   with ink text.
///
/// [onPlate] defaults to "inside a plate" (`OnHero` or a palette whose
/// surface is the plate colour, as on the deck's top card).
class AknDeltaChip extends StatefulWidget {
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
  /// chip on white.
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

  /// True: the change is good for the viewer (an ok chip on white); false:
  /// bad (a danger chip); null: unknown (neutral). Ignored on the plate.
  final bool? goodForViewer;
  final bool? onPlate;
  final String? semanticLabel;

  /// True inside a plate (hero panel or a plate-coloured palette).
  static bool isOnPlate(BuildContext context) {
    final c = context.akn;
    return OnHero.isOn(context) || c.isPlatePalette;
  }

  @override
  State<AknDeltaChip> createState() => _AknDeltaChipState();
}

class _AknDeltaChipState extends State<AknDeltaChip>
    with SingleTickerProviderStateMixin {
  // Created up front: a chip without an arrow must not create its ticker
  // in dispose(), when the element is no longer active.
  late final AnimationController _arrow;
  Timer? _timer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _arrow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _arrow.value = 1;
    } else {
      _timer = Timer(const Duration(milliseconds: 280), () {
        if (mounted) _arrow.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _arrow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final plate = widget.onPlate ?? AknDeltaChip.isOnPlate(context);
    final good = widget.goodForViewer;
    final ToneColors? tone = plate || good == null
        ? null
        : good
        ? c.ok
        : c.danger;
    // On the plate: no fill, an ink arrow and value, a `plateLine` outline
    // (painted over the chip, so its size stays 24).
    final fill = plate ? null : tone?.bg ?? c.surfaceAlt;
    final ink = plate ? c.ink : tone?.fg ?? c.ink;
    final style = t.bodySmall.copyWith(
      fontSize: 13,
      height: 24 / 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      color: ink,
      fontFeatures: AknNumerals.tabular,
    );
    final dir = widget.direction;
    final hasArrow =
        dir == AknDeltaDirection.up || dir == AknDeltaDirection.down;
    final down = dir == AknDeltaDirection.down;
    final label = widget.label;
    final spoken = switch (dir) {
      AknDeltaDirection.up => '$label artış',
      AknDeltaDirection.down => '$label düşüş',
      _ => label,
    };
    return Semantics(
      label: widget.semanticLabel ?? spoken,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: fill, borderRadius: AknRadius.tag),
        foregroundDecoration: plate
            ? BoxDecoration(
                border: Border.all(color: c.plateLine),
                borderRadius: AknRadius.tag,
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasArrow) ...[
              AnimatedBuilder(
                animation: _arrow,
                child: TriangleGlyph.small(down: down, color: ink),
                builder: (context, child) {
                  final v = _arrow.value;
                  final p = v >= 1 ? 1.0 : AknMotion.pop.transform(v);
                  return Opacity(
                    opacity: (v * 2).clamp(0.0, 1.0),
                    child: Transform.translate(
                      // The arrow arrives travelling its own way.
                      offset: Offset(0, (down ? -5 : 5) * (1 - p)),
                      child: child,
                    ),
                  );
                },
              ),
              const SizedBox(width: 5),
            ],
            Text(label, style: style, maxLines: 1, softWrap: false),
          ],
        ),
      ),
    );
  }
}
