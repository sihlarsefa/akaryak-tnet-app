import 'dart:math' as math;

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
import 'finance_customers_page.dart'
    show financeProfileLamp, riskLamp, riskShort;

/// Cari finans kartı (spec A.4 A5; tasarım v3 "Akış"): itilen başlık "Finans kartı"; gövde cari adı
/// (`display`), VKN ve son karar, durum ve risk çipleri; **kahraman kart** "Kullanılabilir limit" (kalan
/// limit, kullanım ölçeri, Limit / Kullanılan / Kullanım; yükselerek gelir); sonra beyaz kartlarda
/// finans koşulları, tahsilat riski, teminatlar, notlar, karar geçmişi ve risk raporları — kartlar art
/// arda yükselerek gelir. Salt okunur (kart düzenleme web portalında).
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
      // v4 §3.2: kaydırınca carinin adı çubukta.
      collapsedTitle: card?.profile.customerTitle,
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
              child: StaggerScope(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    FadeUp(offset: 10, child: _Header(profile: card.profile)),
                    ..._sections(context, ref, card),
                  ],
                ),
              ),
            ),
    );
  }

  List<Widget> _sections(
    BuildContext context,
    WidgetRef ref,
    FinanceCard card,
  ) {
    final t = context.aknText;
    final p = card.profile;
    final policy = ref.watch(accessPolicyProvider);
    final features = ref.watch(appConfigProvider).features;
    final today = TrTime.todayStart();
    final reviewOverdue =
        p.nextReviewDate != null && p.nextReviewDate!.isBefore(today);
    final customerRoute = AppRoutes.customer(p.customerId);
    final usage = p.limitUsage;
    final hasLimit =
        usage != null && usage.hasLimit && (usage.limitAmount ?? 0) > 0;
    final overdue = (p.overdueAmount ?? 0) > 0;
    // Kartlar art arda yükselir; aşağıdakiler kaydırdıkça kayarak girer.
    var n = 0;
    Widget stagger(Widget child) => StaggerItem(index: n++, child: child);
    const money = TextStyle(fontFeatures: AknNumerals.tabular);
    return [
      if (hasLimit)
        // Kahraman kart ilk açılışta yükselip büyüyerek gelir.
        FadeUp(
          offset: 24,
          scale: 0.94,
          duration: AknMotion.heroRise,
          curve: AknMotion.emphasizedCurve,
          child: _LimitPlate(usage: usage),
        )
      else
        stagger(
          const _Section(
            title: 'Limit',
            child: FactList(
              facts: [
                FactRow(
                  label: 'Bağlantı limiti',
                  value: 'Tanımlı değil (limitsiz)',
                ),
              ],
            ),
          ),
        ),
      if (p.status == FinanceProfileStatus.pending ||
          p.status == FinanceProfileStatus.infoRequested)
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: AknBanner(
            tone: AknTone.warn,
            message:
                'Kart finans onayı bekliyor. Kararı Onaylarım\'daki "Yeni cari finans onayı" talebinden verin.',
          ),
        ),
      if (reviewOverdue)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: AknBanner(
            tone: AknTone.warn,
            icon: PhosphorIconsRegular.calendarX,
            message:
                'Gözden geçirme günü ${Fmt.longDate(p.nextReviewDate)} idi. Kartı web portalında güncelleyin.',
          ),
        ),
      stagger(
        _Section(
          title: 'Finans koşulları',
          child: FactList(
            facts: [
              FactRow(
                label: 'Onaylanan limit',
                value: p.approvedLimitAmount == null
                    ? 'Öneri yok'
                    : Fmt.moneyWhole(p.approvedLimitAmount),
                valueStyle: money,
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
                ].join(', '),
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
                value: Fmt.longDate(p.nextReviewDate),
                tone: reviewOverdue ? AknTone.warn : null,
              ),
            ],
          ),
        ),
      ),
      stagger(
        _Section(
          title: 'Tahsilat riski',
          child: FactList(
            facts: [
              FactRow(
                label: 'Açık bakiye',
                value: Fmt.money(p.openBalance),
                valueStyle: money,
              ),
              FactRow(
                label: 'Gecikmiş tutar',
                value: overdue ? Fmt.money(p.overdueAmount) : 'Yok',
                tone: overdue ? AknTone.danger : null,
                valueStyle: money,
              ),
              FactRow(
                label: 'Karşılıksız çek',
                value: p.hasBouncedCheque ? 'Var' : 'Yok',
                tone: p.hasBouncedCheque ? AknTone.danger : null,
              ),
              FactRow(
                label: 'Protestolu senet',
                value: p.hasProtestedNote ? 'Var' : 'Yok',
                tone: p.hasProtestedNote ? AknTone.danger : null,
              ),
            ],
          ),
        ),
      ),
      if (p.collaterals.isNotEmpty)
        stagger(
          _Section(
            title: 'Teminatlar',
            count: p.collaterals.length,
            padded: false,
            child: AknLedger(
              children: [for (final c in p.collaterals) _CollateralRow(c: c)],
            ),
          ),
        ),
      if (p.notes != null)
        stagger(
          _Section(
            title: 'Notlar',
            child: Text(p.notes!, style: t.body),
          ),
        ),
      if (card.reviews.isNotEmpty)
        stagger(
          _Section(
            title: 'Karar geçmişi',
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
        stagger(
          _Section(
            title: 'Risk raporları',
            count: card.riskReports.length,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < card.riskReports.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: SizedBox(
                        height: 1,
                        child: ColoredBox(color: context.akn.line),
                      ),
                    ),
                  _RiskReport(report: card.riskReports[i]),
                ],
              ],
            ),
          ),
        ),
      if (RouteAccess.isAllowed(customerRoute, policy, features))
        stagger(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _CardSurface(
              child: AknListTile(
                leading: const _GlyphTile(icon: PhosphorIconsRegular.buildings),
                title: 'Cari kartını aç',
                subtitle: 'Siparişler, teslimat noktaları ve notlar',
                showChevron: true,
                padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
                onTap: () => context.push(customerRoute),
              ),
            ),
          ),
        ),
    ];
  }
}

