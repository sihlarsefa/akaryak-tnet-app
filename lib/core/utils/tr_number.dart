/// Kullanıcının Türkçe yazdığı sayıları okur: `12.500` → 12500, `12.500,75` → 12500.75, `42,13` → 42.13.
///
/// Kurallar: virgül ondalık ayırıcıdır; nokta binlik ayırıcıdır. Yalnızca nokta varsa ve noktadan sonra
/// tam 3 hane yoksa (ör. `12.5`) nokta ondalık sayılır (yapıştırılan İngilizce biçim).
abstract final class TrNumber {
  static double? parse(String? input) {
    var s = (input ?? '')
        .trim()
        .replaceAll(' ', '')
        .replaceAll(' ', '')
        .replaceAll('₺', '')
        .replaceAll('L', '');
    if (s.isEmpty) return null;
    final negative = s.startsWith('-');
    if (negative) s = s.substring(1);
    if (s.contains(',')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else if (s.contains('.')) {
      final parts = s.split('.');
      final thousands =
          parts.length > 1 && parts.skip(1).every((p) => p.length == 3);
      if (thousands) s = parts.join();
    }
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) return null;
    final v = double.tryParse(s);
    if (v == null) return null;
    return negative ? -v : v;
  }

  /// Ondalık hane sayısı (girişte en fazla N hane kuralı için).
  static int decimals(String? input) {
    final s = (input ?? '').trim();
    final i = s.lastIndexOf(',');
    return i < 0 ? 0 : s.length - i - 1;
  }
}
