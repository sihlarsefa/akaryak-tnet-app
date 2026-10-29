import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../painters/truck_route.dart' show paintFlowMark;
import '../status.dart';
import '../theme.dart';
import '../tokens.dart';
import 'animated_number.dart' show AknEntranceHandoff;
import 'timeline.dart';

/// Where an order stands on the » Akış line (design v4 §3b): the stops in
/// the web's words, the current stop and how the journey ends.
///
/// * Customer stops (the web's OrderTrackingBuilder): Sipariş · Teklif ·
///   Onay · Yolda · Teslim ([customerStops]).
/// * Bayi stops (the web's _OrderFlowSteps; the app says "Teslim" for both
///   roles): Teklif · Müşteri onayı · Sevkiyat · Teslim ([bayiStops]).
///
/// Build it from a viewer-aware lamp:
///
/// ```dart
/// final lamp = AknStatus.lampFor(order.status, viewer);
/// AknFlowLine(flow: AknFlow.customer(lamp))
/// ```
@immutable
class AknFlow {
  const AknFlow({
    required this.stops,
    required this.current,
    this.yourMove = false,
    this.delivered = false,
    this.problem = false,
    this.moving = false,
  });

  /// The customer's stops (web: OrderTrackingBuilder).
  static const List<String> customerStops = [
    'Sipariş',
    'Teklif',
    'Onay',
    'Yolda',
    'Teslim',
  ];

  /// The bayi's stops (web: _OrderFlowSteps, "Teslim" for the last).
  static const List<String> bayiStops = [
    'Teklif',
    'Müşteri onayı',
    'Sevkiyat',
    'Teslim',
  ];

  /// The customer's line for a viewer-aware [lamp] (no stage: the first
  /// stop).
  factory AknFlow.customer(StatusLamp lamp) => AknFlow.customerAt(
    lamp.stage ?? AknStage.talep,
    yourMove: lamp.yourMove,
    delivered: lamp.complete,
    problem: lamp.problem,
  );

  /// The bayi's line for a viewer-aware [lamp].
  factory AknFlow.bayi(StatusLamp lamp) => AknFlow.bayiAt(
    lamp.stage ?? AknStage.teklif,
    yourMove: lamp.yourMove,
    delivered: lamp.complete,
    problem: lamp.problem,
  );

  /// The customer's line at [stage] ([AknStage.customerStop]).
  factory AknFlow.customerAt(
    AknStage stage, {
    bool yourMove = false,
    bool delivered = false,
    bool problem = false,
  }) => AknFlow(
    stops: customerStops,
    current: stage.customerStop,
    yourMove: yourMove && !delivered && !problem,
    delivered: delivered,
    problem: problem && !delivered,
    moving: stage == AknStage.yolda && !delivered && !problem,
  );

  /// The bayi's line at [stage] ([AknStage.bayiStop]).
  factory AknFlow.bayiAt(
    AknStage stage, {
    bool yourMove = false,
    bool delivered = false,
    bool problem = false,
  }) => AknFlow(
    stops: bayiStops,
    current: stage.bayiStop,
    yourMove: yourMove && !delivered && !problem,
    delivered: delivered,
    problem: problem && !delivered,
    moving: stage == AknStage.yolda && !delivered && !problem,
  );

  /// The labels, first to last.
  final List<String> stops;

  /// Index of the stop where the order is (the »).
  final int current;

  /// The current stop is the viewer's move: Pas label, one ping ring.
  final bool yourMove;

  /// Delivered: the line is travelled and ends on the ok check disc (the
  /// only green on the line).
  final bool delivered;

  /// Rejected, expired, disputed: a danger disc where the line ends.
  final bool problem;

  /// In transit: the vehicle ping runs on the ».
  final bool moving;

  int get _last => stops.length - 1;

  /// [current] within the stops.
  int get index => current.clamp(0, math.max(0, _last));

  /// The current stop's label.
  String get currentLabel => stops.isEmpty ? '' : stops[index];

