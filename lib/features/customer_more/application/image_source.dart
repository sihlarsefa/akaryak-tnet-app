import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/image_capture.dart';
import '../../../core/models/enums.dart';

/// Fotoğraf kaynağı (kamera / galeri). Testler sahte uygulama verir.
abstract interface class CmImagePicker {
  Future<CapturedImage?> pick(
    BuildContext context,
    CaptureSource source,
    AttachmentKind kind,
  );

  Future<List<CapturedImage>> pickMany({int limit = 6});
}

class _CoreImagePicker implements CmImagePicker {
  const _CoreImagePicker();

  @override
  Future<CapturedImage?> pick(
    BuildContext context,
    CaptureSource source,
    AttachmentKind kind,
  ) => ImageCapture.pick(source: source, kind: kind, context: context);

  @override
  Future<List<CapturedImage>> pickMany({int limit = 6}) =>
      ImageCapture.pickMany(limit: limit);
}

final cmImagePickerProvider = Provider<CmImagePicker>(
  (ref) => const _CoreImagePicker(),
);
