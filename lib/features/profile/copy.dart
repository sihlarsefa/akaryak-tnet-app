/// Profil ve ayarlar metinleri (spec A.4 A8, C.7: "siz" dili, cümle düzeni; düğmeler ≤ 22 karakter).
abstract final class ProfileCopy {
  static const title = 'Profil';
  static const editProfile = 'Profili düzenle';

  // ------------------------------------------------------------------ Bölümler
  static const security = 'Güvenlik';
  static const notifications = 'Bildirimler';
  static const appearance = 'Görünüm';
  static const support = 'Destek';
  static const legal = 'Yasal';
  static const privacy = 'Gizlilik';
  static const app = 'Uygulama';

  // ------------------------------------------------------------------ Güvenlik
  static String biometricTitle(String method) => '$method ile kilitle';
  static const biometricHint =
      'Uygulama 1 dakikadan uzun arka planda kalınca kilitlenir.';
  static const biometricUnavailable =
      'Bu cihazda biyometrik doğrulama ya da ekran kilidi yok.';
  static const biometricReason = 'Uygulama kilidini açmak için doğrulayın';
  static const biometricFailed = 'Doğrulama yapılamadı; kilit açılmadı.';
  static const biometricOn = 'Uygulama kilidi açıldı.';
  static const changePassword = 'Şifre değiştir';
  static const changePasswordHint = 'Değişince tüm cihazlarda yeniden giriş';
  static const phoneLogin = 'Telefonla giriş';
  static const phoneLoginEnable = 'Telefonla girişi etkinleştir';
  static const phoneVerified =
      'Telefonunuz doğrulandı; SMS koduyla girebilirsiniz.';
  static const phoneNotVerified = 'Telefonunuzu doğrulayıp SMS koduyla girin.';
  static const phoneMissing = 'Profilinize cep telefonu ekleyin.';
  static const phoneOn = 'Açık';
  static const phoneOff = 'Kapalı';
  static const sessions = 'Aktif oturumlar';
  static const sessionsHint = 'Hesabınızın açık olduğu cihazlar';

  // ------------------------------------------------------------------ Bildirimler
  static const notificationPrefs = 'Bildirim tercihleri';
  static const notificationPrefsHint = 'Hangi bildirimlerin geleceğini seçin';

  // ------------------------------------------------------------------ Görünüm
  static const theme = 'Tema';
  static const themeSystem = 'Sistem';
  static const themeLight = 'Açık';
  static const themeDark = 'Koyu';

  // ------------------------------------------------------------------ Destek
  static const supportTitle = 'Destek ile görüş';
  static const supportSubtitle = 'Size en uygun kanalı seçin';
  static const supportCall = 'Telefonla arayın';
  static const supportWhatsapp = 'WhatsApp ile yazın';
  static const supportEmail = 'E-posta gönderin';
  static const supportPage = 'Yardım ve iletişim';
  static const supportPageHint = 'Destek sayfasını açar';
  static const supportMailSubject = 'AkaryakıtNet mobil destek';
  static const askAssistant = 'Asistana sorun';
  static const askAssistantHint = 'Uygulamanın kullanımıyla ilgili sorular';
  static const linkFailed =
      'Sayfa açılamadı. Tarayıcınızı kontrol edip tekrar deneyin.';

  // ------------------------------------------------------------------ Yasal
  static const privacyPolicy = 'Gizlilik politikası';
  static const kvkk = 'KVKK aydınlatma metni';
  static const terms = 'Kullanım koşulları';
  static const aiDisclosure = 'Yapay zekâ aydınlatma metni';

  // ------------------------------------------------------------------ Gizlilik
  static const assistantConsent = 'Asistan onayı';
  static String consentGiven(String? date) => date == null
      ? 'Aydınlatma metnini onayladınız.'
      : '$date tarihinde onayladınız.';
  static const consentNotGiven =
      'Asistanı ilk kullanımda aydınlatma metnini onaylarsınız.';
  static const consentChecking = 'Durum denetleniyor…';
  static const withdraw = 'Onayı geri al';
  static const withdrawTitle = 'Asistan onayı geri alınsın mı?';
  static const withdrawMessage =
      'Asistanı yeniden kullanmak için aydınlatma metnini tekrar onaylamanız gerekir. '
      'Sohbet kayıtlarınız saklama süresi dolunca silinir.';
  static const withdrawDone = 'Asistan onayınız geri alındı.';
  static const withdrawFailed =
      'Onay geri alınamadı. Bağlantınızı kontrol edip tekrar deneyin.';
  static const permissions = 'Uygulama izinleri';
  static const permissionsHint = 'Konum, kamera ve bildirim izinleri';

