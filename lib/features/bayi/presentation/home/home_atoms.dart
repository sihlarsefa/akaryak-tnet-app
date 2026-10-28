import 'package:flutter/material.dart';

import '../../../../core/models/models.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../copy.dart';
import '../widgets/bayi_widgets.dart' show BayiCard, BayiSectionHeader;

/// Ana sayfa yapı taşları (tasarım v3 "Akış" §4): sayfa zemininde süzülen beyaz bölüm kartları (22
/// köşe, kart gölgesi), içlerinde bölüm başlığı + içeriden ince çizgiyle ayrılmış satırlar, sayı
/// sütunu sağda (tablo rakamları, sayarak gelir). Bir satırda en fazla bir tutar / sayı.

/// Ana sayfa bölüm kartının başlık boşluğu: içerikle aynı 20 px kenar, üstte 10 (başlık satırı en az
/// 48 px, [HomeCardHeader]).
const EdgeInsets kHomeHeaderPadding = EdgeInsets.fromLTRB(20, 10, 8, 0);

/// Başlıktaki kişi satırı: "Mehmet Demir, bayi sahibi" (rol adının ilk harfi küçük).
String homePersonLine(MeAccess? access, {String? fallbackRole}) {
  final name = (access?.displayName ?? '').trim();
  final roles = access?.bayiRoleNames ?? const <String>[];
  final role = roles.isNotEmpty ? roles.first : fallbackRole;
  return [
    if (name.isNotEmpty) name,
    if (role != null && role.trim().isNotEmpty) lowerFirst(role.trim()),
  ].join(', ');
}

/// İlk harfi Türkçe kurala göre küçültür ("Bayi sahibi" → "bayi sahibi").
String lowerFirst(String s) {
  if (s.isEmpty) return s;
  final first = String.fromCharCode(s.runes.first);
  return TurkishText.lower(first) + s.substring(first.length);
}

/// Türkçe tamlayan eki, kesme işaretiyle: "Körfez Nakliyat’ın", "Ege Tarım Kooperatifi’nin",
/// "Anadolu Lojistik A.Ş.’nin". Kısaltmalar okunuşlarına göre (A.Ş. "a şe", Şti. "şirketi").
String trGenitive(String name) {
  final n = name.trim();
  if (n.isEmpty) return n;
  final words = n.split(RegExp(r'\s+'));
  final last = words.last;
  if (last.endsWith('.')) {
    final key = TurkishText.lower(last);
    const abbr = {'ltd.': '’in', 'koop.': '’un', 'tic.': '’in'};
    return '$n${abbr[key] ?? '’nin'}';
  }
  final lower = TurkishText.lower(last);
  const vowels = 'aeıioöuü';
  // İnce "l" ile biten alıntılar ince ünlü alır: petrolün, kontrolün, saatin.
  const front = {
    'petrol': 'ün',
    'kontrol': 'ün',
    'protokol': 'ün',
    'alkol': 'ün',
    'rol': 'ün',
    'gol': 'ün',
    'saat': 'in',
    'hal': 'in',
    'kalp': 'in',
  };
  final exception = front[lower.replaceAll(RegExp(r'[^a-zçğıöşü]'), '')];
  if (exception != null) return '$n’$exception';
  String? lastVowel;
  for (var i = lower.length - 1; i >= 0; i--) {
    if (vowels.contains(lower[i])) {
      lastVowel = lower[i];
      break;
    }
  }
  if (lastVowel == null) return '$n’in';
  final harmony = switch (lastVowel) {
    'a' || 'ı' => 'ı',
    'e' || 'i' => 'i',
    'o' || 'u' => 'u',
    _ => 'ü',
  };
  final endsWithVowel = vowels.contains(lower[lower.length - 1]);
  return '$n’${endsWithVowel ? 'n' : ''}${harmony}n';
}

