import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/cm_access.dart';
import '../../application/documents_controller.dart';
import '../../copy.dart';
import '../../data/customer_more_repository.dart';
import '../../data/documents.dart';
import '../cm_widgets.dart';
import 'document_viewer.dart';

/// Tarih aralığı seçenekleri (sunucu en geniş 366 gün; boş = son 3 ay).
enum _Range {
  last3('Son 3 ay'),
  last30('Son 30 gün'),
  thisYear('Bu yıl'),
  last12('Son 12 ay');

  const _Range(this.label);
  final String label;

  DocumentArchiveQuery apply(DocumentArchiveQuery q) {
    final today = TrTime.startOfDay(TrTime.now());
    return switch (this) {
      last3 => q.copyWith(clearRange: true),
      last30 => q.copyWith(
        from: today.subtract(const Duration(days: 30)),
        to: today,
      ),
      thisYear => q.copyWith(
        from: TrTime.fromWall(TrTime.wall(today).year),
        to: today,
      ),
      last12 => q.copyWith(
        from: today.subtract(const Duration(days: 365)),
        to: today,
      ),
    };
  }

  static _Range of(DocumentArchiveQuery q) {
    if (q.from == null) return last3;
    final days = q.to == null ? 0 : q.to!.difference(q.from!).inDays;
    if (days <= 31) return last30;
    if (days >= 360) return last12;
    return thisYear;
  }
}

/// Belgeler: belge arşivi (sipariş × sevkiyat satırları, `{totals, items}`) ve cihazda üretilen PDF'ler
/// (Sipariş formu, Teklif (sürüm başına), Mutabakat, Teslim tutanağı, Sevk belgesi).
class DocumentsPage extends ConsumerStatefulWidget {
  const DocumentsPage({super.key, this.orderId});

  /// Derin bağlantı: `/documents?orderId=12` o siparişin belgelerini açar.
  final int? orderId;

  @override
  ConsumerState<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends ConsumerState<DocumentsPage> {
  bool _openedDeepLink = false;

  @override
  void initState() {
    super.initState();
    final id = widget.orderId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _openedDeepLink) return;
        _openedDeepLink = true;
        unawaited(showOrderDocumentsSheet(context, orderId: id));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(documentsControllerProvider);
    final ctrl = ref.read(documentsControllerProvider.notifier);
    final policy = ref.watch(accessPolicyProvider);
    final q = s.query;
    final range = _Range.of(q);
    final totals = s.totals;
    return AppScaffold(
      title: CmCopy.documentsTitle,
      subtitle: s.page.loading && s.page.isEmpty
          ? null
          : '${totals.orderCount} sipariş · ${totals.shipmentCount} sevkiyat',
      refreshing: s.page.refreshing,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SearchField(
              hint: 'Sipariş no, SVK / TT kodu, plaka ara',
              onChanged: (v) => ctrl.setQuery(q.copyWith(search: v.trim())),
            ),
          ),
          FilterChips<_Range>(
            options: [
              for (final r in _Range.values)
                FilterOption(value: r, label: r.label),
            ],
            selected: {range},
            allowEmpty: false,
            onChanged: (set) {
              final r = set.firstOrNull;
              if (r != null) ctrl.setQuery(r.apply(q));
            },
          ),
          CmSegmented<ArchiveShipmentFilter>(
            segments: [
              for (final f in ArchiveShipmentFilter.values)
                FilterOption(value: f, label: f.label),
            ],
            value: q.shipment,
            onChanged: (f) => ctrl.setQuery(q.copyWith(shipment: f)),
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          ),
          if (s.page.fromCache) CachedNote(storedAt: s.page.storedAt),
          const SizedBox(height: 4),
          Expanded(
            child: _List(state: s, policy: policy),
          ),
        ],
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.state, required this.policy});

  final DocumentsState state;
  final AccessPolicy policy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(documentsControllerProvider.notifier);
    final p = state.page;
    if (p.showSkeleton) return const SkeletonList(itemCount: 5, lines: 3);
    if (p.isEmpty) {
      final err = p.error;
      final filtered = !state.query.isDefault;
      final Widget child = err != null
          ? CmFailureView(failure: err, onRetry: ctrl.load)
          : (filtered
                ? EmptyState(
                    title: CmCopy.filteredEmpty,
                    message:
                        'Tarih aralığını genişletmeyi ya da aramayı değiştirmeyi deneyin.',
                    illustration: AknIllustration.search,
                    actionLabel: CmCopy.clearFilters,
                    onAction: () => ctrl.setQuery(const DocumentArchiveQuery()),
                  )
                : const EmptyState(
                    title: CmCopy.documentsEmpty,
                    message: CmCopy.documentsEmptyMessage,
                    illustration: AknIllustration.documents,
                  ));
      return PullToRefresh(
        onRefresh: () => ctrl.load(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [child],
        ),
      );
    }
    return PullToRefresh(
      onRefresh: () => ctrl.load(refresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 400) ctrl.loadMore();
          return false;
        },
        child: StaggerScope(
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            itemCount: p.items.length + 2,
            itemBuilder: (context, i) {
              if (i == p.items.length) {
                return LoadMoreFooter(
                  loading: p.loadingMore,
                  error: p.loadMoreError,
                  onRetry: ctrl.loadMore,
                );
              }
              if (i == p.items.length + 1) return const _FooterNote();
              final row = p.items[i];
              return StaggerItem(
                index: i,
                child: ArchiveRowCard(
                  row: row,
                  policy: policy,
                  onOpenAll: () => showOrderDocumentsSheet(
                    context,
                    orderId: row.orderId,
                    rows: [
                      for (final r in p.items)
                        if (r.orderId == row.orderId) r,
                    ],
                  ),
                  onOpen: (req) => openGeneratedDocument(context, ref, req),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: c.dim),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              CmCopy.documentsFooter,
              style: t.caption.copyWith(color: c.dim),
            ),
          ),
        ],
      ),
    );
  }
}

