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
    // firebase_messaging 15.x bildirim bağlantısını (bildirim merkezi temsilcisine katılma, ilk mesaj,
    // APNs kaydı) UIApplicationDidFinishLaunchingNotification'da kurar; örtük motorda eklentiler
    // açılıştan sonra kaydolduğu için bu bildirim kaçar: uygulama açıkken bant, onMessage ve dokunuş
    // (onMessageOpenedApp) hiç çalışmaz. Kurulum burada bir kez elle tetiklenir; eklentinin kendi
    // gözlemcisi önce kaldırılır, böylece kurulum iki kez çalışamaz. Yukarıdaki
    // `UNUserNotificationCenter.current().delegate = self` bu bloktan önce kalmalıdır (yoksa eklenti
    // temsilciyi devralır). firebase_messaging 16.5+ bunu kendisi yapar: yükseltirken bu blok silinmeli.
    if FirebaseApp.app() != nil {
      let setup = NSSelectorFromString("application_onDidFinishLaunchingNotification:")
      if let fcm = engineBridge.pluginRegistry.valuePublished(byPlugin: "FLTFirebaseMessagingPlugin"),
         fcm.responds(to: setup) {
        NotificationCenter.default.removeObserver(
          fcm, name: UIApplication.didFinishLaunchingNotification, object: nil)
        _ = fcm.perform(
          setup, with: NSNotification(name: UIApplication.didFinishLaunchingNotification, object: nil))
      }
    }
  }
}
