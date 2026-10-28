import 'package:flutter/material.dart';

import '../../utils/format.dart';
import '../tokens.dart';
import '../typography.dart';

/// Turkish licence plate (design v3 §4): a white plate with a faint
/// top-to-bottom sheen, a 1.5 px graphite rim and radius 5, a soft contact
/// shadow, the blue TR strip (#1D4AB4, 16 wide, "TR" white 8 700 at the
/// bottom) and the number in Plus Jakarta Sans 700 with tabular figures
/// and 0.6 tracking. 28 px high at the default [fontSize] 15, 32 in driver
/// mode (17).
///
/// It depicts a physical plate, so it stays white in dark mode and its text
/// grows at most 1.3× with the text size.
class PlateBadge extends StatelessWidget {
  const PlateBadge({super.key, required this.plate, this.fontSize = 15});

  /// Raw or formatted plate; shown formatted (`34 ABC 123`).
  final String plate;

  /// Number size (15 → a 28 px plate; 17 → 32 px).
  final double fontSize;

  /// The TR strip blue — the only blue in the app (§0).
  static const Color trBlue = Color(0xFF1D4AB4);

  @override
  Widget build(BuildContext context) {
    const paper = AknColors.light;
    final o = fontSize / 15;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
    final k = o * scale;
    final text = Fmt.plate(plate);
    final height = 28 * k;
    final ink = paper.onPlate;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Semantics(
        label: 'Plaka $text',
        excludeSemantics: true,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFFFFF), Color(0xFFF1F2F4)],
            ),
            borderRadius: BorderRadius.circular(5 * k),
            border: Border.all(color: ink, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2915171A),
                offset: Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 16 * k,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      trBlue,
                      Color.alphaBlend(const Color(0x2E000000), trBlue),
                    ],
                  ),
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
                    letterSpacing: 0.2,
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
                    fontFamily: AknFonts.sans,
                    fontSize: fontSize * scale,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6 * k,
                    fontFeatures: AknNumerals.tabular,
                    color: ink,
                    leadingDistribution: TextLeadingDistribution.even,
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