/// Arşiv satırı: sipariş, (varsa) sevkiyat ve hızlı belge düğmeleri.
class ArchiveRowCard extends StatelessWidget {
  const ArchiveRowCard({
    super.key,
    required this.row,
    required this.policy,
    required this.onOpenAll,
    required this.onOpen,
  });

  final DocumentArchiveRow row;
  final AccessPolicy policy;
  final VoidCallback onOpenAll;
  final void Function(DocRequest r) onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final r = row;
    final quick = <DocRequest>[
      if (policy.cmOrderDocuments) OrderDocRequest(r.orderId, r.orderNumber),
      if (policy.cmOrderDocuments && r.hasQuote)
        QuoteDocRequest(r.orderId, r.orderNumber, r.quoteVersion!),
      if (policy.cmOrderDocuments && r.canReconcile)
        ReconciliationDocRequest(r.orderId, r.orderNumber),
      if (policy.cmShipmentDocuments && r.canReceipt)
        ReceiptDocRequest(r.shipmentId!),
      if (policy.cmShipmentDocuments && r.canWaybill)
        WaybillDocRequest(r.shipmentId!),
    ];
    final ship = r.shipmentStatus;
    return AknCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      onTap: onOpenAll,
      semanticLabel:
          '${r.orderNumber}, ${r.status.label}, ${r.productName} ${Fmt.liters(r.quantityLiters)}'
          '${r.hasShipment ? ', ${r.shipmentCode}, ${ship?.label ?? ''}' : ', sevkiyat yok'}'
          ', ${quick.length} belge',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CmHeadRow(
                  title: Text(r.orderNumber, style: t.bodyStrong),
                  trailing: StatusChip.style(
                    r.status.statusStyle,
                    size: StatusChipSize.small,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${r.productName} · ${Fmt.liters(r.quantityLiters)} · ${Fmt.date(r.orderDate)}',
                  style: t.bodySmall,
                ),
                Text(
                  [
                    r.stationTitle,
                    ?r.deliveryPointName,
                  ].where((x) => x.isNotEmpty).join(' · '),
                  style: t.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (r.hasShipment) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: AknRadius.chip,
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(r.shipmentCode!, style: t.label),
                        if (ship != null)
                          StatusChip.style(
                            ship.statusStyle,
                            size: StatusChipSize.small,
                          ),
                        Text(
                          r.deliveredAt != null
                              ? 'Teslim ${Fmt.date(r.deliveredAt)} · ${Fmt.liters(r.deliveredLiters)}'
                              : 'Plan ${Fmt.date(r.scheduledAt)} · ${Fmt.liters(r.plannedLiters)}',
                          style: t.caption.copyWith(color: c.text),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (quick.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 0,
              children: [
                for (final req in quick)
                  ActionChip(
                    avatar: Icon(
                      DocumentTile.iconOf(req.kind),
                      size: 16,
                      color: c.brandInk,
                    ),
                    label: Text(_shortLabel(req)),
                    tooltip: '${req.label} PDF',
                    onPressed: () => onOpen(req),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _shortLabel(DocRequest r) => switch (r) {
    OrderDocRequest() => 'Sipariş formu',
    QuoteDocRequest(:final version) => 'Teklif v$version',
    ReconciliationDocRequest() => 'Mutabakat',
    ReceiptDocRequest() => 'Teslim tutanağı',
    WaybillDocRequest() => 'Sevk belgesi',
  };
}

/// Siparişin tüm belgeleri (teklif sürümleri dahil) alt sayfada.
Future<void> showOrderDocumentsSheet(
  BuildContext context, {
  required int orderId,
  List<DocumentArchiveRow> rows = const [],
}) => showAppSheet<void>(
  context: context,
  title: CmCopy.documentsTitle,
  subtitle: rows.isEmpty ? null : rows.first.orderNumber,
  builder: (_) => _OrderDocumentsSheet(orderId: orderId, rows: rows),
);

class _OrderDocumentsSheet extends ConsumerWidget {
  const _OrderDocumentsSheet({required this.orderId, required this.rows});

  final int orderId;
  final List<DocumentArchiveRow> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final policy = ref.watch(accessPolicyProvider);
    final doc = ref.watch(orderDocumentProvider(orderId));
    final order = doc.valueOrNull;
    final number = order?.orderNumber ?? rows.firstOrNull?.orderNumber;
    final orderDocs = <DocRequest>[];
    if (policy.cmOrderDocuments && number != null) {
      orderDocs.add(OrderDocRequest(orderId, number));
      final versions = order != null
          ? [for (final q in order.quotes.reversed) q.version]
          : [?rows.firstOrNull?.quoteVersion];
      for (final v in versions) {
        orderDocs.add(QuoteDocRequest(orderId, number, v));
      }
      final reconcile = order?.canReconcile ?? rows.any((r) => r.canReconcile);
      if (reconcile) orderDocs.add(ReconciliationDocRequest(orderId, number));
    }
    final shipments = <int, ShipmentStatus?>{};
    if (order != null) {
      for (final s in order.shipments) {
        shipments[s.id] = s.status;
      }
    } else {
      for (final r in rows) {
        if (r.shipmentId != null) shipments[r.shipmentId!] = r.shipmentStatus;
      }
    }
    final shipDocs = <DocRequest>[
      if (policy.cmShipmentDocuments)
        for (final e in shipments.entries) ...[
          if (e.value != ShipmentStatus.cancelled) ReceiptDocRequest(e.key),
          WaybillDocRequest(e.key),
        ],
    ];
    void open(DocRequest r) => openGeneratedDocument(context, ref, r);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (doc.isLoading && order == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (order != null) ...[
          Text(
            '${order.productName} · ${Fmt.liters(order.quantityLiters)} · ${order.displayStatus}',
            style: t.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
        if (orderDocs.isNotEmpty) ...[
          const SectionHeader(
            title: 'Sipariş belgeleri',
            padding: EdgeInsets.fromLTRB(0, 8, 0, 4),
          ),
          for (final r in orderDocs)
            DocumentTile(request: r, onTap: () => open(r)),
        ],
        if (shipDocs.isNotEmpty) ...[
          const SectionHeader(
            title: 'Sevkiyat belgeleri',
            padding: EdgeInsets.fromLTRB(0, 16, 0, 4),
          ),
          for (final r in shipDocs)
            DocumentTile(request: r, onTap: () => open(r)),
        ],
        if (orderDocs.isEmpty && shipDocs.isEmpty)
          const EmptyState(
            title: 'Bu sipariş için açabileceğiniz belge yok',
            compact: true,
            illustration: AknIllustration.documents,
          ),
        const SizedBox(height: 12),
        Text(CmCopy.documentsFooter, style: t.caption),
      ],
    );
  }
}
