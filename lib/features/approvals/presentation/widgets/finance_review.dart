import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/env/app_config_controller.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/routing/app_location.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/routing/route_access.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../copy.dart';
import '../../data/approval_models.dart';
import 'info_cards.dart';
import 'summary_sections.dart';

/// Sipariş finansının (tür 4) bayi / merkez incelemesi (tasarım v4 "Sade"; panelin
/// `_DetailOrderFinance` + `_CustomerSnapshot` bölümleri): karar için gereken olgular düz bir "Özet"
/// listesine gömülmez, kararın sırasıyla bölümlere ayrılır.
///
/// * **Finans incelemesi**: gerekçeler (limit aşımı kırmızı, vadeli yöntem amber, kural gereği
///   olanlar nötr; yalnızca genel kural varsa "Başka bir finans gerekçesi yok"), ödeme (yöntem,
///   vade, son ödeme, belge; vade kartın en uzun vadesini aşıyorsa uyarı) ve bu siparişle limit
///   (durum renkli küçük ölçer, kalan önce → sonra, aşım).
/// * **Cari finans durumu**: kart, risk ve son rapor, gecikmiş, açık bakiye, teminat, izinli
///   yöntemler, gözden geçirme; karşılıksız çek / protestolu senet işaretleri. Başlıkta "Finans kartı".
/// * **Geçmiş**: önceki siparişler, son sipariş, finans onayındaki diğerleri, geciken tahsilat,
///   karşılıksız ödemeler (sunucu veriyorsa).
/// * **Aynı ödemedeki siparişler** (ödeme grubu) ve **Sipariş** (siparişin kendi satırları).
///
/// Eski sunucu (`summary.finance` yok): aynı bölümler özet satırlarından (anahtar ya da etiketle)
/// kurulur; kart satırları sunucunun biçimiyle olduğu gibi gösterilir.
class FinanceReviewSections extends ConsumerWidget {
  const FinanceReviewSections({
    super.key,
    required this.detail,
    required this.review,
    this.onDocumentUploaded,
  });

  final ApprovalDetail detail;
  final OrderFinanceReview review;

