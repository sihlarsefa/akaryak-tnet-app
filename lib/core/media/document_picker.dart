import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/external_activity.dart';
import '../utils/log.dart';

/// Seçilen PDF dosyası.
@immutable
class PickedDocument {
  const PickedDocument({
    required this.path,
    required this.bytes,
    required this.fileName,
  });

  final String path;
  final Uint8List bytes;
  final String fileName;

  String get contentType => 'application/pdf';
  int get sizeBytes => bytes.length;
}

/// Seçilen dosya kullanılamıyor (çok büyük, PDF değil, okunamadı). [message] Türkçedir ve olduğu gibi
/// gösterilir.
class DocumentPickFailure implements Exception {
  const DocumentPickFailure(this.message);

  final String message;

  @override
  String toString() => 'DocumentPickFailure($message)';
}

/// "Dosya (PDF)" seçimi (spec D.7): dekont, vergi levhası, imza sirküleri gibi belgelerin hazır PDF'i.
///
/// - Yalnızca `.pdf`; içerik `%PDF` imzasıyla doğrulanır (sunucu da imza baytlarına bakar).
/// - Boyut sınırı sunucunun `Attachments.MaxFileMb` ayarıdır (varsayılan 10 MB, üst sınır 25 MB).
///   Uygulama bu değeri bilmediğinde varsayılanı kullanır; sınırı aşan dosya yüklenmeden reddedilir.
/// - Kullanıcı vazgeçerse `null`; kullanılamayan dosyada [DocumentPickFailure].
abstract final class DocumentPicker {
  /// Sunucu varsayılanı (`AttachmentOptions.MaxFileMb`).
  static const defaultMaxMb = 10;

  /// Ayarın üst değeri (`SystemSettingDefaults.MaxAttachmentFileMb`).
  static const absoluteMaxMb = 25;

  /// Testler seçiciyi değiştirir (dosya yolu döndürür).
  @visibleForTesting
  static Future<String?> Function()? debugPickPath;

  static Future<PickedDocument?> pickPdf({int maxMb = defaultMaxMb}) async {
    final limitMb = maxMb.clamp(1, absoluteMaxMb);
    String? path;
    String? name;
    try {
      final override = debugPickPath;
      if (override != null) {
        path = await override();
      } else {
        final result = await ExternalActivity.run(
          () => FilePicker.pickFiles(
            type: FileType.custom,
            allowedExtensions: const ['pdf'],
          ),
        );
        final file = result?.files.firstOrNull;
        path = file?.path;
        name = file?.name;
      }
    } on PlatformException catch (e) {
      AppLog.warn('Dosya seçilemedi (${e.code})', error: e.message);
      throw const DocumentPickFailure('Dosya seçilemedi. Tekrar deneyin.');
    }
    if (path == null) return null;
    return read(path, fileName: name, maxMb: limitMb);
  }

  /// Seçilen dosyayı doğrular ve okur.
  static Future<PickedDocument> read(
    String path, {
    String? fileName,
    int maxMb = defaultMaxMb,
  }) async {
    final file = File(path);
    final int size;
    try {
      size = await file.length();
    } catch (_) {
      throw const DocumentPickFailure(
        'Dosya okunamadı. Başka bir dosya seçin ya da tekrar deneyin.',
      );
    }
    if (size > maxMb * 1024 * 1024) {
      throw DocumentPickFailure('Dosya en fazla $maxMb MB olabilir.');
    }
    final bytes = await file.readAsBytes();
    if (!isPdf(bytes)) {
      throw const DocumentPickFailure('Yalnızca PDF dosyası seçebilirsiniz.');
    }
    final name = (fileName ?? path.split(Platform.pathSeparator).last).trim();
    return PickedDocument(
      path: path,
      bytes: bytes,
      fileName: name.isEmpty ? 'belge.pdf' : name,
    );
  }

  /// `%PDF` imzası.
  static bool isPdf(Uint8List bytes) =>
      bytes.length > 4 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;
}
