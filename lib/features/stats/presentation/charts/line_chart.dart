import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// Bir çizgi noktası (değeri olmayan ay atlanır, çizgi kopmaz).
@immutable
class LinePoint {
  const LinePoint({required this.label, required this.value});

  final String label;
  final double? value;
}

/// Aylık çizgi (ortalama birim fiyat): 2 px çizgi, %10 alan dolgusu, son noktada yüzey halkalı nokta;
/// soldan sağa çizilir (700 ms). [labels] açıkken altında ay adları, en düşük ve en yüksek değer
/// etiketlenir. Değer metinleri mürekkep renginde (veri rengi metinde kullanılmaz).
class StatsLineChart extends StatelessWidget {
  const StatsLineChart({
    super.key,
    required this.points,
    required this.color,
    required this.valueLabel,
    required this.semanticsLabel,
    this.labels = true,
    this.emptyHint,
  });

  final List<LinePoint> points;
  final Color color;
  final String Function(double value) valueLabel;
  final String semanticsLabel;
  final bool labels;
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final reduced = AknMotion.reduced(context);
    final values = [
      for (final p in points)
        if (p.value != null) p.value!,
    ];
    final scaler = MediaQuery.textScalerOf(context);
    final monthH = labels ? scaler.scale(11) * 1.4 + 4 : 0.0;
    final valueH = labels ? scaler.scale(11) * 1.35 + 2 : 0.0;
    if (values.length < 2) {
      return Center(
        child: Text(
          emptyHint ?? '',
          textAlign: TextAlign.center,
          style: t.caption.copyWith(color: c.dim, fontWeight: FontWeight.w600),
        ),
      );
    }
    return Semantics(
      label: semanticsLabel,
      image: true,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, cons) {
          final plotH = math.max(16.0, cons.maxHeight - monthH - valueH * 2);
          return Column(
            children: [
              SizedBox(
                height: plotH + valueH * 2,
                width: cons.maxWidth,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: reduced ? 1 : 0, end: 1),
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, p, _) => CustomPaint(
                    painter: _LinePainter(
                      points: points,
                      color: color,
                      surface: c.surface,
                      grid: c.lineSoft,
                      progress: p,
                      padTop: valueH,
                      padBottom: valueH,
                      labelStyle: labels
                          ? t.caption.copyWith(
                              fontSize: 11,
                              color: c.ink,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            )
                          : null,
                      valueLabel: valueLabel,
                      textScaler: scaler,
                    ),
                  ),
                ),
              ),
              if (labels)
                SizedBox(
                  height: monthH,
                  child: Row(
                    children: [
                      for (final p in points)
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Text(
                              p.label,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: t.caption.copyWith(
                                fontSize: 11,
                                color: c.dim,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.points,
    required this.color,
    required this.surface,
    required this.grid,
    required this.progress,
    required this.padTop,
    required this.padBottom,
    required this.labelStyle,
    required this.valueLabel,
    required this.textScaler,
  });

  final List<LinePoint> points;
  final Color color;
  final Color surface;
  final Color grid;
  final double progress;
  final double padTop;
  final double padBottom;
  final TextStyle? labelStyle;
  final String Function(double value) valueLabel;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    if (n == 0) return;
    final vals = [
      for (final p in points)
        if (p.value != null) p.value!,
    ];
    if (vals.length < 2) return;
    var lo = vals.reduce(math.min);
    var hi = vals.reduce(math.max);
    if ((hi - lo).abs() < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    // Uçlar kenara yapışmasın: %12 pay.
    final span = hi - lo;
    lo -= span * 0.12;
    hi += span * 0.12;
    final slot = size.width / n;
    final top = padTop;
    final h = math.max(1.0, size.height - padTop - padBottom);
    Offset at(int i, double v) =>
        Offset(slot * i + slot / 2, top + h * (1 - (v - lo) / (hi - lo)));

    final pts = <(int, Offset)>[
      for (var i = 0; i < n; i++)
        if (points[i].value != null) (i, at(i, points[i].value!)),
    ];

    // Taban kılavuzu.
    canvas.drawLine(
      Offset(0, top + h),
      Offset(size.width, top + h),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );

    final line = Path()..moveTo(pts.first.$2.dx, pts.first.$2.dy);
    for (final p in pts.skip(1)) {
      line.lineTo(p.$2.dx, p.$2.dy);
    }
    final clipW =
        pts.first.$2.dx + (pts.last.$2.dx - pts.first.$2.dx) * progress;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, clipW + 1, size.height));
    final area = Path.from(line)
      ..lineTo(pts.last.$2.dx, top + h)
      ..lineTo(pts.first.$2.dx, top + h)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    if (progress >= 0.999) {
      final last = pts.last.$2;
      canvas.drawCircle(last, 6, Paint()..color = surface);
      canvas.drawCircle(last, 4, Paint()..color = color);
    }

    final style = labelStyle;
    if (style == null || progress < 0.999) return;
    // En düşük ve en yüksek nokta etiketleri (seçici etiketleme).
    var minI = pts.first;
    var maxI = pts.first;
    for (final p in pts) {
      if (points[p.$1].value! < points[minI.$1].value!) minI = p;
      if (points[p.$1].value! > points[maxI.$1].value!) maxI = p;
    }
    void label(Offset o, double v, {required bool above}) {
      final tp = TextPainter(
        text: TextSpan(text: valueLabel(v), style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final x = (o.dx - tp.width / 2).clamp(0.0, size.width - tp.width);
      final y = above ? o.dy - tp.height - 6 : o.dy + 6;
      tp.paint(canvas, Offset(x, y.clamp(0.0, size.height - tp.height)));
    }

    label(maxI.$2, points[maxI.$1].value!, above: true);
    if (minI.$1 != maxI.$1) {
      label(minI.$2, points[minI.$1].value!, above: false);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.progress != progress ||
      old.points != points ||
      old.color != color ||
      old.surface != surface ||
      old.labelStyle != labelStyle;
}
