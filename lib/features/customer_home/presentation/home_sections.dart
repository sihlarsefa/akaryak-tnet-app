import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../../customer_more/api.dart';
import '../../customer_orders/api.dart';
import '../copy.dart';
import 'limits_page.dart';

/// Ana sayfada yerel tercih değişince (ipucu / asistan kartı kapatıldı) yeniden çizim.
final homeLocalRevisionProvider = NotifierProvider<HomeLocalRevision, int>(
  HomeLocalRevision.new,
);

class HomeLocalRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Ana sayfanın sayfa kenarı (tasarım v2 §4.1: 20).
const _gutter = AknSpace.page;

/// Kuyuların (uyarı, ipucu, taslak) dış boşluğu.
EdgeInsets _wellMargin(double top) =>
    EdgeInsets.fromLTRB(_gutter, top, _gutter, 0);

/// Bölüm başlığının hemen altındaki satırın dolgusu: başlıkla satır arası panodaki gibi sıkı
/// (eylemli başlık 48 px dokunma alanı nedeniyle zaten 11 px boşluk bırakır).
EdgeInsets homeFirstRow({required bool action}) =>
    EdgeInsets.fromLTRB(_gutter, action ? 0 : 10, _gutter, 12);

/// "1–21 Ekim": bu ayın bugüne kadarki dönemi.
String monthToDateLabel(DateTime wall) => wall.day == 1
    ? '1 ${Fmt.monthNames[wall.month - 1]}'
    : '1–${wall.day} ${Fmt.monthNames[wall.month - 1]}';

/// "2,25" + "mn ₺" (plaka okumalarında birim ayrı yazılır).
(String, String) compactMoneyParts(num value) {
  final s = Fmt.moneyCompact(value);
  final i = s.indexOf(' ');
  if (i < 0) return (s, '₺');
  return (s.substring(0, i), s.substring(i + 1));
}

/// Ana sayfa bölüm başlığı (tasarım v2 §6.7): [SectionHeader], başlık satırı eylemin 48 px dokunma
/// alanı yüzünden aşağı kaymasın diye dolgusu ölçülür; böylece başlığın üstü her zaman [top] (ilk
/// bölümde 16, sonra 20) olur. Altındaki ilk satır [homeFirstRow] dolgusunu alır.
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    super.key,
    required this.title,
    this.count,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.top = 20,
  });

  final String title;
  final int? count;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double top;

  @override
  Widget build(BuildContext context) {
    final action = actionLabel != null && onAction != null;
    var lift = 0.0;
    if (action) {
      final scaler = MediaQuery.textScalerOf(context);
      final line = scaler.scale(20) * 26 / 20;
      final sub = subtitle == null ? 0.0 : 2 + scaler.scale(14) * 20 / 14;
      lift = ((AknSpace.minTap - line - sub) / 2).clamp(0.0, 12.0);
    }
    // Büyük yazıda sayı ayrı satıra düşmesin (pano ekran 9): sayı yalnızca normal boyutta.
    final large = MediaQuery.textScalerOf(context).scale(10) >= 16;
    return SectionHeader(
      title: title,
      count: large ? null : count,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
      padding: EdgeInsets.fromLTRB(
        _gutter,
        (top - lift).clamp(0.0, top),
        12,
        0,
      ),
    );
  }
}

/// Bu ayın plakası (tasarım v2 §5.1, §7.4): yönetici destesi görünmediğinde ekranın tek plakası.
/// Bu ayın harcaması (onaylanmış teklif tutarları), son altı ayın çubukları (varsa) ve okumalar:
/// alınan yakıt, sipariş sayısı, geçen ayın toplamı. Dokununca Harcamalar açılır.
class MonthPlate extends StatelessWidget {
  const MonthPlate({
    super.key,
    required this.dashboard,
    this.months,
    this.onOpen,
  });

  /// `stats` dolu olmalı.
  final CustomerDashboard dashboard;

