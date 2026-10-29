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

const String _aknEnvDefine = String.fromEnvironment(
  'AKN_ENV',
  defaultValue: 'dev',
);

/// Sahte API (uygulama içi sahte sunucu, demo personaları, demo kartları) bu derlemeye girer mi
/// (derleme zamanı koruması, spec D.7). `AKN_ENV=prod` ile derlenen uygulamaya hiç girmez (ağaç
/// sallama); yanlış bir ortam dosyası canlı derlemede sahte kipi ya da demo oturumunu açamaz. Test
/// derlemesi (`AKN_ENV=test`, `API_MODE=live`) sahte sunucuyu taşır: açılış canlı API ile, demo kartı
/// yalnızca o oturum için sahte dünyaya geçer ([FakeApiPolicy.onDemand]). Çalışma anı kararı
/// [fakeApiPolicyFor]'dadır (ayrıştırılmış ortamla; ` prod ` gibi boşluklu yazımlar da canlı sayılır).
/// Kural [fakeApiCompiledFor] ile aynıdır; testler sabiti bu sürecin tanımıyla karşılaştırır.
const bool kFakeApiCompiled =
    _aknEnvDefine != 'prod' &&
    _aknEnvDefine != 'production' &&
    _aknEnvDefine != 'PROD' &&
    _aknEnvDefine != 'Prod' &&
    _aknEnvDefine != 'PRODUCTION' &&
    _aknEnvDefine != 'Production';

/// [kFakeApiCompiled] kuralının saf eşi (testler dart-define değiştiremez): `AKN_ENV` tanımı canlı ortamı
/// adlandırmıyorsa sahte sunucu derlenir. Sabit ifadede harf dönüşümü olmadığından büyük harfli
/// yazımlar tek tek sayılır.
bool fakeApiCompiledFor(String aknEnvDefine) => !const {
  'prod',
  'production',
  'PROD',
  'Prod',
  'PRODUCTION',
  'Production',
}.contains(aknEnvDefine);

/// Sahte API'nin bir derlemedeki yeri.
enum FakeApiPolicy {
  /// Hiç yok (canlı derleme `AKN_ENV=prod`, ya da sahte sunucusu derlenmemiş): sahte sunucu, demo
  /// personaları ve demo kartları yok.
  none,

  /// Uygulama canlı API ile açılır; giriş ekranındaki demo kartı yalnızca o oturum için uygulama içi sahte
  /// dünyaya geçer (test derlemesi, TestFlight: `AKN_ENV=test`, `API_MODE=live`).
  onDemand,

  /// Baştan sahte kip (geliştirme ve demo derlemesi: `API_MODE=fake`).
  always,
}

