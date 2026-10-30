import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../storage/prefs_store.dart';
import '../utils/log.dart';
import 'local_notifications.dart';
import 'push_payload.dart';

/// Kapalı uygulamaya gelen push (Firebase gerektirir; bildirim sistem tarafından gösterilir).
@pragma('vm:entry-point')
Future<void> aknFirebaseBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  } catch (_) {
    // Yapılandırma yok: arka plan işi yok.
  }
}

/// Push izni durumu.
enum PushPermission { unavailable, notDetermined, granted, denied }

/// Bildirim izninin platform çağrıları (FCM; testler geçersiz kılar).
abstract interface class PushPermissionPlatform {
  /// Mevcut izin (`getNotificationSettings`).
  Future<AuthorizationStatus> status();

  /// Sistem izin penceresi (`requestPermission`; Android 13+'ta POST_NOTIFICATIONS).
  Future<AuthorizationStatus> request();

  /// Android API düzeyi (Android değilse ya da okunamazsa null).
  Future<int?> androidSdkInt();
}

class _FirebasePermissionPlatform implements PushPermissionPlatform {
  const _FirebasePermissionPlatform();

  @override
  Future<AuthorizationStatus> status() async =>
      (await FirebaseMessaging.instance.getNotificationSettings())
          .authorizationStatus;

  @override
  Future<AuthorizationStatus> request() async =>
      (await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      )).authorizationStatus;

  @override
  Future<int?> androidSdkInt() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    } catch (_) {
      return null;
    }
  }
}

/// FCM sarmalayıcısı (F2GO `notification_service.dart` uyarlaması, spec C.4).
///
/// - `GoogleService-Info.plist` / `google-services.json` yoksa Firebase başlatılamaz: [available] false,
///   push kapalıdır ve uygulama gelen kutusunu 60 sn'de bir yoklar.
/// - Ön planda gelen push uygulama içi bildirim olur (sistem bildirimi gösterilmez); dokunulan push ve
///   ilk mesaj [events] ile `PushRouter`'a gider.
class PushService {
  PushService({
    required this.available,
    PrefsStore? prefs,
    PushPermissionPlatform? permissions,
  }) : _prefs = prefs,
       _permissions = permissions ?? const _FirebasePermissionPlatform();

  /// Firebase başlatıldı mı.
  final bool available;

  final PrefsStore? _prefs;
  final PushPermissionPlatform _permissions;

  final _events = StreamController<PushEvent>.broadcast();
  final _tokens = StreamController<String>.broadcast();
  final List<StreamSubscription<Object?>> _subs = [];
  bool _started = false;

  /// Ön plan ve dokunma olayları.
  Stream<PushEvent> get events => _events.stream;

  /// Belirteç yenilendi (cihaz kaydı tazelenir).
  Stream<String> get tokenRefreshes => _tokens.stream;

