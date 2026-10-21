import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/models.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/bayi_grants.dart';
import '../../application/orders_controller.dart';
import '../../data/bayi_repository.dart';
import '../../data/customer_models.dart';
import '../../data/order_models.dart';
import '../widgets/bayi_widgets.dart';

/// Sipariş süzgeçleri: durum, ödeme, finans, cari, oluşturulma ve istenen teslim aralığı, sıralama.
Future<void> showOrderFiltersSheet(BuildContext context) => showAppSheet<void>(
  context: context,
  title: 'Süzgeçler',
  builder: (_) => const _OrderFilters(),
);

class _OrderFilters extends ConsumerStatefulWidget {
  const _OrderFilters();

  @override
  ConsumerState<_OrderFilters> createState() => _OrderFiltersState();
}

class _OrderFiltersState extends ConsumerState<_OrderFilters> {
  late BayiOrdersFilter _f = ref.read(bayiOrdersProvider).filter;

  static const _statuses = [
    OrderStatus.awaitingQuote,
    OrderStatus.revisionRequested,
    OrderStatus.awaitingApproval,
    OrderStatus.approved,
    OrderStatus.completed,
    OrderStatus.rejected,
    OrderStatus.expired,
  ];

  static const _payments = [
    PaymentStatus.pending,
    PaymentStatus.documentUploaded,
    PaymentStatus.collected,
    PaymentStatus.bounced,
    PaymentStatus.cancelled,
  ];

  static const _finance = [
    OrderFinanceStatus.pending,
    OrderFinanceStatus.infoRequested,
    OrderFinanceStatus.approved,
    OrderFinanceStatus.conditionallyApproved,
    OrderFinanceStatus.rejected,
  ];

  Future<void> _pickCustomer() async {
    final picked = await showCustomerPicker(context);
    if (picked != null && mounted) {
      setState(
        () => _f = _f.copyWith(
          customerId: picked.customerId,
          customerTitle: picked.title,
        ),
      );
    }
  }

