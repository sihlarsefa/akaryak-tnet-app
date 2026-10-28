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

/// Aylık çizgi (ortalama birim fiyat; tasarım v3 §4–5): 2,5 px vurgu renginde (`chartHighlight`)
/// yumuşak çizgi, altında aynı rengin aşağı doğru sönen dolgusu, son noktada 10 px nokta, 2 px yüzey
/// halkası ve hafif hale; 12/16 700 tabular son değer etiketi (gelen çizginin karşı tarafında,
/// üstüne binmez), taban saç çizgisi ve ay adları (sonuncusu kalın). Küçük oynamalar abartılmasın
/// diye dikey aralık ortalamanın en az %4'üdür.
///
/// Hareket: ilk görünüşte çizgi soldan sağa kendini çizer, dolgu onunla belirir, sonra nokta "pop"
/// ile oturur ve etiket belirir; değerler değişince yeniden çizer. Hareket azaltmada son hâli.
/// Renkler bağlamdan gelir (plakada aynı çizim plaka paletiyle çıkar).
class StatsLine extends StatefulWidget {
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
  State<StatsLine> createState() => _StatsLineState();
}

class _StatsLineState extends State<StatsLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _draw.value = 1;
    } else {
      _draw.forward();
    }
  }

  @override
  void didUpdateWidget(StatsLine old) {
    super.didUpdateWidget(old);
    if (_same(old.values, widget.values)) return;
    if (AknMotion.reduced(context)) {
      _draw.value = 1;
    } else {
      _draw.forward(from: 0);
    }
  }

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

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
      label: widget.semanticLabel,
      image: widget.semanticLabel != null,
      excludeSemantics: true,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _LinePainter(
              progress: _draw,
              values: widget.values,
              labels: widget.labels,
              endLabel: widget.endLabel,
              line: c.chartHighlight,
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
                fontFeatures: AknNumerals.tabular,
              ),
              scaler: MediaQuery.textScalerOf(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.progress,
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
  }) : super(repaint: progress);

  final Animation<double> progress;
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
    final p = progress.value;
    // Çizgi ilk %70'te çizilir; nokta ve etiket son %30'da "pop" ile oturur.
    final drawT = AknMotion.emphasizedCurve.transform((p / 0.7).clamp(0, 1));
    final popT = AknMotion.pop.transform(((p - 0.62) / 0.38).clamp(0, 1));
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
    final pts = [for (var i = 0; i < n; i++) Offset(x(i), y(i))];
    final path = _smooth(pts);
    final metric = path.computeMetrics().toList();
    final length = metric.fold<double>(0, (a, m) => a + m.length);
    final drawn = Path();
    var remaining = length * drawT;
    Offset? head;
    for (final m in metric) {
      if (remaining <= 0) break;
      final take = math.min(remaining, m.length);
      drawn.addPath(m.extractPath(0, take), Offset.zero);
      head = m.getTangentForOffset(take)?.position;
      remaining -= take;
    }
    if (n >= 2 && head != null) {
      // Çizginin altındaki sönen dolgu, çizilen kısım kadar.
      final fill = Path.from(drawn)
        ..lineTo(head.dx, baseY - 1)
        ..lineTo(pts.first.dx, baseY - 1)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              line.withValues(alpha: 0.20 * drawT),
              line.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromLTRB(0, top, size.width, baseY)),
      );
    }
    canvas.drawPath(
      drawn,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    if (popT <= 0) return;
    final end = pts.last;
    canvas.drawCircle(
      end,
      10 * popT,
      Paint()..color = dot.withValues(alpha: 0.18),
    );
    canvas.drawCircle(end, 7 * popT, Paint()..color = ring);
    canvas.drawCircle(end, 5 * popT, Paint()..color = dot);
    final el = endLabel;
    if (el != null) {
      final tp = _tp(
        el,
        strongStyle.copyWith(
          color: strongStyle.color?.withValues(
            alpha: popT.clamp(0.0, 1.0) * (strongStyle.color?.a ?? 1),
          ),
        ),
      );
      // Etiket, son noktaya gelen çizginin karşı tarafına (çizgi yukarıdan geliyorsa alta).
      final fromAbove = n >= 2 && y(n - 2) < end.dy;
      final lx = (end.dx - 10 - tp.width).clamp(0.0, size.width - tp.width);
      final ly = fromAbove ? end.dy + 8 : end.dy - 8 - tp.height;
      tp.paint(
        canvas,
        Offset(lx, ly.clamp(0.0, math.max(0.0, baseY - tp.height - 1))),
      );
      tp.dispose();
    }
  }

  /// Noktalardan geçen yumuşak eğri (aşmayan monoton kübik; uç noktalar sabit).
  static Path _smooth(List<Offset> p) {
    final path = Path();
    if (p.isEmpty) return path;
    path.moveTo(p.first.dx, p.first.dy);
    if (p.length < 3) {
      for (final q in p.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      return path;
    }
    for (var i = 0; i < p.length - 1; i++) {
      final a = p[i];
      final b = p[i + 1];
      final dx = (b.dx - a.dx) / 3;
      // Komşu eğimlerin ortalaması; tepe ve diplerde düz (aşma yok), uçlarda tek yanlı eğim.
      double sec(int a, int b) => (p[b].dy - p[a].dy) / (p[b].dx - p[a].dx);
      double slope(int k) {
        if (k <= 0) return sec(0, 1);
        if (k >= p.length - 1) return sec(k - 1, k);
        final l = sec(k - 1, k);
        final r = sec(k, k + 1);
        if (l * r <= 0) return 0;
        return (l + r) / 2;
      }

      final sa = slope(i);
      final sb = slope(i + 1);
      path.cubicTo(
        a.dx + dx,
        a.dy + sa * dx,
        b.dx - dx,
        b.dy - sb * dx,
        b.dx,
        b.dy,
      );
    }
    return path;
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.progress != progress ||
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

  /// Deprecated: çizgi ve son nokta vurgu renginde (belirteçlerden).
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
