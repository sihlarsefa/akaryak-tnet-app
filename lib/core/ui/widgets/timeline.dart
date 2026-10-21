import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';

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
  });

  final String title;
  final String? subtitle;

  /// Right-aligned time text ("21.10 14:20").
  final String? time;
  final TimelineState state;

  /// Replaces the default state icon in the dot.
  final IconData? icon;

  /// Extra content under the texts (e.g. plate badge, note).
  final Widget? content;
}

/// Vertical order / delivery timeline. Done steps are joined by a solid ok
/// line, the current step has a soft pulsing ring (static under reduce
/// motion), upcoming steps are hollow and joined by a dashed line.
class StepTimeline extends StatelessWidget {
  const StepTimeline({super.key, required this.steps, this.dense = false});

  final List<TimelineStep> steps;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(
            step: steps[i],
            first: i == 0,
            last: i == steps.length - 1,
            next: i + 1 < steps.length ? steps[i + 1] : null,
            dense: dense,
            index: i,
            count: steps.length,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.step,
    required this.first,
    required this.last,
    required this.next,
    required this.dense,
    required this.index,
    required this.count,
  });

  final TimelineStep step;
  final bool first;
  final bool last;
  final TimelineStep? next;
  final bool dense;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final dot = dense ? 20.0 : 24.0;
    final reached =
        next != null &&
        (next!.state == TimelineState.done ||
            next!.state == TimelineState.current ||
            next!.state == TimelineState.failed ||
            next!.state == TimelineState.warning);
    final lineColor = reached ? c.ok.fg : c.lineStrong;
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
              width: dot + 8,
              child: Column(
                children: [
                  _Dot(step: step, size: dot, colors: c),
                  if (!last)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: CustomPaint(
                          painter: _RailPainter(
                            color: lineColor,
                            dashed: !reached,
                          ),
                          child: const SizedBox(width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : (dense ? 14 : 20)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(top: dense ? 0 : 2),
                            child: Text(
                              step.title,
                              style: t.bodyStrong.copyWith(
                                color: upcoming ? c.dim : c.ink,
                                fontWeight: step.state == TimelineState.current
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (step.time != null && !stackTime) ...[
                          const SizedBox(width: 8),
                          Padding(
                            padding: EdgeInsets.only(top: dense ? 1 : 4),
                            child: Text(
                              step.time!,
                              style: t.caption.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (step.time != null && stackTime) ...[
                      const SizedBox(height: 2),
                      Text(
                        step.time!,
                        style: t.caption.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    if (step.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(step.subtitle!, style: t.bodySmall),
                    ],
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

class _Dot extends StatefulWidget {
  const _Dot({required this.step, required this.size, required this.colors});

  final TimelineStep step;
  final double size;
  final AknColors colors;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Dot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final want =
        widget.step.state == TimelineState.current &&
        !AknMotion.reduced(context);
    if (want && _pulse == null) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2200),
      )..repeat();
    } else if (!want && _pulse != null) {
      _pulse!.dispose();
      _pulse = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final s = widget.size;
    final step = widget.step;
    final (
      Color bg,
      Color fg,
      Color? border,
      IconData? icon,
    ) = switch (step.state) {
      TimelineState.done => (
        c.ok.solid,
        c.ok.onSolid,
        null,
        step.icon ?? Icons.check_rounded,
      ),
      TimelineState.current => (c.brandFill, c.onBrandFill, null, step.icon),
      TimelineState.upcoming => (c.surface, c.faint, c.lineStrong, step.icon),
      TimelineState.failed => (
        c.danger.solid,
        c.danger.onSolid,
        null,
        step.icon ?? Icons.close_rounded,
      ),
      TimelineState.warning => (
        c.warn.solid,
        c.warn.onSolid,
        null,
        step.icon ?? Icons.priority_high_rounded,
      ),
    };
    final core = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: border == null ? null : Border.all(color: border, width: 2),
      ),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, size: s * 0.6, color: fg)
          : step.state == TimelineState.current
          ? Container(
              width: s * 0.34,
              height: s * 0.34,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            )
          : null,
    );
    final pulse = _pulse;
    if (pulse == null) {
      return SizedBox(
        width: s + 8,
        height: s,
        child: Center(child: core),
      );
    }
    return SizedBox(
      width: s + 8,
      height: s,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: pulse,
            builder: (context, _) {
              final v = Curves.easeOut.transform(pulse.value);
              return Container(
                width: s + 10 * v,
                height: s + 10 * v,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.brand.withValues(alpha: 0.28 * (1 - v)),
                ),
              );
            },
          ),
          core,
        ],
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  _RailPainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    if (!dashed) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      return;
    }
    for (var y = 0.0; y < size.height; y += 7) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, (y + 3.5).clamp(0, size.height)),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.color != color || old.dashed != dashed;
}

/// Wizard progress header: "Adım 2 / 5", the step title and a segmented
/// bar. Completed steps can be tapped to go back when [onStepTap] is set.
class StepperHeader extends StatelessWidget {
  const StepperHeader({
    super.key,
    required this.steps,
    required this.current,
    this.onStepTap,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 12),
  });

  final List<String> steps;

  /// 0-based.
  final int current;
  final ValueChanged<int>? onStepTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final n = steps.length;
    final i = current.clamp(0, n - 1);
    final duration = AknMotion.of(context, AknMotion.base);
    return Padding(
      padding: padding,
      child: Semantics(
        label: 'Adım ${i + 1} / $n: ${steps[i]}',
        excludeSemantics: onStepTap == null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Adım ${i + 1} / $n',
                  style: t.captionStrong.copyWith(color: c.brandInk),
                ),
                if (i + 1 < n) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Sonraki: ${steps[i + 1]}',
                      style: t.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            AnimatedSwitcher(
              duration: duration,
              transitionBuilder: (child, a) =>
                  FadeTransition(opacity: a, child: child),
              child: Text(
                steps[i],
                key: ValueKey(i),
                style: t.title.copyWith(fontSize: 20, height: 26 / 20),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var s = 0; s < n; s++) ...[
                  if (s > 0) const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onStepTap != null && s < i
                          ? () => onStepTap!(s)
                          : null,
                      child: Semantics(
                        button: onStepTap != null && s < i,
                        label: onStepTap != null && s < i
                            ? '${steps[s]} adımına dön'
                            : null,
                        onTap: onStepTap != null && s < i
                            ? () => onStepTap!(s)
                            : null,
                        // Dokunulabilir çubuklar 48 dp hedef (spec C.7); çizgi ortada 4 dp kalır.
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: onStepTap != null ? AknSpace.minTap : 16,
                          ),
                          child: Center(
                            child: AnimatedContainer(
                              duration: duration,
                              curve: AknMotion.standard,
                              height: 4,
                              decoration: BoxDecoration(
                                color: s <= i ? c.brand : c.lineSoft,
                                borderRadius: AknRadius.pillAll,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
