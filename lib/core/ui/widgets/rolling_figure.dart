import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';

/// The plate figure as an odometer (design v3 §5 "Numbers"): every digit is
/// a wheel that spins up, turns once round and settles on its digit, the
/// wheels landing one after another from left to right with a soft click
/// (a sixteenth of a digit past it, then back). A fast wheel is drawn with a
/// light vertical motion blur and the drum edges fade through a mask, so the
/// roll reads smooth at 60 fps instead of strobing.
///
/// * **First build**: the figure rolls in ([_introDuration], fading in over
///   the first 140 ms). With [animate] it plays the full home-moment roll
///   instead — [duration] ([AknMotion.plateRoll], 900 ms) after [delay],
///   with [onRollStart] / [onRollEnd] — which the deck runs once per
///   session (`plateRollSeenProvider`).
/// * **Value changes** (pull-to-refresh, the driver's next stop) roll each
///   wheel from its old digit to its new one over [AknMotion.count], forward
///   when the value grows and backward when it shrinks; unchanged digits
///   stay still.
/// * Every digit sits in a **fixed slot** — the slot of its final digit,
///   measured from the settled text — and all figures are tabular, so the
///   figure never jitters and the last frame equals plain text.
/// * Reduce motion: the final frame at once (the roll still counts as seen:
///   [onRollStart] is called).
///
/// [value] is the formatted figure ("1.524.380", "42,34", "%72"); [decimals]
/// (",00") and [unit] ("₺", "L", "₺/L") or [unitSpan] are drawn after it on
/// the same baseline, statically, so nothing can wrap between the number and
/// its unit. Screen readers hear the final value once.
class RollingFigure extends StatefulWidget {
  const RollingFigure({
    super.key,
    required this.value,
    this.style,
    this.decimals,
    this.unit,
    this.unitStyle,
    this.unitSpan,
    this.unitGap = 6,
    this.decimalsGap = 1,
    this.animate = false,
    this.delay = Duration.zero,
    this.duration = AknMotion.plateRoll,
    this.onRollStart,
    this.onRollEnd,
    this.fadeColor,
    this.semanticLabel,
  });

  /// The formatted figure (tr_TR): "1.524.380", "42,34", "%72".
  final String value;

  /// Figure style; defaults to `context.aknText.plateFigure`.
  final TextStyle? style;

  /// Static decimals right after the figure (",00"), in [unitStyle].
  final String? decimals;

  /// Unit after a [unitGap] gap ("₺", "L", "₺/L"), in [unitStyle].
  final String? unit;

  /// Unit / decimals style; defaults to `context.aknText.plateUnit`.
  final TextStyle? unitStyle;

  /// A custom unit span (e.g. a figure word in `figureWord`); overrides
  /// [unit].
  final InlineSpan? unitSpan;

  /// Gap before the unit (6 on the plate); scales with the text.
  final double unitGap;

  /// Gap before [decimals] (1).
  final double decimalsGap;

  /// Play the full home-moment roll (after [delay], with the callbacks)
  /// instead of the quick roll-in. Ignored under reduce motion.
  final bool animate;

  /// Wait before the [animate] roll (e.g. [AknMotion.plateLight] while the
  /// plate lights).
  final Duration delay;

  /// Length of the [animate] roll.
  final Duration duration;

  /// Called (after the frame) when the [animate] roll starts — or, under
  /// reduce motion, when the final frame is shown instead: the moment is
  /// consumed either way (set `plateRollSeenProvider` here).
  final VoidCallback? onRollStart;
  final VoidCallback? onRollEnd;

  /// Deprecated: the drum edges now fade through a mask, whatever lies
  /// behind the figure. Kept for API stability.
  final Color? fadeColor;

  /// Screen-reader text; defaults to the value, decimals and unit.
  final String? semanticLabel;

  /// The quick roll-in of a figure shown without [animate].
  static const Duration _introDuration = Duration(milliseconds: 820);

