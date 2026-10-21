import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';
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

  /// Deprecated: v2 dots carry no icons; ignored.
  final IconData? icon;

  /// Extra content under the texts (e.g. plate badge, note).
  final Widget? content;

  /// Overrides [StepTimeline.yourMove] for this step.
  final bool? yourMove;
}

/// Vertical timeline (design v2 §6.14): "Sipariş akışı" (chronological) and
/// "Hareketler" (newest first — the caller orders the steps).
///
/// Dots: 12 px ink (done), a 16 px ring (current — orange with a soft halo
/// when it is the viewer's move ([yourMove]), else ink), 12 px hollow faint
/// (future); a 16 px danger disc with × (failed) or a warn disc with !
/// (warning). Connector: 2 px ink below done steps, dashed faint toward the
/// future. Title 16/22 600 (future: dim 500), meta 14/20 dim, time 14/22 500
/// dim on the right (under the title at ≥ 1.3× text). No pulse, no motion.
class StepTimeline extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(
            step: steps[i],
            last: i == steps.length - 1,
            dense: dense,
            index: i,
            count: steps.length,
            yourMove: steps[i].yourMove ?? yourMove,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.step,
    required this.last,
    required this.dense,
    required this.index,
    required this.count,
    required this.yourMove,
  });

  final TimelineStep step;
  final bool last;
  final bool dense;
  final int index;
  final int count;
  final bool yourMove;

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
    // Büyük yazıda (≥ 1,3×) saat başlığın sağında değil altında durur: dar ekranda taşmaz.
    final stackTime = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final titleStyle = t.bodyStrong.copyWith(
      fontSize: 16,
      height: 22 / 16,
      color: upcoming ? c.dim : c.ink,
      fontWeight: upcoming ? FontWeight.w500 : FontWeight.w600,
    );
    final timeStyle = t.bodySmall.copyWith(
      height: 22 / 14,
      fontWeight: FontWeight.w500,
      color: c.dim,
    );
    // The dot sits on the title's first line (22 px, scaled with the text).
    final lineHeight = MediaQuery.textScalerOf(context).scale(22);
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
              width: 20,
              child: CustomPaint(
                painter: _TimelineRailPainter(
                  state: step.state,
                  last: last,
                  yourMove: yourMove,
                  lineHeight: lineHeight,
                  colors: c,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : (dense ? 12 : 16)),
                child: Column(
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
                    if (step.time != null && stackTime)
                      Text(step.time!, style: timeStyle),
                    if (step.subtitle != null)
                      Text(step.subtitle!, style: t.bodySmall),
                    if (step.content != null) ...[
                      const SizedBox(height: 8),
                      step.content!,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dot of one timeline row and the connector down to the next row.
class _TimelineRailPainter extends CustomPainter {
  _TimelineRailPainter({
    required this.state,
    required this.last,
    required this.yourMove,
    required this.lineHeight,
    required this.colors,
  });

  final TimelineState state;
  final bool last;
  final bool yourMove;
  final double lineHeight;
  final AknColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;
    final x = size.width / 2;
    final cy = lineHeight / 2;
    final big =
        state == TimelineState.current ||
        state == TimelineState.failed ||
        state == TimelineState.warning;
    final r = big ? 8.0 : 6.0;

    if (!last) {
      final from = cy + r + 2;
      final to = size.height + math.max(0, (lineHeight / 2) - 8) - 2;
      if (state == TimelineState.done) {
        canvas.drawLine(
          Offset(x, from),
          Offset(x, to),
          Paint()
            ..color = c.ink
            ..strokeWidth = 2,
        );
      } else {
        final dash = Paint()
          ..color = c.faint
          ..strokeWidth = 2;
        for (var y = from; y < to; y += 7) {
          canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 4, to)), dash);
        }
      }
    }

    final center = Offset(x, cy);
    switch (state) {
      case TimelineState.done:
        canvas.drawCircle(center, r, Paint()..color = c.ink);
      case TimelineState.upcoming:
        canvas.drawCircle(center, r, Paint()..color = c.bg);
        canvas.drawCircle(
          center,
          r - 1,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = c.faint,
        );
      case TimelineState.current:
        final ring = yourMove ? c.logo : c.ink;
        if (yourMove) {
          canvas.drawCircle(center, r + 4, Paint()..color = c.brandSoft);
        }
        canvas.drawCircle(center, r, Paint()..color = c.bg);
        canvas.drawCircle(
          center,
          r - 1.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = ring,
        );
      case TimelineState.failed || TimelineState.warning:
        final tone = state == TimelineState.failed ? c.danger : c.warn;
        canvas.drawCircle(center, r, Paint()..color = tone.solid);
        final mark = Paint()
          ..color = tone.onSolid
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        if (state == TimelineState.failed) {
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
    }
  }

  @override
  bool shouldRepaint(_TimelineRailPainter old) =>
      old.state != state ||
      old.last != last ||
      old.yourMove != yourMove ||
      old.lineHeight != lineHeight ||
      old.colors != colors;
}

/// Wizard progress header (§6.14): the [StageStrip] visual with the step
/// labels, the current step's ring in orange (in a wizard it is always the
/// viewer's move). Completed steps can be tapped to go back when
/// [onStepTap] is set (48 dp targets, "Ürün adımına dön"). At ≥ 1.3× text
/// or on a narrow screen it shows the dots and one line "Adım 2 / 4:
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
