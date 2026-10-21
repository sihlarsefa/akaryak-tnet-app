import 'dart:convert';
import 'dart:typed_data';

import '../../utils/turkish_text.dart';

/// Sahte sunucuya gelen çok parçalı formun dosyası.
class FakeFile {
  const FakeFile({
    required this.field,
    required this.fileName,
    required this.contentType,
    required this.bytes,
  });
  final String field;
  final String fileName;
  final String contentType;
  final Uint8List bytes;
}

/// Çözülmüş `multipart/form-data` gövdesi (yalnızca sahte API için; küçük ve basit).
class FakeMultipart {
  const FakeMultipart({this.fields = const {}, this.files = const []});

  final Map<String, String> fields;
  final List<FakeFile> files;

  FakeFile? file(String field) {
    for (final f in files) {
      if (f.field == field) return f;
    }
    return null;
  }

  /// `Content-Type: multipart/form-data; boundary=…` başlığı ve ham bayttan çözer.
  static FakeMultipart? tryParse(String? contentType, Uint8List bytes) {
    if (contentType == null ||
        !contentType.asciiLower.contains('multipart/form-data')) {
      return null;
    }
    final m = RegExp(r'boundary=("?)([^";]+)\1').firstMatch(contentType);
    if (m == null) return null;
    final boundary = ascii.encode('--${m[2]}');
    final fields = <String, String>{};
    final files = <FakeFile>[];

    var pos = _indexOf(bytes, boundary, 0);
    while (pos >= 0) {
      var start = pos + boundary.length;
      // Son sınır: "--"
      if (start + 1 < bytes.length &&
          bytes[start] == 45 &&
          bytes[start + 1] == 45) {
        break;
      }
      if (start + 1 < bytes.length &&
          bytes[start] == 13 &&
          bytes[start + 1] == 10) {
        start += 2;
      }
      final next = _indexOf(bytes, boundary, start);
      if (next < 0) break;
      var end = next;
      if (end >= 2 && bytes[end - 2] == 13 && bytes[end - 1] == 10) end -= 2;
      final part = Uint8List.sublistView(bytes, start, end);
      final headerEnd = _indexOf(part, ascii.encode('\r\n\r\n'), 0);
      if (headerEnd >= 0) {
        final headerText = utf8.decode(
          part.sublist(0, headerEnd),
          allowMalformed: true,
        );
        final content = Uint8List.fromList(part.sublist(headerEnd + 4));
        final headers = <String, String>{};
        for (final line in headerText.split('\r\n')) {
          final i = line.indexOf(':');
          if (i > 0) {
            headers[line.substring(0, i).trim().asciiLower] = line
                .substring(i + 1)
                .trim();
          }
        }
        final disposition = headers['content-disposition'] ?? '';
        final name =
            RegExp(r'name="([^"]*)"').firstMatch(disposition)?[1] ?? '';
        final fileName = RegExp(
          r'filename="([^"]*)"',
        ).firstMatch(disposition)?[1];
        if (fileName != null) {
          files.add(
            FakeFile(
              field: name,
              fileName: fileName,
              contentType:
                  headers['content-type'] ?? 'application/octet-stream',
              bytes: content,
            ),
          );
        } else {
          fields[name] = utf8.decode(content, allowMalformed: true);
        }
      }
      pos = next;
    }
    return FakeMultipart(fields: fields, files: files);
  }

  static int _indexOf(List<int> data, List<int> pattern, int from) {
    outer:
    for (var i = from; i <= data.length - pattern.length; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
