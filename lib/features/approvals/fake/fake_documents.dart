/// Sahte kipte belge görselleri: gerçek PNG / PDF baytları (küçük resimler ve görüntüleyici çalışsın).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Belge görünümlü PNG (beyaz kâğıt, renkli başlık şeridi, satır çizgileri). [accent] 0xRRGGBB.
Uint8List fakeDocumentPng({int accent = 0x1F2A37, int lines = 7}) {
  final w = 240;
  final h = 320;
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(250, 250, 248));
  final r = (accent >> 16) & 0xFF;
  final g = (accent >> 8) & 0xFF;
  final b = accent & 0xFF;
  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: w,
    y2: 46,
    color: img.ColorRgb8(r, g, b),
  );
  // Logo yerine turuncu kare (» işareti kutusu).
  img.fillRect(
    image,
    x1: 16,
    y1: 12,
    x2: 38,
    y2: 34,
    color: img.ColorRgb8(255, 80, 1),
  );
  for (var i = 0; i < lines; i++) {
    final y = 72 + i * 30;
    final end = i.isEven ? w - 28 : w - 80;
    img.fillRect(
      image,
      x1: 20,
      y1: y,
      x2: end,
      y2: y + 8,
      color: img.ColorRgb8(203, 213, 225),
    );
  }
  // İmza alanı.
  img.drawLine(
    image,
    x1: 140,
    y1: h - 40,
    x2: w - 20,
    y2: h - 40,
    color: img.ColorRgb8(100, 116, 139),
    thickness: 2,
  );
  return Uint8List.fromList(img.encodePng(image, level: 1));
}

/// En küçük geçerli tek sayfalık PDF (görüntüleyici ve paylaş için).
Uint8List fakeMinimalPdf(String title) {
  const ascii = {
    'ç': 'c', 'Ç': 'C', 'ğ': 'g', 'Ğ': 'G', 'ı': 'i', 'İ': 'I', //
    'ö': 'o', 'Ö': 'O', 'ş': 's', 'Ş': 'S', 'ü': 'u', 'Ü': 'U',
  };
  final buf = StringBuffer();
  for (final ch in title.split('')) {
    final mapped = ascii[ch] ?? ch;
    buf.write(mapped.codeUnitAt(0) < 128 ? mapped : '?');
  }
  final safe = buf.toString().replaceAll(RegExp(r'[()\\]'), ' ');
  final content = 'BT /F1 18 Tf 72 720 Td ($safe) Tj ET';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(latin1.encode(out.toString()));
}
