import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

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

/// Aylık sütun grafiği (F2GO `_MiniCubukGrafik` uyarlaması). Seçili sütun (varsayılan son ay) kartın
/// renginde ve üstünde değeri yazar; diğerleri %38 saydam. Sütunlar sırayla büyür (500 + i·70 ms,
/// easeOutCubic); dokunulan sütun seçilir. Veri yoksa yer tutucu sütunlar ve ortada kısa not.
/// Her sütun ekran okuyucuya "Ekim 2026 satış 21,5 milyon lira" der.
///
/// [axis] açıkken (istatistik sayfası) üç ince yatay kılavuz çizgisi ve solda kısa eksen değerleri.
class StatsBarChart extends StatefulWidget {
  const StatsBarChart({
    super.key,
    required this.bars,
    required this.color,
    required this.valueLabel,
    required this.spoken,
    required this.emptyHint,
    this.axis = false,
    this.axisLabel,
    this.onSelected,
    this.maxBarWidth = 24,
  });

  final List<ChartBar> bars;
  final Color color;

  /// Seçili sütunun üstündeki kısa değer ("21,5 Mn ₺").
  final String Function(double value) valueLabel;

  /// Ekran okuyucu metni.
  final String Function(ChartBar bar) spoken;
  final String emptyHint;
  final bool axis;

  /// Eksen değerleri ("10 Mn"); null ise [valueLabel].
  final String Function(double value)? axisLabel;

  /// Seçim değişince (sayfa altındaki ayrıntı satırı).
  final ValueChanged<int>? onSelected;
  final double maxBarWidth;

  @override
  State<StatsBarChart> createState() => _StatsBarChartState();
}

class _StatsBarChartState extends State<StatsBarChart> {
  int? _selected;

  @override
  void didUpdateWidget(StatsBarChart old) {
    super.didUpdateWidget(old);
    if (old.bars.length != widget.bars.length) _selected = null;
  }

  void _select(int i) {
    if (_selected == i) return;
    AknHaptics.selection();
    setState(() => _selected = i);
    widget.onSelected?.call(i);
  }

  /// Kılavuz çizgileri: üst sınırın yarısı ve kendisi (yuvarlak değerler: 10 / 20 Mn).
  static const _ticks = [0.5, 1.0];

  /// Eksen üst sınırı: değeri kapsayan yuvarlak sayı (1, 2, 2,5, 5, 10 × 10^n).
  static double _niceMax(double value) {
    if (value <= 0) return 1;
    final exp = (math.log(value) / math.ln10).floor();
    final pow = math.pow(10, exp).toDouble();
    for (final step in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
      if (step * pow >= value) return step * pow;
    }
    return 10 * pow;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final bars = widget.bars;
    if (bars.isEmpty) return const SizedBox.shrink();
    final dataMax = bars.fold<double>(0, (m, b) => math.max(m, b.value));
    final empty = dataMax <= 0;
    final top = widget.axis && !empty ? _niceMax(dataMax) : dataMax;
    final selected = (_selected ?? bars.length - 1).clamp(0, bars.length - 1);
    final scaler = MediaQuery.textScalerOf(context);
    final labelH = scaler.scale(11.5) * 1.35 + 2;
    final monthH = scaler.scale(11) * 1.4 + 4;
    final reduced = AknMotion.reduced(context);
    final axisFmt = widget.axisLabel ?? widget.valueLabel;
    final axisStyle = t.caption.copyWith(
      fontSize: 11,
      color: c.dim,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // Eksen sütunu en geniş etiket kadar (yarım ve tam değer).
    var axisW = 0.0;
    if (widget.axis && !empty) {
      for (final f in _ticks) {
        final tp = TextPainter(
          text: TextSpan(text: axisFmt(top * f), style: axisStyle),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        axisW = math.max(axisW, tp.width + 8);
        tp.dispose();
      }
    }

    return LayoutBuilder(
      builder: (context, cons) {
        final barArea = math.max(12.0, cons.maxHeight - labelH - monthH);
        final plotW = math.max(0.0, cons.maxWidth - axisW);
        final slot = plotW / bars.length;
        final barW = math.min(widget.maxBarWidth, slot * 0.52);
        final baseline = labelH + barArea;

        return Stack(
          children: [
            // Kılavuz çizgiler (sayfa) ve taban çizgisi.
            if (widget.axis && !empty)
              for (final f in _ticks)
                Positioned(
                  left: axisW,
                  right: 0,
                  top: baseline - barArea * f,
                  child: Container(height: 1, color: c.lineSoft),
                ),
            if (widget.axis && !empty)
              for (final f in _ticks)
                Positioned(
                  left: 0,
                  width: axisW - 6,
                  top: baseline - barArea * f - scaler.scale(11) * 0.7,
                  child: ExcludeSemantics(
                    child: Text(
                      axisFmt(top * f),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: axisStyle,
                    ),
                  ),
                ),
            Positioned(
              left: axisW,
              right: 0,
              top: baseline,
              child: Container(height: 1, color: c.line),
            ),
            Padding(
              padding: EdgeInsetsDirectional.only(start: axisW),
              child: Row(
                children: [
                  for (var i = 0; i < bars.length; i++)
                    Expanded(
                      child: Semantics(
                        label: widget.spoken(bars[i]),
                        button: !empty,
                        selected: !empty && i == selected,
                        onTap: empty ? null : () => _select(i),
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          excludeFromSemantics: true,
                          onTap: empty ? null : () => _select(i),
                          child: Column(
                            children: [
                              SizedBox(
                                height: baseline,
                                child: TweenAnimationBuilder<double>(
                                  key: ValueKey('grow-$empty-${bars.length}'),
                                  tween: Tween<double>(
                                    begin: reduced ? 1 : 0,
                                    end: 1,
                                  ),
                                  duration: reduced
                                      ? Duration.zero
                                      : Duration(milliseconds: 500 + i * 70),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, g, _) {
                                    final ratio = empty
                                        ? 0.12 + 0.06 * (i % 3)
                                        : bars[i].value / (top <= 0 ? 1 : top);
                                    final minH = empty || bars[i].value > 0
                                        ? 3.0
                                        : 2.0;
                                    final h = math.max(
                                      minH,
                                      barArea * ratio.clamp(0.0, 1.0) * g,
                                    );
                                    final isSel = !empty && i == selected;
                                    return Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        if (isSel)
                                          SizedBox(
                                            height: labelH,
                                            width: slot,
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                widget.valueLabel(
                                                  bars[i].value,
                                                ),
                                                maxLines: 1,
                                                style: t.captionStrong.copyWith(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: c.ink,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        _Bar(
                                          width: barW,
                                          height: h,
                                          color: empty
                                              ? c.line
                                              : isSel
                                              ? widget.color
                                              : widget.color.withValues(
                                                  alpha: 0.38,
                                                ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                              SizedBox(
                                height: monthH,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Text(
                                    bars[i].label,
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: t.caption.copyWith(
                                      fontSize: 11,
                                      color: !empty && i == selected
                                          ? c.ink
                                          : c.dim,
                                      fontWeight: !empty && i == selected
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (empty)
              Positioned.fill(
                bottom: monthH,
                left: axisW,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: c.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.emptyHint,
                      textAlign: TextAlign.center,
                      style: t.caption.copyWith(
                        color: c.dim,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Tek sütun: 4 px yuvarlak üst uç, tabanda köşesiz; renk değişimi 200 ms geçişle.
class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height, required this.color});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: AknMotion.of(context, const Duration(milliseconds: 200)),
      builder: (context, col, _) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: col ?? color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ),
    );
  }
}
