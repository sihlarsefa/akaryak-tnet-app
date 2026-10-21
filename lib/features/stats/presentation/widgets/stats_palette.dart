import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// Bir kartın / bölümün renkleri (DS belirteçlerinden): ikon, işaret (çubuk, halka) ve kartın üstündeki
/// hafif ton. Turuncu kartta ikon `brand`, çubuklar `logo` (spec R1 §1.1); diğerleri tonun ön rengi.
@immutable
class StatsHue {
  const StatsHue({required this.glyph, required this.mark, required this.tint});

  factory StatsHue.of(AknColors c, AknTone tone) => switch (tone) {
    AknTone.brand => StatsHue(glyph: c.brand, mark: c.logo, tint: c.logo),
    _ => StatsHue(
      glyph: c.tone(tone).fg,
      mark: c.tone(tone).fg,
      tint: c.tone(tone).fg,
    ),
  };

  /// İkon.
  final Color glyph;

  /// Çubuk, halka, ilerleme (metin değil).
  final Color mark;

  /// Kartın üst tonu ve ince çizgisi.
  final Color tint;
}

/// Ürün dağılımı renkleri — yalnızca DS belirteçlerinden, sabit sırayla: marka turuncusu (`logo`) · mavi
/// (`info`) · yeşil (`ok`) · amber (`warn`). Mor yoktur; tema değişince renkler de değişir. DS'te henüz
/// kategorik grafik paleti olmadığından ayırt edilebilir dört renk vardır: beşinci ve sonraki ürünler
/// "Diğer" dilimine katlanır (nötr gri). Dilimler arasında yüzey boşluğu, yanlarında ad ve yüzde yazar
/// (renk tek başına bilgi taşımaz). Renk ürüne bağlıdır, sırasına değil ([productColors]).
abstract final class StatsPalette {
  /// Renkli dilim sayısı (kalanlar "Diğer").
  static const size = 4;

  static Color slot(AknColors c, int i) => switch (i % size) {
    0 => c.logo,
    1 => c.info.fg,
    2 => c.ok.fg,
    _ => c.warn.fg,
  };

  /// "Diğer" dilimi.
  static Color other(AknColors c) => c.dim;

  /// Gösterilen ürünlerin renkleri: kimlik → `(id - 1) % 4`, çakışmada sıradaki boş renk (kimliğe göre
  /// artan sırayla). Aynı ürün kümesi her dönemde aynı renkleri alır; en çok [size] ürün verin.
  static Map<int, Color> productColors(AknColors c, Iterable<int> productIds) {
    final ids = productIds.toSet().toList()..sort();
    final used = <int>{};
    final out = <int, Color>{};
    for (final id in ids) {
      var s = ((id - 1) % size + size) % size;
      var guard = 0;
      while (used.contains(s) && guard++ < size) {
        s = (s + 1) % size;
      }
      used.add(s);
      out[id] = slot(c, s);
    }
    return out;
  }
}
