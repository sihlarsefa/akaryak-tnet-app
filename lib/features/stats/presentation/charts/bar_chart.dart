import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../copy.dart';

/// Bir sütun: kısa etiket ("Eki"), uzun ad ("Ekim 2026") ve değer.
@immutable
class ChartBar {
  const ChartBar({
    required this.label,
    required this.longLabel,
    required this.value,
  });

  final String label;
  final String longLabel;
  final double value;
}

/// Aylık sütun grafiği (tasarım v2 §6.20; beyaz sayfa). Tek seri, vurgu biçimi: geçmiş aylar
/// `chartContext`, bu ay `chartHighlight`. Sütunlar ≤ 16 geniş (12 ayda 12), üstte 4 px yuvarlak,
/// 1 px taban çizgisinde köşesiz; kılavuz çizgisi ve eksen sayısı yok. Doğrudan etiket yalnızca bu
/// aya ("bu ay" + "8,43 mn", sütunun sağında) ve en yüksek aya ("13,1", üstünde); diğerleri dokununca
/// küçük ters baloncukta (2 sn). Ay sonu tahmini 1,5 px kesikli mürekkep çerçeve. Her sütun ekran
/// okuyucuya "Ekim 2026 satış 8,43 milyon lira" der ve dokunulabilir.
class StatsBarChart extends StatefulWidget {
  const StatsBarChart({
    super.key,
    required this.bars,
    required this.valueLabel,
    required this.spoken,
    required this.emptyHint,
    this.color,
    this.axis = false,
    this.axisLabel,
    this.onSelected,
    this.maxBarWidth = 16,
    this.currentIndex,
    this.projection,
    this.projectionLabel,
    this.extremeLabel,
    this.bubbleLabel,
    this.currentCaption = StatsCopy.thisMonth,
    this.barAreaHeight = 112,
  });

  final List<ChartBar> bars;

  /// Bu ayın yanındaki kısa değer ("8,43 mn").
  final String Function(double value) valueLabel;

  /// Ekran okuyucu metni.
  final String Function(ChartBar bar) spoken;
  final String emptyHint;

  /// Deprecated: tek seri vurgu biçiminde renk belirteçlerden gelir.
  final Color? color;

  /// Deprecated: eksen ve kılavuz çizgisi yok.
  final bool axis;

  /// Deprecated: eksen yok.
  final String Function(double value)? axisLabel;

  /// Dokunulan sütun.
  final ValueChanged<int>? onSelected;
  final double maxBarWidth;

  /// Vurgulanan (bu ay) sütun; varsayılan son.
  final int? currentIndex;

  /// Bu ayın ay sonu tahmini (kesikli çerçeve).
  final double? projection;

  /// Tahminin kısa etiketi ("12,4"); null ise [valueLabel].
  final String Function(double value)? projectionLabel;

  /// En yüksek ayın etiketi ("13,1"); null ise [valueLabel].
  final String Function(double value)? extremeLabel;

  /// Dokununca baloncuk metni; null ise "Eylül 2026: 11,9 mn".
  final String Function(ChartBar bar)? bubbleLabel;
  final String currentCaption;

  /// Sütun alanının yüksekliği (112).
  final double barAreaHeight;

  @override
  State<StatsBarChart> createState() => _StatsBarChartState();
}

class _StatsBarChartState extends State<StatsBarChart> {
  int? _bubble;
  Timer? _timer;

