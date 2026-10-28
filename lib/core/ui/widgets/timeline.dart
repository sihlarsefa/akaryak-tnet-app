import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';
import 'animated_number.dart';
import 'stage_strip.dart';

enum TimelineState { done, current, upcoming, failed, warning }

/// One step of a [StepTimeline].
@immutable
class TimelineStep {
  const TimelineStep({
    required this.title,
    this.subtitle,
    this.time,
    this.state = TimelineState.upcoming,
    this.icon,
    this.content,
    this.yourMove,
  });

  final String title;

  /// Meta line (14/20 dim): who, what ("Elif Demir onayladı").
  final String? subtitle;

  /// Right-aligned time ("10:05", "21.10 14:20").
  final String? time;
  final TimelineState state;

  /// Deprecated: the nodes carry no icons; ignored.
  final IconData? icon;

  /// Extra content under the texts (e.g. plate badge, note).
  final Widget? content;

  /// Overrides [StepTimeline.yourMove] for this step.
  final bool? yourMove;
}

/// Vertical timeline (design v3 §4–5): "Sipariş akışı" (chronological) and
/// "Hareketler" (newest first — the caller orders the steps).
///
/// Nodes: done = an 18 px green disc (`ok.solid`) with a white check;
/// current = an 18 px ring with a centre dot — orange with a breathing halo
/// when it is the viewer's move ([yourMove]), else ink with a soft one;
/// future = a 12 px hollow ring (`lineStrong`); failed = a danger disc with
/// ×, warning = a warn disc with !. Connector: a 2.5 px green line below
/// done steps, dashed `lineStrong` toward the future.
///
/// Motion: when it first appears the rail draws itself top to bottom — each
/// node pops in (the checks draw), the line grows to the next one and the
/// texts fade in beside it; the current node's halo then breathes (ambient:
/// off in tests and under reduce motion, where everything shows at once).
///
/// Title 15/22 600 (current 700, future dim 500), meta 14/20 dim, time
/// 14/22 500 dim tabular on the right (under the title at ≥ 1.3× text).
class StepTimeline extends StatefulWidget {
  const StepTimeline({
    super.key,
    required this.steps,
    this.dense = false,
    this.yourMove = false,
  });

  final List<TimelineStep> steps;
  final bool dense;

  /// The current step is the viewer's move (orange ring).
  final bool yourMove;

  @override
  State<StepTimeline> createState() => _StepTimelineState();
}

class _StepTimelineState extends State<StepTimeline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    value: 1,
  );
  bool _started = false;

  Object get _handoffKey => (
    'StepTimeline',
    Object.hashAll([for (final s in widget.steps) (s.title, s.state)]),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final n = widget.steps.length;
    if (n == 0 || AknMotion.reduced(context)) return;
    _reveal.duration = Duration(milliseconds: math.min(1200, 360 + 150 * n));
    // A wrapper that remounted the timeline mid-reveal hands over its
    // progress, so the rail never draws itself twice.
    final handed = AknEntranceHandoff.take(_handoffKey) ?? 0;
    if (handed < 1) _reveal.forward(from: handed);
  }

  @override
  void deactivate() {
    AknEntranceHandoff.put(_handoffKey, _reveal.value);
    super.deactivate();
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(
            step: steps[i],
            last: i == steps.length - 1,
            dense: widget.dense,
            index: i,
            count: steps.length,
            yourMove: steps[i].yourMove ?? widget.yourMove,
            reveal: _reveal,
          ),
      ],
    );
  }
}

/// The cascade of a timeline reveal: node `i` pops over [pop] node-units
/// starting at `i × lag`; the connector below it grows over [lag] units
/// starting a little after.
abstract final class _Cascade {
  static const double lag = 0.55;
  static const double pop = 0.6;

  static double span(int n) => lag * math.max(0, n - 1) + pop;

  /// Pop progress (0–1) of node [i] at reveal time [t] (0–1).
  static double node(double t, int i, int n) =>
      ((t * span(n) - lag * i) / pop).clamp(0.0, 1.0);

