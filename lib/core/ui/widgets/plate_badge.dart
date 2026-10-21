import 'package:flutter/material.dart';

import '../../utils/format.dart';

/// Turkish licence plate look: blue "TR" strip on the left, white plate,
/// dark frame. [fontSize] scales everything (≈12 in lists, 16 in details).
///
/// Ported from F2GO's `PlakaRozeti`; the plate stays white in dark mode (it
/// depicts a physical plate).
class PlateBadge extends StatelessWidget {
  const PlateBadge({super.key, required this.plate, this.fontSize = 16});

  /// Raw or formatted plate; shown formatted (`34 ABC 123`).
  final String plate;
  final double fontSize;

  static const _trBlue = Color(0xFF1D4ED8);
  static const _ink = Color(0xFF0F172A);

  @override
  Widget build(BuildContext context) {
    final o = fontSize / 16;
    final radius = BorderRadius.circular(6 * o);
    final text = Fmt.plate(plate);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Semantics(
        label: 'Plaka $text',
        excludeSemantics: true,
        child: ClipRRect(
          borderRadius: radius,
          child: Container(
            color: const Color(0xFFFFFFFF),
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: _ink, width: 1.5 * o.clamp(0.8, 1.0)),
            ),
            child: IntrinsicHeight(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18 * o,
                    color: _trBlue,
                    alignment: Alignment.bottomCenter,
                    padding: EdgeInsets.only(bottom: 3 * o),
                    child: Text(
                      'TR',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 8 * o,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10 * o,
                      vertical: 4 * o,
                    ),
                    child: Text(
                      text,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2 * o,
                        color: _ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
