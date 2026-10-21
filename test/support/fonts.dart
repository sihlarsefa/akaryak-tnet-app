import 'dart:io';

import 'package:flutter/services.dart';

/// Gerçek yazı tipleri bulunur mu: arayüzün Mona Sans dosyaları (`assets/fonts/mona/`) ya da Flutter
/// SDK önbelleğindeki Roboto. Testin `skip` değeri için eşzamanlı.
bool realFontsAvailable() => monaSansAvailable() || _robotoAvailable();

/// Arayüz yazı tipi Mona Sans (tasarım v2 §3.1) depoda mı.
bool monaSansAvailable() {
  final dir = _monaDir();
  return dir != null &&
      File(
        '${dir.path}${Platform.pathSeparator}MonaSans-Regular.ttf',
      ).existsSync();
}

bool _robotoAvailable() {
  final dir = _fontDir();
  return dir != null &&
      File(
        '${dir.path}${Platform.pathSeparator}Roboto-Medium.ttf',
      ).existsSync();
}

Directory? _fontDir() {
  final root = _flutterRoot();
  if (root == null) return null;
  final dir = Directory(
    [
      root,
      'bin',
      'cache',
      'artifacts',
      'material_fonts',
    ].join(Platform.pathSeparator),
  );
  return dir.existsSync() ? dir : null;
}

/// `assets/fonts/mona/` (testler paket kökünde çalışır; yine de yukarı doğru `pubspec.yaml` aranır).
Directory? _monaDir() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    final sep = Platform.pathSeparator;
    if (File('${dir.path}${sep}pubspec.yaml').existsSync()) {
      final mona = Directory([dir.path, 'assets', 'fonts', 'mona'].join(sep));
      return mona.existsSync() ? mona : null;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

Future<bool> _family(Directory dir, String name, List<String> files) async {
  final loader = FontLoader(name);
  var any = false;
  for (final f in files) {
    final file = File('${dir.path}${Platform.pathSeparator}$f');
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    any = true;
  }
  if (any) await loader.load();
  return any;
}

/// Arayüz yazı tipleri: `MonaSans` (400–700) ve `MonaSansCondensed` (600–800), uygulamanın
/// kullandığı aile adlarıyla. Varsayılan test yazı tipi her harfi 1 em kare çizer; ölçü ve ekran
/// görüntüsü testleri cihazdaki yüzü görmek için bunu yükler. Dosyalar bulunamazsa false.
Future<bool> loadMonaSans() async {
  final dir = _monaDir();
  if (dir == null) return false;
  final sans = await _family(dir, 'MonaSans', const [
    'MonaSans-Regular.ttf',
    'MonaSans-Medium.ttf',
    'MonaSans-SemiBold.ttf',
    'MonaSans-Bold.ttf',
  ]);
  final condensed = await _family(dir, 'MonaSansCondensed', const [
    'MonaSansCondensed-SemiBold.ttf',
    'MonaSansCondensed-Bold.ttf',
    'MonaSansCondensed-ExtraBold.ttf',
  ]);
  return sans && condensed;
}

/// Gerçek yazı tipleri: Mona Sans (arayüz), Roboto (PDF'ler ve eski ölçüler) ve Material
/// simgeleri (Flutter SDK önbelleğinden). Düğme etiketinin satıra sığıp sığmadığını ölçen testler
/// cihazdakine yakın ölçü için bunu yükler. Hiçbir gerçek yazı tipi bulunamazsa false.
Future<bool> loadRealFonts() async {
  final mona = await loadMonaSans();
  final dir = _fontDir();
  if (dir == null) return mona;
  final roboto = await _family(dir, 'Roboto', const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await _family(dir, 'MaterialIcons', const ['MaterialIcons-Regular.otf']);
  return mona || roboto;
}

String? _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  // …/bin/cache/artifacts/engine/<platform>/flutter_tester
  final exe = File(Platform.resolvedExecutable).absolute.path;
  final marker = ['', 'bin', 'cache', ''].join(Platform.pathSeparator);
  final i = exe.indexOf(marker);
  return i < 0 ? null : exe.substring(0, i);
}
