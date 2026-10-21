/// Saha özelliğinin Türkçe metinleri (spec C.5: boş/hata metinleri özellikte tutulur).
///
/// Ton: "siz", cümle düzeni; Bayi (İstasyon değil), cari (bayi tarafı); düğme ≤ 22 karakter.
abstract final class FieldCopy {
  // ---- Başlıklar
  static const tabRep = 'Saha';
  static const tabTeam = 'Saha ekibi';
  static const tabLeadsOnly = 'Ön kayıtlar';
  static const forms = 'Formlar';
  static const myForms = 'Formlarım';
  static const leads = 'Ön kayıtlar';
  static const myLeads = 'Ön kayıtlarım';
  static const portfolio = 'Portföy';
  static const pending = 'Onayda';
  static const rejected = 'Reddedilen';
  static const newForm = 'Saha formu';
  static const newLead = 'Ön kayıt';

  // ---- Boş durumlar
  static const formsEmptyTitle = 'Henüz saha formu yok';
  static const formsEmptyMessage =
      'Müşteri ziyaretinde fiyatı ve teslimatı birlikte belirleyip formu buradan gönderin.';
  static const teamFormsEmptyTitle = 'Bu görünümde form yok';
  static const teamFormsEmptyMessage =
      'Saha ekibinin doldurduğu formlar burada görünür.';
  static const pendingEmptyTitle = 'Onay bekleyen form yok';
  static const pendingEmptyMessage =
      'Gönderilen formlar onay kademesine göre burada listelenir.';
  static const rejectedEmptyTitle = 'Reddedilen form yok';
  static const leadsEmptyTitle = 'Henüz ön kayıt yok';
  static const leadsEmptyMessage =
      'Yeni bir firmayı ziyaret ettiğinizde ön kaydı buradan açın; vergi levhasını fotoğraflayıp finansa gönderin.';
  static const portfolioEmptyTitle = 'Portföyünüz boş';
  static const portfolioEmptyMessage =
      'Size atanmış cari yok. Bayi yöneticinizden portföy ataması isteyin.';
  static const filteredEmptyTitle = 'Filtreye uyan kayıt yok';
  static const filteredEmptyAction = 'Filtreleri temizle';
  static const offlineEmptyTitle = 'Çevrimdışısınız';
  static const offlineEmptyMessage =
      'Çevrimdışısınız; bu ekran için kayıtlı veri yok.';
  static const forbiddenTitle = 'Bu bölüm için yetkiniz yok';
  static const forbiddenMessage = 'Erişim için bayi yöneticinize başvurun.';
  static const notFoundTitle = 'Kayıt bulunamadı';
  static const notFoundMessage = 'Bu kayıt artık görüntülenemiyor.';

  // ---- Bekleyen işlemler
  static const queuedTitle = 'Kaydedildi — bağlantı gelince gönderilecek';
  static const queuedFormMessage =
      'Taslağınız bu cihazda saklandı. İnternet bağlantısı gelince otomatik gönderilir; durumunu Formlarım listesinde görebilirsiniz.';
  static const queuedLeadMessage =
      'Ön kaydınız bu cihazda saklandı. Bağlantı gelince otomatik gönderilir; durumunu Ön kayıtlarım listesinde görebilirsiniz.';
  static const waitingChip = 'Gönderilmeyi bekliyor';
  static const sendingChip = 'Gönderiliyor';
  static const attentionChip = 'İlgilenmeniz gerekiyor';

  // ---- Konum
  static const locationPrimerTitle = 'Konumunuzu kullanalım mı?';
  static const visitPrimerReason =
      'Ziyaret ettiğiniz yeri ön kayda eklemek için konumunuzu yalnızca bu işlemde kullanırız.';
  static const weatherPrimerReason =
      'Bulunduğunuz yerin hava durumunu göstermek için konumunuzu yalnızca bu ekranda kullanırız.';
  static const preciseOffTitle = 'Hassas konum kapalı';
  static const preciseOffMessage =
      'Yalnızca yaklaşık konum paylaşılıyor; ziyaret yeri yüzlerce metre şaşabilir. Ayarlardan "Hassas konum"u açın.';
  static const locationDeniedTitle = 'Konum izni kapalı';
  static const locationDeniedMessage =
      'Konumu eklemek için Ayarlar’dan bu uygulamaya konum izni verin.';
  static const locationServiceOffTitle = 'Konum servisleri kapalı';
  static const locationServiceOffMessage =
      'Telefonunuzun konum servisini açtıktan sonra tekrar deneyin.';

  // ---- Önizleme
  static const previewIdle =
      'Cari, ürün, litre ve fiyat girildiğinde onay bandı burada hesaplanır.';
  static const previewOffline =
      'Önizleme için bağlantı gerekir. Taslağı yine de kaydedebilirsiniz.';
  static const previewNoCosts =
      'Renk bandı formun hangi onaydan geçeceğini gösterir.';

  // ---- Genel
  static const retry = 'Tekrar dene';
  static const sectionFailed = 'Bu bölüm yüklenemedi';
  static const supportCode = 'Destek kodu';
}
