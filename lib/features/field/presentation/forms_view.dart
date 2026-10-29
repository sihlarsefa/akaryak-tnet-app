import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../application/field_access.dart';
import '../application/field_lists.dart';
import '../copy.dart';
import '../data/field_models.dart';
import '../data/field_outbox.dart';
import '../data/field_repository.dart';
import 'widgets/field_widgets.dart';

/// Form listesi görünümü (temsilci: Formlarım; ekip: Formlar / Onayda / Reddedilen). Tasarım v3:
/// arama ve süzgeç çipleri, ardından sayfada yüzen satır kartları — ilk açılışta (ve süzgeç
/// değişince) sırayla, sonra kaydırdıkça görünür oldukça kayarak belirir.
@immutable
class FieldFormsConfig {
  /// Temsilcinin kendi formları (durum süzgeci, gönderilmeyi bekleyen taslaklar).
  const FieldFormsConfig.rep({this.initialStatus})
    : baseStatuses = const [],
      statusFilter = true,
      repFilter = false,
      levelFilter = false,
      showRep = false,
      showQueued = true,
      emptyTitle = FieldCopy.formsEmptyTitle,
      emptyMessage = FieldCopy.formsEmptyMessage;

  /// Saha ekibinin formları (temsilciye ve duruma göre).
  const FieldFormsConfig.team({this.initialStatus})
    : baseStatuses = const [],
      statusFilter = true,
      repFilter = true,
      levelFilter = false,
      showRep = true,
      showQueued = true,
      emptyTitle = FieldCopy.teamFormsEmptyTitle,
      emptyMessage = FieldCopy.teamFormsEmptyMessage;

  /// Onay bekleyenler (kademeye göre).
  const FieldFormsConfig.pending()
    : baseStatuses = const [1],
      statusFilter = false,
      repFilter = true,
      levelFilter = true,
      showRep = true,
      showQueued = false,
      initialStatus = null,
      emptyTitle = FieldCopy.pendingEmptyTitle,
      emptyMessage = FieldCopy.pendingEmptyMessage;

  /// Reddedilenler.
  const FieldFormsConfig.rejected()
    : baseStatuses = const [3],
      statusFilter = false,
      repFilter = true,
      levelFilter = false,
      showRep = true,
      showQueued = false,
      initialStatus = null,
      emptyTitle = FieldCopy.rejectedEmptyTitle,
      emptyMessage = FieldCopy.rejectedEmptyMessage;

  final List<int> baseStatuses;
  final bool statusFilter;
  final bool repFilter;
  final bool levelFilter;
  final bool showRep;
  final bool showQueued;
  final int? initialStatus;
  final String emptyTitle;
  final String emptyMessage;
}

class FieldFormsView extends ConsumerStatefulWidget {
  const FieldFormsView({super.key, required this.config});

  final FieldFormsConfig config;

  @override
  ConsumerState<FieldFormsView> createState() => _FieldFormsViewState();
}

class _FieldFormsViewState extends ConsumerState<FieldFormsView> {
  final _scroll = ScrollController();
  String _search = '';
  int? _status;
  int? _rep;
  int? _level;

  static const _statusOptions = <FilterOption<int>>[
    FilterOption(value: 0, label: 'Taslak'),
    FilterOption(value: 1, label: 'Onay bekliyor'),
    FilterOption(value: 2, label: 'Onaylandı'),
    FilterOption(value: 4, label: 'Siparişe dönüştü'),
    FilterOption(value: 3, label: 'Reddedildi'),
    FilterOption(value: 5, label: 'İptal edildi'),
  ];

  static const _levelOptions = <FilterOption<int>>[
    FilterOption(value: 1, label: 'Bayi yöneticisi'),
    FilterOption(value: 2, label: 'Üst onay'),
    FilterOption(value: 3, label: 'İstisna'),
  ];

