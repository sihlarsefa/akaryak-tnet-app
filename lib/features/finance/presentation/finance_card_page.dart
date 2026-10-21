import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/models/enums.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/routing/route_access.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../../approvals/api.dart';
import '../application/finance_providers.dart';
import '../copy.dart';
import '../data/finance_models.dart';
import 'finance_customers_page.dart' show riskShort;

/// Cari finans kartı (spec A.4 A5): durum ve risk, limit kullanımı, finans koşulları, tahsilat riski,
/// teminatlar, karar geçmişi ve risk raporları. Salt okunur (kart düzenleme web portalında).
class FinanceCardPage extends ConsumerWidget {
  const FinanceCardPage({super.key, required this.stationCustomerId});

  final int stationCustomerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(financeCardProvider(stationCustomerId));
    Future<void> refresh() async {
      ref.invalidate(financeCardProvider(stationCustomerId));
      try {
        await ref.read(financeCardProvider(stationCustomerId).future);
      } catch (_) {}
    }

    final card = async.valueOrNull;
    return AppScaffold(
      title: 'Finans kartı',
      subtitle: card?.profile.customerTitle,
      refreshing: async.isLoading && card != null,
      body: card == null
          ? (async.hasError
                ? Center(
                    child: SingleChildScrollView(
                      child: A5FailureView(
                        failure: AppFailure.from(async.error!),
                        onRetry: refresh,
                        notFoundTitle: FinanceCopy.notFoundTitle,
                      ),
                    ),
                  )
                : const _CardSkeleton())
          : PullToRefresh(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _Hero(profile: card.profile),
                  ..._sections(context, ref, card),
                ],
              ),
            ),
    );
  }

  List<Widget> _sections(
    BuildContext context,
    WidgetRef ref,
    FinanceCard card,
  ) {
    final p = card.profile;
    final policy = ref.watch(accessPolicyProvider);
    final features = ref.watch(appConfigProvider).features;
    final today = TrTime.todayStart();
    final reviewOverdue =
        p.nextReviewDate != null && p.nextReviewDate!.isBefore(today);
    final customerRoute = AppRoutes.customer(p.customerId);
    final usage = p.limitUsage;
    return [
      if (p.status == FinanceProfileStatus.pending ||
          p.status == FinanceProfileStatus.infoRequested)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: AknBanner(
            tone: AknTone.warn,
            message:
                'Kart finans onayı bekliyor; karar Onaylarım\'daki "Yeni cari finans onayı" talebinden verilir.',
          ),
        ),
      if (reviewOverdue)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: AknBanner(
            tone: AknTone.warn,
            icon: Icons.event_busy_rounded,
            message:
                'Gözden geçirme tarihi geçti (${Fmt.date(p.nextReviewDate)}). Kartı web portalında güncelleyin.',
          ),
        ),
      _Section(
        title: 'Limit',
        child: AknCard(
          child: usage != null && usage.hasLimit
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    UsageBar(
                      value: usage.ratio ?? 0,
                      label: [
                        'Kullanım',
                        if (usage.limitPeriod != null)
                          TurkishText.lower(usage.limitPeriod!),
                      ].join(' · '),
                      valueLabel: Fmt.percent(
                        (usage.ratio ?? 0) * 100,
                        maxFraction: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FactRow(
                      label: 'Limit',
                      value: _amount(usage.limitAmount, usage.isLiters),
                    ),
                    FactRow(
                      label: 'Kullanılan',
                      value: _amount(usage.used, usage.isLiters),
                    ),
                    FactRow(
                      label: 'Kalan',
                      value: _amount(usage.available, usage.isLiters),
                      tone: (usage.available ?? 1) <= 0 ? AknTone.danger : null,
                    ),
                  ],
                )
              : const FactRow(
                  label: 'Bağlantı limiti',
                  value: 'Tanımlı değil (limitsiz)',
                ),
        ),
      ),
      _Section(
        title: 'Finans koşulları',
        child: AknCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              FactRow(
                label: 'Onaylanan limit',
                value: p.approvedLimitAmount == null
                    ? 'Öneri yok'
                    : Fmt.money(p.approvedLimitAmount),
              ),
              FactRow(
                label: 'İzinli yöntemler',
                value: p.allowedMethodCodes.isEmpty
                    ? 'Tümü (kısıt yok)'
                    : p.allowedMethodCodes.map(paymentMethodName).join(', '),
              ),
              FactRow(
                label: 'En uzun vade',
                value: p.maxTermDays == null
                    ? 'Kısıt yok'
                    : (p.maxTermDays == 0 ? 'Peşin' : '${p.maxTermDays} gün'),
              ),
              FactRow(
                label: 'Teminat oranı',
                value: [
                  Fmt.percent(p.collateralRatioPercent),
                  if (p.suggestedCollateralRatioPercent != null)
                    'öneri ${Fmt.percent(p.suggestedCollateralRatioPercent)}',
                ].join(' · '),
              ),
              if (p.firstNOrdersRequireFinance != null)
                FactRow(
                  label: 'Finans incelemesi',
                  value: 'İlk ${p.firstNOrdersRequireFinance} sipariş',
                ),
              FactRow(
                label: 'Stratejik fiyat',
                value: p.isStrategicPricing ? 'Evet' : 'Hayır',
              ),
              FactRow(
                label: 'Sonraki gözden geçirme',
                value: Fmt.date(p.nextReviewDate),
                tone: reviewOverdue ? AknTone.warn : null,
              ),
            ],
          ),
        ),
      ),
      _Section(
        title: 'Tahsilat riski',
        child: AknCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              FactRow(label: 'Açık bakiye', value: Fmt.money(p.openBalance)),
              FactRow(
                label: 'Gecikmiş tutar',
                value: Fmt.money(p.overdueAmount ?? 0),
                tone: (p.overdueAmount ?? 0) > 0 ? AknTone.danger : null,
              ),
              FactRow(
                label: 'Karşılıksız çek',
                value: p.hasBouncedCheque ? 'Var' : 'Yok',
                tone: p.hasBouncedCheque ? AknTone.danger : AknTone.ok,
              ),
              FactRow(
                label: 'Protestolu senet',
                value: p.hasProtestedNote ? 'Var' : 'Yok',
                tone: p.hasProtestedNote ? AknTone.danger : AknTone.ok,
              ),
            ],
          ),
        ),
      ),
      if (p.collaterals.isNotEmpty)
        _Section(
          title: 'Teminatlar',
          child: AknCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < p.collaterals.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: context.akn.lineSoft),
                  _CollateralTile(c: p.collaterals[i]),
                ],
              ],
            ),
          ),
        ),
      if (p.notes != null)
        _Section(
          title: 'Notlar',
          child: AknCard(child: Text(p.notes!, style: context.aknText.body)),
        ),
      if (card.reviews.isNotEmpty)
        _Section(
          title: 'Karar geçmişi',
          child: AknCard(
            child: StepTimeline(
              steps: adaptSteps(context, [
                for (final r in card.reviews)
                  TimelineStep(
                    title: r.decision.label,
                    subtitle: [
                      ?r.decidedByDisplay,
                      ?r.note,
                      ?FinanceCopy.describeConditions(r.conditionsJson),
                    ].join('\n'),
                    time: Fmt.date(r.decidedAt),
                    state: switch (r.decision) {
                      FinanceDecisionKind.rejected => TimelineState.failed,
                      FinanceDecisionKind.infoRequested =>
                        TimelineState.warning,
                      _ => TimelineState.done,
                    },
                  ),
              ]),
            ),
          ),
        ),
      if (card.riskReports.isNotEmpty)
        _Section(
          title: 'Risk raporları',
          child: Column(
            children: [
              for (final r in card.riskReports)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RiskReportCard(report: r),
                ),
            ],
          ),
        ),
      if (RouteAccess.isAllowed(customerRoute, policy, features))
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: AknCard(
            padding: EdgeInsets.zero,
            child: AknListTile(
              leadingIcon: Icons.apartment_rounded,
              title: 'Cari kartını aç',
              subtitle: 'Siparişler, teslimat noktaları ve notlar',
              onTap: () => context.push(customerRoute),
            ),
          ),
        ),
    ];
  }

  static String _amount(double? v, bool liters) =>
      liters ? Fmt.liters(v) : Fmt.money(v);
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHeader(
        title: title,
        padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: child,
      ),
    ],
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.profile});

  final FinanceProfile profile;

  @override
  Widget build(BuildContext context) => AknHeroPanel(
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: _HeroBody(profile: profile),
  );
}

