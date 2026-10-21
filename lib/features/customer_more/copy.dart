/// A3 ekran metinleri (spec C.5: her özelliğin boş / hata metinleri kendi `copy.dart` dosyasında).
abstract final class CmCopy {
  // Ortak
  static const offlineEmpty = 'Çevrimdışısınız; bu ekran için kayıtlı veri yok';
  static const offlineEmptyMessage =
      'Bağlantı gelince yeniden deneyin. Daha önce açtığınız ekranlar çevrimdışı da görünür.';
  static const forbiddenTitle = 'Bu ekrana erişiminiz yok';
  static const forbiddenMessage =
      'Yetkiniz değişmiş olabilir. Gerekirse şirket yöneticinize başvurun.';
  static const notFound = 'Bu kayıt artık görüntülenemiyor';
  static const filteredEmpty = 'Filtreye uyan kayıt yok';
  static const clearFilters = 'Filtreleri temizle';
  static const retry = 'Tekrar dene';
  static const offlineAction =
      'Bağlantı yok; işlem çevrimiçi olunca yapılabilir.';
  static const conflict = 'Bu kayıt sizden sonra güncellendi';

  // Teslimatlar
  static const shipmentsTitle = 'Teslimatlar';
  static const shipmentsEmpty = 'Henüz teslimat yok';
  static const shipmentsEmptyMessage =
      'Bayiniz siparişinizi planlayınca teslimatlar burada görünür.';
  static const historyEmpty = 'Geçmiş teslimat yok';
  static const proofTitle = 'Teslim kanıtı';
  static const acceptConfirmTitle = 'Teslimatı onaylıyor musunuz?';
  static const accepted = 'Teslimat onaylandı';
  static const acceptChecking = 'Teslimat kontrol ediliyor…';
  static const disputeChecking = 'İtiraz kontrol ediliyor…';
  static const disputeSent =
      'İtirazınız bayiye iletildi; düzeltme bildirilince yeniden onayınız istenecek';
  static const disputeNoteHint =
      'Eksik / fazla miktar, hasar, yanlış ürün… Ne gördüğünüzü kısaca yazın.';
  static const disputePhotoHint =
      'Fotoğraf eklemeniz itirazın hızlı çözülmesini sağlar (en fazla 6).';
  static const awaitingBanner = 'teslimat onayınızı bekliyor';

  // Belgeler
  static const documentsTitle = 'Belgeler';
  static const documentsEmpty = 'Bu aralıkta belge yok';
  static const documentsEmptyMessage =
      'Sipariş verdiğinizde sipariş formu, teklif ve teslimat belgeleri burada oluşur.';
  static const documentsFooter =
      'Belgeler uygulamada oluşturulur. Mali belge değildir; e-irsaliye/e-fatura yerine geçmez.';
  static const savedOnDevice = 'Cihazda kayıtlı';

  // Harcamalar
  static const spendingTitle = 'Harcamalar';
  static const spendingCaption = 'Onaylanmış teklif tutarları; fatura değildir';
  static const spendingEmpty =
      'Seçilen aralıkta onaylanmış ya da tamamlanmış sipariş yok.';

  // Teslimat noktaları
  static const pointsTitle = 'Teslimat noktaları';
  static const pointsEmpty = 'Kayıtlı teslimat noktası yok';
  static const pointsEmptyMessage =
      'Sipariş verirken seçebilmek için ilk teslimat noktanızı ekleyin.';
  static const useMyLocation = 'Bulunduğum konumu kullan';
  static const openInMaps = 'Haritada aç';
  static const locationPrimerTitle = 'Konumunuzu kullanalım mı?';
  static const locationPrimerMessage =
      'Teslimat noktasının konumunu bulunduğunuz yerden kaydetmek için konum izni gerekir. Konumunuz yalnızca bu kayıtta kullanılır.';
  static const preciseOff = 'Hassas konum kapalı';
  static const unsaved = 'Girdiğiniz bilgiler kaydedilmedi';

  // Talepler
  static const requestsTitle = 'Talepler';
  static const requestsEmpty = 'Şirket içi talep yok';
  static const requestsEmptyMessage =
      'Onay eşiğini aşan siparişler talep olarak buraya düşer; onaylanınca siparişe dönüşür.';

  // Finans bilgisi
  static const financeTitle = 'Finans bilgisi';
  static const financeIntro =
      'Bağlı olduğunuz bayilerin finans onayı ve finans ekibinin sizden istediği bilgiler. Yeni cari hesaplar, bayi finans onayından sonra sipariş verebilir.';
  static const financeNoLinks = 'Bağlı bayi yok';
  static const financeNoLinksMessage =
      'Bir bayi sizi davet ettiğinde finans durumu burada görünür.';
  static const financeAllClear = 'Finans açısından bekleyen bir işlem yok.';

  // Şirket kullanıcıları
  static const usersTitle = 'Şirket kullanıcıları';
  static const usersOnlyAdmin = 'Bu sayfayı şirket yöneticisi kullanır';
  static const usersOnlyAdminMessage =
      'Kullanıcı eklemek ya da rol değiştirmek için şirketinizin yöneticisine başvurun.';
  static const usersAlone =
      'Şu an şirketinizde yalnızca siz varsınız. Satın alma ekibinizi ekleyip rollerini belirleyebilirsiniz.';
  static const thresholdsTitle = 'Şirket içi onay eşikleri';
  static const thresholdsLitreHint =
      'Toplam miktar bunun üstündeyse onay gerekir.';
  static const thresholdsAmountHint =
      'Bayinin güncel fiyatıyla hesaplanır. Fiyat yoksa litre eşiği uygulanır; litre eşiği de boşsa sipariş onaya düşer.';
  static const thresholdsOff = 'İki alanı da boş bırakırsanız onay kapanır.';
}
