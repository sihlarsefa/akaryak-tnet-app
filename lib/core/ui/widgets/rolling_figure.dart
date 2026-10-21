import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';

/// The plate figure as a mechanical pump register (design v2 §8.1, "sayaç
/// dönüşü"): on the first home render of a session the figure rolls into
/// place in [AknMotion.plateRoll] (900 ms) on `v(t) = target × (1 − (1 −
/// t)^3.2)`.
///
/// * Every digit is a wheel in a **fixed slot** — the slot of its final
///   digit, measured from the settled text — so the figure never jitters
///   and the last frame equals plain text.
/// * **Carry model**: the units wheel turns continuously (`v mod 10`); wheel
///   k sits at `floor(v / 10^k) mod 10` and only turns during its carry, so
///   the higher wheels are always readable and correct
///   ([RollingFigure.wheelPosition]).
/// * Leading zeros and their separators stay blank until their wheel first
///   shows a digit; the units wheel of the integer part and the decimals are
///   always shown ("0,87").
/// * A wheel faster than 30 steps/s draws two ghost copies (±0.16 em at
///   30 %, ±0.32 em at 12 %) — no blur filter; a 12 % fade in the plate
///   colour shades the drum edges (no ShaderMask, no saveLayer).
/// * One `CustomPainter`, 10 cached `TextPainter`s per style (plus the two
///   ghost alphas), clipped to the figure's line box.
///
/// [value] is the formatted figure ("1.524.380", "42,34", "%72"); [decimals]
/// (",00") and [unit] ("₺", "L", "₺/L") or [unitSpan] are drawn after it on
/// the same baseline, statically, so nothing can wrap between the number and
/// its unit. Without [animate] (and always under reduce motion) the final
/// frame is drawn at once. The roll plays once per State: later value
/// changes jump (pull-to-refresh, deck swipes and tab switches never replay
/// it — the caller passes `animate: false` once `plateRollSeenProvider` is
/// set). Screen readers hear the final value once.
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

  /// Roll on first show (ignored under reduce motion).
  final bool animate;

  /// Wait before rolling (e.g. [AknMotion.plateLight] while the plate
  /// lights).
  final Duration delay;
  final Duration duration;

  /// Called (after the frame) when the roll starts — or, under reduce
  /// motion, when the final frame is shown instead: the moment is consumed
  /// either way (set `plateRollSeenProvider` here).
  final VoidCallback? onRollStart;
  final VoidCallback? onRollEnd;

  /// Drum shading colour; defaults to the ambient surface (the plate on the
  /// plate palette).
  final Color? fadeColor;

  /// Screen-reader text; defaults to the value, decimals and unit.
  final String? semanticLabel;

  /// Position of digit wheel [k] (0 = the rightmost digit) when the register
  /// shows [v] (0 ≤ position < 10, fractional while turning): the carry
  /// model of §8.1.
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = AknMotion.reduced(context);
    if (!_scheduled) {
      _scheduled = true;
      if (widget.animate) {
        final rolls = !reduced && RollingFigure.targetOf(widget.value) > 0;
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
    _c.forward(from: 0).whenComplete(() {
      if (mounted) widget.onRollEnd?.call();
    });
  }

  @override
  void didUpdateWidget(RollingFigure old) {
    super.didUpdateWidget(old);
    if (old.duration != widget.duration) _c.duration = widget.duration;
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
    final c = context.akn;
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
          fade: widget.fadeColor ?? c.surface,
          seconds: widget.duration.inMicroseconds / 1e6,
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

/// One digit wheel: its slot in the settled text and its place value.
class _Slot {
  const _Slot(this.box, this.k, {required this.leading});

  final Rect box;

  /// Place value: 0 = the rightmost digit.
  final int k;

  /// Integer digit left of the integer units digit (blank while zero).
  final bool leading;
}

/// A non-digit character of the figure (separator, "%", sign).
class _Static {
  const _Static(this.box, {this.leftWheel});

  final Rect box;

  /// For a group separator: the wheel on its left (hidden while blank).
  final _Slot? leftWheel;
}

/// The measured figure: settled text, slots, digit painters.
class _FigureLayout {
  _FigureLayout(this.key) {
    final ltr = TextDirection.ltr;
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

    // Slots: one per digit, in the settled text's own glyph boxes.
    final text = key.value;
    final digitIdx = <int>[
      for (var i = 0; i < text.length; i++)
        if (_isDigit(text.codeUnitAt(i))) i,
    ];
    final comma = text.lastIndexOf(',');
    final fractional = comma < 0 ? 0 : digitIdx.where((i) => i > comma).length;
    final slotAt = <int, _Slot>{};
    for (var n = 0; n < digitIdx.length; n++) {
      final i = digitIdx[n];
      final k = digitIdx.length - 1 - n;
      final s = _Slot(_box(i), k, leading: k > fractional);
      slotAt[i] = s;
      slots.add(s);
    }
    for (var i = 0; i < text.length; i++) {
      if (slotAt.containsKey(i)) continue;
      final ch = text[i];
      _Slot? left;
      if (ch == '.' || ch == ',') {
        for (var j = i - 1; j >= 0; j--) {
          if (slotAt[j] != null) {
            left = slotAt[j];
            break;
          }
        }
      }
      statics.add(_Static(_box(i), leftWheel: left));
    }
    target = RollingFigure.targetOf(text).toDouble();
    em = key.scaler.scale(key.style.fontSize ?? 58);
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
  final List<_Slot> slots = [];
  final List<_Static> statics = [];
  late final double target;
  late final double em;

  /// Digit painters 0–9 at full ink, 30 % and 12 % (ghosts), built lazily.
  final Map<int, List<TextPainter>> _digits = {};

  static bool _isDigit(int u) => u >= 0x30 && u <= 0x39;

  Rect _box(int i) {
    final boxes = figure.getBoxesForSelection(
      TextSelection(baseOffset: i, extentOffset: i + 1),
    );
    if (boxes.isEmpty) return Rect.zero;
    final b = boxes.first.toRect();
    return Rect.fromLTRB(b.left, 0, b.right, figure.height);
  }

  List<TextPainter> _digitSet(int alphaPct) =>
      _digits.putIfAbsent(alphaPct, () {
        final color = key.style.color ?? Colors.black;
        final style = key.style.copyWith(
          color: color.withValues(alpha: color.a * alphaPct / 100),
        );
        return [
          for (var d = 0; d < 10; d++)
            TextPainter(
              text: TextSpan(text: '$d', style: style),
              textDirection: TextDirection.ltr,
              textScaler: key.scaler,
              maxLines: 1,
            )..layout(),
        ];
      });

  void dispose() {
    figure.dispose();
    decimals?.dispose();
    unit?.dispose();
    for (final set in _digits.values) {
      for (final p in set) {
        p.dispose();
      }
    }
  }

  void paint(Canvas canvas, double t, Color fade, double seconds) {
    if (decimals != null) decimals!.paint(canvas, Offset(decLeft, decTop));
    if (unit != null) unit!.paint(canvas, Offset(unitLeft, unitTop));
    if (t >= 1 || target <= 0 || slots.isEmpty) {
      figure.paint(canvas, Offset(0, figTop));
      return;
    }
    final v = target * AknMotion.rollProgress(t);
    // Units-wheel speed in steps per second (dv/dt of the roll curve).
    final speed =
        target * 3.2 * math.pow(1 - t, 2.2) / (seconds <= 0 ? 0.9 : seconds);
    final line = figure.height;
    final top = figTop;

    bool blank(_Slot s) =>
        s.leading &&
        v < math.pow(10, s.k) &&
        RollingFigure.wheelPosition(v, s.k) < 0.5;

    // Static glyphs (separators follow the wheel on their left).
    for (final s in statics) {
      final left = s.leftWheel;
      if (left != null && blank(left)) continue;
      canvas.save();
      canvas.clipRect(s.box.shift(Offset(0, top)));
      figure.paint(canvas, Offset(0, top));
      canvas.restore();
    }

    final ink = _digitSet(100);
    double? spanLeft;
    double? spanRight;
    for (final s in slots) {
      final pos = RollingFigure.wheelPosition(v, s.k);
      final whole = pos.floorToDouble();
      final frac = pos - whole;
      final d0 = whole.toInt() % 10;
      final d1 = (d0 + 1) % 10;
      final leadingZero = s.leading && v < math.pow(10, s.k);
      final rect = s.box.shift(Offset(0, top));
      spanLeft = math.min(spanLeft ?? rect.left, rect.left);
      spanRight = math.max(spanRight ?? rect.right, rect.right);
      canvas.save();
      canvas.clipRect(rect);
      void digit(List<TextPainter> set, int d, double dy) {
        final p = set[d];
        p.paint(
          canvas,
          Offset(rect.left + (rect.width - p.width) / 2, top + dy),
        );
      }

      void pair(List<TextPainter> set, double shift) {
        if (!leadingZero) digit(set, d0, -frac * line + shift);
        if (frac > 0) digit(set, d1, (1 - frac) * line + shift);
      }

      final wheelSpeed = speed / math.pow(10, s.k);
      if (wheelSpeed > 30) {
        // Faster than the eye can follow: the frame's sub-step position is
        // noise, so the wheel shows its nearest digit crisp, smeared by two
        // ghost copies of the same digit (±0.16 em at 30 %, ±0.32 em at
        // 12 %) — a pump register in motion, not a half-scrolled glyph.
        final shown = pos.round() % 10;
        if (!(leadingZero && shown == 0)) {
          final near = _digitSet(30);
          final far = _digitSet(12);
          digit(far, shown, -0.32 * em);
          digit(far, shown, 0.32 * em);
          digit(near, shown, -0.16 * em);
          digit(near, shown, 0.16 * em);
          digit(ink, shown, 0);
        }
      } else {
        pair(ink, 0);
      }
      canvas.restore();
    }

    // Drum shading: 12 % top and bottom fade in the surface colour.
    if (spanLeft != null && spanRight != null) {
      final band = line * 0.12;
      final clear = fade.withValues(alpha: 0);
      final topRect = Rect.fromLTRB(spanLeft, top, spanRight, top + band);
      final bottomRect = Rect.fromLTRB(
        spanLeft,
        top + line - band,
        spanRight,
        top + line,
      );
      canvas.drawRect(
        topRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [fade, clear],
          ).createShader(topRect),
      );
      canvas.drawRect(
        bottomRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [fade, clear],
          ).createShader(bottomRect),
      );
    }
  }
}

class _RollPainter extends CustomPainter {
  _RollPainter({
    required this.layout,
    required this.progress,
    required this.fade,
    required this.seconds,
  }) : super(repaint: progress);

  final _FigureLayout layout;
  final Animation<double> progress;
  final Color fade;
  final double seconds;

  @override
  void paint(Canvas canvas, Size size) =>
      layout.paint(canvas, progress.value, fade, seconds);

  @override
  bool shouldRepaint(_RollPainter old) =>
      old.layout != layout ||
      old.progress != progress ||
      old.fade != fade ||
      old.seconds != seconds;
}
