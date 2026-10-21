/// Tanıtımın Türkçe metinleri (spec A.4 A1, C.7): üç sahne, siparişten teslimata. Bayi ve müşteri aynı
/// uygulamayı kullandığı için metinler iki tarafa da uyar.
abstract final class OnboardingCopy {
  static const skip = 'Atla';
  static const skipSpoken = 'Tanıtımı atla';
  static const next = 'Devam';
  static const start = 'Başlayalım';
  static String page(int index, int count) => 'Sayfa $index/$count';

  // Sahne 1 — Sipariş
  static const orderEyebrow = 'Sipariş';
  static const orderTitle = 'Sipariş birkaç dokunuşla';
  static const orderBody =
      'Ürün, litre ve teslimat noktası seçilir; sipariş bayiye anında ulaşır.';
  static const orderScene =
      'Örnek sipariş: motorin, 12.500 litre, yarın teslim; sipariş gönderildi.';

  // Sahne 2 — Teklif
  static const quoteEyebrow = 'Teklif';
  static const quoteTitle = 'Teklif ve onay tek ekranda';
  static const quoteBody =
      'Fiyat ve teslim tarihi hazır olunca bildirim gelir; onay, revize ya da ret '
      'tek dokunuşla.';
  static const quoteScene =
      'Örnek teklif: litre fiyatı ve toplam tutar, geçerlilik süresi ve onay düğmesi.';

  // Sahne 3 — Teslimat
  static const deliveryEyebrow = 'Teslimat';
  static const deliveryTitle = 'Teslimat adım adım';
  static const deliveryBody =
      'Planlamadan yola çıkışa, teslim kanıtına kadar her adım cebinizde.';
  static const deliveryScene =
      'Örnek teslimat: araç yolda, planlandı ve yola çıktı adımları tamam, teslim bekleniyor.';

  // Sahne içi örnek etiketler (yalnızca çizim; ekran okuyucu sahne açıklamasını okur)
  static const product = 'Motorin';
  static const productCaption = 'Ürün';
  static const quantity = 'Miktar';
  static const delivery = 'Teslimat';
  static const deliveryValue = 'Yarın, 09:00';
  static const point = 'Nokta';
  static const pointValue = 'Merkez depo';
  static const placeOrder = 'Sipariş ver';
  static const sent = 'Gönderildi';
  static const quoteReady = 'Teklif hazır';
  static const validFor = '25 dk';
  static const total = 'Toplam';
  static const deliveryDate = 'Teslim';
  static const tomorrow = 'Yarın';
  static const revise = 'Revize';
  static const approve = 'Onayla';
  static const approved = 'Onaylandı';
  static const inTransit = 'Yolda';
  static const origin = 'Bayi';
  static const destination = 'Depo';
  static const stepPlanned = 'Planlandı';
  static const stepDispatched = 'Yola çıktı';
  static const stepDelivered = 'Teslim edildi';
  static const plate = '34 AKN 101';
  static const unitPriceCaption = 'Litre fiyatı';
  static const received = 'Teslim alınan';
}