  /// Position of digit wheel [k] (0 = the rightmost digit) of a counting
  /// register that shows [v] (0 ≤ position < 10, fractional while turning):
  /// the carry model of design v2 §8.1, kept for callers that count.
  static double wheelPosition(double v, int k) {
    if (k <= 0) return v - 10 * (v / 10).floorToDouble();
    final p = math.pow(10, k).toDouble();
    final whole = (v / p).floorToDouble();
    final base = whole - 10 * (whole / 10).floorToDouble();
    final rem = v - p * whole;
    final carry = (rem - (p - 1)).clamp(0.0, 1.0);
    return base + carry;
  }

  /// The digits of [value] as one integer ("1.524.380" → 1524380).
  static int targetOf(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0;
    return int.tryParse(digits) ?? 0;
  }

  @override
  State<RollingFigure> createState() => _RollingFigureState();
}

class _RollingFigureState extends State<RollingFigure>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );
  Timer? _delay;
  bool _scheduled = false;
  _FigureLayout? _layout;
  _Roll _roll = const _Roll.intro();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = AknMotion.reduced(context);
    if (!_scheduled) {
      _scheduled = true;
      final digits = _hasDigit(widget.value);
      if (widget.animate) {
        final rolls = !reduced && digits;
        if (rolls) _c.value = 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!rolls) {
            widget.onRollStart?.call();
            return;
          }
          if (widget.delay <= Duration.zero) {
            _start();
          } else {
            _delay = Timer(widget.delay, _start);
          }
        });
      } else if (!reduced && digits) {
        // Every other figure rolls in quickly on its first build.
        _c
          ..duration = RollingFigure._introDuration
          ..forward(from: 0);
      }
    } else if (reduced && _c.value < 1) {
      _delay?.cancel();
      _c.value = 1;
    }
  }

  void _start() {
    if (!mounted) return;
    widget.onRollStart?.call();
    if (AknMotion.reduced(context)) {
      _c.value = 1;
      widget.onRollEnd?.call();
      return;
    }
    setState(() {
      _roll = const _Roll.intro();
      _c.duration = widget.duration;
    });
    _c.forward(from: 0).whenComplete(() {
      if (mounted) widget.onRollEnd?.call();
    });
  }

  @override
  void didUpdateWidget(RollingFigure old) {
    super.didUpdateWidget(old);
    if (old.duration != widget.duration && widget.animate) {
      _c.duration = widget.duration;
    }
    if (old.value != widget.value &&
        !(_delay?.isActive ?? false) &&
        !AknMotion.reduced(context) &&
        _hasDigit(old.value) &&
        _hasDigit(widget.value)) {
      _roll = _Roll.change(
        _digitsFromRight(old.value),
        up:
            RollingFigure.targetOf(widget.value) >=
            RollingFigure.targetOf(old.value),
      );
      _c
        ..duration = AknMotion.count
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    _layout?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final style = t.plateFigure.merge(widget.style);
    final unitStyle = t.plateUnit.merge(widget.unitStyle);
    final scaler = MediaQuery.textScalerOf(context);
    final key = _LayoutKey(
      value: widget.value,
      style: style,
      decimals: widget.decimals,
      unit: widget.unit,
      unitStyle: unitStyle,
      unitSpan: widget.unitSpan,
      unitGap: widget.unitGap,
      decimalsGap: widget.decimalsGap,
      scaler: scaler,
    );
    var layout = _layout;
    if (layout == null || layout.key != key) {
      layout?.dispose();
      layout = _layout = _FigureLayout(key);
    }
    final spoken =
        widget.semanticLabel ??
        [
          '${widget.value}${widget.decimals ?? ''}',
          if (widget.unitSpan != null)
            widget.unitSpan!.toPlainText()
          else if (widget.unit != null)
            widget.unit!,
        ].join(' ');
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: CustomPaint(
        size: layout.size,
        painter: _RollPainter(
          layout: layout,
          progress: _c,
          roll: _roll,
          seconds: (_c.duration ?? widget.duration).inMicroseconds / 1e6,
        ),
      ),
    );
  }
}

@immutable
class _LayoutKey {
  const _LayoutKey({
    required this.value,
    required this.style,
    required this.decimals,
    required this.unit,
    required this.unitStyle,
    required this.unitSpan,
    required this.unitGap,
    required this.decimalsGap,
    required this.scaler,
  });

