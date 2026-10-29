import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/access_policy.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/models/models.dart';
import '../copy.dart';
import '../data/home_models.dart';
import '../data/order_models.dart';
import 'home_controller.dart';

/// Teklif kararı ve teslim kabulü: web müşteri sipariş ayrıntısıyla TEK kural (panel eşitliği; sahip:
/// "panel tarafıyla uygulama tamamen birlikte çalışsın").
///
/// Panel (`CustomerController.OrderDetail`):
/// * Karar paneli (revize, red): sipariş "Onay bekliyor" ve Teklifler "Düzenler". Şirket rolü aranmaz.
/// * "Teklifi onayla": karar paneli açık ve şirket içi onay kilidi yok. Talep edenin, şirketin onay
///   eşiğini (litre ya da son teklif tutarı) aşan teklifinde onay kapalıdır; not
///   [OrdersCopy.requesterApproveBlocked], sunucu da onay denemesini aynı metinle reddeder. Revize ve
///   red açık kalır.
/// * Teslim kabulü: carinin "Onaylandı" siparişi, kabul bekleyen sevkiyat ve Sevkiyatlar "Düzenler".
///   Şirket rolü aranmaz.
///
/// Sunucu bu değerleri görüntüleyen için hesaplar (`canDecideQuote`, `canApproveQuote`,
/// `approveBlockedReason`, `canAcceptDelivery`; `orders/{id}`, `customers/me/orders`, `home/customer`,
/// `shipments`). Uygulama önce onları okur. Yayındaki eski API alanları göndermez: o zaman panelin
/// kuralı uygulamanın elindeki veriyle kurulur ([CustomerDecider]):
/// * yetkiler `me/access`'ten (Teklifler / Sevkiyatlar "Düzenler"), rol `customerUserRole`'dan;
/// * talep edenin eşiği ana sayfanın `companyApproval` kuralından ([CompanyApprovalRule.predicts],
///   sunucu `CustomerApprovalRules.RequiresApproval` portu; sunucu bu kuralı yalnızca talep edene
///   gönderir, onaylayan ve yönetici hiç kilitlenmez);
/// * kural okunamazsa (ana sayfa yok) onay panel gibi açık kalır, sunucu reddederse metni gösterilir
///   ve karar çubuğu kilitli onaya döner; ama teklif "Sıra sizde" sayılmaz ([QuoteRights.certain]):
///   ölü bir "Sıra sizde" hiç gösterilmez.
///
/// Finans kilidi (bayinin finans onayı / ek bilgi isteği) ve eksik ödeme belgesi bu değerlere katılmaz
/// (panelde de ayrı uygulanır).
@immutable
class QuoteRights {
  const QuoteRights({
    this.canDecide = false,
    this.canApprove = false,
    this.blockedReason,
    this.certain = true,
  });

  /// Karar yok.
  static const none = QuoteRights();

  /// Karar paneli açık: revize ve red (web `CanDecide`).
  final bool canDecide;

  /// "Teklifi onayla" açık (web `CanDecide` ve `ApproveNeedsCompanyApprover` değil).
  final bool canApprove;

  /// Onay şirket içi kuralla kapalıyken panelin notu (sunucunun ret metni).
  final String? blockedReason;

  /// Onayın açıklığı kesin: sunucu söyledi ya da yedek kural eşiği bildi. Talep edenin kuralı
  /// okunamadığında false: onay açık kalır, "Sıra sizde" sayılmaz.
  final bool certain;

  /// Onay şirket içi kuralla kapalı, revize ve red açık: sıra onaylayanın.
  bool get approveBlocked => canDecide && !canApprove;

  /// Teklif görüntüleyenin işi ("Sıra sizde", Onaylar rozeti, Bende, Siparişler): onay açık ve kesin.
  bool get yourMove => canApprove && certain;

  /// Sunucu onayı [message] ile reddetti (eski API'de kural bilinmiyordu): panel gibi onay kapanır,
  /// revize ve red açık kalır.
  QuoteRights refused(String message) => QuoteRights(
    canDecide: canDecide,
    blockedReason: canDecide ? message : null,
  );

