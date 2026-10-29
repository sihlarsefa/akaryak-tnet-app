import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/access_policy.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/models/enums.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/turkish_text.dart';
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

/// Tahsilat (tasarım v4 "Sade" §3.2, P7).
///
/// * Bant: "Tahsilat" ve canlı durum satırı ("Vadesi geçen 2 ödeme · 184.000 ₺"); ⌕ (bandın altında
///   açılan arama şeridi) ve Filtre (ödemelerde cari, gecikenler ve durumlar; portföyde durum ve
///   tür).
/// * Tek seçici: [Ödemeler n | Çek / senet n] (AknSegmented); görünüm değişince içerik solarak geçer.
/// * Satırlar defterde (tek beyaz kart, araları ince çizgi); kart yığını, çip satırı ve arama kuyusu
///   yok. Karta dokununca ödeme ayrıntısı ya da belge sayfası açılır.
/// * Derin bağlantı: `?tab=instruments`, `?filter=overdue` (gecikenler), `?filter=documents`
///   (kontrol bekleyen belgeler).
class PaymentsPage extends ConsumerStatefulWidget {
  const PaymentsPage({
    super.key,
    this.initialTab = PaymentsTab.payments,
    this.initialFilter,
  });

  /// Derin bağlantı: `/payments?tab=instruments`.
  final PaymentsTab initialTab;

  /// Derin bağlantı: `/payments?filter=overdue|documents|bounced`.
  final String? initialFilter;

  /// `filter` sorgu değerinden ödemeler süzgeci.
  static PaymentsQuery queryFor(String? raw) =>
      switch (TurkishText.searchKey(raw ?? '')) {
        'overdue' || 'gecikenler' => const PaymentsQuery(overdueOnly: true),
        'documents' || 'belgeler' => const PaymentsQuery(
          statuses: {PaymentStatus.documentUploaded},
        ),
        // Ana sayfanın "Karşılıksız çıkan n ödeme" satırı (v4 tur 2).
        'bounced' ||
        'karsiliksiz' => const PaymentsQuery(statuses: {PaymentStatus.bounced}),
        _ => const PaymentsQuery(),
      };