  /// Son aylar (eskiden yeniye; son eleman bu ay). Biri bile yoksa çubuk çizilmez.
  final List<SpendingMonth>? months;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final stats = dashboard.stats!;
    final wall = TrTime.wall(TrTime.now());
    final period = monthToDateLabel(wall);
    final amount = stats.monthAmount;
    final m = months;
    final hasBars =
        m != null &&
        m.length > 1 &&
        m.last.year == wall.year &&
        m.last.month == wall.month;
    final values = hasBars ? [for (final x in m) x.amount] : const <double>[];
    final labels = hasBars
        ? [
            for (final x in m)
              x.shortLabel ?? Fmt.monthShort[(x.month - 1).clamp(0, 11)],
          ]
        : const <String>[];
    final projection = hasBars
        ? plateMonthEndProjection(values.last, wall)
        : null;
    final (prevValue, prevUnit) = compactMoneyParts(stats.prevMonthAmount);
    final spoken = [
      '${HomeCopy.monthPlate}, $period',
      Fmt.moneyWhole(amount),
      'alınan yakıt ${Fmt.liters(stats.monthLiters)}',
      '${stats.monthOrders} sipariş',
      'geçen ay ${Fmt.moneyCompact(stats.prevMonthAmount)}',
    ].join(', ');
    // Büyük yazıda (≥ 1,6×) destedeki gibi sıkı düzen: baş, rakam ve bir cümle (§5.3).
    final compact = MediaQuery.textScalerOf(context).scale(10) >= 16;
    final plate = AknPlate(
      compact: compact,
      head: PlateHead(
        icon: Icons.payments_outlined,
        title: HomeCopy.monthPlate,
        period: period,
      ),
      figure: PlateFigure(value: Fmt.number(amount.round()), unit: '₺'),
      delta: compact
          ? PlateDelta(
              sentence:
                  '${Fmt.liters(stats.monthLiters)} yakıt, ${stats.monthOrders} sipariş',
            )
          : null,
      chart: hasBars
          ? PlateBars(
              values: values,
              labels: labels,
              projection: projection,
              valueLabels: [for (final v in values) Fmt.moneyCompact(v)],
              semanticLabels: [
                for (var i = 0; i < values.length; i++)
                  '${labels[i]}, ${Fmt.moneyWhole(values[i])}',
              ],
            )
          : null,
      below: PlateReadouts(
        items: [
          PlateReadout(
            label: 'Alınan yakıt',
            value: Fmt.number(stats.monthLiters, maxFraction: 0),
            unit: 'L',
          ),
          PlateReadout(label: 'Sipariş', value: '${stats.monthOrders}'),
          PlateReadout(label: 'Geçen ay', value: prevValue, unit: prevUnit),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 4, _gutter, 0),
      child: Semantics(
        label: spoken,
        button: onOpen != null,
        hint: onOpen == null ? null : 'Harcamaları açar',
        excludeSemantics: true,
        onTap: onOpen,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: plate,
        ),
      ),
    );
  }
}

/// Sipariş verilemiyor: neden + (finans ek bilgi istiyorsa) "Yanıtla" + bayi iletişimi.
class OrderingBanner extends StatelessWidget {
  const OrderingBanner({super.key, required this.home, this.top = 16});

  final CustomerHomeData home;
  final double top;

  @override
  Widget build(BuildContext context) {
    final o = home.ordering;
    final info = o?.infoRequested ?? false;
    final approval = o?.openApprovalRequestId;
    return Padding(
      padding: _wellMargin(top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AknBanner(
            tone: info ? AknTone.warn : AknTone.danger,
            icon: info ? Icons.mark_email_unread_outlined : Icons.block_rounded,
            title: info ? HomeCopy.financeInfo : HomeCopy.blockedTitle,
            message:
                o?.blockReason ??
                (home.hasStations
                    ? 'Bu bayide şu an sipariş veremezsiniz. Bayinizi arayıp nedenini sorabilirsiniz.'
                    : 'Bağlı bayi bulunamadı. Sipariş verebilmek için bayinizin sizi cari olarak eklemesi gerekir.'),
            actionLabel: info ? 'Yanıtla' : null,
            onAction: info
                ? () => context.push(
                    approval == null
                        ? AppRoutes.financeInfo
                        : AppRoutes.approval(approval),
                  )
                : null,
          ),
          if (home.station != null) ...[
            const SizedBox(height: 8),
            StationContactButtons(station: home.station, dense: true),
          ],
        ],
      ),
    );
  }
}

