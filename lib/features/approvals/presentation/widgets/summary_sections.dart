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

/// Bölüm başlığı + içerik (tasarım v3 §4: 18/24 800 başlık, içerik genelde beyaz kart). İçerik 20
/// px kenarda; [bleed] iken tam genişlik (sayfa düzeyindeki satır grubu kendini kart olarak
/// yüzdürür).
class DetailSection extends StatelessWidget {
  const DetailSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.bleed = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// İçerik kenar boşluksuz (tam genişlik satırlar).
  final bool bleed;

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
        ),
        if (bleed)
          child
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: child,
          ),
      ],
    );
  }
}

/// Sunucunun Türkçe biçimli etiket – değer satırları (tasarım v3 §4): beyaz kart (r20, kart
/// gölgesi), etiket solda soluk, değer sağda; satırlar arasında içeriden ince çizgi.
class FactsCard extends StatelessWidget {
  const FactsCard({super.key, required this.facts});

  final List<SummaryFact> facts;

  @override
  Widget build(BuildContext context) {
    return AknCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < facts.length; i++) ...[
            if (i > 0) const AknLedgerDivider(indent: 0),
            FactRow(
              label: facts[i].label,
              value: facts[i].value.replaceAll(' · ', ', '),
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

/// Kalemler (sipariş satırları, ürünler; tasarım v3 §4): beyaz kartta satırlar, solda ürün kuyusu,
/// değer sağda (`amount`, tablo rakamları); aralarında içeriden ince çizgi.
class LinesCard extends StatelessWidget {
  const LinesCard({super.key, required this.lines});

  final List<SummaryLine> lines;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return AknCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const AknLedgerDivider(indent: 0),
            Semantics(
              container: true,
              label: [
                lines[i].title,
                ?lines[i].subtitle,
                ?lines[i].value,
              ].join(', '),
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AknIconBox(
                      icon: PhosphorIconsRegular.gasPump,
                      size: 36,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lines[i].title,
                            style: t.bodyStrong.copyWith(color: c.ink),
                          ),
                          if (lines[i].subtitle != null)
                            Text(
                              lines[i].subtitle!.replaceAll(' · ', ', '),
                              style: t.bodySmall.copyWith(color: c.dim),
                            ),
                        ],
                      ),
                    ),
                    if (lines[i].value != null) ...[
                      const SizedBox(width: 12),
                      // Değer doğal genişliğinde, sağa yaslı (en çok ekranın %40'ı; uzunsa sarar).
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                        ),
                        child: Text(
                          lines[i].value!,
                          style: t.amount.copyWith(fontSize: 15, color: c.ink),
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
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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
        PhosphorIconsRegular.receipt,
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
        PhosphorIconsRegular.listChecks,
        AppRoutes.companyRequest(d.companyRequestId!),
      ),
    );
  }
  if (!customer) {
    if (l.fieldOrderId != null) {
      out.add(
        RelatedLink(
          'Saha formunu aç',
          PhosphorIconsRegular.clipboardText,
          AppRoutes.fieldForm(l.fieldOrderId!),
        ),
      );
    }
    if (l.leadId != null) {
      out.add(
        RelatedLink(
          'Ön kaydı aç',
          PhosphorIconsRegular.userCheck,
          AppRoutes.fieldLead(l.leadId!),
        ),
      );
    }
    if (l.stationCustomerId != null && p.can(Pg.stationFinance)) {
      out.add(
        RelatedLink(
          'Finans kartını aç',
          PhosphorIconsRegular.bank,
          AppRoutes.financeCustomer(l.stationCustomerId!),
        ),
      );
    }
    if (l.customerId != null) {
      out.add(
        RelatedLink(
          'Cari kartını aç',
          PhosphorIconsRegular.buildings,
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
    final links = [
      for (final l in relatedLinks(detail, policy))
        if (RouteAccess.isAllowed(l.route, policy, features)) l,
    ];
    if (links.isEmpty) return const SizedBox.shrink();
    return DetailSection(
      title: 'İlgili kayıtlar',
      bleed: true,
      child: AknLedger(
        children: [
          for (final l in links)
            AknListTile(
              leadingIcon: l.icon,
              title: l.label,
              showChevron: true,
              dense: true,
              onTap: () => context.push(l.route),
            ),
        ],
      ),
    );
  }
}