/// Bölüm (tasarım v3): sayfa zemininde süzülen beyaz kart (20 köşe, kart gölgesi); içinde başlık ve
/// içerik. [padded] içerik 18 px kenarla girer; defter satırları kendi kenarlarını verir.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.count,
    this.padded = true,
  });

  final String title;
  final int? count;
  final Widget child;
  final bool padded;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: _CardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 58),
            child: SectionHeader(
              title: title,
              count: count,
              padding: const EdgeInsets.fromLTRB(18, 10, 8, 0),
            ),
          ),
          if (padded)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: child,
            )
          else
            Padding(padding: const EdgeInsets.only(bottom: 4), child: child),
        ],
      ),
    ),
  );
}

/// Beyaz kart yüzeyi (tasarım v3): 20 köşe, yumuşak kart gölgesi; koyu temada 1 px ince çizgi; içerik
/// köşelere kırpılır.
class _CardSurface extends StatelessWidget {
  const _CardSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AknRadius.card,
        boxShadow: AknShadows.card(c),
      ),
      position: DecorationPosition.background,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: AknRadius.card,
          border: c.isDark ? Border.all(color: c.line) : null,
        ),
        child: AknCardScope(
          child: ClipRRect(borderRadius: AknRadius.card, child: child),
        ),
      ),
    );
  }
}

/// 36 px yuvarlak köşeli Beton simge karosu (kart satırının önü).
class _GlyphTile extends StatelessWidget {
  const _GlyphTile({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: context.akn.surfaceAlt,
        borderRadius: BorderRadius.circular(AknRadius.sm),
      ),
      child: Icon(icon, size: 19, color: context.akn.ink),
    ),
  );
}

/// Olgular: etiket / değer satırları, aralarında ince çizgi (tasarım v3: `lineSoft`).
class FactList extends StatelessWidget {
  const FactList({super.key, required this.facts});

  final List<Widget> facts;

  @override
  Widget build(BuildContext context) {
    final line = context.akn.lineSoft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < facts.length; i++) ...[
          if (i > 0) SizedBox(height: 1, child: ColoredBox(color: line)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: facts[i],
          ),
        ],
      ],
    );
  }
}

/// Gövdenin başı (tasarım v3): cari adı (`display`), VKN ve son karar, kart durumu ve risk çipleri.
class _Header extends StatelessWidget {
  const _Header({required this.profile});