  /// Growth (0–1) of the connector below node [i].
  static double line(double t, int i, int n) =>
      ((t * span(n) - lag * i - 0.15) / lag).clamp(0.0, 1.0);
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.step,
    required this.last,
    required this.dense,
    required this.index,
    required this.count,
    required this.yourMove,
    required this.reveal,
  });

  final TimelineStep step;
  final bool last;
  final bool dense;
  final int index;
  final int count;
  final bool yourMove;
  final Animation<double> reveal;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final stateWord = switch (step.state) {
      TimelineState.done => 'tamamlandı',
      TimelineState.current => 'şu anki adım',
      TimelineState.upcoming => 'bekliyor',
      TimelineState.failed => 'başarısız',
      TimelineState.warning => 'dikkat',
    };
    final upcoming = step.state == TimelineState.upcoming;
    final current = step.state == TimelineState.current;
    // Büyük yazıda (≥ 1,3×) saat başlığın sağında değil altında durur: dar ekranda taşmaz.
    final scaler = MediaQuery.textScalerOf(context);
    final stackTime = scaler.scale(10) >= 13;
    final titleStyle = t.bodyStrong.copyWith(
      color: upcoming ? c.dim : c.ink,
      fontWeight: upcoming
          ? FontWeight.w500
          : current
          ? FontWeight.w700
          : FontWeight.w600,
    );
    final timeStyle = t.bodySmall.copyWith(
      height: 22 / 14,
      fontWeight: FontWeight.w500,
      color: c.dim,
      fontFeatures: AknNumerals.tabular,
    );
    // The node sits on the title's first line (22 px, scaled with the text).
    final lineHeight = scaler.scale(22);
    Widget rail(double pulse) => CustomPaint(
      painter: _TimelineRailPainter(
        state: step.state,
        last: last,
        yourMove: yourMove,
        lineHeight: lineHeight,
        colors: c,
        reveal: reveal,
        index: index,
        count: count,
        pulse: pulse,
      ),
    );
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(step.title, style: titleStyle)),
            if (step.time != null && !stackTime) ...[
              const SizedBox(width: 12),
              Text(step.time!, style: timeStyle),
            ],
          ],
        ),
        if (step.time != null && stackTime) Text(step.time!, style: timeStyle),
        if (step.subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(step.subtitle!, style: t.bodySmall),
          ),
        if (step.content != null) ...[
          const SizedBox(height: 10),
          step.content!,
        ],
      ],
    );
    return Semantics(
      label:
          'Adım ${index + 1} / $count: ${step.title}, $stateWord'
          '${step.time == null ? '' : ', ${step.time}'}'
          '${step.subtitle == null ? '' : '. ${step.subtitle}'}',
      excludeSemantics: step.content == null,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 24,
              child: current
                  ? RepaintBoundary(
                      child: AknAmbient(
                        period: AknMotion.breathe,
                        reverse: true,
                        builder: (context, p, _) => rail(p),
                      ),
                    )
                  : rail(0),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : (dense ? 12 : 18)),
                child: AnimatedBuilder(
                  animation: reveal,
                  child: texts,
                  builder: (context, child) {
                    final a = Curves.easeOut.transform(
                      _Cascade.node(reveal.value, index, count),
                    );
                    return Opacity(
                      opacity: a,
                      child: Transform.translate(
                        offset: Offset(8 * (1 - a), 0),
                        child: child,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The node of one timeline row and the connector down to the next row;
/// repaints with the [reveal] (no relayout).
class _TimelineRailPainter extends CustomPainter {
  _TimelineRailPainter({
    required this.state,
    required this.last,
    required this.yourMove,
    required this.lineHeight,
    required this.colors,
    required this.reveal,
    required this.index,
    required this.count,
    this.pulse = 0,
  }) : super(repaint: reveal);

  final TimelineState state;
  final bool last;
  final bool yourMove;
  final double lineHeight;
  final AknColors colors;
  final Animation<double> reveal;
  final int index;
  final int count;

  /// The current node's breath (0–1).
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;
    final x = size.width / 2;
    final cy = lineHeight / 2;
    final t = reveal.value;
    final appear = _Cascade.node(t, index, count);
    final grow = _Cascade.line(t, index, count);
    final r = state == TimelineState.upcoming ? 6.0 : 9.0;

    if (!last && grow > 0) {
      final from = cy + r + 3;
      // Into the next row, stopping 3 px above its node.
      final to = size.height + cy - 12;
      final end = from + (to - from) * Curves.easeInOutCubic.transform(grow);
      if (state == TimelineState.done) {
        canvas.drawLine(
          Offset(x, from),
          Offset(x, end),
          Paint()
            ..color = c.ok.solid
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round,
        );
      } else {
        final dash = Paint()
          ..color = c.lineStrong.withValues(alpha: 0.7)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        for (var y = from; y < end; y += 7) {
          canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 3, end)), dash);
        }
      }
    }

    if (appear <= 0) return;
    final center = Offset(x, cy);
    final scale = Curves.easeOutBack.transform(appear);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);
    switch (state) {
      case TimelineState.done:
        canvas.drawCircle(center, r, Paint()..color = c.ok.solid);
        final draw = ((appear - 0.35) / 0.65).clamp(0.0, 1.0);
        if (draw > 0) {
          _check(canvas, center, r, c.ok.onSolid, draw);
        }
      case TimelineState.upcoming:
        canvas.drawCircle(
          center,
          r - 1,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = c.lineStrong,
        );
      case TimelineState.current:
        final ring = yourMove ? c.logo : c.ink;
        final p = pulse.clamp(0.0, 1.0);
        canvas.drawCircle(
          center,
          r + 4 + 4 * p,
          Paint()
            ..color = ring.withValues(
              alpha: (yourMove ? 0.2 : 0.09) * (1 - 0.55 * p),
            ),
        );
        canvas.drawCircle(
          center,
          r - 1.25,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = ring,
        );
        canvas.drawCircle(center, 3.5, Paint()..color = ring);
      case TimelineState.failed || TimelineState.warning:
        final tone = state == TimelineState.failed ? c.danger : c.warn;
        canvas.drawCircle(center, r, Paint()..color = tone.solid);
        final mark = Paint()
          ..color = tone.onSolid
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        if (state == TimelineState.failed) {
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
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TimelineRailPainter old) =>
      old.state != state ||
      old.last != last ||
      old.yourMove != yourMove ||
      old.lineHeight != lineHeight ||
      old.colors != colors ||
      old.reveal != reveal ||
      old.index != index ||
      old.count != count ||
      old.pulse != pulse;
}

/// Draws a check inside a disc of radius [r] at [center], trimmed to
/// [progress] (0–1) of its length.
void _check(Canvas canvas, Offset center, double r, Color color, double p) {
  final s = r * 0.5;
  final a = center + Offset(-s * 0.95, s * 0.05);
  final b = center + Offset(-s * 0.25, s * 0.72);
  final d = center + Offset(s, -s * 0.62);
  final l1 = (b - a).distance;
  final l2 = (d - b).distance;
  final drawn = (l1 + l2) * p;
  final path = Path()..moveTo(a.dx, a.dy);
  if (drawn <= l1) {
    final q = a + (b - a) * (drawn / l1);
    path.lineTo(q.dx, q.dy);
  } else {
    path.lineTo(b.dx, b.dy);
    final q = b + (d - b) * ((drawn - l1) / l2);
    path.lineTo(q.dx, q.dy);
  }
  canvas.drawPath(
    path,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, r * 0.22)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );
}

/// Wizard progress header (design v3 §4): the [StageStrip] with the step
/// labels — the line fills to the current step, done steps pop their
/// checks, the current step's orange ring breathes (in a wizard it is
/// always the viewer's move). Completed steps can be tapped to go back when
/// [onStepTap] is set (48 dp targets, "Ürün adımına dön"). At ≥ 1.3× text
/// or on a narrow screen it shows the nodes and one line "Adım 2 / 4:
/// Teslimat".
class StepperHeader extends StatelessWidget {
  const StepperHeader({
    super.key,
    required this.steps,
    required this.current,
    this.onStepTap,
    this.padding = const EdgeInsets.fromLTRB(
      AknSpace.page,
      8,
      AknSpace.page,
      12,
    ),
  });

  final List<String> steps;

  /// 0-based.
  final int current;
  final ValueChanged<int>? onStepTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: StageStrip(
        stages: steps,
        current: current.clamp(0, steps.length - 1),
        yourMove: true,
        onStageTap: onStepTap,
        fallback: StageStripFallback.compact,
        semanticPrefix: 'Adım',
        announceYourMove: false,
      ),
    );
  }
}