  /// Onaylayan eksik ödeme belgesini ekledi (G8): sayfa yenilenir.
  final VoidCallback? onDocumentUploaded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = detail;
    final r = review;
    final groups = FinanceFactGroups.of(d.summary.facts);
    final policy = ref.watch(accessPolicyProvider);
    final features = ref.watch(appConfigProvider).features;
    final cardId = d.summary.links.stationCustomerId;
    final cardRoute = cardId == null ? null : AppRoutes.financeCustomer(cardId);
    final canOpenCard =
        cardRoute != null && RouteAccess.isAllowed(cardRoute, policy, features);
    final cardRows = _cardRows(r, groups);
    final historyRows = _historyRows(r.history);
    final orderFacts = [...groups.order, ...groups.rest];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailSection(
          title: ApprovalsCopy.financeReviewTitle,
          child: AknCard(
            key: const ValueKey('finance-review'),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReasonsBlock(review: r),
                const _BlockDivider(),
                _PaymentBlock(
                  review: r,
                  details: groups.paymentDetails,
                  // Karar verebilen, başka yoldan gelen zorunlu belgeyi talebe ekleyebilir (G8); ek
                  // bilgi beklenirken bu iş "Bilgi alındı" sayfasında.
                  upload:
                      d.status == ApprovalStatus.pending &&
                          d.modes.isNotEmpty &&
                          r.payment.documentMissing &&
                          r.payment.documentKind != null
                      ? ApproverUploadBox(
                          approvalId: d.id,
                          kind: r.payment.documentKind!,
                          onUploaded: onDocumentUploaded,
                        )
                      : null,
                ),
                const _BlockDivider(),
                _LimitBlock(review: r),
              ],
            ),
          ),
        ),
        if (cardRows.isNotEmpty)
          DetailSection(
            title: ApprovalsCopy.financeCardTitle,
            actionLabel: canOpenCard ? ApprovalsCopy.financeCardOpen : null,
            onAction: canOpenCard
                ? () => context.openAppLocation(cardRoute)
                : null,
            child: AknCard(
              key: const ValueKey('finance-card'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cardRows,
              ),
            ),
          ),
        if (historyRows.isNotEmpty)
          DetailSection(
            title: ApprovalsCopy.financeHistoryTitle,
            child: AknCard(
              key: const ValueKey('finance-history'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _divided(historyRows),
              ),
            ),
          ),
        if (r.paymentGroup.isNotEmpty)
          DetailSection(
            title: ApprovalsCopy.paymentGroupTitle,
            subtitle: ApprovalsCopy.paymentGroupSubtitle,
            bleed: true,
            child: AknLedger(
              children: [
                for (final g in r.paymentGroup)
                  _GroupLineTile(line: g, approvalId: d.id),
              ],
            ),
          ),
        if (orderFacts.isNotEmpty)
          DetailSection(
            title: ApprovalsCopy.orderFactsTitle,
            child: FactsCard(facts: orderFacts),
          ),
      ],
    );
  }

  /// Kart satırları: yapılandırılmış kart varsa ondan (+ işaretler), yoksa sunucunun kart satırları.
  static List<Widget> _cardRows(
    OrderFinanceReview r,
    FinanceFactGroups groups,
  ) {
    final card = r.card;
    if (card == null) {
      return _divided([
        for (final f in groups.card)
          FactRow(
            label: f.label,
            value: f.value.replaceAll(' · ', ', '),
            tone: FinanceTones.of(f.tone),
          ),
      ]);
    }
    final risk = r.riskReport;
    final rows = <Widget>[
      FactRow(
        label: 'Kart durumu',
        value: card.isGrandfathered && !card.hasCard
            ? '${card.displayStatusLabel} (eski cari)'
            : card.displayStatusLabel,
        tone: FinanceTones.profile(card.status),
      ),
      if (card.riskShort != null)
        FactRow(
          label: 'Risk sınıfı',
          value: card.riskShort!,
          tone: card.riskClass.isHighRisk ? AknTone.warn : null,
        ),
      FactRow(
        label: 'Son risk raporu',
        value: ApprovalsCopy.riskReportLine(risk),
        tone: risk == null || !risk.success
            ? (risk == null ? null : AknTone.warn)
            : (risk.riskClass.isHighRisk ? AknTone.warn : null),
      ),
      FactRow(
        label: 'Gecikmiş',
        value: (card.overdueAmount ?? 0) > 0
            ? Fmt.moneyWhole(card.overdueAmount)
            : ApprovalsCopy.none,
        tone: (card.overdueAmount ?? 0) > 0 ? AknTone.danger : null,
      ),
      if (card.openBalance != null)
        FactRow(label: 'Açık bakiye', value: Fmt.moneyWhole(card.openBalance)),
      if (card.approvedLimitAmount != null)
        FactRow(
          label: 'Onaylanan limit',
          value: Fmt.moneyWhole(card.approvedLimitAmount),
        ),
      FactRow(label: 'Teminat', value: ApprovalsCopy.collateralLine(card)),
      FactRow(
        label: 'İzinli yöntemler',
        value: card.allowedMethodCodes.isEmpty
            ? 'Bayide açık tümü'
            : card.allowedMethodCodes.map(ApprovalsCopy.methodName).join(', '),
      ),
      FactRow(
        label: 'En uzun vade',
        value: card.maxTermDays == null
            ? 'Sınır yok'
            : '${card.maxTermDays} gün',
        tone: r.termExceedsCard ? AknTone.warn : null,
      ),
      if (card.nextReviewDate != null)
        FactRow(
          label: 'Gözden geçirme',
          value: card.reviewOverdue
              ? '${Fmt.date(card.nextReviewDate)}, tarihi geçti'
              : Fmt.date(card.nextReviewDate),
          tone: card.reviewOverdue ? AknTone.danger : null,
        ),
    ];
    final flags = <Widget>[
      if (!card.canOrder)
        AknLamp(
          label: card.blockReason ?? 'Sipariş veremez',
          tone: AknTone.danger,
        ),
      if (card.hasBouncedCheque)
        const AknLamp(label: 'Karşılıksız çek kaydı var', tone: AknTone.danger),
      if (card.hasProtestedNote)
        const AknLamp(
          label: 'Protestolu senet kaydı var',
          tone: AknTone.danger,
        ),
      if (card.isStrategicPricing)
        const AknLamp(label: 'Stratejik müşteri', tone: AknTone.neutral),
    ];
    return [
      if (flags.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Wrap(spacing: 8, runSpacing: 8, children: flags),
        ),
      ..._divided(rows),
    ];
  }

  static List<Widget> _historyRows(OrderFinanceHistory? h) {
    if (h == null) return const [];
    if (h.isFirstOrder) {
      return const [
        FactRow(
          label: 'Önceki siparişler',
          value: ApprovalsCopy.firstOrder,
          tone: AknTone.info,
        ),
      ];
    }
    return [
      FactRow(
        label: 'Önceki siparişler',
        value: ApprovalsCopy.orderCountLine(h.orderCount, h.completedCount),
      ),
      if (h.lastOrderAt != null || h.lastOrderNumber != null)
        FactRow(
          label: 'Son sipariş',
          value: [
            if (h.lastOrderAt != null) Fmt.dayMonth(h.lastOrderAt),
            ?h.lastOrderNumber,
          ].join(', '),
        ),
      if (h.openFinanceCount > 0)
        FactRow(
          label: 'Finans onayında',
          value: '${h.openFinanceCount} sipariş daha',
          tone: AknTone.info,
        ),
      FactRow(
        label: 'Geciken tahsilat',
        value: h.overdueCount == 0
            ? ApprovalsCopy.none
            : ApprovalsCopy.overdueCollectionsLine(h),
        tone: h.overdueCount == 0 ? null : AknTone.danger,
      ),
      if (h.bouncedCount > 0)
        FactRow(
          label: 'Karşılıksız ödeme',
          value: '${h.bouncedCount} sipariş',
          tone: AknTone.danger,
        ),
      if (h.financeRejectedCount > 0)
        FactRow(
          label: 'Finansın reddettiği',
          value: '${h.financeRejectedCount} sipariş',
        ),
    ];
  }
}

