import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
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
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  CmCopy.financeIntro,
                  style: context.aknText.bodySmall.copyWith(
                    color: context.akn.dim,
                  ),
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
                    margin: EdgeInsets.fromLTRB(20, 12, 20, 0),
                    tone: AknTone.ok,
                    message: CmCopy.financeAllClear,
                  ),
                SectionHeader(title: 'Bayiler', count: info.links.length),
                AknLedger(
                  children: [for (final l in info.links) _LinkCard(link: l)],
                ),
              ],
              if (info.orders.isNotEmpty) ...[
                SectionHeader(
                  title: 'Siparişler için istenen bilgiler',
                  count: info.orders.length,
                ),
                AknLedger(
                  children: [for (final o in info.orders) _OrderCard(order: o)],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bayi satırı: bayi adı, finans durumu lambası (ek bilgi istendiyse "sıra sizde"), finans kartı,
/// engel nedeni, finansın isteği ve "Yanıtla".
class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.link});

  final FinanceInfoLink link;

  @override
  Widget build(BuildContext context) {
    final l = link;
    final t = context.aknText;
    final c = context.akn;
    final (label, tone) = l.needsReply
        ? ('Ek bilgi istendi', AknTone.brand)
        : (l.status.canOrder
              ? ('Sipariş verebilirsiniz', AknTone.ok)
              : (l.inReview
                    ? ('Finans incelemesinde', AknTone.info)
                    : ('Sipariş verilemiyor', AknTone.danger)));
    final requestId = l.requestId ?? l.status.openApprovalRequestId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.stationTitle, style: t.headline.copyWith(color: c.ink)),
          if (l.status.profileStatus != null)
            Text(
              'Finans kartı: ${TurkishText.lower(l.status.profileStatus!.label)}',
              style: t.bodySmall.copyWith(color: c.dim),
            ),
          const SizedBox(height: 8),
          AknLamp(label: label, tone: tone),
          if (!l.status.canOrder && l.status.blockReason != null) ...[
            const SizedBox(height: 6),
            Text(
              l.status.blockReason!,
              style: t.bodySmall.copyWith(color: c.text),
            ),
          ],
          if (l.needsReply && (l.infoNote != null || l.kindLabel != null)) ...[
            const SizedBox(height: 10),
            _InfoRequestBox(
              note: l.infoNote,
              kindLabel: l.kindLabel,
              requestedAt: l.requestedAt,
            ),
          ],
          if (l.inReview && !l.needsReply) ...[
            const SizedBox(height: 6),
            Text(
              'Finans ekibi cari hesabınızı inceliyor. Sonuç e-posta ile bildirilir.',
              style: t.bodySmall.copyWith(color: c.dim),
            ),
          ],
          if (l.needsReply && requestId != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AknButton(
                label: 'Yanıtla',
                size: AknButtonSize.medium,
                semanticLabel: '${l.stationTitle} finans ekibine yanıt ver',
                onPressed: () =>
                    context.push(financeReplyRoute(requestId, l.requiredKind)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Sipariş satırı: sipariş no ve bayi, "Ek bilgi istendi" (sıra sizde), finansın isteği, "Siparişi
/// aç" ve "Yanıtla".
class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final FinanceInfoOrder order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final t = context.aknText;
    final c = context.akn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(o.orderNumber, style: t.headline.copyWith(color: c.ink)),
          if (o.stationTitle.isNotEmpty)
            Text(o.stationTitle, style: t.bodySmall.copyWith(color: c.dim)),
          const SizedBox(height: 8),
          const AknLamp(label: 'Ek bilgi istendi', tone: AknTone.brand),
          const SizedBox(height: 10),
          _InfoRequestBox(
            note: o.infoNote,
            kindLabel: o.kindLabel,
            requestedAt: o.createdAt,
            timeLabel: 'Sipariş',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AknButton(
                label: 'Yanıtla',
                size: AknButtonSize.medium,
                semanticLabel: '${o.orderNumber} için finansa yanıt ver',
                onPressed: o.requestId <= 0
                    ? null
                    : () => context.push(
                        financeReplyRoute(o.requestId, o.requiredKind),
                      ),
              ),
              AknButton.secondary(
                label: 'Siparişi aç',
                size: AknButtonSize.medium,
                onPressed: () => context.push(AppRoutes.order(o.orderId)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Finansın isteği: Beton kuyu (r12), mürekkep metin, istenen belge ve zaman.
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: AknRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Finans ekibinin isteği',
            style: t.label.copyWith(color: c.ink, fontWeight: FontWeight.w600),
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note!, style: t.body.copyWith(color: c.text)),
          ],
          if (kindLabel != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.attach_file_rounded, size: 16, color: c.dim),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'İstenen belge: $kindLabel',
                    style: t.label.copyWith(color: c.ink),
                  ),
                ),
              ],
            ),
          ],
          if (requestedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              '$timeLabel: ${Fmt.relative(requestedAt)}',
              style: t.bodySmall.copyWith(color: c.dim),
            ),
          ],
        ],
      ),
    );
  }
}
