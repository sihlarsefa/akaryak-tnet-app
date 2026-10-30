# AkaryakıtNet Mobil

Bayi ve müşteriler için akaryakıt sipariş, teklif ve teslimat uygulaması (Flutter 3.41.6 / Dart 3.11.4).
Tek uygulama: deneyimi oturum açan kullanıcının rolü belirler (müşteri, bayi alt rolleri, saha satış,
şoför, merkez). Kimlik: `com.ortakplatform.akaryakitnet`, ekip `YHBGU7W497`.

## Hızlı başlangıç

```bash
flutter pub get
flutter run --dart-define-from-file=env/dev.json     # sahte API (ağ yok, demo hesapları)
flutter run --dart-define-from-file=env/test.json    # test sunucusu (HTTP 134.149.201.54:3108)
```

Tanım verilmezse uygulama geliştirme ortamında **sahte API** ile açılır. Canlı olmayan derlemelerde sağ
üst köşede küçük bir şerit vardır: sahte veride **DEMO**, test sunucusunda **TEST**.

### Demo hesapları (yalnızca sahte kip)

Şifre `demo`, SMS kodu `123456`. Giriş ekranındaki "Demo hesapları" şeridinden ya da
Profil → Geliştirici menüsünden tek dokunuşla geçilir. Alt menüde kısa adlar görünür (en fazla 10
karakter; uzun basınca tam ad), kalanlar **Diğer** sayfasındadır.

**Roller v5** (sahip kararı 30.10.2026; spec `work/akn-roles-v5.md` §7): giriş ekranında 9 kart vardır,
her etkin rol ve merkez. Demo bayisi Roller v5'e geçmiştir: birim onaycıları **sahip** (yönetici
birimi), **satis** (satış) ve **finans** (finans); finans onayı tek kademedir ("Finans birimi"). Demo
carisinde şirket içi onay kapalıdır (tek müşteri rolü "Yönetici"; rol seçimi, eşikler ve Talepler yok).

| Kullanıcı | Rol | Alt menü |
|---|---|---|
| `musteri` | Müşteri, Yönetici (tek rol: sipariş, teklif kararı, teslim kabulü, şirket kullanıcıları) | Ana sayfa · Siparişler · **Sipariş ver** · Onaylar · Diğer |
| `sahip` | Bayi yöneticisi (ana hesap; yönetici birimi onaycısı; kendisine atanmış teslimatı var) | Ana sayfa · Onaylar · Teklifler · Siparişler · Diğer (Teslimatlar, Ekip …) |
| `satis` | Satış müdürü (satış birimi onaycısı) | Ana sayfa · Onaylar · Saha · Cariler · Diğer |
| `saha` | Satış temsilcisi | Ana sayfa · Saha · **Yeni form** · Cariler · Diğer |
| `finans` | Finans birimi (finans birimi onaycısı; tek kademe, sınırsız) | Ana sayfa · Onaylar · Finans · Tahsilat · Diğer |
| `ikmal` | İkmal birimi (teklif, sevkiyat planı ve şoför ataması, dolum kaydı) | Ana sayfa · Teklifler · Sevkiyat · Siparişler · Diğer |
| `muhasebe` | Muhasebe birimi | Ana sayfa · Tahsilat · Finans · Siparişler · Diğer |
| `sofor` | Şoför (yalnızca kendi teslimatları) | Teslimat · Bildirim · Asistan · Profil |
| `merkez` | Merkez (şifre + SMS kodu) | Ana sayfa · Onaylar · Bildirim · Profil |

Pasif rollerin personaları silinmez: kartları yoktur, formdan ("kullanıcı adı + demo") ve dev menüsünden
("pasif") girilir, saklı oturumları açılır. Eski kodlarını ve eski akışlarını taşırlar.