/// Bir sayının tutulduğu satır (tasarım v3): isteğe bağlı 40 px simge karosu ([icon]; Beton zemin,
/// 12 köşe — sayı sıra sizdeyse turuncu yumuşak zemin), başlık solda, sayı sağda (`number` 24/30,
/// tablo rakamları; ilk görünüşte sıfırdan sayar); altında isteğe bağlı lamba ve ikinci satır. Ana
/// sayfanın sayaç satırları ("Kararınızı bekleyen 2").
class HomeCountRow extends StatelessWidget {
  const HomeCountRow({
    super.key,
    required this.label,
    required this.count,
    this.lamp,
    this.meta,
    this.onTap,
    this.semanticLabel,
    this.highlight,
    this.icon,
  });

  final String label;
  final int count;

  /// Durum satırı (lamba + kelime).
  final Widget? lamp;

  /// İkinci satır ("7 gün içinde", "Toplam planlı 5").
  final String? meta;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Sayının rengi (sıra sizdeyse Pas, sorun varsa kırmızı); varsayılan mürekkep (0 ise soluk).
  final Color? highlight;

  /// Baştaki simge karosu (Phosphor çizgi simgesi).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final countColor = highlight ?? (count > 0 ? c.ink : c.dim);
    final countText = AnimatedNumber(
      value: count,
      style: t.number.copyWith(color: countColor),
    );
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: t.bodyStrong.copyWith(height: 20 / 15, color: c.ink),
        ),
        if (meta != null && meta!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(meta!, style: t.bodySmall.copyWith(color: c.dim)),
        ],
        if (lamp != null) ...[const SizedBox(height: 6), lamp!],
      ],
    );
    final glyph = icon;
    final yours = highlight != null && highlight == c.brandInk && count > 0;
    final danger = highlight != null && highlight == c.danger.fg && count > 0;
    final body = Padding(
      padding: AknSpace.row,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          crossAxisAlignment: large
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            if (glyph != null) ...[
              HomeIconTile(
                icon: glyph,
                tone: yours
                    ? AknTone.brand
                    : danger
                    ? AknTone.danger
                    : null,
              ),
              const SizedBox(width: 14),
            ],
            Expanded(child: left),
            const SizedBox(width: 12),
            countText,
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(PhosphorIconsRegular.caretRight, size: 18, color: c.dim),
            ],
          ],
        ),
      ),
    );
    final l = lamp;
    final spoken =
        semanticLabel ??
        [
          '$label: $count',
          if (meta != null && meta!.isNotEmpty) meta!,
          if (l is AknLamp) l.label,
        ].join(', ');
    return Semantics(
      label: spoken,
      button: onTap != null,
      excludeSemantics: true,
      onTap: onTap,
      child: onTap == null ? body : _PressRow(onTap: onTap!, child: body),
    );
  }
}

/// Satır başındaki 40 px simge karosu (tasarım v3 `AknListTile` önü): Beton zemin, 12 köşe, mürekkep
/// simge; [tone] verilirse tonun yumuşak zemini ve rengi ("sıra sizde" turuncu, sorun kırmızı).
class HomeIconTile extends StatelessWidget {
  const HomeIconTile({
    super.key,
    required this.icon,
    this.tone,
    this.size = 40,
  });

  final IconData icon;
  final AknTone? tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final tn = tone;
    final tc = tn == null ? null : c.tone(tn);
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: AknMotion.of(context, AknMotion.base),
        curve: AknMotion.standard,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: tc?.bg ?? c.surfaceAlt,
          borderRadius: BorderRadius.circular(AknRadius.sm),
        ),
        child: Icon(icon, size: size * 0.5, color: tc?.fg ?? c.ink),
      ),
    );
  }
}