/// Satırlar arasına içeriden ince çizgi.
List<Widget> _divided(List<Widget> rows) => [
  for (var i = 0; i < rows.length; i++) ...[
    if (i > 0) const AknLedgerDivider(indent: 0),
    rows[i],
  ],
];

/// Kartın içindeki bloklar arası çizgi.
class _BlockDivider extends StatelessWidget {
  const _BlockDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 10),
    child: AknLedgerDivider(indent: 0),
  );
}

/// Bloğun küçük başlığı (12/16 700 soluk; ekran okuyucuda başlık).
class _BlockCaption extends StatelessWidget {
  const _BlockCaption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: t.label.copyWith(fontWeight: FontWeight.w700, color: c.dim),
        ),
      ),
    );
  }
}

/// Gerekçeler: tonlu hap lambalar (renk tek başına söylemez, söz de vardır). Yalnızca genel kural
/// varsa "Başka bir finans gerekçesi yok".
class _ReasonsBlock extends StatelessWidget {
  const _ReasonsBlock({required this.review});

  final OrderFinanceReview review;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final reasons = review.reasons;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _BlockCaption(ApprovalsCopy.reasonsCaption),
        if (reasons.isEmpty)
          Text(
            ApprovalsCopy.noReasons,
            style: t.bodySmall.copyWith(color: c.dim),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in reasons)
                AknLamp(
                  key: ValueKey('finance-reason-${r.kind.code}'),
                  label: r.text,
                  tone: FinanceTones.reason(r),
                ),
            ],
          ),
        if (review.isRoutine) ...[
          const SizedBox(height: 6),
          Text(
            ApprovalsCopy.routineReason,
            style: t.bodySmall.copyWith(color: c.dim),
          ),
        ],
      ],
    );
  }
}