  @override
  ConsumerState<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends ConsumerState<PaymentsPage> {
  late PaymentsTab _tab = widget.initialTab;
  late PaymentsQuery _payments = PaymentsPage.queryFor(widget.initialFilter);
  InstrumentsQuery _instruments = const InstrumentsQuery();
  bool _searchOpen = false;

  /// Bandın durum satırı: geciken ödemeler (sayı ve tutar).
  static const _overdueQuery = PaymentsQuery(overdueOnly: true);

  void _setTab(PaymentsTab t) {
    if (t == _tab) return;
    setState(() {
      _tab = t;
      _searchOpen = false;
    });
  }

  /// Cari seçici (Filtre sayfasından); seçilen süzgeç sayfaya ve Filtre sayfasına döner.
  Future<PaymentsQuery?> _pickCustomer() async {
    final pick = await showCustomerPicker(context, current: _payments.customer);
    if (!mounted || pick == null) return null;
    setState(() {
      _payments = _payments.copyWith(
        customer: () => switch (pick) {
          CustomerPicked(:final customer) => customer,
          CustomerCleared() => null,
        },
      );
    });
    return _payments;
  }

  /// Etkin süzgeç sayısı (Filtre düğmesinin rozeti; arama hariç).
  int get _activeFilters {
    if (_tab == PaymentsTab.payments) {
      final q = _payments;
      return (q.customer == null ? 0 : 1) +
          (q.overdueOnly ? 1 : 0) +
          (setEquals(q.statuses, defaultPaymentStatuses) ? 0 : 1);
    }
    final q = _instruments;
    return (q.kind == null ? 0 : 1) +
        (q.filter == InstrumentFilter.open ? 0 : 1);
  }

  /// "Vadesi geçen 2 ödeme · 184.000 ₺" (tutar yalnızca hepsi yüklüyse ve bant darsa yazılmaz).
  Object _status(PagedState<PaymentRow> overdue, {required bool narrow}) {
    if (!overdue.hasData) return '';
    final n = overdue.totalCount;
    if (n <= 0) return PaymentsCopy.calmStatus;
    final complete = !overdue.hasMore && overdue.items.length >= n;
    final sum = overdue.items.fold<double>(
      0,
      (a, r) => a + (r.displayAmount ?? 0),
    );
    return [
      AknStatusClause.overdue(PaymentsCopy.overdueStatus(n)),
      if (complete && sum > 0 && !narrow) AknStatusClause(Fmt.moneyWhole(sum)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pay = ref.watch(paymentsListProvider(_payments));
    final ins = ref.watch(instrumentsListProvider(_instruments));
    final overdue = ref.watch(paymentsListProvider(_overdueQuery));
    final refreshing = _tab == PaymentsTab.payments
        ? pay.refreshing
        : ins.refreshing;
    final switcher = _TabSwitcher(
      value: _tab,
      payments: pay.hasData ? pay.totalCount : null,
      instruments: ins.hasData ? ins.totalCount : null,
      onChanged: _setTab,
    );
    final searching = _tab == PaymentsTab.payments
        ? _payments.search
        : _instruments.search;
    final leading = bandPageLeading(context);
    // Bant geri / ana sayfa düğmesiyle daralınca durum satırı kısa söylenir (tek satır, kesilmez).
    final narrow =
        leading != null ||
        (ModalRoute.of(context)?.impliesAppBarDismissal ?? false);
    return AppScaffold(
      title: PaymentsCopy.title,
      bandIcon: PhosphorIconsRegular.wallet,
      // Alt menüde değilse (Diğer'den) de bantla görünür.
      largeTitle: true,
      leading: leading,
      status: _status(overdue, narrow: narrow),
      refreshing: refreshing,
      actions: [
        AknSearchReveal.button(
          semanticLabel: _tab == PaymentsTab.payments
              ? 'Ödemelerde ara'
              : 'Çek ve senetlerde ara',
          onPressed: () => setState(() => _searchOpen = true),
        ),
        AknFilterButton(
          count: _activeFilters,
          sheetBuilder: (_) => _tab == PaymentsTab.payments
              ? _PaymentFilters(
                  query: _payments,
                  onChanged: (q) => setState(() => _payments = q),
                  onPickCustomer: _pickCustomer,
                )
              : _InstrumentFilters(
                  query: _instruments,
                  onChanged: (q) => setState(() => _instruments = q),
                ),
        ),
      ],
      body: Column(
        children: [
          AknSearchReveal(
            key: ValueKey(_tab),
            open: _searchOpen || searching.isNotEmpty,
            hint: _tab == PaymentsTab.payments
                ? PaymentsCopy.searchPayments
                : PaymentsCopy.searchInstruments,
            onChanged: (s) => setState(() {
              if (_tab == PaymentsTab.payments) {
                _payments = _payments.copyWith(search: s.trim());
              } else {
                _instruments = _instruments.copyWith(search: s.trim());
              }
            }),
            onClose: () => setState(() {
              _searchOpen = false;
              _payments = _payments.copyWith(search: '');
              _instruments = _instruments.copyWith(search: '');
            }),
          ),
          Expanded(
            child: FadeThroughSwitcher(
              child: _tab == PaymentsTab.payments
                  ? KeyedSubtree(
                      key: const ValueKey('payments'),
                      child: _paymentsList(pay, switcher),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('instruments'),
                      child: _instrumentsList(ins, switcher),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentsList(PagedState<PaymentRow> state, Widget switcher) {
    final q = _payments;
    final ctrl = ref.read(paymentsListProvider(q).notifier);
    return A5PagedListView<PaymentRow>(
      state: state,
      ledger: true,
      staggerKey: q,
      onRefresh: () async {
        ref.invalidate(paymentsListProvider(_overdueQuery));
        await ctrl.refresh();
      },
      onLoadMore: () => unawaited(ctrl.loadMore()),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
      header: [const SizedBox(height: 4), switcher, const SizedBox(height: 6)],
      itemBuilder: (context, row, i) => PaymentRowCard(
        row: row,
        onTap: () => context.push(AppRoutes.payment(row.orderId)),
      ),
      footer: !q.isFiltered && !state.hasMore
          ? const ListFootnote(PaymentsCopy.paymentsFootnote)
          : null,
      empty: q.isFiltered
          ? EmptyState.compact(
              title: q.search.isEmpty
                  ? PaymentsCopy.filteredTitle
                  : "'${q.search}' için sonuç yok",
              message: PaymentsCopy.filteredMessage,
              illustration: AknIllustration.search,
              actionLabel: PaymentsCopy.clearFilters,
              onAction: () => setState(() {
                _payments = const PaymentsQuery();
                _searchOpen = false;
              }),
            )
          : const EmptyState(
              title: PaymentsCopy.emptyPaymentsTitle,
              message: PaymentsCopy.emptyPaymentsMessage,
              illustration: AknIllustration.payments,
            ),
    );
  }

  Widget _instrumentsList(PagedState<Instrument> state, Widget switcher) {
    final q = _instruments;
    final ctrl = ref.read(instrumentsListProvider(q).notifier);
    final canChange = canChangeInstruments(ref.watch(accessPolicyProvider));
    return A5PagedListView<Instrument>(
      state: state,
      ledger: true,
      staggerKey: q,
      onRefresh: ctrl.refresh,
      onLoadMore: () => unawaited(ctrl.loadMore()),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
      header: [const SizedBox(height: 4), switcher, const SizedBox(height: 6)],
      itemBuilder: (context, i, index) => InstrumentRowCard(
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
      footer: q.filter == InstrumentFilter.open && !state.hasMore
          ? const ListFootnote(PaymentsCopy.instrumentsFootnote)
          : null,
      empty: q.isFiltered
          ? EmptyState.compact(
              title: q.search.isEmpty
                  ? PaymentsCopy.filteredTitle
                  : "'${q.search}' için sonuç yok",
              message: PaymentsCopy.filteredMessage,
              illustration: AknIllustration.search,
              actionLabel: PaymentsCopy.clearFilters,
              onAction: () => setState(() {
                _instruments = const InstrumentsQuery();
                _searchOpen = false;
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

/// Tek seçici (v4 P7): [Ödemeler n | Çek / senet n]; büyük yazıda aynı seçim tek satır çiplerle.
class _TabSwitcher extends StatelessWidget {
  const _TabSwitcher({
    required this.value,
    required this.payments,
    required this.instruments,
    required this.onChanged,
  });

  final PaymentsTab value;
  final int? payments;
  final int? instruments;
  final ValueChanged<PaymentsTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = [
      FilterOption(
        value: PaymentsTab.payments,
        label: PaymentsCopy.paymentsTab,
        count: (payments ?? 0) > 0 ? payments : null,
      ),
      FilterOption(
        value: PaymentsTab.instruments,
        label: PaymentsCopy.instrumentsTab,
        count: (instruments ?? 0) > 0 ? instruments : null,
      ),
    ];
    if (isLargeText(context)) {
      return FilterChips<PaymentsTab>(
        options: options,
        selected: {value},
        allowEmpty: false,
        onChanged: (s) {
          final v = s.firstOrNull;
          if (v != null) onChanged(v);
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: AknSegmented<PaymentsTab>(
        segments: options,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// Sayfa başlığı (Filtre sayfasının bölüm adı).
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: context.aknText.label.copyWith(
          fontWeight: FontWeight.w700,
          color: context.akn.dim,
        ),
      ),
    ),
  );
}

/// Ödemeler süzgeci (Filtre sayfası): cari, gecikenler ve durumlar; seçim hemen uygulanır.
class _PaymentFilters extends StatefulWidget {
  const _PaymentFilters({
    required this.query,
    required this.onChanged,
    required this.onPickCustomer,
  });

  final PaymentsQuery query;
  final ValueChanged<PaymentsQuery> onChanged;
  final Future<PaymentsQuery?> Function() onPickCustomer;

  @override
  State<_PaymentFilters> createState() => _PaymentFiltersState();
}

class _PaymentFiltersState extends State<_PaymentFilters> {
  late PaymentsQuery _q = widget.query;

  void _set(PaymentsQuery q) {
    setState(() => _q = q);
    widget.onChanged(q);
  }

  @override
  Widget build(BuildContext context) {
    final customer = _q.customer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Caption('Cari'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AknChip(
              label: customer == null
                  ? PaymentsCopy.allCustomers
                  : 'Cari: ${customer.title}',
              icon: PhosphorIconsRegular.caretUpDown,
              selected: customer != null,
              semanticLabel: customer == null
                  ? 'Cari süzgeci: tüm cariler. Cari seçmek için dokunun.'
                  : 'Cari süzgeci: ${customer.title}. Değiştirmek için dokunun.',
              onTap: () async {
                final next = await widget.onPickCustomer();
                if (next != null && mounted) setState(() => _q = next);
              },
            ),
            AknChip(
              label: PaymentsCopy.overdue,
              selected: _q.overdueOnly,
              onTap: () => _set(_q.copyWith(overdueOnly: !_q.overdueOnly)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const _Caption('Durum'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in PaymentsCopy.statusFilters)
              AknChip(
                label: s.label,
                selected: _q.statuses.contains(s),
                onTap: () {
                  final next = Set<PaymentStatus>.of(_q.statuses);
                  if (!next.remove(s)) next.add(s);
                  _set(_q.copyWith(statuses: next));
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Portföy süzgeci (Filtre sayfası): durum ve tür; seçim hemen uygulanır.
class _InstrumentFilters extends StatefulWidget {
  const _InstrumentFilters({required this.query, required this.onChanged});

  final InstrumentsQuery query;
  final ValueChanged<InstrumentsQuery> onChanged;

  @override
  State<_InstrumentFilters> createState() => _InstrumentFiltersState();
}

class _InstrumentFiltersState extends State<_InstrumentFilters> {
  late InstrumentsQuery _q = widget.query;

  void _set(InstrumentsQuery q) {
    setState(() => _q = q);
    widget.onChanged(q);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      const _Caption('Durum'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final f in InstrumentFilter.values)
            AknChip(
              label: f.label,
              selected: _q.filter == f,
              onTap: () => _set(_q.copyWith(filter: f)),
            ),
        ],
      ),
      const SizedBox(height: 12),
      const _Caption('Tür'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final k in const [
            InstrumentKind.cheque,
            InstrumentKind.promissoryNote,
            InstrumentKind.letterOfGuarantee,
          ])
            AknChip(
              label: k.label,
              selected: _q.kind == k,
              onTap: () =>
                  _set(_q.copyWith(kind: () => _q.kind == k ? null : k)),
            ),
        ],
      ),
      const SizedBox(height: 8),
    ],
  );
}
