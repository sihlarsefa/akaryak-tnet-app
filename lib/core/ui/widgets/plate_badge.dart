import 'package:flutter/material.dart';

import '../../utils/format.dart';
import '../tokens.dart';
import '../typography.dart';

/// Turkish licence plate (design v2 §6.16): white, 1.5 px black border, r5,
/// the blue TR strip (#1D4AB4, 16 wide, "TR" white 8/1 700 at the bottom)
/// and the number in Mona Sans Condensed 700 with 0.6 tracking. 28 px high
/// at the default [fontSize] 15, 32 in driver mode (17).
///
/// It depicts a physical plate, so it stays white in dark mode and its text
/// grows at most 1.3× with the text size.
class PlateBadge extends StatelessWidget {
  const PlateBadge({super.key, required this.plate, this.fontSize = 15});

  /// Raw or formatted plate; shown formatted (`34 ABC 123`).
  final String plate;

  /// Number size (15 → a 28 px plate; 17 → 32 px).
  final double fontSize;

  /// The TR strip blue — the only blue in the app (§2.1).
  static const Color trBlue = Color(0xFF1D4AB4);

  @override
  Widget build(BuildContext context) {
    const paper = AknColors.light;
    final o = fontSize / 15;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
    final k = o * scale;
    final text = Fmt.plate(plate);
    final height = 28 * k;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Semantics(
        label: 'Plaka $text',
        excludeSemantics: true,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: paper.surface,
            borderRadius: BorderRadius.circular(5 * k),
            border: Border.all(color: paper.onPlate, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 16 * k,
                decoration: BoxDecoration(
                  color: trBlue,
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(3.5 * k),
                  ),
                ),
                alignment: Alignment.bottomCenter,
                padding: EdgeInsets.only(bottom: 3.5 * k),
                child: Text(
                  'TR',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontFamily: AknFonts.sans,
                    fontSize: 8 * k,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: paper.surface,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(7 * k, 0, 8 * k, 0),
                child: Text(
                  text,
                  maxLines: 1,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontFamily: AknFonts.condensed,
                    fontSize: fontSize * scale,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6 * k,
                    color: paper.onPlate,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
