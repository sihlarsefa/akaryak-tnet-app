import 'package:flutter/services.dart';

/// Türkiye cep telefonu yazımı: `5XX XXX XX XX`. Başta `0`, `90` ya da `+90` yazılırsa atılır;
/// yapıştırılan numara da aynı biçime getirilir. İmleç sona alınır.
class TrMobileFormatter extends TextInputFormatter {
  const TrMobileFormatter();

  /// Girilen metnin 10 haneli yerel numarası (5XXXXXXXXX), eksikse olduğu kadarı.
  static String localDigits(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('90') && d.length > 10) d = d.substring(2);
    if (d.startsWith('0')) d = d.substring(1);
    return d.length > 10 ? d.substring(0, 10) : d;
  }

  /// `5321234567` → `532 123 45 67`.
  static String group(String digits) {
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 3 || i == 6 || i == 8) b.write(' ');
      b.write(digits[i]);
    }
    return b.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = group(localDigits(newValue.text));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