  @override
  void initState() {
    super.initState();
    _status = widget.config.initialStatus;
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  FieldFormsQuery get _query => FieldFormsQuery(
    statuses: widget.config.baseStatuses.isNotEmpty
        ? widget.config.baseStatuses
        : [?_status],
    salesRepresentativeId: _rep,
    requiredApprovalLevel: _level,
    search: _search.isEmpty ? null : _search,
  );

  bool get _filtered =>
      _search.isNotEmpty || _status != null || _rep != null || _level != null;

  void _onScroll() {
    final p = _scroll.position;
    if (p.extentAfter < 480) {
      unawaited(ref.read(fieldFormsProvider(_query).notifier).loadMore());
    }
  }

  void _clear() => setState(() {
    _search = '';
    _status = null;
    _rep = null;
    _level = null;
  });

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    final query = _query;
    final state = ref.watch(fieldFormsProvider(query));
    final access = ref.watch(fieldAccessProvider);
    final queued = cfg.showQueued && !_filtered
        ? ref.watch(fieldQueuedItemsProvider).where((q) => q.isForm).toList()
        : const <FieldQueuedItem>[];

    final header = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: SearchField(
          hint: 'Form no, cari ünvanı ya da kodu',
          onChanged: (s) => setState(() => _search = s),
        ),
      ),
      if (cfg.statusFilter)
        FilterChips<int>(
          options: _statusOptions,
          selected: {?_status},
          onChanged: (s) =>
              setState(() => _status = s.isEmpty ? null : s.first),
        ),
      if (cfg.levelFilter)
        FilterChips<int>(
          options: _levelOptions,
          selected: {?_level},
          onChanged: (s) => setState(() => _level = s.isEmpty ? null : s.first),
        ),
      if (cfg.repFilter)
        _RepChips(value: _rep, onChanged: (v) => setState(() => _rep = v)),
      if (state.cachedAt != null) FieldCachedNote(at: state.cachedAt!),
      for (final q in queued)
        FieldListCard(
          child: FieldQueuedTile(
            item: q,
            onEdit: () =>
                context.push('${AppRoutes.fieldFormNew}?op=${q.op.id}'),
          ),
        ),
    ];

    Widget list;
    if (state.firstLoading && state.items.isEmpty) {
      list = ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [...header, const FieldSkeletonCards(count: 5)],
      );
    } else if (state.items.isEmpty && queued.isEmpty) {
      list = ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ...header,
          FieldListState(
            error: state.error,
            onRetry: () =>
                ref.read(fieldFormsProvider(query).notifier).refresh(),
            emptyTitle: cfg.emptyTitle,
            emptyMessage: cfg.emptyMessage,
            filtered: _filtered,
            onClearFilters: _clear,
            emptyActionLabel: access.canCreateForm && cfg.baseStatuses.isEmpty
                ? 'Saha formu'
                : null,
            onEmptyAction: () => context.push(AppRoutes.fieldFormNew),
          ),
        ],
      );
    } else {
      final items = state.items;
      list = StaggerScope(
        key: ValueKey(query.key),
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: header.length + items.length + 1,
          itemBuilder: (context, i) {
            if (i < header.length) return header[i];
            final index = i - header.length;
            if (index == items.length) {
              return FieldListFooter(
                loading: state.loadingMore,
                error: state.moreError,
                onRetry: () =>
                    ref.read(fieldFormsProvider(query).notifier).loadMore(),
                total: state.total,
                shown: items.length,
              );
            }
            return FieldStaggerItem(
              index: index,
              child: FieldListCard(
                child: FieldFormTile(row: items[index], showRep: cfg.showRep),
              ),
            );
          },
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: PullToRefresh(
            onRefresh: () =>
                ref.read(fieldFormsProvider(query).notifier).refresh(),
            child: list,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: TopProgressBar(active: state.refreshing),
        ),
      ],
    );
  }
}

/// Temsilci süzgeci (`field-orders/reps`).
class _RepChips extends ConsumerWidget {
  const _RepChips({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reps = ref.watch(fieldRepsProvider).valueOrNull ?? const <IdName>[];
    if (reps.isEmpty) return const SizedBox.shrink();
    return FilterChips<int>(
      options: [
        for (final r in reps)
          FilterOption(
            value: r.id,
            label: r.isInactive ? '${r.name} (pasif)' : r.name,
            icon: PhosphorIconsRegular.user,
          ),
      ],
      selected: {?value},
      onChanged: (s) => onChanged(s.isEmpty ? null : s.first),
    );
  }
}
