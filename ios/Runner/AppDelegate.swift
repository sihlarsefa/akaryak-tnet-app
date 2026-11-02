import FirebaseCore
import FirebaseMessaging
import Flutter
import GoogleMaps
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Google Maps anahtarı git dışı Secrets.xcconfig → Info.plist GMSApiKey. Boşsa haritalar kapalıdır
    // (uygulama MAPS_ENABLED=false ile adres ve yol tarifi gösterir).
    if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !key.isEmpty, !key.hasPrefix("$(") {
      GMSServices.provideAPIKey(key)
    }
    // Push (F2GO ile aynı sıra): Firebase açılışta yerelde başlatılır ve cihaz APNs'e hemen kaydedilir.
    // Örtük Flutter motorunda eklentiler açılıştan sonra kaydolduğu için firebase_messaging bu kaydı
    // kendisi yapamıyordu; APNs belirteci gelmeyince FCM belirteci de oluşmuyor, sunucuda cihaz
    // görünmüyordu (uygulama kapalıyken bildirim yalnızca kutuya düşüyordu). Yapılandırma dosyası yoksa
    // push kapalı çalışır (Dart tarafı da aynı kuralı izler).
    if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
      if FirebaseApp.app() == nil {
        FirebaseApp.configure()
      }
      UNUserNotificationCenter.current().delegate = self
      application.registerForRemoteNotifications()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // APNs belirteci doğrudan FCM'e verilir (yöntem değiştirmeye güvenmeden), sonra eklentilere iletilir.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    if FirebaseApp.app() != nil {
      Messaging.messaging().apnsToken = deviceToken
    }
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
