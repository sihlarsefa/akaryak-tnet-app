import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// Sayfa bölümü (tasarım v3 §3–4): sayfada yüzen beyaz kart — r22, yumuşak kart gölgesi (koyu
/// temada 1 px çizgi), 20 px sayfa kenarı. Kartın içinde başlık (`SectionHeader` 18/24 800) ve sağda
/// ya bir not ([caption], "son 12 ay") ya da bir gezinme ([actionLabel] + ›); altında içerik (satırlar
/// kartın kenarından 20 px içeride). İçerik kartta olduğunu bilir (`AknCardScope`): ayırıcılar
/// `lineSoft` olur, okumalar sakin kuyuya döner.
class StatsSection extends StatelessWidget {
  const StatsSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.caption,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? caption;
  final String? actionLabel;
  final VoidCallback? onAction;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => StatsCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionHeader(
          title: title,
          subtitle: subtitle,
          caption: caption,
          actionLabel: onAction == null ? null : actionLabel,
          onAction: onAction,
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
        ),
        ...children,
      ],
    ),
  );
}

/// İstatistik sayfasının kartı (tasarım v3 §3): beyaz (`surface`), r22, kart gölgesi; koyu temada
/// 1 px `line` kenar. İçerik kenara kadar uzanır (satırlar kendi 20 px boşluğunu verir) ve
/// `AknCardScope` ile kartta olduğunu bilir. [margin] varsayılanı sayfa kenarı 20, üstte 16.
class StatsCard extends StatelessWidget {
  const StatsCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(20, 16, 20, 0),
    this.padding = const EdgeInsets.only(bottom: 12),
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: AknRadius.section,
          border: c.isDark ? Border.all(color: c.line) : null,
          boxShadow: AknShadows.card(c),
        ),
        child: ClipRRect(
          borderRadius: AknRadius.section,
          child: AknCardScope(
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Defter satırı (kartın içinde): etiket solda, değer sağda (tabular; ilk görünüşte rakamları
/// sayaç gibi yerine oturur); isteğe bağlı soluk not ve ton.
///
/// Değer satırın 6/11'inden genişse (büyük yazı, dar kart) etiket harf harf sıkışmasın diye değer
/// etiketin altına, başa hizalı iner (çekirdek `FactRow` gibi); orada da sığmazsa bölünmeden
/// küçülür.
class StatsFactRow extends StatelessWidget {
  const StatsFactRow({
    super.key,
    required this.label,
    required this.value,
    this.note,
    this.tone,
  });

  final String label;
  final String value;
  final String? note;

  /// Sorunlu satır (gecikme): etiket ve değer ton renginde, kalın.
  final AknTone? tone;

  /// Etiket ile değer arası.
  static const double _gap = 12;

  /// Değer tek satırda [width] genişliğin 6/11'inden geniş mi (o zaman alt alta dizilir).
  bool _stacks(BuildContext context, TextStyle style, double width) {
    if (!width.isFinite) return false;
    final tp = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final valueWidth = tp.width;
    tp.dispose();
    return valueWidth > (width - _gap) * 6 / 11;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final tc = tone == null ? null : c.tone(tone!);
    final labelStyle = t.body.copyWith(
      color: tc?.fg ?? c.text,
      fontWeight: tone == null ? FontWeight.w400 : FontWeight.w600,
    );
    final valueStyle = t.bodyStrong.copyWith(
      fontWeight: FontWeight.w700,
      color: tc?.fg ?? c.ink,
      fontFeatures: AknNumerals.tabular,
    );
    final labelText = Text.rich(
      TextSpan(
        text: label,
        children: [
          if (note != null)
            TextSpan(
              text: '  $note',
              style: t.bodySmall.copyWith(color: c.dim),
            ),
        ],
      ),
      style: labelStyle,
    );
    final figure = RollingText(TextSpan(text: value, style: valueStyle));
    return Semantics(
      label: [label, value, ?note].join(', '),
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AknSpace.minTap),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: LayoutBuilder(
            builder: (context, box) {
              if (_stacks(context, valueStyle, box.maxWidth)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    labelText,
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: figure,
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(child: labelText),
                  const SizedBox(width: _gap),
                  figure,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Satırları kartın içinde 20 px içeriden `lineSoft` saç çizgisiyle ayırır (yalnızca satırlar
/// arasında; ilkinin üstünde ve sonuncunun altında çizgi yok).
class StatsDivided extends StatelessWidget {
  const StatsDivided({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const AknLedgerDivider(),
          children[i],
        ],
      ],
    );
  }
}

/// Oran satırı: "%92 zamanında ……… hedef %90" (yüzde 17/22 800 tabular, sayaç gibi döner; hedef
/// soluk).
class StatsRateLine extends StatelessWidget {
  const StatsRateLine({
    super.key,
    required this.rate,
    required this.label,
    this.trailing,
  });

  final String rate;
  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final style = t.body.copyWith(color: c.ink);
    return ExcludeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: RollingText(
              TextSpan(
                children: [
                  TextSpan(
                    text: rate,
                    style: t.amount.copyWith(
                      fontWeight: FontWeight.w800,
                      color: c.ink,
                    ),
                  ),
                  TextSpan(text: ' $label', style: style),
                ],
              ),
              maxLines: 3,
              softWrap: true,
            ),
          ),
          if (trailing != null)
            Text(trailing!, style: t.bodySmall.copyWith(color: c.dim)),
        ],
      ),
    );
  }
}

/// Büyük okuma: `numberLarge` rakam + birim ("42,34 ₺/L"); ilk görünüşte rakamlar sayaç gibi döner.
class StatsReadoutFigure extends StatelessWidget {
  const StatsReadoutFigure({super.key, required this.value, this.unit});

  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return RollingText(
      TextSpan(
        text: value,
        style: t.numberLarge.copyWith(color: c.ink),
        children: [
          if (unit != null)
            TextSpan(
              text: ' $unit',
              style: t.readoutUnit.copyWith(
                color: c.ink,
                fontSize: math.max(16, t.readoutUnit.fontSize ?? 16) + 2,
              ),
            ),
        ],
      ),
    );
  }
}

/// Büyüyen çubuk (tasarım v3 §5 "grafikler"): tam yuvarlak uçlu, [height] kalın; ilk görünüşte
/// başlangıç kenarından [fraction] oranına büyür ([delay] sonra, vurgulu eğri), değer değişince
/// yeni orana kayar. Dolgu [fillStart] → [fill] yatay degrade; [glow] ise altında aynı renkte yumuşak
/// bir ışıma. İsteğe bağlı iz ([trackColor], tam genişlik), iki seride ilk serinin boyu ([track],
/// [trackFill]) ve ince eşik çizgisi ([threshold], [tick]). Hareket azaltmada son hâli çizilir.
/// Süsleyicidir (satırı kelimeler taşır).
class StatsGrowBar extends StatefulWidget {
  const StatsGrowBar({
    super.key,
    required this.fraction,
    required this.fill,
    this.fillStart,
    this.trackColor,
    this.track = 1,
    this.trackFill,
    this.threshold,
    this.tick,
    this.height = 8,
    this.delay = Duration.zero,
    this.glow = false,
  });

  /// Dolu kısım (0–1, tam genişliğe göre).
  final double fraction;
  final Color fill;
  final Color? fillStart;

  /// Tam genişlikteki iz.
  final Color? trackColor;

  /// İki seri: ilk serinin boyu (0–1) ve rengi.
  final double track;
  final Color? trackFill;

  /// İnce eşik çizgisi (0–1) ve rengi.
  final double? threshold;
  final Color? tick;
  final double height;
  final Duration delay;
  final bool glow;

  @override
  State<StatsGrowBar> createState() => _StatsGrowBarState();
}

class _StatsGrowBarState extends State<StatsGrowBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _c,
    curve: AknMotion.emphasizedCurve,
  );
  Timer? _timer;
  bool _started = false;
  double _from = 0;
  double _fromTrack = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else if (widget.delay <= Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void didUpdateWidget(StatsGrowBar old) {
    super.didUpdateWidget(old);
    if (old.fraction == widget.fraction && old.track == widget.track) return;
    final v = _t.value;
    _from = _from + (old.fraction - _from) * v;
    _fromTrack = _fromTrack + (old.track - _fromTrack) * v;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else if (!(_timer?.isActive ?? false)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return SizedBox(
      height: w.height,
      width: double.infinity,
      child: CustomPaint(
        painter: _GrowBarPainter(
          progress: _t,
          from: _from,
          fromTrack: _fromTrack,
          fraction: w.fraction.isNaN ? 0 : w.fraction.clamp(0.0, 1.0),
          track: w.track.clamp(0.0, 1.0),
          fill: w.fill,
          fillStart: w.fillStart ?? w.fill,
          trackColor: w.trackColor,
          trackFill: w.trackFill,
          threshold: w.threshold,
          tick: w.tick,
          glow: w.glow,
          rtl: Directionality.of(context) == TextDirection.rtl,
        ),
      ),
    );
  }
}

class _GrowBarPainter extends CustomPainter {
  _GrowBarPainter({
    required this.progress,
    required this.from,
    required this.fromTrack,
    required this.fraction,
    required this.track,
    required this.fill,
    required this.fillStart,
    required this.trackColor,
    required this.trackFill,
    required this.threshold,
    required this.tick,
    required this.glow,
    required this.rtl,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final double from;
  final double fromTrack;
  final double fraction;
  final double track;
  final Color fill;
  final Color fillStart;
  final Color? trackColor;
  final Color? trackFill;
  final double? threshold;
  final Color? tick;
  final bool glow;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final r = Radius.circular(h / 2);
    final v = progress.value;
    RRect bar(double width) {
      final w = width.clamp(0.0, size.width);
      final left = rtl ? size.width - w : 0.0;
      return RRect.fromRectAndRadius(Rect.fromLTWH(left, 0, w, h), r);
    }

    final tc = trackColor;
    if (tc != null) {
      canvas.drawRRect(bar(size.width), Paint()..color = tc);
    }
    final first = trackFill;
    final tr = fromTrack + (track - fromTrack) * v;
    if (first != null && tr > 0) {
      final w = math.max(h, size.width * tr);
      canvas.drawRRect(bar(w), Paint()..color = first);
    }
    final f = from + (fraction - from) * v;
    if (f > 0) {
      final w = math.max(h, size.width * f);
      final rect = bar(w);
      if (glow) {
        canvas.drawRRect(
          rect.shift(const Offset(0, 2)),
          Paint()
            ..color = fill.withValues(alpha: 0.28)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
            end: rtl ? Alignment.centerLeft : Alignment.centerRight,
            colors: [fillStart, fill],
          ).createShader(rect.outerRect),
      );
    }
    final th = threshold;
    final mark = tick;
    if (th != null && mark != null) {
      final x0 = (size.width * th).clamp(1.0, size.width - 1);
      final x = rtl ? size.width - x0 : x0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x - 1, -4, x + 1, h + 4),
          const Radius.circular(1),
        ),
        Paint()..color = mark,
      );
    }
  }

  @override
  bool shouldRepaint(_GrowBarPainter old) =>
      old.progress != progress ||
      old.from != from ||
      old.fromTrack != fromTrack ||
      old.fraction != fraction ||
      old.track != track ||
      old.fill != fill ||
      old.fillStart != fillStart ||
      old.trackColor != trackColor ||
      old.trackFill != trackFill ||
      old.threshold != threshold ||
      old.tick != tick ||
      old.glow != glow ||
      old.rtl != rtl;
}