/// Dokunulabilir kuyu (Beton, r12): simge, başlık, bir cümle ve ok. Taslak ve gönderim durumu.
class HomeWell extends StatelessWidget {
  const HomeWell({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.leading,
    this.tone = AknTone.info,
    this.onTap,
    this.top = 16,
  });

  final String title;
  final double top;
  final String? message;
  final IconData? icon;

  /// [icon] yerine (ör. dönen gösterge).
  final Widget? leading;
  final AknTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final tc = c.tone(tone);
    final msg = message;
    final lead =
        leading ??
        Icon(icon ?? AknStatus.toneIcon(tone), size: 20, color: tc.fg);
    return Padding(
      padding: _wellMargin(top),
      child: Semantics(
        button: onTap != null,
        label: msg == null || msg.isEmpty ? title : '$title. $msg',
        excludeSemantics: true,
        onTap: onTap,
        child: Material(
          color: c.surfaceAlt,
          borderRadius: AknRadius.card,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            highlightColor: c.line,
            splashFactory: NoSplash.splashFactory,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AknSpace.minTap),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: lead,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: t.bodyStrong.copyWith(color: c.ink),
                          ),
                          if (msg != null && msg.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              msg,
                              style: t.bodySmall.copyWith(color: c.ink),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (onTap != null) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded, size: 22, color: c.dim),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Uygulama gönderim sırasında kapandıysa ana sayfada doğrulama durumu.
class SubmissionStatusCard extends ConsumerWidget {
  const SubmissionStatusCard({super.key, required this.state, this.top = 16});

  final SubmitState state;
  final double top;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (tone, icon, title, message) = switch (state.phase) {
      SubmitPhase.success => (
        AknTone.ok,
        Icons.check_circle_rounded,
        OrdersCopy.successTitle,
        state.result?.message ?? '',
      ),
      SubmitPhase.partial => (
        AknTone.warn,
        Icons.call_split_rounded,
        OrdersCopy.partialTitle,
        state.result?.partialError ?? '',
      ),
      SubmitPhase.failed => (
        AknTone.danger,
        Icons.error_outline_rounded,
        'Sipariş gönderilemedi',
        state.failure?.message ?? '',
      ),
      SubmitPhase.uncertain || SubmitPhase.askNewKey => (
        AknTone.warn,
        Icons.schedule_rounded,
        OrdersCopy.uncertainTitle,
        'Sonucu görmek için dokunun.',
      ),
      _ => (
        AknTone.info,
        Icons.sync_rounded,
        OrdersCopy.checking,
        'Bağlantı yavaş; aynı işlem güvenle yeniden deneniyor.',
      ),
    };
    return HomeWell(
      top: top,
      tone: tone,
      icon: icon,
      leading: state.isBusy ? const ChevronSpinner(size: 20) : null,
      title: title,
      message: message,
      onTap: () => context.push(AppRoutes.orderNew),
    );
  }
}

/// "Yarım kalan siparişinize devam edin".
class ResumeDraftCard extends StatelessWidget {
  const ResumeDraftCard({super.key, required this.summary, this.top = 16});

  final DraftSummary summary;
  final double top;

  @override
  Widget build(BuildContext context) {
    final detail = [
      if (summary.partial) 'Kalan satırlar',
      if (summary.lineCount > 0) '${summary.lineCount} satır',
      if (summary.totalLiters > 0) Fmt.liters(summary.totalLiters),
      if (summary.savedAt != null) Fmt.relative(summary.savedAt),
    ].join(', ');
    return HomeWell(
      top: top,
      tone: AknTone.brand,
      icon: summary.pendingSubmission
          ? Icons.sync_rounded
          : Icons.edit_note_rounded,
      title: summary.pendingSubmission
          ? HomeCopy.resumeChecking
          : HomeCopy.resumeTitle,
      message: detail,
      onTap: () => context.push(AppRoutes.orderNew),
    );
  }
}

/// İlk girişte bir kez: "İlk siparişinizi verin" (kapatılabilir).
class FirstOrderTip extends StatelessWidget {
  const FirstOrderTip({
    super.key,
    required this.onStart,
    required this.onDismiss,
    this.top = 16,
  });

  final VoidCallback onStart;
  final Future<void> Function() onDismiss;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: _wellMargin(top),
    child: AknBanner(
      tone: AknTone.brand,
      icon: Icons.tips_and_updates_outlined,
      title: HomeCopy.tipTitle,
      message: HomeCopy.tipMessage,
      actionLabel: HomeCopy.newOrder,
      onAction: onStart,
      onClose: () => unawaited(onDismiss()),
    ),
  );
}

