/// Şoför özelliğinin Türkçe metinleri (spec C.5: her özellik kendi boş/hata metinlerini tutar).
/// "Siz" dili, cümle düzeni; düğmeler ≤ 22, sekmeler ≤ 10 karakter.
abstract final class DriverCopy {
  // ------------------------------------------------------------------ Genel
  static const title = 'Teslimatlarım';
  static const tabToday = 'Bugün';
  static const tabUpcoming = 'Yaklaşan';
  static const tabHistory = 'Geçmiş';

  static const sectionTodo = 'Sırada';
  static const sectionDone = 'Tamamlanan';
  static const sectionDisputed = 'Düzeltme bekleyen';

  static const lastUpdated = 'Son güncelleme';

  // ------------------------------------------------------------------ Boş / hata
  static const emptyTodayTitle = 'Bugün için teslimat yok';
  static const emptyTodayMessage =
      'Size yeni bir teslimat atandığında burada görünür ve bildirim alırsınız.';
  static const emptyUpcomingTitle = 'Yaklaşan teslimat yok';
  static const emptyUpcomingMessage =
      'Yarın ve sonrası için planlanan teslimatlarınız burada listelenir.';
  static const emptyHistoryTitle = 'Son 30 günde teslimat yok';
  static const emptyHistoryMessage =
      'Bildirdiğiniz ve iptal edilen teslimatlar burada görünür.';
  static const offlineNoCacheTitle = 'Çevrimdışısınız';
  static const offlineNoCacheMessage =
      'Bu ekran için kayıtlı veri yok. Bağlantı gelince otomatik yenilenir.';
  static const forbiddenTitle = 'Bu ekranı görüntüleyemiyorsunuz';
  static const forbiddenMessage =
      'Teslimatlarım yalnızca sevkiyat yetkisi olan bayi personeline açıktır.';
  static const notFoundTitle = 'Bu kayıt artık görüntülenemiyor';
  static const notFoundMessage =
      'Teslimat başka bir şoföre atanmış ya da iptal edilmiş olabilir.';
  static const loadMoreFailed = 'Devamı yüklenemedi.';

  // ------------------------------------------------------------------ Kahraman
  static const nextStop = 'Sıradaki teslimat';
  static const enRoute = 'Yoldasınız';
  static const nothingToday = 'Bugün sırada teslimat yok';
  static const nothingTodayHint =
      'Yeni teslimat atanınca bildirim gelir. Yaklaşan teslimatlarınızı aşağıdan görebilirsiniz.';
  static const overdue = 'Gecikmiş';
  static String todaySummary(int open, int done) => done == 0
      ? '$open teslimat sırada'
      : '$open teslimat sırada · $done tamamlandı';

  // ------------------------------------------------------------------ İpucu
  static const tipTitle = 'Teslimatı kaydırarak onaylayın';
  static const tipBody =
      'Yola çıkarken ve teslim ederken düğmeyi sağa kaydırın; yanlışlıkla dokunmak işlem yapmaz. '
      'Bağlantı yoksa bilgiler telefonda saklanır ve sonra gönderilir.';
  static const tipDismiss = 'Anladım';

  // ------------------------------------------------------------------ Kart / ayrıntı
  static const actionStart = 'Yola çık';
  static const actionDeliver = 'Teslim et';
  static const actionFix = 'Teslimatı düzelt';
  static const actionDetail = 'Ayrıntı';
  static const actionNavigate = 'Yol tarifi';
  static const actionCall = 'Ara';
  static const actionResume = 'Devam et';
  static const slideStart = 'Kaydırarak yola çıkın';
  static const slideDeliver = 'Kaydırarak teslim edin';
  static const slideStartDone = 'Kaydedildi';
  static const disputedTitle = 'Müşteri itiraz etti';
  static const disputedFallback =
      'Müşteri teslimata itiraz etti. Bilgileri kontrol edip teslimatı düzeltin.';
  static const resumeDraft = 'Yarım kalan teslimat';
  static String resumeDraftBody(String code, String step) =>
      '$code · $step adımında kaldınız.';

