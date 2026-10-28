import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/requests_controller.dart';
import '../../copy.dart';
import '../../data/order_requests.dart';
import '../cm_widgets.dart';

/// Talepler: şirket içi sipariş talepleri (Talep eden yalnızca kendi taleplerini görür).
class RequestsPage extends ConsumerWidget {
  const RequestsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(requestsControllerProvider);
    final ctrl = ref.read(requestsControllerProvider.notifier);
    final p = s.page;
    Widget body;
    if (p.showSkeleton) {
      body = const SkeletonList(itemCount: 4, lines: 3);
    } else if (p.isEmpty) {
      body = PullToRefresh(
        onRefresh: () => ctrl.load(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (p.error != null)
              CmFailureView(failure: p.error!, onRetry: ctrl.load)
            else
              FadeUp(
                offset: 16,
                scale: 0.97,
                child: EmptyState(
                  title: s.segment == RequestSegment.pending
                      ? 'Bekleyen talep yok'
                      : CmCopy.requestsEmpty,
                  message: CmCopy.requestsEmptyMessage,
                  illustration: AknIllustration.approvals,
                ),
              ),
          ],
        ),
      );
    } else {
      // Kartlar sırayla yükselerek gelir; bölüm değişince akış yeniden başlar.
      body = StaggerScope(
        key: ValueKey(s.segment),
        child: PullToRefresh(
          onRefresh: () => ctrl.load(refresh: true),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 400) ctrl.loadMore();
              return false;
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                top: 4,
                bottom: 16 + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: p.items.length + 1,
              itemBuilder: (context, i) {
                if (i == p.items.length) {
                  return LoadMoreFooter(
                    loading: p.loadingMore,
                    error: p.loadMoreError,
                    onRetry: ctrl.loadMore,
                  );
                }
                final r = p.items[i];
                return StaggerItem(
                  key: ValueKey(r.id),
                  index: i,
                  child: Padding(
                    padding: CmCard.listMargin,
                    child: RequestCard(
                      request: r,
                      onTap: () => context.push(AppRoutes.companyRequest(r.id)),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }
    return AppScaffold(
      title: CmCopy.requestsTitle,
      bandIcon: PhosphorIconsRegular.listChecks,
      eyebrow: 'Müşteri',
      description: 'Şirket içi sipariş talepleri',
      refreshing: p.refreshing,
      body: Column(
        children: [
          const SizedBox(height: 4),
          CmSegmented<RequestSegment>(
            segments: [
              for (final seg in RequestSegment.values)
                FilterOption(value: seg, label: seg.label),
            ],
            value: s.segment,
            onChanged: ctrl.setSegment,
          ),
          const SizedBox(height: 8),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Talep kartı (tasarım v3 §4): beyaz r20 kart; başta durumun simge karosu, ürün ve litre, talep
/// no / kişi / zaman, sağda tahmini tutar; ince çizginin altında durum lambası ("Onayınızı
/// bekliyor" sıra sizde) ve sonuç ("1 sipariş oluştu", gerekçe). Basınca 0,97'ye iner.
class RequestCard extends StatelessWidget {
  const RequestCard({super.key, required this.request, this.onTap});

  final OrderRequest request;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final t = context.aknText;
    final c = context.akn;
    final lamp = AknStatus.companyRequestLamp(
      r.status,
      StatusViewer.customer(canDecide: r.canDecide),
      serverLabel: r.statusLabel,
    );
    final lines = r.lines.length;
    final created = r.createdOrderIds.length;
    final failed = r.failedLineCount;
    final title = '${r.productsSummary}, ${Fmt.liters(r.totalLiters)}';
    final subtitle = [
      r.number,
      r.requestedByName,
      if (lines > 1) '$lines satır',
      if (r.createdAt != null) Fmt.relative(r.createdAt),
    ].where((x) => x.trim().isNotEmpty).join(', ');
    final outcome = switch (r.status) {
      CustomerOrderRequestStatus.approved =>
        '$created sipariş oluştu${failed > 0 ? ', $failed satır oluşturulamadı' : ''}',
      CustomerOrderRequestStatus.rejected =>
        r.decisionNote == null ? null : 'Gerekçe: ${r.decisionNote}',
      CustomerOrderRequestStatus.pending =>
        r.canDecide ? null : 'Onaylayanın kararı bekleniyor',
      _ => null,
    };
    final tap = onTap;
    return CmCard(
      pressable: tap != null,
      child: AknListTile(
        leading: CmIconTile(
          icon: switch (r.status) {
            CustomerOrderRequestStatus.approved =>
              PhosphorIconsRegular.sealCheck,
            CustomerOrderRequestStatus.rejected => PhosphorIconsRegular.xCircle,
            CustomerOrderRequestStatus.cancelled =>
              PhosphorIconsRegular.arrowUUpLeft,
            _ => PhosphorIconsRegular.clipboardText,
          },
          tone: lamp.tone,
        ),
        padding: CmCard.rowPadding,
        titleStyle: cmRowTitle(context),
        title: cmKeepUnits(title),
        subtitle: subtitle,
        amount: r.estimatedAmount == null ? null : Fmt.money(r.estimatedAmount),
        amountMeta: r.estimatedAmount == null ? null : 'tahmini',
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Divider(height: 1, thickness: 1, color: c.lineSoft),
            const SizedBox(height: 10),
            AknStatusLine(
              lamp: AknLamp.status(lamp),
              trailing: outcome == null
                  ? null
                  : Text(
                      outcome,
                      style: t.bodySmall.copyWith(
                        color: failed > 0 ? c.danger.fg : c.dim,
                        fontWeight: failed > 0 ? FontWeight.w600 : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ],
        ),
        onTap: tap == null
            ? null
            : () {
                AknHaptics.selection();
                tap();
              },
        semanticLabel: [
          r.number,
          lamp.label,
          title,
          r.requestedByName,
          if (r.estimatedAmount != null)
            'tahmini ${Fmt.money(r.estimatedAmount)}',
          ?outcome,
        ].join(', '),
      ),
    );
  }
}