  @override
  void didUpdateWidget(StatsBarChart old) {
    super.didUpdateWidget(old);
    if (old.bars.length != widget.bars.length) _bubble = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _select(int i) {
    AknHaptics.selection();
    setState(() => _bubble = i);
    widget.onSelected?.call(i);
    _timer?.cancel();
    _timer = Timer(AknMotion.bubbleHold, () {
      if (mounted) setState(() => _bubble = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final bars = widget.bars;
    if (bars.isEmpty) return const SizedBox.shrink();
    final n = bars.length;
    final current = (widget.currentIndex ?? n - 1).clamp(0, n - 1);
    final dataMax = bars.fold<double>(0, (m, b) => math.max(m, b.value));
    final empty = dataMax <= 0;
    final proj = empty ? null : widget.projection;
    final top = math.max(dataMax, proj ?? 0);
    final scaler = MediaQuery.textScalerOf(context);
    final small = t.caption.copyWith(
      fontSize: 11,
      height: 14 / 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
      color: c.dim,
    );
    final strong = t.label.copyWith(
      fontSize: 13,
      height: 16 / 13,
      fontWeight: FontWeight.w700,
      color: c.ink,
    );
    final month = t.caption.copyWith(
      fontSize: 12,
      height: 16 / 12,
      letterSpacing: 0,
    );
    double measure(String s, TextStyle st) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: st),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = tp.width;
      tp.dispose();
      return w;
    }

    final cur = bars[current];
    final curValue = empty ? null : widget.valueLabel(cur.value);
    final projText = proj == null || proj <= cur.value
        ? null
        : (widget.projectionLabel ?? widget.valueLabel)(proj);
    final rightW = empty
        ? 0.0
        : [
                measure(widget.currentCaption, small),
                measure(curValue!, strong),
                if (projText != null) measure(projText, small),
              ].reduce(math.max) +
              10;
    // En yüksek geçmiş ay (bu ay değil).
    var extreme = -1;
    for (var i = 0; i < n; i++) {
      if (i == current || bars[i].value <= 0) continue;
      if (extreme < 0 || bars[i].value > bars[extreme].value) extreme = i;
    }
    final smallH = scaler.scale(11) * 14 / 11;
    final monthH = scaler.scale(12) * 16 / 12;
    final topPad = smallH + 6;
    final area = widget.barAreaHeight;
    var labelW = 0.0;
    for (final b in bars) {
      labelW = math.max(labelW, measure(b.label, month));
    }

    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth;
        final plotW = math.max(0.0, w - rightW);
        final step = plotW / n;
        final barW = math.min(
          n > 6 ? math.min(12.0, widget.maxBarWidth) : widget.maxBarWidth,
          step * 0.62,
        );
        double cx(int i) => step * i + step / 2;
        double y(double v) =>
            topPad + area - (top <= 0 ? 0 : v.clamp(0, top) / top * area);
        final baseline = topPad + area;
        // Ay adları çakışmasın: sığana kadar her k. ay (bu ay hep yazılır; 12 ayda en az 2'de bir).
        var showEvery = n > 6 ? 2 : 1;
        while (showEvery < n && step * showEvery < labelW + 6) {
          showEvery++;
        }
        // "bu ay" + değer, tahmin etiketinin altında kalır (büyük yazıda üst üste binmez).
        final captionH = smallH + scaler.scale(13) * 16 / 13;
        var captionTop = empty
            ? 0.0
            : math.min(y(cur.value) - smallH, baseline - captionH);
        final projTop = proj == null ? null : y(proj) - smallH / 2;
        if (projText != null && projTop != null) {
          captionTop = math.max(captionTop, projTop + smallH + 2);
        }
        final boxH = math.max(baseline + 4 + monthH, captionTop + captionH);
        final bubble = _bubble;
        return SizedBox(
          height: boxH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _BarsPainter(
                    values: [for (final b in bars) b.value],
                    current: current,
                    selected: bubble,
                    projection: projText == null ? null : proj,
                    top: top,
                    topPad: topPad,
                    area: area,
                    plotW: plotW,
                    barW: barW,
                    empty: empty,
                    contextColor: c.chartContext,
                    highlight: c.chartHighlight,
                    track: c.chartTrack,
                    outline: c.ink,
                    baseline: c.line,
                  ),
                ),
              ),
              if (!empty && extreme >= 0)
                Positioned(
                  left: cx(extreme) - 40,
                  width: 80,
                  top: y(bars[extreme].value) - smallH - 4,
                  child: ExcludeSemantics(
                    child: Text(
                      (widget.extremeLabel ?? widget.valueLabel)(
                        bars[extreme].value,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: small,
                    ),
                  ),
                ),
              if (!empty) ...[
                Positioned(
                  left: cx(current) + barW / 2 + 8,
                  top: captionTop,
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.currentCaption, style: small, maxLines: 1),
                        Text(curValue!, style: strong, maxLines: 1),
                      ],
                    ),
                  ),
                ),
                if (projText != null)
                  Positioned(
                    left: cx(current) + barW / 2 + 8,
                    top: projTop,
                    child: ExcludeSemantics(
                      child: Text(projText, style: small, maxLines: 1),
                    ),
                  ),
              ],
              for (var i = 0; i < n; i++)
                if (i == current || (n - 1 - i) % showEvery == 0)
                  Positioned(
                    left: cx(i) - 28,
                    width: 56,
                    top: baseline + 4,
                    child: ExcludeSemantics(
                      child: Text(
                        bars[i].label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: i == current && !empty
                            ? month.copyWith(
                                color: c.ink,
                                fontWeight: FontWeight.w700,
                              )
                            : month.copyWith(color: c.dim),
                      ),
                    ),
                  ),
              // Bir sütun bir hedef (dokun → baloncuk), bir ekran okuyucu düğümü.
              for (var i = 0; i < n; i++)
                Positioned(
                  left: step * i,
                  width: step,
                  top: 0,
                  height: baseline + 4 + monthH,
                  child: Semantics(
                    label: widget.spoken(bars[i]),
                    button: !empty,
                    onTap: empty ? null : () => _select(i),
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true,
                      onTap: empty ? null : () => _select(i),
                    ),
                  ),
                ),
              if (empty)
                Positioned(
                  left: 0,
                  right: 0,
                  top: topPad,
                  height: area,
                  child: Center(
                    child: Text(
                      widget.emptyHint,
                      textAlign: TextAlign.center,
                      style: t.bodySmall.copyWith(color: c.dim),
                    ),
                  ),
                ),
              if (bubble != null && !empty && bubble < n)
                _Bubble(
                  centerX: cx(bubble),
                  bottom: y(bars[bubble].value) - 6,
                  maxWidth: w,
                  text:
                      widget.bubbleLabel?.call(bars[bubble]) ??
                      '${bars[bubble].longLabel}: '
                          '${widget.valueLabel(bars[bubble].value)}',
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.current,
    required this.selected,
    required this.projection,
    required this.top,
    required this.topPad,
    required this.area,
    required this.plotW,
    required this.barW,
    required this.empty,
    required this.contextColor,
    required this.highlight,
    required this.track,
    required this.outline,
    required this.baseline,
  });

  final List<double> values;
  final int current;
  final int? selected;
  final double? projection;
  final double top;
  final double topPad;
  final double area;
  final double plotW;
  final double barW;
  final bool empty;
  final Color contextColor;
  final Color highlight;
  final Color track;
  final Color outline;
  final Color baseline;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final step = plotW / n;
    final base = topPad + area;
    canvas.drawRect(
      Rect.fromLTWH(0, base, plotW, 1),
      Paint()..color = baseline,
    );
    for (var i = 0; i < n; i++) {
      final h = empty
          ? area * (0.14 + 0.06 * (i % 3))
          : (top <= 0 ? 0.0 : values[i].clamp(0, top) / top * area);
      if (h <= 0) continue;
      final cx = step * i + step / 2;
      final r = math.min(4.0, h);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(cx - barW / 2, base - h, barW, h),
          topLeft: Radius.circular(r),
          topRight: Radius.circular(r),
        ),
        Paint()
          ..color = empty
              ? track
              : i == current || i == selected
              ? highlight
              : contextColor,
      );
    }
    final p = projection;
    if (p != null && !empty && top > 0) {
      final cx = step * current + step / 2;
      final mtd = values[current].clamp(0, top) / top * area;
      final pt = base - p.clamp(0, top) / top * area;
      final bottom = base - mtd;
      if (bottom - pt > 1) {
        final l = cx - barW / 2 + 0.75;
        final r = cx + barW / 2 - 0.75;
        const rad = 4.0;
        final path = Path()
          ..moveTo(l, bottom)
          ..lineTo(l, pt + rad)
          ..quadraticBezierTo(l, pt, l + rad, pt)
          ..lineTo(r - rad, pt)
          ..quadraticBezierTo(r, pt, r, pt + rad)
          ..lineTo(r, bottom);
        drawDashedPath(canvas, path, outline, width: 1.5, on: 3, off: 2.5);
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values ||
      old.current != current ||
      old.selected != selected ||
      old.projection != projection ||
      old.top != top ||
      old.plotW != plotW ||
      old.barW != barW ||
      old.empty != empty ||
      old.contextColor != contextColor ||
      old.highlight != highlight ||
      old.outline != outline;
}

/// [path]'i kesikli çizer ([on] / [off] px).
void drawDashedPath(
  Canvas canvas,
  Path path,
  Color color, {
  double width = 1.5,
  double on = 3,
  double off = 2.5,
}) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width;
  for (final metric in path.computeMetrics()) {
    var d = 0.0;
    while (d < metric.length) {
      final next = math.min(d + on, metric.length);
      canvas.drawPath(metric.extractPath(d, next), paint);
      d += on + off;
    }
  }
}