class _HeroBody extends StatelessWidget {
  const _HeroBody({required this.profile});

  final FinanceProfile profile;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final p = profile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(p.customerTitle, style: t.title)),
        if (p.taxNumber != null) ...[
          const SizedBox(height: 4),
          Text('VKN ${p.taxNumber}', style: t.body.copyWith(color: c.dim)),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusChip.style(AknStatus.financeProfile(p.status)),
            if (p.riskClass != RiskClass.none && !p.riskClass.isUnknown)
              StatusChip.style(
                AknStatus.risk(p.riskClass).withLabel(riskShort(p.riskClass)),
              ),
            if (p.isGrandfathered)
              const StatusChip(
                label: 'Eski cari',
                tone: AknTone.neutral,
                icon: Icons.history_rounded,
              ),
          ],
        ),
        if (p.decidedAt != null) ...[
          const SizedBox(height: 12),
          Text(
            'Son karar: ${Fmt.date(p.decidedAt)}',
            style: t.caption.copyWith(color: c.dim),
          ),
        ],
      ],
    );
  }
}

class _CollateralTile extends StatelessWidget {
  const _CollateralTile({required this.c});

  final Collateral c;

  @override
  Widget build(BuildContext context) {
    final tone = switch (c.status) {
      CollateralStatus.active => AknTone.ok,
      CollateralStatus.expired => AknTone.warn,
      _ => AknTone.neutral,
    };
    final chip = StatusChip(
      label: c.status.label,
      tone: tone,
      icon: AknStatus.toneIcon(tone),
      size: StatusChipSize.small,
    );
    // Büyük yazıda durum çipi satırın sağına sığmaz; altına iner.
    final large = isLargeText(context);
    final tile = AknListTile(
      leadingIcon: Icons.shield_rounded,
      leadingTone: tone,
      title: '${c.kind.label} · ${Fmt.money(c.amount)}',
      subtitle: [
        ?c.bankName,
        if (c.validUntil != null) 'geçerlilik ${Fmt.date(c.validUntil)}',
        ?c.note,
      ].join(' · '),
      trailing: large ? null : chip,
    );
    if (!large) return tile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tile,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Shrinkable(child: chip),
          ),
        ),
      ],
    );
  }
}

