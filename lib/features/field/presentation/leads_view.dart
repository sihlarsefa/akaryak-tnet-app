import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../application/field_access.dart';
import '../application/field_lists.dart';
import '../copy.dart';
import '../data/field_outbox.dart';
import '../data/field_repository.dart';
import 'widgets/field_widgets.dart';

/// Ön kayıt listesi (`leads?scope=mine|all&status&q`). [all]: bayinin tümü (`lead.viewAll`).
/// Tasarım v3: satırlar sayfada yüzen kartlardır; ilk açılışta sırayla, kaydırdıkça kayarak belirir.
class FieldLeadsView extends ConsumerStatefulWidget {
  const FieldLeadsView({super.key, this.all = false, this.initialStatus});

  final bool all;
  final String? initialStatus;

  @override
  ConsumerState<FieldLeadsView> createState() => _FieldLeadsViewState();
}

class _FieldLeadsViewState extends ConsumerState<FieldLeadsView> {
  final _scroll = ScrollController();
  String _search = '';
  String? _status;

  static const _statusOptions = <FilterOption<String>>[
    FilterOption(value: 'draft', label: 'Taslak'),
    FilterOption(value: 'finance', label: 'Finansta'),
    FilterOption(value: 'info', label: 'Ek bilgi'),
    FilterOption(value: 'converted', label: 'Dönüştü'),
    FilterOption(value: 'rejected', label: 'Reddedildi'),
    FilterOption(value: 'cancelled', label: 'İptal'),
  ];

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 480) {
        unawaited(ref.read(fieldLeadsProvider(_query).notifier).loadMore());
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  LeadsQuery get _query => LeadsQuery(
    all: widget.all,
    status: _status,
    search: _search.isEmpty ? null : _search,
  );

  bool get _filtered => _search.isNotEmpty || _status != null;

  @override
  Widget build(BuildContext context) {
    final query = _query;
    final state = ref.watch(fieldLeadsProvider(query));
    final access = ref.watch(fieldAccessProvider);
    final queued = _filtered
        ? const <FieldQueuedItem>[]
        : ref
              .watch(fieldQueuedItemsProvider)
              .where((q) => q.isLead || q.isUpload)
              .toList();

    final header = <Widget>[
      if (widget.all)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            'Bayinin tüm ön kayıtları',
            style: context.aknText.label.copyWith(color: context.akn.dim),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: SearchField(
          hint: 'Ünvan, VKN ya da ön kayıt no',
          onChanged: (s) => setState(() => _search = s),
        ),
      ),
      FilterChips<String>(
        options: _statusOptions,
        selected: {?_status},
        onChanged: (s) => setState(() => _status = s.isEmpty ? null : s.first),
      ),
      if (state.cachedAt != null) FieldCachedNote(at: state.cachedAt!),
      for (final q in queued)
        FieldListCard(
          child: FieldQueuedTile(
            item: q,
            onEdit: q.isLead
                ? () => context.push('${AppRoutes.fieldLeadNew}?op=${q.op.id}')
                : null,
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
                ref.read(fieldLeadsProvider(query).notifier).refresh(),
            emptyTitle: FieldCopy.leadsEmptyTitle,
            emptyMessage: access.canCreateLead
                ? FieldCopy.leadsEmptyMessage
                : FieldCopy.leadsTeamEmptyMessage,
            filtered: _filtered,
            onClearFilters: () => setState(() {
              _search = '';
              _status = null;
            }),
            emptyActionLabel: access.canCreateLead ? 'Ön kayıt' : null,
            onEmptyAction: () => context.push(AppRoutes.fieldLeadNew),
            illustration: AknIllustration.customers,
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
                    ref.read(fieldLeadsProvider(query).notifier).loadMore(),
                total: state.total,
                shown: items.length,
              );
            }
            return FieldStaggerItem(
              index: index,
              child: FieldListCard(
                child: FieldLeadTile(row: items[index], showRep: widget.all),
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
                ref.read(fieldLeadsProvider(query).notifier).refresh(),
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