/// Derleme ortamından sahte API kararı (saf; testler dart-define değiştiremediği için doğrudan çağırır).
/// [compiled] derleme zamanı korumasıdır ([kFakeApiCompiled]). Canlı ortam her `API_MODE` için
/// [FakeApiPolicy.none] alır.
FakeApiPolicy fakeApiPolicyFor({
  required AknEnv env,
  required ApiMode apiMode,
  bool compiled = kFakeApiCompiled,
}) {
  if (!compiled || env == AknEnv.prod) return FakeApiPolicy.none;
  return apiMode == ApiMode.fake
      ? FakeApiPolicy.always
      : FakeApiPolicy.onDemand;
}

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
    this.demoOnDemand = false,
    this.demoSession = false,
  });

  factory AppEnv.fromEnvironment() => AppEnv.fromDefines(
    aknEnv: _aknEnvDefine,
    apiMode: const String.fromEnvironment('API_MODE', defaultValue: 'fake'),
    apiBaseUrl: const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:3108/',
    ),
    portalBaseUrl: const String.fromEnvironment(
      'PORTAL_BASE_URL',
      defaultValue: 'http://localhost:3107/',
    ),
    mapsEnabled: const bool.fromEnvironment('MAPS_ENABLED'),
  );

  /// Derleme tanımlarından ortam (saf; [AppEnv.fromEnvironment] ve testler). Sahte kip ve demo oturumu
  /// [fakeApiPolicyFor] kararına uyar: canlı ortamda ve sahte sunucusuz derlemede ([fakeCompiled] false)
  /// her `API_MODE` için canlı API, demo yok.
  factory AppEnv.fromDefines({
    required String aknEnv,
    required String apiMode,
    required String apiBaseUrl,
    required String portalBaseUrl,
    bool mapsEnabled = false,
    bool fakeCompiled = kFakeApiCompiled,
  }) {
    final env = AknEnv.parse(aknEnv);
    final policy = fakeApiPolicyFor(
      env: env,
      apiMode: ApiMode.parse(apiMode),
      compiled: fakeCompiled,
    );
    return AppEnv(
      env: env,
      apiBaseUrl: _withSlash(apiBaseUrl),
      // Canlı ortamda ve canlı derlemede sahte API asla açılmaz.
      apiMode: policy == FakeApiPolicy.always ? ApiMode.fake : ApiMode.live,
      portalBaseUrl: _withSlash(portalBaseUrl),
      mapsEnabled: mapsEnabled,
      demoOnDemand: policy == FakeApiPolicy.onDemand,
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

  /// Derleme canlı API ile açılır ve giriş ekranında demo kartlarını da sunar; bir kart o oturum için
  /// sahte dünyaya geçer ([FakeApiPolicy.onDemand], test derlemesi). Canlı ortamda hiç true olmaz.
  final bool demoOnDemand;

  /// Bu, test derlemesinde süren bir demo oturumunun etkin ortamı ([asDemoSession]).
  final bool demoSession;

  bool get isFake => apiMode == ApiMode.fake;
  bool get isProd => env == AknEnv.prod;
  bool get isDev => env == AknEnv.dev;

  /// Demo oturumunun etkin ortamı: aynı ortam ve adresler, sahte API (bütün API istekleri uygulama içi
  /// sahte sunucuya gider; şerit "DEMO", "Hakkında" rozeti "Test, sahte API"). Derleme demo oturumu
  /// sunmuyorsa (canlı derleme ya da baştan sahte kip) ortamın kendisi döner.
  AppEnv asDemoSession() {
    if (!kFakeApiCompiled || !demoOnDemand || isProd || demoSession) {
      return this;
    }
    return AppEnv(
      env: env,
      apiBaseUrl: apiBaseUrl,
      apiMode: ApiMode.fake,
      portalBaseUrl: portalBaseUrl,
      mapsEnabled: mapsEnabled,
      demoOnDemand: true,
      demoSession: true,
    );
  }

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
    } else if (env == AknEnv.test && isFake && !demoSession) {
      problems.add('Test ortamı canlı API ile çalışmalı (API_MODE=live).');
    }
    return problems;
  }

  @override
  String toString() =>
      'AppEnv(${env.name}, ${apiMode.name}${demoSession ? ', demo oturumu' : ''}, $apiBaseUrl)';
}

/// Derleme ortamı (dart-define'lardan; uygulama boyunca sabit). `bootstrap` gerçek değerle geçersiz
/// kılar; testler test derlemesini taklit etmek için [AppEnv.fromDefines] ile ezer.
final buildEnvProvider = Provider<AppEnv>((ref) => AppEnv.fromEnvironment());

/// Test derlemesinde demo oturumu sürüyor mu. Süreçle sınırlıdır: uygulama her açılışta derleme kipinde
/// (test derlemesinde canlı) başlar. Giriş ekranındaki demo kartı [DemoSessionController.start], oturumun
/// kapanması (`SessionController.signOut`) [DemoSessionController.end] çağırır.
final demoSessionProvider = NotifierProvider<DemoSessionController, bool>(
  DemoSessionController.new,
);

class DemoSessionController extends Notifier<bool> {
  @override
  bool build() => false;

  /// Demo oturumunu başlatır: etkin ortam sahte kipe geçer ([AppEnv.asDemoSession]); API yığını sahte
  /// sunucuyla yeniden kurulur, sonraki istekler (giriş dahil) canlı API'ye gitmez. Derleme demo oturumu
  /// sunmuyorsa (canlı derleme ya da baştan sahte kip) hiçbir şey yapmaz. Döner: demo oturumu açık mı.
  bool start() {
    if (!kFakeApiCompiled || !ref.read(buildEnvProvider).demoOnDemand) {
      return false;
    }
    state = true;
    return true;
  }

  /// Demo oturumu biter: etkin ortam canlı kipe döner (giriş formu yeniden canlı API'ye gider).
  void end() => state = false;
}

/// Etkin ortam: derleme ortamı; test derlemesinde demo oturumu sürerken onun sahte kipteki eşi. Ağ
/// katmanı (API yığını bunu izler, değişince yeniden kurulur), şerit ve "Hakkında" rozeti buna bakar.
/// Testler doğrudan da ezebilir ([AppEnv.fakeForTests]); o zaman demo oturumu ortamı değiştirmez.
final appEnvProvider = Provider<AppEnv>((ref) {
  final build = ref.watch(buildEnvProvider);
  return ref.watch(demoSessionProvider) ? build.asDemoSession() : build;
});
