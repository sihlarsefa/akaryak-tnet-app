import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/company_controller.dart';
import '../../copy.dart';
import '../../data/finance_info.dart';
import '../cm_widgets.dart';

/// Yanıt sayfası: onay ayrıntısı, istenen belge türü önceden seçili (`?reply=1&kind=<AttachmentKind>`).
String financeReplyRoute(int requestId, AttachmentKind? kind) {
  final q = <String>[
    'reply=1',
    if (kind != null && !kind.isUnknown) 'kind=${kind.code}',
  ];
  return '${AppRoutes.approval(requestId)}?${q.join('&')}';
}

/// Finans bilgisi: bağlı bayilerdeki finans durumu (`links`) ve finansın ek bilgi istediği siparişler
/// (`orders`). "Yanıtla" onay ayrıntısını istenen belge türüyle açar.
class FinanceInfoPage extends ConsumerWidget {
  const FinanceInfoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(financeInfoProvider);
    Future<void> refresh() async {
      ref.invalidate(financeInfoProvider);
      try {
        await ref.read(financeInfoProvider.future);
      } catch (_) {}
    }

    return AppScaffold(
      title: CmCopy.financeTitle,
      refreshing: async.isLoading && async.hasValue,
      body: async.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const SkeletonList(itemCount: 3, lines: 3),
        error: (e, _) =>
            CmFailureView(failure: AppFailure.from(e), onRetry: refresh),
        data: (info) => PullToRefresh(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  CmCopy.financeIntro,
                  style: context.aknText.bodySmall,
                ),
              ),
              if (info.links.isEmpty)
                const EmptyState(
                  title: CmCopy.financeNoLinks,
                  message: CmCopy.financeNoLinksMessage,
                  illustration: AknIllustration.payments,
                )
              else ...[
                if (info.pendingReplies == 0)
                  const AknBanner(
                    margin: EdgeInsets.fromLTRB(16, 0, 16, 12),
                    tone: AknTone.ok,
                    message: CmCopy.financeAllClear,
                  ),
                const SectionHeader(
                  title: 'Bayiler',
                  padding: EdgeInsets.fromLTRB(16, 4, 8, 8),
                ),
                for (final l in info.links) _LinkCard(link: l),
              ],
              if (info.orders.isNotEmpty) ...[
                SectionHeader(
                  title: 'Siparişler için istenen bilgiler',
                  count: info.orders.length,
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                ),
                for (final o in info.orders) _OrderCard(order: o),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.link});

  final FinanceInfoLink link;

  @override
  Widget build(BuildContext context) {
    final l = link;
    final t = context.aknText;
    final c = context.akn;
    final (label, tone, icon) = l.needsReply
        ? ('Ek bilgi istendi', AknTone.info, Icons.contact_support_rounded)
        : (l.status.canOrder
              ? (
                  'Sipariş verebilirsiniz',
                  AknTone.ok,
                  Icons.check_circle_rounded,
                )
              : (l.inReview
                    ? (
                        'Finans incelemesinde',
                        AknTone.warn,
                        Icons.hourglass_top_rounded,
                      )
                    : (
                        'Sipariş verilemiyor',
                        AknTone.danger,
                        Icons.block_rounded,
                      )));
    final requestId = l.requestId ?? l.status.openApprovalRequestId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: AknCard(
        accent: l.needsReply ? AknTone.info : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CmHeadRow(
              title: Text(l.stationTitle, style: t.bodyStrong),
              trailing: StatusChip(
                label: label,
                tone: tone,
                icon: icon,
                size: StatusChipSize.small,
              ),
            ),
            if (l.status.profileStatus != null) ...[
              const SizedBox(height: 4),
              Text(
                'Finans kartı: ${l.status.profileStatus!.label}',
                style: t.caption,
              ),
            ],
            if (!l.status.canOrder && l.status.blockReason != null) ...[
              const SizedBox(height: 8),
              Text(
                l.status.blockReason!,
                style: t.bodySmall.copyWith(color: c.text),
              ),
            ],
            if (l.needsReply &&
                (l.infoNote != null || l.kindLabel != null)) ...[
              const SizedBox(height: 10),
              _InfoRequestBox(
                note: l.infoNote,
                kindLabel: l.kindLabel,
                requestedAt: l.requestedAt,
              ),
            ],
            if (l.inReview && !l.needsReply) ...[
              const SizedBox(height: 8),
              Text(
                'Finans ekibi cari hesabınızı inceliyor. Sonuç e-posta ile bildirilir.',
                style: t.caption,
              ),
            ],
            if (l.needsReply && requestId != null) ...[
              const SizedBox(height: 12),
              AknButton(
                label: 'Yanıtla',
                icon: Icons.reply_rounded,
                expand: true,
                semanticLabel: '${l.stationTitle} finans ekibine yanıt ver',
                onPressed: () =>
                    context.push(financeReplyRoute(requestId, l.requiredKind)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final FinanceInfoOrder order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: AknCard(
        accent: AknTone.info,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CmHeadRow(
              title: Text(o.orderNumber, style: t.bodyStrong),
              trailing: const StatusChip(
                label: 'Ek bilgi istendi',
                tone: AknTone.info,
                icon: Icons.contact_support_rounded,
                size: StatusChipSize.small,
              ),
            ),
            if (o.stationTitle.isNotEmpty)
              Text(o.stationTitle, style: t.caption),
            const SizedBox(height: 10),
            _InfoRequestBox(
              note: o.infoNote,
              kindLabel: o.kindLabel,
              requestedAt: o.createdAt,
              timeLabel: 'Sipariş',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AknButton.secondary(
                    label: 'Siparişi aç',
                    expand: true,
                    onPressed: () => context.push(AppRoutes.order(o.orderId)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AknButton(
                    label: 'Yanıtla',
                    icon: Icons.reply_rounded,
                    expand: true,
                    semanticLabel: '${o.orderNumber} için finansa yanıt ver',
                    onPressed: o.requestId <= 0
                        ? null
                        : () => context.push(
                            financeReplyRoute(o.requestId, o.requiredKind),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRequestBox extends StatelessWidget {
  const _InfoRequestBox({
    this.note,
    this.kindLabel,
    this.requestedAt,
    this.timeLabel = 'İstendi',
  });

  final String? note;
  final String? kindLabel;
  final DateTime? requestedAt;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.info.bg,
        borderRadius: AknRadius.card,
        border: Border.all(color: c.info.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Finans ekibinin isteği',
            style: t.label.copyWith(color: c.info.fg),
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note!, style: t.body.copyWith(color: c.text)),
          ],
          if (kindLabel != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.attach_file_rounded, size: 16, color: c.info.fg),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'İstenen belge: $kindLabel',
                    style: t.label.copyWith(color: c.text),
                  ),
                ),
              ],
            ),
          ],
          if (requestedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              '$timeLabel: ${Fmt.relative(requestedAt)}',
              style: t.caption.copyWith(color: c.text),
            ),
          ],
        ],
      ),
    );
  }
}
