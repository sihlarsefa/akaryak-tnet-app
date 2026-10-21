import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/turkish_text.dart';

/// Ortam: geliştirme (sahte API), test sunucusu, canlı.
enum AknEnv {
  dev('Geliştirme'),
  test('Test'),
  prod('Canlı');

  const AknEnv(this.label);
  final String label;

  static AknEnv parse(String value) => switch (value.trim().asciiLower) {
    'prod' || 'production' => AknEnv.prod,
    'test' => AknEnv.test,
    _ => AknEnv.dev,
  };
}

/// API kipi: `fake` = uygulama içi sahte sunucu (ağ yok), `live` = gerçek API.
enum ApiMode {
  fake,
  live;

  static ApiMode parse(String value) =>
      value.trim().asciiLower == 'live' ? ApiMode.live : ApiMode.fake;
}

/// Sahte API bu derlemeye girer mi (derleme zamanı koruması, spec D.7). `API_MODE=live` ya da
/// `AKN_ENV=prod` ile derlenen uygulamada sahte sunucu ve demo hesapları derlemeye hiç girmez (ağaç
/// sallama); yanlış bir ortam dosyası canlı derlemede sahte kipi açamaz.
const bool kFakeApiCompiled =
    String.fromEnvironment('API_MODE', defaultValue: 'fake') != 'live' &&
    String.fromEnvironment('AKN_ENV', defaultValue: 'dev') != 'prod';

/// Derleme ortamı (spec C.1). Değerler `--dart-define-from-file=env/<ortam>.json` ile gelir:
/// `AKN_ENV`, `API_BASE_URL`, `API_MODE`, `PORTAL_BASE_URL`, `MAPS_ENABLED`. Gizli değer içermez.
/// Hiç tanım verilmezse (`flutter run`) geliştirme + sahte API ile açılır.
@immutable
class AppEnv {
  const AppEnv({
    required this.env,
    required this.apiBaseUrl,
    required this.apiMode,
    required this.portalBaseUrl,
    this.mapsEnabled = false,
  });

  factory AppEnv.fromEnvironment() {
    const env = String.fromEnvironment('AKN_ENV', defaultValue: 'dev');
    const api = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:3108/',
    );
    const mode = String.fromEnvironment('API_MODE', defaultValue: 'fake');
    const portal = String.fromEnvironment(
      'PORTAL_BASE_URL',
      defaultValue: 'http://localhost:3107/',
    );
    const maps = bool.fromEnvironment('MAPS_ENABLED');
    final parsedEnv = AknEnv.parse(env);
    return AppEnv(
      env: parsedEnv,
      apiBaseUrl: _withSlash(api),
      // Canlı ortamda ve canlı derlemede sahte API asla açılmaz.
      apiMode: parsedEnv == AknEnv.prod || !kFakeApiCompiled
          ? ApiMode.live
          : ApiMode.parse(mode),
      portalBaseUrl: _withSlash(portal),
      mapsEnabled: maps,
    );
  }

  /// Testler için sahte kipte ortam.
  static const fakeForTests = AppEnv(
    env: AknEnv.dev,
    apiBaseUrl: 'http://fake.akaryakitnet.local/',
    apiMode: ApiMode.fake,
    portalBaseUrl: 'http://fake.akaryakitnet.local/',
  );

  static String _withSlash(String url) {
    final u = url.trim();
    return u.endsWith('/') ? u : '$u/';
  }

  final AknEnv env;

  /// API kökü (sonu `/`), ör. `http://134.149.201.54:3108/`.
  final String apiBaseUrl;
  final ApiMode apiMode;

  /// Web portalı kökü (sonu `/`): "Şifremi unuttum" ve yasal bağlantılar.
  final String portalBaseUrl;

  /// Google Maps yalnızca anahtar tanımlı derlemelerde açılır; kapalıyken adres ve "Yol tarifi" gösterilir.
  final bool mapsEnabled;

  bool get isFake => apiMode == ApiMode.fake;
  bool get isProd => env == AknEnv.prod;
  bool get isDev => env == AknEnv.dev;

  /// Mobil API v1 kökü: `<apiBaseUrl>api/v1/`.
  String get apiV1Url => '${apiBaseUrl}api/v1/';

  /// "Şifremi unuttum" (web portalı).
  Uri get forgotPasswordUrl =>
      Uri.parse('${portalBaseUrl}Account/ForgotPassword');

  /// Profil → Hakkında rozeti: "Test, sahte API".
  String get badge => isFake ? '${env.label}, sahte API' : env.label;

  /// Canlı olmayan derlemelerde köşedeki şerit: sahte veride "DEMO", test sunucusunda "TEST" (canlıda
  /// yok).
  String? get ribbon => isProd ? null : (isFake ? 'DEMO' : 'TEST');

  /// Yapılandırma denetimi (spec C.1, D.7). Canlı ortam canlı API ve HTTPS ister; örnek alan adı
  /// (`*.example`) canlıda kabul edilmez. Sorun yoksa boş liste.
  List<String> validate() {
    final problems = <String>[];
    final api = Uri.tryParse(apiBaseUrl);
    final portal = Uri.tryParse(portalBaseUrl);
    if (api == null || !api.hasScheme || api.host.isEmpty) {
      problems.add('API_BASE_URL geçersiz: $apiBaseUrl');
    }
    if (portal == null || !portal.hasScheme || portal.host.isEmpty) {
      problems.add('PORTAL_BASE_URL geçersiz: $portalBaseUrl');
    }
    if (isProd) {
      if (isFake) problems.add('Canlı ortamda sahte API kullanılamaz.');
      if (api != null && api.scheme != 'https') {
        problems.add('Canlı ortamda API adresi HTTPS olmalı.');
      }
      if (portal != null && portal.scheme != 'https') {
        problems.add('Canlı ortamda portal adresi HTTPS olmalı.');
      }
      for (final u in [api, portal]) {
        if (u != null && u.host.endsWith('.example')) {
          problems.add(
            'Canlı adres tanımlanmamış (örnek alan adı: ${u.host}).',
          );
        }
      }
    } else if (env == AknEnv.test && isFake) {
      problems.add('Test ortamı canlı API ile çalışmalı (API_MODE=live).');
    }
    return problems;
  }

  @override
  String toString() => 'AppEnv(${env.name}, ${apiMode.name}, $apiBaseUrl)';
}

/// Derleme ortamı. `bootstrap` gerçek değerle geçersiz kılar; testler [AppEnv.fakeForTests] verir.
final appEnvProvider = Provider<AppEnv>((ref) => AppEnv.fromEnvironment());