  static const deliveryPoint = 'Teslimat noktası';
  static const accessNotes = 'Giriş ve erişim notları';
  static const tankCapacity = 'Tank kapasitesi';
  static const window = 'Teslim saatleri';
  static const contact = 'Yetkili';
  static const order = 'Sipariş';
  static const product = 'Ürün';
  static const planned = 'Planlanan';
  static const delivered = 'Teslim edilen';
  static const difference = 'Fark';

  /// Teslim edilen planlanandan az / fazla: "50 L eksik (planlanan 10.000 L)".
  static String differenceLine(
    String diff,
    String planned, {
    required bool less,
  }) => '$diff ${less ? 'eksik' : 'fazla'} (planlanan $planned)';
  static const scheduled = 'Plan';
  static const plate = 'Plaka';
  static const dispatchedAt = 'Yola çıkış';
  static const deliveredAt = 'Teslim';
  static const documentNo = 'İrsaliye no';
  static const recipient = 'Teslim alan';
  static const note = 'Not';
  static const signatureWaived = 'İmza alınamadı';
  static const proofTitle = 'Teslim kanıtı';
  static const noAddress = 'Adres bilgisi yok';
  static const openInMaps = 'Haritada aç';
  static const copyAddress = 'Adresi kopyala';
  static const addressCopied = 'Adres kopyalandı.';
  static const googleMaps = 'Google Haritalar';
  static const appleMaps = 'Apple Haritalar';
  static const navigateFailed = 'Harita uygulaması açılamadı.';
  static const callFailed = 'Arama başlatılamadı.';
  static const enRouteCaption = 'Yolda (canlı konum değildir)';
  static String enRouteSince(String time) => 'Yolda · çıkış $time';

  // ------------------------------------------------------------------ Bekleyen işlem
  static const opWaiting = 'Gönderilmeyi bekliyor';
  static const opSending = 'Gönderiliyor';
  static const opSent = 'Gönderildi';
  static const opAttention = 'İlgilenmeniz gerekiyor';
  static const opFix = 'Düzelt';
  static const opRetry = 'Tekrar dene';
  static const opDiscard = 'Vazgeç';
  static const queuedTitle = 'Kaydedildi — bağlantı gelince gönderilecek';
  static const queuedStartBody =
      'Yola çıkışınız telefonda saklandı. İnternet gelince otomatik gönderilir; bu sırada teslimata devam edebilirsiniz.';
  static const queuedDeliverBody =
      'Teslimat bilgileri telefonunuzda güvende. İnternet gelince otomatik gönderilir; uygulamayı kapatabilirsiniz.';
  static String nextAttempt(String time) => 'Sonraki deneme $time';
  static const startSentTitle = 'Yola çıktınız';
  static const startSentBody =
      'Müşteriye aracın yola çıktığı bildirildi. İyi yolculuklar.';
  static const deliverSentTitle = 'Teslimat bildirildi';
  static const deliverSentBody =
      'Müşteriye teslimatı onaylaması için bildirim gönderildi.';
  static const deliverFailedTitle = 'Teslimat gönderilemedi';
  static const startFailedTitle = 'Yola çıkış gönderilemedi';
  static const sendingTitle = 'Gönderiliyor…';
  static const backToList = 'Teslimatlarıma dön';
  static const discardOpTitle = 'Bekleyen işlem silinsin mi?';
  static const discardOpBody =
      'Bu bilgiler sunucuya gönderilmeyecek ve eklenen fotoğraflar silinecek.';
  static const startQueuedNote = 'Yola çıkış gönderilmeyi bekliyor';
  static String opsWaiting(int n) => '$n işlem gönderilmeyi bekliyor';
  static String opsWaitingOffline(int n) =>
      '$n işlem bağlantı gelince gönderilecek';
  static String opsAttention(int n) => '$n işlem ilgilenmenizi bekliyor';
  static const opsShow = 'Göster';
  static const deliverAlreadyQueued =
      'Bu teslimatın bilgileri gönderilmeyi bekliyor.';
  static const startAlreadyQueued =
      'Yola çıkışınız gönderilmeyi bekliyor; teslim edebilirsiniz.';
  static const reportedLocked =
      'Bu teslimat bildirildi. Değişiklik için bayinizle görüşün.';

