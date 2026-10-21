import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import 'timeline.dart';

/// What went wrong at the current stop of a [StageStrip]: a 16 px danger
/// disc with a white "×" (rejected, cancelled) or "!" (disputed), and the
/// line ends there.
enum StageProblem { rejected, attention }

/// How a [StageStrip] reflows when it does not fit (width < 340 or text
/// scale ≥ 1.3).
enum StageStripFallback {
  /// A vertical [StepTimeline] (order detail).
  timeline,

  /// The dots without labels plus one line "Adım 2 / 4: Teslimat" (wizard
  /// headers).
  compact,
}

/// The order's stage strip (design v2 §6.14): stops evenly spaced over the
/// content width — Talep, Onay, Teklif, Karar, Plan, Yolda, Teslim.
///
/// * Done: 10 px ink dot, solid 2 px ink connector.
/// * Current: a 16 px ring — 3 px logo ring, 6 px logo centre and a 4 px
///   soft halo when it is the viewer's move ([yourMove]), else the same ring
///   in ink.
/// * Future: 10 px hollow ring (2 px faint), dashed 2 px faint connector
///   (6 on, 4 off).
/// * [problem]: a danger disc with a white × or ! at the current stop; the
///   line ends there.
/// * Labels 12/16: done ink 500, current ink 700, future dim 400.
/// * When [current] changes the ring slides to the new stop in 240 ms
///   (instant under reduce motion).
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

  /// Height of the dot row.
  static const double _dotRow = 16;

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
    final content = _dotRow + (labels ? 6 + labelHeight : 0);
    final tappable = onStageTap != null;
    final height = tappable ? math.max(content, AknSpace.minTap) : content;
    final top = (height - content) / 2;
    final labelWidth = math.max(span, 52.0);
    final summaryLine = !labels && fallback == StageStripFallback.compact;

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
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: current.toDouble()),
                duration: AknMotion.of(context, AknMotion.stageStep),
                curve: AknMotion.emphasizedCurve,
                builder: (context, position, _) => CustomPaint(
                  painter: StageStripPainter(
                    count: n,
                    position: position,
                    pad: _pad,
                    yourMove: yourMove,
                    problem: problem,
                    colors: c,
                  ),
                ),
              ),
            ),
          ),
          if (labels)
            for (var i = 0; i < n; i++)
              Positioned(
                left: xOf(i) - labelWidth / 2,
                width: labelWidth,
                top: top + _dotRow + 6,
                child: ExcludeSemantics(
                  child: Text(
                    stages[i],
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    textAlign: TextAlign.center,
                    style: labelStyle.copyWith(
                      color: i <= current ? c.ink : c.dim,
                      fontWeight: i < current
                          ? FontWeight.w500
                          : i == current
                          ? FontWeight.w700
                          : FontWeight.w400,
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
                    onTap: () => onStageTap!(i),
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
              const SizedBox(height: 4),
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

/// Paints the dots and connectors of a [StageStrip]; [position] is the
/// (animated) index of the current stop.
class StageStripPainter extends CustomPainter {
  StageStripPainter({
    required this.count,
    required this.position,
    required this.pad,
    required this.yourMove,
    required this.problem,
    required this.colors,
  });

  final int count;
  final double position;
  final double pad;
  final bool yourMove;
  final StageProblem? problem;
  final AknColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (count == 0) return;
    final c = colors;
    final y = size.height / 2;
    final span = count <= 1 ? 0.0 : (size.width - pad * 2) / (count - 1);
    double xOf(double i) => count <= 1 ? size.width / 2 : pad + span * i;
    final allDone = position >= count - 0.001 && problem == null;
    final pos = position.clamp(0.0, (count - 1).toDouble());
    final xCur = xOf(pos);

    // Connectors: solid ink up to the current stop, dashed faint after it.
    final solid = Paint()
      ..color = c.ink
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(xOf(0), y),
      Offset(allDone ? xOf(count - 1.0) : xCur, y),
      solid,
    );
    if (!allDone && problem == null) {
      final dash = Paint()
        ..color = c.faint
        ..strokeWidth = 2;
      final end = xOf(count - 1.0);
      for (var x = xCur + 8; x < end; x += 10) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 6, end), y), dash);
      }
    }

    // Stops.
    for (var i = 0; i < count; i++) {
      final x = xOf(i.toDouble());
      final isDone = allDone || i < pos - 0.5;
      final isCurrent = !allDone && (i - pos).abs() <= 0.5;
      if (isCurrent) continue;
      if (isDone) {
        canvas.drawCircle(Offset(x, y), 5, Paint()..color = c.ink);
      } else {
        canvas.drawCircle(Offset(x, y), 5, Paint()..color = c.bg);
        canvas.drawCircle(
          Offset(x, y),
          4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = c.faint,
        );
      }
    }
    if (allDone) return;

    final center = Offset(xCur, y);
    if (problem != null) {
      final tone = c.danger;
      canvas.drawCircle(center, 8, Paint()..color = tone.solid);
      final mark = Paint()
        ..color = tone.onSolid
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      if (problem == StageProblem.rejected) {
        canvas.drawLine(
          center + const Offset(-3, -3),
          center + const Offset(3, 3),
          mark,
        );
        canvas.drawLine(
          center + const Offset(3, -3),
          center + const Offset(-3, 3),
          mark,
        );
      } else {
        canvas.drawLine(
          center + const Offset(0, -4),
          center + const Offset(0, 1),
          mark,
        );
        canvas.drawCircle(
          center + const Offset(0, 4),
          1.2,
          Paint()..color = tone.onSolid,
        );
      }
      return;
    }
    final ringColor = yourMove ? c.logo : c.ink;
    if (yourMove) {
      canvas.drawCircle(center, 12, Paint()..color = c.brandSoft);
    }
    canvas.drawCircle(center, 8, Paint()..color = c.bg);
    canvas.drawCircle(
      center,
      6.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = ringColor,
    );
    canvas.drawCircle(center, 3, Paint()..color = ringColor);
  }

  @override
  bool shouldRepaint(StageStripPainter old) =>
      old.count != count ||
      old.position != position ||
      old.pad != pad ||
      old.yourMove != yourMove ||
      old.problem != problem ||
      old.colors != colors;
}