  @override
  bool operator ==(Object other) =>
      other is QuoteRights &&
      other.canDecide == canDecide &&
      other.canApprove == canApprove &&
      other.blockedReason == blockedReason &&
      other.certain == certain;

  @override
  int get hashCode =>
      Object.hash(canDecide, canApprove, blockedReason, certain);

  @override
  String toString() =>
      'QuoteRights(decide: $canDecide, approve: $canApprove, '
      'blocked: $blockedReason, certain: $certain)';
}

/// Görüntüleyenin karar bağlamı: sunucunun değeri varsa o, yoksa panelin kuralı (bkz. [QuoteRights]).
@immutable
class CustomerDecider {
  const CustomerDecider({
    this.quotesEdit = false,
    this.shipmentsEdit = false,
    this.requester = false,
    this.companyRule,
  });

  /// Teklifler ve Sevkiyatlar "Düzenler", şirket içi kilit yok (yönetici; saf testler).
  static const full = CustomerDecider(quotesEdit: true, shipmentsEdit: true);

  /// `me/access` ve talep edende ana sayfanın şirket içi onay kuralı ([companyRule]).
  factory CustomerDecider.of(
    AccessPolicy policy, {
    CompanyApprovalRule? companyRule,
  }) => CustomerDecider(
    quotesEdit: policy.isCustomer && policy.can(Pg.customerQuotes, Perm.edit),
    shipmentsEdit:
        policy.isCustomer && policy.can(Pg.customerShipments, Perm.edit),
    requester:
        policy.isCustomer && policy.customerRole == CustomerUserRole.requester,
    companyRule: companyRule,
  );

  /// Teklifler "Düzenler" (panelin karar yetkisi; rol aranmaz).
  final bool quotesEdit;

  /// Sevkiyatlar "Düzenler" (panelin teslim kabulü yetkisi; rol aranmaz).
  final bool shipmentsEdit;

  /// Şirket rolü Talep eden: onay eşiğe tabidir. Onaylayan, Yönetici ve rolü boş eski kullanıcı
  /// eşiğe tabi değildir.
  final bool requester;

  /// Talep edenin şirket içi onay kuralı (`home/customer` → `companyApproval`); bilinmiyorsa null.
  final CompanyApprovalRule? companyRule;

  /// Teklif kararı: sunucunun değerleri ([canDecideQuote] null değilse aynen), yoksa panelin kuralı.
  /// [liters] siparişin litresi, [total] son teklifin (en yüksek sürüm) tutarı.
  QuoteRights quote({
    required OrderStatus status,
    required double liters,
    double? total,
    bool? canDecideQuote,
    bool? canApproveQuote,
    String? approveBlockedReason,
  }) {
    if (canDecideQuote != null) {
      final approve = canDecideQuote && (canApproveQuote ?? true);
      return QuoteRights(
        canDecide: canDecideQuote,
        canApprove: approve,
        blockedReason: canDecideQuote && !approve
            ? (approveBlockedReason ?? OrdersCopy.requesterApproveBlocked)
            : null,
      );
    }
    if (status != OrderStatus.awaitingApproval || !quotesEdit) {
      return QuoteRights.none;
    }
    if (!requester) return const QuoteRights(canDecide: true, canApprove: true);
    final rule = companyRule;
    if (rule == null) {
      // Kural bilinmiyor: panel gibi onay açık (sunucu reddederse metni gösterilir), sayılmaz.
      return const QuoteRights(
        canDecide: true,
        canApprove: true,
        certain: false,
      );
    }
    if (rule.predicts(totalLiters: liters, estimatedAmount: total)) {
      return const QuoteRights(
        canDecide: true,
        blockedReason: OrdersCopy.requesterApproveBlocked,
      );
    }
    return const QuoteRights(canDecide: true, canApprove: true);
  }

  /// Ana sayfanın karar satırı (`home/customer`).
  QuoteRights quoteOfRow(DashboardOrderRow r) => quote(
    status: r.status,
    liters: r.quantityLiters,
    total: r.latestTotalAmountTry,
    canDecideQuote: r.canDecideQuote,
    canApproveQuote: r.canApproveQuote,
    approveBlockedReason: r.approveBlockedReason,
  );

