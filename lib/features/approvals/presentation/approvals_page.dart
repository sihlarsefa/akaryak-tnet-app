import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tasks/task_inbox.dart';
import '../../../core/auth/access_policy.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/models/enums.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../../customer_orders/api.dart' show customerHomeProvider;
import '../application/approvals_providers.dart';
import '../copy.dart';
import '../data/approval_models.dart';
import '../data/approvals_repository.dart';
import '../shared/layout.dart';
import '../shared/paged_list.dart';
import '../shared/paged_list_view.dart';
import 'widgets/approval_card.dart';

/// Onaylar (tasarım v4 "Sade" §5 08 bayi, 08b cari).
///
/// * Bant: "Onaylar" (alt menü sözcüğü) ve canlı durum satırı — bayide "9 talep kararınızı
///   bekliyor · 2'si gecikti" (gecikme sözü "Gecikmiş"e kaydırır), caride "3 iş sizi bekliyor";
///   ⌕ (bandın altında açılan arama şeridi) ve bayide Filtre (tür; denetçiye "Tüm talepler").
/// * Tek seçici: [Bende n | Taleplerim | Kararlarım] (AknSegmented).
/// * Bayi Bende: gruplar Gecikmiş → Bugün → Dün → Daha önce → "Yanıt bekleniyor" (başkasının
///   yanıtı beklenen, nötr, sayısız); satırlar defterde ([ApprovalRowTile]).
/// * Cari Bende: görev kutusu (`customerTasksProvider`) ana sayfadaki "Sıra sizde" ile aynı
///   satırlar ([AknTaskRow]) ve aynı sırada — rozet = Bende = ana sayfa sayısı (P2).
/// * Uyarı bandı, çip satırı ve arama kuyusu yok (v4 P7).
class ApprovalsPage extends ConsumerStatefulWidget {
  const ApprovalsPage({super.key, this.initialScope, this.initialType});

  /// Derin bağlantı: `/approvals?scope=taleplerim`.
  final ApprovalScope? initialScope;

  /// Derin bağlantı: `/approvals?type=4` (tür süzgeci).
  final ApprovalType? initialType;

  /// `scope` sorgu değerini sekmeye çevirir (`bende`, `taleplerim`, `kararlarim`, `tumu` ya da
  /// 0–3).
  static ApprovalScope? parseScope(String? raw) {
    final v = raw == null ? null : TurkishText.searchKey(raw);
    if (v == null || v.isEmpty) return null;
    return switch (v) {
      '0' || 'bende' || 'tome' => ApprovalScope.toMe,
      '1' || 'taleplerim' || 'mine' => ApprovalScope.mine,
      '2' || 'kararlarim' || 'decided' => ApprovalScope.decidedByMe,
      '3' || 'tumu' || 'all' => ApprovalScope.all,
      _ => null,
    };
  }

  /// `type` sorgu değerini türe çevirir (kod ya da ad).
  static ApprovalType? parseType(String? raw) {
    final v = raw == null ? null : TurkishText.searchKey(raw);
    if (v == null || v.isEmpty) return null;
    final code = int.tryParse(v);
    if (code != null) {
      final t = ApprovalType.fromCode(code);
      return t.isUnknown ? null : t;
    }
    for (final t in ApprovalType.values) {
      if (t.isUnknown) continue;
      if (TurkishText.searchKey(t.name) == v) return t;
    }
    return null;
  }

  @override
  ConsumerState<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends ConsumerState<ApprovalsPage> {
  late ApprovalScope _scope;

  /// Denetçinin "Tüm talepler" kapsamı (Filtre sayfasından).
  bool _all = false;
  ApprovalType? _type;
  String _search = '';
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    final policy = ref.read(accessPolicyProvider);
    final initial = widget.initialScope;
    if (initial == ApprovalScope.all) {
      _all = _canSeeAll(policy);
      _scope = _defaultScope(policy);
    } else {
      _scope = initial ?? _defaultScope(policy);
    }
    _type = policy.isCustomer ? null : widget.initialType;
  }

