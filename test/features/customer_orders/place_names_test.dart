// v4 §3.2 "bir yer, bir ad" (round 2, B8): kullanıcıya görünen metinde bir yerin adı alt menüdeki
// sözcüktür (Onaylar, Siparişler, Teklifler, Şablonlar). Eski adlar ("Onaylarım", "Siparişlerim",
// "Teklif masası", "Şablonlarım", "Onay merkezi") müşteri, profil, asistan, ödeme ve giriş
// özelliklerinin kaynağında yorum satırları dışında geçmez. Bu metinler çoğu zaman ancak belirsiz bir
// gönderimde ya da asistanın yanıtında görünür; ekran taraması (test/qa/shell-common/copy_sweep_test)
// onları yakalamaz, kaynak taraması yakalar.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _areas = [
  'customer_home',
  'customer_orders',
  'customer_more',
  'profile',
  'assistant',
  'payments',
  'auth',
];

final _oldNames = RegExp(
  'Onaylarım|Siparişlerim|Teklif masas|Şablonlarım|Onay merkezi',
);

void main() {
  test('eski yer adları kullanıcı metninde geçmez', () {
    final offenders = <String>[];
    for (final area in _areas) {
      final dir = Directory('lib/features/$area');
      for (final f in dir.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trimLeft();
          if (line.startsWith('//')) continue;
          // Satır sonundaki yorum sayılmaz.
          final code = line.split(' // ').first;
          if (_oldNames.hasMatch(code)) {
            offenders.add('${f.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