  // ------------------------------------------------------------------ Uygulama
  static const pendingOps = 'Bekleyen işlemler';
  static const pendingNone = 'Gönderilmeyi bekleyen işlem yok';
  static String pendingCount(int n) => '$n işlem gönderilmeyi bekliyor';
  static const about = 'Hakkında';
  static String server(String s) => 'Sunucu $s';
  static const biometricGeneric = 'Biyometri';
  static String version(String v, String env) => 'Sürüm $v, $env';
  static const devMenu = 'Geliştirici menüsü';
  static const devMenuHint =
      'Demo hesapları, hata enjeksiyonu, tasarım galerisi';

  // ------------------------------------------------------------------ Çıkış
  static const signOut = 'Çıkış yap';
  static const signOutTitle = 'Çıkış yapılsın mı?';
  static const signOutAllTitle = 'Tüm cihazlardan çıkılsın mı?';
  static const signOutAllMessage =
      'Bu cihaz dahil hesabınızın açık olduğu tüm cihazlarda oturum kapanır.';
  static String pendingTitle(int n) => 'Gönderilmeyi bekleyen $n işlem var';
  static const pendingMessage =
      'Çıkış yaparsanız bu işlemler bu cihazdan silinir ve sunucuya gönderilmez.';
  static const sendNow = 'Şimdi gönder';
  static const signOutAnyway = 'Yine de çık (işlemler silinir)';
  static const cancel = 'Vazgeç';
  static const sendOffline =
      'İnternet bağlantısı yok; işlemler şu an gönderilemez.';
  static String stillPending(int n) =>
      '$n işlem gönderilemedi. Bağlantınızı kontrol edip tekrar deneyin.';
  static const sentAll = 'Bekleyen işlemler gönderildi.';
  static const securityChanged =
      'Güvenlik bilgileriniz değişti; yeniden giriş yapın.';

  // ------------------------------------------------------------------ Profil düzenle
  static const editTitle = 'Profil bilgileri';
  static const fullName = 'Ad soyad';
  static const fullNameRequired = 'Ad soyad zorunludur.';
  static const fullNameTooLong = 'Ad soyad en fazla 150 karakter olabilir.';
  static const mobilePhone = 'Cep telefonu';
  static const mobilePhoneHelper = 'SMS kodları bu numaraya gelir.';
  static const email = 'E-posta';
  static const emailHint =
      'E-posta adresinizi bayiniz ya da şirket yöneticiniz değiştirebilir.';
  static const currentPassword = 'Mevcut şifre';
  static const currentPasswordRequired = 'Mevcut şifrenizi girin.';
  static const phoneChangeNote =
      'Telefon değişince tüm cihazlarda oturumunuz kapanır ve telefonla giriş için numaranızı yeniden doğrulamanız gerekir.';
  static const save = 'Kaydet';
  static const leaveTitle = 'Girdiğiniz bilgiler kaydedilmedi';
  static const leaveMessage = 'Değişiklikler kaybolacak.';
  static const leave = 'Çık';
  static const stay = 'Devam et';
  static const saved = 'Bilgileriniz güncellendi.';
  static const profileLoadFailed = 'Profil bilgileri yüklenemedi';
  static const role = 'Rol';
  static const organization = 'Bağlı olduğu yer';

  // ------------------------------------------------------------------ Şifre
  static const passwordTitle = 'Şifre değiştir';
  static const passwordIntro =
      'Şifreniz değişince güvenliğiniz için tüm cihazlarda oturumunuz kapanır.';
  static const newPassword = 'Yeni şifre';
  static const newPasswordAgain = 'Yeni şifre (tekrar)';
  static const passwordMismatch = 'Şifreler aynı değil.';
  static const passwordSame = 'Yeni şifre mevcut şifreden farklı olmalıdır.';
  static const ruleLength = 'En az 8 karakter';
  static const ruleUpper = 'En az bir büyük harf';
  static const ruleLower = 'En az bir küçük harf';
  static const ruleDigit = 'En az bir rakam';
  static const passwordRules = 'Şifre kurallarını sağlayın.';
  static const passwordSave = 'Şifreyi değiştir';
  static const passwordDoneTitle = 'Şifreniz değişti';
  static const passwordDoneMessage =
      'Güvenliğiniz için tüm cihazlarda oturumunuz kapandı. Yeni şifrenizle giriş yapın.';
  static const toLogin = 'Giriş ekranına git';
  static const showPassword = 'Şifreyi göster';
  static const hidePassword = 'Şifreyi gizle';

