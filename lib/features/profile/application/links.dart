import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/env/app_config_controller.dart';
import '../../../core/env/app_env.dart';
import '../../../core/utils/external_activity.dart';
import '../../../core/utils/log.dart';
import '../../../core/utils/validators.dart';

/// Bağlantı açar: yasal metinler uygulama içi tarayıcıda, arama / WhatsApp / e-posta dış uygulamada.
/// Açılamazsa `false` (ekran "Bağlantı açılamadı" der). Testler ezer.
typedef ProfileLinkOpener = Future<bool> Function(Uri uri, {bool external});

final profileLinkOpenerProvider = Provider<ProfileLinkOpener>((ref) => _open);

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

/// Yasal metinlerin adresleri (spec A.4 A8 "Yasal"): `app/config` legal; boşsa API'nin kendi
/// `/legal/{belge}` sayfaları (sunucu da aynı yedeği kullanır). Yapay zekâ aydınlatma metni
/// `/legal/ai`.
@immutable
class LegalUris {
  const LegalUris({
    required this.privacy,
    required this.kvkk,
    required this.terms,
    required this.ai,
    required this.accountDeletion,
    required this.support,
  });

  final Uri privacy;
  final Uri kvkk;
  final Uri terms;
  final Uri ai;
  final Uri accountDeletion;
  final Uri support;
}

final legalUrisProvider = Provider<LegalUris>((ref) {
  final env = ref.watch(appEnvProvider);
  final legal = ref.watch(appConfigProvider.select((c) => c.legal));
  Uri pick(String? configured, String doc) =>
      SupportUris.web(configured) ?? Uri.parse('${env.apiBaseUrl}legal/$doc');
  return LegalUris(
    privacy: pick(legal.privacyUrl, 'privacy'),
    kvkk: pick(legal.kvkkUrl, 'kvkk'),
    terms: pick(legal.termsUrl, 'terms'),
    ai: pick(null, 'ai'),
    accountDeletion: pick(null, 'account-deletion'),
    support: pick(null, 'support'),
  );
});

/// Destek kanallarının adresleri.
abstract final class SupportUris {
  /// `tel:` (boşluk ve ayraçlar atılır; `+` korunur).
  static Uri? phone(String? raw) {
    final v = raw?.replaceAll(RegExp(r'[^\d+]'), '') ?? '';
    return v.isEmpty ? null : Uri(scheme: 'tel', path: v);
  }

  /// `https://wa.me/90XXXXXXXXXX`.
  static Uri? whatsapp(String? raw) {
    var d = Validators.digitsOnly(raw);
    if (d.isEmpty) return null;
    if (d.length == 11 && d.startsWith('0')) d = '90${d.substring(1)}';
    if (d.length == 10) d = '90$d';
    return Uri.parse('https://wa.me/$d');
  }

  /// `mailto:` (konu `%20` ile kodlanır).
  static Uri? email(String? raw, {String? subject}) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty || !v.contains('@')) return null;
    final s = subject == null ? '' : '?subject=${Uri.encodeComponent(subject)}';
    return Uri.parse('mailto:$v$s');
  }

  /// `http(s)` adresi; geçersizse null.
  static Uri? web(String? raw) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty) return null;
    final u = Uri.tryParse(v);
    if (u == null || !(u.scheme == 'https' || u.scheme == 'http')) return null;
    return u;
  }
}
