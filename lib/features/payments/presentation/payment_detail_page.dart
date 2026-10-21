import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/models/enums.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/connectivity.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/routing/route_access.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../approvals/api.dart';
import '../application/payments_providers.dart';
import '../copy.dart';
import '../data/payment_models.dart';
import 'payments_page.dart';
import 'widgets/payment_cards.dart';
import 'widgets/status_sheets.dart';

/// Ödeme ayrıntısı (spec A.4 A5): durum, yöntem satırları, çek / senet, belgeler (görüntüleyici),
/// durum geçmişi (dayanak belgeyle) ve "Durumu değiştir" (StationPayments Düzenler +
/// payment.status.update; yalnızca `allowedTransitions`).
class PaymentDetailPage extends ConsumerWidget {
  const PaymentDetailPage({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(paymentDetailProvider(orderId));
    final d = async.valueOrNull;
    Future<void> refresh() async {
      ref.invalidate(paymentDetailProvider(orderId));
      try {
        await ref.read(paymentDetailProvider(orderId).future);
      } catch (_) {}
    }

    if (d == null) {
      return AppScaffold(
        title: 'Tahsilat',
        body: async.hasError
            ? Center(
                child: SingleChildScrollView(
                  child: A5FailureView(
                    failure: AppFailure.from(async.error!),
                    onRetry: refresh,
                    notFoundTitle: PaymentsCopy.notFoundTitle,
                  ),
                ),
              )
            : const _Skeleton(),
      );
    }

    final policy = ref.watch(accessPolicyProvider);
    final features = ref.watch(appConfigProvider).features;
    final online = ref.watch(isOnlineProvider);
    final canChange =
        policy.can(Pg.stationPayments, Perm.edit) &&
        policy.hasCap(Caps.paymentStatusUpdate) &&
        d.allowedTransitions.isNotEmpty;
    final orderRoute = AppRoutes.bayiOrder(d.orderId);
    final canOpenOrder = RouteAccess.isAllowed(orderRoute, policy, features);
    final t = context.aknText;
    final c = context.akn;

    Future<void> change() async {
      final message = await showPaymentStatusSheet(context, orderId: orderId);
      if (message != null && context.mounted) {
        AppToast.success(message, context: context);
      }
    }

    Future<void> openInstrument(Instrument i) async {
      final message = await showInstrumentSheet(
        context,
        instrument: i,
        canChange: canChangeInstruments(policy),
      );
      if (message != null && context.mounted) {
        AppToast.success(message, context: context);
      }
    }

    final row = d.row;
    return AppScaffold(
      title: 'Tahsilat',
      subtitle: row.orderNumber,
      refreshing: async.isLoading,
      actionBar: canChange || canOpenOrder
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (canChange && !online)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      PaymentsCopy.offline,
                      style: t.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                Row(
                  children: [
                    if (canOpenOrder)
                      Expanded(
                        child: AknButton.secondary(
                          label: 'Siparişi aç',
                          icon: Icons.receipt_long_rounded,
                          expand: true,
                          onPressed: () => context.push(orderRoute),
                        ),
                      ),
                    if (canOpenOrder && canChange) const SizedBox(width: 12),
                    if (canChange)
                      Expanded(
                        flex: 2,
                        child: AknButton(
                          label: 'Durumu değiştir',
                          icon: Icons.published_with_changes_rounded,
                          expand: true,
                          onPressed: online ? change : null,
                        ),
                      ),
                  ],
                ),
              ],
            )
          : null,
      body: PullToRefresh(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            AknHeroPanel(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _HeroBody(detail: d),
            ),
            if (d.notice != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: AknBanner(tone: AknTone.info, message: d.notice!),
              ),
            if (d.missingRequiredDocument)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: AknBanner(
                  tone: AknTone.warn,
                  message:
                      '${d.documentKindLabel ?? d.uploadKind.label} henüz yüklenmedi. Bu ödeme yönteminde belge zorunlu.',
                ),
              ),
            _Section(
              title: 'Ödeme',
              child: AknCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    FactRow(label: 'Yöntem', value: row.methodName ?? Fmt.dash),
                    if (row.termDays != null)
                      FactRow(
                        label: 'Vade',
                        value: row.termDays == 0
                            ? 'Peşin'
                            : '${row.termDays} gün',
                      ),
                    FactRow(
                      label: 'Ödeme tarihi',
                      value: Fmt.date(row.dueDate),
                      tone: row.isOverdue ? AknTone.danger : null,
                    ),
                    if (row.installments != null && row.installments! > 1)
                      FactRow(label: 'Taksit', value: '${row.installments}'),
                    if (row.displayAmount != null)
                      FactRow(
                        label: row.isEstimate ? 'Tahmini tutar' : 'Tutar',
                        value: Fmt.money(row.displayAmount),
                      ),
                    FactRow(
                      label: 'Sipariş durumu',
                      value: row.orderStatusLabel ?? row.orderStatus.label,
                    ),
                    if (row.financeLabel != null)
                      FactRow(label: 'Finans', value: row.financeLabel!),
                    for (final l in d.detailLines)
                      FactRow(label: l.label, value: l.value),
                  ],
                ),
              ),
            ),
            if (d.instrument != null)
              _Section(
                title: d.instrument!.displayKindLabel,
                child: InstrumentRowCard(
                  instrument: d.instrument!,
                  onTap: () => openInstrument(d.instrument!),
                ),
              ),
            _Section(
              title: 'Belgeler',
              subtitle: d.documentKindLabel == null
                  ? null
                  : 'Yöntemin belgesi: ${d.documentKindLabel}${d.documentRequired ? ' (zorunlu)' : ''}',
              child: d.documents.isEmpty
                  ? AknCard(
                      child: Row(
                        children: [
                          Icon(Icons.folder_open_rounded, color: c.dim),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Bu ödemeye henüz belge eklenmedi.',
                              style: t.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    )
                  : A5AttachmentGrid(attachments: d.documents),
            ),
            if (d.history.isNotEmpty)
              _Section(
                title: 'Durum geçmişi',
                child: AknCard(
                  child: StepTimeline(
                    steps: adaptSteps(context, [
                      for (final h in d.history.reversed)
                        TimelineStep(
                          title: h.title,
                          subtitle: [?h.changedByDisplay, ?h.note].join('\n'),
                          time: shortStamp(h.changedAt),
                          state: h.toStatus == PaymentStatus.bounced
                              ? TimelineState.failed
                              : TimelineState.done,
                          icon: AknStatus.payment(h.toStatus).icon,
                          content: h.attachmentPublicId == null
                              ? null
                              : Align(
                                  alignment: Alignment.centerLeft,
                                  child: AknButton.ghost(
                                    label: 'Dayanak belgeyi aç',
                                    icon: Icons.attach_file_rounded,
                                    size: AknButtonSize.small,
                                    onPressed: () => openAttachmentById(
                                      context,
                                      publicId: h.attachmentPublicId!,
                                      known: d.documents,
                                    ),
                                  ),
                                ),
                        ),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroBody extends StatelessWidget {
  const _HeroBody({required this.detail});

  final PaymentDetail detail;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final row = detail.row;
    final status = AknStatus.payment(
      row.paymentStatus,
    ).withLabel(row.paymentStatusLabel);
    final overdue = row.isOverdue || row.overdueDays > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  PaymentsCopy.methodIcon(row.methodCode),
                  size: 18,
                  color: c.dim,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    row.orderNumber,
                    style: t.captionStrong.copyWith(color: c.dim),
                  ),
                ),
              ],
            ),
            StatusChip.style(status),
          ],
        ),
        const SizedBox(height: 12),
        Semantics(header: true, child: Text(row.customerTitle, style: t.title)),
        if (row.paymentLine.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(row.paymentLine, style: t.body.copyWith(color: c.dim)),
        ],
        if (row.displayAmount != null) ...[
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AmountText(Fmt.money(row.displayAmount), large: true),
          ),
          if (row.isEstimate)
            Text(
              'Tahmini tutar (teklif henüz kesinleşmedi)',
              style: t.caption.copyWith(color: c.dim),
            ),
        ],
        if (row.dueHint != null) ...[
          const SizedBox(height: 12),
          StatusChip(
            label: overdue ? 'Ödeme ${row.dueHint}' : 'Ödemeye ${row.dueHint}',
            tone: dueTone(overdue: overdue, due: row.dueDate),
            icon: overdue ? Icons.alarm_off_rounded : Icons.event_rounded,
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHeader(
        title: title,
        subtitle: subtitle,
        padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: child,
      ),
    ],
  );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => Shimmer(
    child: ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: const [
        SkeletonBox(height: 150, radius: 24),
        SizedBox(height: 16),
        SkeletonCard(lines: 5, leading: false, margin: EdgeInsets.zero),
        SizedBox(height: 12),
        SkeletonCard(margin: EdgeInsets.zero),
      ],
    ),
  );
}