/// "22 Ekim Perşembe teslim" (teklifin ya da talebin teslim günü).
String? deliveryDayPhrase(DateTime? instant) {
  if (instant == null) return null;
  final w = TrTime.wall(instant);
  return '${w.day} ${Fmt.monthNames[w.month - 1]} '
      '${Fmt.weekdayNames[w.weekday - 1]} teslim';
}

/// Karar bekleyen teklifler (tasarım v2 §7.4): yalnızca en acil satır; birden fazlaysa "Tümü".
/// Satır: "Demir Petrol teklifi" ve tutar, ürün / litre / nokta ve ₺/L, teslim günü ve geri sayım
/// (karar verebilen için Pas).
class DecisionsSection extends ConsumerWidget {
  const DecisionsSection({
    super.key,
    required this.rows,
    required this.total,
    required this.expiryEnabled,
    this.canDecide = true,
    this.headerTop = 24,
  });

  /// Başlığın üstündeki boşluk (plakadan sonraki ilk bölümde 16).
  final double headerTop;

  final List<DashboardOrderRow> rows;
  final int total;
  final bool expiryEnabled;

  /// Onaylayan / yönetici: geri sayım "sıra sizde" rengindedir.
  final bool canDecide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.akn;
    final t = context.aknText;
    final config = ref.watch(orderingConfigValueProvider);
    final expiry = config.expiryEnabled(expiryEnabled);
    final r = _mostUrgent(rows);
    final deadline = expiry && r.expiresAt != null
        ? config.deviceDeadline(r.expiresAt!)
        : null;
    final day = deliveryDayPhrase(
      r.latestDeliveryDate ?? r.requestedDeliveryDate,
    );
    final left = deadline?.difference(TrTime.now());
    final spoken = [
      HomeCopy.quoteTitle(r.stationTitle),
      r.orderNumber,
      ?r.productName,
      Fmt.liters(r.quantityLiters),
      ?r.deliveryPointName,
      if (r.latestTotalAmountTry != null) Fmt.money(r.latestTotalAmountTry),
      if (r.latestUnitPriceTry != null)
        'litresi ${Fmt.unitPrice(r.latestUnitPriceTry)}',
      ?day,
      if (left != null && left > Duration.zero)
        'teklif ${CountdownBadge.spoken(left)} içinde sona eriyor',
    ].join(', ');
    final lamp = deadline == null
        ? AknLamp.status(
            AknStatus.orderLamp(
              OrderStatus.awaitingApproval,
              StatusViewer.customer(canDecide: canDecide),
            ),
          )
        : (day == null
              ? null
              : Text(day, style: t.bodySmall.copyWith(color: c.dim)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          top: headerTop,
          title: HomeCopy.decisions,
          count: total,
          actionLabel: total > 1 ? HomeCopy.all : null,
          onAction: total > 1
              ? () => context.push('${AppRoutes.orders}?segment=decision')
              : null,
        ),
        AknListTile(
          padding: homeFirstRow(action: total > 1),
          title: HomeCopy.quoteTitle(r.stationTitle),
          subtitle: [
            r.productName,
            Fmt.liters(r.quantityLiters),
            r.deliveryPointName,
          ].whereType<String>().join(', '),
          amount: r.latestTotalAmountTry == null
              ? null
              : Fmt.money(r.latestTotalAmountTry),
          amountMeta: r.latestUnitPriceTry == null
              ? null
              : Fmt.unitPrice(r.latestUnitPriceTry),
          status: AknStatusLine(
            lamp: lamp,
            trailing: deadline == null
                ? null
                : CountdownBadge(
                    deadline: deadline,
                    yourMove: canDecide,
                    subject: 'Teklif',
                  ),
          ),
          semanticLabel: spoken,
          onTap: () => context.push(AppRoutes.order(r.orderId)),
        ),
      ],
    );
  }

  static DashboardOrderRow _mostUrgent(List<DashboardOrderRow> rows) {
    var best = rows.first;
    for (final r in rows.skip(1)) {
      final a = best.expiresAt;
      final b = r.expiresAt;
      if (b != null && (a == null || b.isBefore(a))) best = r;
    }
    return best;
  }
}

