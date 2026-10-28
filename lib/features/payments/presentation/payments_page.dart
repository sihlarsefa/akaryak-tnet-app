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

/// Tahsilat (spec A.4 A5; tasarım v3 "Akış"): kök başlık, "Ödemeler" ve "Çek / senet" sekmeleri
/// (sekme değişince içerik solarak geçer), arama kuyusu, tek satır süzgeç çipleri ve beyaz kartlar
/// (art arda yükselerek gelir, süzgeç değişince yeniden). Ödemeler: geciken, cari ve durum
/// süzgeçleri; portföy: durum ve tür süzgeçleri, vadeleriyle. Karta dokununca ödeme ayrıntısı ya da
/// belge sayfası açılır.
class PaymentsPage extends ConsumerStatefulWidget {
  const PaymentsPage({super.key, this.initialTab = PaymentsTab.payments});

  /// Derin bağlantı: `/payments?tab=instruments`.
  final PaymentsTab initialTab;

  @override
  ConsumerState<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends ConsumerState<PaymentsPage>
    with SingleTickerProviderStateMixin {
  late PaymentsTab _tab = widget.initialTab;
  late final TabController _tabs = TabController(
    length: PaymentsTab.values.length,
    vsync: this,
    initialIndex: widget.initialTab.index,
  )..addListener(_onTab);
  PaymentsQuery _payments = const PaymentsQuery();
  InstrumentsQuery _instruments = const InstrumentsQuery();
  final _paySearch = TextEditingController();
  final _insSearch = TextEditingController();

  void _onTab() {
    final next = PaymentsTab.values[_tabs.index];
    if (next != _tab) setState(() => _tab = next);
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTab)
      ..dispose();
    _paySearch.dispose();
    _insSearch.dispose();
    super.dispose();
  }

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

  PreferredSizeWidget _tabBar(int? payments, int? instruments) {
    Widget label(String text, int? count) => Text.rich(
      TextSpan(
        text: text,
        children: [
          if (count != null)
            TextSpan(
              text: ' $count',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontFeatures: AknNumerals.tabular,
              ),
            ),
        ],
      ),
      maxLines: 1,
    );
    return PreferredSize(
      preferredSize: const Size.fromHeight(48),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            tabs: [
              Tab(height: 46, child: label(PaymentsCopy.paymentsTab, payments)),
              Tab(
                height: 46,
                child: label(PaymentsCopy.instrumentsTab, instruments),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pay = ref.watch(paymentsListProvider(_payments));
    final ins = ref.watch(instrumentsListProvider(_instruments));
    final refreshing = _tab == PaymentsTab.payments
        ? pay.refreshing
        : ins.refreshing;
    return AppScaffold(
      title: PaymentsCopy.title,
      refreshing: refreshing,
      bottom: _tabBar(
        pay.hasData ? pay.totalCount : null,
        ins.hasData ? ins.totalCount : null,
      ),
      body: FadeThroughSwitcher(
        child: _tab == PaymentsTab.payments
            ? KeyedSubtree(
                key: const ValueKey('payments'),
                child: _paymentsList(pay),
              )
            : KeyedSubtree(
                key: const ValueKey('instruments'),
                child: _instrumentsList(ins),
              ),
      ),
    );
  }

  Widget _search(
    TextEditingController ctrl,
    String hint,
    ValueChanged<String> on,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
    child: SearchField(controller: ctrl, hint: hint, onChanged: on),
  );

  Widget _paymentsList(PagedState<PaymentRow> state) {
    final q = _payments;
    final ctrl = ref.read(paymentsListProvider(q).notifier);
    final customer = q.customer;
    void toggle(PaymentStatus s) {
      final next = Set<PaymentStatus>.of(q.statuses);
      if (!next.remove(s)) next.add(s);
      setState(() => _payments = _payments.copyWith(statuses: next));
    }

    return A5PagedListView<PaymentRow>(
      state: state,
      staggerKey: q,
      onRefresh: ctrl.refresh,
      onLoadMore: () => unawaited(ctrl.loadMore()),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
      itemSpacing: 12,
      header: [
        _search(
          _paySearch,
          PaymentsCopy.searchPayments,
          (s) =>
              setState(() => _payments = _payments.copyWith(search: s.trim())),
        ),
        ChipRow(
          leading: [
            AknChip(
              label: customer == null
                  ? PaymentsCopy.allCustomers
                  : 'Cari: ${customer.title}',
              icon: PhosphorIconsRegular.caretUpDown,
              selected: customer != null,
              semanticLabel: customer == null
                  ? 'Cari süzgeci: tüm cariler. Cari seçmek için dokunun.'
                  : 'Cari süzgeci: ${customer.title}. Değiştirmek için dokunun.',
              onTap: () => unawaited(_pickCustomer()),
            ),
            AknChip(
              label: PaymentsCopy.overdue,
              selected: q.overdueOnly,
              onTap: () => setState(
                () =>
                    _payments = _payments.copyWith(overdueOnly: !q.overdueOnly),
              ),
            ),
          ],
          trailing: [
            for (final s in PaymentsCopy.statusFilters)
              AknChip(
                label: s.label,
                selected: q.statuses.contains(s),
                onTap: () => toggle(s),
              ),
          ],
        ),
      ],
      itemBuilder: (context, row, i) => LedgerItem(
        index: i,
        child: PaymentRowCard(
          row: row,
          onTap: () => context.push(AppRoutes.payment(row.orderId)),
        ),
      ),
      footer: !q.isFiltered && !state.hasMore
          ? const ListFootnote(PaymentsCopy.paymentsFootnote)
          : null,
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

  Widget _instrumentsList(PagedState<Instrument> state) {
    final q = _instruments;
    final ctrl = ref.read(instrumentsListProvider(q).notifier);
    final canChange = canChangeInstruments(ref.watch(accessPolicyProvider));
    return A5PagedListView<Instrument>(
      state: state,
      staggerKey: q,
      onRefresh: ctrl.refresh,
      onLoadMore: () => unawaited(ctrl.loadMore()),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
      itemSpacing: 12,
      header: [
        _search(
          _insSearch,
          PaymentsCopy.searchInstruments,
          (s) => setState(
            () => _instruments = _instruments.copyWith(search: s.trim()),
          ),
        ),
        ChipRow(
          leading: [
            for (final f in InstrumentFilter.values)
              AknChip(
                label: f.label,
                selected: q.filter == f,
                onTap: () => setState(
                  () => _instruments = _instruments.copyWith(filter: f),
                ),
              ),
          ],
          trailing: [
            for (final k in const [
              InstrumentKind.cheque,
              InstrumentKind.promissoryNote,
              InstrumentKind.letterOfGuarantee,
            ])
              AknChip(
                label: k.label,
                selected: q.kind == k,
                onTap: () => setState(
                  () => _instruments = _instruments.copyWith(
                    kind: () => q.kind == k ? null : k,
                  ),
                ),
              ),
          ],
        ),
      ],
      itemBuilder: (context, i, index) => LedgerItem(
        index: index,
        child: InstrumentRowCard(
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
      ),
      footer: q.filter == InstrumentFilter.open && !state.hasMore
          ? const ListFootnote(PaymentsCopy.instrumentsFootnote)
          : null,
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