  void _apply() {
    ref.read(bayiOrdersProvider.notifier).setFilter(_f);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final grants = ref.watch(bayiGrantsProvider);
    final today = TrTime.todayStart();
    final first = TrTime.addDays(today, -730);
    final last = TrTime.addDays(today, 365);
    Widget label(String s) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(s, style: t.bodyStrong),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        label('Durum'),
        Wrap(
          spacing: 8,
          children: [
            for (final s in _statuses)
              FilterChip(
                label: Text(s.label),
                selected: _f.statuses.contains(s),
                onSelected: (on) => setState(() {
                  final next = Set<OrderStatus>.of(_f.statuses);
                  on ? next.add(s) : next.remove(s);
                  _f = _f.copyWith(statuses: next);
                }),
              ),
          ],
        ),
        label('Ödeme durumu'),
        Wrap(
          spacing: 8,
          children: [
            for (final p in _payments)
              ChoiceChip(
                label: Text(p.label),
                selected: _f.paymentStatus == p,
                onSelected: (on) => setState(
                  () => _f = _f.copyWith(paymentStatus: on ? p : null),
                ),
              ),
          ],
        ),
        label('Finans durumu'),
        Wrap(
          spacing: 8,
          children: [
            for (final s in _finance)
              ChoiceChip(
                label: Text(s.label),
                selected: _f.financeStatus == s,
                onSelected: (on) => setState(
                  () => _f = _f.copyWith(financeStatus: on ? s : null),
                ),
              ),
          ],
        ),
        if (grants.viewCustomers) ...[
          label('Cari'),
          AknListTile(
            padding: const EdgeInsets.symmetric(vertical: 4),
            leadingIcon: Icons.apartment_rounded,
            title:
                _f.customerTitle ??
                (_f.customerId == null
                    ? 'Tüm cariler'
                    : 'Cari #${_f.customerId}'),
            subtitle: _f.customerId == null ? 'Cari seçmek için dokunun' : null,
            onTap: _pickCustomer,
            trailing: _f.customerId == null
                ? null
                : AknIconButton(
                    icon: Icons.close_rounded,
                    semanticLabel: 'Cari süzgecini kaldır',
                    onPressed: () => setState(
                      () => _f = _f.copyWith(
                        customerId: null,
                        customerTitle: null,
                      ),
                    ),
                  ),
          ),
        ],
        label('Oluşturulma tarihi'),
        _Range(
          from: _f.createdFrom,
          to: _f.createdTo,
          first: first,
          last: today,
          onChanged: (a, b) =>
              setState(() => _f = _f.copyWith(createdFrom: a, createdTo: b)),
        ),
        label('İstenen teslim tarihi'),
        _Range(
          from: _f.requestedFrom,
          to: _f.requestedTo,
          first: first,
          last: last,
          onChanged: (a, b) => setState(
            () => _f = _f.copyWith(requestedFrom: a, requestedTo: b),
          ),
        ),
        label('Sıralama'),
        Wrap(
          spacing: 8,
          children: [
            for (final s in BayiOrderSort.values)
              ChoiceChip(
                label: Text(s.label),
                selected: _f.sort == s,
                onSelected: (_) => setState(() => _f = _f.copyWith(sort: s)),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: AknButton.secondary(
                label: 'Temizle',
                expand: true,
                onPressed: _f.advancedCount == 0
                    ? null
                    : () => setState(() => _f = _f.clearAdvanced()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AknButton(
                label: 'Uygula',
                expand: true,
                onPressed: _apply,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Range extends StatelessWidget {
  const _Range({
    required this.from,
    required this.to,
    required this.first,
    required this.last,
    required this.onChanged,
  });

  final DateTime? from;
  final DateTime? to;
  final DateTime first;
  final DateTime last;
  final void Function(DateTime? from, DateTime? to) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DateField(
          label: 'Başlangıç',
          value: from,
          firstDate: first,
          lastDate: last,
          quickPicks: false,
          onChanged: (d) =>
              onChanged(d, to != null && to!.isBefore(d) ? d : to),
        ),
        const SizedBox(height: 8),
        DateField(
          label: 'Bitiş',
          value: to,
          firstDate: from ?? first,
          lastDate: last,
          quickPicks: false,
          onChanged: (d) => onChanged(from, d),
        ),
        if (from != null || to != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => onChanged(null, null),
              child: const Text('Tarihi temizle'),
            ),
          ),
      ],
    );
  }
}

/// Cari seçici (arama; bayinin carileri ya da temsilcinin portföyü).
Future<BayiCustomerRow?> showCustomerPicker(BuildContext context) =>
    showAppSheet<BayiCustomerRow>(
      context: context,
      title: 'Cari seçin',
      builder: (_) => const _CustomerPicker(),
    );

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  List<BayiCustomerRow>? _rows;
  AppFailure? _error;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load(''));
  }

  Future<void> _load(String q) async {
    final epoch = ++_epoch;
    try {
      final r = await ref
          .read(bayiRepositoryProvider)
          .customers(q: q, pageSize: 30);
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _rows = r.items;
        _error = null;
      });
    } catch (e) {
      if (!mounted || epoch != _epoch) return;
      setState(() => _error = AppFailure.from(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SearchField(
          hint: 'Ünvan, vergi no, şehir',
          onChanged: (q) => unawaited(_load(q)),
        ),
        const SizedBox(height: 8),
        if (_error != null)
          FailureView(
            failure: _error!,
            compact: true,
            onRetry: () => unawaited(_load('')),
          )
        else if (rows == null)
          const Padding(padding: EdgeInsets.all(24), child: LoadingView())
        else if (rows.isEmpty)
          const EmptyState(
            compact: true,
            title: 'Cari bulunamadı',
            illustration: AknIllustration.search,
          )
        else
          for (final r in rows)
            AknListTile(
              padding: const EdgeInsets.symmetric(vertical: 8),
              leading: AknAvatar(name: r.title, size: 36),
              title: r.title,
              subtitle: [?r.code, ?r.place].join(' · '),
              onTap: () => Navigator.of(context).pop(r),
            ),
      ],
    );
  }
}