/// Basılı satır (tasarım v3, `AknListTile` ile aynı dil): dokununca 16 köşeli Beton dolgu ve 0,97
/// küçülme, bırakınca yayla döner; dokunuşu kaydırma devralırsa (InkWell vurgusu düşer) satır hemen
/// bırakılır.
class _PressRow extends StatefulWidget {
  const _PressRow({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PressRow> createState() => _PressRowState();
}

class _PressRowState extends State<_PressRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = AknMotion.reduced(context);
    final d = _pressed ? AknMotion.press : AknMotion.pressOut;
    const radius = BorderRadius.all(Radius.circular(16));
    final fill = context.akn.surfaceAlt;
    return AnimatedScale(
      scale: _pressed && !reduced ? AknMotion.pressScale : 1,
      duration: d,
      curve: _pressed ? AknMotion.standard : AknMotion.spring,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {
            AknHaptics.selection();
            widget.onTap();
          },
          borderRadius: radius,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          onHighlightChanged: (v) {
            if (v != _pressed) setState(() => _pressed = v);
          },
          child: AnimatedContainer(
            duration: AknMotion.of(context, d),
            curve: AknMotion.standard,
            decoration: BoxDecoration(
              color: _pressed ? fill : fill.withValues(alpha: 0),
              borderRadius: radius,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Bölüm yüklenemedi kuyusu: ne olmadı ve ne yapılır ("Tekrar dene").
class HomeSectionFailed extends StatelessWidget {
  const HomeSectionFailed({super.key, required this.title, this.onRetry});

  final String title;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(AknSpace.page, 16, AknSpace.page, 0),
    child: AknBanner(
      tone: AknTone.warn,
      icon: PhosphorIconsRegular.cloudSlash,
      title: title,
      message: '${BayiCopy.sectionFailed}. ${BayiCopy.sectionFailedMessage}',
      actionLabel: onRetry == null ? null : BayiCopy.retry,
      onAction: onRetry,
    ),
  );
}

/// "Son güncelleme 5 dk önce." (önbellekten açılış ya da tazeleme hatası; tasarım v3): kahraman
/// kartın altında küçük Beton hap, simge ve soluk metin.
class HomeUpdatedLine extends StatelessWidget {
  const HomeUpdatedLine({
    super.key,
    required this.updatedAt,
    this.fromCache = false,
    this.error,
  });

  final DateTime? updatedAt;
  final bool fromCache;
  final AppFailure? error;

  @override
  Widget build(BuildContext context) {
    final at = updatedAt;
    if (at == null || (!fromCache && error == null)) {
      return const SizedBox.shrink();
    }
    final c = context.akn;
    final t = context.aknText;
    final offline = error is OfflineFailure || (fromCache && error == null);
    final when = lowerFirst(Fmt.relative(at));
    final text = offline
        ? 'Son güncelleme $when.'
        : 'Yenilenemedi, son güncelleme $when. Aşağı çekerek tekrar deneyin.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(AknSpace.page, 12, AknSpace.page, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FadeUp(
          offset: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(AknRadius.md),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 12, 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      offline
                          ? PhosphorIconsRegular.clockCounterClockwise
                          : PhosphorIconsRegular.cloudWarning,
                      size: 16,
                      color: c.dim,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(text, style: t.label.copyWith(color: c.dim)),
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

/// Tonlu tutar satırı (tasarım v3, "Tahsilat"): tonun yumuşak zemininde 40 px simge karosu, başlık
/// (15/20 600; kırmızıda tehlike rengi), tutar sağda (`amount`, tablo rakamları), altında ikinci satır
/// ("En eskisi 6 gün gecikmede"). Büyük yazıda tutar başlığın altına iner. [icon] verilmezse tonun
/// simgesi.
class HomeLampAmountRow extends StatelessWidget {
  const HomeLampAmountRow({
    super.key,
    required this.label,
    required this.tone,
    this.amount,
    this.meta,
    this.onTap,
    this.semanticLabel,
    this.icon,
  });

  final String label;
  final AknTone tone;
  final String? amount;
  final String? meta;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Karodaki simge (varsayılan tonun simgesi).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final danger = tone == AknTone.danger;
    final title = Text(
      label,
      style: t.bodyStrong.copyWith(
        height: 20 / 15,
        color: danger ? c.danger.fg : c.ink,
      ),
    );
    final amountText = amount == null
        ? null
        : Text(
            amount!,
            style: t.amount.copyWith(color: c.ink),
            maxLines: 1,
            softWrap: false,
          );
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final metaText = meta == null || meta!.isEmpty
        ? null
        : Text(meta!, style: t.bodySmall.copyWith(color: c.dim));
    final body = Padding(
      padding: AknSpace.row,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          crossAxisAlignment: large
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            HomeIconTile(
              icon: icon ?? AknStatus.toneIcon(tone),
              tone: tone == AknTone.neutral ? null : tone,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (large || amountText == null) ...[
                    title,
                    if (amountText != null) ...[
                      const SizedBox(height: 2),
                      amountText,
                    ],
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 12),
                        amountText,
                      ],
                    ),
                  if (metaText != null) ...[
                    const SizedBox(height: 2),
                    metaText,
                  ],
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(PhosphorIconsRegular.caretRight, size: 18, color: c.dim),
            ],
          ],
        ),
      ),
    );
    return Semantics(
      label: semanticLabel ?? [label, ?amount, ?meta].join(', '),
      button: onTap != null,
      excludeSemantics: true,
      onTap: onTap,
      child: onTap == null ? body : _PressRow(onTap: onTap!, child: body),
    );
  }
}

