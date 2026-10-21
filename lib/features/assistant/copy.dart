/// Asistan metinleri (spec A.6, C.7: "siz" dili, cümle düzeni; düğmeler ≤ 22 karakter).
abstract final class AssistantCopy {
  static const title = 'Asistan';
  static const subtitle = 'Yapay zekâ destekli yardım';
  static const close = 'Kapat';
  static const newChat = 'Yeni sohbet';
  static const support = 'Destek ile görüş';
  static const more = 'Diğer seçenekler';

  // ------------------------------------------------------------------ Karşılama
  static String greeting(String? firstName) =>
      firstName == null || firstName.isEmpty
      ? 'Merhaba, size nasıl yardımcı olabilirim?'
      : 'Merhaba $firstName, size nasıl yardımcı olabilirim?';
  static const intro =
      'Sipariş, teklif, ödeme, teslimat ve onay adımlarıyla ilgili sorularınızı yanıtlarım. '
      'Hesabınızda işlem yapmam.';
  static const starters = 'Şunları sorabilirsiniz';

  // ------------------------------------------------------------------ Mesajlar
  static const typing = 'Asistan yazıyor';
  static const you = 'Siz';
  static const assistant = 'Asistan';
  static const sendFailed = 'Gönderilemedi';
  static const retry = 'Tekrar dene';
  static const emptyReply = 'Bu soruya şu an yanıt veremiyorum.';
  static const consentAgain =
      'Aydınlatma metni güncellendi; onayladıktan sonra yeniden gönderin.';
  static const disabledMessage = 'Asistan şu an kullanılamıyor.';
  static const helpfulQuestion = 'Yanıt yararlı oldu mu?';
  static const helpful = 'Yararlı';
  static const notHelpful = 'Yararlı değil';
  static const thanks = 'Geri bildiriminiz için teşekkürler.';
  static const feedbackTitle = 'Neyi daha iyi yapabilirdik?';
  static const feedbackHint = 'İsteğe bağlı; kişisel bilgi yazmayın.';
  static const feedbackSend = 'Gönder';
  static const feedbackSkip = 'Yorum eklemeden gönder';
  static const copied = 'Yanıt kopyalandı.';
  static const linkFailed = 'Bağlantı açılamadı.';
  static const typingStatic = 'Yazıyor…';

  // ------------------------------------------------------------------ Yazma alanı
  static const inputHint = 'Sorunuzu yazın';
  static const inputLabel = 'Mesajınız';
  static const send = 'Gönder';
  static const privacyHint = 'Kişisel bilgi paylaşmayın.';
  static const aiFooter = 'Yanıtlar yapay zekâ ile oluşturulur.';
  static const kvkk = 'KVKK';
  static String cooldown(int seconds) =>
      'Çok fazla soru gönderdiniz. $seconds sn sonra tekrar deneyin.';
  static const offline = 'İnternet bağlantısı yok; mesaj gönderilemez.';

  // ------------------------------------------------------------------ Aydınlatma
  static const disclosureLead =
      'Asistanı kullanmadan önce okuyun. Kullanmak isteğe bağlıdır.';
  static const accept = 'Kabul ediyorum';
  static const decline = 'Vazgeç';
  static const fullText = 'Tam metni açın';
  static const doNotShare = 'Kart, şifre, kod paylaşmayın';
  static const doNotShareBody =
      'Kart numarası, şifre, SMS kodu, kimlik ya da vergi numarası yazmayın.';
  static String retention(int days) => 'Kayıtlar $days gün saklanır';
  static const optional = 'İsteğe bağlı';
  static const acceptFailed =
      'Onayınız kaydedilemedi. Bağlantınızı kontrol edip tekrar deneyin.';

  // ------------------------------------------------------------------ Durumlar
  static const disabledTitle = 'Asistan şu an kullanılamıyor';
  static const disabledBody =
      'Sorularınız için destek ekibimize ulaşabilirsiniz.';
  static const errorTitle = 'Asistan açılamadı';
  static const offlineTitle = 'Çevrimdışısınız';
  static const offlineBody =
      'Asistanı kullanmak için internet bağlantısı gerekir.';
}
