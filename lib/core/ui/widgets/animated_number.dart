import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../utils/format.dart';
import '../motion.dart';
import '../theme.dart';
import '../typography.dart';

/// A formatted number that counts (design v3 §5 "Numbers"): on first
/// appearance it counts up from [from] (0) to [value], and when [value]
/// changes it counts from the number on screen to the new one — over
/// [duration] (`AknMotion.count`, 600 ms) on [curve] (standard). Under the
/// OS reduce-motion setting the final value shows at once.
///
/// * [format] turns the value into text (`Fmt.money`, `Fmt.liters`, …);
///   integer targets count in whole steps. Defaults to `Fmt.integer`
///   (`12.500`).
/// * Tabular figures ([AknNumerals.tabular]) and a box held at the final
///   value's width: the digits tick in place, nothing beside the number
///   moves while it counts. The style defaults to `context.aknText.number`
///   (24/30 800).
/// * Screen readers hear the final formatted value once ([semanticsLabel]
///   overrides), never the intermediate ones.
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

  /// Formatter for the value; integers get whole numbers.
  final String Function(num value)? format;
  final TextStyle? style;

  /// Where the first count starts (0).
  final num from;

  /// Length of one count (`AknMotion.count`, 600 ms).
  final Duration duration;

  /// Easing of the count (standard).
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
    value: 1,
  );
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _c,
    curve: widget.curve,
  );
  late num _begin = widget.value;
  late num _end = widget.value;
  bool _started = false;

  Object get _handoffKey => ('AnimatedNumber', _text(widget.value));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // A wrapper that remounted this number mid-entrance hands over where the
    // count was, so it never restarts from zero.
    final handed = AknEntranceHandoff.take(_handoffKey);
    if (handed != null) {
      _begin = widget.from;
      _end = widget.value;
      final d = AknMotion.of(context, widget.duration);
      _c.value = handed;
      if (handed < 1 && d > Duration.zero) {
        _c.duration = d;
        _c.forward();
      }
      return;
    }
    _count(from: widget.from, to: widget.value);
  }

  @override
  void deactivate() {
    AknEntranceHandoff.put(_handoffKey, _c.value);
    super.deactivate();
  }

  @override
  void didUpdateWidget(AnimatedNumber old) {
    super.didUpdateWidget(old);
    if (old.curve != widget.curve) _t.curve = widget.curve;
    if (old.value != widget.value) _count(from: _shown, to: widget.value);
  }

  @override
  void dispose() {
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  bool _finite(num v) => v is int || (v.isFinite && !v.isNaN);

  void _count({required num from, required num to}) {
    _begin = from;
    _end = to;
    final d = AknMotion.of(context, widget.duration);
    if (d == Duration.zero || from == to || !_finite(from) || !_finite(to)) {
      _c.value = 1;
      return;
    }
    _c.duration = d;
    _c.forward(from: 0);
  }

  /// The number on screen right now.
  num get _shown {
    final v = _t.value;
    if (v >= 1 || _c.isCompleted) return _end;
    final x = _begin + (_end - _begin) * v;
    return _end is int && _begin is int ? x.round() : x;
  }

  String _text(num v) {
    final f = widget.format;
    if (f != null) return f(v);
    return Fmt.integer(v);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final style = (w.style ?? context.aknText.number).copyWith(
      fontFeatures: AknNumerals.tabular,
    );
    final finalText = _text(w.value);
    // The box keeps the final value's width (measured once per build, not
    // per frame), so the digits tick in place; while it counts down from a
    // wider number it holds that width instead, and settles on the final
    // one when the count ends.
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    double measure(String text) => AknNumerals.fixedWidth(
      text,
      effective,
      textScaler: scaler,
      textDirection: direction,
    );
    final width = measure(finalText);
    final counting = !_c.isCompleted && _begin != _end;
    final countWidth = counting
        ? math.max(width, measure(_text(_begin)))
        : width;
    final Widget number = AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final settled = _t.value >= 1 || _c.isCompleted;
        return ConstrainedBox(
          constraints: BoxConstraints(minWidth: settled ? width : countWidth),
          child: Text(
            settled ? finalText : _text(_shown),
            style: style,
            maxLines: w.maxLines,
            textAlign: w.textAlign,
            overflow: w.fit ? null : TextOverflow.ellipsis,
            softWrap: !w.fit,
          ),
        );
      },
    );
    return Semantics(
      label: w.semanticsLabel ?? finalText,
      excludeSemantics: true,
      child: !w.fit
          ? number
          : FittedBox(
              fit: BoxFit.scaleDown,
              alignment: switch (w.textAlign) {
                TextAlign.center => Alignment.center,
                TextAlign.end ||
                TextAlign.right => AlignmentDirectional.centerEnd,
                _ => AlignmentDirectional.centerStart,
              },
              child: number,
            ),
    );
  }
}

/// Hands a one-shot entrance (a count-up, a reveal, a sweep) from a State
/// that is being thrown away to the State that replaces it in the same
/// frame, so the entrance never plays twice. Some wrappers rebuild their
/// child under a different parent when their own animation ends, which
/// remounts the child; without the handoff its entrance would restart.
///
/// Building blocks call [put] from `State.deactivate` with a key that
/// names the content (e.g. `('AnimatedNumber', '12.500')`) and [take] when
/// they first start. Entries are dropped at the end of the frame that put
/// them (a post-frame callback, after the replacement was built), so only a
/// replacement built in the same frame can pick one up — and no animation
/// callback is left behind when the tree is torn down.
abstract final class AknEntranceHandoff {
  static final Map<Object, List<double>> _stash = {};
  static bool _clearing = false;

  /// Remembers the [progress] (0–1) of the entrance named by [key].
  static void put(Object key, double progress) {
    (_stash[key] ??= []).add(progress.clamp(0.0, 1.0));
    if (_clearing) return;
    _clearing = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _stash.clear();
      _clearing = false;
    }, debugLabel: 'AknEntranceHandoff.clear');
  }

  /// The progress handed over for [key] in this frame, if any (each entry
  /// is taken once).
  static double? take(Object key) {
    final list = _stash[key];
    if (list == null || list.isEmpty) return null;
    final v = list.removeAt(0);
    if (list.isEmpty) _stash.remove(key);
    return v;
  }
}
