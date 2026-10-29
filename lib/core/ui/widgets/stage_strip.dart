import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import 'animated_number.dart';
import 'timeline.dart';

/// What went wrong at the current stop of a [StageStrip]: an 18 px danger
/// disc with a white "×" (rejected, cancelled) or "!" (disputed), and the
/// line ends there.
enum StageProblem { rejected, attention }

/// How a [StageStrip] reflows when it does not fit (width < 340 or text
/// scale ≥ 1.3).
enum StageStripFallback {
  /// A vertical [StepTimeline] (order detail).
  timeline,

  /// The nodes without labels plus one line "Adım 2 / 4: Teslimat" (wizard
  /// headers).
  compact,
}

/// The stage strip (design v3 §4–5) — v4: **wizard steps only**
/// (`StepperHeader`); an order's journey is the » Akış line
/// (`AknFlowLine`). Stops evenly spaced over the content width on a rounded
/// 4 px track, in the Akış line's bead colours (passed: surface bead with a
/// brand ring; the travelled track in brand).
///
/// * Done: a 14 px green disc (`ok.solid`) with a white check; the track is
///   filled green up to the current stop.
/// * Current: an 18 px ring with a centre dot on a white bead — orange with
///   a breathing halo when it is the viewer's move ([yourMove]), else ink
///   with a soft halo.
/// * Future: a 10 px white bead with a `lineStrong` ring.
/// * [problem]: a danger disc with a white × or ! at the current stop; the
///   fill ends there.
/// * Labels 12/16: done ink 600, current 800 (Pas when it is the viewer's
///   move), future dim 500.
/// * Motion: when it first appears the fill runs from the first stop to the
///   current one, the ring travelling along and every passed stop popping
///   its check; when [current] changes the ring slides on (instant under
///   reduce motion). The halo breathes (ambient: off in tests and under
///   reduce motion).
/// * Width < 340 or text scale ≥ 1.3: [fallback].
/// * With [onStageTap], done stops are 48 dp buttons ("Ürün adımına dön").
class StageStrip extends StatelessWidget {
  const StageStrip({
    super.key,
    required this.stages,
    required this.current,
    this.yourMove = false,
    this.problem,
    this.onStageTap,
    this.fallback = StageStripFallback.timeline,
    this.semanticPrefix = 'Aşama',
    this.announceYourMove = true,
  });

  /// The order's stops, e.g. Talep, Onay, Teklif, Karar, Plan, Yolda, Teslim
  /// (company approval "Onay" only when the customer uses it).
  final List<String> stages;

  /// Index of the current stop (0-based); every stop before it is done. A
  /// value of `stages.length` marks every stop done.
  final int current;

  /// The current stop is the viewer's move: orange ring and halo.
  final bool yourMove;
  final StageProblem? problem;

  /// Done stops become buttons that call this with their index.
  final ValueChanged<int>? onStageTap;
  final StageStripFallback fallback;

  /// "Aşama 4 / 7: Karar" (the wizard uses "Adım").
  final String semanticPrefix;

  /// Adds ", sıra sizde" to the announcement when [yourMove].
  final bool announceYourMove;

  /// Horizontal inset of the first and last stop centre.
  static const double _pad = 18;

  /// Height of the node row.
  static const double _dotRow = 20;

  String get _summary {
    final n = stages.length;
    if (n == 0) return '';
    final i = current.clamp(0, n - 1);
    final done = current >= n;
    final problemWord = switch (problem) {
      StageProblem.rejected => ', durdu',
      StageProblem.attention => ', dikkat gerekiyor',
      null => '',
    };
    final move = yourMove && announceYourMove && !done ? ', sıra sizde' : '';
    if (done) return '$semanticPrefix $n / $n: ${stages.last}, tamamlandı';
    return '$semanticPrefix ${i + 1} / $n: ${stages[i]}$problemWord$move';
  }

