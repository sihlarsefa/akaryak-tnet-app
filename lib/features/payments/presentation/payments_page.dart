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
import '../../approvals/api.dart';
import '../application/payments_providers.dart';
import '../copy.dart';
import '../data/payment_models.dart';
import '../data/payments_repository.dart';
import 'widgets/customer_picker.dart';
import 'widgets/payment_cards.dart';
import 'widgets/status_sheets.dart';

enum PaymentsTab { payments, instruments }

/// Çek / senet durumunu değiştirebilir mi (StationPayments Düzenler + yönetim ya da güncelleme yetkinliği).
bool canChangeInstruments(AccessPolicy p) =>
    p.can(Pg.stationPayments, Perm.edit) &&
    (p.hasCap(Caps.paymentInstrumentManage) ||
        p.hasCap(Caps.paymentStatusUpdate));

/// Tahsilat (spec A.4 A5): ödemeler (geciken, cari, durum süzgeçleri) ve çek / senet portföyü
/// (vadeleriyle). Satıra dokununca ödeme ayrıntısı ya da belge sayfası açılır.
class PaymentsPage extends ConsumerStatefulWidget {
  const PaymentsPage({super.key, this.initialTab = PaymentsTab.payments});

  /// Derin bağlantı: `/payments?tab=instruments`.
  final PaymentsTab initialTab;

  @override
  ConsumerState<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends ConsumerState<PaymentsPage> {
  late PaymentsTab _tab = widget.initialTab;
  PaymentsQuery _payments = const PaymentsQuery();
  InstrumentsQuery _instruments = const InstrumentsQuery();
  final _paySearch = TextEditingController();
  final _insSearch = TextEditingController();

  @override
  void dispose() {
    _paySearch.dispose();
    _insSearch.dispose();
    super.dispose();
  }

  // Tek seçimli çipler (Onaylarım sekmeleriyle aynı; `AknSegmented` kontrastı için bkz.
  // contract-changes.md A5).
  Widget _tabs() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: FilterChips<PaymentsTab>(
      options: const [
        FilterOption(
          value: PaymentsTab.payments,
          label: PaymentsCopy.paymentsTab,
          icon: Icons.payments_rounded,
        ),
        FilterOption(
          value: PaymentsTab.instruments,
          label: PaymentsCopy.instrumentsTab,
          icon: Icons.receipt_long_rounded,
        ),
      ],
      selected: {_tab},
      allowEmpty: false,
      onChanged: (s) => setState(() => _tab = s.first),
    ),
  );

