import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/auth_models.dart';
import '../storage/secure_store.dart';
import '../utils/log.dart';

/// Uygulama ve cihaz bilgisi: sürüm, derleme, platform, model, kurulum başına cihaz kimliği.
/// İstek başlıkları (`X-Device-Id`, `X-App-Platform`, `X-App-Version`, `X-App-Build`) buradan gelir.
@immutable
class AppInfo {
  const AppInfo({
    required this.appVersion,
    required this.appBuild,
    required this.platform,
    required this.deviceId,
    this.model,
    this.osVersion,
    this.locale = 'tr-TR',
  });

  /// Testler ve önizleme için.
  static const test = AppInfo(
    appVersion: '1.0.0',
    appBuild: 1,
    platform: 'ios',
    deviceId: 'test-device',
    model: 'Test',
  );

  /// Bootstrap'ta bir kez yüklenir. Eklenti yoksa (test) güvenli varsayılanlara düşer.
  static Future<AppInfo> load(SecureStore store) async {
    var version = '1.0.0';
    var build = 1;
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = int.tryParse(info.buildNumber) ?? 1;
    } catch (e) {
      AppLog.warn('Paket bilgisi okunamadı', error: e);
    }

    final platform = defaultTargetPlatform == TargetPlatform.android
        ? 'android'
        : 'ios';
    String? model;
    String? os;
    try {
      final plugin = DeviceInfoPlugin();
      if (platform == 'android') {
        final a = await plugin.androidInfo;
        model = '${a.manufacturer} ${a.model}'.trim();
        os = 'Android ${a.version.release}';
      } else {
        final i = await plugin.iosInfo;
        model = i.utsname.machine;
        os = '${i.systemName} ${i.systemVersion}';
      }
    } catch (e) {
      AppLog.warn('Cihaz bilgisi okunamadı', error: e);
    }

    var deviceId = await store.read(SecureKeys.deviceId);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await store.write(SecureKeys.deviceId, deviceId);
    }

    return AppInfo(
      appVersion: version,
      appBuild: build,
      platform: platform,
      deviceId: deviceId,
      model: model,
      osVersion: os,
    );
  }

  final String appVersion;
  final int appBuild;

  /// `ios` / `android`.
  final String platform;
  final String deviceId;
  final String? model;
  final String? osVersion;
  final String locale;

  /// Profil → Hakkında: "1.0.0 (1)".
  String get versionLabel => '$appVersion ($appBuild)';

  DeviceInfo toDeviceInfo({String? pushToken}) => DeviceInfo(
    deviceId: deviceId,
    platform: platform,
    model: model,
    osVersion: osVersion,
    appVersion: appVersion,
    appBuild: appBuild,
    pushToken: pushToken,
  );
}

/// Bootstrap gerçek değerle geçersiz kılar.
final appInfoProvider = Provider<AppInfo>((ref) => AppInfo.test);