/// Ödeme: yöntem ve vade, son ödeme, durum, belge; kartla çelişki uyarıları; ödeme ayrıntıları.
class _PaymentBlock extends StatelessWidget {
  const _PaymentBlock({
    required this.review,
    required this.details,
    this.upload,
  });

  final OrderFinanceReview review;
  final List<SummaryFact> details;

  /// Eksik belgeyi ekleme (karar verebilene).
  final Widget? upload;

  @override
  Widget build(BuildContext context) {
    final p = review.payment;
    final card = review.card;
    final rows = <Widget>[
      FactRow(
        label: 'Yöntem',
        value: p.line != null && p.methodCode == null
            ? p.line!.replaceAll(' · ', ', ')
            : ApprovalsCopy.paymentLine(p),
        tone: p.isDeferred ? AknTone.warn : null,
      ),
      if (p.dueDate != null)
        FactRow(label: 'Son ödeme', value: Fmt.longDate(p.dueDate)),
      if (p.methodCode != null && p.displayStatusLabel != null)
        FactRow(label: 'Ödeme durumu', value: p.displayStatusLabel!),
      if (p.documentLabel != null && (p.documentRequired || p.documentMissing))
        FactRow(
          label: 'Belge',
          value: p.documentMissing
              ? '${p.documentLabel} eklenmedi'
              : '${p.documentLabel} var',
          tone: p.documentMissing ? AknTone.danger : AknTone.ok,
        ),
      for (final f in details)
        FactRow(label: f.label, value: f.value.replaceAll(' · ', ', ')),
    ];
    final warnings = <String>[
      if (review.termExceedsCard && card?.maxTermDays != null)
        ApprovalsCopy.termExceedsCard(card!.maxTermDays!),
      if (review.methodNotAllowed) ApprovalsCopy.methodNotAllowed,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BlockCaption(ApprovalsCopy.paymentCaption),
        ..._divided(rows),
        for (final w in warnings)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: AknLamp(label: w, tone: AknTone.warn),
            ),
          ),
        if (upload != null) ...[const SizedBox(height: 8), upload!],
      ],
    );
  }
}

/// Limit: bu siparişle kullanım (durum renkli ölçer: yeşil, %80 sonrası amber, %100 sonrası
/// kırmızı), limit, diğer siparişler, bu sipariş, kalan önce → sonra, aşım; teklifi bekleyen diğer
/// siparişler. Eski sunucuda kullanım bu siparişi içermeyebilir: "Kullanım".
class _LimitBlock extends StatelessWidget {
  const _LimitBlock({required this.review});

