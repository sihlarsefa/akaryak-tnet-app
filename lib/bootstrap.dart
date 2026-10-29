import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/config_error_app.dart';
import 'app/wiring.dart';
import 'core/env/app_env.dart';
import 'core/env/app_info.dart';
import 'core/network/network_providers.dart';
import 'core/offline/cache_store.dart';
import 'core/offline/outbox_store.dart';
import 'core/push/push_providers.dart';
import 'core/push/push_service.dart';
import 'core/storage/local_db.dart';
import 'core/storage/prefs_store.dart';
import 'core/storage/secure_store.dart';
import 'core/ui/theme.dart';
import 'core/utils/log.dart';

/// Uygulama açılışı (spec C.3/C.4): hata kancaları, ortam, Firebase denemesi, depolar, ProviderScope.
Future<void> bootstrap() async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      AppLog.error('Flutter hatası', details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      AppLog.error('Platform hatası', error, stack);
      return true;
    };
    LicenseRegistry.addLicense(_robotoLicense);

    // Kenardan kenara (Android 15 zorunlu; spec D.7): sistem çubukları saydam, simge rengi her
    // yüzeyin AnnotatedRegion'ından gelir.
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    SystemChrome.setSystemUIOverlayStyle(
      AknTheme.overlayFor(PlatformDispatcher.instance.platformBrightness),
    );

    Intl.defaultLocale = 'tr_TR';
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('tr');

    final env = AppEnv.fromEnvironment();
    AppLog.debug('Açılış: $env');
    // Yapılandırma denetimi (spec D.7): canlı ortam HTTPS + canlı API ister; sorun varsa uygulama
    // açılmaz (kapalı başarısızlık), diğer ortamlarda yalnızca uyarılır.
    final problems = env.validate();
    if (problems.isNotEmpty) {
      AppLog.warn('Ortam yapılandırması: ${problems.join(' · ')}');
      if (env.isProd) {
        runApp(ConfigErrorApp(problems: problems));
        return;
      }
    }

    // Firebase isteğe bağlı: yapılandırma dosyaları yoksa push kapalı, gelen kutusu yoklanır.
    final firebase = await PushService.tryInitFirebase();

    final prefs = await SharedPreferences.getInstance();
    final secure = FlutterSecureStore();
    await secure.verifyReadable();
    // Yeniden kurulumda iOS Anahtar Zinciri'nde kalan eski oturum ve cihaz kimliği silinir.
    final fresh = await FirstLaunch.wipeIfFresh(
      hasPref: prefs.containsKey,
      markPref: (k) => prefs.setBool(k, true),
      secure: secure,
    );
    if (fresh) AppLog.debug('İlk açılış: güvenli anahtarlar temizlendi');
    final info = await AppInfo.load(secure);
    final db = await LocalDb.open();

    runApp(
      ProviderScope(
        overrides: [
          // Derleme ortamı; etkin ortam (`appEnvProvider`) test derlemesinde demo oturumunda sahte kipe
          // geçer ve çıkışta buna döner.
          buildEnvProvider.overrideWithValue(env),
          appInfoProvider.overrideWithValue(info),
          prefsStoreProvider.overrideWithValue(PrefsStore(prefs)),
          secureStoreProvider.overrideWithValue(secure),
          firebaseAvailableProvider.overrideWithValue(firebase),
          if (db != null)
            cacheStoreProvider.overrideWithValue(SqfliteCacheStore(db)),
          if (db != null)
            outboxStoreProvider.overrideWithValue(SqfliteOutboxStore(db)),
          ...appWiringOverrides(),
        ],
        child: const AknApp(),
      ),
    );
  }, (error, stack) => AppLog.error('Yakalanmamış hata', error, stack));
}

/// PDF belgelerindeki gömülü Roboto yazı tipinin lisansı (Apache 2.0).
Stream<LicenseEntry> _robotoLicense() async* {
  try {
    final text = await rootBundle.loadString('assets/fonts/NOTICE.txt');
    yield LicenseEntryWithLineBreaks(const ['Roboto'], text);
  } catch (_) {
    // Lisans dosyası yoksa listelenmez.
  }
}
