import 'package:flutter/material.dart';

import '../../utils/format.dart';
import '../motion.dart';
import '../theme.dart';

/// A formatted number (KPI values, totals) — design v2 §6.9, §8.3: it **no
/// longer counts up**. Only the plate's figure rolls (`RollingFigure`);
/// every other number shows its final value at once, so the screen is calm
/// and the value is readable from the first frame.
///
/// * [format] turns the value into text (`Fmt.money`, `Fmt.liters`, …);
///   integers stay whole. Defaults to `Fmt.integer` (`12.500`).
/// * Proportional figures (no tabular digits: Mona's `tnum` is code-styled);
///   the style defaults to `context.aknText.number` (Condensed 24/28 700).
/// * Screen readers hear the formatted value ([semanticsLabel] overrides).
/// * [from], [duration] and [curve] are kept for API stability and ignored.
///
/// ```dart
/// AnimatedNumber(
///   value: stats.sales.amount,
///   format: Fmt.moneyCompact,
///   style: context.aknText.number,
/// )
/// ```
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber({
    super.key,
    required this.value,
    this.format,
    this.style,
    this.from = 0,
    this.duration = AknMotion.count,
    this.curve = Curves.easeOutCubic,
    this.textAlign,
    this.maxLines = 1,
    this.semanticsLabel,
    this.fit = false,
  });

  final num value;

  /// Formatter for the value; integers get whole numbers.
  final String Function(num value)? format;
  final TextStyle? style;

  /// Ignored in v2 (no count-up).
  final num from;

  /// Ignored in v2 (no count-up).
  final Duration duration;

  /// Ignored in v2 (no count-up).
  final Curve curve;
  final TextAlign? textAlign;
  final int maxLines;
  final String? semanticsLabel;

  /// Scale the text down to the available width (big numbers in narrow
  /// tiles) instead of wrapping.
  final bool fit;

  String get _text {
    final f = format;
    if (f != null) return f(value);
    return Fmt.integer(value);
  }

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? context.aknText.number;
    final text = _text;
    final label = Text(
      text,
      style: style,
      maxLines: maxLines,
      textAlign: textAlign,
      overflow: fit ? null : TextOverflow.ellipsis,
      softWrap: !fit,
    );
    return Semantics(
      label: semanticsLabel ?? text,
      excludeSemantics: true,
      child: !fit
          ? label
          : FittedBox(
              fit: BoxFit.scaleDown,
              alignment: switch (textAlign) {
                TextAlign.center => Alignment.center,
                TextAlign.end ||
                TextAlign.right => AlignmentDirectional.centerEnd,
                _ => AlignmentDirectional.centerStart,
              },
              child: label,
            ),
    );
  }
}
