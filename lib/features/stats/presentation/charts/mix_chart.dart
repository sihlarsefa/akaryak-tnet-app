import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../data/stats_models.dart';
import '../stats_format.dart';
import '../widgets/stats_atoms.dart';
import '../widgets/stats_palette.dart';

/// Dağılımın bir dilimi.
@immutable
class MixSlice {
  const MixSlice({
    required this.label,
    required this.fraction,
    required this.color,
    this.liters = 0,
    this.amount = 0,
  });

  final String label;

  /// 0..1.
  final double fraction;
  final Color color;
  final double liters;
  final double amount;
}

/// Ürünlerden litre payına göre dilimler: en çok [max] ürün kendi adı ve rengiyle (en çok
/// [StatsPalette.size]), kalanı "Diğer". Tek ürün artıyorsa ve renk varsa o da adıyla gösterilir. Litre
/// toplamı yoksa sunucunun payı kullanılır. Renk ürüne bağlıdır ([StatsPalette.productColors]).
List<MixSlice> productSlices(
  AknColors c,
  List<StatsProduct> products, {
  int max = StatsPalette.size,
  String otherLabel = 'Diğer',
}) {
  if (products.isEmpty) return const [];
  final totalLiters = products.fold<double>(0, (s, p) => s + p.liters);
  final totalShare = products.fold<double>(0, (s, p) => s + p.share);
  double frac(StatsProduct p) => totalLiters > 0
      ? p.liters / totalLiters
      : (totalShare > 0 ? p.share / totalShare : 0);
  final sorted = [...products]..sort((a, b) => frac(b).compareTo(frac(a)));
  var n = max.clamp(1, StatsPalette.size);
  if (sorted.length == n + 1 && n < StatsPalette.size) n++;
  final head = sorted.take(n).toList();
  final tail = sorted.skip(n).toList();
  final colors = StatsPalette.productColors(c, head.map((p) => p.productId));
  final out = [
    for (final p in head)
      if (frac(p) > 0)
        MixSlice(
          label: p.name,
          fraction: frac(p),
          color: colors[p.productId]!,
          liters: p.liters,
          amount: p.amount,
        ),
  ];
  if (tail.isNotEmpty) {
    final f = tail.fold<double>(0, (s, p) => s + frac(p));
    if (f > 0) {
      out.add(
        MixSlice(
          label: otherLabel,
          fraction: f,
          color: StatsPalette.other(c),
          liters: tail.fold<double>(0, (s, p) => s + p.liters),
          amount: tail.fold<double>(0, (s, p) => s + p.amount),
        ),
      );
    }
  }
  return out;
}

/// Yatay yığılı dağılım çubuğu: dilimler arasında 2 px yüzey boşluğu, yuvarlak uçlar; soldan büyür.
class MixBar extends StatelessWidget {
  const MixBar({super.key, required this.slices, this.height = 12});

  final List<MixSlice> slices;
  final double height;

  @override
  Widget build(BuildContext context) {
    final reduced = AknMotion.reduced(context);
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: reduced ? 1 : 0, end: 1),
          duration: reduced ? Duration.zero : const Duration(milliseconds: 750),
          curve: Curves.easeOutCubic,
          builder: (context, p, _) => CustomPaint(
            painter: MixBarPainter(
              slices: slices,
              progress: p,
              track: context.akn.lineSoft,
            ),
          ),
        ),
      ),
    );
  }
}

class MixBarPainter extends CustomPainter {
  MixBarPainter({
    required this.slices,
    required this.progress,
    required this.track,
  });

  final List<MixSlice> slices;
  final double progress;
  final Color track;

  static const gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    final whole = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.drawRRect(whole, Paint()..color = track);
    if (slices.isEmpty) return;
    canvas.save();
    canvas.clipRRect(whole);
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
    final n = slices.length;
    final usable = math.max(0.0, size.width - gap * (n - 1));
    final total = slices.fold<double>(0, (s, x) => s + x.fraction);
    var x = 0.0;
    for (var i = 0; i < n; i++) {
      final w = total <= 0 ? 0.0 : usable * slices[i].fraction / total;
      if (w > 0) {
        canvas.drawRect(
          Rect.fromLTWH(x, 0, w, size.height),
          Paint()..color = slices[i].color,
        );
      }
      x += w + gap;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MixBarPainter old) =>
      old.progress != progress || old.slices != slices || old.track != track;
}

