import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../copy.dart';

/// Bir plaka okuması (§7.11): etiket (sürücü kipinde 15/20 600 soluk) üstte, değer pompa göstergesi
/// gibi Archivo 800 tablo rakamları (sürücü kipinde 28/32) ve küçük birimi ("km", "L")
/// aynı satırda.
@immutable
class StopReadout {
  const StopReadout({
    required this.label,
    required this.value,
    this.unit,
    this.semanticLabel,
    this.caption,
  });

  /// "Varış planı", "Uzaklık", "Tank kapasitesi".
  final String label;

  /// "09:00", "18", "08:00–18:00".
  final String value;

  /// "km", "L" (değerden sonra, daha küçük).
  final String? unit;

  /// Ekran okuyucu metni (varsayılan "etiket: değer birim, alt satır").
  final String? semanticLabel;

  /// Değerin altındaki kısa satır (v4 §5 11): "teslim aralığı 08:00–18:00" (13/18 soluk, en çok 2
  /// satır; sütun genişliğine katılmaz).
  final String? caption;

  String get spoken =>
      semanticLabel ??
      ['$label: $value${unit == null ? '' : ' $unit'}', ?caption].join(', ');
}

/// Durak plakasının okumaları (tasarım v3 §4–5): sığdıkça tek satırda sütunlar (her sütun en az
/// içeriği kadar, kalan yer eşit paylaşılır); sığmazsa iki uca yaslı sarılır. Büyük yazıda (≥ 1,6×)
/// etiket solda, değer sağda satırlar olur. Değerler sayaç gibi yuvarlanarak yerine oturur (ilk
/// çizimde sütun sütun, değer değişince eski rakamdan yenisine: uzaklık azaldıkça, fark
/// değiştikçe). Değer hiçbir zaman sayının ortasından bölünmez.
class StopReadouts extends StatelessWidget {
  const StopReadouts({super.key, required this.items});

  final List<StopReadout> items;

