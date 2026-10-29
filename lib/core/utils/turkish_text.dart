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

  /// Bir firmanın kısa adı: yasal ve sektör eklerinden önceki sözcükler ("Demir Petrol Akaryakıt
  /// Ltd. Şti." → "Demir Petrol", "Körfez Nakliyat ve Ticaret" → "Körfez Nakliyat"). Görev satırları
  /// ve bildirim metinleri aynı sözü yazar (v4 P2, A9).
  static String shortCompany(String? title) {
    final full = (title ?? '').trim();
    if (full.isEmpty) return '';
    const stops = {
      'akaryakıt',
      'akaryakit',
      'ltd.',
      'ltd',
      'şti.',
      'şti',
      'a.ş.',
      'a.ş',
      'aş',
      'tic.',
      'san.',
      'limited',
      'anonim',
      've',
    };
    final kept = <String>[];
    for (final w in full.split(RegExp(r'\s+'))) {
      if (stops.contains(lower(w))) break;
      kept.add(w);
    }
    final out = kept.join(' ').trim();
    return out.isEmpty ? full : out;
  }

  /// Saatin yönelme eki, okunuşuna göre: "21:00'e", "08:26'ya", "10:30'a", "16:50'ye" (dakika
  /// sıfırsa saat okunur: "10:00'a"). "… kadar karar verin" cümleleri için.
  static String timeDative(String time) {
    final m = RegExp(r'(\d{1,2})[:.](\d{2})$').firstMatch(time.trim());
    if (m == null) return "$time'e";
    final hour = int.parse(m[1]!);
    final minute = int.parse(m[2]!);
    final word = _numberWord(minute == 0 ? hour : minute);
    const vowels = 'aeıioöuü';
    var last = 'e';
    for (var i = word.length - 1; i >= 0; i--) {
      if (vowels.contains(word[i])) {
        last = word[i];
        break;
      }
    }
    final back = 'aıou'.contains(last);
    final y = vowels.contains(word[word.length - 1]) ? 'y' : '';
    return "$time'$y${back ? 'a' : 'e'}";
  }

  /// Sayının (0–59 ve saatler) okunuşunun son sözcüğü: ek uyumu için.
  static String _numberWord(int n) {
    const ones = [
      'sıfır',
      'bir',
      'iki',
      'üç',
      'dört',
      'beş',
      'altı',
      'yedi',
      'sekiz',
      'dokuz',
    ];
    const tens = ['', 'on', 'yirmi', 'otuz', 'kırk', 'elli'];
    if (n < 10) return ones[n];
    final o = n % 10;
    return o == 0 ? tens[(n ~/ 10).clamp(0, 5)] : ones[o];
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