  final String value;
  final TextStyle style;
  final String? decimals;
  final String? unit;
  final TextStyle unitStyle;
  final InlineSpan? unitSpan;
  final double unitGap;
  final double decimalsGap;
  final TextScaler scaler;

  @override
  bool operator ==(Object other) =>
      other is _LayoutKey &&
      other.value == value &&
      other.style == style &&
      other.decimals == decimals &&
      other.unit == unit &&
      other.unitStyle == unitStyle &&
      other.unitSpan == unitSpan &&
      other.unitGap == unitGap &&
      other.decimalsGap == decimalsGap &&
      other.scaler == scaler;

  @override
  int get hashCode => Object.hash(
    value,
    style,
    decimals,
    unit,
    unitStyle,
    unitSpan,
    unitGap,
    decimalsGap,
    scaler,
  );
}

/// The measured figure: settled text, digit wheels, separators.
class _FigureLayout {
  _FigureLayout(this.key) {
    const ltr = TextDirection.ltr;
    figure = TextPainter(
      text: TextSpan(text: key.value, style: key.style),
      textDirection: ltr,
      textScaler: key.scaler,
      maxLines: 1,
    )..layout();
    final dec = key.decimals;
    if (dec != null && dec.isNotEmpty) {
      decimals = TextPainter(
        text: TextSpan(text: dec, style: key.unitStyle),
        textDirection: ltr,
        textScaler: key.scaler,
        maxLines: 1,
      )..layout();
    }
    final span =
        key.unitSpan ??
        (key.unit == null || key.unit!.isEmpty
            ? null
            : TextSpan(text: key.unit, style: key.unitStyle));
    if (span != null) {
      unit = TextPainter(
        text: TextSpan(style: key.unitStyle, children: [span]),
        textDirection: ltr,
        textScaler: key.scaler,
        maxLines: 1,
      )..layout();
    }

    // Baselines: the figure, the decimals and the unit share one.
    const alpha = TextBaseline.alphabetic;
    final figBase = figure.computeDistanceToActualBaseline(alpha);
    final decBase = decimals?.computeDistanceToActualBaseline(alpha) ?? 0;
    final unitBase = unit?.computeDistanceToActualBaseline(alpha) ?? 0;
    final baseline = [
      figBase,
      if (decimals != null) decBase,
      if (unit != null) unitBase,
    ].reduce(math.max);
    figTop = baseline - figBase;
    decTop = baseline - decBase;
    unitTop = baseline - unitBase;
    var x = figure.width;
    if (decimals != null) {
      decLeft = x + key.scaler.scale(key.decimalsGap);
      x = decLeft + decimals!.width;
    }
    if (unit != null) {
      unitLeft = x + key.scaler.scale(key.unitGap);
      x = unitLeft + unit!.width;
    }
    final bottom = [
      figTop + figure.height,
      if (decimals != null) decTop + decimals!.height,
      if (unit != null) unitTop + unit!.height,
    ].reduce(math.max);
    size = Size(x.ceilToDouble(), bottom.ceilToDouble());

    // One wheel per digit, in the settled text's own glyph boxes.
    final text = key.value;
    final digitIdx = <int>[
      for (var i = 0; i < text.length; i++)
        if (_isDigit(text.codeUnitAt(i))) i,
    ];
    for (var n = 0; n < digitIdx.length; n++) {
      final i = digitIdx[n];
      wheels.add(
        _Wheel(
          _box(i).shift(Offset(0, figTop)),
          k: digitIdx.length - 1 - n,
          digit: text.codeUnitAt(i) - 0x30,
          glyphTop: figTop,
        ),
      );
    }
  }

  final _LayoutKey key;
  late final TextPainter figure;
  TextPainter? decimals;
  TextPainter? unit;
  late final double figTop;
  late final double decTop;
  late final double unitTop;
  double decLeft = 0;
  double unitLeft = 0;
  late final Size size;
  final List<_Wheel> wheels = [];
  List<TextPainter>? _digits;
  TextPainter? _statics;

