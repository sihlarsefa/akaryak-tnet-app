import 'package:flutter/material.dart';

import '../../../../core/models/models.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../copy.dart';

/// Ana sayfa yapı taşları (tasarım v4 "Sade"): kişi satırı, Türkçe ek yardımcıları, yüklenemeyen
/// bölüm uyarısı ve "son güncelleme" notu. Bölüm kartları yerine defterler (`AknLedger`) kullanılır.

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