/// Yüklenmesi beklenen ödeme belgeleri (sunucu listeler; yüklenince düşer).
class PendingDocumentsSection extends StatelessWidget {
  const PendingDocumentsSection({
    super.key,
    required this.documents,
    required this.onUploaded,
    this.headerTop = 24,
  });

  /// Başlığın üstündeki boşluk (plakadan sonraki ilk bölümde 16).
  final double headerTop;

  final List<PendingPaymentDocument> documents;
  final Future<void> Function() onUploaded;

  @override
  Widget build(BuildContext context) {
    final shown = documents.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          top: headerTop,
          title: HomeCopy.documents,
          count: documents.length,
          subtitle: HomeCopy.documentsHint,
        ),
        AknLedger(
          children: [
            for (final (i, d) in shown.indexed)
              AknListTile(
                padding: i == 0 ? homeFirstRow(action: false) : null,
                title: d.label,
                subtitle: [
                  d.orderNumber,
                  if (d.stationTitle != null)
                    HomeCopy.shortCompany(d.stationTitle),
                ].join(', '),
                trailing: AknButton.secondary(
                  label: 'Yükle',
                  icon: Icons.upload_rounded,
                  size: AknButtonSize.small,
                  semanticLabel: '${d.orderNumber} ${d.label} yükle',
                  onPressed: () async {
                    final done = await showPaymentDocumentSheet(
                      context,
                      target: d.target,
                      orderNumber: d.orderNumber,
                    );
                    if (done) await onUploaded();
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Teslimat bölümü (tasarım v2 §7.4): sevkiyat yoldayken "Yolda", değilse "Teslimat". Tek satır:
/// nokta, saat (planlanan varış), litre / ürün / plaka ve yoldaysa rota çizgisi. Canlı konum
/// iddiası yok: araç işareti rotanın ortasında durur, saat bayinin planladığı saattir.
class ActiveDeliveryCard extends StatelessWidget {
  const ActiveDeliveryCard({
    super.key,
    required this.shipment,
    required this.openTotal,
    this.station,
    this.canDecide = true,
    this.headerTop = 24,
  });

  /// Başlığın üstündeki boşluk (plakadan sonraki ilk bölümde 16).
  final double headerTop;

  final DashboardShipmentRow shipment;
  final int openTotal;
  final StationContact? station;

  /// Teslimatı onaylayabilir (yönetici / onaylayan).
  final bool canDecide;

  @override
  Widget build(BuildContext context) {
    final s = shipment;
    final inTransit = s.status == ShipmentStatus.inTransit;
    void open() => context.push(AppRoutes.shipment(s.shipmentId));
    final many = openTotal > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          top: headerTop,
          title: inTransit ? HomeCopy.inTransit : HomeCopy.delivery,
          actionLabel: many ? HomeCopy.all : HomeCopy.track,
          onAction: many ? () => context.push(AppRoutes.shipments) : open,
        ),
        DeliveryRow(
          shipment: s,
          canDecide: canDecide,
          onTap: open,
          padding: homeFirstRow(action: true).copyWith(bottom: 14),
        ),
      ],
    );
  }
}

/// Teslimat satırı: başlık ve saat (sayı yazısı, sağda), ikinci satır ve "planlanan varış", durum
/// lambası (yolda değilken) ve rota çizgisi (yoldayken). Dar ekranda ve büyük yazıda saat başlığın
/// altına iner.
class DeliveryRow extends StatefulWidget {
  const DeliveryRow({
    super.key,
    required this.shipment,
    required this.onTap,
    this.canDecide = true,
    this.padding = const EdgeInsets.fromLTRB(_gutter, 12, _gutter, 14),
  });

  final DashboardShipmentRow shipment;
  final VoidCallback onTap;
  final bool canDecide;
  final EdgeInsets padding;

  @override
  State<DeliveryRow> createState() => _DeliveryRowState();
}

class _DeliveryRowState extends State<DeliveryRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final s = widget.shipment;
    final inTransit = s.status == ShipmentStatus.inTransit;
    final at = s.scheduledAt;
    final today = at != null && TrTime.dayDiff(TrTime.now(), at) == 0;
    final (String? atText, String? atMeta) = at == null
        ? (null, null)
        : today
        ? (
            Fmt.time(at),
            inTransit ? HomeCopy.plannedArrival : HomeCopy.plannedDelivery,
          )
        : (Fmt.dayMonth(at), HomeCopy.plannedDelivery);
    final title = s.deliveryPointName ?? s.orderNumber;
    final product = s.productName == null
        ? null
        : TurkishText.lower(s.productName!);
    final liters = Fmt.liters(s.deliveredLiters ?? s.plannedLiters);
    final second = [
      product == null ? liters : '$liters $product',
      if (s.vehiclePlate != null) Fmt.plate(s.vehiclePlate),
    ].join(', ');
    final lamp = inTransit
        ? null
        : AknLamp.status(
            AknStatus.shipmentLamp(
              s.status,
              StatusViewer.customer(canDecide: widget.canDecide),
            ),
          );
    final from = s.stationTitle == null
        ? null
        : HomeCopy.shortCompany(s.stationTitle);
    final spoken = [
      inTransit ? 'Yolda' : lamp?.label,
      if (from != null) '$from bayisinden',
      title,
      second,
      if (atText != null) '$atMeta $atText',
    ].whereType<String>().join(', ');
    final whenStyle = t.number.copyWith(color: c.ink, height: 1);
    final metaStyle = t.bodySmall.copyWith(color: c.dim);
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;

    Widget content(bool stack) {
      final titleText = Text(
        title,
        style: t.headline.copyWith(color: c.ink),
        maxLines: stack ? 4 : 2,
        overflow: TextOverflow.ellipsis,
      );
      final secondText = Text(
        second,
        style: metaStyle,
        maxLines: stack ? 4 : 2,
        overflow: TextOverflow.ellipsis,
      );
      final lines = <Widget>[
        if (stack) ...[
          titleText,
          if (atText != null) ...[
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                text: atText,
                style: whenStyle,
                children: [TextSpan(text: '  $atMeta', style: metaStyle)],
              ),
            ),
          ],
          const SizedBox(height: 4),
          secondText,
        ] else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: titleText),
              if (atText != null) ...[
                const SizedBox(width: 12),
                Text(atText, style: whenStyle, maxLines: 1, softWrap: false),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: secondText),
              if (atMeta != null) ...[
                const SizedBox(width: 12),
                Text(atMeta, style: metaStyle, maxLines: 1, softWrap: false),
              ],
            ],
          ),
        ],
        if (lamp != null) ...[const SizedBox(height: 8), lamp],
        if (inTransit) ...[
          const SizedBox(height: 14),
          const TruckRoute(moving: true, height: 22),
        ],
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: lines,
      );
    }

    return Semantics(
      button: true,
      label: spoken,
      hint: 'Sevkiyatı açar',
      excludeSemantics: true,
      onTap: widget.onTap,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          onHighlightChanged: (v) {
            if (v != _pressed) setState(() => _pressed = v);
          },
          child: LayoutBuilder(
            builder: (context, constraints) => AnimatedContainer(
              duration: AknMotion.of(
                context,
                _pressed ? AknMotion.press : AknMotion.pressOut,
              ),
              color: _pressed ? c.surfaceAlt : Colors.transparent,
              padding: widget.padding,
              constraints: const BoxConstraints(minHeight: 64),
              child: content(large || constraints.maxWidth < 340),
            ),
          ),
        ),
      ),
    );
  }
}