  /// The settled figure with its digits made transparent: separators and
  /// signs exactly where the plain text puts them.
  TextPainter get statics => _statics ??= TextPainter(
    text: _hideDigits(TextSpan(text: key.value, style: key.style)),
    textDirection: TextDirection.ltr,
    textScaler: key.scaler,
    maxLines: 1,
  )..layout();

  Rect _box(int i) {
    final boxes = figure.getBoxesForSelection(
      TextSelection(baseOffset: i, extentOffset: i + 1),
    );
    if (boxes.isEmpty) return Rect.zero;
    final b = boxes.first.toRect();
    return Rect.fromLTRB(b.left, 0, b.right, figure.height);
  }

  List<TextPainter> get digits =>
      _digits ??= _digitPainters(key.style, key.scaler);

  void dispose() {
    figure.dispose();
    decimals?.dispose();
    unit?.dispose();
    _statics?.dispose();
    for (final p in _digits ?? const <TextPainter>[]) {
      p.dispose();
    }
  }

  void paint(Canvas canvas, double t, _Roll roll, double seconds) {
    if (t >= 1 || wheels.isEmpty) {
      figure.paint(canvas, Offset(0, figTop));
      decimals?.paint(canvas, Offset(decLeft, decTop));
      unit?.paint(canvas, Offset(unitLeft, unitTop));
      return;
    }
    final bounds = Offset.zero & size;
    final alpha = roll.isIntro
        ? Curves.easeOut.transform((t * seconds / 0.14).clamp(0.0, 1.0))
        : 1.0;
    if (alpha <= 0) return;
    if (alpha < 1) {
      canvas.saveLayer(
        bounds.inflate(4),
        Paint()..color = Color.fromRGBO(0, 0, 0, alpha),
      );
    }
    decimals?.paint(canvas, Offset(decLeft, decTop));
    unit?.paint(canvas, Offset(unitLeft, unitTop));
    statics.paint(canvas, Offset(0, figTop));
    _paintWheels(canvas, wheels, digits, t, roll, seconds);
    if (alpha < 1) canvas.restore();
  }
}

class _RollPainter extends CustomPainter {
  _RollPainter({
    required this.layout,
    required this.progress,
    required this.roll,
    required this.seconds,
  }) : super(repaint: progress);

  final _FigureLayout layout;
  final Animation<double> progress;
  final _Roll roll;
  final double seconds;

  @override
  void paint(Canvas canvas, Size size) =>
      layout.paint(canvas, progress.value, roll, seconds);

  @override
  bool shouldRepaint(_RollPainter old) =>
      old.layout != layout ||
      old.progress != progress ||
      old.roll != roll ||
      old.seconds != seconds;
}

/// A [Text.rich] whose digits roll into place like the plate figure (design
/// v3 §5 "Numbers": readouts and KPI values count up): on its first build
/// every digit wheel spins one turn and lands, left to right, over
/// [duration] after [delay]; when its digits change later they roll from
/// the old digits to the new ones over [AknMotion.count]. Separators, units
/// and words stay still.
///
/// The real [Text.rich] stays in the tree the whole time (layout, screen
/// readers and finders see the final text; it is only hidden while the
/// wheels are drawn over it), so the last frame is the plain text. Static
/// under reduce motion or with [animate] false.
class RollingText extends StatefulWidget {
  const RollingText(
    this.span, {
    super.key,
    this.animate = true,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 720),
    this.maxLines = 1,
    this.softWrap = false,
    this.textAlign,
  });

  /// The text as it settles (e.g. a readout value and its unit).
  final InlineSpan span;

  /// Roll in on the first build.
  final bool animate;
  final Duration delay;
  final Duration duration;
  final int? maxLines;
  final bool softWrap;
  final TextAlign? textAlign;

  @override
  State<RollingText> createState() => _RollingTextState();
}

