import 'package:flutter/material.dart';

import '../../utils/format.dart';
import '../motion.dart';
import '../theme.dart';

/// A number that counts up (big statistic values, KPI tiles, deck cards).
///
/// * First show: counts from [from] (default 0) to [value]; later changes
///   count from the value on screen to the new one.
/// * [AknMotion.count] (700 ms, range 600–900) with `easeOutCubic`.
/// * Reduce motion (`MediaQuery.disableAnimations`): the value shows at once.
/// * [format] turns the running value into text (`Fmt.money`,
///   `Fmt.liters`, …); integers count in whole steps. Defaults to
///   `Fmt.integer` (`12.500`).
/// * Tabular figures, so the width does not jitter while counting; the
///   style defaults to `context.aknText.number` (28 w800).
/// * Screen readers hear only the final formatted value ([semanticsLabel]
///   overrides it).
///
/// ```dart
/// AnimatedNumber(
///   value: stats.sales.amount,
///   format: Fmt.moneyCompact,
///   style: context.aknText.number,
/// )
/// ```
class AnimatedNumber extends StatefulWidget {
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

  /// Formatter for the running value; integers get whole numbers.
  final String Function(num value)? format;
  final TextStyle? style;

  /// Start value of the first count-up.
  final num from;
  final Duration duration;
  final Curve curve;
  final TextAlign? textAlign;
  final int maxLines;
  final String? semanticsLabel;

  /// Scale the text down to the available width (big numbers in narrow
  /// tiles) instead of wrapping.
  final bool fit;

  @override
  State<AnimatedNumber> createState() => _AnimatedNumberState();
}

class _AnimatedNumberState extends State<AnimatedNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late double _begin = widget.from.toDouble();
  late double _end = widget.value.toDouble();
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context) || _begin == _end) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(AnimatedNumber old) {
    super.didUpdateWidget(old);
    if (old.duration != widget.duration) _c.duration = widget.duration;
    final next = widget.value.toDouble();
    if (next == _end) return;
    _begin = _current;
    _end = next;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  double get _current {
    final t = widget.curve.transform(_c.value.clamp(0.0, 1.0));
    return _begin + (_end - _begin) * t;
  }

  String _text(double v) {
    final isInt = widget.value is int;
    final shown = isInt ? v.round() : v;
    final f = widget.format;
    if (f != null) return f(shown);
    return Fmt.integer(shown);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ?? context.aknText.number;
    final style = base.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final finalText = _text(_end);
    return Semantics(
      label: widget.semanticsLabel ?? finalText,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final text = Text(
            _c.isCompleted ? finalText : _text(_current),
            style: style,
            maxLines: widget.maxLines,
            textAlign: widget.textAlign,
            overflow: widget.fit ? null : TextOverflow.ellipsis,
            softWrap: !widget.fit,
          );
          if (!widget.fit) return text;
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: switch (widget.textAlign) {
              TextAlign.center => Alignment.center,
              TextAlign.end ||
              TextAlign.right => AlignmentDirectional.centerEnd,
              _ => AlignmentDirectional.centerStart,
            },
            child: text,
          );
        },
      ),
    );
  }
}