/// Şirket içi talepler: onaylayan için "Onayınızı bekleyen talepler", talep eden için "Taleplerim".
/// Satırlar `customers/me/order-requests` ucundan gelir; gelmezse (eski sunucu, hata) bekleyen
/// sayısıyla tek bir satır gösterilir.
class CompanyRequestsSection extends ConsumerWidget {
  const CompanyRequestsSection({
    super.key,
    required this.approver,
    this.waiting = 0,
    this.headerTop = 24,
  });

  /// Başlığın üstündeki boşluk (plakadan sonraki ilk bölümde 16).
  final double headerTop;

  /// true: onaylayan / yönetici (bekleyenler); false: talep eden (kendi talepleri).
  final bool approver;

  /// Ana sayfa verisindeki bekleyen sayısı (yedek satır için).
  final int waiting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(homeOrderRequestsProvider(approver)).valueOrNull;
    final items = data?.items ?? const <OrderRequest>[];
    if (!approver && items.isEmpty) return const SizedBox.shrink();
    final total = data?.total ?? waiting;
    if (approver && total <= 0) return const SizedBox.shrink();
    final allRoute = approver ? AppRoutes.approvals : AppRoutes.companyRequests;
    final action = total > items.length || !approver;
    final rows = <Widget>[
      if (items.isEmpty)
        AknListTile(
          padding: homeFirstRow(action: action),
          title: HomeCopy.approvalsWaiting(total),
          status: AknLamp.status(
            AknStatus.companyRequestLamp(
              CustomerOrderRequestStatus.pending,
              const StatusViewer.customer(),
            ),
          ),
          showChevron: true,
          semanticLabel: HomeCopy.approvalsWaiting(total),
          onTap: () => context.push(AppRoutes.approvals),
        )
      else
        for (final (i, r) in items.indexed)
          _RequestRow(
            padding: i == 0 ? homeFirstRow(action: action) : null,
            request: r,
            approver: approver,
            onTap: () => context.push(
              approver ? AppRoutes.approvals : AppRoutes.companyRequest(r.id),
            ),
          ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          top: headerTop,
          title: approver ? HomeCopy.companyApprovals : HomeCopy.myRequests,
          count: total,
          actionLabel: action ? HomeCopy.all : null,
          onAction: () => context.push(allRoute),
        ),
        AknLedger(children: rows),
      ],
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.approver,
    required this.onTap,
    this.padding,
  });

  final EdgeInsets? padding;
  final OrderRequest request;
  final bool approver;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final r = request;
    final points = <String>{
      for (final l in r.lines)
        if (l.deliveryPointName.trim().isNotEmpty) l.deliveryPointName.trim(),
    }.toList();
    final place = points.isEmpty
        ? null
        : points.length == 1
        ? points.first
        : '${points.first} ve ${points.length - 1} nokta';
    final subtitle = [
      ?place,
      if (r.createdAt != null) Fmt.relative(r.createdAt),
    ].join(', ');
    final lamp = AknStatus.companyRequestLamp(
      r.status,
      StatusViewer.customer(canDecide: approver && r.canDecide),
      serverLabel: r.statusLabel,
    );
    final who = approver && r.requestedByName.trim().isNotEmpty
        ? '${r.requestedByName.trim()} talep etti'
        : null;
    final title = '${r.productsSummary}, ${Fmt.liters(r.totalLiters)}';
    return AknListTile(
      padding: padding,
      title: title,
      subtitle: subtitle.isEmpty ? r.number : subtitle,
      amount: r.estimatedAmount == null ? null : Fmt.money(r.estimatedAmount),
      amountMeta: r.estimatedAmount == null ? null : 'tahmini',
      status: AknStatusLine(
        lamp: AknLamp.status(lamp),
        trailing: who == null
            ? null
            : Text(who, style: t.bodySmall.copyWith(color: c.dim)),
      ),
      semanticLabel: [
        r.number,
        title,
        if (subtitle.isNotEmpty) subtitle,
        if (r.estimatedAmount != null)
          'tahmini ${Fmt.money(r.estimatedAmount)}',
        lamp.label,
        ?who,
      ].join(', '),
      onTap: onTap,
    );
  }
}