  /// Siparişler satırı (`customers/me/orders`; tutar = son teklifin tutarı).
  QuoteRights quoteOfOrder(CustomerOrderRow r) => quote(
    status: r.status,
    liters: r.quantityLiters,
    total: r.quotedTotal,
    canDecideQuote: r.canDecideQuote,
    canApproveQuote: r.canApproveQuote,
    approveBlockedReason: r.approveBlockedReason,
  );

  /// Sipariş ayrıntısı (`orders/{id}`): tutar panelin ifadesiyle, en yüksek sürümdeki teklifin tutarı.
  QuoteRights quoteOfDetail(OrderDetail d) {
    double? total = d.latestTotalAmountTry;
    if (d.quotes.isNotEmpty) {
      total = d.quotes
          .reduce((a, b) => a.version >= b.version ? a : b)
          .totalAmountTry;
    }
    return quote(
      status: d.status,
      liters: d.quantityLiters,
      total: total,
      canDecideQuote: d.canDecideQuote,
      canApproveQuote: d.canApproveQuote,
      approveBlockedReason: d.approveBlockedReason,
    );
  }

  /// Teslim kabulü: sunucunun değeri ([server]); yoksa Sevkiyatlar "Düzenler" ve [eligible] (carinin
  /// "Onaylandı" siparişinde kabul bekleyen sevkiyat).
  bool acceptsDelivery({bool? server, required bool eligible}) =>
      server ?? (shipmentsEdit && eligible);

  /// Ana sayfanın sevkiyat satırı (panelin listesi yalnızca "Onaylandı" siparişlerin sevkiyatlarıdır).
  bool acceptsShipmentRow(DashboardShipmentRow s) => acceptsDelivery(
    server: s.canAcceptDelivery,
    eligible: s.status == ShipmentStatus.reported,
  );

  /// Teslimatlar satırı (`shipments`; siparişin durumu satırda; eski yanıtta yoksa onaylı sayılır).
  bool acceptsListItem(ShipmentListItem x) => acceptsDelivery(
    server: x.canAcceptDelivery,
    eligible:
        x.status == ShipmentStatus.reported &&
        (x.orderStatus == OrderStatus.approved || x.orderStatus.isUnknown),
  );

  /// Siparişler satırı (etkin sevkiyat kabul bekliyor).
  bool acceptsOrderRow(CustomerOrderRow r) => acceptsDelivery(
    server: r.canAcceptDelivery,
    eligible:
        r.status == OrderStatus.approved &&
        r.activeShipmentStatus == ShipmentStatus.reported,
  );

  /// Sipariş ayrıntısı: sunucunun değeri; yoksa takibin girdisi (`canAcceptDeliveries`: carinin
  /// kendi "Onaylandı" siparişi), kabul bekleyen sevkiyat ve Sevkiyatlar "Düzenler" (panelin üç koşulu).
  bool acceptsOrder(OrderDetail d, OrderTracking? t) => acceptsDelivery(
    server: d.canAcceptDelivery,
    eligible: (t?.canAcceptDeliveries ?? false) && (t?.hasReported ?? false),
  );

  @override
  bool operator ==(Object other) =>
      other is CustomerDecider &&
      other.quotesEdit == quotesEdit &&
      other.shipmentsEdit == shipmentsEdit &&
      other.requester == requester &&
      other.companyRule?.required == companyRule?.required &&
      other.companyRule?.aboveLitres == companyRule?.aboveLitres &&
      other.companyRule?.aboveAmount == companyRule?.aboveAmount;

  @override
  int get hashCode => Object.hash(
    quotesEdit,
    shipmentsEdit,
    requester,
    companyRule?.required,
    companyRule?.aboveLitres,
    companyRule?.aboveAmount,
  );
}

/// Oturumdaki müşterinin karar bağlamı (`me/access` + ana sayfanın şirket içi onay kuralı).
final customerDeciderProvider = Provider.autoDispose<CustomerDecider>((ref) {
  final policy = ref.watch(accessPolicyProvider);
  final rule = policy.isCustomer
      ? ref.watch(customerHomeProvider.select((s) => s.data?.companyApproval))
      : null;
  return CustomerDecider.of(policy, companyRule: rule);
});