  /// Screen-reader summary, never "Aşama x / y": "Sipariş akışı: Onay
  /// adımında, sıra sizde. Sırada Yolda, Teslim."
  String get spoken {
    if (stops.isEmpty) return '';
    if (delivered) return 'Sipariş akışı: ${stops.last} tamamlandı.';
    final now = currentLabel;
    final tail = stops.sublist(index + 1);
    final move = yourMove ? ', sıra sizde' : '';
    final stopped = problem ? ', durdu' : '';
    final next = tail.isEmpty || problem ? '' : ' Sırada ${tail.join(', ')}.';
    return 'Sipariş akışı: $now adımında$stopped$move.$next';
  }

  @override
  bool operator ==(Object other) =>
      other is AknFlow &&
      _sameStops(other.stops, stops) &&
      other.current == current &&
      other.yourMove == yourMove &&
      other.delivered == delivered &&
      other.problem == problem &&
      other.moving == moving;

  static bool _sameStops(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(stops),
    current,
    yourMove,
    delivered,
    problem,
    moving,
  );
}

/// The » Akış line (design v4 §3b), the signature of the app: where an order
/// is, on every screen and for both roles.
///
/// * The mark: the logo's » in a 20 × 20 r6 tile (logo orange, white », a
///   warm glow) riding a 3 dp line; nothing else carries the ».
/// * The line: the travelled part in the brand gradient; passed stops are
///   8 dp surface beads with a 2 dp brand ring; the rest is dotted
///   `lineStrong` (2 dp dots every 6 dp) with hollow beads; delivered ends
///   on an `ok.solid` check disc (the only green); a problem on a
///   `danger.solid` disc where the line ends.
/// * Labels 12/16, at most 2 lines: passed ink 600; the current stop 800
///   (Pas on the viewer's move, else ink); future dim 500. Labels show at
///   every width ≥ 280 dp; at text scale ≥ 1.3 the line becomes a vertical
///   [StepTimeline]. Never "Aşama x / y".
/// * Motion (§6 Add 3): the first draw takes 600 ms (emphasized) — the
///   track fills, the » glides in and lands with a ~4 % overshoot, passed
///   beads pop 0.6 → 1 as it passes; a live change hops the » to the new
///   stop (420 ms spring) with a selection haptic while the labels
///   cross-fade; on the viewer's move one ping ring runs (1.8 s, the page's
///   focus loop); in transit the vehicle ping runs. Static under reduce
///   motion.
class AknFlowLine extends StatelessWidget {
  const AknFlowLine({
    super.key,
    required this.flow,
    this.labels = true,
    this.semanticLabel,
  });

  final AknFlow flow;

  /// Show the stop labels (on by default; they hide only under 280 dp).
  final bool labels;

  /// Overrides [AknFlow.spoken].
  final String? semanticLabel;

  /// Height of the mark row.
  static const double markRow = 20;

  /// Labels show at this width and wider.
  static const double labelMinWidth = 280;

  @override
  Widget build(BuildContext context) {
    final n = flow.stops.length;
    if (n == 0) return const SizedBox.shrink();
    final scaler = MediaQuery.textScalerOf(context);
    final large = scaler.scale(10) >= 13;
    final spoken = semanticLabel ?? flow.spoken;
    if (large) {
      return Semantics(
        container: true,
        label: spoken,
        child: ExcludeSemantics(child: _timeline()),
      );
    }
    return Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth.isFinite ? box.maxWidth : 350.0;
            final showLabels = labels && width >= labelMinWidth;
            return _FlowStrip(flow: flow, width: width, labels: showLabels);
          },
        ),
      ),
    );
  }

  Widget _timeline() {
    final n = flow.stops.length;
    final i = flow.index;
    return StepTimeline(
      dense: true,
      yourMove: flow.yourMove,
      steps: [
        for (var k = 0; k < n; k++)
          TimelineStep(
            title: flow.stops[k],
            state: flow.delivered || k < i
                ? TimelineState.done
                : k == i
                ? (flow.problem ? TimelineState.failed : TimelineState.current)
                : TimelineState.upcoming,
          ),
      ],
    );
  }
}

/// The horizontal line with its labels.
class _FlowStrip extends StatelessWidget {
  const _FlowStrip({
    required this.flow,
    required this.width,
    required this.labels,
  });