class _RiskReportCard extends StatelessWidget {
  const _RiskReportCard({required this.report});

  final RiskReport report;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final r = report;
    if (!r.success) {
      return AknBanner(
        tone: AknTone.warn,
        title: 'Rapor alınamadı · ${Fmt.date(r.requestedAt)}',
        message: r.errorMessage ?? 'Sağlayıcı yanıt vermedi.',
      );
    }
    return AknCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.provider, style: t.bodyStrong),
                    Text(Fmt.dateTime(r.requestedAt), style: t.caption),
                  ],
                ),
              ),
              if (r.suggestedRiskClass != RiskClass.none &&
                  !r.suggestedRiskClass.isUnknown)
                StatusChip.style(
                  AknStatus.risk(
                    r.suggestedRiskClass,
                  ).withLabel('Öneri ${r.suggestedRiskClass.label}'),
                  size: StatusChipSize.small,
                ),
            ],
          ),
          if (r.isMock) ...[
            const SizedBox(height: 8),
            const AknBanner(
              tone: AknTone.info,
              message: 'Deneme raporu: örnek veridir, karta yazılmaz.',
            ),
          ],
          const SizedBox(height: 8),
          if (r.score != null) FactRow(label: 'Skor', value: '${r.score}'),
          FactRow(
            label: 'Toplam banka limiti',
            value: Fmt.money(r.totalBankLimit),
          ),
          FactRow(
            label: 'Toplam banka riski',
            value: Fmt.money(r.totalBankRisk),
          ),
          FactRow(
            label: 'Gecikme',
            value: Fmt.money(r.overdueAmount ?? 0),
            tone: (r.overdueAmount ?? 0) > 0 ? AknTone.danger : null,
          ),
          FactRow(
            label: 'Karşılıksız çek · protesto',
            value:
                '${r.bouncedChequeCount ?? 0} · ${r.protestedNoteCount ?? 0}',
            tone: (r.bouncedChequeCount ?? 0) + (r.protestedNoteCount ?? 0) > 0
                ? AknTone.danger
                : null,
          ),
          if (r.lines.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Bankalar', style: t.label),
            for (final l in r.lines)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Semantics(
                  label:
                      '${l.bankName}: limit ${Fmt.money(l.limit)}, risk ${Fmt.money(l.risk)}',
                  excludeSemantics: true,
                  // Büyük yazıda tutarlar banka adının altına iner.
                  child: Flex(
                    direction: isLargeText(context)
                        ? Axis.vertical
                        : Axis.horizontal,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isLargeText(context))
                        Text(l.bankName, style: t.bodySmall)
                      else
                        Expanded(child: Text(l.bankName, style: t.bodySmall)),
                      Text(
                        '${Fmt.moneyCompact(l.risk)} / ${Fmt.moneyCompact(l.limit)}',
                        style: t.caption.copyWith(
                          color: c.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (r.pdfAttachmentPublicId != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: AknButton.ghost(
                label: 'Rapor PDF\'ini aç',
                icon: Icons.picture_as_pdf_rounded,
                onPressed: () => openAttachmentById(
                  context,
                  publicId: r.pdfAttachmentPublicId!,
                  fallbackName: 'risk-raporu.pdf',
                  fallbackType: 'application/pdf',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) => Shimmer(
    child: ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: const [
        SkeletonBox(height: 140, radius: 24),
        SizedBox(height: 16),
        SkeletonCard(lines: 3, leading: false, margin: EdgeInsets.zero),
        SizedBox(height: 12),
        SkeletonCard(lines: 5, leading: false, margin: EdgeInsets.zero),
      ],
    ),
  );
}
