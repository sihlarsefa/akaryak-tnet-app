import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/external_activity.dart';
import '../../../core/utils/log.dart';
import '../../../core/utils/validators.dart';

/// Bağlantı açar: yasal metinler ve portal sayfaları uygulama içi tarayıcıda, arama / WhatsApp / e-posta /
/// mağaza dış uygulamada. Açılamazsa `false` döner (ekran "Bağlantı açılamadı" der). Testler ezer.
typedef LinkOpener = Future<bool> Function(Uri uri, {bool external});

final linkOpenerProvider = Provider<LinkOpener>((ref) => _open);

Future<bool> _open(Uri uri, {bool external = false}) async {
  try {
    return await launchExternal(
      uri,
      mode: external
          ? LaunchMode.externalApplication
          : LaunchMode.inAppBrowserView,
    );
  } catch (e) {
    AppLog.debug('Bağlantı açılamadı (${uri.scheme}): ${e.runtimeType}');
    return false;
  }
}

/// Destek bağlantıları (spec A.4 A1 "Hesabım yok").
abstract final class SupportLinks {
  /// `tel:` (boşluk ve ayraçlar atılır; `+` korunur).
  static Uri? phone(String? raw) {
    final v = raw?.replaceAll(RegExp(r'[^\d+]'), '') ?? '';
    return v.isEmpty ? null : Uri(scheme: 'tel', path: v);
  }

  /// `https://wa.me/90XXXXXXXXXX` (yerel 0'lı ya da 10 haneli numara ülke koduna çevrilir).
  static Uri? whatsapp(String? raw) {
    var d = Validators.digitsOnly(raw);
    if (d.isEmpty) return null;
    if (d.length == 11 && d.startsWith('0')) d = '90${d.substring(1)}';
    if (d.length == 10) d = '90$d';
    return Uri.parse('https://wa.me/$d');
  }

  /// `mailto:` (konu `%20` ile kodlanır; bazı e-posta uygulamaları `+` işaretini olduğu gibi gösterir).
  static Uri? email(String? raw, {String? subject}) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty || !v.contains('@')) return null;
    final s = subject == null ? '' : '?subject=${Uri.encodeComponent(subject)}';
    return Uri.parse('mailto:$v$s');
  }

  /// `http(s)` bağlantısı; geçersizse null.
  static Uri? web(String? raw) {
    final v = raw?.trim() ?? '';
    final u = Uri.tryParse(v);
    if (u == null || !(u.scheme == 'https' || u.scheme == 'http')) return null;
    return u;
  }
}