/// Gösterge satırı. Kartta ([dense]) tek satır: renk noktası · ad · pay · litre; sayfada ad ve litre alt
/// alta, pay sağda. Sayılar sığmazsa küçülür, ad kısalır (taşma yok).
class MixLegendRow extends StatelessWidget {
  const MixLegendRow({
    super.key,
    required this.slice,
    this.detail,
    this.dense = true,
  });

  final MixSlice slice;

  /// Payın yanında küçük açıklama ("120.000 L").
  final String? detail;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final pct = StatsFmt.rate(slice.fraction);
    const numbers = [FontFeature.tabularFigures()];
    final name = Text(
      slice.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (dense ? t.caption : t.label).copyWith(
        color: c.ink,
        fontWeight: FontWeight.w600,
      ),
    );
    final share = Text(
      pct,
      style: (dense ? t.caption : t.label).copyWith(
        color: c.ink,
        fontWeight: FontWeight.w800,
        fontFeatures: numbers,
      ),
    );
    final note = detail == null
        ? null
        : Text(
            detail!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.caption.copyWith(color: c.dim, fontFeatures: numbers),
          );
    return Semantics(
      label: '${slice.label} $pct${detail == null ? '' : ', $detail'}',
      excludeSemantics: true,
      child: StatsLineRow(
        crossAxisAlignment: dense
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        leading: Padding(
          padding: EdgeInsetsDirectional.only(end: 8, top: dense ? 0 : 4),
          child: Container(
            width: dense ? 9 : 11,
            height: dense ? 9 : 11,
            decoration: BoxDecoration(
              color: slice.color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        title: dense || note == null
            ? name
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [name, note],
              ),
        trailing: dense && note != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [share, const SizedBox(width: 8), note],
              )
            : share,
      ),
    );
  }
}

/// Halka grafik (ürün dağılımı): dilimler sırayla dolar (900 ms), aralarında 2 px yüzey boşluğu;
/// ortada toplam. Hareket azaltmada doğrudan tam çizilir.
class StatsDonut extends StatelessWidget {
  const StatsDonut({
    super.key,
    required this.slices,
    required this.centerValue,
    required this.centerLabel,
    this.size = 148,
    this.stroke = 20,
    this.semanticsLabel,
  });

  final List<MixSlice> slices;
  final String centerValue;
  final String centerLabel;
  final double size;
  final double stroke;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final reduced = AknMotion.reduced(context);
    return Semantics(
      label:
          semanticsLabel ??
          [
            for (final s in slices) '${s.label} ${StatsFmt.rate(s.fraction)}',
          ].join(', '),
      image: true,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: reduced ? 1 : 0, end: 1),
          duration: reduced ? Duration.zero : const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, p, child) => CustomPaint(
            painter: DonutPainter(
              slices: slices,
              progress: p,
              stroke: stroke,
              track: c.lineSoft,
            ),
            child: child,
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(stroke + 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      centerValue,
                      maxLines: 1,
                      style: t.headline.copyWith(
                        fontWeight: FontWeight.w800,
                        color: c.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Text(
                    centerLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.caption.copyWith(color: c.dim),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DonutPainter extends CustomPainter {
  DonutPainter({
    required this.slices,
    required this.progress,
    required this.stroke,
    required this.track,
  });

  final List<MixSlice> slices;
  final double progress;
  final double stroke;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.shortestSide - stroke) / 2;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(center, radius, base);
    final total = slices.fold<double>(0, (s, x) => s + x.fraction);
    if (total <= 0) return;
    final n = slices.where((s) => s.fraction > 0).length;
    // 2 px yüzey boşluğu (yay uzunluğu → açı); tek dilimde boşluk yok.
    final gap = n > 1 ? 2 / radius : 0.0;
    final sweepTotal = 2 * math.pi * progress;
    var start = -math.pi / 2;
    var drawn = 0.0;
    for (final s in slices) {
      if (s.fraction <= 0) continue;
      final full = 2 * math.pi * s.fraction / total;
      final remaining = sweepTotal - drawn;
      if (remaining <= 0) break;
      final sweep = math.min(full, remaining);
      final visible = sweep - gap;
      if (visible > 0) {
        canvas.drawArc(
          rect,
          start + gap / 2,
          visible,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.butt
            ..color = s.color,
        );
      }
      start += full;
      drawn += full;
    }
  }

  @override
  bool shouldRepaint(DonutPainter old) =>
      old.progress != progress ||
      old.slices != slices ||
      old.stroke != stroke ||
      old.track != track;
}