  /// Okuma [i] ne zaman yuvarlanmaya başlar (kart yükselirken).
  static Duration _delay(int i) => Duration(milliseconds: 240 + 90 * i);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final c = context.akn;
    final t = context.aknText;
    final labelStyle = t.label.copyWith(
      color: c.dim,
      fontWeight: FontWeight.w600,
    );
    final valueStyle = t.number.copyWith(color: c.ink);
    final unitStyle = t.readoutUnit.copyWith(color: c.ink);
    final captionStyle = t.label.copyWith(
      fontWeight: FontWeight.w500,
      color: c.dim,
      fontFeatures: AknNumerals.tabular,
    );
    InlineSpan value(StopReadout r) => TextSpan(
      text: r.value,
      style: valueStyle,
      children: [
        if (r.unit != null && r.unit!.isNotEmpty)
          TextSpan(text: ' ${r.unit}', style: unitStyle),
      ],
    );
    final scaler = MediaQuery.textScalerOf(context);
    final large = scaler.scale(10) >= 16;
    if (large) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++)
            Semantics(
              label: items[i].spoken,
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: i == 0
                    ? null
                    : BoxDecoration(
                        border: Border(top: BorderSide(color: c.lineSoft)),
                      ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(items[i].label, style: labelStyle),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerEnd,
                              child: MediaQuery.withClampedTextScaling(
                                maxScaleFactor: 1.6,
                                child: RollingText(
                                  value(items[i]),
                                  delay: _delay(i),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (items[i].caption case final String caption)
                      Text(caption, style: captionStyle),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 16.0;
        double measure(InlineSpan span) {
          final tp = TextPainter(
            text: span,
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final w = tp.width;
          tp.dispose();
          return w.ceilToDouble();
        }

        final room = box.maxWidth - gap * (items.length - 1);
        List<double> widths({required bool captions}) => [
          for (final r in items)
            [
              measure(TextSpan(text: r.label, style: labelStyle)),
              measure(value(r)),
              if (captions && r.caption != null)
                measure(TextSpan(text: r.caption, style: captionStyle)),
            ].reduce(math.max),
        ];
        // Alt satırlar sığıyorsa tek satırda kalır; sığmıyorsa sütun genişliğine katılmaz, sarılır.
        var mins = widths(captions: true);
        if (mins.fold<double>(0, (a, b) => a + b) > room) {
          mins = widths(captions: false);
        }
        final need = mins.fold<double>(0, (a, b) => a + b);
        // Sığarsa tek satırda sütunlar (her biri en az içeriği kadar, artan yer eşit paylaşılır);
        // sığmazsa iki uca yaslı sarılır. Ağaç her iki düzende de aynıdır: değerler yalnızca kendi
        // rakamları değişince döner (yazarken "Planlanan" yeniden dönmez).
        final columns = need <= room;
        final extra = columns ? (room - need) / items.length : 0.0;
        return Wrap(
          alignment: columns ? WrapAlignment.start : WrapAlignment.spaceBetween,
          spacing: columns ? gap : 20,
          runSpacing: 12,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: columns
                    ? (mins[i] + extra).floorToDouble()
                    : (mins[i] > box.maxWidth ? box.maxWidth : null),
                child: Semantics(
                  label: items[i].spoken,
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(items[i].label, style: labelStyle, maxLines: 2),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: RollingText(value(items[i]), delay: _delay(i)),
                      ),
                      if (items[i].caption case final String caption) ...[
                        const SizedBox(height: 2),
                        Text(caption, style: captionStyle, maxLines: 2),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Şoförün durak plakası (tasarım v3 §4 kahraman kart, §7.11): ekranın tek plakası — beyaz kart,
/// üstte sıcak yıkama, r26, sıcak gölge. Başta tankerin ADR levhası ("30 / 1202") ve "Motorin, bu
/// durakta"; altında bu durağın litresi (sürücü kipinde 56/60, sayaç gibi yuvarlanır, uzun sayı
/// sığmazsa küçülür), isteğe bağlı güzergâh çizgisi ([chart]), çizgi ve okumalar (Plan, Uzaklık,
/// Teslim saati). Durum rengi plakaya girmez.
///
/// [header] verilirse (ana sayfadaki sıradaki durak: sıra, yük çubuğu, müşteri ve adres) aynı
/// kartın üstünde, ince çizgiyle ayrılarak durur ve kendi ekran okuyucu düğümünü korur. [onTap]
/// verilirse kartın tamamı basılınca hafifçe küçülür ve ayrıntıyı açar (ekran okuyucu bu eylemi
/// başlıkta bulur).
///
/// Teslim sihirbazında aynı plaka sayaç okumasını canlı gösterir ([title] "Sayaç okuması",
/// [liveRegion]): her tuşta rakamlar eski değerden yenisine döner.
class DriverStopPlate extends StatelessWidget {
  const DriverStopPlate({
    super.key,
    required this.product,
    required this.figure,
    this.title,
    this.unit = 'L',
    this.readouts = const [],
    this.margin,
    this.semanticLabel,
    this.liveRegion = false,
    this.header,
    this.chart,
    this.onTap,
    this.notice,
  });

  /// Ürün adı ("Motorin"): ADR kodlarını ve varsayılan başlığı belirler.
  final String? product;

  /// Biçimli litre ("10.000", "9.950,5").
  final String figure;

  /// Varsayılan "Motorin, bu durakta".
  final String? title;
  final String unit;
  final List<StopReadout> readouts;
  final EdgeInsetsGeometry? margin;

  /// Ekran okuyucu metni (varsayılan: başlık, litre ve okumalar).
  final String? semanticLabel;

  /// Değer değiştikçe okunur (sayaç girişi).
  final bool liveRegion;

  /// Kartın üstündeki içerik (sıradaki durağın kimliği); kendi anlamsal düğümüyle.
  final Widget? header;

  /// Litrenin altındaki grafik (güzergâh çizgisi, `TruckRoute`).
  final Widget? chart;

  /// Kartın tamamı dokunulabilir (basınca küçülür, seçim titreşimi).
  final VoidCallback? onTap;

  /// Kartın en üstündeki tek satırlık uyarı (v4 §5 11: itirazlı teslimat), ince çizgiyle ayrılır;
  /// kendi dokunma alanı ve anlamsal düğümüyle.
  final Widget? notice;

  @override
  Widget build(BuildContext context) {
    final heading = title ?? DriverCopy.onThisStop(product);
    final spoken =
        semanticLabel ??
        [
          heading,
          '$figure ${unit == 'L' ? 'litre' : unit}',
          for (final r in readouts) r.spoken,
        ].join(', ');
    final adr = AdrPlate.forProduct(product);
    final head = Builder(
      builder: (context) {
        final c = context.akn;
        final t = context.aknText;
        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.6,
          child: Row(
            children: [
              adr ??
                  SizedBox.square(
                    dimension: 40,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: c.plateIconFill,
                        shape: const RoundedSuperellipseBorder(
                          borderRadius: BorderRadius.all(
                            Radius.circular(AknRadius.sm),
                          ),
                        ),
                      ),
                      child: Icon(
                        PhosphorIconsRegular.gasPump,
                        size: 22,
                        color: c.plateAccent,
                      ),
                    ),
                  ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  heading,
                  style: t.headline.copyWith(
                    fontSize: 18,
                    height: 24 / 18,
                    letterSpacing: -0.2,
                    color: c.ink,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
    final body = Semantics(
      container: true,
      liveRegion: liveRegion,
      label: spoken,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          head,
          const SizedBox(height: 12),
          PlateFigure(value: figure, unit: unit),
          if (chart != null) ...[const SizedBox(height: 14), chart!],
          if (readouts.isNotEmpty) ...[
            SizedBox(height: chart != null ? 16 : 14),
            const PlateRule(),
            const SizedBox(height: 12),
            StopReadouts(items: readouts),
          ],
        ],
      ),
    );
    final h = header;
    final n = notice;
    Widget plate = AknPlate(
      padding: EdgeInsets.fromLTRB(18, n == null ? 16 : 6, 18, 18),
      child: h == null && n == null
          ? body
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (n != null) ...[
                  n,
                  const SizedBox(height: 6),
                  const PlateRule(),
                  const SizedBox(height: 14),
                ],
                if (h != null) ...[
                  h,
                  const SizedBox(height: 14),
                  const PlateRule(),
                  const SizedBox(height: 14),
                ],
                body,
              ],
            ),
    );
    final tap = onTap;
    if (tap != null) {
      plate = PressScale(
        scale: 0.985,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: () {
            AknHaptics.selection();
            tap();
          },
          child: plate,
        ),
      );
    }
    if (margin != null) plate = Padding(padding: margin!, child: plate);
    return plate;
  }
}