/// Limitler (ilk 2; "Tümü" → Limitlerim).
class LimitsSection extends StatelessWidget {
  const LimitsSection({super.key, required this.limits, this.headerTop = 24});

  /// Başlığın üstündeki boşluk (plakadan sonraki ilk bölümde 16).
  final double headerTop;

  final List<CustomerLimit> limits;

  @override
  Widget build(BuildContext context) {
    final withLimit = limits.where((l) => l.hasLimit).toList()
      ..sort((a, b) => b.usedPct.compareTo(a.usedPct));
    final shown = (withLimit.isEmpty ? limits : withLimit).take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          top: headerTop,
          title: HomeCopy.limits,
          actionLabel: HomeCopy.all,
          onAction: () => context.push(limitsRoute),
        ),
        AknLedger(
          children: [
            for (final (i, l) in shown.indexed)
              LimitMeter(
                limit: l,
                compact: true,
                padding: i == 0 ? homeFirstRow(action: true) : null,
              ),
          ],
        ),
      ],
    );
  }
}

/// Son kullanılan 3 şablon (tek dokunuşla sihirbaz).
class TemplatesSection extends StatelessWidget {
  const TemplatesSection({
    super.key,
    required this.templates,
    this.headerTop = 24,
  });

  /// Başlığın üstündeki boşluk (plakadan sonraki ilk bölümde 16).
  final double headerTop;

