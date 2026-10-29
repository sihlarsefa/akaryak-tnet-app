import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../../approvals/api.dart';
import '../application/finance_providers.dart';
import '../copy.dart';
import '../data/finance_models.dart';
import '../data/finance_repository.dart';

/// Yüklenen satırların sıralaması (Filtre sayfası; sunucu ada göre verir).
enum FinanceSort {
  name('Ada göre'),
  usage('Kullanıma göre'),
  limit('Limite göre');

  const FinanceSort(this.label);
  final String label;
}

/// Finans (tasarım v4 "Sade" §5 09).
///
/// * Bant: "Finans" ve canlı durum satırı ("1 cari finans onayınızı bekliyor"); ⌕ (bandın altında
///   açılan arama şeridi; VKN de aranır) ve Filtre (risk A–D, gözden geçirme, sıralama).
/// * Tek seçici: [Tümü | Bekleyen n | Onaylı | Kapalı] (AknSegmented).
/// * Gruplar: "Dikkat n" (istisnalar: finans onayı, gecikme / karşılıksız çek, gözden geçirme,
///   Risk D) önce, ardından "Tüm cariler n" (istisna yoksa) ya da "Diğer cariler n" — bir cari
///   ekranda bir kez (P4).
/// * Satırlar defterde ([FinanceRowCard]): ad + limit, 6 dp kullanım çubuğu + "%47", yalnızca
///   istisnada üçüncü satır. "Onaylı" hapı, VKN satırı, risk çipleri ve arama kuyusu yok.
/// * Diğer'den itilince de aynı görünür; `?filter=pending|review` süzgeçle açar.
class FinanceCustomersPage extends ConsumerStatefulWidget {
  const FinanceCustomersPage({super.key, this.initialFilter});

  /// Derin bağlantı: `/finance?filter=pending` (bekleyen), `review` (gözden geçirmesi geçen).
  final String? initialFilter;

  /// `filter` sorgu değerinden ilk süzgeç.
  static FinanceQuery queryFor(String? raw) =>
      switch (TurkishText.searchKey(raw ?? '')) {
        'pending' ||
        'bekleyen' => const FinanceQuery(status: FinanceStatusFilter.pending),
        'approved' ||
        'onayli' => const FinanceQuery(status: FinanceStatusFilter.approved),
        'closed' ||
        'kapali' => const FinanceQuery(status: FinanceStatusFilter.closed),
        'review' ||
        'overdue' ||
        'gozden-gecirme' => const FinanceQuery(reviewOverdue: true),
        _ => const FinanceQuery(),
      };

  @override
  ConsumerState<FinanceCustomersPage> createState() =>
      _FinanceCustomersPageState();
}

class _FinanceCustomersPageState extends ConsumerState<FinanceCustomersPage> {
  late FinanceQuery _query = FinanceCustomersPage.queryFor(
    widget.initialFilter,
  );
  FinanceSort _sort = FinanceSort.name;
  bool _searchOpen = false;

  /// Bekleyen sayısı (seçicideki "Bekleyen n" ve durum satırı): bekleyenler listesinin toplamı.
  static const _pendingQuery = FinanceQuery(
    status: FinanceStatusFilter.pending,
  );

  int get _activeFilters =>
      (_query.risk == null ? 0 : 1) +
      (_query.reviewOverdue ? 1 : 0) +
      (_sort == FinanceSort.name ? 0 : 1);

