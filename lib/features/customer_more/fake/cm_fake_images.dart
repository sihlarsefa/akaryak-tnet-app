import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Sahte kipte teslim kanıtı görselleri (yalnızca demo verisi; ağdan indirilmez). Deterministiktir.
abstract final class CmFakeImages {
  static final Map<int, Uint8List> _photos = {};
  static Uint8List? _signature;

  /// Teslimat fotoğrafı: gökyüzü, tank, hortum (JPEG, 480×360).
  static Uint8List deliveryPhoto(int seed) => _photos.putIfAbsent(seed, () {
    final r = math.Random(seed);
    final im = img.Image(width: 480, height: 360);
    // Gökyüzü → zemin
    for (var y = 0; y < 360; y++) {
      final t = y / 360;
      final c = y < 220
          ? img.ColorRgb8(
              (176 + 40 * t).round(),
              (200 + 30 * t).round(),
              (226 + 20 * t).round(),
            )
          : img.ColorRgb8(120 + r.nextInt(6), 124, 118);
      img.drawLine(im, x1: 0, y1: y, x2: 479, y2: y, color: c);
    }
    // Tank gövdesi
    final x0 = 70 + r.nextInt(40);
    img.fillRect(
      im,
      x1: x0,
      y1: 120,
      x2: x0 + 260,
      y2: 250,
      radius: 40,
      color: img.ColorRgb8(226, 232, 240),
    );
    img.fillRect(
      im,
      x1: x0 + 18,
      y1: 168,
      x2: x0 + 242,
      y2: 182,
      color: img.ColorRgb8(201, 76, 12),
    );
    // Ayaklar
    for (final dx in [40, 210]) {
      img.fillRect(
        im,
        x1: x0 + dx,
        y1: 250,
        x2: x0 + dx + 14,
        y2: 290,
        color: img.ColorRgb8(71, 85, 105),
      );
    }
    // Hortum ve dolum ağzı
    img.drawLine(
      im,
      x1: x0 + 250,
      y1: 150,
      x2: 440,
      y2: 300,
      color: img.ColorRgb8(15, 23, 42),
      thickness: 6,
    );
    img.fillCircle(
      im,
      x: x0 + 250,
      y: 150,
      radius: 9,
      color: img.ColorRgb8(31, 42, 55),
    );
    return img.encodeJpg(im, quality: 72);
  });

  /// İmza: beyaz zemin, lacivert mürekkep (PNG, 600×200).
  static Uint8List signature() => _signature ??= () {
    final im = img.Image(width: 600, height: 200);
    img.fill(im, color: img.ColorRgb8(255, 255, 255));
    final ink = img.ColorRgb8(15, 23, 42);
    var px = 60;
    var py = 120;
    for (var i = 0; i <= 120; i++) {
      final t = i / 120;
      final x = (60 + 470 * t).round();
      final y = (120 - 45 * math.sin(t * math.pi * 3) * (1 - t * 0.6) - 10 * t)
          .round();
      img.drawLine(im, x1: px, y1: py, x2: x, y2: y, color: ink, thickness: 3);
      px = x;
      py = y;
    }
    img.drawLine(im, x1: 80, y1: 160, x2: 520, y2: 150, color: ink);
    return img.encodePng(im);
  }();
}