class _RollingTextState extends State<RollingText>
    with SingleTickerProviderStateMixin {
  // Created up front: a text that never rolls must not create its ticker in
  // dispose(), when the element is no longer active.
  late final AnimationController _c;
  Timer? _timer;
  bool _started = false;
  bool _rolling = false;
  _Roll _roll = const _Roll.intro();
  _SpanLayout? _layout;

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed && _rolling && mounted) {
      setState(() => _rolling = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration, value: 1)
      ..addStatusListener(_onStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = AknMotion.reduced(context);
    if (!_started) {
      _started = true;
      if (widget.animate &&
          !reduced &&
          _rollable(widget.span) &&
          _hasDigit(widget.span.toPlainText())) {
        _rolling = true;
        _c.value = 0;
        if (widget.delay <= Duration.zero) {
          _c.forward();
        } else {
          _timer = Timer(widget.delay, () {
            if (mounted) _c.forward();
          });
        }
      }
    } else if (reduced && _rolling) {
      _timer?.cancel();
      _c.value = 1;
      _rolling = false;
    }
  }

  @override
  void didUpdateWidget(RollingText old) {
    super.didUpdateWidget(old);
    final before = old.span.toPlainText();
    final after = widget.span.toPlainText();
    if (before != after &&
        !(_timer?.isActive ?? false) &&
        !AknMotion.reduced(context) &&
        _rollable(widget.span) &&
        _hasDigit(before) &&
        _hasDigit(after)) {
      _roll = _Roll.change(
        _digitsFromRight(before),
        up: RollingFigure.targetOf(after) >= RollingFigure.targetOf(before),
      );
      _rolling = true;
      _c
        ..duration = AknMotion.count
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    _layout?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Text.rich(
      widget.span,
      maxLines: widget.maxLines,
      softWrap: widget.softWrap,
      textAlign: widget.textAlign,
    );
    if (!_rolling) {
      return CustomPaint(
        child: Opacity(opacity: 1, alwaysIncludeSemantics: true, child: text),
      );
    }
    final key = _SpanKey.of(context, widget);
    var layout = _layout;
    if (layout == null || layout.key != key) {
      layout?.dispose();
      layout = _layout = _SpanLayout(key);
    }
    return CustomPaint(
      foregroundPainter: _SpanRollPainter(
        layout: layout,
        progress: _c,
        roll: _roll,
        seconds: (_c.duration ?? widget.duration).inMicroseconds / 1e6,
      ),
      child: Opacity(opacity: 0, alwaysIncludeSemantics: true, child: text),
    );
  }
}

/// Everything that shapes a [RollingText] the way its [Text.rich] does.
@immutable
class _SpanKey {
  const _SpanKey({
    required this.span,
    required this.scaler,
    required this.direction,
    required this.align,
    required this.maxLines,
    required this.heightBehavior,
    required this.widthBasis,
    required this.softWrap,
  });

  factory _SpanKey.of(BuildContext context, RollingText w) {
    final d = DefaultTextStyle.of(context);
    var style = d.style;
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    return _SpanKey(
      span: TextSpan(style: style, children: [w.span]),
      scaler: MediaQuery.textScalerOf(context),
      direction: Directionality.of(context),
      align: w.textAlign ?? d.textAlign ?? TextAlign.start,
      maxLines: w.maxLines ?? d.maxLines,
      heightBehavior:
          d.textHeightBehavior ?? DefaultTextHeightBehavior.maybeOf(context),
      widthBasis: d.textWidthBasis,
      softWrap: w.softWrap,
    );
  }

  final InlineSpan span;
  final TextScaler scaler;
  final TextDirection direction;
  final TextAlign align;
  final int? maxLines;
  final TextHeightBehavior? heightBehavior;
  final TextWidthBasis widthBasis;

  /// Wrapping text is laid out at its box width, the rest unbounded (as
  /// `RenderParagraph` does).
  final bool softWrap;

  @override
  bool operator ==(Object other) =>
      other is _SpanKey &&
      other.softWrap == softWrap &&
      other.span == span &&
      other.scaler == scaler &&
      other.direction == direction &&
      other.align == align &&
      other.maxLines == maxLines &&
      other.heightBehavior == heightBehavior &&
      other.widthBasis == widthBasis;

  @override
  int get hashCode => Object.hash(
    span,
    scaler,
    direction,
    align,
    maxLines,
    heightBehavior,
    widthBasis,
    softWrap,
  );
}

/// A laid-out [RollingText]: the settled paragraph, its wheels and the
/// digit glyphs of every digit style in it.
class _SpanLayout {
  _SpanLayout(this.key)
    : text = _painterFor(key, key.span),
      statics = _painterFor(key, _hideDigits(key.span));

  static TextPainter _painterFor(_SpanKey key, InlineSpan span) => TextPainter(
    text: span,
    textAlign: key.align,
    textDirection: key.direction,
    textScaler: key.scaler,
    maxLines: key.maxLines,
    textHeightBehavior: key.heightBehavior,
    textWidthBasis: key.widthBasis,
  );

  final _SpanKey key;
  final TextPainter text;

  /// [text] with its digits made transparent (same shaping: only colours
  /// differ), painted under the wheels.
  final TextPainter statics;
  final Map<TextStyle, List<TextPainter>> _digits = {};
  final List<_Wheel> wheels = [];
  final List<List<TextPainter>> wheelDigits = [];
  double? _width;

  /// Lays the paragraph out at [width] (the size of its [Text.rich]).
  void layoutAt(double width) {
    if (_width == width) return;
    _width = width;
    text.layout(
      minWidth: width,
      maxWidth: key.softWrap ? width : double.infinity,
    );
    statics.layout(
      minWidth: width,
      maxWidth: key.softWrap ? width : double.infinity,
    );
    wheels.clear();
    wheelDigits.clear();
    final plain = key.span.toPlainText(includeSemanticsLabels: false);
    final lines = text.computeLineMetrics();
    final digitIdx = <int>[
      for (var i = 0; i < plain.length; i++)
        if (_isDigit(plain.codeUnitAt(i))) i,
    ];
    for (var n = 0; n < digitIdx.length; n++) {
      final i = digitIdx[n];
      final boxes = text.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
        boxHeightStyle: ui.BoxHeightStyle.max,
      );
      final style = _styleAt(key.span, i);
      if (boxes.isEmpty || style == null) continue;
      final box = boxes.first.toRect();
      final set = _digits.putIfAbsent(
        style,
        () => _digitPainters(style, key.scaler),
      );
      // The digit glyphs sit on the baseline of the box's line.
      var baseline = box.bottom;
      for (final l in lines) {
        if (box.center.dy >= l.baseline - l.ascent &&
            box.center.dy <= l.baseline + l.descent) {
          baseline = l.baseline;
          break;
        }
      }
      final glyphBase = set.first.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      wheels.add(
        _Wheel(
          box,
          k: digitIdx.length - 1 - n,
          digit: plain.codeUnitAt(i) - 0x30,
          glyphTop: baseline - glyphBase,
        ),
      );
      wheelDigits.add(set);
    }
  }

  void paint(Canvas canvas, Size size, double t, _Roll roll, double seconds) {
    layoutAt(size.width);
    final alpha = roll.isIntro
        ? Curves.easeOut.transform((t * seconds / 0.14).clamp(0.0, 1.0))
        : 1.0;
    if (alpha <= 0) return;
    final bounds = (Offset.zero & size).inflate(4);
    if (alpha < 1) {
      canvas.saveLayer(bounds, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    }
    // Everything but the digits, from the settled paragraph.
    statics.paint(canvas, Offset.zero);
    _paintWheels(canvas, wheels, null, t, roll, seconds, sets: wheelDigits);
    if (alpha < 1) canvas.restore();
  }

  void dispose() {
    text.dispose();
    statics.dispose();
    for (final set in _digits.values) {
      for (final p in set) {
        p.dispose();
      }
    }
  }
}

class _SpanRollPainter extends CustomPainter {
  _SpanRollPainter({
    required this.layout,
    required this.progress,
    required this.roll,
    required this.seconds,
  }) : super(repaint: progress);

  final _SpanLayout layout;
  final Animation<double> progress;
  final _Roll roll;
  final double seconds;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t >= 1) return;
    layout.paint(canvas, size, t, roll, seconds);
  }

  @override
  bool shouldRepaint(_SpanRollPainter old) =>
      old.layout != layout ||
      old.progress != progress ||
      old.roll != roll ||
      old.seconds != seconds;
}

