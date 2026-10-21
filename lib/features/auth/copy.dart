/// Kimlik ekranlarının Türkçe metinleri (spec C.5, C.7): "siz" dili, cümle düzeni, büyük harf başlık yok,
/// düğme etiketleri en çok 22 karakter. Sunucunun Türkçe mesajları (ServiceException) olduğu gibi
/// gösterilir; burada yalnızca uygulamanın kendi metinleri vardır.
abstract final class AuthCopy {
  // ------------------------------------------------------------------ Giriş
  /// Giriş bandının başlığı (tasarım v2 §7.2).
  static const tagline = 'Siparişten teslimata.';

  /// Bandın sağ alt köşesindeki satır.
  static const bandSubtitle = 'Bayiler ve kurumsal müşteriler için';

  /// Bandın ekran okuyucu metni (bant tek başlık olarak okunur).
  static const bandSpoken =
      '$tagline AkaryakıtNet, bayiler ve kurumsal müşteriler için.';

  /// Giriş ekranının yumuşak üst alanındaki karşılama.
  static const welcome = 'Hoş geldiniz';
  static const welcomeLine = 'Hesabınıza giriş yapın.';
  static const loginTitle = 'Giriş yapın';
  static const loginSubtitle = 'Bayi ve müşteri hesapları için tek giriş.';
  static const modePassword = 'Şifre ile';
  static const modePhone = 'Numara ile';
  static const modeGroup = 'Giriş yöntemi';
  static const userLabel = 'E-posta ya da kullanıcı adı';
  static const passwordLabel = 'Şifre';
  static const showPassword = 'Şifreyi göster';
  static const hidePassword = 'Şifreyi gizle';
  static const show = 'Göster';
  static const hide = 'Gizle';
  static const loginButton = 'Giriş yap';
  static const loggingIn = 'Giriş yapılıyor';
  static const forgotPassword = 'Şifremi unuttum';
  static const noAccount = 'Hesabınız yok mu?';
  static const noAccountLink = 'Bayinizden davet isteyin';
  static const phoneLabel = 'Cep telefonu';
  static const phoneHint = '5XX XXX XX XX';
  static const phoneHelper =
      'Telefonla giriş, Profil bölümünde doğruladığınız numarayla çalışır.';
  static const sendCode = 'Kod gönder';
  static const sendingCode = 'Kod gönderiliyor';
  static const userRequired = 'Kullanıcı adınızı ya da e-postanızı girin.';
  static const passwordRequired = 'Şifrenizi girin.';
  static const demoTitle = 'Demo hesabı seçin';
  static const demoButton = 'Demo hesabı seç';
  static const demoCaption = 'Demo';
  static String demoSubtitle(String password, String code) =>
      'Sahte kip: şifre $password, kod $code. Bir hesaba dokunun, giriş yapılır.';

  /// Giriş ekranındaki demo bölümü (sahip kararı 2026-10-21): bandın altında, formun üstünde.
  static const demoSectionTitle = 'Demo hesaplarıyla girin';
  static const demoTapHint = 'Tek dokunuşla giriş.';
  static String demoHint(String password, String code) =>
      '$demoTapHint Şifre $password, kod $code.';
  static const demoSeeAll = 'Tümünü gör';
  static const demoCardHint = 'Bu hesapla giriş yapar';
  static String demoSigningIn(String name) => '$name olarak giriş yapılıyor';
  static const demoGroupCustomer = 'Müşteri';
  static const demoGroupBayi = 'Bayi';
  static const demoGroupCenter = 'Merkez';

  /// Demo kartları ile form arasındaki ayraç.
  static const ownAccountDivider = 'Kendi hesabınızla girin';
  static String version(String label) => 'Sürüm $label';

  // ------------------------------------------------------------------ Hatalar ve sınırlar
  static const lockedTitle = 'Giriş geçici olarak kapalı';
  static const throttledTitle = 'Biraz bekleyin';
  static String rateLimited(String wait) =>
      'Çok fazla deneme. $wait sonra tekrar deneyin.';
  static String retryIn(String wait) => 'Tekrar dene ($wait)';
  static String retryInSpoken(String wait) => '$wait sonra tekrar deneyin';
  static const errorTitle = 'Giriş yapılamadı';
  static const codeErrorTitle = 'Kod gönderilemedi';
  static const offline =
      'Bağlantı yok. Bağlantınızı kontrol edip tekrar deneyin.';
  static const timeout =
      'Sunucu zamanında yanıt vermedi. Birkaç dakika sonra tekrar deneyin.';
  static const server =
      'Sunucuya şu an ulaşılamıyor. Birkaç dakika sonra tekrar deneyin.';
  static String supportCode(String code) => 'Destek kodu: $code';
  static const supportCodeHint = 'Kopyalamak için dokunun';
  static const supportCodeCopied = 'Destek kodu kopyalandı.';
  static const linkFailed =
      'Sayfa açılamadı. Tarayıcınızı kontrol edip tekrar deneyin.';
  static const offlineNotice =
      'Çevrimdışısınız. Giriş için internet bağlantısı gerekir.';
  static const updateBannerTitle = 'Yeni sürüm hazır';
  static const updateBannerBody =
      'Güncelleyerek yeni özelliklere ve iyileştirmelere ulaşabilirsiniz.';
  static const updateAction = 'Güncelle';

