import 'turkish_text.dart';

/// Form doğrulayıcıları. `TextFormField.validator` ile kullanılır: geçerliyse `null`, değilse Türkçe mesaj.
/// VKN / TCKN kuralları sunucuyla aynıdır (`LeadDtos.cs` IsValidVkn / IsValidTckn / TaxNumberError).
abstract final class Validators {
  static String? required(
    String? value, {
    String message = 'Bu alan zorunludur.',
  }) => value == null || value.trim().isEmpty ? message : null;

  /// Yalnızca rakamlar (boşluk, tire, nokta atılır).
  static String digitsOnly(String? raw) =>
      raw == null ? '' : raw.replaceAll(RegExp(r'\D'), '');

  /// 10 haneli vergi kimlik numarası (GİB algoritması).
  static bool isValidVkn(String? digits) {
    if (digits == null || !RegExp(r'^\d{10}$').hasMatch(digits)) return false;
    var sum = 0;
    for (var i = 0; i < 9; i++) {
      final tmp = (digits.codeUnitAt(i) - 48 + 9 - i) % 10;
      var v = tmp * (1 << (9 - i)) % 9;
      if (tmp != 0 && v == 0) v = 9;
      sum += v;
    }
    return (10 - sum % 10) % 10 == digits.codeUnitAt(9) - 48;
  }

  /// 11 haneli T.C. kimlik numarası.
  static bool isValidTckn(String? digits) {
    if (digits == null || !RegExp(r'^[1-9]\d{10}$').hasMatch(digits)) {
      return false;
    }
    final d = digits.codeUnits.map((c) => c - 48).toList();
    final odd = d[0] + d[2] + d[4] + d[6] + d[8];
    final even = d[1] + d[3] + d[5] + d[7];
    final d10 = ((odd * 7 - even) % 10 + 10) % 10;
    final d11 = d.take(10).fold<int>(0, (a, b) => a + b) % 10;
    return d[9] == d10 && d[10] == d11;
  }

  /// VKN / TCKN hatası (geçerliyse null). Boş değer "zorunlu" hatası verir.
  static String? taxNumber(String? raw) {
    final digits = digitsOnly(raw);
    if (digits.isEmpty) return 'VKN / TCKN zorunludur.';
    if (digits.length == 10) {
      return isValidVkn(digits)
          ? null
          : 'VKN doğrulanamadı; numarayı kontrol edin.';
    }
    if (digits.length == 11) {
      return isValidTckn(digits)
          ? null
          : 'TCKN doğrulanamadı; numarayı kontrol edin.';
    }
    return 'VKN 10, TCKN 11 haneli olmalıdır.';
  }

  /// Türkiye cep telefonu: 5XX XXX XX XX (başında 0 ya da 90 olabilir).
  static String? mobilePhone(String? raw, {bool required = true}) {
    final d = digitsOnly(raw);
    if (d.isEmpty) return required ? 'Telefon numarası zorunludur.' : null;
    return normalizePhone(d) == null
        ? 'Geçerli bir cep telefonu girin (5XX XXX XX XX).'
        : null;
  }

  /// Telefonu sunucunun beklediği `90XXXXXXXXXX` biçimine çevirir; geçersizse null.
  static String? normalizePhone(String? raw) {
    var d = digitsOnly(raw);
    if (d.length == 12 && d.startsWith('90')) d = d.substring(2);
    if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
    if (d.length != 10 || !d.startsWith('5')) return null;
    return '90$d';
  }

  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  static String? email(String? raw, {bool required = true}) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty) return required ? 'E-posta zorunludur.' : null;
    return _email.hasMatch(v) ? null : 'Geçerli bir e-posta adresi girin.';
  }

  static final _userName = RegExp(r'^[A-Za-z0-9._-]+$');

  /// Kullanıcı adının karakter kuralı (sunucunun iletisi aynen).
  static const userNameCharacters =
      'Kullanıcı adında yalnızca İngilizce harf, rakam, nokta, alt çizgi ve tire olabilir.';

  /// Kullanıcı adı (sunucuyla aynı, sahip 2026-10-30): kırpılır; 3–50 karakter; İngilizce harf, rakam,
  /// `.`, `_`, `-` (Türkçe harf yok).
  static String? userName(String? raw) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty) return 'Kullanıcı adı zorunludur.';
    if (!_userName.hasMatch(v)) return userNameCharacters;
    if (v.length < 3 || v.length > 50) {
      return 'Kullanıcı adı 3–50 karakter olmalı.';
    }
    return null;
  }

  static final _plate = RegExp(r'^(0[1-9]|[1-7]\d|8[01])[A-Z]{1,3}\d{2,5}$');

  /// Türkiye plakası (01–81 il kodu + 1–3 harf + 2–5 rakam).
  static String? plate(String? raw, {bool required = true}) {
    final s = (raw ?? '').asciiUpper.replaceAll(RegExp(r'[^0-9A-Z]'), '');
    if (s.isEmpty) return required ? 'Plaka zorunludur.' : null;
    return _plate.hasMatch(s)
        ? null
        : 'Geçerli bir plaka girin (ör. 34 ABC 123).';
  }

  /// Pozitif sayı, en fazla [max] (ör. planlanan litre) ve [maxDecimals] ondalık.
  static String? positiveNumber(
    num? value, {
    num? max,
    int maxDecimals = 3,
    String unit = '',
  }) {
    if (value == null) return 'Bu alan zorunludur.';
    if (value <= 0) return 'Sıfırdan büyük bir değer girin.';
    if (max != null && value > max) {
      return 'En fazla ${_plain(max)}$unit girilebilir.';
    }
    final s = value.toString();
    final dot = s.indexOf('.');
    if (dot >= 0 && s.length - dot - 1 > maxDecimals && !s.contains('e')) {
      return 'En fazla $maxDecimals ondalık hane girilebilir.';
    }
    return null;
  }

  static String _plain(num v) => v == v.roundToDouble()
      ? v.round().toString()
      : v.toString().replaceAll('.', ',');
}