  final AknFlow flow;
  final double width;
  final bool labels;

  /// Horizontal inset of the first and last stop centres (half the mark).
  static const double pad = 10;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final n = flow.stops.length;
    final span = n <= 1 ? 0.0 : (width - pad * 2) / (n - 1);
    double xOf(int i) => n <= 1 ? width / 2 : pad + span * i;
    final scaler = MediaQuery.textScalerOf(context);
    final labelLine = scaler.scale(12) * 16 / 12;
    final labelWidth = math.max(span, 56.0);
    final i = flow.index;
    final base = t.caption.copyWith(fontSize: 12, height: 16 / 12);
    final duration = AknMotion.of(context, AknMotion.base);

    TextStyle styleOf(int k) {
      final passed = flow.delivered || k < i;
      final current = !flow.delivered && k == i;
      return base.copyWith(
        color: current && flow.yourMove
            ? c.brandInk
            : current && flow.problem
            ? c.danger.fg
            : passed || current
            ? c.ink
            : c.dim,
        fontWeight: current
            ? FontWeight.w800
            : passed
            ? FontWeight.w600
            : FontWeight.w500,
        letterSpacing: 0,
      );
    }

    final track = SizedBox(
      height: AknFlowLine.markRow,
      child: _FlowTrack(flow: flow),
    );
    if (!labels) return track;
    return SizedBox(
      height: AknFlowLine.markRow + 8 + labelLine * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 0, right: 0, top: 0, child: track),
          for (var k = 0; k < n; k++)
            Positioned(
              top: AknFlowLine.markRow + 8,
              left: k == 0
                  ? 0
                  : k == n - 1
                  ? width - labelWidth
                  : xOf(k) - labelWidth / 2,
              width: labelWidth,
              child: AnimatedDefaultTextStyle(
                duration: duration,
                curve: AknMotion.standard,
                style: styleOf(k),
                child: Text(
                  flow.stops[k],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: k == 0
                      ? TextAlign.start
                      : k == n - 1
                      ? TextAlign.end
                      : TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The animated track of an [AknFlowLine]: first draw, hops, the ping.
class _FlowTrack extends StatefulWidget {
  const _FlowTrack({required this.flow});

  final AknFlow flow;

  @override
  State<_FlowTrack> createState() => _FlowTrackState();
}

class _FlowTrackState extends State<_FlowTrack>
    with SingleTickerProviderStateMixin {
  /// The » lands with a ~4 % overshoot.
  static const Curve _land = Cubic(0.3, 0, 0.2, 1.12);

  late final AnimationController _c = AnimationController(
    vsync: this,
    value: 1,
  );
  late final CurvedAnimation _t = CurvedAnimation(parent: _c, curve: _land);
  double _from = 0;
  late double _to = _target(widget.flow);
  bool _started = false;

  /// The current run is the first draw (the » grows in with it).
  bool _first = false;

  static double _target(AknFlow f) =>
      (f.delivered ? f.stops.length - 1 : f.index).toDouble();

  double get _position => _from + (_to - _from) * _t.value;

  Object get _handoffKey => ('AknFlowLine', widget.flow);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // A remounted line (scroll, tab return) does not draw itself again.
    final handed = AknEntranceHandoff.take(_handoffKey);
    if (handed != null) {
      _from = 0;
      _c.value = handed;
      if (handed < 1 && !AknMotion.reduced(context)) _c.forward();
      return;
    }
    _go(from: 0, first: true);
  }

  @override
  void deactivate() {
    AknEntranceHandoff.put(_handoffKey, _c.value);
    super.deactivate();
  }

  @override
  void didUpdateWidget(_FlowTrack old) {
    super.didUpdateWidget(old);
    final next = _target(widget.flow);
    if (next != _to) {
      final from = _position;
      _to = next;
      AknHaptics.selection();
      _go(from: from, first: false);
    }
  }

  void _go({required double from, required bool first}) {
    _from = from;
    _first = first;
    final d = AknMotion.of(
      context,
      first ? AknMotion.flowDraw : AknMotion.flowHop,
    );
    _t.curve = first ? _land : AknMotion.spring;
    if (d == Duration.zero || (from == _to && !first)) {
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
    final f = widget.flow;
    Widget paint(double ping) => AnimatedBuilder(
      animation: _t,
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: AknFlowPainter(
          count: f.stops.length,
          position: _position,
          entrance: _first && _c.isAnimating ? _c.value : 1,
          delivered: f.delivered,
          problem: f.problem,
          ping: ping,
          colors: c,
        ),
      ),
    );
    // One "you are here" loop: the ping on the viewer's move, the vehicle
    // ping in transit — the page's focus loop (budgeted).
    final live = (f.yourMove || f.moving) && !f.delivered && !f.problem;
    return RepaintBoundary(
      child: live
          ? AknAmbient(
              period: AknMotion.breathe,
              curve: Curves.linear,
              role: AknAmbientRole.focus,
              builder: (context, p, _) => paint(p),
            )
          : paint(0),
    );
  }
}

/// Paints the Akış line (v4 §3b): the track, beads, the » mark (or the end
/// disc) and the ping. [position] is the animated stop index of the mark,
/// [entrance] (0–1) the first draw, [ping] (0–1, looping) the ring.
class AknFlowPainter extends CustomPainter {
  AknFlowPainter({
    required this.count,
    required this.position,
    required this.colors,
    this.entrance = 1,
    this.delivered = false,
    this.problem = false,
    this.ping = 0,
    this.mark = 20,
  });

  final int count;
  final double position;
  final AknColors colors;
  final double entrance;
  final bool delivered;
  final bool problem;
  final double ping;

  /// The » tile's side.
  final double mark;

  @override
  void paint(Canvas canvas, Size size) {
    if (count == 0 || size.isEmpty) return;
    final c = colors;
    final y = size.height / 2;
    final pad = mark / 2;
    final last = (count - 1).toDouble();
    final span = count <= 1 ? 0.0 : (size.width - pad * 2) / last;
    double xOf(double i) => count <= 1 ? size.width / 2 : pad + span * i;
    final pos = position.clamp(0.0, last);
    final xm = xOf(pos);
    final x0 = xOf(0);
    final xn = xOf(last);
    final lineW = 3.0 * mark / 20;

    // The rest of the way: dotted `lineStrong`, 2 dp dots every 6 dp
    // (none past a problem: the line ends there).
    if (!problem && !delivered) {
      final dots = Paint()..color = c.lineStrong;
      for (var x = xm + mark / 2 + 4; x <= xn; x += 6) {
        canvas.drawCircle(Offset(x, y), 1, dots);
      }
    }
    // The travelled way: the brand gradient up to the mark.
    final travelledTo = delivered ? xn : xm;
    if (travelledTo > x0) {
      canvas.drawLine(
        Offset(x0, y),
        Offset(travelledTo, y),
        Paint()
          ..strokeWidth = lineW
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            colors: [c.brandFillStart, c.brandFill],
          ).createShader(Rect.fromLTRB(x0, y - 2, math.max(x0 + 1, xn), y + 2)),
      );
    }

    // Beads: passed (surface + 2 dp brand ring, popping 0.6 → 1 as the mark
    // passes), future (hollow `lineStrong`).
    final bead = 4.0 * mark / 20;
    for (var i = 0; i < count; i++) {
      final center = Offset(xOf(i.toDouble()), y);
      final atMark = (i - pos).abs() < 0.5;
      if (atMark && !(delivered && i < last)) continue;
      final passed = i < pos - 0.01 || (delivered && i <= last);
      if (passed) {
        final pop = Curves.easeOutBack.transform(
          ((pos - i) / 0.45).clamp(0.0, 1.0),
        );
        final s = 0.6 + 0.4 * pop;
        canvas.drawCircle(center, bead * s, Paint()..color = c.surface);
        canvas.drawCircle(
          center,
          (bead - 1) * s,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = c.brandFill,
        );
      } else {
        canvas.drawCircle(center, bead, Paint()..color = c.surface);
        canvas.drawCircle(
          center,
          bead - 1,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = c.lineStrong,
        );
      }
    }

    final center = Offset(xm, y);
    if (delivered) {
      _disc(canvas, Offset(xn, y), c.ok.solid, c.ok.onSolid, check: true);
      return;
    }
    if (problem) {
      _disc(canvas, center, c.danger.solid, c.danger.onSolid, check: false);
      return;
    }
    // The ping ring grows out of the tile and fades.
    if (ping > 0) {
      final grow = Curves.easeOutCubic.transform(ping);
      final side = mark + 14 * grow;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: side, height: side),
          Radius.circular(6 + 6 * grow),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = c.logo.withValues(alpha: 0.45 * (1 - ping)),
      );
    }
    // The » glides in with the first draw (fades and grows in).
    final e = Curves.easeOut.transform(entrance.clamp(0.0, 1.0));
    canvas.save();
    canvas.translate(center.dx, center.dy);
    final s = 0.7 + 0.3 * e;
    canvas.scale(s);
    canvas.translate(-center.dx, -center.dy);
    paintFlowMark(
      canvas,
      center,
      side: mark,
      tile: c.logo.withValues(alpha: c.logo.a * (0.3 + 0.7 * e)),
      glow: e,
    );
    canvas.restore();
  }