  // ------------------------------------------------------------------ Teslim et sihirbazı
  static const flowTitle = 'Teslim et';
  static const flowFixTitle = 'Teslimatı düzelt';
  static const stepLiters = 'Teslim edilen litre';
  static const stepDocument = 'İrsaliye no';
  static const stepRecipient = 'Teslim alan';
  static const stepPhotos = 'Fotoğraf';
  static const stepSignature = 'İmza';
  static const stepSummary = 'Özet';
  static const stepShort = [
    'Litre',
    'İrsaliye',
    'Teslim alan',
    'Fotoğraf',
    'İmza',
    'Özet',
  ];
  static const next = 'İleri';
  static const back = 'Geri';
  static const close = 'Kapat';

  static const litersHint = 'Sayaçtaki teslim litresini girin.';
  static String plannedChip(String liters) => 'Planlanan: $liters';
  static const fillPlanned = 'Planlananı yaz';
  static const litersRequired = 'Teslim edilen litreyi girin.';
  static String litersMax(String max) =>
      'Planlanan litreyi aşamaz (en fazla $max).';
  static const litersDecimals = 'En çok 3 ondalık girilebilir.';
  static String tankWarning(String cap) =>
      'Girilen litre tank kapasitesini ($cap) aşıyor. Lütfen kontrol edin.';
  static const keyDelete = 'Sil';
  static const keyComma = 'Virgül';

  static const documentHint = 'İrsaliye üzerindeki numarayı yazın.';
  static const documentLabel = 'İrsaliye numarası';
  static const documentRequired = 'İrsaliye numarasını girin.';
  static const documentTooLong =
      'İrsaliye numarası en çok 100 karakter olabilir.';

  static const recipientHint =
      'Yakıtı teslim alan kişinin adı. İmzalayan kişi genellikle odur.';
  static const recipientLabel = 'Teslim alan kişi';
  static const recipientTooLong =
      'Teslim alan adı en çok 150 karakter olabilir.';
  static const recipientUseContact = 'Yetkiliyi yaz';

  static const photosHint =
      'Tankı, sayacı ve teslim noktasını gösteren fotoğraflar çekin.';
  static const photosRequired = 'En az 1 fotoğraf gerekli.';
  static const photosOptional = 'Fotoğraf isteğe bağlıdır ama önerilir.';
  static const photoTake = 'Fotoğraf çek';
  static const photoPick = 'Galeriden seç';
  static const photoRemove = 'Fotoğrafı kaldır';
  static const photoPrevious = 'Önceki teslimattan';
  static String photoCount(int n) => '$n fotoğraf';
  static const photoMax = 'En çok 20 fotoğraf eklenebilir.';
  static const photoFailed = 'Fotoğraf alınamadı. Lütfen tekrar deneyin.';

  static const signatureHint = 'Teslim alan kişi aşağıya imzalasın.';
  static const signatureOptional = 'İmza isteğe bağlıdır.';
  static const signatureRequired =
      'İmza alın ya da imza alınamama nedenini seçin.';
  static const signatureCantGet = 'İmza alınamıyor';
  static const signatureTaken = 'İmza alındı';
  static const signatureRedo = 'Yeniden imzalat';
  static const signaturePadHint = 'Teslim alan kişi burada imzalasın';
  static const waiverChange = 'Değiştir';
  static const waiverBackToSignature = 'İmza al';

  static const waiverTitle = 'İmza alınamıyor';
  static const waiverSubtitle =
      'Nedeni seçin. Bu durumda en az 1 fotoğraf ve teslim konumu zorunludur.';
  static const waiverNoteLabel = 'Açıklama';
  static const waiverNoteHintOther = 'İmzanın neden alınamadığını kısaca yazın';
  static const waiverNoteHint = 'İsteğe bağlı kısa açıklama';
  static const waiverNoteRequired =
      '"Diğer" seçildiğinde kısa bir açıklama yazın (en az 3 karakter).';
  static const waiverConfirm = 'Nedeni kaydet';
  static const waiverNeedsPhoto =
      'İmza alınamadığında en az 1 fotoğraf gerekir. Fotoğraf adımına dönüldü.';
  static const waiverNeedsGps =
      'İmza alınamadığında teslim konumu zorunludur. Konumu açın ya da imza alın.';

