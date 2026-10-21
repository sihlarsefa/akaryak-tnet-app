/// Müşteri ana sayfası Türkçe metinleri (spec C.5 tarifi).
library;

abstract final class HomeCopy {
  static const newOrder = 'Sipariş ver';
  static const newOrderHint =
      'Ürün, litre ve teslimat noktasıyla dakikalar içinde';
  static const decisions = 'Karar bekleyen teklifler';
  static const documents = 'Yüklenecek ödeme belgeleri';
  static const delivery = 'Teslimat';
  static const limits = 'Limitlerim';
  static const templates = 'Şablonlarım';
  static const spending = 'Harcamalar';
  static const all = 'Tümü';
  static const resumeTitle = 'Yarım kalan siparişinize devam edin';
  static const resumeChecking = 'Siparişiniz kontrol ediliyor';
  static const tipTitle = 'İlk siparişinizi verin';
  static const tipMessage =
      'Ürünü ve litreyi seçin, teslimat noktanızı ve ödeme yönteminizi belirleyin. '
      'Bayiniz teklif verince size haber veririz; teklifi buradan onaylarsınız.';
  static const assistantTitle = 'Asistana sorun';
  static const assistantMessage =
      '“Siparişim nerede?”, “Çek nasıl yüklerim?” gibi sorularınızı yanıtlar.';
  static const assistant = 'Asistan';
  static const companyApprovals = 'Onayınızı bekleyen talepler';
  static const financeInfo = 'Finans ek bilgi bekliyor';
  static const financeInfoMessage =
      'Bayinin finans ekibi sizden bilgi ya da belge istedi. Yanıt verene kadar siparişleriniz bekleyebilir.';
  static const blockedTitle = 'Şu an sipariş veremezsiniz';
  static const limitsEmpty = 'Tanımlı limit yok';
  static const limitsEmptyMessage =
      'Bayileriniz sizin için bir alım limiti tanımlamadı; siparişleriniz limitsiz değerlendirilir.';
  static const unlimited = 'Limitsiz';
  static const spendingCaption = 'Onaylanmış teklif tutarları; fatura değildir';

  static String greeting(DateTime wall) {
    final h = wall.hour;
    if (h < 5) return 'İyi geceler';
    if (h < 12) return 'Günaydın';
    if (h < 18) return 'İyi günler';
    return 'İyi akşamlar';
  }
}
