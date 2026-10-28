import 'package:flutter/material.dart';

import '../../utils/turkish_text.dart';
import '../theme.dart';
import '../typography.dart';

/// The orange ADR hazard plate of a tanker (design v3 §4): 48 × 36 (4 : 3,
/// like the real 40 × 30 cm plate), retro-reflective orange with a soft
/// sheen from the top, a black border (2.5, r3.5) and a black middle rule,
/// the hazard number over the UN number in Plus Jakarta Sans 800 with
/// tabular figures ("30" over "1202"). It sits on the surface with a small
/// contact shadow (dark mode: a hairline ring keeps its black border
/// visible). Driver and dispatch load lines only — never decorative.
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

  // The plate's own colours (a physical object, the same in both themes;
  // dimmed a little at night so it does not glare).
  static const Color _ink = Color(0xFF111111);
  static const Color _orangeTop = Color(0xFFFF9A2E);
  static const Color _orangeBottom = Color(0xFFF2700F);
  static const Color _nightTop = Color(0xFFE88A2A);
  static const Color _nightBottom = Color(0xFFD5640D);

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final k = height / 36;
    final style = TextStyle(
      fontFamily: AknFonts.sans,
      fontSize: 14 * k,
      height: 1,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.2 * k,
      color: _ink,
      fontFeatures: AknNumerals.tabular,
      leadingDistribution: TextLeadingDistribution.even,
      locale: AknFonts.locale,
    );
    final radius = BorderRadius.circular(3.5 * k);
    Widget number(String s) => Expanded(
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(s, style: style, textScaler: TextScaler.noScaling),
        ),
      ),
    );
    return Semantics(
      label: 'Tehlike levhası $hazard, UN $un',
      excludeSemantics: true,
      child: Container(
        width: height * 4 / 3,
        height: height,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: c.isDark
                ? const [_nightTop, _nightBottom]
                : const [_orangeTop, _orangeBottom],
          ),
          border: Border.all(color: _ink, width: 2.5 * k),
          boxShadow: [
            if (c.isDark)
              const BoxShadow(color: Color(0x2EFFFFFF), spreadRadius: 1)
            else
              BoxShadow(
                color: const Color(0x2E15171A),
                offset: Offset(0, 1 * k),
                blurRadius: 3 * k,
              ),
          ],
        ),
        child: Stack(
          children: [
            // The retro-reflective sheeting catches the light at the top.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: height * 0.32,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: c.isDark ? 0.12 : 0.22),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Column(
              children: [
                number(hazard),
                Container(height: 2.5 * k, color: _ink),
                number(un),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