  /// Firebase'i başlatmayı dener (bootstrap). Yapılandırma dosyası yoksa false döner; hata fırlatmaz.
  static Future<bool> tryInitFirebase() async {
    if (kIsWeb) return false;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(aknFirebaseBackgroundHandler);
      return true;
    } catch (e) {
      AppLog.debug('Firebase yapılandırması yok; push kapalı ($e)');
      return false;
    }
  }

  /// Dinleyicileri bağlar (bir kez).
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await LocalNotifications.init();
    LocalNotifications.onTap = (route) => _emit(
      PushPayload(route: route, receivedAt: DateTime.now().toUtc()),
      PushOrigin.tap,
    );
    if (!available) return;
    try {
      final m = FirebaseMessaging.instance;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // Uygulama açıkken sistem bandı yerine uygulama içi bildirim gösterilir; rozet güncellenir.
        await m.setForegroundNotificationPresentationOptions(
          alert: false,
          badge: true,
          sound: false,
        );
      }
      _subs.add(
        FirebaseMessaging.onMessage.listen(
          (msg) => _emit(_payload(msg), PushOrigin.foreground),
        ),
      );
      _subs.add(
        FirebaseMessaging.onMessageOpenedApp.listen(
          (msg) => _emit(_payload(msg), PushOrigin.tap),
        ),
      );
      _subs.add(
        m.onTokenRefresh.listen((t) {
          if (!_tokens.isClosed) _tokens.add(t);
        }),
      );
      final initial = await m.getInitialMessage();
      if (initial != null) _emit(_payload(initial), PushOrigin.tap);
    } catch (e) {
      AppLog.warn('Push dinleyicileri bağlanamadı', error: e);
    }
  }

  void _emit(PushPayload p, PushOrigin origin) {
    if (!_events.isClosed) _events.add(PushEvent(p, origin));
  }

  static PushPayload _payload(RemoteMessage m) => PushPayload.fromData(
    m.data,
    title: m.notification?.title,
    body: m.notification?.body,
  );

  /// Mevcut izin durumu.
  ///
  /// Android 13+ (API 33) çalışma zamanı izninde eklenti henüz sorulmamış izni de "reddedildi"
  /// bildirir (`checkSelfPermission` → 0). Uygulama izni bir kez sorduğunu saklar
  /// ([PrefKeys.pushPermissionRequested]); hiç sormadıysa durum "belirlenmedi" sayılır ki sistem
  /// penceresi açılabilsin. Android 12 ve öncesinde izin varsayılan açıktır; "kapalı"
  /// kullanıcının ayarlardan kapattığı anlamına gelir.
  Future<PushPermission> permission() async {
    if (!available) return PushPermission.unavailable;
    try {
      final status = await _permissions.status();
      final mapped = switch (status) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => PushPermission.granted,
        AuthorizationStatus.denied => PushPermission.denied,
        AuthorizationStatus.notDetermined => PushPermission.notDetermined,
      };
      if (mapped == PushPermission.denied && await _notAskedYet()) {
        return PushPermission.notDetermined;
      }
      return mapped;
    } catch (_) {
      return PushPermission.unavailable;
    }
  }

  Future<bool> _notAskedYet() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    if (_prefs?.getBool(PrefKeys.pushPermissionRequested) ?? false) {
      return false;
    }
    final sdk = await _permissions.androidSdkInt();
    return sdk != null && sdk >= 33;
  }

  /// Sistem izin penceresi (ilk açılışta, Bildirim ayarları anahtarından ya da müşterinin ilk
  /// siparişinden sonra). Bir kez sorulur: FCM'in isteği Android 13+'ta POST_NOTIFICATIONS
  /// penceresini açar; yerel bildirimler aynı izni kullandığından ikinci bir istek (ve "İzin
  /// verme"den sonra aynı pencerenin yeniden çıkması) yoktur.
  Future<bool> requestPermission() async {
    if (!available) return false;
    try {
      await _prefs?.setBool(PrefKeys.pushPermissionRequested, true);
      final s = await _permissions.request();
      return s == AuthorizationStatus.authorized ||
          s == AuthorizationStatus.provisional;
    } catch (e) {
      AppLog.warn('Bildirim izni istenemedi', error: e);
      return false;
    }
  }

  /// İlk açılış (sahip kararı 2026-10-30): bildirim izni hiç sorulmadıysa sistem penceresi ön sayfa
  /// olmadan, herkese (müşteri dahil) hemen açılır. Bir kez bakılır ([PrefKeys.pushLaunchAsked]):
  /// izin zaten verilmiş ya da reddedilmişse yalnızca not edilir; reddedilen izin için açılışta bir
  /// daha sorulmaz (Bildirim ayarları → "Anlık bildirimler" telefon ayarlarına götürür). Firebase
  /// yoksa hiçbir şey yapılmaz ve not da düşülmez. Döner: sistem penceresi açıldı mı.
  Future<bool> requestAtFirstLaunch() async {
    final prefs = _prefs;
    if (!available || prefs == null) return false;
    if (prefs.getBool(PrefKeys.pushLaunchAsked)) return false;
    final current = await permission();
    if (current == PushPermission.unavailable) return false;
    await prefs.setBool(PrefKeys.pushLaunchAsked, true);
    if (current != PushPermission.notDetermined) return false;
    await requestPermission();
    return true;
  }

  /// FCM belirteci. iOS'ta APNs belirteci gecikebilir; birkaç kez denenir (F2GO).
  Future<String?> token() async {
    if (!available) return null;
    final m = FirebaseMessaging.instance;
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          await m.getAPNSToken();
          await Future<void>.delayed(
            Duration(milliseconds: 250 + attempt * 200),
          );
        }
        final t = await m.getToken();
        if (t != null && t.isNotEmpty) return t;
      } catch (e) {
        AppLog.debug('FCM belirteci alınamadı (deneme ${attempt + 1}): $e');
      }
      await Future<void>.delayed(Duration(milliseconds: 400 + attempt * 150));
    }
    return null;
  }

  /// Çıkışta cihaz belirtecini siler (sunucu da `auth/logout` ile temizler).
  Future<void> deleteToken() async {
    if (!available) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _events.close();
    await _tokens.close();
  }
}