  /// Karar veremeyen talep sahipleri (cari "Talep eden", saha temsilcisi) Taleplerim'le başlar.
  static ApprovalScope _defaultScope(AccessPolicy p) {
    if (p.isCustomer && !p.customerRole.canApprove) return ApprovalScope.mine;
    if (p.isFieldSales &&
        !Caps.all.any((c) => c.startsWith('approve.') && p.hasCap(c))) {
      return ApprovalScope.mine;
    }
    return ApprovalScope.toMe;
  }

  static bool _canSeeAll(AccessPolicy p) =>
      p.isPlatform ||
      (p.isBayi && p.can(Pg.stationApprovals, Perm.inspect)) ||
      (p.isCustomer && p.can(Pg.customerApprovals, Perm.inspect));

  List<ApprovalScope> _scopes(AccessPolicy p) => [
    ApprovalScope.toMe,
    ApprovalScope.mine,
    if (!p.isCustomer || p.customerRole.canApprove) ApprovalScope.decidedByMe,
  ];

  ApprovalsQuery get _query => ApprovalsQuery(
    scope: _all ? ApprovalScope.all : _scope,
    type: _type,
    search: _search,
  );

  void _setScope(ApprovalScope s) {
    if (s == _scope && !_all) return;
    setState(() {
      _scope = s;
      _all = false;
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(approvalBadgeProvider);
    await ref.read(approvalsListProvider(_query).notifier).refresh();
  }

  Future<void> _refreshInbox() async {
    ref.invalidate(approvalBadgeProvider);
    await Future.wait([
      ref.read(customerHomeProvider.notifier).refresh(),
      ref
          .read(approvalsListProvider(const ApprovalsQuery()).notifier)
          .refresh(),
    ]);
  }

  int get _activeFilters => (_type == null ? 0 : 1) + (_all ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final policy = ref.watch(accessPolicyProvider);
    final customer = policy.isCustomer;
    final scopes = _scopes(policy);
    if (!scopes.contains(_scope)) _scope = scopes.first;
    final inboxView = customer && _scope == ApprovalScope.toMe && !_all;
    final inbox = customer ? ref.watch(customerTasksProvider) : null;
    final badge = customer
        ? null
        : ref.watch(approvalBadgeProvider).valueOrNull;

    final leading = bandPageLeading(context);
    // Bant geri / ana sayfa düğmesiyle daralınca durum satırı kısa söylenir (tek satır, kesilmez).
    final narrow =
        leading != null ||
        (ModalRoute.of(context)?.impliesAppBarDismissal ?? false);
    // Gecikme sözü dokunulabilir değil: "Gecikmiş" zaten Bende'nin ilk grubu ve bandın tek satırlık
    // durum yazısı 48 dp dokunma hedefi olamaz (C.7).
    final Object status;
    final int? bendeCount;
    if (customer) {
      final n = inbox?.count ?? 0;
      bendeCount = n;
      status = n > 0
          ? AknStatusClause.yourMove(ApprovalsCopy.customerWaiting(n))
          : ApprovalsCopy.customerCalm;
    } else {
      final n = badge?.toMe ?? 0;
      final late = badge?.overdue ?? 0;
      bendeCount = badge?.toMe;
      status = n > 0
          ? [
              AknStatusClause.yourMove(
                ApprovalsCopy.bayiWaiting(
                  n,
                  short: late > 0 || narrow,
                  bare: late > 0 && narrow,
                ),
              ),
              if (late > 0)
                AknStatusClause.overdue('${numeralPossessive(late)} gecikti'),
            ]
          : ApprovalsCopy.bayiCalm;
    }

    final switcher = _ScopeSwitcher(
      scopes: scopes,
      value: _all ? null : _scope,
      toMeCount: bendeCount,
      onChanged: _setScope,
    );

    final raw = inboxView ? null : ref.watch(approvalsListProvider(_query));
    return AppScaffold(
      title: ApprovalsCopy.title,
      bandIcon: PhosphorIconsRegular.checkCircle,
      // Alt menüde değilse (Diğer'den) de bantla görünür.
      largeTitle: true,
      leading: leading,
      status: status,
      refreshing: raw?.refreshing ?? false,
      actions: [
        AknSearchReveal.button(
          semanticLabel: 'Onaylarda ara',
          onPressed: () => setState(() => _searchOpen = true),
        ),
        if (!customer)
          AknFilterButton(
            count: _activeFilters,
            sheetBuilder: (_) => _ApprovalFilters(
              type: _type,
              all: _all,
              canSeeAll: _canSeeAll(policy),
              onType: (t) => setState(() => _type = t),
              onAll: (v) => setState(() => _all = v),
            ),
          ),
      ],
      body: Column(
        children: [
          AknSearchReveal(
            open: _searchOpen || _search.isNotEmpty,
            hint: customer
                ? ApprovalsCopy.customerSearchHint
                : ApprovalsCopy.searchHint,
            onChanged: (q) => setState(() => _search = q.trim()),
            onClose: () => setState(() {
              _searchOpen = false;
              _search = '';
            }),
          ),
          Expanded(
            child: FadeThroughSwitcher(
              child: inboxView
                  ? KeyedSubtree(
                      key: const ValueKey('inbox'),
                      child: _CustomerBende(
                        inbox: inbox ?? TaskInbox.empty,
                        search: _search,
                        header: switcher,
                        onRefresh: _refreshInbox,
                        onClearSearch: () => setState(() {
                          _search = '';
                          _searchOpen = false;
                        }),
                      ),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('list'),
                      child: _list(context, policy, raw!, switcher),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(
    BuildContext context,
    AccessPolicy policy,
    PagedState<ApprovalRow> state,
    Widget switcher,
  ) {
    final customer = policy.isCustomer;
    final query = _query;
    final bende = query.scope == ApprovalScope.toMe;
    final me = ref.watch(currentUserIdProvider);
    bool waiting(ApprovalRow r) =>
        r.status == ApprovalStatus.infoRequested &&
        (me == null || r.requestedByUserId != me);
    return A5PagedListView<ApprovalRow>(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      state: state,
      ledger: true,
      staggerKey: query,
      onRefresh: _refresh,
      onLoadMore: () =>
          unawaited(ref.read(approvalsListProvider(query).notifier).loadMore()),
      header: [const SizedBox(height: 4), switcher],
      groups: (rows) =>
          bende && !customer ? _bendeGroups(rows, waiting) : _dayGroups(rows),
      itemBuilder: (context, row, _) {
        final waits = bende && !customer && waiting(row);
        return ApprovalRowTile(
          row: row,
          customerSide: customer,
          viewerId: me,
          mode: !bende
              ? ApprovalRowMode.history
              : (waits ? ApprovalRowMode.waiting : ApprovalRowMode.decide),
          // Gün gruplarında zaman günsüz ("Yanıt bekleniyor" gün grubu değil).
          dayGrouped: !waits,
          onTap: () => context.push(AppRoutes.approval(row.id)),
        );
      },
      empty: _empty(context),
    );
  }

  /// Bende (bayi, merkez): Gecikmiş → Bugün → Dün → Daha önce → Yanıt bekleniyor.
  List<A5ListGroup<ApprovalRow>> _bendeGroups(
    List<ApprovalRow> rows,
    bool Function(ApprovalRow) waiting,
  ) {
    final late = <ApprovalRow>[];
    final rest = <ApprovalRow>[];
    final wait = <ApprovalRow>[];
    final now = TrTime.now();
    for (final r in rows) {
      if (waiting(r)) {
        wait.add(r);
      } else if (r.status.isOpen &&
          (r.slaState == ApprovalSlaState.overdue ||
              (r.dueAt != null && !r.dueAt!.isAfter(now)))) {
        late.add(r);
      } else {
        rest.add(r);
      }
    }
    // Gecikenler en eskisi önce (v4 §3.4 sıralama).
    late.sort(
      (a, b) => (a.dueAt ?? a.createdAt ?? now).compareTo(
        b.dueAt ?? b.createdAt ?? now,
      ),
    );
    return [
      A5ListGroup(
        id: 'overdue',
        title: ApprovalsCopy.groupOverdue,
        count: late.length,
        tone: AknTone.danger,
        items: late,
      ),
      ..._dayGroups(rest),
      A5ListGroup(
        id: 'waiting',
        title: ApprovalsCopy.groupWaiting,
        items: wait,
      ),
    ];
  }

  /// Bugün → Dün → Daha önce (talebin geldiği güne göre).
  static List<A5ListGroup<ApprovalRow>> _dayGroups(List<ApprovalRow> rows) {
    final today = <ApprovalRow>[];
    final yesterday = <ApprovalRow>[];
    final earlier = <ApprovalRow>[];
    final now = TrTime.now();
    for (final r in rows) {
      final at = r.createdAt;
      final diff = at == null ? -99 : TrTime.dayDiff(now, at);
      if (diff >= 0) {
        today.add(r);
      } else if (diff == -1) {
        yesterday.add(r);
      } else {
        earlier.add(r);
      }
    }
    return [
      A5ListGroup(
        id: 'today',
        title: ApprovalsCopy.groupToday,
        count: today.length,
        items: today,
      ),
      A5ListGroup(
        id: 'yesterday',
        title: ApprovalsCopy.groupYesterday,
        count: yesterday.length,
        items: yesterday,
      ),
      A5ListGroup(
        id: 'earlier',
        title: ApprovalsCopy.groupEarlier,
        count: earlier.length,
        items: earlier,
      ),
    ];
  }

  Widget _empty(BuildContext context) {
    final q = _query;
    if (q.isFiltered) {
      return EmptyState.compact(
        title: ApprovalsCopy.noResultTitle(q.search),
        message: ApprovalsCopy.noResultMessage,
        illustration: AknIllustration.search,
        actionLabel: ApprovalsCopy.clearFilters,
        onAction: () => setState(() {
          _type = null;
          _search = '';
          _searchOpen = false;
        }),
      );
    }
    final scope = q.scope;
    return EmptyState(
      title: ApprovalsCopy.emptyTitle(scope),
      message: ApprovalsCopy.emptyMessage(scope),
      illustration: scope == ApprovalScope.toMe
          ? AknIllustration.done
          : AknIllustration.approvals,
      actionLabel: scope == ApprovalScope.toMe ? ApprovalsCopy.showMine : null,
      onAction: scope == ApprovalScope.toMe
          ? () => _setScope(ApprovalScope.mine)
          : null,
    );
  }
}

/// Tek seçici (v4 P7): normal yazıda kayan başparmaklı [AknSegmented] ([Bende n | Taleplerim |
/// Kararlarım]); büyük yazıda (≥ 1,3×) aynı seçim tek satır çiplerle yapılır (yine tek şerit).
/// [value] null: denetçi "Tüm talepler"i seçti, başparmak yok.
class _ScopeSwitcher extends StatelessWidget {
  const _ScopeSwitcher({
    required this.scopes,
    required this.value,
    required this.onChanged,
    this.toMeCount,
  });

  final List<ApprovalScope> scopes;
  final ApprovalScope? value;
  final ValueChanged<ApprovalScope> onChanged;
  final int? toMeCount;

  @override
  Widget build(BuildContext context) {
    final options = [
      for (final s in scopes)
        FilterOption<ApprovalScope?>(
          value: s,
          label: s.shortLabel,
          count: s == ApprovalScope.toMe && (toMeCount ?? 0) > 0
              ? toMeCount
              : null,
        ),
    ];
    final scaler = MediaQuery.textScalerOf(context);
    if (scaler.scale(10) >= 13) {
      return FilterChips<ApprovalScope?>(
        options: options,
        selected: {?value},
        allowEmpty: false,
        onChanged: (s) {
          final v = s.firstOrNull;
          if (v != null) onChanged(v);
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: AknSegmented<ApprovalScope?>(
        segments: options,
        value: value,
        onChanged: (s) {
          if (s != null) onChanged(s);
        },
      ),
    );
  }
}

/// Cari Bende (v4 §5 08b): görev kutusunun sayılan işleri, ana sayfadaki "Sıra sizde" satırlarıyla
/// aynı ([AknTaskRow]) ve aynı sırada, tek defterde; satırların sözü (bayinin kısa adı, kuruşsuz
/// tutar) görev kutusundandır. Arama metni başlık, alt satır ve notta aranır.
class _CustomerBende extends StatelessWidget {
  const _CustomerBende({
    required this.inbox,
    required this.search,
    required this.header,
    required this.onRefresh,
    required this.onClearSearch,
  });

  final TaskInbox inbox;
  final String search;
  final Widget header;
  final Future<void> Function() onRefresh;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    final key = TurkishText.searchKey(search);
    final tasks = [
      for (final t in inbox.items)
        if (t.counts &&
            (key.isEmpty ||
                TurkishText.searchKey(
                  [t.title, ?t.subtitle, ?t.amount, ?t.note].join(' '),
                ).contains(key)))
          t,
    ];
    final Widget body;
    if (inbox.loading && inbox.items.isEmpty) {
      body = const SkeletonList(
        itemCount: 3,
        lines: 2,
        padding: EdgeInsets.only(top: 4),
        shrinkWrap: true,
      );
    } else if (tasks.isEmpty && key.isNotEmpty) {
      body = EmptyState.compact(
        title: ApprovalsCopy.noResultTitle(search),
        message: ApprovalsCopy.noResultMessage,
        illustration: AknIllustration.search,
        actionLabel: ApprovalsCopy.clearFilters,
        onAction: onClearSearch,
      );
    } else if (tasks.isEmpty) {
      body = EmptyState(
        title: ApprovalsCopy.customerEmptyTitle,
        message: ApprovalsCopy.customerEmptyMessage,
        illustration: AknIllustration.done,
        actionLabel: ApprovalsCopy.goToOrders,
        onAction: () => context.go(AppRoutes.orders),
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.only(top: 10),
        child: AknLedger(
          pour: true,
          children: [
            for (final t in tasks)
              AknTaskRow(
                key: ValueKey(t.id),
                task: t.toAknTask(onTap: () => context.push(t.location)),
              ),
          ],
        ),
      );
    }
    return PullToRefresh(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: 24 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [const SizedBox(height: 4), header, body],
      ),
    );
  }
}

/// Filtre sayfası (bayi, merkez): tür ve denetçiye "Tüm talepler". Seçim hemen uygulanır.
class _ApprovalFilters extends StatefulWidget {
  const _ApprovalFilters({
    required this.type,
    required this.all,
    required this.canSeeAll,
    required this.onType,
    required this.onAll,
  });

  final ApprovalType? type;
  final bool all;
  final bool canSeeAll;
  final ValueChanged<ApprovalType?> onType;
  final ValueChanged<bool> onAll;

  @override
  State<_ApprovalFilters> createState() => _ApprovalFiltersState();
}

class _ApprovalFiltersState extends State<_ApprovalFilters> {
  late ApprovalType? _type = widget.type;
  late bool _all = widget.all;

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
        if (widget.canSeeAll) ...[
          caption(ApprovalsCopy.filterScope),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final all in const [false, true])
                AknChip(
                  label: all
                      ? ApprovalsCopy.scopeAll
                      : ApprovalsCopy.scopeMineAndToMe,
                  selected: _all == all,
                  onTap: () {
                    if (_all == all) return;
                    setState(() => _all = all);
                    widget.onAll(all);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        caption(ApprovalsCopy.filterType),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AknChip(
              label: ApprovalsCopy.allTypes,
              selected: _type == null,
              onTap: () {
                setState(() => _type = null);
                widget.onType(null);
              },
            ),
            for (final type in ApprovalType.values)
              if (!type.isUnknown)
                AknChip(
                  label: ApprovalsCopy.typeName(type),
                  selected: _type == type,
                  onTap: () {
                    final next = _type == type ? null : type;
                    setState(() => _type = next);
                    widget.onType(next);
                  },
                ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