  final FinanceProfile profile;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final p = profile;
    final line = [
      if (p.taxNumber != null) 'VKN ${p.taxNumber}',
      if (p.decidedAt != null) 'son karar ${Fmt.longDate(p.decidedAt)}',
    ].join(', ');
    final hasRisk = p.riskClass != RiskClass.none && !p.riskClass.isUnknown;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Nesne başlığı (§6.1) kök başlık gibi en çok 1,5× büyür.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.5,
            child: Semantics(
              header: true,
              child: Text(p.customerTitle, style: t.display),
            ),
          ),
          if (line.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(line, style: t.body.copyWith(color: c.dim)),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 20,
            runSpacing: 6,
            children: [
              AknLamp.style(financeProfileLamp(p.status)),
              if (hasRisk) AknLamp.style(riskLamp(p.riskClass)),
              if (p.isGrandfathered)
                const AknLamp(label: 'Eski cari', tone: AknTone.neutral),
            ],
          ),
        ],
      ),
    );
  }
}

/// Kartın plakası (§5.2, §7.13): kullanılabilir limit, kullanım ölçeri (%80 uyarı çizgisi), kural,
/// Limit / Kullanılan / Kullanım. Limit dolduysa ya da %80'i geçtiyse siyah "!" ve kalın söz.
class _LimitPlate extends StatelessWidget {
  const _LimitPlate({required this.usage});

