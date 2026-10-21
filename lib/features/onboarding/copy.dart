/// Tanıtımın Türkçe metinleri (spec A.4 A1, C.7; tasarım v2 §7.3): üç sahne, siparişten teslimata. Bayi
/// ve müşteri aynı uygulamayı kullandığı için metinler iki tarafa da uyar. Üst etiketler (eyebrow)
/// v2'de çizilmez; yalnızca API uyumu için durur.
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
      'Örnek sipariş özeti: 12.500 litre motorin, yarın 09:00 teslim; sipariş bayiye gönderildi.';

  // Sahne 2 — Teklif
  static const quoteEyebrow = 'Teklif';
  static const quoteTitle = 'Teklif ve onay tek ekranda';
  static const quoteBody =
      'Fiyat ve teslim tarihi hazır olunca bildirim gelir; onay, revize ya da ret '
      'tek dokunuşla.';
  static const quoteScene =
      'Örnek teklif: 529.375 lira, litresi 42,35 lira, yarın teslim; teklif onaylandı.';

  // Sahne 3 — Teslimat
  static const deliveryEyebrow = 'Teslimat';
  static const deliveryTitle = 'Teslimat adım adım';
  static const deliveryBody =
      'Planlamadan yola çıkışa, teslim kanıtına kadar her adım cebinizde.';
  static const deliveryScene =
      'Örnek teslimat: araç yolda, tahmini varış 11:20; planlandı ve yola çıktı adımları tamam, teslim bekleniyor.';

  // Sahne içi örnek metinler (yalnızca çizim; ekran okuyucu sahne açıklamasını okur). Sayılar ve
  // tarihler gerçek arayüzdeki biçimle (tr_TR).
  static const wizardTitle = 'Yeni sipariş';
  static const wizardMeta = 'Özet, 4. adım';
  static const summaryTitle = 'Tahmini sipariş';
  static const litres = '12.500';
  static const litresSpoken = '12.500 litre';
  static const orderSentence = 'motorin, yarın 09:00 teslim';
  static const product = 'Motorin';
  static const productCaption = 'Ürün';
  static const quantity = 'Miktar';
  static const delivery = 'Teslimat';
  static const deliveryValue = 'Yarın, 09:00';
  static const point = 'Nokta';
  static const pointValue = 'Merkez depo';
  static const placeOrder = 'Siparişi gönder';
  static const sent = 'Siparişiniz bayiye gönderildi';
  static const quoteOrder = 'Motorin, 12.500 L';
  static const awaitingDecision = 'Kararınızı bekliyor';
  static const quoteFrom = 'Demir Petrol teklifi';
  static const quoteTime = 'bugün 10:05';
  static const quoteSpoken = '529.375 lira';
  static const quoteReady = 'Teklif hazır';
  static const validFor = '2 sa 57 dk kaldı';
  static const total = 'Tahmini tutar';
  static const deliveryDate = 'Teslim';
  static const tomorrow = 'Yarın';
  static const revise = 'Revize iste';
  static const approve = 'Teklifi onayla';
  static const approved = 'Teklif onaylandı';
  static const approvedToast = 'Teklif onaylandı. Bayi sevkiyatı planlayacak.';
  static const inTransit = 'Yolda';
  static const origin = 'Bayi deposu, 09:58 çıktı';
  static const destination = 'Merkez depo';
  static const remaining = '18 km kaldı';
  static const eta = 'varış 11:20';
  static const etaShort = 'tahmini 11:20';
  static const deliveryRowTitle = 'Motorin, 12.500 L';
  static const deliveryRowMeta = 'Merkez depo, bugün';
  static const stepPlanned = 'Planlandı';
  static const stepDispatched = 'Yola çıktı';
  static const stepDelivered = 'Teslim edildi';
  static const plate = '34 AKN 101';
  static const unitPriceCaption = 'Birim fiyat (tahmini)';
  static const unitPriceShort = 'Birim fiyat';
  static const received = 'Teslim alınan';
}