/// Grafik altındaki lejantın 10 px kesikli karesi (ay sonu tahmini).
class ChartDashedSwatch extends StatelessWidget {
  const ChartDashedSwatch({super.key, this.size = 10});

  final double size;

  @override
  Widget build(BuildContext context) {
    final s =
        size * math.min(MediaQuery.textScalerOf(context).scale(10) / 10, 1.6);
    return CustomPaint(
      size: Size.square(s),
      painter: _SwatchPainter(context.akn.ink),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.75),
      const Radius.circular(2),
    );
    drawDashedPath(canvas, Path()..addRRect(r), color, on: 2.2, off: 1.6);
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.color != color;
}

/// Dokunulan sütunun üstündeki küçük ters baloncuk.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.centerX,
    required this.bottom,
    required this.text,
    required this.maxWidth,
  });

  final double centerX;
  final double bottom;
  final String text;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final style = t.captionStrong.copyWith(
      color: c.onInverse,
      letterSpacing: 0,
    );
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = tp.width + 16;
    final h = tp.height + 8;
    tp.dispose();
    final left = (centerX - w / 2)
        .clamp(0.0, math.max(0.0, maxWidth - w))
        .toDouble();
    return Positioned(
      left: left,
      top: math.max(0.0, bottom - h),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: c.inverse,
            borderRadius: AknRadius.tag,
          ),
          child: Text(text, style: style, maxLines: 1, softWrap: false),
        ),
      ),
    );
  }
}