  List<FinanceListItem> _sorted(List<FinanceListItem> items) {
    if (_sort == FinanceSort.name) return items;
    final out = [...items];
    switch (_sort) {
      case FinanceSort.usage:
        out.sort((a, b) => (b.usage ?? -1).compareTo(a.usage ?? -1));
      case FinanceSort.limit:
        out.sort(
          (a, b) => (b.limitAmount ?? -1).compareTo(a.limitAmount ?? -1),
        );
      case FinanceSort.name:
        break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(financeListProvider(_query));
    final ctrl = ref.read(financeListProvider(_query).notifier);
    final pendingState = ref.watch(financeListProvider(_pendingQuery));
    final pending = pendingState.hasData ? pendingState.totalCount : null;
    final q = _query;
    final today = TrTime.todayStart();

    final leading = bandPageLeading(context);
    // Bant geri / ana sayfa düğmesiyle daralınca durum satırı kısa söylenir (tek satır, kesilmez).
    final narrow =
        leading != null ||
        (ModalRoute.of(context)?.impliesAppBarDismissal ?? false);
    final Object status = (pending ?? 0) > 0
        ? AknStatusClause.yourMove(
            FinanceCopy.pendingStatus(pending!, short: narrow),
          )
        : (pending == null ? '' : FinanceCopy.calmStatus);

    final switcher = isLargeText(context)
        ? FilterChips<FinanceStatusFilter?>(
            options: [
              const FilterOption(value: null, label: FinanceCopy.allStatuses),
              for (final s in FinanceStatusFilter.values)
                FilterOption(
                  value: s,
                  label: s.label,
                  count: s == FinanceStatusFilter.pending ? pending : null,
                ),
            ],
            selected: {q.status},
            allowEmpty: false,
            onChanged: (s) => setState(
              () => _query = _query.copyWith(status: () => s.firstOrNull),
            ),
          )
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: AknSegmented<FinanceStatusFilter?>(
              segments: [
                const FilterOption(value: null, label: FinanceCopy.allStatuses),
                for (final s in FinanceStatusFilter.values)
                  FilterOption(
                    value: s,
                    label: s.label,
                    count:
                        s == FinanceStatusFilter.pending && (pending ?? 0) > 0
                        ? pending
                        : null,
                  ),
              ],
              value: q.status,
              onChanged: (s) =>
                  setState(() => _query = _query.copyWith(status: () => s)),
            ),
          );

    return AppScaffold(
      title: FinanceCopy.title,
      bandIcon: PhosphorIconsRegular.bank,
      // Diğer'den itilince de aynı görünür (v4 §5 09).
      largeTitle: true,
      leading: leading,
      status: status,
      refreshing: state.refreshing,
      actions: [
        AknSearchReveal.button(
          semanticLabel: 'Carilerde ara',
          onPressed: () => setState(() => _searchOpen = true),
        ),
        AknFilterButton(
          count: _activeFilters,
          sheetBuilder: (_) => _FinanceFilters(
            risk: q.risk,
            reviewOverdue: q.reviewOverdue,
            sort: _sort,
            onRisk: (r) =>
                setState(() => _query = _query.copyWith(risk: () => r)),
            onReviewOverdue: (v) =>
                setState(() => _query = _query.copyWith(reviewOverdue: v)),
            onSort: (s) => setState(() => _sort = s),
          ),
        ),
      ],
      body: Column(
        children: [
          AknSearchReveal(
            open: _searchOpen || q.search.isNotEmpty,
            hint: FinanceCopy.searchHint,
            onChanged: (s) =>
                setState(() => _query = _query.copyWith(search: s.trim())),
            onClose: () => setState(() {
              _searchOpen = false;
              _query = _query.copyWith(search: '');
            }),
          ),
          Expanded(
            child: A5PagedListView<FinanceListItem>(
              state: state,
              ledger: true,
              staggerKey: (q, _sort),
              onRefresh: () async {
                ref.invalidate(financeListProvider(_pendingQuery));
                await ctrl.refresh();
              },
              onLoadMore: () => unawaited(ctrl.loadMore()),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              header: [const SizedBox(height: 4), switcher],
              groups: (items) {
                final sorted = _sorted(items);
                final attention = [
                  for (final i in sorted)
                    if (financeNeedsAttention(i, today)) i,
                ];
                final rest = [
                  for (final i in sorted)
                    if (!financeNeedsAttention(i, today)) i,
                ];
                final total = state.totalCount;
                return [
                  A5ListGroup(
                    id: 'attention',
                    title: FinanceCopy.groupAttention,
                    count: attention.length,
                    items: attention,
                  ),
                  A5ListGroup(
                    id: 'rest',
                    title: attention.isEmpty
                        ? FinanceCopy.groupAll
                        : FinanceCopy.groupOthers,
                    count: attention.isEmpty
                        ? total
                        : (total - attention.length).clamp(rest.length, total),
                    items: rest,
                  ),
                ];
              },
              itemBuilder: (context, item, i) => FinanceRowCard(
                item: item,
                onTap: () => context.push(
                  AppRoutes.financeCustomer(item.stationCustomerId),
                ),
              ),
              empty: q.isFiltered
                  ? EmptyState.compact(
                      title: q.search.isEmpty
                          ? FinanceCopy.filteredTitle
                          : "'${q.search}' için sonuç yok",
                      message: FinanceCopy.filteredMessage,
                      illustration: AknIllustration.search,
                      actionLabel: FinanceCopy.clearFilters,
                      onAction: () => setState(() {
                        _query = const FinanceQuery();
                        _searchOpen = false;
                      }),
                    )
                  : const EmptyState(
                      title: FinanceCopy.emptyTitle,
                      message: FinanceCopy.emptyMessage,
                      illustration: AknIllustration.customers,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Filtre sayfası: risk sınıfı (tek seçim), gözden geçirmesi geçenler ve sıralama. Seçim hemen
/// uygulanır.
class _FinanceFilters extends StatefulWidget {
  const _FinanceFilters({
    required this.risk,
    required this.reviewOverdue,
    required this.sort,
    required this.onRisk,
    required this.onReviewOverdue,
    required this.onSort,
  });

  final RiskClass? risk;
  final bool reviewOverdue;
  final FinanceSort sort;
  final ValueChanged<RiskClass?> onRisk;
  final ValueChanged<bool> onReviewOverdue;
  final ValueChanged<FinanceSort> onSort;

  @override
  State<_FinanceFilters> createState() => _FinanceFiltersState();
}

class _FinanceFiltersState extends State<_FinanceFilters> {
  late RiskClass? _risk = widget.risk;
  late bool _review = widget.reviewOverdue;
  late FinanceSort _sort = widget.sort;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    Widget caption(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: t.label.copyWith(fontWeight: FontWeight.w700, color: c.dim),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        caption(FinanceCopy.filterRisk),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in const [
              RiskClass.a,
              RiskClass.b,
              RiskClass.c,
              RiskClass.d,
            ])
              AknChip(
                label: riskShort(r),
                selected: _risk == r,
                onTap: () {
                  final next = _risk == r ? null : r;
                  setState(() => _risk = next);
                  widget.onRisk(next);
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        caption(FinanceCopy.filterReview),
        Wrap(
          children: [
            AknChip(
              label: FinanceCopy.reviewOverdue,
              selected: _review,
              onTap: () {
                setState(() => _review = !_review);
                widget.onReviewOverdue(_review);
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        caption(FinanceCopy.filterSort),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in FinanceSort.values)
              AknChip(
                label: s.label,
                selected: _sort == s,
                onTap: () {
                  if (_sort == s) return;
                  setState(() => _sort = s);
                  widget.onSort(s);
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Kart durumunun lambası. Finans onayı bekleyen kart finans ekibinin sırasıdır (Pas).
StatusStyle financeProfileLamp(FinanceProfileStatus s) {
  final base = AknStatus.financeProfile(s);
  return s == FinanceProfileStatus.pending
      ? base.copyWith(tone: AknTone.brand)
      : base;
}

/// "Risk A" (etiketin harfi).
String riskShort(RiskClass r) => 'Risk ${r.label.split(' ').first}';

/// Risk sınıfının lambası: A iyi, B süreçte, C uyarı, D tehlike (her zaman "Risk X" sözüyle).
StatusStyle riskLamp(RiskClass r) => AknStatus.risk(r).withLabel(riskShort(r));

/// Gözden geçirmeye bu kadar gün kala satırda uyarı (v4 §5 09: 30 gün).
const _reviewSoonDays = 30;

/// Satırın istisnaları (v4 §5 09 L3): finans onayı bekliyor (Pas), gecikme / karşılıksız çek /
/// protestolu senet (tehlike), gözden geçirme geçti ya da 30 gün içinde (uyarı), Risk D, ek bilgi,
/// askı ve ret.
({String? yourMove, List<String> danger, String? warn, List<String> notes})
financeExceptions(FinanceListItem item, DateTime today) {
  final status = item.status;
  final danger = [
    if ((item.overdueAmount ?? 0) > 0)
      'Gecikme ${Fmt.moneyWhole(item.overdueAmount)}',
    if (item.hasBouncedCheque) 'karşılıksız çek',
    if (item.hasProtestedNote) 'protestolu senet',
  ];
  String? warn;
  final review = item.nextReviewDate;
  if (review != null) {
    final days = TrTime.dayDiff(today, review);
    if (days < 0) {
      warn = 'Gözden geçirme geçti';
    } else if (days == 0) {
      warn = 'Gözden geçirme bugün';
    } else if (days <= _reviewSoonDays) {
      warn = 'Gözden geçirme $days gün sonra';
    }
  }
  return (
    yourMove: status == FinanceProfileStatus.pending
        ? FinanceCopy.pendingYourMove
        : null,
    danger: danger,
    warn: warn,
    notes: [
      if (item.riskClass == RiskClass.d) riskShort(RiskClass.d),
      if (status == FinanceProfileStatus.infoRequested) status!.label,
      if (status == FinanceProfileStatus.suspended ||
          status == FinanceProfileStatus.rejected)
        status!.label,
      if (status == null) FinanceCopy.statusLabel(null),
    ],
  );
}

/// Satır "Dikkat" grubunda mı (en az bir istisna).
bool financeNeedsAttention(FinanceListItem item, DateTime today) {
  final x = financeExceptions(item, today);
  return x.yourMove != null ||
      x.danger.isNotEmpty ||
      x.warn != null ||
      x.notes.isNotEmpty;
}

/// Finans satırı (tasarım v4 §5 09, defterde [AknListTile]):
///
/// ```
/// Anadolu Lojistik A.Ş.                                    2.500.000 ₺
/// ▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░                                              %47
/// ! Gecikme 185.000 ₺ · karşılıksız çek          (yalnızca istisnada)
/// ```
///
/// L1 cari ve limit (limit yoksa "limitsiz"); L2 6 dp kullanım çubuğu (ilk görünüşte dolarak gelir)
/// ve oranı; L3 yalnızca istisnada: "Finans onayınızı bekliyor" (Pas), gecikme (tehlike), gözden
/// geçirme (uyarı), "Risk D". Normal durum yazılmaz ("Onaylı" yok, v4 P4); VKN satırda yok (arama
/// bulur).
class FinanceRowCard extends StatelessWidget {
  const FinanceRowCard({super.key, required this.item, required this.onTap});

  final FinanceListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final today = TrTime.todayStart();
    final usage = item.usage;
    final liters = const {'L', 'l'}.contains(item.limitUnit?.trim());
    String amount(double? v) => liters ? Fmt.liters(v) : Fmt.moneyWhole(v);
    final x = financeExceptions(item, today);
    final percent = usage == null
        ? null
        : Fmt.percent(usage * 100, maxFraction: 0);
    final tone = usage == null
        ? null
        : usage >= 1
        ? AknTone.danger
        : usage >= 0.8
        ? AknTone.warn
        : null;

    final lines = <Widget>[
      if (x.yourMove != null)
        Text(
          x.yourMove!,
          style: t.bodySmall.copyWith(
            fontWeight: FontWeight.w600,
            color: c.brandInk,
          ),
        ),
      if (x.danger.isNotEmpty)
        _ExceptionLine(
          icon: PhosphorIconsFill.warningCircle,
          text: _sentence(x.danger),
          color: c.danger.fg,
        ),
      if (x.warn != null)
        _ExceptionLine(
          icon: PhosphorIconsRegular.calendarX,
          text: x.warn!,
          color: c.warn.fg,
        ),
      if (x.notes.isNotEmpty)
        Text(
          x.notes.join(' · '),
          style: t.bodySmall.copyWith(
            fontWeight: FontWeight.w600,
            color: item.riskClass == RiskClass.d ? c.danger.fg : c.dim,
          ),
        ),
    ];

    final semantic = [
      item.customerTitle,
      if (item.limitAmount == null)
        FinanceCopy.unlimited
      else
        'limit ${amount(item.limitAmount)}',
      if (usage != null)
        'kullanım yüzde ${(usage * 100).round()}, ${amount(item.limitUsed)} kullanıldı',
      ?x.yourMove,
      ...x.danger,
      ?x.warn,
      ...x.notes,
    ].join(', ');

    return AknListTile(
      title: item.customerTitle,
      amount: item.limitAmount == null ? null : amount(item.limitAmount),
      meta: item.limitAmount == null ? FinanceCopy.unlimited : null,
      flow: usage == null
          ? null
          : ExcludeSemantics(
              child: Row(
                children: [
                  Expanded(
                    // Ölçer sıfırdan dolarak gelir (çekirdek [UsageBar]); rengi son değerden.
                    child: UsageBar(value: usage, height: 6, tone: tone),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    percent!,
                    style: t.label.copyWith(
                      fontWeight: FontWeight.w600,
                      color: tone == null ? c.dim : c.tone(tone).fg,
                      fontFeatures: AknNumerals.tabular,
                    ),
                  ),
                ],
              ),
            ),
      status: lines.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0) const SizedBox(height: 2),
                  lines[i],
                ],
              ],
            ),
      semanticLabel: semantic,
      onTap: onTap,
    );
  }

  /// "Gecikme 185.000 ₺ · karşılıksız çek" (ilk söz büyük harfle).
  static String _sentence(List<String> parts) {
    final text = parts.join(' · ');
    if (text.isEmpty) return text;
    return '${TurkishText.upper(text.substring(0, 1))}${text.substring(1)}';
  }
}

/// İstisna satırı: küçük simge + renkli söz (renk tek başına değil, söz de söyler).
class _ExceptionLine extends StatelessWidget {
  const _ExceptionLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final size = MediaQuery.textScalerOf(context).scale(15).clamp(15.0, 28.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: size, color: color),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: t.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
