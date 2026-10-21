/// Türkçe metin yardımcıları: büyük/küçük harf (İ/ı) ve arama normalizasyonu.
///
/// Kural (spec C.7, D.7): `lib/` içinde `toUpperCase()` / `toLowerCase()` yalnızca bu dosyadadır
/// (`test/core/no_case_mapping_test.dart` ve `tool/ci.sh` denetler). Türkçe metin için [TurkishText];
/// kod, başlık, uzantı, plaka gibi ASCII değerler için [AsciiCase] (`'PDF'.asciiLower`).
abstract final class TurkishText {
  /// Türkçe küçük harf: `I` → `ı`, `İ` → `i`.
  static String lower(String s) =>
      s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

  /// Türkçe büyük harf: `i` → `İ`, `ı` → `I`.
  static String upper(String s) =>
      s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

  /// Arama anahtarı: Türkçe küçük harf, aksanlar atılır (ç→c, ğ→g, ı→i, ö→o, ş→s, ü→u), boşluklar sadeleşir.
  /// "ŞİŞLİ" ve "sisli" aynı anahtarı verir.
  static String searchKey(String s) {
    final l = lower(s);
    final b = StringBuffer();
    for (final r in l.runes) {
      final ch = String.fromCharCode(r);
      b.write(_fold[ch] ?? ch);
    }
    return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static const _fold = {
    'ç': 'c',
    'ğ': 'g',
    'ı': 'i',
    'ö': 'o',
    'ş': 's',
    'ü': 'u',
    'â': 'a',
    'î': 'i',
    'û': 'u',
    '̇': '', // birleşik nokta (i̇)
  };

  /// [haystack] içinde [query] geçiyor mu (Türkçe duyarsız). Boş sorgu her zaman eşleşir.
  static bool matches(String? haystack, String query) {
    final q = searchKey(query);
    if (q.isEmpty) return true;
    return searchKey(haystack ?? '').contains(q);
  }

  /// Sunucu / web metnindeki " · " ayırıcılarını v2 yazımına çevirir ("A · B" → "A, B"; tasarım v2 §1
  /// kural 7). Ekranda gösterilen sunucu özetleri, bildirim metinleri ve çip satırları için.
  static String commaList(String s) => s.replaceAll(' · ', ', ');

  /// [commaList] + sonuç oku: "Satır 5 · Min %4 → Bayi yöneticisi onayı" → "Satır 5, Min %4: Bayi
  /// yöneticisi onayı" (barem çipi gibi sunucu satırları; "→" yazımda kullanılmaz).
  static String plainMeta(String s) => commaList(s).replaceAll(' → ', ': ');

  /// Boş değeri koruyan [plainMeta].
  static String? plainMetaOrNull(String? s) => s == null ? null : plainMeta(s);

  /// Baş harfler (avatar): "Ahmet Yılmaz" → "AY".
  static String initials(String? name, {int max = 2}) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    return parts.take(max).map((p) => upper(p.substring(0, 1))).join();
  }
}

/// Yalnızca A–Z harflerine dokunan büyük/küçük harf dönüşümü: kodlar, HTTP başlıkları, dosya
/// uzantıları, içerik türleri, plaka ve belge numaraları. Türkçe metinde [TurkishText] kullanılır.
extension AsciiCase on String {
  /// `'Image/JPEG'.asciiLower` → `'image/jpeg'` (Türkçe harfler olduğu gibi kalır).
  String get asciiLower {
    final b = StringBuffer();
    for (final u in codeUnits) {
      b.writeCharCode(u >= 0x41 && u <= 0x5A ? u + 0x20 : u);
    }
    return b.toString();
  }

  /// `'34 abc 12'.asciiUpper` → `'34 ABC 12'` (`i` → `I`; plakada `İ` yoktur).
  String get asciiUpper {
    final b = StringBuffer();
    for (final u in codeUnits) {
      b.writeCharCode(u >= 0x61 && u <= 0x7A ? u - 0x20 : u);
    }
    return b.toString();
  }
}
