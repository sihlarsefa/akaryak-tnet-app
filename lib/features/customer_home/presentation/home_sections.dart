import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
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

/// Lacivert karşılama: selam, firma, KPI'lar ve "Sipariş ver".
class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.greeting,
    required this.title,
    required this.dashboard,
    required this.canCreate,
    required this.canOrder,
    required this.onNewOrder,
    this.onDecisions,
    this.onShipments,
  });

  final String greeting;
  final String title;
  final CustomerDashboard dashboard;
  final bool canCreate;
  final bool canOrder;
  final VoidCallback onNewOrder;
  final VoidCallback? onDecisions;
  final VoidCallback? onShipments;

  @override
  Widget build(BuildContext context) {
    final stats = dashboard.stats;
    return AknHeroPanel(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Builder(
        builder: (context) {
          final t = context.aknText;
          final c = context.akn;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: Text(greeting, style: t.title)),
              const SizedBox(height: 4),
              Text(title, style: t.body.copyWith(color: c.dim)),
              const SizedBox(height: 16),
              KpiRow(
                children: [
                  KpiTile(
                    label: 'Karar bekleyen',
                    value: dashboard.pendingDecisionTotal,
                    icon: Icons.request_quote_rounded,
                    tone: dashboard.pendingDecisionTotal > 0
                        ? AknTone.warn
                        : AknTone.neutral,
                    onTap: onDecisions,
                    semanticLabel:
                        '${dashboard.pendingDecisionTotal} teklif kararınızı bekliyor',
                  ),
                  KpiTile(
                    label: stats == null ? 'Açık teslimat' : 'Bu ay',
                    value: stats == null
                        ? dashboard.openShipmentTotal
                        : stats.monthLiters,
                    format: stats == null ? null : Fmt.liters,
                    icon: stats == null
                        ? Icons.local_shipping_rounded
                        : Icons.local_gas_station_rounded,
                    tone: AknTone.info,
                    onTap: stats == null ? onShipments : null,
                    caption: stats == null
                        ? null
                        : '${stats.monthOrders} sipariş',
                  ),
                ],
              ),
              if (canCreate) ...[
                const SizedBox(height: 16),
                AknButton(
                  label: HomeCopy.newOrder,
                  icon: Icons.add_shopping_cart_rounded,
                  size: AknButtonSize.large,
                  expand: true,
                  onPressed: canOrder ? onNewOrder : null,
                ),
                const SizedBox(height: 6),
                Text(
                  canOrder ? HomeCopy.newOrderHint : HomeCopy.blockedTitle,
                  style: t.caption.copyWith(color: c.dim),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Sipariş verilemiyor: neden + (finans ek bilgi istiyorsa) "Yanıtla" + bayi iletişimi.
class OrderingBanner extends StatelessWidget {
  const OrderingBanner({super.key, required this.home});

  final CustomerHomeData home;

  @override
  Widget build(BuildContext context) {
    final o = home.ordering;
    final info = o?.infoRequested ?? false;
    final approval = o?.openApprovalRequestId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AknBanner(
            tone: info ? AknTone.warn : AknTone.danger,
            icon: info ? Icons.mark_email_unread_rounded : Icons.block_rounded,
            title: info ? HomeCopy.financeInfo : HomeCopy.blockedTitle,
            message:
                o?.blockReason ??
                (home.hasStations
                    ? 'Bu bayide şu an sipariş veremezsiniz.'
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

/// Uygulama gönderim sırasında kapandıysa ana sayfada doğrulama durumu.
class SubmissionStatusCard extends ConsumerWidget {
  const SubmissionStatusCard({super.key, required this.state});

  final SubmitState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final c = context.akn;
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: AknCard(
        accent: tone,
        semanticLabel: '$title. $message',
        onTap: () => context.push(AppRoutes.orderNew),
        child: Row(
          children: [
            if (state.isBusy)
              const ChevronSpinner(size: 28)
            else
              AknIconBox(icon: icon, tone: tone),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.bodyStrong),
                  if (message.isNotEmpty)
                    Text(
                      message,
                      style: t.bodySmall.copyWith(color: c.dim),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.dim),
          ],
        ),
      ),
    );
  }
}

/// "Yarım kalan siparişinize devam edin".
class ResumeDraftCard extends StatelessWidget {
  const ResumeDraftCard({super.key, required this.summary});

  final DraftSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final detail = [
      if (summary.partial) 'Kalan satırlar',
      if (summary.lineCount > 0) '${summary.lineCount} satır',
      if (summary.totalLiters > 0) Fmt.liters(summary.totalLiters),
      if (summary.savedAt != null) Fmt.relative(summary.savedAt),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: AknCard(
        accent: AknTone.brand,
        semanticLabel:
            '${summary.pendingSubmission ? HomeCopy.resumeChecking : HomeCopy.resumeTitle}. $detail',
        onTap: () => context.push(AppRoutes.orderNew),
        child: Row(
          children: [
            AknIconBox(
              icon: summary.pendingSubmission
                  ? Icons.sync_rounded
                  : Icons.edit_note_rounded,
              tone: AknTone.brand,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary.pendingSubmission
                        ? HomeCopy.resumeChecking
                        : HomeCopy.resumeTitle,
                    style: t.bodyStrong,
                  ),
                  if (detail.isNotEmpty)
                    Text(detail, style: t.bodySmall.copyWith(color: c.dim)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.dim),
          ],
        ),
      ),
    );
  }
}

/// İlk girişte bir kez: "İlk siparişinizi verin" (kapatılabilir).
class FirstOrderTip extends StatelessWidget {
  const FirstOrderTip({
    super.key,
    required this.onStart,
    required this.onDismiss,
  });

  final VoidCallback onStart;
  final Future<void> Function() onDismiss;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: AknBanner(
      tone: AknTone.brand,
      icon: Icons.tips_and_updates_rounded,
      title: HomeCopy.tipTitle,
      message: HomeCopy.tipMessage,
      actionLabel: HomeCopy.newOrder,
      onAction: onStart,
      onClose: () => unawaited(onDismiss()),
    ),
  );
}

/// Karar bekleyen teklifler (geri sayım sunucu saatine göre).
class DecisionsSection extends ConsumerWidget {
  const DecisionsSection({
    super.key,
    required this.rows,
    required this.total,
    required this.expiryEnabled,
  });

  final List<DashboardOrderRow> rows;
  final int total;
  final bool expiryEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final c = context.akn;
    final config = ref.watch(orderingConfigValueProvider);
    final expiry = config.expiryEnabled(expiryEnabled);
    return SectionCard(
      title: HomeCopy.decisions,
      icon: Icons.request_quote_rounded,
      accent: AknTone.warn,
      trailing: total > rows.take(3).length
          ? AknButton.ghost(
              label: '${HomeCopy.all} ($total)',
              size: AknButtonSize.small,
              onPressed: () =>
                  context.push('${AppRoutes.orders}?segment=decision'),
            )
          : null,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in rows.take(3))
            Semantics(
              button: true,
              label: [
                'Teklif ${r.orderNumber}',
                if (r.productName != null) r.productName!,
                Fmt.liters(r.quantityLiters),
                if (r.latestTotalAmountTry != null)
                  Fmt.money(r.latestTotalAmountTry),
              ].join(', '),
              excludeSemantics: true,
              onTap: () => context.push(AppRoutes.order(r.orderId)),
              child: InkWell(
                borderRadius: AknRadius.card,
                onTap: () => context.push(AppRoutes.order(r.orderId)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                  child: _DecisionRowLayout(
                    info: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.orderNumber, style: t.bodyStrong),
                        Text(
                          [
                            r.productName,
                            Fmt.liters(r.quantityLiters),
                          ].whereType<String>().join(' · '),
                          style: t.bodySmall.copyWith(color: c.dim),
                        ),
                        if (r.latestUnitPriceTry != null)
                          AmountText(
                            '${Fmt.unitPrice(r.latestUnitPriceTry)} · ${Fmt.money(r.latestTotalAmountTry)}',
                            style: t.bodySmall.copyWith(color: c.ink),
                          ),
                      ],
                    ),
                    badge: expiry && r.expiresAt != null
                        ? CountdownBadge(
                            deadline: config.deviceDeadline(r.expiresAt!),
                          )
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Karar satırı: bilgiler + geri sayım (yoksa ok). Büyük yazıda rozet alta iner ve sığmazsa küçülür.
class _DecisionRowLayout extends StatelessWidget {
  const _DecisionRowLayout({required this.info, this.badge});

  final Widget info;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final b = badge;
    if (b != null && isLargeText(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          info,
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FitBadge(child: b),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: info),
        const SizedBox(width: 8),
        b ?? Icon(Icons.chevron_right_rounded, color: context.akn.dim),
      ],
    );
  }
}

/// Yüklenmesi beklenen ödeme belgeleri (sunucu listeler; yüklenince düşer).
class PendingDocumentsSection extends StatelessWidget {
  const PendingDocumentsSection({
    super.key,
    required this.documents,
    required this.onUploaded,
  });

  final List<PendingPaymentDocument> documents;
  final Future<void> Function() onUploaded;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return SectionCard(
      title: HomeCopy.documents,
      icon: Icons.photo_camera_outlined,
      accent: AknTone.warn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Belge yüklenene kadar teklif onaylanamaz.',
            style: t.bodySmall.copyWith(color: c.dim),
          ),
          const SizedBox(height: 8),
          for (final d in documents.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.label, style: t.bodyStrong),
                        Text(
                          [
                            d.orderNumber,
                            d.stationTitle,
                          ].whereType<String>().join(' · '),
                          style: t.bodySmall.copyWith(color: c.dim),
                        ),
                      ],
                    ),
                  ),
                  AknButton.secondary(
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
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Yoldaki / kabul bekleyen teslimat (canlı konum iddiası yok).
class ActiveDeliveryCard extends StatelessWidget {
  const ActiveDeliveryCard({
    super.key,
    required this.shipment,
    required this.openTotal,
    this.station,
  });

  final DashboardShipmentRow shipment;
  final int openTotal;
  final StationContact? station;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final s = shipment;
    final reduce =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final inTransit = s.status == ShipmentStatus.inTransit;
    final reported = s.status == ShipmentStatus.reported;
    return SectionCard(
      title: HomeCopy.delivery,
      icon: Icons.local_shipping_rounded,
      accent: reported ? AknTone.warn : null,
      trailing: openTotal > 1
          ? AknButton.ghost(
              label: '${HomeCopy.all} ($openTotal)',
              size: AknButtonSize.small,
              onPressed: () => context.push(AppRoutes.shipments),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusChip.style(
                s.status.statusStyle,
                size: StatusChipSize.small,
              ),
              if (s.vehiclePlate != null)
                Semantics(
                  label: 'Plaka ${Fmt.plate(s.vehiclePlate)}',
                  excludeSemantics: true,
                  child: PlateBadge(plate: s.vehiclePlate!, fontSize: 13),
                ),
              Text(s.orderNumber, style: t.bodySmall.copyWith(color: c.dim)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            [
              s.productName,
              Fmt.liters(s.deliveredLiters ?? s.plannedLiters),
              s.deliveryPointName,
            ].whereType<String>().join(' · '),
            style: t.body,
          ),
          if (inTransit) ...[
            const SizedBox(height: 8),
            TruckRoute(
              moving: !reduce,
              height: 40,
              semanticLabel: 'Araç yolda. ${OrdersCopy.inTransitCaption}.',
            ),
            Text(
              OrdersCopy.inTransitCaption,
              style: t.caption.copyWith(color: c.dim),
            ),
          ] else if (s.status == ShipmentStatus.planned &&
              s.scheduledAt != null)
            Text(
              '${OrdersCopy.estimatedDelivery}: ${Fmt.dayLabel(s.scheduledAt)} ${Fmt.date(s.scheduledAt)}',
              style: t.bodySmall.copyWith(color: c.text),
            ),
          const SizedBox(height: 10),
          if (reported)
            AknButton(
              label: OrdersCopy.confirmDelivery,
              icon: Icons.fact_check_rounded,
              expand: true,
              onPressed: () => context.push(AppRoutes.shipment(s.shipmentId)),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: AknButton.secondary(
                label: 'Siparişi aç',
                size: AknButtonSize.small,
                onPressed: () => context.push(AppRoutes.order(s.orderId)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Limitler (ilk 2; "Tümü" → Limitlerim).
class LimitsSection extends StatelessWidget {
  const LimitsSection({super.key, required this.limits});

  final List<CustomerLimit> limits;

  @override
  Widget build(BuildContext context) {
    final withLimit = limits.where((l) => l.hasLimit).toList();
    final shown = (withLimit.isEmpty ? limits : withLimit).take(2).toList();
    return SectionCard(
      title: HomeCopy.limits,
      icon: Icons.speed_rounded,
      trailing: AknButton.ghost(
        label: HomeCopy.all,
        size: AknButtonSize.small,
        onPressed: () => context.push(limitsRoute),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final l in shown)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 8),
              child: LimitMeter(limit: l, compact: true),
            ),
        ],
      ),
    );
  }
}

/// Son kullanılan 3 şablon (tek dokunuşla sihirbaz).
class TemplatesSection extends StatelessWidget {
  const TemplatesSection({super.key, required this.templates});

  final List<TemplateListItem> templates;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: HomeCopy.templates,
    icon: Icons.bookmarks_rounded,
    trailing: AknButton.ghost(
      label: HomeCopy.all,
      size: AknButtonSize.small,
      onPressed: () => context.push(templatesRoute),
    ),
    padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final tpl in templates.take(3))
          AknListTile(
            dense: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            leadingIcon: Icons.bookmark_rounded,
            leadingTone: AknTone.brand,
            title: tpl.name,
            subtitle: tpl.subtitle,
            semanticLabel: '${tpl.name} şablonuyla sipariş ver',
            onTap: () =>
                context.push('${AppRoutes.orderNew}?fromTemplate=${tpl.id}'),
          ),
      ],
    ),
  );
}

/// Harcama eğrisi (sunucu toplamları; dokununca Harcamalar).
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: AknCard(
        onTap: () => context.push(AppRoutes.spending),
        semanticLabel: '${HomeCopy.spending}. $label',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.insights_rounded, size: 20, color: c.dim),
                const SizedBox(width: 8),
                Expanded(child: Text(HomeCopy.spending, style: t.headline)),
                Icon(Icons.chevron_right_rounded, color: c.dim),
              ],
            ),
            const SizedBox(height: 8),
            AmountText(Fmt.moneyCompact(last.amount), large: true),
            Text(
              '${last.shortLabel ?? Fmt.monthNames[(last.month - 1).clamp(0, 11)]} · ${Fmt.liters(last.liters)}',
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
    );
  }
}

/// "Asistana sorun" (kapatılabilir; /assistant'a gider; A8 koduna bağımlı değil).
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: AknCard(
        onTap: onOpen,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LogoMark(size: 40, semanticLabel: null),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(HomeCopy.assistantTitle, style: t.bodyStrong),
                  const SizedBox(height: 2),
                  Text(
                    HomeCopy.assistantMessage,
                    style: t.bodySmall.copyWith(color: c.dim),
                  ),
                ],
              ),
            ),
            AknIconButton(
              icon: Icons.close_rounded,
              semanticLabel: 'Asistan kartını kapat',
              color: c.dim,
              onPressed: () => unawaited(onDismiss()),
            ),
          ],
        ),
      ),
    );
  }
}