  Future<void> _pickCustomer() async {
    final pick = await showCustomerPicker(context, current: _payments.customer);
    if (!mounted || pick == null) return;
    setState(() {
      _payments = _payments.copyWith(
        customer: () => switch (pick) {
          CustomerPicked(:final customer) => customer,
          CustomerCleared() => null,
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final refreshing = _tab == PaymentsTab.payments
        ? ref.watch(paymentsListProvider(_payments)).refreshing
        : ref.watch(instrumentsListProvider(_instruments)).refreshing;
    return AppScaffold(
      title: PaymentsCopy.title,
      subtitle: ref.watch(accessPolicyProvider).access?.stationTitle,
      refreshing: refreshing,
      body: FadeThroughSwitcher(
        child: _tab == PaymentsTab.payments
            ? KeyedSubtree(
                key: const ValueKey('payments'),
                child: _paymentsList(),
              )
            : KeyedSubtree(
                key: const ValueKey('instruments'),
                child: _instrumentsList(),
              ),
      ),
    );
  }

  Widget _paymentsList() {
    final q = _payments;
    final state = ref.watch(paymentsListProvider(q));
    final ctrl = ref.read(paymentsListProvider(q).notifier);
    final customer = q.customer;
    return A5PagedListView<PaymentRow>(
      state: state,
      staggerKey: q,
      onRefresh: ctrl.refresh,
      onLoadMore: () => unawaited(ctrl.loadMore()),
      header: [
        _tabs(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SearchField(
            controller: _paySearch,
            hint: PaymentsCopy.searchPayments,
            onChanged: (s) => setState(
              () => _payments = _payments.copyWith(search: s.trim()),
            ),
          ),
        ),
        FilterChips<PaymentStatus>(
          multi: true,
          options: [
            for (final s in const [
              PaymentStatus.pending,
              PaymentStatus.documentUploaded,
              PaymentStatus.collected,
              PaymentStatus.bounced,
              PaymentStatus.refunded,
              PaymentStatus.cancelled,
            ])
              FilterOption(
                value: s,
                label: s.label,
                icon: AknStatus.payment(s).icon,
              ),
          ],
          selected: q.statuses,
          onChanged: (s) =>
              setState(() => _payments = _payments.copyWith(statuses: s)),
        ),
        FilterChips<String>(
          multi: true,
          options: [
            const FilterOption(
              value: 'overdue',
              label: 'Gecikenler',
              icon: Icons.alarm_off_rounded,
            ),
            FilterOption(
              value: 'customer',
              label: customer == null
                  ? 'Cari: tümü'
                  : 'Cari: ${customer.title}',
              icon: Icons.apartment_rounded,
            ),
          ],
          selected: {
            if (q.overdueOnly) 'overdue',
            if (customer != null) 'customer',
          },
          onChanged: (s) {
            final overdue = s.contains('overdue');
            if (overdue != q.overdueOnly) {
              setState(
                () => _payments = _payments.copyWith(overdueOnly: overdue),
              );
            } else {
              unawaited(_pickCustomer());
            }
          },
        ),
      ],
      itemBuilder: (context, row, _) => PaymentRowCard(
        row: row,
        onTap: () => context.push(AppRoutes.payment(row.orderId)),
      ),
      empty: q.isFiltered
          ? EmptyState(
              title: PaymentsCopy.filteredTitle,
              message: PaymentsCopy.filteredMessage,
              illustration: AknIllustration.search,
              actionLabel: PaymentsCopy.clearFilters,
              onAction: () => setState(() {
                _payments = const PaymentsQuery();
                _paySearch.clear();
              }),
            )
          : const EmptyState(
              title: PaymentsCopy.emptyPaymentsTitle,
              message: PaymentsCopy.emptyPaymentsMessage,
              illustration: AknIllustration.payments,
            ),
    );
  }

  Widget _instrumentsList() {
    final q = _instruments;
    final state = ref.watch(instrumentsListProvider(q));
    final ctrl = ref.read(instrumentsListProvider(q).notifier);
    final canChange = canChangeInstruments(ref.watch(accessPolicyProvider));
    return A5PagedListView<Instrument>(
      state: state,
      staggerKey: q,
      onRefresh: ctrl.refresh,
      onLoadMore: () => unawaited(ctrl.loadMore()),
      header: [
        _tabs(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SearchField(
            controller: _insSearch,
            hint: PaymentsCopy.searchInstruments,
            onChanged: (s) => setState(
              () => _instruments = _instruments.copyWith(search: s.trim()),
            ),
          ),
        ),
        FilterChips<InstrumentFilter>(
          options: [
            for (final f in InstrumentFilter.values)
              FilterOption(value: f, label: f.label),
          ],
          selected: {q.filter},
          allowEmpty: false,
          onChanged: (s) => setState(
            () => _instruments = _instruments.copyWith(filter: s.first),
          ),
        ),
        FilterChips<InstrumentKind>(
          options: [
            for (final k in const [
              InstrumentKind.cheque,
              InstrumentKind.promissoryNote,
              InstrumentKind.letterOfGuarantee,
            ])
              FilterOption(
                value: k,
                label: k.label,
                icon: AknStatus.instrumentKind(k).icon,
              ),
          ],
          selected: {?q.kind},
          onChanged: (s) => setState(
            () => _instruments = _instruments.copyWith(
              kind: () => s.isEmpty ? null : s.first,
            ),
          ),
        ),
      ],
      itemBuilder: (context, i, _) => InstrumentRowCard(
        instrument: i,
        onTap: () async {
          final message = await showInstrumentSheet(
            context,
            instrument: i,
            canChange: canChange,
          );
          if (message != null && context.mounted) {
            AppToast.success(message, context: context);
          }
        },
      ),
      empty: q.isFiltered
          ? EmptyState(
              title: PaymentsCopy.filteredTitle,
              message: PaymentsCopy.filteredMessage,
              illustration: AknIllustration.search,
              actionLabel: PaymentsCopy.clearFilters,
              onAction: () => setState(() {
                _instruments = const InstrumentsQuery();
                _insSearch.clear();
              }),
            )
          : const EmptyState(
              title: PaymentsCopy.emptyInstrumentsTitle,
              message: PaymentsCopy.emptyInstrumentsMessage,
              illustration: AknIllustration.payments,
            ),
    );
  }
}