  @override
  Widget build(BuildContext context) {
    final n = stages.length;
    if (n == 0) return const SizedBox.shrink();
    final scaler = MediaQuery.textScalerOf(context);
    final large = scaler.scale(10) >= 13;
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth.isFinite && box.maxWidth < 340;
        if ((large || narrow) && fallback == StageStripFallback.timeline) {
          return _timeline();
        }
        return _strip(context, box.maxWidth, labels: !(large || narrow));
      },
    );
  }

  Widget _timeline() {
    final n = stages.length;
    return StepTimeline(
      dense: true,
      yourMove: yourMove,
      steps: [
        for (var i = 0; i < n; i++)
          TimelineStep(
            title: stages[i],
            state: i < current
                ? TimelineState.done
                : i == current
                ? switch (problem) {
                    StageProblem.rejected => TimelineState.failed,
                    StageProblem.attention => TimelineState.warning,
                    null => TimelineState.current,
                  }
                : TimelineState.upcoming,
          ),
      ],
    );
  }

  Widget _strip(BuildContext context, double width, {required bool labels}) {
    final c = context.akn;
    final t = context.aknText;
    final n = stages.length;
    final w = width.isFinite ? width : 350.0;
    final span = n <= 1 ? 0.0 : (w - _pad * 2) / (n - 1);
    double xOf(int i) => n <= 1 ? w / 2 : _pad + span * i;
    final labelStyle = t.caption.copyWith(height: 16 / 12, letterSpacing: 0);
    final labelHeight = MediaQuery.textScalerOf(context).scale(16);
    final content = _dotRow + (labels ? 8 + labelHeight : 0);
    final tappable = onStageTap != null;
    final height = tappable ? math.max(content, AknSpace.minTap) : content;
    final top = (height - content) / 2;
    final labelWidth = math.max(span, 52.0);
    final summaryLine = !labels && fallback == StageStripFallback.compact;
    final textDuration = AknMotion.of(context, AknMotion.base);

    final strip = SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: top,
            height: _dotRow,
            child: ExcludeSemantics(
              child: _StageTrack(
                count: n,
                current: current,
                pad: _pad,
                yourMove: yourMove,
                problem: problem,
              ),
            ),
          ),
          if (labels)
            for (var i = 0; i < n; i++)
              Positioned(
                left: xOf(i) - labelWidth / 2,
                width: labelWidth,
                top: top + _dotRow + 8,
                child: ExcludeSemantics(
                  child: AnimatedDefaultTextStyle(
                    duration: textDuration,
                    style: labelStyle.copyWith(
                      color: i == current && yourMove && problem == null
                          ? c.brandInk
                          : i <= current
                          ? c.ink
                          : c.dim,
                      fontWeight: i < current
                          ? FontWeight.w600
                          : i == current
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                    child: Text(
                      stages[i],
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          if (tappable)
            for (var i = 0; i < math.min(current, n); i++)
              Positioned(
                left: xOf(i) - AknSpace.minTap / 2,
                width: AknSpace.minTap,
                top: 0,
                height: height,
                child: Semantics(
                  button: true,
                  label: '${stages[i]} adımına dön',
                  onTap: () => onStageTap!(i),
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      AknHaptics.selection();
                      onStageTap!(i);
                    },
                  ),
                ),
              ),
        ],
      ),
    );

    final Widget body = summaryLine
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              strip,
              const SizedBox(height: 6),
              ExcludeSemantics(
                child: Text(
                  current >= n
                      ? stages.last
                      : '$semanticPrefix ${current + 1} / $n: ${stages[current]}',
                  style: t.label.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          )
        : strip;
    return Semantics(container: true, label: _summary, child: body);
  }
}

/// The animated node row of a [StageStrip]: the fill runs to [current] on
/// first appearance and slides on when it changes; the "your move" halo
/// breathes.
class _StageTrack extends StatefulWidget {
  const _StageTrack({
    required this.count,
    required this.current,
    required this.pad,
    required this.yourMove,
    required this.problem,
  });

