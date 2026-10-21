import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/media/image_capture.dart';
import '../../../core/utils/external_activity.dart';
import '../../../core/utils/log.dart';

/// Fotoğraf alma sonucu.
enum CaptureStatus { ok, cancelled, denied, failed }

@immutable
class CaptureResult {
  const CaptureResult._(this.status, [this.paths = const []]);

  const CaptureResult.ok(List<String> paths) : this._(CaptureStatus.ok, paths);
  const CaptureResult.cancelled() : this._(CaptureStatus.cancelled);
  const CaptureResult.denied() : this._(CaptureStatus.denied);
  const CaptureResult.failed() : this._(CaptureStatus.failed);

  final CaptureStatus status;

  /// Geçici klasördeki sıkıştırılmış JPEG yolları (kalıcı klasöre taşınmalı).
  final List<String> paths;
}

/// Teslim fotoğrafı: kamera ya da galeri → sıkıştırılmış JPEG (uzun kenar ≤ 1600, kalite 80, EXIF
/// silinir; `ImageCapture.prepare`). Kamera izni reddedildiyse [CaptureStatus.denied] döner, ekran
/// "Ayarları aç" kartını gösterir. Testler sahte bir uygulamayla değiştirir.
abstract class DriverCamera {
  Future<CaptureResult> takePhoto();

  Future<CaptureResult> pickFromGallery({int limit = 6});

  /// iOS'ta kamera ilk açılışta sistem izni sorar (ön sayfa gerekir); Android'de sistem kamerası izin
  /// istemez.
  bool get needsCameraPrimer;
}

class ImagePickerDriverCamera implements DriverCamera {
  ImagePickerDriverCamera();

  final ImagePicker _picker = ImagePicker();

  static String _name() =>
      'teslimat-${DateTime.now().millisecondsSinceEpoch}.jpg';

  @override
  bool get needsCameraPrimer => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<CaptureResult> takePhoto() async {
    try {
      // Kameradan dönüş biyometrik kilidi tetiklemez.
      final file = await ExternalActivity.run(
        () => _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: ImageCapture.maxEdge.toDouble(),
          maxHeight: ImageCapture.maxEdge.toDouble(),
          imageQuality: 95,
          requestFullMetadata: false,
        ),
      );
      if (file == null) return const CaptureResult.cancelled();
      final image = await ImageCapture.prepare(file.path, fileName: _name());
      if (image == null) return const CaptureResult.failed();
      return CaptureResult.ok([image.path]);
    } on PlatformException catch (e) {
      AppLog.warn('Kamera açılamadı (${e.code})');
      return e.code == 'camera_access_denied'
          ? const CaptureResult.denied()
          : const CaptureResult.failed();
    } catch (e) {
      AppLog.warn('Kamera açılamadı', error: e);
      return const CaptureResult.failed();
    }
  }

  @override
  Future<CaptureResult> pickFromGallery({int limit = 6}) async {
    try {
      final images = await ImageCapture.pickMany(limit: limit);
      if (images.isEmpty) return const CaptureResult.cancelled();
      return CaptureResult.ok([for (final i in images) i.path]);
    } catch (e) {
      AppLog.warn('Galeri açılamadı', error: e);
      return const CaptureResult.failed();
    }
  }
}

final driverCameraProvider = Provider<DriverCamera>(
  (ref) => ImagePickerDriverCamera(),
);