  // ------------------------------------------------------------------ Hesabım yok
  static const noAccountTitle = 'Hesabınız yok mu?';
  static const noAccountBody =
      'AkaryakıtNet hesapları bayiniz ya da şirketinizin yöneticisi tarafından açılır. '
      'Hesabınız açılınca e-postanıza bir davet bağlantısı gelir; bağlantıdan şifrenizi '
      'belirleyip giriş yapabilirsiniz.';
  static const noAccountCustomer =
      'Müşteriyseniz çalıştığınız bayiden ya da şirketinizin AkaryakıtNet yöneticisinden isteyin.';
  static const noAccountBayi =
      'Bayi personeliyseniz bayi yöneticinizden hesap açmasını isteyin.';
  static const supportTitle = 'Destek';
  static const callSupport = 'Destek hattını arayın';
  static const whatsappSupport = 'WhatsApp\'tan yazın';
  static const emailSupport = 'E-posta gönderin';
  static const supportPage = 'Destek sayfası';
  static const noSupport = 'Destek iletişim bilgileri henüz tanımlanmadı.';
  static const supportMailSubject = 'AkaryakıtNet hesap talebi';

  // ------------------------------------------------------------------ Yasal
  static const privacy = 'Gizlilik';
  static const kvkk = 'KVKK';
  static const terms = 'Koşullar';
  static const privacySpoken = 'Gizlilik politikası';
  static const kvkkSpoken = 'KVKK aydınlatma metni';
  static const termsSpoken = 'Kullanım koşulları';

  // ------------------------------------------------------------------ Kod ekranı
  static const codeTitleTwoFactor = 'Doğrulama kodu';
  static const codeTitleOtp = 'Telefonla giriş';
  static const codeHeadline = 'Kodu girin';
  static String codeSentTo(String masked) =>
      '$masked numarasına gönderdiğimiz 6 haneli kodu girin.';
  static const codeSentGeneric =
      'Telefonunuza gönderdiğimiz 6 haneli kodu girin.';
  static const codeFieldLabel = 'Doğrulama kodu, 6 hane';
  static const verify = 'Doğrula';
  static const verifying = 'Doğrulanıyor';
  static const noCode = 'Kod gelmedi mi?';
  static const resend = 'Kodu tekrar gönder';
  static String resendIn(String wait) => 'Kodu tekrar gönder ($wait)';
  static String resendInSpoken(String wait) =>
      '$wait sonra yeniden gönderebilirsiniz';
  static const codeResent = 'Yeni kod gönderildi.';
  static String codeExpiresIn(String wait) => 'Kod $wait geçerli.';
  static const codeExpired = 'Kodun süresi doldu. Yeni kod isteyin.';
  static const codeIncomplete = '6 haneli kodu girin.';
  static const twoFactorNote =
      'Hesabınızda iki adımlı doğrulama açık. Numaranız değiştiyse yöneticinize başvurun.';
  static const otpNote =
      'Kod gelmediyse numaranın Profil bölümünde doğrulanmış olduğundan emin olun.';
  static const missingChallenge = 'Kod isteği bulunamadı';
  static const missingChallengeBody =
      'Kod isteğinin süresi doldu. Girişe dönüp yeniden giriş yapın.';
  static const backToLogin = 'Girişe dön';
  static const restart = 'Baştan başla';

