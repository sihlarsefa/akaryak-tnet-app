import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/log.dart';

/// Cihazda saklanan belge (çevrimdışı paylaşım).
@immutable
class CachedPdf {
  const CachedPdf({
    required this.fileName,
    required this.savedAt,
    required this.sizeBytes,
    this.path,
  });

  final String fileName;
  final DateTime savedAt;
  final int sizeBytes;

  /// Diskteki yol (bellek içi önbellekte null).
  final String? path;
}

/// Oluşturulan PDF'lerin cihaz önbelleği (spec C.4a: belgeler çevrimdışı paylaşılabilir).
///
/// Dosyalar kullanıcıya özel klasördedir; başka kullanıcının dosyaları yazma sırasında silinir
/// (ortak telefon). En fazla [maxFiles] dosya ve [maxAge] süre tutulur. Hiçbir yöntem hata fırlatmaz:
/// disk kullanılamazsa belge yine oluşturulur, yalnızca saklanmaz.
abstract interface class PdfCache {
  Future<Uint8List?> read(String userId, String fileName);
  Future<CachedPdf?> info(String userId, String fileName);
  Future<CachedPdf?> write(String userId, String fileName, Uint8List bytes);
  Future<List<CachedPdf>> list(String userId);
  Future<void> clear(String userId);

  static const maxFiles = 60;
  static const maxAge = Duration(days: 30);
}

/// Kullanıcı klasör adı (iki tohumlu 32 bit FNV-1a; kimlik yol karakteri içerse de güvenli).
String pdfCacheUserKey(String userId) {
  String fnv(int seed) {
    var h = seed;
    for (final b in utf8.encode('akn-docs:$userId')) {
      h ^= b;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  return 'u${fnv(0x811c9dc5)}${fnv(0x01234567)}';
}

/// Dosya adı güvenliği: yol karakterleri atılır.
String safePdfFileName(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '')
      .replaceAll(RegExp(r'\s+'), '_');
  return RegExp(r'\.pdf$', caseSensitive: false).hasMatch(cleaned)
      ? cleaned
      : '$cleaned.pdf';
}

/// Uygulama destek klasöründe `akn_docs/<kullanıcı>/` altında dosyalar.
class FilePdfCache implements PdfCache {
  FilePdfCache({Future<Directory> Function()? root})
    : _root = root ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _root;

  Future<Directory?> _base() async {
    try {
      final root = await _root();
      return Directory(p.join(root.path, 'akn_docs'));
    } catch (e) {
      AppLog.debug('Belge önbelleği kullanılamıyor: $e');
      return null;
    }
  }

  Future<Directory?> _dir(String userId, {bool create = false}) async {
    final base = await _base();
    if (base == null) return null;
    final dir = Directory(p.join(base.path, pdfCacheUserKey(userId)));
    if (create && !await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<Uint8List?> read(String userId, String fileName) async {
    try {
      final dir = await _dir(userId);
      if (dir == null) return null;
      final f = File(p.join(dir.path, safePdfFileName(fileName)));
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } catch (e) {
      AppLog.debug('Belge okunamadı: $e');
      return null;
    }
  }

  @override
  Future<CachedPdf?> info(String userId, String fileName) async {
    try {
      final dir = await _dir(userId);
      if (dir == null) return null;
      final f = File(p.join(dir.path, safePdfFileName(fileName)));
      if (!await f.exists()) return null;
      final stat = await f.stat();
      return CachedPdf(
        fileName: safePdfFileName(fileName),
        savedAt: stat.modified.toUtc(),
        sizeBytes: stat.size,
        path: f.path,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<CachedPdf?> write(
    String userId,
    String fileName,
    Uint8List bytes,
  ) async {
    try {
      final base = await _base();
      if (base == null) return null;
      // Ortak telefon: başka kullanıcının belgeleri kalmaz.
      if (await base.exists()) {
        final keep = pdfCacheUserKey(userId);
        await for (final e in base.list()) {
          if (e is Directory && p.basename(e.path) != keep) {
            await e.delete(recursive: true);
          }
        }
      }
      final dir = await _dir(userId, create: true);
      if (dir == null) return null;
      final name = safePdfFileName(fileName);
      final f = File(p.join(dir.path, name));
      await f.writeAsBytes(bytes, flush: true);
      await _prune(dir);
      return CachedPdf(
        fileName: name,
        savedAt: DateTime.now().toUtc(),
        sizeBytes: bytes.length,
        path: f.path,
      );
    } catch (e) {
      AppLog.debug('Belge saklanamadı: $e');
      return null;
    }
  }

  Future<void> _prune(Directory dir) async {
    final files = <File>[];
    await for (final e in dir.list()) {
      if (e is File) files.add(e);
    }
    final now = DateTime.now();
    final stats = <(File, DateTime)>[];
    for (final f in files) {
      stats.add((f, (await f.stat()).modified));
    }
    stats.sort((a, b) => b.$2.compareTo(a.$2));
    for (var i = 0; i < stats.length; i++) {
      final (file, modified) = stats[i];
      if (i >= PdfCache.maxFiles ||
          now.difference(modified) > PdfCache.maxAge) {
        await file.delete();
      }
    }
  }

  @override
  Future<List<CachedPdf>> list(String userId) async {
    try {
      final dir = await _dir(userId);
      if (dir == null || !await dir.exists()) return const [];
      final out = <CachedPdf>[];
      await for (final e in dir.list()) {
        if (e is File) {
          final stat = await e.stat();
          out.add(
            CachedPdf(
              fileName: p.basename(e.path),
              savedAt: stat.modified.toUtc(),
              sizeBytes: stat.size,
              path: e.path,
            ),
          );
        }
      }
      out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return out;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> clear(String userId) async {
    try {
      final dir = await _dir(userId);
      if (dir != null && await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}

/// Bellek içi önbellek (testler).
class MemoryPdfCache implements PdfCache {
  final Map<String, Map<String, (Uint8List, DateTime)>> _files = {};

  @override
  Future<Uint8List?> read(String userId, String fileName) async =>
      _files[userId]?[safePdfFileName(fileName)]?.$1;

  @override
  Future<CachedPdf?> info(String userId, String fileName) async {
    final name = safePdfFileName(fileName);
    final e = _files[userId]?[name];
    return e == null
        ? null
        : CachedPdf(fileName: name, savedAt: e.$2, sizeBytes: e.$1.length);
  }

  @override
  Future<CachedPdf?> write(
    String userId,
    String fileName,
    Uint8List bytes,
  ) async {
    _files.removeWhere((k, _) => k != userId);
    final name = safePdfFileName(fileName);
    final now = DateTime.now().toUtc();
    (_files[userId] ??= {})[name] = (bytes, now);
    return CachedPdf(fileName: name, savedAt: now, sizeBytes: bytes.length);
  }

  @override
  Future<List<CachedPdf>> list(String userId) async => [
    for (final e in (_files[userId] ?? const {}).entries)
      CachedPdf(
        fileName: e.key,
        savedAt: e.value.$2,
        sizeBytes: e.value.$1.length,
      ),
  ];

  @override
  Future<void> clear(String userId) async => _files.remove(userId);
}

final pdfCacheProvider = Provider<PdfCache>((ref) => FilePdfCache());
