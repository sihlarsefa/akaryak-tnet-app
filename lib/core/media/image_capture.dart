import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/enums.dart';
import '../ui/widgets/toast.dart';
import '../utils/external_activity.dart';
import '../utils/log.dart';
import '../utils/turkish_text.dart';
import 'crop_guide_page.dart';
import 'document_picker.dart';

/// Hazırlanmış (sıkıştırılmış) görsel ya da seçilmiş PDF ([CaptureSource.file]).
@immutable
class CapturedImage {
  const CapturedImage({
    required this.path,
    required this.bytes,
    this.fileName = 'foto.jpg',
    this.contentType = 'image/jpeg',
  });

  /// Geçici klasördeki JPEG yolu (bekleyen işlemde kullanılacaksa `OutboxFiles.persist`).
  final String path;
  final Uint8List bytes;
  final String fileName;

  /// `image/jpeg` ya da `application/pdf`.
  final String contentType;
  int get sizeBytes => bytes.length;

  /// PDF (önizlemede görsel yerine belge simgesi gösterilir).
  bool get isPdf => contentType == 'application/pdf';
}

/// Belge kaynağı: kamera, galeri ya da hazır PDF dosyası ("Dosya (PDF)").
enum CaptureSource { camera, gallery, file }

/// Kamera / galeri → sıkıştırılmış JPEG (spec C.4).
///
/// - Uzun kenar ≤ 1600 px, kalite 80; HEIC JPEG'e çevrilir.
/// - Yön (EXIF orientation) piksellere uygulanır, sonra EXIF (konum, cihaz) silinir.
/// - Çek ve senet için kırpma kılavuzu açılır ([AttachmentKind.chequeImage], [AttachmentKind.promissoryNoteImage]).
/// - İzin reddedilirse ya da kullanıcı vazgeçerse `null` döner; hata fırlatmaz.
abstract final class ImageCapture {
  static const maxEdge = 1600;
  static const quality = 80;

  static final ImagePicker _picker = ImagePicker();

  /// Tek görsel seçer/çeker. [context] verilirse ve tür çek/senet ise kırpma kılavuzu gösterilir.
  /// [CaptureSource.file] hazır bir PDF seçtirir (boyut [maxFileMb]; sınır aşılırsa bildirim gösterilir).
  static Future<CapturedImage?> pick({
    required CaptureSource source,
    AttachmentKind kind = AttachmentKind.other,
    BuildContext? context,
    int maxFileMb = DocumentPicker.defaultMaxMb,
  }) async {
    if (source == CaptureSource.file) return _pickPdf(maxFileMb);
    try {
      final file = await ExternalActivity.run(
        () => _picker.pickImage(
          source: source == CaptureSource.camera
              ? ImageSource.camera
              : ImageSource.gallery,
          maxWidth: maxEdge.toDouble(),
          maxHeight: maxEdge.toDouble(),
          imageQuality: 95,
          requestFullMetadata: false,
        ),
      );
      if (file == null) return null;
      var image = await prepare(file.path, fileName: _fileName(kind));
      if (image == null) return null;
      if (context != null && context.mounted && _needsCropGuide(kind)) {
        final cropped = await Navigator.of(context, rootNavigator: true)
            .push<Uint8List>(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => CropGuidePage(image: image!.bytes, kind: kind),
              ),
            );
        if (cropped != null) {
          image = await _fromBytes(cropped, fileName: image.fileName);
        }
      }
      return image;
    } on PlatformException catch (e) {
      AppLog.warn('Görsel alınamadı (${e.code})', error: e.message);
      return null;
    } catch (e) {
      AppLog.warn('Görsel alınamadı', error: e);
      return null;
    }
  }

  static Future<CapturedImage?> _pickPdf(int maxMb) async {
    try {
      final doc = await DocumentPicker.pickPdf(maxMb: maxMb);
      if (doc == null) return null;
      return CapturedImage(
        path: doc.path,
        bytes: doc.bytes,
        fileName: doc.fileName,
        contentType: doc.contentType,
      );
    } on DocumentPickFailure catch (f) {
      AppToast.error(f.message);
      return null;
    } catch (e) {
      AppLog.warn('Dosya alınamadı', error: e);
      return null;
    }
  }

  /// Galeriden birden çok görsel (itiraz, saha fotoğrafları). En fazla [limit].
  static Future<List<CapturedImage>> pickMany({int limit = 6}) async {
    try {
      final files = await ExternalActivity.run(
        () => _picker.pickMultiImage(
          maxWidth: maxEdge.toDouble(),
          maxHeight: maxEdge.toDouble(),
          imageQuality: 95,
          requestFullMetadata: false,
          limit: limit,
        ),
      );
      final out = <CapturedImage>[];
      for (final f in files.take(limit)) {
        final img = await prepare(f.path);
        if (img != null) out.add(img);
      }
      return out;
    } catch (e) {
      AppLog.warn('Görseller alınamadı', error: e);
      return const [];
    }
  }

  static bool _needsCropGuide(AttachmentKind kind) =>
      kind == AttachmentKind.chequeImage ||
      kind == AttachmentKind.promissoryNoteImage;

  static String _fileName(AttachmentKind kind) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final base = switch (kind) {
      AttachmentKind.chequeImage => 'cek',
      AttachmentKind.promissoryNoteImage => 'senet',
      AttachmentKind.deliveryPhoto => 'teslimat',
      AttachmentKind.disputePhoto => 'itiraz',
      AttachmentKind.visitPhoto => 'ziyaret',
      AttachmentKind.taxPlate => 'vergi-levhasi',
      _ => 'belge',
    };
    return '$base-$ts.jpg';
  }

  /// Dosyayı sıkıştırılmış JPEG'e çevirir (yön uygulanır, EXIF silinir). Sıkıştırma başarısızsa
  /// JPEG/PNG ise özgün bayt kullanılır.
  static Future<CapturedImage?> prepare(
    String sourcePath, {
    String? fileName,
  }) async {
    Uint8List? bytes;
    try {
      bytes = await FlutterImageCompress.compressWithFile(
        sourcePath,
        minWidth: maxEdge,
        minHeight: maxEdge,
        quality: quality,
        format: CompressFormat.jpeg,
        keepExif: false,
        autoCorrectionAngle: true,
      );
    } catch (e) {
      AppLog.warn('Görsel sıkıştırılamadı; özgün dosya kullanılacak', error: e);
    }
    if (bytes == null) {
      final ext = p.extension(sourcePath).asciiLower;
      if (ext != '.jpg' && ext != '.jpeg' && ext != '.png') return null;
      bytes = await File(sourcePath).readAsBytes();
    }
    return _fromBytes(
      bytes,
      fileName: fileName ?? 'foto-${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
  }

  /// Baytları (ör. kırpılmış PNG) JPEG'e çevirip geçici dosyaya yazar.
  static Future<CapturedImage> _fromBytes(
    Uint8List input, {
    required String fileName,
  }) async {
    var bytes = input;
    final isJpeg = bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
    if (!isJpeg) {
      try {
        bytes = await FlutterImageCompress.compressWithList(
          input,
          minWidth: maxEdge,
          minHeight: maxEdge,
          quality: quality,
          format: CompressFormat.jpeg,
          keepExif: false,
        );
      } catch (_) {
        bytes = input;
      }
    }
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, fileName);
    await File(path).writeAsBytes(bytes, flush: true);
    return CapturedImage(path: path, bytes: bytes, fileName: fileName);
  }
}