  final int count;
  final int current;
  final double pad;
  final bool yourMove;
  final StageProblem? problem;

  @override
  State<_StageTrack> createState() => _StageTrackState();
}

class _StageTrackState extends State<_StageTrack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    value: 1,
  );
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _c,
    curve: AknMotion.emphasizedCurve,
  );
  double _from = 0;
  late double _to = widget.current.toDouble();
  bool _started = false;

  double get _position => _from + (_to - _from) * _t.value;

  Object get _handoffKey => (
    'StageStrip',
    widget.count,
    widget.current,
    widget.yourMove,
    widget.problem,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _go(from: 0, to: widget.current.toDouble(), first: true);
    // A wrapper that remounted the strip mid-sweep hands over its progress.
    final handed = AknEntranceHandoff.take(_handoffKey);
    if (handed != null && _c.isAnimating) {
      _c.value = handed;
      if (handed < 1) _c.forward();
    }
  }

  @override
  void deactivate() {
    AknEntranceHandoff.put(_handoffKey, _c.value);
    super.deactivate();
  }

  @override
  void didUpdateWidget(_StageTrack old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) {
      _go(from: _position, to: widget.current.toDouble(), first: false);
    }
  }

  void _go({required double from, required double to, required bool first}) {
    _from = from;
    _to = to;
    final steps = (to - from).abs();
    final ms = first
        ? 420 + 150 * steps
        : AknMotion.stageStep.inMilliseconds * math.max(1.0, steps);
    final d = AknMotion.of(
      context,
      Duration(milliseconds: ms.round().clamp(0, 1600)),
    );
    if (d == Duration.zero || from == to) {
      _c.value = 1;
      return;
    }
    _c.duration = d;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    Widget paint(double pulse) => AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final position = _position;
        return CustomPaint(
          size: Size.infinite,
          painter: StageStripPainter(
            count: widget.count,
            position: position,
            pad: widget.pad,
            yourMove: widget.yourMove,
            // The travelling ring turns into the problem disc on arrival.
            problem: (_to - position).abs() < 0.3 ? widget.problem : null,
            colors: c,
            pulse: pulse,
          ),
        );
      },
    );
    final live = widget.problem == null && widget.current < widget.count;
    return RepaintBoundary(
      child: live
          ? AknAmbient(
              period: AknMotion.breathe,
              reverse: true,
              role: AknAmbientRole.focus,
              builder: (context, p, _) => paint(p),
            )
          : paint(0),
    );
  }
}

/// Paints the track, the fill and the nodes of a [StageStrip]; [position]
/// is the (animated) index of the current stop, [pulse] (0–1) the breath of
/// the current ring's halo.
class StageStripPainter extends CustomPainter {
  StageStripPainter({
    required this.count,
    required this.position,
    required this.pad,
    required this.yourMove,
    required this.problem,
    required this.colors,
    this.pulse = 0,
  });

  final int count;
  final double position;
  final double pad;
  final bool yourMove;
  final StageProblem? problem;
  final AknColors colors;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    if (count == 0) return;
    final c = colors;
    final y = size.height / 2;
    final span = count <= 1 ? 0.0 : (size.width - pad * 2) / (count - 1);
    double xOf(double i) => count <= 1 ? size.width / 2 : pad + span * i;
    final last = (count - 1).toDouble();
    final pos = position.clamp(0.0, last);
    final xCur = xOf(pos);
    final x0 = xOf(0);
    final xN = xOf(last);
    // Past the last stop the ring hands over to the last check.
    final ringFade = position > last
        ? (1 - (position - last) / 0.5).clamp(0.0, 1.0)
        : 1.0;

