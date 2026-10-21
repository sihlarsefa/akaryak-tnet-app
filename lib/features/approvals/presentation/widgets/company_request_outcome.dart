import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/env/app_config_controller.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/routing/route_access.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/approvals_providers.dart';
import '../../data/approval_models.dart';
import '../../shared/layout.dart';

/// Şirket içi sipariş talebinin sonucu (karar sonrası): satır satır oluşan sipariş ya da hata,
/// siparişlere bağlantı ve "Başarısız satırları yeni siparişe aktar" (`/orders/new?fromRequest={id}`).
/// Talep okunamazsa (yetki yok) sunucu özetinin kalemleri gösterilir.
class CompanyRequestOutcome extends ConsumerWidget {
  const CompanyRequestOutcome({super.key, required this.detail});

  final ApprovalDetail detail;

  /// Gösterilmeli mi: talep onaylandı ya da satırlardan biri sonuçlandı.
  static bool applies(ApprovalDetail d) =>
      d.type == ApprovalType.companyOrderRequest &&
      d.companyRequestId != null &&
      (d.status == ApprovalStatus.approved ||
          d.summary.lines.any(
            (l) => (l.value ?? '').contains('Oluşturulamadı'),
          ));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = detail.companyRequestId!;
    final async = ref.watch(companyRequestProvider(id));
    final policy = ref.watch(accessPolicyProvider);
    final features = ref.watch(appConfigProvider).features;
    final t = context.aknText;
    final reorder = '${AppRoutes.orderNew}?fromRequest=$id';
    final canReorder = RouteAccess.isAllowed(reorder, policy, features);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Shimmer(child: SkeletonCard(margin: EdgeInsets.zero)),
      ),
      error: (_, _) {
        // Talep okunamadı: özetteki kalemlerden sonuç gösterilir (bağlantısız).
        final failed = detail.summary.lines.any(
          (l) => (l.value ?? '').contains('Oluşturulamadı'),
        );
        return _Frame(
          title: 'Talep sonucu',
          subtitle: null,
          children: [
            for (final l in detail.summary.lines)
              AknListTile(
                title: l.title,
                subtitle: [?l.subtitle, ?l.value].join('\n'),
                subtitleMaxLines: 4,
              ),
            if (failed && canReorder)
              _ReorderButton(onTap: () => context.push(reorder)),
          ],
        );
      },
      data: (req) {
        final created = req.createdCount;
        final failed = req.failedCount;
        final subtitle = [
          if (created > 0)
            created == 1
                ? '1 sipariş oluşturuldu'
                : '$created sipariş oluşturuldu',
          if (failed > 0)
            failed == 1
                ? '1 satır oluşturulamadı'
                : '$failed satır oluşturulamadı',
          if (created == 0 && failed == 0) req.displayStatusLabel,
        ].join(' · ');
        return _Frame(
          title: 'Talep sonucu',
          subtitle: subtitle,
          tone: failed > 0
              ? AknTone.warn
              : (created > 0 ? AknTone.ok : AknTone.neutral),
          children: [
            for (final l in req.lines) _LineRow(line: l),
            if (req.hasFailures && canReorder) ...[
              const SizedBox(height: 4),
              _ReorderButton(onTap: () => context.push(reorder)),
            ],
            if (req.hasFailures && !canReorder)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  'Başarısız satırlar için talep edene yeni sipariş vermesini söyleyin.',
                  style: t.bodySmall,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.title,
    required this.children,
    this.subtitle,
    this.tone = AknTone.neutral,
  });

  final String title;
  final String? subtitle;
  final AknTone tone;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: AknCard(
        padding: EdgeInsets.zero,
        accent: tone == AknTone.neutral ? null : tone,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  Icon(
                    tone == AknTone.warn
                        ? Icons.rule_rounded
                        : Icons.fact_check_rounded,
                    color: tone == AknTone.neutral ? c.dim : c.tone(tone).fg,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(title, style: t.bodyStrong),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty)
                          Text(subtitle!, style: t.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _LineRow extends ConsumerWidget {
  const _LineRow({required this.line});

  final CompanyRequestLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.akn;
    final t = context.aknText;
    final l = line;
    final policy = ref.watch(accessPolicyProvider);
    final features = ref.watch(appConfigProvider).features;
    final orderRoute = l.orderId == null ? null : AppRoutes.order(l.orderId!);
    final canOpen =
        orderRoute != null &&
        RouteAccess.isAllowed(orderRoute, policy, features);
    final detail = [
      Fmt.liters(l.quantityLiters),
      ?l.deliveryPointName,
      if (l.requestedDeliveryDate != null) Fmt.date(l.requestedDeliveryDate),
    ].join(' · ');
    final Widget trailing = l.created
        ? StatusChip(
            label: l.orderNumber ?? 'Sipariş',
            tone: AknTone.ok,
            icon: Icons.check_circle_rounded,
            size: StatusChipSize.small,
          )
        : l.failed
        ? const StatusChip(
            label: 'Oluşturulamadı',
            tone: AknTone.danger,
            icon: Icons.error_rounded,
            size: StatusChipSize.small,
          )
        : const StatusChip(
            label: 'Bekliyor',
            tone: AknTone.neutral,
            icon: Icons.schedule_rounded,
            size: StatusChipSize.small,
          );
    // Büyük yazıda sonuç çipi satırın sağına sığmaz; başlığın altına iner.
    final large = isLargeText(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: c.lineSoft),
        AknListTile(
          title: l.productName ?? 'Ürün',
          subtitle: detail,
          trailing: large ? null : trailing,
          showChevron: canOpen,
          onTap: canOpen ? () => context.push(orderRoute) : null,
          semanticLabel: [
            l.productName ?? 'Ürün',
            detail,
            if (l.created) 'sipariş ${l.orderNumber ?? ''} oluşturuldu',
            if (l.failed) 'oluşturulamadı: ${l.error}',
            if (canOpen) 'siparişi açmak için dokunun',
          ].join(', '),
        ),
        if (large)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Shrinkable(child: trailing),
            ),
          ),
        if (l.failed && l.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              l.error!,
              style: t.bodySmall.copyWith(color: c.danger.fg),
            ),
          ),
      ],
    );
  }
}

class _ReorderButton extends StatelessWidget {
  const _ReorderButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
    child: AknButton.secondary(
      label: 'Başarısız satırları yeni siparişe aktar',
      icon: Icons.replay_rounded,
      expand: true,
      onPressed: onTap,
    ),
  );
}
