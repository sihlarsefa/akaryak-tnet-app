// QA yardımcıları: test boyunca tüm Flutter hatalarını toplar ve (isteğe bağlı) ayrıntılarını bir
// dosyaya yazar (`--dart-define=AKN_QA_OUT=/tam/yol`); böylece "Multiple exceptions" yerine her hata
// yığın izinin uygulama satırlarıyla okunabilir.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const qaOut = String.fromEnvironment('AKN_QA_OUT');

/// Test gövdesindeki Flutter hatalarını toplar (gövde bitince eski işleyici geri yüklenir).
class QaErrors {
  QaErrors._(this._orig);

  final FlutterExceptionHandler? _orig;
  final List<String> errors = [];
  String _where = '';

  static QaErrors install() {
    final q = QaErrors._(FlutterError.onError);
    FlutterError.onError = (d) {
      final stack = (d.stack?.toString() ?? '')
          .split('\n')
          .where((l) => l.contains('package:akaryakitnet'))
          .take(6)
          .join('\n    ');
      final full = d.toString();
      final where = full
          .split('\n')
          .where((l) => l.contains('akaryakitnet-mobile/lib/'))
          .map((l) => l.trim())
          .toSet()
          .take(4)
          .join('\n    ');
      q.errors.add(
        '[${q._where}] ${d.exceptionAsString().split('\n').take(6).join(' / ')}'
        '${where.isEmpty ? '' : '\n    at $where'}'
        '${d.context != null ? '\n  ctx: ${d.context!.toDescription()}' : ''}'
        '\n    $stack',
      );
    };
    return q;
  }

  /// Sonraki hataların nerede oluştuğu (rota / adım).
  set where(String w) => _where = w;

  void restore() => FlutterError.onError = _orig;

  /// Hataları dosyaya yazar ([qaOut] verilmişse).
  void dump(String name) {
    if (qaOut.isEmpty) return;
    File('$qaOut/$name.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync(errors.join('\n\n'));
  }
}

/// Bir gövdeyi hata toplayıcıyla çalıştırır; hata varsa testi başarısız sayar.
Future<void> qaRun(
  WidgetTester tester,
  String name,
  Future<void> Function(QaErrors q) body,
) async {
  final q = QaErrors.install();
  try {
    await body(q);
  } finally {
    q.restore();
    q.dump(name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_'));
  }
  expect(q.errors, isEmpty, reason: q.errors.take(8).join('\n\n'));
}