  final List<TemplateListItem> templates;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HomeSectionHeader(
        top: headerTop,
        title: HomeCopy.templates,
        actionLabel: HomeCopy.all,
        onAction: () => context.push(templatesRoute),
      ),
      AknLedger(
        children: [
          for (final (i, tpl) in templates.take(3).indexed)
            AknListTile(
              padding: i == 0 ? homeFirstRow(action: true) : null,
              title: tpl.name,
              subtitle: tpl.subtitle.replaceAll(' · ', ', '),
              showChevron: true,
              semanticLabel: '${tpl.name} şablonuyla sipariş ver',
              onTap: () =>
                  context.push('${AppRoutes.orderNew}?fromTemplate=${tpl.id}'),
            ),
        ],
      ),
    ],
  );
}

/// Harcama eğrisi (yönetici destesi ve ay plakası yokken; dokununca Harcamalar).
class SpendingSection extends StatelessWidget {
  const SpendingSection({super.key, required this.months});

  final List<SpendingMonth> months;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final last = months.last;
    final values = [for (final m in months) m.amount];
    final label = [
      for (final m in months)
        '${m.shortLabel ?? Fmt.monthShort[(m.month - 1).clamp(0, 11)]}: ${Fmt.moneyWhole(m.amount)}',
    ].join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          title: HomeCopy.spending,
          actionLabel: 'Rapor',
          onAction: () => context.push(AppRoutes.spending),
        ),
        Semantics(
          label: '${HomeCopy.spending}. $label',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AmountText(Fmt.moneyCompact(last.amount), large: true),
                Text(
                  '${last.shortLabel ?? Fmt.monthNames[(last.month - 1).clamp(0, 11)]}, ${Fmt.liters(last.liters)}',
                  style: t.bodySmall.copyWith(color: c.dim),
                ),
                const SizedBox(height: 8),
                Sparkline(values: values, height: 44, semanticLabel: null),
                const SizedBox(height: 4),
                Text(
                  HomeCopy.spendingCaption,
                  style: t.caption.copyWith(color: c.dim),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "Asistana sorun" (kapatılabilir; /assistant'a gider; A8 koduna bağımlı değil): küçük logo
/// karosu, başlık ve bir cümle; sağda kapat.
class AssistantCard extends StatelessWidget {
  const AssistantCard({
    super.key,
    required this.onOpen,
    required this.onDismiss,
  });

  final VoidCallback onOpen;
  final Future<void> Function() onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: '${HomeCopy.assistantTitle}. ${HomeCopy.assistantMessage}',
              excludeSemantics: true,
              onTap: onOpen,
              child: InkWell(
                onTap: onOpen,
                splashFactory: NoSplash.splashFactory,
                highlightColor: c.surfaceAlt,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(_gutter, 12, 4, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: LogoMark(size: 24, semanticLabel: null),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              HomeCopy.assistantTitle,
                              style: t.headline.copyWith(color: c.ink),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              HomeCopy.assistantMessage,
                              style: t.bodySmall.copyWith(color: c.dim),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 8),
            child: AknIconButton(
              icon: Icons.close_rounded,
              semanticLabel: 'Asistan kartını kapat',
              color: c.dim,
              size: 20,
              onPressed: () => unawaited(onDismiss()),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Bayiniz": varsayılan bayinin adı ve iletişim düğmeleri (sayfanın sonunda).
class StationSection extends StatelessWidget {
  const StationSection({super.key, required this.station});

  final StationContact station;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HomeSectionHeader(title: HomeCopy.station),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(station.title, style: t.headline.copyWith(color: c.ink)),
              if (station.city != null)
                Text(station.city!, style: t.bodySmall.copyWith(color: c.dim)),
              const SizedBox(height: 10),
              StationContactButtons(station: station, dense: true),
            ],
          ),
        ),
      ],
    );
  }
}