  // ------------------------------------------------------------------ Telefon doğrulama
  static const phoneTitle = 'Telefon doğrulama';
  static const phoneIntroTitle = 'Telefonla giriş';
  static const phoneIntroBody =
      'Cep telefonunuzu SMS ile doğrulayın; sonraki girişlerde şifre yerine telefonunuza '
      'gelen tek kullanımlık kodu kullanabilirsiniz.';
  static const phoneNumberLabel = 'Cep telefonu';
  static const phoneVerified = 'Doğrulandı';
  static const phoneNotVerified = 'Doğrulanmadı';
  static const phoneVerifiedBody =
      'Bu numarayla giriş ekranında "Telefonla" seçeneğini kullanabilirsiniz.';
  static const phoneChangeNote =
      'Numaranız değişirse telefonla giriş kapanır; yeni numarayı yeniden doğrulamanız gerekir.';
  static const sendVerification = 'Doğrulama kodu gönder';
  static const reverify = 'Yeniden doğrula';
  static const noPhoneTitle = 'Profilinizde cep telefonu yok';
  static const noPhoneBody =
      'Önce Profil bölümünden cep telefonunuzu ekleyin, sonra buradan doğrulayın.';
  static const otpOffNote =
      'Telefonla giriş şu an kapalı. Numaranızı yine de doğrulayabilirsiniz; özellik açılınca hazır olur.';
  static const platformNote =
      'Merkez hesapları telefonla giriş yapamaz; girişte şifre ve SMS kodu kullanılır.';
  static const phoneDoneTitle = 'Telefonunuz doğrulandı';
  static const phoneDoneBody =
      'Artık giriş ekranında "Telefonla" seçeneğiyle giriş yapabilirsiniz.';
  static const done = 'Tamam';
  static const statusLoadFailed = 'Telefon bilgileriniz yüklenemedi.';

  // ------------------------------------------------------------------ Güncelleme ve sunucu durumu
  static const forcedTitle = 'Güncelleme gerekli';
  static const forcedBody =
      'Bu sürüm artık desteklenmiyor. Devam etmek için AkaryakıtNet\'i güncelleyin.';
  static const openStore = 'Mağazada aç';
  static const noStoreBody =
      'AkaryakıtNet\'i App Store ya da Google Play üzerinden güncelleyin.';
  static const checkAgain = 'Tekrar kontrol et';
  static const optionalTitle = 'Yeni sürüm hazır';
  static const optionalBody =
      'AkaryakıtNet\'in yeni bir sürümü var. Güncelleyerek yeni özelliklere ve '
      'iyileştirmelere ulaşabilirsiniz.';
  static const later = 'Daha sonra';
  static const serverTitle = 'Sunucu güncel değil';
  static const serverBody =
      'Sunucu bu uygulama sürümüyle henüz uyumlu değil. Sunucu güncellenince kaldığınız '
      'yerden devam edebilirsiniz.';
  static const maintenanceTitle = 'Bakımdayız';
  static const maintenanceBody =
      'AkaryakıtNet kısa bir bakım çalışması yapıyor. Birkaç dakika sonra tekrar deneyin.';
  static const tryAgain = 'Tekrar dene';
  static const checking = 'Kontrol ediliyor';
  static String installedVersion(String label) => 'Yüklü sürüm: $label';

  // ------------------------------------------------------------------ Kilit
  static const lockedScreenTitle = 'Uygulama kilitli';
  static String welcomeBack(String name) => 'Tekrar hoş geldiniz, $name';
  static const lockedBody = 'Devam etmek için kimliğinizi doğrulayın.';
  static const biometricReason =
      'AkaryakıtNet\'i açmak için kimliğinizi doğrulayın';
  static const biometricCancelled = 'Doğrulama iptal edildi.';
  static const biometricFailed = 'Kimliğiniz doğrulanamadı.';
  static const biometricUnavailable =
      'Bu cihazda biyometrik doğrulama şu an kullanılamıyor.';
  static const biometricLockedOut =
      'Çok fazla deneme yapıldı. Biraz sonra yeniden deneyin ya da şifrenizle giriş yapın.';
  static const biometricError = 'Doğrulama tamamlanamadı.';
  static const passwordFallback = 'Şifreyle giriş yap';
  static const passwordFallbackNotice =
      'Güvenliğiniz için şifrenizle giriş yapın.';
  static const tryUnlockAgain = 'Tekrar dene';

  // ------------------------------------------------------------------ Biyometrik öneri
  static const offerTitle = 'Daha hızlı ve güvenli açılış';
  static String offerBody(String phrase) =>
      'Uygulamayı $phrase kilitleyin; bir dakikadan uzun arka planda kalınca '
      'kimliğiniz sorulsun. Profil bölümünden istediğiniz zaman kapatabilirsiniz.';
  static String offerAccept(String method) => '$method kullan';
  static const offerAcceptGeneric = 'Kilidi etkinleştir';
  static const offerLater = 'Şimdi değil';
  static const offerEnabled = 'Uygulama kilidi açıldı.';
}