// ───────────────────────── The wheels ─────────────────────────

/// What a roll does: the first roll-in (every wheel spins one turn from 0
/// and lands on its digit) or a change from earlier digits.
@immutable
class _Roll {
  const _Roll.intro() : from = null, up = true;
  const _Roll.change(this.from, {required this.up});

  /// The earlier digits, from the right (index 0 = the units digit).
  final List<int>? from;

  /// The value grew (wheels turn forward) or shrank (backward).
  final bool up;

  bool get isIntro => from == null;
}

/// One digit wheel: its column (a full line box), its place from the right
/// ([k]), its settled [digit] and where its glyphs' tops sit.
class _Wheel {
  const _Wheel(
    this.box, {
    required this.k,
    required this.digit,
    required this.glyphTop,
  });

  final Rect box;
  final int k;
  final int digit;
  final double glyphTop;
}

bool _isDigit(int u) => u >= 0x30 && u <= 0x39;

bool _hasDigit(String s) => s.codeUnits.any(_isDigit);

/// True when [span] is plain text the wheels can draw: no widget
/// placeholders to lay out and no custom foreground paints.
bool _rollable(InlineSpan span) {
  var plain = true;
  span.visitChildren((s) {
    if (s is PlaceholderSpan || s.style?.foreground != null) plain = false;
    return plain;
  });
  return plain;
}

