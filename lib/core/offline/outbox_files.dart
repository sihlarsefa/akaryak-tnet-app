import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/log.dart';

/// Bekleyen işlem dosyaları: fotoğraf ve imzalar geçici klasörden uygulama klasörüne kopyalanır
/// (işletim sistemi geçici dosyaları silebilir). İşlem tamamlanınca [OutboxRunner] siler.
abstract final class OutboxFiles {
  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'outbox'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// [sourcePath] dosyasını kalıcı klasöre kopyalar ve yeni yolu döndürür.
  static Future<String> persist(String sourcePath, {String? name}) async {
    final dir = await _dir();
    final ext = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath);
    final target = p.join(
      dir.path,
      '${name ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$ext',
    );
    await File(sourcePath).copy(target);
    return target;
  }

  /// Bayt içeriğini (ör. imza PNG) kalıcı klasöre yazar.
  static Future<String> persistBytes(
    List<int> bytes, {
    required String extension,
  }) async {
    final dir = await _dir();
    final target = p.join(
      dir.path,
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}.$extension',
    );
    await File(target).writeAsBytes(bytes, flush: true);
    return target;
  }

  /// Hiçbir işleme bağlı olmayan eski dosyaları temizler.
  static Future<void> sweep(
    Set<String> keep, {
    Duration olderThan = const Duration(days: 3),
  }) async {
    try {
      final dir = await _dir();
      final cutoff = DateTime.now().subtract(olderThan);
      for (final f in dir.listSync().whereType<File>()) {
        if (!keep.contains(f.path) && f.statSync().modified.isBefore(cutoff)) {
          f.deleteSync();
        }
      }
    } catch (e) {
      AppLog.debug('Bekleyen dosya temizliği atlandı: $e');
    }
  }
}
