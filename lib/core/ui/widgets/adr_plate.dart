import 'package:flutter/material.dart';

import '../../utils/turkish_text.dart';
import '../theme.dart';
import '../typography.dart';

/// The orange ADR hazard plate of a tanker (design v2 §6.16): 48 × 36,
/// logo orange, a 2.5 px black border (r4) and a 2.5 px middle rule, the
/// hazard number over the UN number in Mona Sans Condensed 800 14 ("30" over
/// "1202"). Driver and dispatch load lines only — never decorative.
///
/// Use [AdrPlate.forProduct] to pick the codes from a product name (Motorin
/// 30/1202, Kurşunsuz 33/1203, Kalorifer yakıtı 30/1202, LPG 23/1965).
class AdrPlate extends StatelessWidget {
  const AdrPlate({
    super.key,
    required this.hazard,
    required this.un,
    this.height = 36,
  });

  /// Hazard identification number (Kemler code): "30".
  final String hazard;

  /// UN number: "1202".
  final String un;

  /// 36 by default (width = height × 4 / 3); 28 for a small plate in rows.
  final double height;

  /// The ADR codes for a product name, or null when it is not a fuel the app
  /// knows.
  static (String hazard, String un)? codesFor(String? product) {
    final p = TurkishText.lower(product ?? '');
    if (p.isEmpty) return null;
    if (p.contains('lpg') || p.contains('otogaz')) return ('23', '1965');
    if (p.contains('kurşunsuz') || p.contains('benzin')) return ('33', '1203');
    if (p.contains('motorin') ||
        p.contains('dizel') ||
        p.contains('kalorifer') ||
        p.contains('mazot')) {
      return ('30', '1202');
    }
    return null;
  }

  /// The plate for [product], or null (draw nothing) when the codes are
  /// unknown.
  static AdrPlate? forProduct(String? product, {double height = 36}) {
    final codes = codesFor(product);
    if (codes == null) return null;
    return AdrPlate(hazard: codes.$1, un: codes.$2, height: height);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final k = height / 36;
    // The real ADR plate: retro-reflective orange with black ink.
    const ink = Color(0xFF000000);
    final style = TextStyle(
      fontFamily: AknFonts.condensed,
      fontSize: 14 * k,
      height: 1,
      fontWeight: FontWeight.w800,
      color: ink,
    );
    return Semantics(
      label: 'Tehlike levhası $hazard, UN $un',
      excludeSemantics: true,
      child: Container(
        width: height * 4 / 3,
        height: height,
        decoration: BoxDecoration(
          color: c.isDark ? c.brandPressed : c.logo,
          borderRadius: BorderRadius.circular(4 * k),
          border: Border.all(color: ink, width: 2.5 * k),
        ),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Text(
                  hazard,
                  style: style,
                  textScaler: TextScaler.noScaling,
                ),
              ),
            ),
            Container(height: 2.5 * k, color: ink),
            Expanded(
              child: Center(
                child: Text(un, style: style, textScaler: TextScaler.noScaling),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
