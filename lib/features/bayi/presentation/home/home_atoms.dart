import 'package:flutter/material.dart';

import '../../../../core/models/models.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../copy.dart';

/// Ana sayfa yapı taşları (tasarım v2 §4, §6.7–6.9): beyaz defter, bölüm başlığı + satırlar, sayı
/// sütunu sağda. Kart yok; bir satırda en fazla bir tutar / sayı.

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

/// Bir sayının tutulduğu defter satırı: başlık solda, sayı sağda (`number` 24/28 Condensed); altında
/// isteğe bağlı lamba ve ikinci satır. Ana sayfanın sayaç satırları ("Kararınızı bekleyen 2").
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

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final countText = Text(
      Fmt.integer(count),
      style: t.number.copyWith(color: highlight ?? (count > 0 ? c.ink : c.dim)),
      maxLines: 1,
      softWrap: false,
    );
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: t.headline.copyWith(color: c.ink)),
        if (meta != null && meta!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(meta!, style: t.bodySmall.copyWith(color: c.dim)),
        ],
        if (lamp != null) ...[const SizedBox(height: 6), lamp!],
      ],
    );
    final body = Padding(
      padding: AknSpace.row,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          crossAxisAlignment: large
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            countText,
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 22, color: c.dim),
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

/// Tam genişlikte basılı satır (Beton dolgu, 90 ms); defter satırlarının dokunma davranışı.
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
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: widget.onTap,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      onHighlightChanged: (v) => setState(() => _pressed = v),
      child: AnimatedContainer(
        duration: AknMotion.of(
          context,
          _pressed ? AknMotion.press : AknMotion.pressOut,
        ),
        color: _pressed ? context.akn.surfaceAlt : Colors.transparent,
        child: widget.child,
      ),
    ),
  );
}

/// Bölüm yüklenemedi kuyusu: ne olmadı ve ne yapılır ("Tekrar dene").
class HomeSectionFailed extends StatelessWidget {
  const HomeSectionFailed({super.key, required this.title, this.onRetry});

  final String title;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: AknBanner(
      tone: AknTone.warn,
      icon: Icons.cloud_off_outlined,
      title: title,
      message: '${BayiCopy.sectionFailed}. ${BayiCopy.sectionFailedMessage}',
      actionLabel: onRetry == null ? null : BayiCopy.retry,
      onAction: onRetry,
    ),
  );
}

/// "Son güncelleme 5 dk önce." (önbellekten açılış ya da tazeleme hatası): tek satır, soluk.
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
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              offline ? Icons.history_rounded : Icons.sync_problem_outlined,
              size: 16,
              color: c.dim,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: t.label.copyWith(color: c.dim)),
          ),
        ],
      ),
    );
  }
}

/// Lambalı tutar satırı (tahta ekran 3 "Tahsilat"): başlık bir lamba (16/22; kırmızıda 600), tutar
/// sağda (`amount`), altında lamba metnine hizalı ikinci satır ("En eskisi 6 gün gecikmede").
class HomeLampAmountRow extends StatelessWidget {
  const HomeLampAmountRow({
    super.key,
    required this.label,
    required this.tone,
    this.amount,
    this.meta,
    this.onTap,
    this.semanticLabel,
  });

  final String label;
  final AknTone tone;
  final String? amount;
  final String? meta;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final lamp = AknLamp(
      label: label,
      tone: tone,
      style: t.body.copyWith(fontSize: 16, height: 22 / 16),
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
    final body = Padding(
      padding: AknSpace.row,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (large || amountText == null) ...[
              Align(alignment: AlignmentDirectional.centerStart, child: lamp),
              if (amountText != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 16, top: 2),
                  child: amountText,
                ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: lamp),
                  const SizedBox(width: 12),
                  amountText,
                ],
              ),
            if (meta != null && meta!.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 16, top: 2),
                child: Text(meta!, style: t.bodySmall.copyWith(color: c.dim)),
              ),
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

/// Kurulum uyarısı kuyusu: Beton, tonun simgesi, başlık ve cümle; küçük ikincil düğme altta (uzun
/// metin dar bir sütuna sıkışmasın).
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
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: AknRadius.card,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              icon ?? AknStatus.toneIcon(tone),
              size: 20,
              color: c.tone(tone).fg,
            ),
          ),
          const SizedBox(width: 10),
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
