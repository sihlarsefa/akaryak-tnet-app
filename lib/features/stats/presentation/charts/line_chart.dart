import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// Bir çizgi noktası (değeri olmayan ay atlanır).
@immutable
class LinePoint {
  const LinePoint({required this.label, required this.value});

  final String label;
  final double? value;
}

/// Aylık çizgi (ortalama birim fiyat; tasarım v2 §5.1 "line on plate", §6.20): 2 px mürekkep çizgi,
/// son noktada 10 px `chartHighlight` nokta ve 2 px yüzey halkası, 12/16 700 son değer etiketi (gelen
/// çizginin karşı tarafında, üstüne binmez), taban çizgisi ve ay adları (sonuncusu kalın). Küçük
/// oynamalar abartılmasın diye dikey aralık ortalamanın en az %4'üdür. Plakada aynı çizim plaka
/// mürekkebiyle çıkar (renkler bağlamdan).
class StatsLine extends StatelessWidget {
  const StatsLine({
    super.key,
    required this.values,
    this.labels = const [],
    this.endLabel,
    this.height = 74,
    this.semanticLabel,
  });

  final List<double> values;

  /// Değer başına bir ay adı ("May" … "Eki").
  final List<String> labels;

  /// Son noktanın etiketi ("42,34").
  final String? endLabel;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final base = t.caption.copyWith(
      fontSize: 12,
      height: 16 / 12,
      letterSpacing: 0,
    );
    return Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _LinePainter(
            values: values,
            labels: labels,
            endLabel: endLabel,
            line: c.ink,
            dot: c.chartHighlight,
            ring: c.surface,
            base: c.line,
            labelStyle: base.copyWith(
              color: c.dim,
              fontWeight: FontWeight.w500,
            ),
            strongStyle: base.copyWith(
              color: c.ink,
              fontWeight: FontWeight.w700,
            ),
            scaler: MediaQuery.textScalerOf(context),
          ),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.labels,
    required this.endLabel,
    required this.line,
    required this.dot,
    required this.ring,
    required this.base,
    required this.labelStyle,
    required this.strongStyle,
    required this.scaler,
  });

  final List<double> values;
  final List<String> labels;
  final String? endLabel;
  final Color line;
  final Color dot;
  final Color ring;
  final Color base;
  final TextStyle labelStyle;
  final TextStyle strongStyle;
  final TextScaler scaler;

  TextPainter _tp(String s, TextStyle st) => TextPainter(
    text: TextSpan(text: s, style: st),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    final labelH = labels.isEmpty ? 0.0 : scaler.scale(12) * 16 / 12 + 4;
    final baseY = size.height - labelH;
    canvas.drawLine(
      Offset(0, baseY - 0.5),
      Offset(size.width, baseY - 0.5),
      Paint()
        ..color = base
        ..strokeWidth = 1,
    );
    const left = 22.0;
    final right = size.width - 24;
    double x(int i) =>
        n <= 1 ? (left + right) / 2 : left + i * (right - left) / (n - 1);
    if (labels.length == n) {
      for (var i = 0; i < n; i++) {
        final tp = _tp(labels[i], i == n - 1 ? strongStyle : labelStyle);
        tp.paint(canvas, Offset(x(i) - tp.width / 2, size.height - tp.height));
        tp.dispose();
      }
    }
    if (n == 0) return;
    var lo = values.reduce(math.min);
    var hi = values.reduce(math.max);
    final mean = values.fold<double>(0, (a, v) => a + v) / n;
    final minSpan = mean.abs() * 0.04;
    if (hi - lo < minSpan) {
      final mid = (hi + lo) / 2;
      lo = mid - minSpan / 2;
      hi = mid + minSpan / 2;
    }
    final endH = endLabel == null ? 0.0 : scaler.scale(12) * 16 / 12;
    final top = 8.0 + math.min(endH, 10);
    final bottom = baseY - 10;
    final span = hi - lo;
    double y(int i) => span <= 0
        ? (top + bottom) / 2
        : bottom - (values[i] - lo) / span * (bottom - top);
    final path = Path()..moveTo(x(0), y(0));
    for (var i = 1; i < n; i++) {
      path.lineTo(x(i), y(i));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final end = Offset(x(n - 1), y(n - 1));
    canvas.drawCircle(end, 7, Paint()..color = ring);
    canvas.drawCircle(end, 5, Paint()..color = dot);
    final el = endLabel;
    if (el != null) {
      final tp = _tp(el, strongStyle);
      // Etiket, son noktaya gelen çizginin karşı tarafına (çizgi yukarıdan geliyorsa alta).
      final fromAbove = n >= 2 && y(n - 2) < end.dy;
      final lx = (end.dx - 8 - tp.width).clamp(0.0, size.width - tp.width);
      final ly = fromAbove ? end.dy + 7 : end.dy - 7 - tp.height;
      tp.paint(
        canvas,
        Offset(lx, ly.clamp(0.0, math.max(0.0, baseY - tp.height - 1))),
      );
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values ||
      old.labels != labels ||
      old.endLabel != endLabel ||
      old.line != line ||
      old.dot != dot ||
      old.ring != ring ||
      old.base != base ||
      old.labelStyle != labelStyle ||
      old.strongStyle != strongStyle ||
      old.scaler != scaler;
}

/// Sayfadaki aylık çizgi ([StatsLine]); değeri olmayan aylar atlanır, iki noktadan azsa not yazar.
class StatsLineChart extends StatelessWidget {
  const StatsLineChart({
    super.key,
    required this.points,
    required this.valueLabel,
    required this.semanticsLabel,
    this.color,
    this.labels = true,
    this.emptyHint,
    this.height = 140,
  });

  final List<LinePoint> points;

  /// Son noktanın etiketi ("42,34").
  final String Function(double value) valueLabel;
  final String semanticsLabel;

  /// Deprecated: çizgi mürekkep, son nokta vurgu rengi.
  final Color? color;
  final bool labels;
  final String? emptyHint;

  /// Sınırsız yükseklikte kullanılan yükseklik.
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final priced = [
      for (final p in points)
        if (p.value != null) p,
    ];
    if (priced.length < 2) {
      return Center(
        child: Text(
          emptyHint ?? '',
          textAlign: TextAlign.center,
          style: t.bodySmall.copyWith(color: c.dim),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, cons) => StatsLine(
        values: [for (final p in priced) p.value!],
        labels: labels ? [for (final p in priced) p.label] : const [],
        endLabel: valueLabel(priced.last.value!),
        height: cons.maxHeight.isFinite ? cons.maxHeight : height,
        semanticLabel: semanticsLabel,
      ),
    );
  }
}