| Kullanıcı | Rol (pasif) | Alt menü |
|---|---|---|
| `talep` | Müşteri, Talep eden (eski akış: eşik üstü şirket içi onaya düşer) | Ana sayfa · Siparişler · **Sipariş ver** · Teslimat · Diğer (Talepler) |
| `onay` | Müşteri, Onaylayan (eski akış) | Ana sayfa · Siparişler · **Sipariş ver** · Onaylar · Diğer |
| `mudur` | Bayi müdürü (birimlerin onaycısı başkası: imza yok) | Ana sayfa · Teklifler · Siparişler · Sevkiyat · Diğer (Onaylar) |
| `finansuzman` | Finans / kredi uzmanı (finans onaycısı başkası: imza yok) | Ana sayfa · Finans · Tahsilat · Siparişler · Diğer (Onaylar) |
| `siparis` | Sipariş masası / operasyon | Ana sayfa · Teklifler · Siparişler · Sevkiyat · Diğer |
| `sevkiyat` | Sevkiyat planlama | Ana sayfa · Sevkiyat · Siparişler · Cariler · Diğer |
| `depo` | Depo / dolum | Ana sayfa · Sevkiyat · Siparişler · Asistan · Diğer |
| `izleyici` | Görüntüleyici (Ekip'te "Görüntüleyici (pasif)" ve "İncelenecek") | Ana sayfa · Siparişler · Sevkiyat · Cariler · Diğer |
| `ozelrol` | Şablonsuz özel rol ("Bölge sorumlusu") | Ana sayfa · Siparişler · Sevkiyat · Cariler · Diğer (Onaylarım "Diğer"de) |

Alt menü `me/access` sayfa yetkilerinden, yetkinliklerden ve rol ön ayarından hesaplanır
(`lib/app/destinations.dart`, spec A.2); rol adına göre karar verilmez. İkmal birimi (`supply`) kendi ön
ayarını kullanır ve sipariş masası ile sevkiyattan önce denenir. Onaylar yalnızca imza yetkinliğinde
(`signingCapabilities`; alanı göndermeyen eski sunucuda `capabilities`) bir `approve.*` kodu olanlarda,
müşteride ve merkezde ana sekmedir: birimin onaycısı başkasıysa o birimin kodu imzada sayılmaz, Onaylar
"Diğer"e iner (ham yetkinlik ve sayfa erişimi sürer). Kendisine teslimat atanmış personelde
(`assignedOpenShipments > 0`) Teslimatlarım görünür. Rol adları sunucudan gelir (pasif rolde "(pasif)");
Ekip'te birim onaycısında "Onaycı · Finans", Profil'de "Finans birimi · onaycı" yazar.

**Eski akışlar (testler):** sahte dünyanın iki anahtarı vardır. `FakeWorld.companyApprovals` (varsayılan
kapalı) şirket içi onayı, 9003 / 9013 tohumlarını, talep bildirimini, eşikleri ve örnek talepleri açar;
`FakeWorld.v5Station` (varsayılan açık) kapatılınca birim onaycıları kalkar ve 9006 iki kademeye döner.
Eski akışı sınayan test dosyaları `setUpAll` içinde `FakeWorld.defaultCompanyApprovals = true` ya da
`FakeWorld.defaultV5Station = false` yapar.

## Ortamlar

`env/<ortam>.json` (`--dart-define-from-file`). Gizli değer içermez.

| Anahtar | dev | test | prod |
|---|---|---|---|
| `AKN_ENV` | dev | test | prod |
| `API_MODE` | fake | live | live (canlıda sahte kip açılamaz) |
| `API_BASE_URL` | — | `http://134.149.201.54:3108/` | HTTPS alan adı (yer tutucu; sahip verecek) |
| `PORTAL_BASE_URL` | — | `http://134.149.201.54:3107/` | HTTPS |
| `MAPS_ENABLED` | false | false | anahtar tanımlanınca true |

- **Denetim (`AppEnv.validate`):** canlı ortam canlı API, HTTPS ve gerçek alan adı ister; değilse uygulama
  "Uygulama yapılandırması eksik" ekranıyla açılır, yanlış sunucuya bağlanmaz.
- **Derleme zamanı koruması (`kFakeApiCompiled`):** `API_MODE=live` ya da `AKN_ENV=prod` ile derlenen
  uygulamaya sahte sunucu ve demo hesapları hiç girmez.
- **Sunucu kapısı:** `app/config` açılışta en fazla 3 sn beklenir (önbellek yedeği); 404 ya da farklı
  `contractVersion` → "Sunucu güncel değil", `maintenance.active` → "Bakımdayız" (`/update?reason=`).

HTTP test adresi: Dio `dart:io` kullanır; ATS ve Android cleartext politikası bu yığına uygulanmaz,
bu yüzden genel `NSAllowsArbitraryLoads` / `usesCleartextTraffic` eklenmedi. Canlı ortam HTTPS kullanır
(tek satır).

## Gizli değerler (asla git'e girmez)

| Dosya | İçerik |
|---|---|
| `ios/Flutter/Secrets.xcconfig` | `GMS_API_KEY = …` (örnek: `Secrets.xcconfig.example`) |
| `android/local.properties` | `MAPS_API_KEY=…` |
| `android/key.properties` + `*.jks` | yayın imzası (örnek: `key.properties.example`); yoksa debug imzası |
| `ios/Runner/GoogleService-Info.plist`, `android/app/google-services.json` | Firebase (F2GO'nun projesi); dosyayı bu yola koymak yeter, Xcode hedefine eklenmez: iOS'ta Runner'ın "Firebase Config (optional)" derleme adımı varsa pakete kopyalar, yoksa paketteki eski kopyayı siler; Android'de `google-services` eklentisi yalnızca dosya varken uygulanır. Yoksa push kapalı çalışır, gelen kutusu 60 sn'de bir yoklanır |

## Mimari

```
lib/main.dart, bootstrap.dart        açılış: hata kancaları, kenardan kenara, ortam denetimi, ilk açılış, Firebase, depolar
lib/app/                             MaterialApp, yönlendirici, alt menü, kabuk, ana sayfa seçimi, şerit, gizlilik örtüsü
lib/app/splash/                      açılış ekranı
lib/core/env|network|auth|storage|offline|push|models|media|pdf|utils|routing
lib/core/ui/                         tasarım sistemi: tema, hareket, durum stilleri, bileşenler
lib/features/<f>/                    <f>_routes.dart · <f>_fake.dart · api.dart · data/ · application/ · presentation/
integration_test/                    cihaz duman testi, mağaza görüntüleri, performans izi
```

- **Ağ:** tek Dio (`apiClientProvider`), başlıklar (`X-Device-Id`, `X-App-*`, `X-Correlation-Id`,
  `Idempotency-Key`), tek seferde tek belirteç yenileme, hatalar `AppFailure` (Türkçe metin tablosu:
  `core/network/failure_copy.dart`, sunucu hatasında "Destek kodu").
- **Sahte API:** `API_MODE=fake` iken `FakeApiAdapter` → `FakeServer` (300–800 ms gecikme, dev menüsünden
  hata enjeksiyonu). Ortak durumlu dünya `core/network/fake/fake_world.dart`; özellikler kendi uçlarını
  `features/<f>/<f>_fake.dart` içinde kaydeder (aynı yolu sonra kaydeden kazanır). Şirket içi talepler
  tek torbadadır (`company.orderRequests`).
- **Oturum:** `SessionController` (bilinmiyor → oturum yok → açık → kilitli); erişim belirteci yalnızca
  bellekte, yenileme belirteci güvenli depoda. Çıkışta / kullanıcı değişince önbellek, görseller,
  bildirim merkezi, simge rozeti ve özelliklerin kullanıcı dosyaları (saklı PDF'ler;
  `sessionCleanupHooksProvider`, `app/wiring.dart`) temizlenir; erişim belirteci dolmuşsa `auth/revoke`. Kurulumdan
  sonraki ilk açılışta `akn.*` güvenli anahtarları silinir (iOS Anahtar Zinciri yeniden kurulumda kalır).
- **Kilit:** biyometrik kilit 60 sn arka planda kalınca; kamera, paylaşım, tarayıcı dönüşü kilitlemez
  (`ExternalActivity`); kilit açıkken uygulama değiştiricide lacivert gizlilik örtüsü.
- **Çevrimdışı:** `OutboxRunner` (bağlantı gelince bekleme sıfırlanır, `Retry-After`, `concurrency_conflict`
  için bir kez yeniden okuyup tekrar), `CacheStore` (SQLite), `PendingOpsChip`.
- **Push:** Firebase isteğe bağlı; Android kategori kanalları (`akn_orders`, `akn_quotes`,
  `akn_shipments`, `akn_approvals`, `akn_payments`, `akn_field`, `akn_system` + `akn_default`) açılışta
  oluşturulur; dokunulan push `RouteAccess` ile doğrulanır, izin yoksa `/notifications`.
- **Türkçe harf kuralı:** `lib/` içinde `toUpperCase()` / `toLowerCase()` yalnızca
  `core/utils/turkish_text.dart`'tadır (`TurkishText` ya da `asciiUpper` / `asciiLower`).
- Kod üretimi yok: modeller elle yazılır (`JsonReader`).

## Komutlar

Paralel ajanlar için kilitli sarmalayıcı: `bash $W/akn-flutter.sh <komut>`
(`pub-get`, `analyze`, `test`, `format`, `fix`, `icons`, `splash`, `build-apk [ortam]`, `build-ios-sim [ortam]`).

```bash
bash tool/ci.sh              # pub get → harf kuralı → gizli değer → format → analyze → test → APK + iOS simülatör
bash tool/ci.sh --no-build   # derlemesiz
bash tool/live_smoke.sh      # test sunucusu salt-okunur duman (health, app/config, yasal sayfalar; giriş isteğe bağlı)
dart run flutter_launcher_icons            # simge (assets/icon; iOS koyu ve renklendirilmiş dahil)
dart run flutter_native_splash:create      # yerel açılış (lacivert #1F2A37 + » işareti)
```

### Testler

| Klasör | İçerik |
|---|---|
| `test/core`, `test/core/ui` | çekirdek davranış, tasarım sistemi (mor yok, kontrast, 48 dp, 2,0× yazı) |
| `test/features/<f>` | özellik ekranları ve sahteleri (C.7 erişilebilirlik dahil) |
| `test/app` | rota ve push rota tablosu, persona geçişi (2,0× koyu + kılavuzlar), duman akışı, 100+ satırlık listeler, çıkış temizliği, ekran görüntüsü |
| `test/contract` | sözleşme örnekleri (C# DTO anahtarları) ve enum kodları |
| `integration_test/` | cihazda duman (`app_smoke_test`), mağaza görüntüleri, performans izi |

```bash
flutter test                                   # tümü (ağ yok)
flutter test test/app/screens_capture_test.dart --dart-define=AKN_SCREENS_DIR=/yol   # persona görüntüleri
flutter test integration_test/app_smoke_test.dart --dart-define-from-file=env/dev.json -d <cihaz>
```

### Yayın denetimleri

- **Performans bütçesi** (profil kipi, orta seviye Android API 30 / 4 GB ve iPhone 11 sınıfı): kabuğa
  soğuk açılış ≤ 2,5 sn; 100 satırlık teklif masası / sipariş listesi kaydırmada takılan kare ≤ %1
  (`flutter drive --profile --target=integration_test/perf_test.dart …`, sahte dünyada 120 bekleyen
  sipariş; soğuk açılış `flutter run --profile --trace-startup`); küçük resimler `cacheWidth` ile
  çözülür; indirme boyutu (≤ 60 MB önerilir) yayın derlemesinden sonra
  `flutter build appbundle --analyze-size` / App Store Connect "App Size" ile kaydedilir.
- **Mağaza paketi:** `$W/akn-mobile/store/` (inceleme notları, gizlilik formları, kayıt metinleri,
  ekran görüntüleri).

Yayın (sahip, bu Mac'te):

```bash
flutter build ipa --release --obfuscate --split-debug-info=build/symbols/<derleme> --dart-define-from-file=env/prod.json
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols/<derleme> --dart-define-from-file=env/prod.json
```

## Lisanslar

PDF belgelerindeki Roboto yazı tipi Apache 2.0 lisanslıdır (`assets/fonts/NOTICE.txt`; uygulama içi
lisans sayfasında listelenir).