/// Ana sayfa bölüm kartının başlığı (tasarım v3): [SectionHeader] 20 px kenarda; başlık satırı en az
/// 48 px (eylemli ve eylemsiz kartlarda başlık aynı yükseklikte durur), üstte 10. Büyük yazıda
/// "Tümü" bağlantısı ve sağdaki not başlığın altına iner ([BayiSectionHeader]).
class HomeCardHeader extends StatelessWidget {
  const HomeCardHeader({
    super.key,
    required this.title,
    this.count,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.caption,
    this.icon,
  });

  final String title;

  /// Web panelindeki kart başlığı gibi nötr simge karosu.
  final IconData? icon;
  final int? count;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? caption;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 58),
    child: BayiSectionHeader(
      title: title,
      icon: icon,
      count: count,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
      caption: caption,
      padding: kHomeHeaderPadding,
    ),
  );
}

/// Kurulum uyarısı kuyusu (tasarım v3): tonun yumuşak zemini ve 1 px çizgisi (16 köşe), 32 px yuvarlak
/// içinde tonun simgesi, başlık ve cümle; küçük ikincil düğme altta (uzun metin dar bir sütuna
/// sıkışmasın).
class HomeWell extends StatelessWidget {
  const HomeWell({
    super.key,
    required this.message,
    this.title,
    this.tone = AknTone.warn,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? title;
  final AknTone tone;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final tc = c.tone(tone);
    return Container(
      decoration: BoxDecoration(
        color: tc.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.line),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c.isDark ? tc.line : c.surface.withValues(alpha: 0.75),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon ?? AknStatus.toneIcon(tone),
                size: 18,
                color: tc.fg,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: t.bodyStrong.copyWith(color: c.ink)),
                  const SizedBox(height: 2),
                ],
                Text(message, style: t.bodySmall.copyWith(color: c.ink)),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 10),
                  AknButton.secondary(
                    label: actionLabel!,
                    size: AknButtonSize.small,
                    onPressed: onAction,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ana sayfa bölüm kartı (tasarım v3 §3–4): ana sayfa zemininde (#F5F6F7) süzülen beyaz yüzey, 22
/// köşe, yumuşak iki katlı kart gölgesi; koyu temada 1 px ince çizgi. İçerik kendi iç boşluğunu verir
/// (20 px kenar, [kHomeHeaderPadding]); kart yalnızca alt boşluğu ekler ve içeriği köşelere kırpar
/// (satırların basılı dolgusu köşeyi izler). Bölümler kart kart, art arda yükselerek gelir.
class HomeSectionCard extends StatelessWidget {
  const HomeSectionCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(
      AknSpace.page,
      16,
      AknSpace.page,
      0,
    ),
    this.bottom = 14,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;

  /// Kartın alt iç boşluğu (son satır kendi boşluğunu veriyorsa küçük).
  final double bottom;

  @override
  Widget build(BuildContext context) => BayiCard(
    margin: margin,
    radius: AknRadius.section,
    pressable: false,
    padding: EdgeInsets.only(bottom: bottom),
    child: child,
  );
}
