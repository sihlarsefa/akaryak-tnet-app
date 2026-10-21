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
              EmptyState(
                title: s.segment == RequestSegment.pending
                    ? 'Bekleyen talep yok'
                    : CmCopy.requestsEmpty,
                message: CmCopy.requestsEmptyMessage,
                illustration: AknIllustration.approvals,
              ),
          ],
        ),
      );
    } else {
      body = PullToRefresh(
        onRefresh: () => ctrl.load(refresh: true),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 400) ctrl.loadMore();
            return false;
          },
          child: StaggerScope(
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 8, bottom: 16),
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
                  index: i,
                  child: RequestCard(
                    request: r,
                    onTap: () => context.push(AppRoutes.companyRequest(r.id)),
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
      subtitle: 'Şirket içi sipariş talepleri',
      refreshing: p.refreshing,
      body: Column(
        children: [
          const SizedBox(height: 8),
          CmSegmented<RequestSegment>(
            segments: [
              for (final seg in RequestSegment.values)
                FilterOption(value: seg, label: seg.label),
            ],
            value: s.segment,
            onChanged: ctrl.setSegment,
          ),
          const SizedBox(height: 4),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Talep satırı.
class RequestCard extends StatelessWidget {
  const RequestCard({super.key, required this.request, this.onTap});

  final OrderRequest request;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final t = context.aknText;
    final c = context.akn;
    final style = r.status.statusStyle.withLabel(r.statusLabel);
    final lines = r.lines.length;
    final created = r.createdOrderIds.length;
    final failed = r.failedLineCount;
    final summary =
        '${Fmt.liters(r.totalLiters)} · ${r.productsSummary} · $lines satır';
    final outcome = switch (r.status) {
      CustomerOrderRequestStatus.approved =>
        '$created sipariş oluştu${failed > 0 ? ' · $failed satır oluşturulamadı' : ''}',
      CustomerOrderRequestStatus.rejected =>
        r.decisionNote == null ? 'Reddedildi' : 'Gerekçe: ${r.decisionNote}',
      CustomerOrderRequestStatus.pending =>
        r.canDecide ? 'Kararınızı bekliyor' : 'Onaylayanın kararı bekleniyor',
      _ => null,
    };
    return AknCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      onTap: onTap,
      accent: r.status == CustomerOrderRequestStatus.pending && r.canDecide
          ? AknTone.warn
          : (failed > 0 ? AknTone.danger : null),
      semanticLabel: [
        r.number,
        style.label,
        summary,
        r.requestedByName,
        if (r.estimatedAmount != null)
          'tahmini ${Fmt.money(r.estimatedAmount)}',
        ?outcome,
      ].join(', '),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CmHeadRow(
              title: Text(r.number, style: t.bodyStrong),
              trailing: StatusChip.style(style, size: StatusChipSize.small),
            ),
            const SizedBox(height: 4),
            Text(summary, style: t.body),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  '${r.requestedByName} · ${Fmt.relative(r.createdAt)}',
                  style: t.caption,
                ),
                if (r.estimatedAmount != null)
                  Text(
                    'Tahmini ${Fmt.money(r.estimatedAmount)}',
                    style: t.caption.copyWith(color: c.text),
                  ),
              ],
            ),
            if (outcome != null) ...[
              const SizedBox(height: 6),
              Text(
                outcome,
                style: t.label.copyWith(
                  color: failed > 0
                      ? c.danger.fg
                      : (r.status == CustomerOrderRequestStatus.approved
                            ? c.ok.fg
                            : c.text),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