  static const summaryNote = 'Teslim notu (isteğe bağlı)';
  static const summaryNoteHint = 'Müşteri ve bayi görür';
  static const summaryRecipientMissing =
      'Teslim alan adı girilmedi. İmzalayan kişinin adını eklemeniz önerilir.';
  static const summaryNeedsGps = 'Teslim için konum gerekli.';
  static const summaryNotReady = 'Eksik bilgileri tamamlayın.';
  static const summaryEdit = 'Düzenle';
  static String summaryPhotos(int n) => n == 0 ? 'Yok' : '$n fotoğraf';

  static const leaveTitle = 'Girdiğiniz bilgiler kaydedilmedi';
  static const leaveBody =
      'Teslim bilgileri bu telefonda taslak olarak saklanabilir (24 saat).';
  static const leaveKeep = 'Taslak olarak sakla';
  static const leaveDiscard = 'Çık';
  static const leaveStay = 'Devam et';

  static const flowBlockedTitle = 'Bu teslimat şu an teslim edilemiyor';
  static const flowBlockedPlanned =
      'Teslim etmek için önce yola çıkın. Ayrıntı ekranındaki düğmeyi kaydırın.';

  // ------------------------------------------------------------------ Konum
  static const locationTitle = 'Teslim konumu';
  static const locationStartTitle = 'Yola çıkış konumu';
  static const locationAcquiring = 'Konum alınıyor…';
  static String locationOk(String accuracy) => 'Konum alındı · $accuracy';
  static String locationLowAccuracy(String accuracy) =>
      'Konum hassasiyeti düşük ($accuracy). Açık alanda tekrar deneyin.';
  static const locationApproximate = 'Hassas konum kapalı';
  static const locationApproximateBody =
      'Yalnızca yaklaşık konum paylaşılıyor. Daha doğru kayıt için ayarlardan hassas konumu açın.';
  static const locationAdd = 'Konum ekle';
  static const locationRetry = 'Tekrar dene';
  static const locationDenied = 'Konum izni kapalı';
  static const locationDeniedBody =
      'Konumu kaydedebilmemiz için ayarlardan konum iznini açın.';
  static const locationServiceOff = 'Konum servisleri kapalı';
  static const locationServiceOffBody =
      'Telefonunuzun konum servisini açıp tekrar deneyin.';
  static const locationFailed = 'Konum alınamadı';
  static const locationFailedBody =
      'Açık alanda birkaç saniye bekleyip tekrar deneyin.';
  static const locationOpenSettings = 'Ayarları aç';
  static const locationSkip = 'Konumsuz devam et';
  static const locationSkipped = 'Konum eklenmeyecek';
  static const locationOptionalHint =
      'Konum isteğe bağlıdır; eklenirse teslim kanıtına yazılır.';
  static const locationStartOptional =
      'Konum izni yok; yola çıkış konumsuz kaydedilir.';
  static String locationStartWill(String accuracy) =>
      'Yola çıkış konumu eklenecek ($accuracy)';

  // ------------------------------------------------------------------ İzin ön sayfaları
  static const primerLocationTitle = 'Konumunuzu ekleyelim mi?';
  static const primerLocationBody =
      'Teslimatı başlatırken ve tamamlarken konumunuzu yalnızca bu işlemlere eklemek için kullanırız.';
  static const primerCameraTitle = 'Kameraya erişim';
  static const primerCameraBody =
      'Teslim fotoğrafını çekip bu teslimata eklemeniz için kameranızı kullanırız.';
  static const primerContinue = 'Devam';
  static const primerNotNow = 'Şimdi değil';
  static const cameraDenied = 'Kamera izni kapalı';
  static const cameraDeniedBody =
      'Fotoğraf çekmek için ayarlardan kamera iznini açın ya da galeriden seçin.';
}
