import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/access_policy.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/models/enums.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/turkish_text.dart';
import '../application/approvals_providers.dart';
import '../copy.dart';
import '../data/approval_models.dart';
import '../data/approvals_repository.dart';
import '../shared/paged_list.dart';
import '../shared/paged_list_view.dart';
import 'widgets/approval_card.dart';

/// SLA süzgeci ("Bende" sekmesinde, yüklenen satırlar üzerinde).
enum _SlaFilter { all, dueSoon, overdue }

/// Onaylarım (spec A.4 A5): Bende / Taleplerim / Karar verdiklerim / Tümü (İnceler), tür çipleri,
/// SLA çipleri, rozet. Satıra dokununca ayrıntı (`/approvals/{id}`) açılır.
class ApprovalsPage extends ConsumerStatefulWidget {
  const ApprovalsPage({super.key, this.initialScope});

  /// Derin bağlantı: `/approvals?scope=taleplerim`.
  final ApprovalScope? initialScope;

  /// `scope` sorgu değerini sekmeye çevirir (`bende`, `taleplerim`, `kararlarim`, `tumu` ya da 0–3).
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

  @override
  ConsumerState<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends ConsumerState<ApprovalsPage> {
  late ApprovalScope _scope;
  ApprovalType? _type;
  String _search = '';
  _SlaFilter _sla = _SlaFilter.all;
  int _autoLoads = 0;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scope =
        widget.initialScope ?? _defaultScope(ref.read(accessPolicyProvider));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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

  bool _canSeeAll(AccessPolicy p) =>
      p.isPlatform ||
      (p.isBayi && p.can(Pg.stationApprovals, Perm.inspect)) ||
      (p.isCustomer && p.can(Pg.customerApprovals, Perm.inspect));

  List<ApprovalScope> _scopes(AccessPolicy p) => [
    ApprovalScope.toMe,
    ApprovalScope.mine,
    if (!p.isCustomer || p.customerRole.canApprove) ApprovalScope.decidedByMe,
    if (_canSeeAll(p)) ApprovalScope.all,
  ];

  ApprovalsQuery get _query =>
      ApprovalsQuery(scope: _scope, type: _type, search: _search);

  void _setScope(ApprovalScope s) {
    if (s == _scope) return;
    setState(() {
      _scope = s;
      _sla = _SlaFilter.all;
      _autoLoads = 0;
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(approvalBadgeProvider);
    await ref.read(approvalsListProvider(_query).notifier).refresh();
  }

  PagedState<ApprovalRow> _applySla(PagedState<ApprovalRow> s) {
    if (_sla == _SlaFilter.all) return s;
    final want = _sla == _SlaFilter.overdue
        ? ApprovalSlaState.overdue
        : ApprovalSlaState.dueSoon;
    return s.copyWith(
      items: [
        for (final r in s.items)
          if (r.slaState == want) r,
      ],
    );
  }

  /// SLA süzgecinde az satır kaldıysa sonraki sayfalar kendiliğinden yüklenir (en çok 4).
  void _maybeAutoLoad(PagedState<ApprovalRow> raw, int shown) {
    if (_sla == _SlaFilter.all || !raw.hasMore || raw.loadingMore) return;
    if (shown >= 10 || _autoLoads >= 4) return;
    _autoLoads++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(approvalsListProvider(_query).notifier).loadMore());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final policy = ref.watch(accessPolicyProvider);
    final scopes = _scopes(policy);
    if (!scopes.contains(_scope)) _scope = scopes.first;
    final query = _query;
    final raw = ref.watch(approvalsListProvider(query));
    final badge = ref.watch(approvalBadgeProvider).valueOrNull;
    final state = _applySla(raw);
    _maybeAutoLoad(raw, state.items.length);
    final customer = policy.isCustomer;
    final showSla = !customer && _scope == ApprovalScope.toMe;
    final org = policy.access?.organizationTitle;

    return AppScaffold(
      title: ApprovalsCopy.title,
      subtitle: org,
      refreshing: raw.refreshing,
      body: A5PagedListView<ApprovalRow>(
        state: state,
        staggerKey: (query, _sla),
        onRefresh: _refresh,
        onLoadMore: () => unawaited(
          ref.read(approvalsListProvider(query).notifier).loadMore(),
        ),
        header: [
          const SizedBox(height: 8),
          _ScopeTabs(
            scopes: scopes,
            value: _scope,
            toMeCount: badge?.toMe,
            onChanged: _setScope,
          ),
          if (showSla &&
              (badge?.overdue ?? 0) > 0 &&
              _sla != _SlaFilter.overdue)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: AknBanner(
                tone: AknTone.warn,
                icon: Icons.alarm_rounded,
                message: badge!.overdue == 1
                    ? '1 talebin karar süresi geçti.'
                    : '${badge.overdue} talebin karar süresi geçti.',
                actionLabel: 'Gecikenleri göster',
                onAction: () => setState(() {
                  _sla = _SlaFilter.overdue;
                  _autoLoads = 0;
                }),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SearchField(
              controller: _searchCtrl,
              hint: ApprovalsCopy.searchHint,
              onChanged: (q) => setState(() => _search = q.trim()),
            ),
          ),
          if (!customer)
            FilterChips<ApprovalType>(
              options: [
                for (final t in ApprovalType.values)
                  if (!t.isUnknown)
                    FilterOption(
                      value: t,
                      label: t.shortLabel,
                      icon: AknStatus.approvalType(t).icon,
                    ),
              ],
              selected: {?_type},
              onChanged: (s) => setState(() {
                _type = s.isEmpty ? null : s.first;
              }),
            ),
          if (showSla)
            FilterChips<_SlaFilter>(
              options: const [
                FilterOption(
                  value: _SlaFilter.dueSoon,
                  label: 'Süresi dolanlar',
                  icon: Icons.alarm_rounded,
                ),
                FilterOption(
                  value: _SlaFilter.overdue,
                  label: 'Süresi geçenler',
                  icon: Icons.alarm_off_rounded,
                ),
              ],
              selected: {if (_sla != _SlaFilter.all) _sla},
              onChanged: (s) => setState(() {
                _sla = s.isEmpty ? _SlaFilter.all : s.first;
                _autoLoads = 0;
              }),
            ),
        ],
        itemBuilder: (context, row, _) => ApprovalCard(
          row: row,
          customerSide: customer,
          onTap: () => context.push(AppRoutes.approval(row.id)),
        ),
        empty: _empty(context, policy),
      ),
    );
  }

  Widget _empty(BuildContext context, AccessPolicy policy) {
    final filtered = _query.isFiltered || _sla != _SlaFilter.all;
    if (filtered) {
      return EmptyState(
        title: ApprovalsCopy.filteredTitle,
        message: ApprovalsCopy.filteredMessage,
        illustration: AknIllustration.search,
        actionLabel: ApprovalsCopy.clearFilters,
        onAction: () => setState(() {
          _type = null;
          _sla = _SlaFilter.all;
          _search = '';
          _searchCtrl.clear();
        }),
      );
    }
    return EmptyState(
      title: ApprovalsCopy.emptyTitle(_scope),
      message: ApprovalsCopy.emptyMessage(_scope),
      illustration: _scope == ApprovalScope.toMe
          ? AknIllustration.done
          : AknIllustration.approvals,
      actionLabel: _scope == ApprovalScope.toMe ? ApprovalsCopy.showMine : null,
      onAction: _scope == ApprovalScope.toMe
          ? () => _setScope(ApprovalScope.mine)
          : null,
    );
  }
}

/// Sekmeler: normal yazı boyutunda kayan başparmaklı bölümlü denetim; büyük yazıda (>%130) kesilmesin
/// diye yatay kayan çipler.
class _ScopeTabs extends StatelessWidget {
  const _ScopeTabs({
    required this.scopes,
    required this.value,
    required this.onChanged,
    this.toMeCount,
  });

  final List<ApprovalScope> scopes;
  final ApprovalScope value;
  final ValueChanged<ApprovalScope> onChanged;
  final int? toMeCount;

  @override
  Widget build(BuildContext context) {
    final options = [
      for (final s in scopes)
        FilterOption(
          value: s,
          label: s.shortLabel,
          count: s == ApprovalScope.toMe && (toMeCount ?? 0) > 0
              ? toMeCount
              : null,
        ),
    ];
    // Tek seçimli çipler: çekirdek `AknSegmented` seçilmemiş metni açık temada 4,5:1 kontrastın
    // altında kalıyor (contract-changes.md A5); çipler büyük yazıda da satır kaydırır.
    return FilterChips<ApprovalScope>(
      options: options,
      selected: {value},
      allowEmpty: false,
      onChanged: (s) => onChanged(s.first),
    );
  }
}
