import '../../../core/utils/turkish_text.dart';
import '../data/notification_models.dart';

/// Gelen kutusunda bir bildirimin nasıl okunacağı (tasarım v4 §5 10, P4).
///
/// * [clean]: başlık ve metinden iç kodlar (SIP-, SVK-, TLP-, SF- …) çıkar. Kodlar yalnızca ayrıntı
///   sayfalarında, kopyalanabilir alt yazı olarak görünür; bildirim kim, ne ve nerede der.
/// * [actionOf]: sıranın görüntüleyende olduğu olaylar için tek eylem satırı ("Teklifi aç",
///   "Teslimatı onayla", "Talebi incele", "Bilgi gönder"). Bilgi veren olaylarda null.
abstract final class NotificationDisplay {
  /// Bir iç kod: 2–4 büyük harf, tire, rakamlarla biten parçalar ("SIP-20261028-12002",
  /// "TLP-00031", "SF-2026-00007").
  static const _code = r'\b[A-Z]{2,4}-\d[\d-]*\d\b|\b[A-Z]{2,4}-\d\b';

  /// Sondaki ": KOD" / " · KOD" / " – KOD" / " KOD" (başlıklarda "Teklif hazır: SIP-…").
  static final RegExp _trailing = RegExp('\\s*[:–·-]?\\s*(?:$_code)\\s*\$');

  /// Baştaki "KOD için " / "KOD: " / "KOD, " / "KOD ".
  static final RegExp _leading = RegExp(
    '^(?:$_code)\\s*(?:için\\s+|[:,]\\s*|\\s+)?',
  );

  /// Ortadaki " KOD" (önündeki boşlukla).
  static final RegExp _inner = RegExp('\\s*\\(?(?:$_code)\\)?');

  /// [text] içindeki iç kodlar çıkmış, boşlukları düzelmiş hali. Kod yoksa metin aynen döner.
  static String clean(String text) {
    if (!text.contains('-')) return text;
    var s = text.trim();
    final before = s;
    s = s.replaceFirst(_trailing, '');
    s = s.replaceFirst(_leading, '');
    s = s.replaceAll(_inner, '');
    if (s == before) return text;
    s = s
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'\s+([,.;:!?])'), r'$1')
        .replaceAll(RegExp(r'^[,.;:·\s]+'), '')
        .replaceAll(RegExp(r'[\s·:,–-]+$'), '')
        .trim();
    if (s.isEmpty) return text;
    // Cümle başı büyük harfle (Türkçe: i → İ).
    return '${TurkishText.upper(s.substring(0, 1))}${s.substring(1)}';
  }

  /// Sıra görüntüleyendeyse eylem satırı; değilse null. [canQuote] false: görüntüleyen teklif
  /// veremez (izleyici, sevkiyat) — "Yeni sipariş" onun için bilgidir, eylemi yoktur.
  static String? actionOf(UserNotification n, {bool canQuote = true}) {
    final route = n.route ?? '';
    return switch (n.eventCode) {
      // Müşteri: teklif geldi / süresi doluyor (bayinin kopyası bayi sipariş sayfasına gider).
      'order.quote_ready' ||
      'order.quote_expiring' when route.startsWith('/orders/') => 'Teklifi aç',
      // Bayi: yeni sipariş geldi; teklif vermek bayinin işi (v4 B17).
      'order.created' when canQuote && route.startsWith('/bayi/orders/') =>
        'Teklif ver',
      // Müşteri: teslim bildirildi (bayiye giden kopya bilgi verir: "müşteri onayı bekleniyor").
      'shipment.reported' when route.startsWith('/shipments/') =>
        'Teslimatı onayla',
      'approval.pending' ||
      'approval.reminder' ||
      'approval.escalated' => 'Talebi incele',
      'order.finance_info' || 'approval.info_requested' => 'Bilgi gönder',
      // Saha: finans ön kayıt için ek bilgi istedi (sunucu uyarı tonunda gönderir; onay, ret ve
      // dönüşüm bilgi verir). Rota ön kaydın kendisidir (v4 tur 2).
      'lead.updated'
          when n.severity == 2 && route.startsWith('/field/leads/') =>
        'Bilgi gönder',
      _ => null,
    };
  }

  /// Eylem satırının açtığı blok (`?focus=`, v4 §3.5): sayfa o bloğa kayar ve parlar — "Teklif ver"
  /// ve "Teklifi aç" teklifi, "Teslimatı onayla" teslimatı, "Talebi incele" talebin karar bloğunu
  /// açar. Eylemi olmayan olayda ya da bilinmeyen rotada null.
  static String? focusOf(UserNotification n) {
    if (actionOf(n) == null) return null;
    final path = Uri.tryParse(n.route ?? '')?.path ?? '';
    if (path.startsWith('/orders/') || path.startsWith('/bayi/orders/')) {
      return switch (n.eventCode) {
        'order.quote_ready' ||
        'order.quote_expiring' ||
        'order.created' => 'quote',
        _ => null,
      };
    }
    if (path.startsWith('/shipments/')) return 'delivery';
    if (path.startsWith('/approvals/')) return 'request';
    return null;
  }

  /// [route] (bildirimin erişilebilir hedefi) [focusOf] bloğuyla; rotada zaten `focus` varsa ya da
  /// blok yoksa olduğu gibi.
  static String withFocus(UserNotification n, String route) {
    final focus = focusOf(n);
    final uri = Uri.tryParse(route);
    if (focus == null || uri == null) return route;
    if (uri.queryParameters.containsKey('focus')) return route;
    return uri
        .replace(queryParameters: {...uri.queryParameters, 'focus': focus})
        .toString();
  }
}