/// [span] with every run of digits in a transparent colour (a colour change
/// does not change shaping, so the rest lands exactly where the plain text
/// puts it).
InlineSpan _hideDigits(InlineSpan span) {
  if (span is! TextSpan) return span;
  final text = span.text;
  final runs = <InlineSpan>[];
  if (text != null) {
    var start = 0;
    while (start < text.length) {
      final digit = _isDigit(text.codeUnitAt(start));
      var end = start + 1;
      while (end < text.length && _isDigit(text.codeUnitAt(end)) == digit) {
        end++;
      }
      final part = text.substring(start, end);
      runs.add(
        digit
            ? TextSpan(
                text: part,
                style: const TextStyle(color: _clear),
              )
            : TextSpan(text: part),
      );
      start = end;
    }
  }
  return TextSpan(
    style: span.style,
    locale: span.locale,
    spellOut: span.spellOut,
    children: [
      ...runs,
      for (final child in span.children ?? const <InlineSpan>[])
        _hideDigits(child),
    ],
  );
}

const Color _clear = Color(0x00000000);

/// The digits of [s] from the right ("1.524" → [4, 2, 5, 1]).
List<int> _digitsFromRight(String s) => [
  for (final u in s.codeUnits.reversed)
    if (_isDigit(u)) u - 0x30,
];

