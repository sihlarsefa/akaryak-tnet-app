import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../copy.dart';

/// Bir plaka okuması (§7.11): etiket (15/20 500) üstte, değer pompa göstergesi gibi Mona Sans
/// Condensed 700 (sürücü kipinde 28/32) ve küçük birimi ("km", "L") aynı satırda.
@immutable
class StopReadout {
  const StopReadout({
    required this.label,
    required this.value,
    this.unit,
    this.semanticLabel,
  });

  /// "Plan", "Uzaklık", "Teslim saati".
  final String label;

  /// "09:00", "18", "08:00–18:00".
  final String value;

  /// "km", "L" (değerden 3 px sonra, daha küçük).
  final String? unit;

  /// Ekran okuyucu metni (varsayılan "etiket: değer birim").
  final String? semanticLabel;

  String get spoken =>
      semanticLabel ?? '$label: $value${unit == null ? '' : ' $unit'}';
}

/// Durak plakasının okumaları: tek satırda iki uca yaslı sütunlar (ADR levhasının alt yarısı gibi);
/// sığmazsa alt satıra geçer. Büyük yazıda (≥ 1,6×) etiket solda, değer sağda satırlar olur.
/// Değer hiçbir zaman sayının ortasından bölünmez.
class StopReadouts extends StatelessWidget {
  const StopReadouts({super.key, required this.items});

  final List<StopReadout> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final c = context.akn;
    final t = context.aknText;
    final labelStyle = t.label.copyWith(
      color: c.ink,
      fontWeight: FontWeight.w500,
    );
    final valueStyle = t.number.copyWith(color: c.ink);
    final unitStyle = t.readoutUnit.copyWith(color: c.ink);
    InlineSpan value(StopReadout r) => TextSpan(
      text: r.value,
      style: valueStyle,
      children: [
        if (r.unit != null && r.unit!.isNotEmpty) ...[
          const WidgetSpan(child: SizedBox(width: 3)),
          TextSpan(text: r.unit, style: unitStyle),
        ],
      ],
    );
    final large = MediaQuery.textScalerOf(context).scale(10) >= 16;
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
                        border: Border(top: BorderSide(color: c.line)),
                      ),
                child: Row(
                  children: [
                    Expanded(child: Text(items[i].label, style: labelStyle)),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerEnd,
                          child: MediaQuery.withClampedTextScaling(
                            maxScaleFactor: 1.6,
                            child: Text.rich(
                              value(items[i]),
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 20,
      runSpacing: 10,
      children: [
        for (final r in items)
          Semantics(
            label: r.spoken,
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(r.label, style: labelStyle),
                Text.rich(value(r), maxLines: 1, softWrap: false),
              ],
            ),
          ),
      ],
    );
  }
}

/// Şoförün durak plakası (tasarım v2 §5.2, §7.11; tahta ekran 6): ekranın tek turuncu plakası.
/// Başta tankerin ADR levhası ("30 / 1202") ve "Motorin, bu durakta"; altında bu durağın litresi
/// (sürücü kipinde 64/62), 3 px siyah çizgi ve okumalar (Plan, Uzaklık, Teslim saati). Her şey
/// siyah basılır; durum rengi plakaya girmez.
///
/// Teslim sihirbazında aynı plaka sayaç okumasını canlı gösterir ([title] "Sayaç okuması",
/// [liveRegion]).
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
    return Semantics(
      container: true,
      liveRegion: liveRegion,
      label: spoken,
      excludeSemantics: true,
      child: AknPlate(
        margin: margin,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        head: Builder(
          builder: (context) {
            final c = context.akn;
            final t = context.aknText;
            return MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.6,
              child: Row(
                children: [
                  adr ??
                      Icon(
                        Icons.local_gas_station_outlined,
                        size: 24,
                        color: c.ink,
                      ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      heading,
                      style: t.headline.copyWith(
                        fontSize: 18,
                        height: 22 / 18,
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
        ),
        figure: PlateFigure(value: figure, unit: unit),
        below: readouts.isEmpty ? null : StopReadouts(items: readouts),
        rule: readouts.isNotEmpty,
      ),
    );
  }
}