  void _disc(
    Canvas canvas,
    Offset center,
    Color fill,
    Color ink, {
    required bool check,
  }) {
    final r = mark / 2;
    canvas.drawCircle(center, r, Paint()..color = fill);
    final pen = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final k = r * 0.42;
    if (check) {
      canvas.drawPath(
        Path()
          ..moveTo(center.dx - k, center.dy + 0.05 * k)
          ..lineTo(center.dx - 0.25 * k, center.dy + 0.75 * k)
          ..lineTo(center.dx + k, center.dy - 0.65 * k),
        pen,
      );
    } else {
      canvas.drawLine(
        center + Offset(-k * 0.8, -k * 0.8),
        center + Offset(k * 0.8, k * 0.8),
        pen,
      );
      canvas.drawLine(
        center + Offset(k * 0.8, -k * 0.8),
        center + Offset(-k * 0.8, k * 0.8),
        pen,
      );
    }
  }

  @override
  bool shouldRepaint(AknFlowPainter old) =>
      old.count != count ||
      old.position != position ||
      old.entrance != entrance ||
      old.delivered != delivered ||
      old.problem != problem ||
      old.ping != ping ||
      old.mark != mark ||
      old.colors != colors;
}

/// The compact Akış for list rows (v4 §3b): one 10 × 3 segment per stop
/// with a 12 dp » mini tile at the current stop (an ok check disc when
/// delivered, a danger disc on a problem), then the [sentence] (13/18).
/// Static (lists hold still).
///
/// [quiet] (the default, list rows; P5 "orange has two jobs"): the » is ink
/// on the neutral well, passed segments are ink at 40 %, the stops ahead a
/// soft `lineStrong`; the sentence is ink 600 on the viewer's move and Pas
/// only when the row is [urgent] (its deadline 3 h or less away), dim
/// otherwise. A screen of rows then holds at most a few orange marks. The
/// loud look (logo-orange » tile, brand segments, a Pas sentence on every
/// move) belongs to [AknFlowLine] on detail pages and the home's Yolda row.
class AknFlowPips extends StatelessWidget {
  const AknFlowPips({
    super.key,
    required this.flow,
    this.sentence,
    this.urgent = false,
    this.quiet = true,
  });

