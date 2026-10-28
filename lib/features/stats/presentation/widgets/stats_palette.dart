import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// Grafik renkleri (tasarım v3 §2): tek seri, vurgu biçimi. Ton artık renk seçmez — her grafikte
/// güncel / seçili değer [mark] (`chartHighlight`: beyaz kartta logo turuncusu, plakada vurgu
/// turuncusu), diğer çubuklar [context] (`chartContext`: beyazda grafit gri, plakada açık turuncu),
/// ölçer ve sıralı çubuk izi [track] (`chartTrack`). Kategori rengi, durum renginde seri, mavi ve mor
/// yoktur.
@immutable
class StatsHue {
  const StatsHue({
    required this.mark,
    required this.context,
    required this.track,
    required this.glyph,
  });

  /// [tone] yok sayılır (API uyumu için duruyor).
  factory StatsHue.of(AknColors c, [AknTone? tone]) => StatsHue(
    mark: c.chartHighlight,
    context: c.chartContext,
    track: c.chartTrack,
    glyph: c.ink,
  );

  /// Güncel / seçili değer.
  final Color mark;

  /// Diğer çubuklar ve noktalar.
  final Color context;

  /// Ölçer ve sıralı çubuk izi.
  final Color track;

  /// İkon (mürekkep; renkli ikon kutusu yok).
  final Color glyph;

  /// Deprecated: kartlarda ton gölgesi yok ([track] ile aynı).
  Color get tint => track;
}
