import 'package:url_launcher/url_launcher.dart';

/// Uygulamanın kendisinin açtığı dış etkinlikler (kamera, galeri, paylaşım sayfası, tarayıcı, harita,
/// telefon): bunlardan dönüş biyometrik kilidi tetiklemez ve gizlilik örtüsü gösterilmez (spec D.7).
///
/// ```dart
/// final file = await ExternalActivity.run(() => picker.pickImage(...));
/// await launchExternal(uri);
/// ```
///
/// `launchUrl` dış uygulama açılır açılmaz döner; kullanıcının dönüşü daha sonradır. Bu yüzden bir
/// etkinlik bittikten sonraki kısa süre ([trailing]) de "dış etkinlik" sayılır; o sırada başlayan arka
/// plan süresi kilit için daha uzun bir hoşgörüyle ölçülür (bkz. `SessionController`).
abstract final class ExternalActivity {
  /// Etkinlik bittikten sonra uygulamanın arka plana geçmesi için tanınan süre.
  static const trailing = Duration(seconds: 3);

  static int _depth = 0;
  static DateTime? _lastEnded;

  /// Testler saati değiştirebilir.
  static DateTime Function() clock = DateTime.now;

  /// Şu an (ya da az önce) uygulamanın açtığı bir dış etkinlik var mı.
  static bool get active {
    if (_depth > 0) return true;
    final last = _lastEnded;
    return last != null && clock().difference(last) < trailing;
  }

  /// [action] çalışırken (ve bittikten sonra [trailing] boyunca) dış etkinlik işaretlenir.
  static Future<T> run<T>(Future<T> Function() action) async {
    _depth++;
    try {
      return await action();
    } finally {
      _depth--;
      _lastEnded = clock();
    }
  }

  /// Senkron işaret (paylaşım sayfası gibi sonucu beklenmeyen çağrılar için).
  static void mark() => _lastEnded = clock();

  /// Testler için.
  static void reset() {
    _depth = 0;
    _lastEnded = null;
  }
}

/// `launchUrl` + [ExternalActivity] (telefon, WhatsApp, e-posta, harita, tarayıcı).
Future<bool> launchExternal(
  Uri uri, {
  LaunchMode mode = LaunchMode.platformDefault,
}) => ExternalActivity.run(() => launchUrl(uri, mode: mode));
