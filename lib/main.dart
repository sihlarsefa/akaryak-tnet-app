import 'bootstrap.dart';
import 'core/ui/typography.dart';

/// AkaryakıtNet — bayi ve müşteriler için akaryakıt sipariş, teklif ve teslimat uygulaması.
///
/// Çalıştırma: `flutter run --dart-define-from-file=env/dev.json` (sahte API) ya da
/// `env/test.json` (test sunucusu). Tanım verilmezse geliştirme + sahte API açılır.
Future<void> main() {
  registerFontLicenses();
  return bootstrap();
}

/// Arayüz yazı tipi Archivo'nun lisansı (SIL OFL 1.1) "Lisanslar" sayfasında görünsün
/// (tasarım v3 §1). Toplayıcı yalnızca lisanslar istendiğinde çalışır.
void registerFontLicenses() => AknFonts.registerLicense();
