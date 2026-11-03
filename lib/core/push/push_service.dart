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

/// FCM'in uygulama içi uçları: dinleyiciler, ilk mesaj, iOS ön plan sunumu (testler geçersiz kılar).
abstract interface class PushMessagingPlatform {
  /// Uygulama açıkken gelen push'lar.
  Stream<RemoteMessage> get onMessage;

  /// Uygulama arka plandayken dokunulan push'lar.
  Stream<RemoteMessage> get onMessageOpenedApp;

  /// Yenilenen FCM belirteci.
  Stream<String> get onTokenRefresh;

  /// Kapalı uygulamayı açan push (yoksa null).
  Future<RemoteMessage?> getInitialMessage();

  /// iOS: uygulama açıkken gelen push'un sistem sunumu (`setForegroundNotificationPresentationOptions`).
  Future<void> setForegroundPresentation({
    required bool alert,
    required bool badge,
    required bool sound,
  });
}

class _FirebaseMessagingPlatform implements PushMessagingPlatform {
  const _FirebaseMessagingPlatform();

  @override
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  @override
  Stream<String> get onTokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;

  @override
  Future<RemoteMessage?> getInitialMessage() =>
      FirebaseMessaging.instance.getInitialMessage();

  @override
  Future<void> setForegroundPresentation({
    required bool alert,
    required bool badge,
    required bool sound,
  }) => FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: alert,
    badge: badge,
    sound: sound,
  );
}

/// FCM sarmalayıcısı (F2GO `notification_service.dart` uyarlaması, spec C.4).
///
/// - `GoogleService-Info.plist` / `google-services.json` yoksa Firebase başlatılamaz: [available] false,
///   push kapalıdır ve uygulama gelen kutusunu 60 sn'de bir yoklar.
/// - Ön planda gelen push, uygulama kapalıyken olduğu gibi sistem bildirimi olur: her adım ayrı görünür
///   ve Bildirim Merkezi'nde kalır (iOS'ta bandı sistem gösterir, Android'de yerel bildirim). İzin yoksa
///   olay gösterilmemiş olarak gider ([PushEvent.presented]) ve uygulama içi balon çıkar.
/// - Dokunulan push, ilk mesaj ve yerel bildirim dokunuşu [events] ile `PushCoordinator`'a gider.
class PushService {
  PushService({
    required this.available,
    PrefsStore? prefs,
    PushPermissionPlatform? permissions,
    PushMessagingPlatform? messaging,
  }) : _prefs = prefs,
       _permissions = permissions ?? const _FirebasePermissionPlatform(),
       _messaging = messaging ?? const _FirebaseMessagingPlatform();

  /// Firebase başlatıldı mı.
  final bool available;

  final PrefsStore? _prefs;
  final PushPermissionPlatform _permissions;
  final PushMessagingPlatform _messaging;

  final _events = StreamController<PushEvent>.broadcast();
  final _tokens = StreamController<String>.broadcast();
  final List<StreamSubscription<Object?>> _subs = [];
  bool _started = false;

  /// iOS: ön plan sunum seçenekleri (bant + rozet + ses) kaydedildi mi. Kaydedilemediyse sistem bandı
  /// çıkmayabilir: ön plan push'u gösterilmemiş sayılır ve uygulama içi balon çıkar.
  bool _iosBanners = false;

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
    // Yerel bildirime dokunuş (Android'de ön planda gösterilen push kopyası): kilit ekranındaki push'a
    // dokunuşla aynı yol — veri push'un kendisi (rota, olay, satır); eski bildirimlerde düz rota.
    LocalNotifications.onTap = (payload) =>
        _emit(PushPayload.fromLocalPayload(payload), PushOrigin.tap);
    final m = available ? _messaging : null;
    if (m != null) {
      try {
        _subs.add(m.onMessage.listen((msg) => unawaited(_foreground(msg))));
        _subs.add(
          m.onMessageOpenedApp.listen(
            (msg) => _emit(_payload(msg), PushOrigin.tap),
          ),
        );
        _subs.add(
          m.onTokenRefresh.listen((t) {
            if (!_tokens.isClosed) _tokens.add(t);
          }),
        );
      } catch (e) {
        AppLog.warn('Push dinleyicileri bağlanamadı', error: e);
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // Uygulama açıkken de sistem bandı (kapalıyken olduğu gibi): her adım görünür ve Bildirim
        // Merkezi'nde kalır; rozet ve ses de. Yerel kopya çıkmaz (aynı push iki kez görünürdü).
        try {
          await m.setForegroundPresentation(
            alert: true,
            badge: true,
            sound: true,
          );
          _iosBanners = true;
        } catch (e) {
          AppLog.warn('iOS ön plan bildirim sunumu ayarlanamadı', error: e);
        }
      }
    }
    // Kapalı uygulamayı açan yerel bildirim dokunuşu (FCM'in ilk mesajı gibi; Android'de ön planda
    // gösterilmiş push kopyası olabilir).
    final launch = await LocalNotifications.takeLaunchPayload();
    if (launch != null) {
      _emit(PushPayload.fromLocalPayload(launch), PushOrigin.tap);
    }
    if (m == null) return;
    try {
      final initial = await m.getInitialMessage();
      if (initial != null) _emit(_payload(initial), PushOrigin.tap);
    } catch (e) {
      AppLog.warn('Push ilk mesajı okunamadı', error: e);
    }
  }

  /// Ön planda gelen push: önce sistem bildirimi olarak gösterilir ([_present]), sonra olay
  /// gösterilip gösterilmediğiyle yayınlanır (gösterilmediyse koordinatör balonu açar).
  Future<void> _foreground(RemoteMessage msg) async {
    final p = _payload(msg);
    var presented = false;
    try {
      presented = await _present(p, alerting: msg.notification != null);
    } catch (e) {
      AppLog.debug('Ön plan bildirimi gösterilemedi: ${e.runtimeType}');
    }
    _emit(p, PushOrigin.foreground, presented: presented);
  }

  /// Ön plan push'unu sistem bildirimi olarak gösterir; döner: gösterildi mi.
  ///
  /// - Sessiz ya da yalnızca veri push'u ([alerting] false: uygulama kapalıyken de bildirim çıkmaz) ve
  ///   başlığı / metni olmayan push gösterilmez.
  /// - Bildirim izni yoksa gösterilmez (sistem gösteremez): çağıran uygulama içi balonu gösterir.
  /// - iOS: bandı sistem gösterir ([start]'taki sunum seçenekleri; firebase_messaging'in bildirim
  ///   merkezi bağlantısı `willPresent`'te bu seçenekleri uygular ve [PushMessagingPlatform.onMessage]'ı
  ///   oradan verir). Seçenekler kaydedilemediyse gösterilmemiş sayılır.
  /// - Android: FCM uygulama açıkken bildirim göstermez; yerel bildirim ([LocalNotifications.showPush]).
  Future<bool> _present(PushPayload p, {required bool alerting}) async {
    if (!available || !alerting) return false;
    if (p.title == null && p.body == null) return false;
    if (await permission() != PushPermission.granted) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return _iosBanners;
      case TargetPlatform.android:
        return LocalNotifications.showPush(p);
      default:
        return false;
    }
  }

  void _emit(PushPayload p, PushOrigin origin, {bool presented = false}) {
    if (!_events.isClosed) {
      _events.add(PushEvent(p, origin, presented: presented));
    }
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