    // Track and fill.
    final round = StrokeCap.round;
    canvas.drawLine(
      Offset(x0, y),
      Offset(xN, y),
      Paint()
        ..color = c.line
        ..strokeWidth = 4
        ..strokeCap = round,
    );
    if (xCur > x0) {
      // v4: the travelled part is the brand line (green only means
      // "delivered", on the Akış line).
      canvas.drawLine(
        Offset(x0, y),
        Offset(xCur, y),
        Paint()
          ..color = c.brandFill
          ..strokeWidth = 4
          ..strokeCap = round,
      );
    }

    // Stops.
    for (var i = 0; i < count; i++) {
      final center = Offset(xOf(i.toDouble()), y);
      final done = ((position - i - 0.5) / 0.5).clamp(0.0, 1.0);
      final atRing = (i - pos).abs() <= 0.5 && ringFade > 0;
      if (done > 0) {
        // A passed stop: the Akış line's bead — surface with a 2 px brand
        // ring and a small brand check — popping 0.6 → 1.
        final s = 0.6 + 0.4 * Curves.easeOutBack.transform(done);
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.scale(s);
        canvas.translate(-center.dx, -center.dy);
        canvas.drawCircle(center, 7, Paint()..color = c.surface);
        canvas.drawCircle(
          center,
          6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = c.brandFill,
        );
        _stageCheck(canvas, center, 6, c.brandFill);
        canvas.restore();
      } else if (!atRing) {
        canvas.drawCircle(center, 5, Paint()..color = c.surface);
        canvas.drawCircle(
          center,
          4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = c.lineStrong,
        );
      }
    }
    if (ringFade <= 0) return;

    final center = Offset(xCur, y);
    if (problem != null) {
      final tone = c.danger;
      canvas.drawCircle(center, 13, Paint()..color = tone.bg);
      canvas.drawCircle(center, 9, Paint()..color = tone.solid);
      final mark = Paint()
        ..color = tone.onSolid
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      if (problem == StageProblem.rejected) {
        canvas.drawLine(
          center + const Offset(-3.2, -3.2),
          center + const Offset(3.2, 3.2),
          mark,
        );
        canvas.drawLine(
          center + const Offset(3.2, -3.2),
          center + const Offset(-3.2, 3.2),
          mark,
        );
      } else {
        canvas.drawLine(
          center + const Offset(0, -4.5),
          center + const Offset(0, 1),
          mark,
        );
        canvas.drawCircle(
          center + const Offset(0, 4.2),
          1.25,
          Paint()..color = tone.onSolid,
        );
      }
      return;
    }
    final ringColor = yourMove ? c.logo : c.ink;
    final p = pulse.clamp(0.0, 1.0);
    canvas.drawCircle(
      center,
      13 + 4 * p,
      Paint()
        ..color = ringColor.withValues(
          alpha: (yourMove ? 0.2 : 0.09) * (1 - 0.55 * p) * ringFade,
        ),
    );
    canvas.drawCircle(
      center,
      9,
      Paint()..color = c.surface.withValues(alpha: ringFade),
    );
    canvas.drawCircle(
      center,
      7.75,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = ringColor.withValues(alpha: ringFade),
    );
    canvas.drawCircle(
      center,
      3.5,
      Paint()..color = ringColor.withValues(alpha: ringFade),
    );
  }

  @override
  bool shouldRepaint(StageStripPainter old) =>
      old.count != count ||
      old.position != position ||
      old.pad != pad ||
      old.yourMove != yourMove ||
      old.problem != problem ||
      old.colors != colors ||
      old.pulse != pulse;
}

/// A small check inside a disc of radius [r].
void _stageCheck(Canvas canvas, Offset center, double r, Color color) {
  final s = r * 0.5;
  final path = Path()
    ..moveTo(center.dx - s * 0.95, center.dy + s * 0.05)
    ..lineTo(center.dx - s * 0.25, center.dy + s * 0.72)
    ..lineTo(center.dx + s, center.dy - s * 0.62);
  canvas.drawPath(
    path,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );
}