/// The digits 0–9 set in [style] (tabular, so every one has the same
/// advance).
List<TextPainter> _digitPainters(TextStyle style, TextScaler scaler) => [
  for (var d = 0; d < 10; d++)
    TextPainter(
      text: TextSpan(text: '$d', style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout(),
];

/// The effective style of the character at [index] in [root].
TextStyle? _styleAt(InlineSpan root, int index) {
  var remaining = index;
  TextStyle? found;
  bool visit(InlineSpan span, TextStyle? inherited) {
    final style = inherited == null
        ? span.style
        : span.style == null
        ? inherited
        : inherited.merge(span.style);
    if (span is TextSpan) {
      final t = span.text;
      if (t != null) {
        if (remaining < t.length) {
          found = style;
          return false;
        }
        remaining -= t.length;
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        if (!visit(child, style)) return false;
      }
      return true;
    }
    // A placeholder (WidgetSpan) is one character.
    if (remaining == 0) return false;
    remaining -= 1;
    return true;
  }

  visit(root, null);
  return found;
}

/// Draws [wheels] at roll time [t]: each wheel turns from its start to its
/// end position (see [_Roll]), the wheels landing left to right; fast wheels
/// get a vertical motion blur, and the drum edges fade through a mask.
/// [digits] is the one glyph set of a figure; [sets] gives one per wheel.
void _paintWheels(
  Canvas canvas,
  List<_Wheel> wheels,
  List<TextPainter>? digits,
  double t,
  _Roll roll,
  double seconds, {
  List<List<TextPainter>>? sets,
}) {
  if (wheels.isEmpty) return;
  var area = wheels.first.box;
  for (final w in wheels) {
    area = area.expandToInclude(w.box);
  }
  canvas.saveLayer(area, Paint());
  final n = wheels.length;
  // The leftmost wheel lands first; each next one a step later.
  final step = n <= 1 ? 0.0 : math.min(0.06, 0.34 / (n - 1));
  final secs = seconds <= 0 ? 0.6 : seconds;
  for (var j = 0; j < n; j++) {
    final w = wheels[j];
    final set = sets?[j] ?? digits!;
    final end = 1 - (n - 1 - j) * step;
    final tau = (t / end).clamp(0.0, 1.0);
    final double from;
    final double to;
    final prev = roll.from;
    if (prev == null) {
      from = 0;
      to = 10.0 + w.digit;
    } else {
      final f = w.k < prev.length ? prev[w.k] : 0;
      from = f.toDouble();
      if (f == w.digit) {
        to = from;
      } else if (roll.up) {
        to = (w.digit < f ? w.digit + 10 : w.digit).toDouble();
      } else {
        to = (w.digit > f ? w.digit - 10 : w.digit).toDouble();
      }
    }
    final distance = to - from;
    // The wheel spins up and settles (CSS "ease": a soft start, a peak of
    // 2.3× its mean speed, a long settle), then clicks a little past its
    // digit and back in the last 16 % of its time.
    var pos = from + distance * _spin.transform(tau);
    if (distance != 0 && tau > 0.84 && tau < 1) {
      final u = (tau - 0.84) / 0.16;
      pos += distance.sign * 0.06 * math.sin(u * math.pi);
    }
    // Speed in digits per second (numerically) → a blur about a third of a
    // frame's travel, capped so a glyph never smears into a block.
    final ahead = (tau + 0.01).clamp(0.0, 1.0);
    final speed = tau >= 1
        ? 0.0
        : (distance * (_spin.transform(ahead) - _spin.transform(tau))).abs() /
              (0.01 * end * secs);
    final line = w.box.height;
    final travel = speed * line / 60;
    final sigma = math.min(line * 0.11, travel * 0.3);
    _paintWheel(canvas, w, set, pos, sigma);
  }
  // Drum shading: the digits fade out at the top and bottom of the line.
  canvas.drawRect(
    area,
    Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x00000000),
          Color(0xFF000000),
          Color(0xFF000000),
          Color(0x00000000),
        ],
        stops: [0, 0.13, 0.87, 1],
      ).createShader(area),
  );
  canvas.restore();
}

/// How a wheel turns over its own time (CSS "ease").
const Curve _spin = Cubic(0.25, 0.1, 0.25, 1);

/// One wheel at [pos] (digits, fractional while turning: digit n sits
/// (n − pos) lines below the slot), blurred vertically by [sigma]. It is
/// clipped to its line only (with room at the sides), so tightly tracked
/// glyphs keep their full ink.
void _paintWheel(
  Canvas canvas,
  _Wheel w,
  List<TextPainter> set,
  double pos,
  double sigma,
) {
  final box = w.box;
  final line = box.height;
  final column = Rect.fromLTRB(
    box.left - line * 0.2,
    box.top,
    box.right + line * 0.2,
    box.bottom,
  );
  canvas.save();
  canvas.clipRect(column);
  final blur = sigma >= 0.8;
  if (blur) {
    canvas.saveLayer(
      column,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: 0.01,
          sigmaY: sigma,
          tileMode: TileMode.decal,
        ),
    );
  }
  final base = pos.floor();
  for (var i = -1; i <= 2; i++) {
    final n = base + i;
    final dy = (n - pos) * line;
    if (dy.abs() >= line + sigma * 2) continue;
    final p = set[((n % 10) + 10) % 10];
    p.paint(
      canvas,
      Offset(box.left + (box.width - p.width) / 2, w.glyphTop + dy),
    );
  }
  if (blur) canvas.restore();
  canvas.restore();
}