  final LimitUsage usage;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final u = usage;
    final liters = u.isLiters;
    final unit = liters ? 'L' : '₺';
    final limit = u.limitAmount ?? 0;
    final available = u.available ?? (limit - u.used);
    final ratio = u.ratio ?? 0;
    String amount(double v) => liters ? Fmt.liters(v) : Fmt.moneyWhole(v);
    final percent = Fmt.percent(ratio * 100, maxFraction: 0);
    final String? problem = available <= 0
        ? (available < 0 ? 'Limit ${amount(-available)} aşıldı' : 'Limit doldu')
        : ratio >= 0.8
        ? 'Limitin $percent kullanıldı'
        : null;
    final period = u.limitPeriod == null
        ? null
        : TurkishText.lower(u.limitPeriod!);
    return AknPlate(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      semanticLabel:
          'Kullanılabilir limit ${amount(math.max(0, available))}${problem == null ? '' : ', $problem'}',
      head: PlateHead(
        icon: PhosphorIconsFill.gauge,
        title: 'Kullanılabilir limit',
        period: period,
      ),
      figure: PlateFigure(
        value: Fmt.integer(math.max(0, available).round()),
        unit: unit,
        semanticLabel: amount(math.max(0, available)),
      ),
      delta: problem == null
          ? null
          : Row(
              children: [
                const PlateBang(),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    problem,
                    style: t.bodySmall.copyWith(
                      color: c.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
      chart: PlateMeter(
        value: ratio.clamp(0.0, 1.0),
        threshold: 0.8,
        semanticLabel: 'Limit kullanımı',
        semanticValue: '$percent, uyarı sınırı %80',
      ),
      below: _readouts(context, [
        PlateReadout(label: 'Limit', value: Fmt.integer(limit), unit: unit),
        PlateReadout(
          label: 'Kullanılan',
          value: Fmt.integer(u.used.round()),
          unit: unit,
        ),
        PlateReadout(label: 'Kullanım', value: percent),
      ]),
    );
  }
}

/// Plakanın göstergeleri: normal yazıda sütunlar; büyük yazıda etiket / değer satırları (uzun tutar
/// etiketin altına iner, sütuna sığmaz).
Widget _readouts(BuildContext context, List<PlateReadout> items) {
  if (!isLargeText(context)) return PlateReadouts(items: items);
  return FactList(
    facts: [
      for (final r in items)
        FactRow(
          label: r.label,
          value: r.unit == null ? r.value : '${r.value} ${r.unit}',
        ),
    ],
  );
}

/// Teminat satırı (kart içinde): tür, sağda tutar (tablo rakamları); ikinci satırda banka, geçerlilik
/// ve not; durum çipi.
class _CollateralRow extends StatelessWidget {
  const _CollateralRow({required this.c});

  final Collateral c;

  @override
  Widget build(BuildContext context) {
    final tone = switch (c.status) {
      CollateralStatus.active => AknTone.ok,
      CollateralStatus.expired => AknTone.warn,
      _ => AknTone.neutral,
    };
    final second = [
      ?c.bankName,
      if (c.validUntil != null) 'geçerlilik ${Fmt.longDate(c.validUntil)}',
      ?c.note,
    ].join(', ');
    return AknListTile(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      title: c.kind.label,
      subtitle: second.isEmpty ? null : second,
      amount: Fmt.moneyWhole(c.amount),
      status: AknStatusLine(
        lamp: AknLamp(label: c.status.label, tone: tone),
      ),
      semanticLabel: [
        c.kind.label,
        Fmt.money(c.amount),
        if (second.isNotEmpty) second,
        c.status.label,
      ].join(', '),
    );
  }
}

/// Risk raporu (kutusuz): sağlayıcı ve zaman, önerilen risk sınıfı, olgular, banka satırları ve PDF.
class _RiskReport extends StatelessWidget {
  const _RiskReport({required this.report});

  final RiskReport report;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final r = report;
    if (!r.success) {
      return AknBanner(
        tone: AknTone.warn,
        title: 'Rapor alınamadı (${Fmt.date(r.requestedAt)})',
        message:
            r.errorMessage ??
            'Sağlayıcı yanıt vermedi. Raporu web portalından yeniden isteyin.',
      );
    }
    final bounced = r.bouncedChequeCount ?? 0;
    final protested = r.protestedNoteCount ?? 0;
    final overdue = r.overdueAmount ?? 0;
    final suggested =
        r.suggestedRiskClass != RiskClass.none &&
        !r.suggestedRiskClass.isUnknown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(r.provider, style: t.headline),
        const SizedBox(height: 2),
        Text(
          Fmt.dateTime(r.requestedAt),
          style: t.bodySmall.copyWith(color: c.dim),
        ),
        if (suggested) ...[
          const SizedBox(height: 8),
          AknLamp.style(
            riskLamp(
              r.suggestedRiskClass,
            ).withLabel('Önerilen ${riskShort(r.suggestedRiskClass)}'),
          ),
        ],
        if (r.isMock) ...[
          const SizedBox(height: 10),
          const AknBanner(
            message: 'Deneme raporu: örnek veridir, karta yazılmaz.',
          ),
        ],
        const SizedBox(height: 6),
        FactList(
          facts: [
            if (r.score != null) FactRow(label: 'Skor', value: '${r.score}'),
            FactRow(
              label: 'Toplam banka limiti',
              value: Fmt.moneyWhole(r.totalBankLimit),
            ),
            FactRow(
              label: 'Toplam banka riski',
              value: Fmt.moneyWhole(r.totalBankRisk),
            ),
            FactRow(
              label: 'Gecikme',
              value: overdue > 0 ? Fmt.moneyWhole(overdue) : 'Yok',
              tone: overdue > 0 ? AknTone.danger : null,
            ),
            FactRow(
              label: 'Karşılıksız çek',
              value: bounced > 0 ? '$bounced adet' : 'Yok',
              tone: bounced > 0 ? AknTone.danger : null,
            ),
            FactRow(
              label: 'Protestolu senet',
              value: protested > 0 ? '$protested adet' : 'Yok',
              tone: protested > 0 ? AknTone.danger : null,
            ),
          ],
        ),
        if (r.lines.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Bankalar, risk / limit', style: t.label),
          const SizedBox(height: 2),
          FactList(
            facts: [
              for (final l in r.lines)
                FactRow(
                  label: l.bankName,
                  value:
                      '${Fmt.moneyCompact(l.risk)} / ${Fmt.moneyCompact(l.limit)}',
                ),
            ],
          ),
        ],
        if (r.pdfAttachmentPublicId != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: AknButton.ghost(
              label: 'Rapor PDF\'ini aç',
              icon: PhosphorIconsRegular.filePdf,
              size: AknButtonSize.small,
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
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) => Shimmer(
    child: ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: const [
        SkeletonBox(height: 30, width: 260, radius: 6),
        SizedBox(height: 10),
        SkeletonBox(height: 14, width: 200),
        SizedBox(height: 18),
        SkeletonBox(height: 14, width: 140),
        SizedBox(height: 16),
        SkeletonBox(height: 220, radius: 20),
        SizedBox(height: 28),
        SkeletonBox(height: 20, width: 170),
        SizedBox(height: 16),
        SkeletonLine(),
        SizedBox(height: 14),
        SkeletonLine(widthFactor: 0.8),
        SizedBox(height: 14),
        SkeletonLine(widthFactor: 0.6),
      ],
    ),
  );
}
