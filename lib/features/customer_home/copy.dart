/// Müşteri ana sayfası Türkçe metinleri (tasarım v2 §7.4, §10: siz dili, cümle düzeni, " · " yok).
library;

import '../../core/utils/turkish_text.dart';

abstract final class HomeCopy {
  static const newOrder = 'Sipariş ver';
  static const newOrderHint =
      'Ürün, litre ve teslimat noktasıyla dakikalar içinde';
  static const decisions = 'Karar bekleyen teklifler';
  static const documents = 'Yüklenecek ödeme belgeleri';
  static const documentsHint = 'Belge yüklenene kadar teklif onaylanamaz.';

  /// Teslimat bölümü: sevkiyat yoldayken "Yolda", değilse "Teslimat" (§10.4).
  static const delivery = 'Teslimat';
  static const inTransit = 'Yolda';
  static const track = 'Takip et';
  static const plannedArrival = 'planlanan varış';
  static const plannedDelivery = 'planlanan teslim';
  static const limits = 'Limitler';
  static const templates = 'Şablonlar';
  static const spending = 'Harcamalar';
  static const monthPlate = 'Bu ay harcama';
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
  static const myRequests = 'Taleplerim';
  static const financeInfo = 'Finans ek bilgi bekliyor';
  static const financeInfoMessage =
      'Bayinin finans ekibi sizden bilgi ya da belge istedi. Yanıt verene kadar siparişleriniz bekleyebilir.';
  static const blockedTitle = 'Şu an sipariş veremezsiniz';
  static const limitsEmpty = 'Tanımlı limit yok';
  static const limitsEmptyMessage =
      'Bayileriniz sizin için bir alım limiti tanımlamadı; siparişleriniz limitsiz değerlendirilir.';
  static const limitsNote =
      'Limit, onaylanan ve yoldaki siparişlerinizle dolar. Aşan siparişler bayinin finans onayına '
      'düşebilir.';
  static const unlimited = 'Limitsiz';
  static const unlimitedMessage = 'Bu bayide alım limitiniz yok.';
  static const spendingCaption = 'Onaylanmış teklif tutarları; fatura değildir';
  static const station = 'Bayiniz';

  // v4 "Sade" (§3.3): görev kartı, ilk açılış ipucu ve bölümler.
  static const calmCreate = 'Yeni sipariş için + tuşuna dokunun.';
  static const calmView = 'Siparişlerinizi Siparişler sekmesinden izleyin.';
  static const onTheWay = 'Yolda';
  static const arrivingToday = 'Bugün gelecek';
  static const quickOrder = 'Hızlı sipariş';
  static const reorderLast = 'Son siparişi tekrarla';
  static const firstOrder = 'İlk siparişinizi verin';
  static const call = 'Ara';

  /// Talep eden: siparişi şirketin onayına gönderir.
  static const requesterSteps = [
    'Sipariş ver tuşuyla ürünü, miktarı ve teslim yerini seçin.',
    'Talebiniz şirketinizdeki onaylayana gider.',
    'Onaylanınca bayiniz teklif verir; siparişi Siparişler sekmesinden izleyin.',
  ];

  /// Görüntüleyen: sipariş vermez, izler.
  static const viewerSteps = [
    'Siparişlerinizi Siparişler sekmesinden izleyin.',
    'Yoldaki araç ana sayfada, Yolda bölümünde görünür.',
    'Teslim edilen yakıtı Teslimat sekmesinde bulun.',
  ];

  /// "Limit · Demir Petrol".
  static String limitTitle(String? title) {
    final s = shortCompany(title);
    return s.isEmpty ? 'Limit' : 'Limit · $s';
  }

  /// "Bayiniz · Demir Petrol".
  static String stationTitle(String? title) {
    final s = shortCompany(title);
    return s.isEmpty ? HomeCopy.station : '${HomeCopy.station} · $s';
  }

  static String greeting(DateTime wall) {
    final h = wall.hour;
    if (h < 5) return 'İyi geceler';
    if (h < 12) return 'Günaydın';
    if (h < 18) return 'İyi günler';
    return 'İyi akşamlar';
  }

  /// "Selin Aydın, yönetici" (ana sayfa başlığının ikinci satırı).
  static String person(String name, String? role) {
    final n = name.trim();
    final r = role?.trim() ?? '';
    if (r.isEmpty) return n;
    if (n.isEmpty) return r;
    return '$n, ${TurkishText.lower(r)}';
  }

  /// "Demir Petrol teklifi": bayi unvanının ilk anlamlı kısmı (hukuki ek ve "Akaryakıt" atılır).
  static String quoteTitle(String? station) {
    final s = shortCompany(station);
    return s.isEmpty ? 'Bayi teklifi' : '$s teklifi';
  }

  /// "Demir Petrol Akaryakıt Ltd. Şti." → "Demir Petrol".
  static String shortCompany(String? title) {
    final full = (title ?? '').trim();
    if (full.isEmpty) return '';
    const stops = {
      'akaryakıt',
      'akaryakit',
      'ltd.',
      'ltd',
      'şti.',
      'şti',
      'a.ş.',
      'a.ş',
      'aş',
      'tic.',
      'san.',
      'limited',
      'anonim',
      've',
    };
    final kept = <String>[];
    for (final w in full.split(RegExp(r'\s+'))) {
      if (stops.contains(TurkishText.lower(w))) break;
      kept.add(w);
    }
    final out = kept.join(' ').trim();
    return out.isEmpty ? full : out;
  }

  /// Bekleyen şirket içi talep sayısı (talep satırları gelmediğinde).
  static String approvalsWaiting(int n) =>
      '$n şirket içi sipariş talebi kararınızı bekliyor.';
}
