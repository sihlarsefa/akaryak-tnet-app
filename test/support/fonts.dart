import 'dart:io';

import 'package:flutter/services.dart';

/// Gerçek Roboto (Flutter SDK önbelleğinde) bulunur mu. Testin `skip` değeri için eşzamanlı.
bool realFontsAvailable() {
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

/// Gerçek Roboto ve Material simgeleri (Flutter SDK önbelleğinden). Varsayılan test yazı tipi her
/// harfi 1 em genişlikte çizer; düğme etiketinin satıra sığıp sığmadığını ölçen testler cihazdakine
/// yakın ölçü için bunu yükler. Yazı tipleri bulunamazsa false.
Future<bool> loadRealFonts() async {
  final dir = _fontDir();
  if (dir == null) return false;
  Future<bool> family(String name, List<String> files) async {
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

  final roboto = await family('Roboto', const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await family('MaterialIcons', const ['MaterialIcons-Regular.otf']);
  return roboto;
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
