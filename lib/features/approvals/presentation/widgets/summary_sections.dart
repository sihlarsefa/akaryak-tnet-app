import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/env/app_config_controller.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/routing/route_access.dart';
import '../../../../core/ui/ui.dart';
import '../../data/approval_models.dart';

/// Bölüm başlığı + içerik (detay tarifindeki kart bölümleri).
class DetailSection extends StatelessWidget {
  const DetailSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: title,
          subtitle: subtitle,
          actionLabel: actionLabel,
          onAction: onAction,
          padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: child,
        ),
      ],
    );
  }
}

/// Sunucunun Türkçe biçimli etiket – değer satırları.
class FactsCard extends StatelessWidget {
  const FactsCard({super.key, required this.facts});

  final List<SummaryFact> facts;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return AknCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < facts.length; i++) ...[
            if (i > 0) Divider(height: 1, color: c.lineSoft),
            FactRow(
              label: facts[i].label,
              value: facts[i].value,
              tone: _tone(facts[i].tone),
            ),
          ],
        ],
      ),
    );
  }

  static AknTone? _tone(String? key) {
    final t = AknStatus.toneFromKey(key);
    return t == AknTone.neutral ? null : t;
  }
}

/// Kalemler (sipariş satırları, ürünler).
class LinesCard extends StatelessWidget {
  const LinesCard({super.key, required this.lines});

  final List<SummaryLine> lines;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return AknCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) Divider(height: 1, color: c.lineSoft),
            Semantics(
              container: true,
              label: [
                lines[i].title,
                ?lines[i].subtitle,
                ?lines[i].value,
              ].join(', '),
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(lines[i].title, style: t.bodyStrong),
                          if (lines[i].subtitle != null)
                            Text(lines[i].subtitle!, style: t.bodySmall),
                        ],
                      ),
                    ),
                    if (lines[i].value != null) ...[
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          lines[i].value!,
                          style: t.amount.copyWith(fontSize: 14),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dikkat edilmesi gerekenler (limit aşımı, eksik belge …).
class WarningBanners extends StatelessWidget {
  const WarningBanners({super.key, required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final w in warnings)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AknBanner(tone: AknTone.warn, message: w),
          ),
      ],
    );
  }
}

/// İlgili kayıt bağlantısı.
@immutable
class RelatedLink {
  const RelatedLink(this.label, this.icon, this.route);
  final String label;
  final IconData icon;
  final String route;
}

/// Özetin bağlantılarından kullanıcının açabildikleri (yetki: [RouteAccess]).
List<RelatedLink> relatedLinks(ApprovalDetail d, AccessPolicy p) {
  final l = d.summary.links;
  final out = <RelatedLink>[];
  final customer = p.isCustomer;
  if (l.orderId != null) {
    out.add(
      RelatedLink(
        'Siparişi aç',
        Icons.receipt_long_rounded,
        customer
            ? AppRoutes.order(l.orderId!)
            : AppRoutes.bayiOrder(l.orderId!),
      ),
    );
  }
  if (customer && d.companyRequestId != null) {
    out.add(
      RelatedLink(
        'Sipariş talebini aç',
        Icons.fact_check_rounded,
        AppRoutes.companyRequest(d.companyRequestId!),
      ),
    );
  }
  if (!customer) {
    if (l.fieldOrderId != null) {
      out.add(
        RelatedLink(
          'Saha formunu aç',
          Icons.assignment_rounded,
          AppRoutes.fieldForm(l.fieldOrderId!),
        ),
      );
    }
    if (l.leadId != null) {
      out.add(
        RelatedLink(
          'Ön kaydı aç',
          Icons.how_to_reg_rounded,
          AppRoutes.fieldLead(l.leadId!),
        ),
      );
    }
    if (l.stationCustomerId != null && p.can(Pg.stationFinance)) {
      out.add(
        RelatedLink(
          'Finans kartını aç',
          Icons.account_balance_rounded,
          AppRoutes.financeCustomer(l.stationCustomerId!),
        ),
      );
    }
    if (l.customerId != null) {
      out.add(
        RelatedLink(
          'Cari kartını aç',
          Icons.apartment_rounded,
          AppRoutes.customer(l.customerId!),
        ),
      );
    }
  }
  return out;
}

/// "İlgili kayıtlar" kartı.
class RelatedLinksCard extends ConsumerWidget {
  const RelatedLinksCard({super.key, required this.detail});

  final ApprovalDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(accessPolicyProvider);
    final features = ref.watch(appConfigProvider).features;
    final c = context.akn;
    final links = [
      for (final l in relatedLinks(detail, policy))
        if (RouteAccess.isAllowed(l.route, policy, features)) l,
    ];
    if (links.isEmpty) return const SizedBox.shrink();
    return DetailSection(
      title: 'İlgili kayıtlar',
      child: AknCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < links.length; i++) ...[
              if (i > 0) Divider(height: 1, color: c.lineSoft),
              AknListTile(
                leadingIcon: links[i].icon,
                title: links[i].label,
                onTap: () => context.push(links[i].route),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
