import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/tupras_prices.dart';

/// "Tüpraş fiyatları" (tasarım v3 §4): bölüm başlığı + "bugün, ₺/L"; altında `KpiRow` hücreleri —
/// sayfada yüzen beyaz kartlar, bir kartın içinde (bayi ana sayfası) sakin kuyular. Hücre: ürün (13/18
/// soluk) üstte, fiyat (`number` 24/30 800, tabular; ilk görünüşte rakamları sayaç gibi yerine oturur)
/// + önceki güne göre değişim (▲/▼ + 13/18 soluk, ya da "aynı"). Değişim yalnızca önceki günün fiyatı
/// biliniyorsa.
///
/// Veri yoksa (yetki yok, uç yanıt vermedi ve kayıt yok) hiçbir şey çizmez. [missingToday] (kurulum
/// kontrolü) ya da gelen fiyat eskiyse bir uyarı kuyusu "Bugünün Tüpraş fiyatı girilmedi." +
/// [onEnterPrice] ("Fiyat gir") gösterilir.
class TuprasStrip extends ConsumerWidget {
  const TuprasStrip({
    super.key,
    this.customerHint,
    this.missingToday = false,
    this.onEnterPrice,
    this.headerPadding = const EdgeInsets.fromLTRB(20, 24, 12, 0),
  });

  /// Fiyat bağlamını almak için bir cari (yoksa temsilcinin portföyünden).
  final int? customerHint;

  /// Ana sayfa kurulum kontrolü: bugünün fiyatı girilmemiş.
  final bool missingToday;
  final VoidCallback? onEnterPrice;
  final EdgeInsetsGeometry headerPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(tuprasPricesProvider(customerHint)).valueOrNull;
    final stale = snap != null && snap.day != null && !snap.isToday();
    final warn = missingToday || stale;
    if (snap == null && !missingToday) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionHeader(
          title: 'Tüpraş fiyatları',
          icon: PhosphorIconsRegular.gasPump,
          caption: snap == null ? null : _caption(snap),
          padding: headerPadding,
        ),
        if (snap != null && snap.prices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: KpiRow(
              children: [for (final p in snap.prices) _PriceCell(price: p)],
            ),
          ),
        if (warn)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: AknBanner(
              tone: AknTone.warn,
              message: snap?.day == null || missingToday
                  ? 'Bugünün Tüpraş fiyatı girilmedi.'
                  : 'Bugünün Tüpraş fiyatı girilmedi. Gösterilen fiyat ${Fmt.dayMonth(snap!.day)} tarihli.',
              actionLabel: onEnterPrice == null ? null : 'Fiyat gir',
              onAction: onEnterPrice,
            ),
          ),
      ],
    );
  }

  /// Şerit sütununa sığan ürün adı: "Kurşunsuz Benzin 95" → "Kurşunsuz 95".
  static String shortName(String name) =>
      name.replaceFirst(RegExp(r'\s+[Bb]enzin(?=\s+\d)'), '').trim();

  /// "bugün, ₺/L", "20 Eki, ₺/L".
  static String _caption(TuprasSnapshot s) {
    final d = s.day;
    final when = d == null
        ? null
        : TrTime.dayDiff(d, TrTime.now()) == 0
        ? 'bugün'
        : TrTime.dayDiff(d, TrTime.now()) == -1
        ? 'dün'
        : Fmt.dayMonth(d);
    return [?when, if (s.fromCache) 'son kayıt', '₺/L'].join(', ');
  }
}

class _PriceCell extends StatelessWidget {
  const _PriceCell({required this.price});

  final TuprasPrice price;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final change = price.change;
    final small = t.label.copyWith(
      fontWeight: FontWeight.w600,
      color: c.dim,
      fontFeatures: AknNumerals.tabular,
    );
    final rounded = change == null ? null : (change * 100).round() / 100;
    final Widget? delta = rounded == null
        ? null
        : rounded == 0
        ? Text('aynı', style: small)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TriangleGlyph.small(down: rounded < 0, color: c.dim),
              const SizedBox(width: 3),
              Text(
                Fmt.number(rounded.abs(), minFraction: 2, maxFraction: 2),
                style: small,
              ),
            ],
          );
    final value = Fmt.number(price.perLiter, minFraction: 2, maxFraction: 2);
    final name = TuprasStrip.shortName(price.name);
    final spoken = [
      name,
      '$value lira litre',
      if (rounded != null)
        rounded == 0
            ? 'dünle aynı'
            : '${Fmt.number(rounded.abs(), minFraction: 2, maxFraction: 2)} lira ${rounded > 0 ? 'artış' : 'düşüş'}',
    ].join(', ');
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: t.label.copyWith(fontWeight: FontWeight.w400, color: c.dim),
            maxLines: 2,
          ),
          const SizedBox(height: 1),
          Wrap(
            spacing: 5,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              RollingText(
                TextSpan(
                  text: value,
                  style: t.number.copyWith(color: c.ink),
                ),
              ),
              ?delta,
            ],
          ),
        ],
      ),
    );
  }
}