/// Vurgunun turuncu rampası (açıktan koyuya): plakada `heroStart` → `plateAccent` (koyu temada
/// `plateAccent` → logo turuncusu), beyaz sayfada vurgunun açık tonu → vurgu.
(Color, Color) statsAccentRamp(AknColors c) {
  if (c.isPlatePalette) {
    return c.isDark
        ? (c.chartHighlight, c.brand)
        : (c.heroStart, c.chartHighlight);
  }
  return (
    Color.lerp(c.chartHighlight, const Color(0xFFFFFFFF), 0.22)!,
    c.chartHighlight,
  );
}

/// Girişte solarak, [offset] px yükselerek ve [scale]'den büyüyerek belirir ([delay] sonra, bir
/// kez). `FadeUp` gibidir, ama hareket bitince ağacın yapısı değişmez: içindeki sayaçlar, büyüyen
/// çubuklar ve kendini çizen çizgiler baştan başlamaz. Hareket azaltmada hemen son hâli.
class StatsRise extends StatefulWidget {
  const StatsRise({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AknMotion.slow,
    this.offset = 12,
    this.scale = 1,
    this.curve = AknMotion.emphasizedCurve,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;
  final double scale;
  final Curve curve;

  @override
  State<StatsRise> createState() => _StatsRiseState();
}

class _StatsRiseState extends State<StatsRise>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _c,
    curve: widget.curve,
  );
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else if (widget.delay <= Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    child: widget.child,
    builder: (context, child) {
      final v = _t.value;
      final s = widget.scale + (1 - widget.scale) * v;
      // Yapı her karede aynı (Opacity → Transform): bitince çocuk yeniden kurulmaz.
      return Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.translationValues(0, widget.offset * (1 - v), 0)
            ..multiply(Matrix4.diagonal3Values(s, s, 1)),
          child: child,
        ),
      );
    },
  );
}

/// Liste öğesinin sırayla girişi ([StaggerItem]: ilk açılışta sırayla, sonra kaydırdıkça); öğe
/// sabit bir anahtarın altında durur ki giriş bitince durumu (sayaçlar, büyüyen çubuklar,
/// grafikler) korunsun.
class StatsStaggerItem extends StatefulWidget {
  const StatsStaggerItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<StatsStaggerItem> createState() => _StatsStaggerItemState();
}

class _StatsStaggerItemState extends State<StatsStaggerItem> {
  final GlobalKey _keep = GlobalKey();

  @override
  Widget build(BuildContext context) => StaggerItem(
    index: widget.index,
    child: KeyedSubtree(key: _keep, child: widget.child),
  );
}