  final OrderFinanceReview review;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final l = review.limit;
    final children = <Widget>[const _BlockCaption(ApprovalsCopy.limitCaption)];
    if (l == null) {
      children.add(
        Text(
          ApprovalsCopy.limitUnknown,
          style: t.bodySmall.copyWith(color: c.dim),
        ),
      );
    } else if (l.invalidReason != null) {
      children.add(
        FactRow(label: 'Limit', value: l.invalidReason!, tone: AknTone.warn),
      );
    } else if (!l.hasLimit) {
      children.add(const FactRow(label: 'Limit', value: ApprovalsCopy.noLimit));
    } else {
      String amount(double? v) => v == null
          ? Fmt.dash
          : (l.isLiters ? Fmt.liters(v.round()) : Fmt.moneyWhole(v));
      final ratio = l.ratio ?? 0;
      final percent = Fmt.percent(ratio * 100, maxFraction: 0);
      final period = l.period == null || l.period == 'Limitsiz'
          ? null
          : ApprovalsCopy.periodLower(l.period!);
      final estimate = review.amountIsEstimate && !l.isLiters;
      final meter = l.ratio == null
          ? null
          : UsageBar(
              key: const ValueKey('finance-limit-meter'),
              value: ratio,
              label: l.includesThisOrder
                  ? ApprovalsCopy.usageAfter
                  : ApprovalsCopy.usageNow,
              valueLabel: percent,
              height: 8,
            );
      // Eski sunucunun tutarsız satırı ("%92 → %131"): ölçer ve sunucunun sözü (ok işareti sözle);
      // tutar satırı yok.
      if (l.limitAmount == null) {
        children.addAll([
          ?meter,
          if (l.text != null) ...[
            if (meter != null) const SizedBox(height: 6),
            FactRow(
              label: ApprovalsCopy.usageNow,
              value: ApprovalsCopy.usageText(l.text!),
              tone: l.wouldExceed ? AknTone.danger : null,
            ),
          ],
        ]);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      }
      children.addAll([
        ?meter,
        const SizedBox(height: 6),
        ..._divided([
          FactRow(
            label: 'Limit',
            value: [amount(l.limitAmount), ?period].join(', '),
          ),
          FactRow(
            label: l.includesThisOrder ? 'Diğer siparişler' : 'Kullanılan',
            value: amount(l.usedByOthers),
          ),
          if (l.includesThisOrder)
            FactRow(
              label: 'Bu sipariş',
              value: estimate
                  ? '≈ ${amount(l.thisOrder)}'
                  : amount(l.thisOrder),
            ),
          FactRow(
            label: 'Kalan',
            value: amount(l.available),
            tone: !l.includesThisOrder && (l.available ?? 1) <= 0
                ? AknTone.warn
                : null,
          ),
          if (l.includesThisOrder && l.availableAfter != null)
            FactRow(
              label: 'Sipariş sonrası kalan',
              value: amount(l.availableAfter),
              tone: l.availableAfter! <= 0 ? AknTone.warn : null,
            ),
          if (l.wouldExceed && l.overrunAmount > 0)
            FactRow(
              label: 'Aşım',
              value: amount(l.overrunAmount),
              tone: AknTone.danger,
            ),
        ]),
        if (l.unpricedOthers > 0) ...[
          const SizedBox(height: 4),
          Text(
            ApprovalsCopy.unpricedOthers(Fmt.moneyWhole(l.unpricedOthers)),
            style: t.caption.copyWith(color: c.dim),
          ),
        ],
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Ödeme grubundaki diğer sipariş: ürün ve litre, numara ve finans durumu, tutar; dokununca kendi
/// onay talebi (yoksa sipariş). Kullanıcının açamadığı konum dokunulmaz (satır yine okunur).
class _GroupLineTile extends ConsumerWidget {
  const _GroupLineTile({required this.line, required this.approvalId});

  final OrderFinanceGroupLine line;
  final int approvalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = line;
    final route =
        g.approvalRequestId != null && g.approvalRequestId != approvalId
        ? AppRoutes.approval(g.approvalRequestId!)
        : AppRoutes.bayiOrder(g.orderId);
    final open = RouteAccess.isAllowed(
      route,
      ref.watch(accessPolicyProvider),
      ref.watch(appConfigProvider).features,
    );
    final title = [
      ?g.productName,
      if (g.quantityLiters > 0) Fmt.liters(g.quantityLiters),
    ].join(' ');
    return AknListTile(
      leadingIcon: PhosphorIconsRegular.receipt,
      title: title.isEmpty ? g.orderNumber : title,
      subtitle: [
        if (title.isNotEmpty) g.orderNumber,
        g.displayFinanceLabel,
      ].join(' · '),
      amount: g.amount == null ? null : Fmt.moneyWhole(g.amount),
      showChevron: open,
      onTap: open ? () => context.openAppLocation(route) : null,
    );
  }
}

/// Sipariş finansının özet satırları, bölüme göre (anahtar; anahtarsız eski sunucuda etiket).
@immutable
class FinanceFactGroups {
  const FinanceFactGroups({
    this.order = const [],
    this.paymentLine,
    this.paymentDetails = const [],
    this.finance = const [],
    this.card = const [],
    this.rest = const [],
  });

  factory FinanceFactGroups.of(List<SummaryFact> facts) {
    final order = <SummaryFact>[];
    final details = <SummaryFact>[];
    final finance = <SummaryFact>[];
    final card = <SummaryFact>[];
    final rest = <SummaryFact>[];
    SummaryFact? payment;
    for (final f in facts) {
      final key = f.key;
      if (key != null) {
        if (key == FactKeys.paymentLine) {
          payment ??= f;
        } else if (key == FactKeys.paymentDetail) {
          details.add(f);
        } else if (key.startsWith('order.')) {
          order.add(f);
        } else if (key.startsWith('finance.')) {
          finance.add(f);
        } else if (key.startsWith('card.')) {
          // Limit kullanımı limit bloğunda (ölçer); burada tekrarlanmaz.
          if (key != FactKeys.cardLimitUsage) card.add(f);
        } else {
          rest.add(f);
        }
        continue;
      }
      if (_orderLabels.contains(f.label)) {
        order.add(f);
      } else if (f.label == 'Ödeme') {
        payment ??= f;
      } else if (_financeLabels.contains(f.label)) {
        finance.add(f);
      } else if (_cardLabels.contains(f.label)) {
        if (f.label != 'Limit kullanımı') card.add(f);
      } else {
        rest.add(f);
      }
    }
    return FinanceFactGroups(
      order: List.unmodifiable(order),
      paymentLine: payment,
      paymentDetails: List.unmodifiable(details),
      finance: List.unmodifiable(finance),
      card: List.unmodifiable(card),
      rest: List.unmodifiable(rest),
    );
  }

  static const _orderLabels = {
    'Sipariş no',
    'Bayi',
    'Cari',
    'Ürün',
    'Miktar',
    'Teslim',
    'Teslimat noktası',
    'Teklif tutarı',
    'Tahmini tutar',
  };

  static const _financeLabels = {
    'Finans durumu',
    'Gerekçe',
    'Finans gerekçesi',
  };

  static const _cardLabels = {
    'Cari finans durumu',
    'Finans kartı',
    'Risk sınıfı',
    'Limit kullanımı',
    'Onaylanan limit',
    'Teminat oranı',
    'Gecikmiş',
    'Gecikmiş bakiye',
    'İzinli yöntemler',
    'En uzun vade',
    'Gözden geçirme',
    'Geçerli teminat',
    'Fiyatlama',
    'Son risk raporu',
  };

  final List<SummaryFact> order;
  final SummaryFact? paymentLine;
  final List<SummaryFact> paymentDetails;
  final List<SummaryFact> finance;
  final List<SummaryFact> card;
  final List<SummaryFact> rest;

  /// Kartın "Gecikmiş" satırı (eski sunucuda "Gecikmiş bakiye" de olabilir).
  SummaryFact? get overdue {
    for (final f in card) {
      if (f.key == FactKeys.cardOverdue ||
          f.label == 'Gecikmiş' ||
          f.label == 'Gecikmiş bakiye') {
        return f;
      }
    }
    return null;
  }
}

/// Finans incelemesinin tonları (v4: turuncu yalnızca eylem; durum renkleri yalnızca durum).
abstract final class FinanceTones {
  /// Sunucu tonu → satır tonu (nötr ve bilgi mürekkeptir).
  static AknTone? of(String? key) {
    final t = AknStatus.toneFromKey(key);
    return t == AknTone.neutral || t == AknTone.info || t == AknTone.brand
        ? null
        : t;
  }

  /// Gerekçe lambası: limit aşımı kırmızı, vadeli yöntem amber, diğerleri nötr.
  static AknTone reason(FinanceReason r) => switch (r.kind) {
    FinanceReasonKind.limitOverrun => AknTone.danger,
    FinanceReasonKind.paymentMethod => AknTone.warn,
    _ => switch (AknStatus.toneFromKey(r.tone)) {
      AknTone.danger => AknTone.danger,
      AknTone.warn => AknTone.warn,
      _ => AknTone.neutral,
    },
  };

  static AknTone? profile(FinanceProfileStatus s) => switch (s) {
    FinanceProfileStatus.approved => AknTone.ok,
    FinanceProfileStatus.pending ||
    FinanceProfileStatus.infoRequested => AknTone.warn,
    FinanceProfileStatus.rejected ||
    FinanceProfileStatus.suspended => AknTone.danger,
    _ => null,
  };
}

/// Plakanın okumaları (sipariş finansı): ödeme (yöntem + vade ya da peşin), bu siparişle limit
/// kullanımı ve gecikmiş — kararın üç sayısı ilk ekranda. Miktar başlığın alt satırında zaten
/// yazılıdır.
List<({String label, String value, String? unit})> financePlateReadouts(
  ApprovalDetail d,
  OrderFinanceReview r,
) {
  final out = <({String label, String value, String? unit})>[];
  final p = r.payment;
  final method = p.methodName.trim();
  if (method.isNotEmpty && method != 'Belirtilmemiş') {
    final term = p.termDays ?? 0;
    out.add(
      term > 0
          ? (label: method, value: '$term', unit: 'gün')
          : (label: method, value: ApprovalsCopy.cashShort, unit: null),
    );
  }
  final l = r.limit;
  final ratio = l?.ratio;
  if (l != null && l.hasLimit && ratio != null) {
    out.add((
      label: l.includesThisOrder ? 'Limit' : 'Kullanım',
      value: Fmt.percent(ratio * 100, maxFraction: 0),
      unit: null,
    ));
  }
  double? overdue = r.card?.overdueAmount;
  if (r.card == null) {
    final f = FinanceFactGroups.of(d.summary.facts).overdue;
    if (f != null) overdue = _moneyOf(f.value) ?? 0;
  }
  if (overdue != null) {
    out.add(
      overdue > 0
          ? (label: 'Gecikmiş', value: Fmt.number(overdue.round()), unit: '₺')
          : (label: 'Gecikmiş', value: ApprovalsCopy.none, unit: null),
    );
  }
  return out.take(3).toList();
}

/// "120.000,00 ₺" → 120000 (biçimsizse null; "—" ya da "Yok" 0).
double? _moneyOf(String text) {
  final t = text.trim();
  if (t.isEmpty || t == Fmt.dash || t == 'Yok') return 0;
  final m = RegExp(r'^([\d.]+(?:,\d+)?)').firstMatch(t);
  if (m == null) return null;
  return double.tryParse(m[1]!.replaceAll('.', '').replaceAll(',', '.'));
}

/// Kart bölümünde işaret olarak gösterilen sunucu uyarıları (yapılandırılmış kart varken bant olarak
/// tekrarlanmaz) ve karar verildikten sonra anlamını yitiren çağrı ("onaydan önce … Ek bilgi iste").
List<String> financeWarnings(ApprovalDetail d, OrderFinanceReview? r) {
  final card = r?.card;
  return [
    for (final w in d.summary.warnings)
      if (!(card != null &&
              (_cardWarnings.contains(w.trim()) ||
                  w.trim() == card.blockReason)) &&
          !(!d.isOpen && w.contains('"Ek bilgi iste"')))
        w,
  ];
}

const _cardWarnings = {
  'Finans kartının gözden geçirme tarihi geçti.',
  'Karşılıksız çek kaydı var.',
  'Protestolu senet kaydı var.',
};

/// "Siparişi aç" (tasarım v4: sipariş finansında tek dokunuş, plakanın hemen altında).
class OrderLinkRow extends ConsumerWidget {
  const OrderLinkRow({super.key, required this.detail});

  final ApprovalDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = detail.summary.links.orderId;
    if (id == null) return const SizedBox.shrink();
    final policy = ref.watch(accessPolicyProvider);
    final features = ref.watch(appConfigProvider).features;
    final route = policy.isCustomer
        ? AppRoutes.order(id)
        : AppRoutes.bayiOrder(id);
    if (!RouteAccess.isAllowed(route, policy, features)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AknLedger(
        children: [
          AknListTile(
            key: const ValueKey('approval-open-order'),
            leadingIcon: PhosphorIconsRegular.receipt,
            title: ApprovalsCopy.openOrder,
            subtitle: detail.row.subjectNumber,
            showChevron: true,
            dense: true,
            onTap: () => context.openAppLocation(route),
          ),
        ],
      ),
    );
  }
}
