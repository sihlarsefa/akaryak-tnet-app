import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/tupras_prices.dart';

/// "Tüpraş fiyatları" (tasarım v4 "Sade" §5 03): tek kart — ana sayfa bölüm kartı (22 köşe, yalnızca
/// ince çizgi; koyu temada 1 px çizgi). Başlık satırında solda "Tüpraş fiyatları", sağda fiyat
/// tarihi ("28 Eki · ₺/L"); fiyat bugünün değilse ya da bugünün fiyatı girilmediyse ([missingToday])
/// tarihin önünde küçük bir uyarı noktası. Altında fiyatlar tek satırda, kuyu yok: ürün (13/18
/// soluk) üstte, fiyat (`number` 24/30 800, tablo rakamları; ilk görünüşte rakamlar sayaç gibi
/// yerine oturur) ve önceki güne göre değişim (▲/▼ + 12/16 soluk ya da "aynı").
///
/// Uyarı kuyusu yok: bugünün fiyatını girme işi ana sayfanın "Sıra sizde" kartındadır (v4: tek
/// uyarı). Veri yoksa (yetki yok, uç yanıt vermedi ve kayıt yok) hiçbir şey çizmez.
class TuprasStrip extends ConsumerWidget {
  const TuprasStrip({
    super.key,
    this.customerHint,
    this.missingToday = false,
    this.margin = const EdgeInsets.fromLTRB(20, 16, 20, 0),
  });

  /// Fiyat bağlamını almak için bir cari (yoksa temsilcinin portföyünden).
  final int? customerHint;

  /// Ana sayfa kurulum kontrolü: bugünün fiyatı girilmemiş (tarihin önünde uyarı noktası).
  final bool missingToday;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(tuprasPricesProvider(customerHint)).valueOrNull;
    if (snap == null || snap.prices.isEmpty) return const SizedBox.shrink();
    final c = context.akn;
    final t = context.aknText;
    final stale = (snap.day != null && !snap.isToday()) || missingToday;
    final caption = _caption(snap);
    final title = Semantics(
      header: true,
      child: Text(
        'Tüpraş fiyatları',
        style: t.headline.copyWith(
          fontSize: 17,
          height: 22 / 17,
          fontWeight: FontWeight.w700,
          color: c.ink,
        ),
      ),
    );
    final when = Semantics(
      label: stale ? '$caption, bugünün fiyatı girilmedi' : caption,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (stale) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: c.warn.solid,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              caption,
              style: t.label.copyWith(
                fontWeight: FontWeight.w500,
                color: c.dim,
                fontFeatures: AknNumerals.tabular,
              ),
            ),
          ),
        ],
      ),
    );
    // Büyük yazıda tarih başlığın altına iner (yan yana sığmaz).
    final stacked = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final Widget header = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [title, const SizedBox(height: 4), when],
          )
        : Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 12),
              Flexible(child: when),
            ],
          );
    final large = MediaQuery.textScalerOf(context).scale(10) >= 14;
    final cells = [for (final p in snap.prices.take(4)) _PriceCell(price: p)];
    final figures = large
        ? Wrap(spacing: 20, runSpacing: 12, children: cells)
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: cells[i]),
              ],
            ],
          );
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: AknRadius.section,
          border: c.isDark ? Border.all(color: c.line) : null,
          boxShadow: c.isDark ? null : [AknShadows.hairline(c)],
        ),
        child: AknCardScope(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [header, const SizedBox(height: 12), figures],
            ),
          ),
        ),
      ),
    );
  }

  /// Şerit sütununa sığan ürün adı: "Kurşunsuz Benzin 95" → "Kurşunsuz 95".
  static String shortName(String name) =>
      name.replaceFirst(RegExp(r'\s+[Bb]enzin(?=\s+\d)'), '').trim();

  /// "Bugün · ₺/L", "28 Eki · ₺/L", "Dün · son kayıt · ₺/L".
  static String _caption(TuprasSnapshot s) {
    final d = s.day;
    final diff = d == null ? null : TrTime.dayDiff(d, TrTime.now());
    final when = d == null
        ? null
        : diff == 0
        ? 'Bugün'
        : diff == -1
        ? 'Dün'
        : Fmt.dayMonth(d);
    return [?when, if (s.fromCache) 'son kayıt', '₺/L'].join(' · ');
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
    final small = t.caption.copyWith(
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
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: RollingText(
              TextSpan(
                text: value,
                style: t.number.copyWith(color: c.ink),
              ),
            ),
          ),
          if (delta != null) ...[const SizedBox(height: 2), delta],
        ],
      ),
    );
  }
}
