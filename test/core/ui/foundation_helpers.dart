// WCAG helpers for the foundation tests (tokens, contrast, typography, driver mode). They import
// only the foundation files, never the widget library, so a widget file that is mid-edit cannot
// stop the token tests from compiling.
import 'package:flutter/painting.dart';

/// WCAG 2.x contrast ratio of two opaque colours.
double wcag(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [fg] composited over [bg] (for translucent tokens).
Color blend(Color fg, Color bg) => Color.alphaBlend(fg, bg);
