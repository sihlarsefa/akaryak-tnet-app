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

/// Şirket içi sipariş talebinin sonucu (karar sonrası; tasarım v2 §7.13): bölüm başlığı "Talep
/// sonucu", bir özet cümlesi ("1 sipariş oluşturuldu, 1 satır oluşturulamadı"), satır satır
/// ledger (ürün ve litre; lamba: oluşan sipariş numarası, "Oluşturulamadı" ya da "Bekliyor"),
/// siparişe dokunarak geçiş ve "Başarısız satırları yeni siparişe aktar"
/// (`/orders/new?fromRequest={id}`). Talep okunamazsa (yetki yok) sunucu özetinin kalemleri
/// gösterilir.
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
    final c = context.akn;
    final reorder = '${AppRoutes.orderNew}?fromRequest=$id';
    final canReorder = RouteAccess.isAllowed(reorder, policy, features);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Shimmer(child: SkeletonCard(margin: EdgeInsets.zero)),
      ),
      error: (_, _) {
        // Talep okunamadı: özetteki kalemlerden sonuç gösterilir (bağlantısız).
        final failed = detail.summary.lines.any(
          (l) => (l.value ?? '').contains('Oluşturulamadı'),
        );
        return _Section(
          summary: null,
          children: [
            AknLedger(
              children: [
                for (final l in detail.summary.lines)
                  AknListTile(
                    title: l.title,
                    subtitle: [?l.subtitle, ?l.value].join('\n'),
                    subtitleMaxLines: 4,
                  ),
              ],
            ),
            if (failed && canReorder)
              _ReorderButton(onTap: () => context.push(reorder)),
          ],
        );
      },
      data: (req) {
        final created = req.createdCount;
        final failed = req.failedCount;
        final parts = [
          if (created > 0)
            created == 1
                ? '1 sipariş oluşturuldu'
                : '$created sipariş oluşturuldu',
          if (failed > 0)
            failed == 1
                ? '1 satır oluşturulamadı'
                : '$failed satır oluşturulamadı',
          if (created == 0 && failed == 0) req.displayStatusLabel,
        ];
        final tone = failed > 0
            ? AknTone.warn
            : (created > 0 ? AknTone.ok : AknTone.neutral);
        return _Section(
          summary: _Summary(text: parts.join(', '), tone: tone),
          children: [
            AknLedger(children: [for (final l in req.lines) _LineRow(line: l)]),
            if (req.hasFailures && canReorder)
              _ReorderButton(onTap: () => context.push(reorder)),
            if (req.hasFailures && !canReorder)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  'Başarısız satırlar için talep edene yeni sipariş vermesini söyleyin.',
                  style: t.bodySmall.copyWith(color: c.dim),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// "Talep sonucu" bölümü: başlık, özet cümlesi ve içerik (kutu yok; satırlar tam genişlik).
class _Section extends StatelessWidget {
  const _Section({required this.summary, required this.children});

  final Widget? summary;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      const SectionHeader(title: 'Talep sonucu'),
      if (summary != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: summary,
        ),
      ...children,
    ],
  );
}

/// Özet cümlesi: tonun simgesi (tamamı oluştu: yeşil onay; eksik var: koyu sarı uyarı) + metin.
class _Summary extends StatelessWidget {
  const _Summary({required this.text, required this.tone});

  final String text;
  final AknTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final icon = switch (tone) {
      AknTone.ok => Icons.check_circle_rounded,
      AknTone.warn => Icons.error_rounded,
      _ => Icons.schedule_outlined,
    };
    final color = tone == AknTone.neutral ? c.dim : c.tone(tone).fg;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: ExcludeSemantics(child: Icon(icon, size: 20, color: color)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: t.body.copyWith(color: c.ink)),
        ),
      ],
    );
  }
}

/// Talep satırı: "Motorin, 8.000 L" / nokta ve gün; lamba: oluşan sipariş (yeşil), oluşturulamadı
/// (kırmızı + neden) ya da bekliyor. Sipariş oluştuysa dokununca açılır.
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
    final product = l.productName ?? 'Ürün';
    final title = '$product, ${Fmt.liters(l.quantityLiters)}';
    final detail = [
      ?l.deliveryPointName,
      if (l.requestedDeliveryDate != null) Fmt.date(l.requestedDeliveryDate),
    ].join(', ');
    final lamp = l.created
        ? AknLamp(
            label: l.orderNumber ?? 'Sipariş oluşturuldu',
            tone: AknTone.ok,
            solid: true,
          )
        : l.failed
        ? const AknLamp(label: 'Oluşturulamadı', tone: AknTone.danger)
        : const AknLamp(label: 'Bekliyor', tone: AknTone.neutral);
    return AknListTile(
      title: title,
      subtitle: detail.isEmpty ? null : detail,
      status: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(alignment: AlignmentDirectional.centerStart, child: lamp),
          if (l.failed && l.error != null) ...[
            const SizedBox(height: 4),
            Text(l.error!, style: t.bodySmall.copyWith(color: c.danger.fg)),
          ],
        ],
      ),
      showChevron: canOpen,
      onTap: canOpen ? () => context.push(orderRoute) : null,
      semanticLabel: [
        title,
        if (detail.isNotEmpty) detail,
        if (l.created) 'sipariş ${l.orderNumber ?? ''} oluşturuldu',
        if (l.failed) 'oluşturulamadı: ${l.error}',
        if (canOpen) 'siparişi açmak için dokunun',
      ].join(', '),
    );
  }
}

class _ReorderButton extends StatelessWidget {
  const _ReorderButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
    child: AknButton.secondary(
      label: 'Başarısız satırları yeni siparişe aktar',
      icon: Icons.replay_rounded,
      expand: true,
      onPressed: onTap,
    ),
  );
}
