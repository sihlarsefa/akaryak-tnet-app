import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Gerçek yazı tipleri bulunur mu: arayüzün Plus Jakarta Sans dosyaları (`assets/fonts/jakarta/`) ya
/// da Flutter SDK önbelleğindeki Roboto. Testin `skip` değeri için eşzamanlı.
bool realFontsAvailable() => uiFontAvailable() || _robotoAvailable();

/// Arayüz yazı tipi Plus Jakarta Sans (tasarım v3 §1) depoda mı.
bool uiFontAvailable() {
  final dir = _jakartaDir();
  return dir != null &&
      File(
        '${dir.path}${Platform.pathSeparator}PlusJakartaSans-Regular.ttf',
      ).existsSync();
}

/// Eski ad (tasarım v2): artık arayüz yazı tipine bakar ([uiFontAvailable]).
bool monaSansAvailable() => uiFontAvailable();

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

/// Paket kökü (testler paket kökünde çalışır; yine de yukarı doğru `pubspec.yaml` aranır).
Directory? _packageRoot() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    final sep = Platform.pathSeparator;
    if (File('${dir.path}${sep}pubspec.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

/// `assets/fonts/jakarta/`.
Directory? _jakartaDir() {
  final root = _packageRoot();
  if (root == null) return null;
  final sep = Platform.pathSeparator;
  final dir = Directory([root.path, 'assets', 'fonts', 'jakarta'].join(sep));
  return dir.existsSync() ? dir : null;
}

/// phosphor_flutter paketinin `lib/fonts/` klasörü (`.dart_tool/package_config.json`'dan).
Directory? _phosphorFontDir() {
  final root = _packageRoot();
  if (root == null) return null;
  final sep = Platform.pathSeparator;
  final config = File(
    [root.path, '.dart_tool', 'package_config.json'].join(sep),
  );
  if (!config.existsSync()) return null;
  final packages =
      (jsonDecode(config.readAsStringSync())
              as Map<String, dynamic>)['packages']
          as List<dynamic>;
  for (final p in packages.cast<Map<String, dynamic>>()) {
    if (p['name'] != 'phosphor_flutter') continue;
    final rootUri = Uri.parse(p['rootUri'] as String);
    final base = rootUri.isAbsolute
        ? rootUri.toFilePath()
        : config.parent.uri.resolveUri(rootUri).toFilePath();
    final dir = Directory([base, 'lib', 'fonts'].join(sep));
    return dir.existsSync() ? dir : null;
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

/// Arayüz yazı tipi `PlusJakartaSans` (400–800), uygulamanın kullandığı aile adıyla. Varsayılan
/// test yazı tipi her harfi 1 em kare çizer; ölçü ve ekran görüntüsü testleri cihazdaki yüzü görmek
/// için bunu yükler. Dosyalar bulunamazsa false.
Future<bool> loadUiFont() async {
  final dir = _jakartaDir();
  if (dir == null) return false;
  return _family(dir, 'PlusJakartaSans', const [
    'PlusJakartaSans-Regular.ttf',
    'PlusJakartaSans-Medium.ttf',
    'PlusJakartaSans-SemiBold.ttf',
    'PlusJakartaSans-Bold.ttf',
    'PlusJakartaSans-ExtraBold.ttf',
  ]);
}

/// Eski ad (tasarım v2): artık arayüz yazı tipini yükler ([loadUiFont]).
Future<bool> loadMonaSans() => loadUiFont();

/// Phosphor simge yazı tipleri (Regular, Fill, Bold), paket yazı tipi adlarıyla
/// (`packages/phosphor_flutter/Phosphor…`). Bulunamazsa false.
Future<bool> loadPhosphorIcons() async {
  final dir = _phosphorFontDir();
  if (dir == null) return false;
  const prefix = 'packages/phosphor_flutter/';
  final regular = await _family(dir, '${prefix}PhosphorRegular', const [
    'Phosphor.ttf',
  ]);
  await _family(dir, '${prefix}PhosphorFill', const ['Phosphor-Fill.ttf']);
  await _family(dir, '${prefix}PhosphorBold', const ['Phosphor-Bold.ttf']);
  return regular;
}

/// Gerçek yazı tipleri: Plus Jakarta Sans (arayüz), Phosphor simgeleri, Roboto (PDF'ler ve eski
/// ölçüler) ve Material simgeleri (Flutter SDK önbelleğinden). Düğme etiketinin satıra sığıp
/// sığmadığını ölçen testler cihazdakine yakın ölçü için bunu yükler. Hiçbir gerçek yazı tipi
/// bulunamazsa false.
Future<bool> loadRealFonts() async {
  final ui = await loadUiFont();
  await loadPhosphorIcons();
  final dir = _fontDir();
  if (dir == null) return ui;
  final roboto = await _family(dir, 'Roboto', const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await _family(dir, 'MaterialIcons', const ['MaterialIcons-Regular.otf']);
  return ui || roboto;
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
