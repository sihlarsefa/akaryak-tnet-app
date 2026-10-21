// Türkçe büyük/küçük harf kuralı (spec C.7, D.7): `lib/` içinde `toUpperCase()` / `toLowerCase()` yalnızca
// `core/utils/turkish_text.dart` içinde bulunur. Türkçe metin için `TurkishText.upper/lower`, kod ve
// ASCII değerler için `asciiUpper` / `asciiLower` kullanılır. `tool/ci.sh` aynı denetimi grep ile yapar.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib/ içinde dil duyarsız büyük/küçük harf dönüşümü yok', () {
    final offenders = <String>[];
    final pattern = RegExp(r'\.to(Upper|Lower)Case\(\)');
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('core/utils/turkish_text.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (pattern.hasMatch(line)) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