  // ------------------------------------------------------------------ Oturumlar
  static const sessionsTitle = 'Aktif oturumlar';
  static const thisDevice = 'Bu cihaz';
  static String lastSeen(String when) => 'Son etkinlik $when';

  /// Cümle içinde (sürümden sonra): "son etkinlik …".
  static String lastSeenInline(String when) => 'son etkinlik $when';
  static const revoke = 'Oturumu kapat';
  static const revokeTitle = 'Bu cihazdaki oturum kapatılsın mı?';
  static const revokeMessage =
      'O cihazda yeniden giriş yapılana kadar hesabınız açılmaz ve bildirim gitmez.';
  static const revoked = 'Oturum kapatıldı.';
  static const signOutAll = 'Tüm cihazlardan çık';
  static const onlyThisDevice = 'Hesabınız yalnızca bu cihazda açık.';
  static const sessionsLoadFailed = 'Oturumlar yüklenemedi';
  static const unknownDevice = 'Bilinmeyen cihaz';
  static const androidPhone = 'Android telefon';
  static const iphone = 'iPhone';
  static String appVersion(String v) => 'AkaryakıtNet $v';

  // ------------------------------------------------------------------ Hesabımı sil
  static const deleteAccount = 'Hesabımı sil';
  static const deleteTitle = 'Hesabımı sil';
  static const deleteIntro =
      'Hesabınızı kapatıp kişisel verilerinizin silinmesini isteyebilirsiniz. Bu işlem geri alınamaz.';
  static const deletedTitle = 'Silinecekler';
  static const deletedItems = [
    'Ad soyad, kullanıcı adı ve e-posta adresiniz',
    'Telefon numaranız ve şifreniz',
    'Cihaz kayıtlarınız, oturumlarınız ve bildirimleriniz',
    'Asistan sohbet metinleriniz',
  ];
  static const keptTitle = 'Saklananlar';
  static const keptItems = [
    'Siparişler, teklifler, teslimat ve onay kayıtları',
    'Ödeme belgeleri ve işlem kayıtları',
  ];
  static const keptNote =
      'Bu kayıtlar yasal saklama yükümlülüğü nedeniyle tutulur; adınız yerine "Silinmiş kullanıcı" görünür.';
  static const timelineTitle = 'Nasıl ilerler?';
  static const timelineToday = 'Bugün';
  static const timelineTodayBody =
      'Hesabınız kapanır, tüm cihazlarda oturumunuz sonlanır ve bildirim gönderilmez.';
  static const timeline14 = '14 gün';
  static const timeline14Body =
      'Fikrinizi değiştirirseniz bu süre içinde bayinize ya da şirket yöneticinize başvurarak hesabınızı yeniden açtırabilirsiniz.';
  static const timelineAfter = 'Sonrası';
  static const timelineAfterBody =
      'Kişisel verileriniz anonimleştirilir; en geç 30 gün içinde tamamlanır.';
  static const reasonTitle = 'Neden ayrılıyorsunuz? (isteğe bağlı)';
  static const reasons = [
    'Uygulamayı artık kullanmıyorum',
    'Şirketten ayrıldım',
    'Başka bir hesap kullanacağım',
    'Diğer',
  ];
  static const reasonNote = 'Açıklama (isteğe bağlı)';
  static const passwordToConfirm = 'Onay için şifreniz';
  static const passwordToConfirmRequired = 'Şifrenizi girin.';
  static const confirmUnderstand =
      'Hesabımın kapanacağını ve kişisel verilerimin silineceğini anladım.';
  static const confirmUnderstandRequired = 'Devam etmek için onaylayın.';
  static const deleteButton = 'Hesabımı sil';
  static const deleteConfirmTitle = 'Hesabınız kapatılsın mı?';
  static const deleteConfirmMessage =
      'Hesabınız hemen kapanır ve bu cihazdan çıkış yapılır.';
  static String deletePendingWarning(int n) =>
      'Gönderilmeyi bekleyen $n işleminiz var; hesap kapanınca gönderilmez.';
  static const deleteDoneTitle = 'Talebiniz alındı';
  static String requestNumber(String id) => 'Talep numarası: $id';
  static String scheduledFor(String date) => 'Anonimleştirme tarihi: $date';
  static const deleteDoneDefault =
      'Hesabınız kapatıldı. Kişisel verileriniz en geç 30 gün içinde silinecek.';
  static const deleteDoneButton = 'Tamam';
  static const requestIdLabel = 'Talep numarası';
  static const scheduledLabel = 'Anonimleştirme';
  static const accountClosed = 'Hesabınız kapatıldı.';
  static const deletionInfoLink = 'Hesap silme hakkında';
}