  final AknFlow flow;

  /// "Yolda · varış 09:00", "Teklifi onaylayın".
  final String? sentence;

  /// The row's deadline is 3 h or less away: a your-move sentence turns
  /// Pas (quiet mode).
  final bool urgent;

  /// The list look (see the class doc); false gives the loud brand look.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final n = flow.stops.length;
    final i = flow.index;
    final passedColor = quiet ? c.ink.withValues(alpha: 0.4) : c.brandFill;
    final aheadColor = quiet
        ? c.lineStrong.withValues(alpha: 0.45)
        : c.lineStrong;
    final pips = <Widget>[];
    for (var k = 0; k < n; k++) {
      if (k > 0) pips.add(const SizedBox(width: 3));
      final atMark = !flow.delivered && k == i;
      if (atMark) {
        pips.add(
          CustomPaint(
            size: const Size.square(12),
            painter: _MiniMarkPainter(
              colors: c,
              problem: flow.problem,
              quiet: quiet,
            ),
          ),
        );
      } else {
        final passed = flow.delivered || k < i;
        pips.add(
          Container(
            width: 10,
            height: 3,
            decoration: BoxDecoration(
              color: passed ? passedColor : aheadColor,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        );
      }
    }
    if (flow.delivered) {
      pips.add(const SizedBox(width: 3));
      pips.add(
        CustomPaint(
          size: const Size.square(12),
          painter: _MiniMarkPainter(colors: c, delivered: true),
        ),
      );
    }
    final text = sentence;
    final pas = flow.yourMove && (!quiet || urgent);
    return Semantics(
      label: text == null ? flow.spoken : '${flow.currentLabel}: $text',
      excludeSemantics: true,
      child: Row(
        children: [
          ...pips,
          if (text != null && text.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.label.copyWith(
                  fontWeight: flow.yourMove ? FontWeight.w600 : FontWeight.w500,
                  color: pas
                      ? c.brandInk
                      : flow.yourMove
                      ? c.ink
                      : c.dim,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniMarkPainter extends CustomPainter {
  _MiniMarkPainter({
    required this.colors,
    this.problem = false,
    this.delivered = false,
    this.quiet = false,
  });

  final AknColors colors;
  final bool problem;
  final bool delivered;

  /// An ink » on the neutral well, no glow (list rows).
  final bool quiet;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    if (delivered || problem) {
      AknFlowPainter(
        count: 1,
        position: 0,
        colors: colors,
        mark: size.width,
      )._disc(
        canvas,
        center,
        delivered ? colors.ok.solid : colors.danger.solid,
        delivered ? colors.ok.onSolid : colors.danger.onSolid,
        check: delivered,
      );
      return;
    }
    if (quiet) {
      paintFlowMark(
        canvas,
        center,
        side: size.width,
        tile: colors.surfaceAlt,
        glyph: colors.ink,
        glow: 0,
      );
      return;
    }
    paintFlowMark(
      canvas,
      center,
      side: size.width,
      tile: colors.logo,
      glow: 0.6,
    );
  }

  @override
  bool shouldRepaint(_MiniMarkPainter old) =>
      old.colors != colors ||
      old.problem != problem ||
      old.delivered != delivered ||
      old.quiet != quiet;
}

/// Under the line (v4 §3b): one 15/20 700 sentence — Pas on the viewer's
/// move — with the countdown (or time) on the right, then a 14/20 dim line
/// that says who acts and by when. A new sentence cross-fades.
///
/// ```dart
/// StageNow(
///   sentence: 'Teklifi onaylayın',
///   yourMove: true,
///   trailing: CountdownBadge(deadline: expiresAt, yourMove: true, compact: true),
///   detail: 'Demir Petrol teklif verdi · bugün 21:00\'e kadar',
/// )
/// ```
class StageNow extends StatelessWidget {
  const StageNow({
    super.key,
    required this.sentence,
    this.yourMove = false,
    this.trailing,
    this.detail,
  });

  final String sentence;
  final bool yourMove;

  /// A countdown or a time, on the right.
  final Widget? trailing;

  /// Who acts and by when (14/20 dim).
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final head = Text(
      sentence,
      style: t.bodyStrong.copyWith(
        fontSize: 15,
        height: 20 / 15,
        fontWeight: FontWeight.w700,
        color: yourMove ? c.brandInk : c.ink,
      ),
    );
    final d = detail;
    return Semantics(
      container: true,
      child: FadeThroughSwitcher(
        duration: AknMotion.statusFade,
        alignment: AlignmentDirectional.topStart,
        child: Column(
          key: ValueKey((sentence, d)),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: head),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
            if (d != null && d.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(d, style: t.bodySmall.copyWith(color: c.dim)),
            ],
          ],
        ),
      ),
    );
  }
}
