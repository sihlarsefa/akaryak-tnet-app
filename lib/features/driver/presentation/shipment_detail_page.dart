import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/env/app_config_controller.dart';
import '../../../core/models/models.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/outbox_op.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../weather/api.dart';
import '../application/driver_home_state.dart';
import '../application/driver_lists.dart';
import '../application/driver_ops.dart';
import '../application/location.dart';
import '../copy.dart';
import '../data/driver_models.dart';
import '../data/driver_outbox.dart';
import '../driver_paths.dart';
import 'widgets/delivery_point_card.dart';
import 'widgets/evidence_grid.dart';
import 'widgets/location_card.dart';
import 'widgets/navigation.dart';
import 'widgets/op_status.dart';

/// Teslimat ayrıntısı (spec A.4 A7): durum başlığı, teslimat noktası (harita iğnesi ya da adres, yol
/// tarifi, yetkili, giriş notları, tank), hava durumu ve sürüş uyarısı, sipariş bilgileri, teslim
/// kanıtı. Alt çubukta durumuna göre "Kaydırarak yola çıkın", "Teslim et", "Teslimatı düzelt" ya da
/// bekleyen işlemin sonucu.
class ShipmentDetailPage extends ConsumerStatefulWidget {
  const ShipmentDetailPage({super.key, required this.id});

  final int id;

  @override
  ConsumerState<ShipmentDetailPage> createState() => _ShipmentDetailPageState();
}

class _ShipmentDetailPageState extends ConsumerState<ShipmentDetailPage> {
  late final LocationCapture _location;
  bool _primed = false;

  /// Az önce kuyruğa yazılan yola çıkış (sağlayıcı güncellenene kadar gösterilir).
  OutboxOp? _justQueued;
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    _location = LocationCapture(ref.read(driverLocationServiceProvider));
  }

  @override
  void dispose() {
    _settle?.cancel();
    _location.dispose();
    super.dispose();
  }

  void _primeLocation(DriverShipmentDetail d) {
    if (_primed || !d.row.isPlanned) return;
    _primed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_location.prime());
    });
  }

  Future<void> _start(DriverShipmentDetail d) async {
    try {
      final position = _location.hasPosition ? await _location.latest() : null;
      final op = await ref
          .read(driverCommandsProvider)
          .start(shipmentId: d.id, code: d.code, position: position);
      if (!mounted) return;
      setState(() => _justQueued = op);
      // Başarı animasyonu bittikten sonra alt çubuk "Teslim et"e geçsin.
      _settle?.cancel();
      _settle = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _justQueued = null);
      });
    } on AppFailure catch (f) {
      if (mounted) AppToast.error(f.message, context: context);
    }
  }

  Future<void> _openDeliver(DriverShipmentDetail d) =>
      context.push(DriverPaths.deliver(d.id));

  Future<void> _fixOp(OutboxOp op) async {
    if (op.type == DriverOutbox.deliver) {
      final draft = await ref.read(driverCommandsProvider).draftForFix(op.id);
      if (!mounted || draft == null) return;
      await context.push(DriverPaths.deliver(draft.shipmentId));
    } else {
      await ref.read(driverCommandsProvider).retry(op.id);
    }
  }

  Future<void> _discardOp(OutboxOp op) async {
    final ok = await showConfirmSheet(
      context,
      title: DriverCopy.discardOpTitle,
      message: DriverCopy.discardOpBody,
      confirmLabel: 'Sil',
      cancelLabel: DriverCopy.opDiscard,
      destructive: true,
    );
    if (ok) await ref.read(driverCommandsProvider).discard(op.id);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(driverShipmentProvider(widget.id));
    final state = async.valueOrNull;
    if (state == null) {
      if (async.hasError) return _errorScaffold(async.error);
      return _skeleton();
    }
    final d = state.detail;
    _primeLocation(d);
    final ops = ref.watchDriverOps()[d.id];
    final draft = ref.watch(driverDraftsProvider)[d.id];
    final weatherOn = ref.watch(
      appConfigProvider.select((c) => c.features.weather),
    );
    final controller = ref.read(driverShipmentProvider(widget.id).notifier);

    return AppScaffold(
      title: d.code,
      subtitle: d.row.customerTitle,
      refreshing: state.refreshing,
      actions: [
        if (d.contactPhone != null)
          AknIconButton(
            icon: Icons.call_rounded,
            semanticLabel:
                '${d.contactName ?? DriverCopy.contact} kişisini ara',
            onPressed: () => callPhone(context, d.contactPhone),
          ),
      ],
      body: PullToRefresh(
        onRefresh: controller.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (state.refreshError != null || state.cachedAt != null)
              _StaleNote(
                at: state.cachedAt,
                offline: state.refreshError is OfflineFailure,
              ),
            _StatusHero(detail: d, ops: ops),
            if (d.row.isDisputed) ...[
              const SizedBox(height: 12),
              AknBanner(
                tone: AknTone.danger,
                icon: Icons.report_rounded,
                title: DriverCopy.disputedTitle,
                message: d.row.disputeNote ?? DriverCopy.disputedFallback,
              ),
            ],
            const SectionHeader(
              title: DriverCopy.deliveryPoint,
              padding: EdgeInsets.fromLTRB(0, 24, 0, 8),
            ),
            DeliveryPointCard(detail: d),
            if (weatherOn && d.hasCoordinates && d.row.isOpen) ...[
              const SizedBox(height: 12),
              DrivingAlertBanner(
                lat: d.latitude!,
                lng: d.longitude!,
                at: d.row.scheduledAt,
              ),
              WeatherCard(lat: d.latitude!, lng: d.longitude!),
            ],
            const SectionHeader(
              title: DriverCopy.order,
              padding: EdgeInsets.fromLTRB(0, 24, 0, 8),
            ),
            _OrderFacts(detail: d),
            if (d.row.deliveredLiters != null || d.attachments.isNotEmpty) ...[
              const SectionHeader(
                title: DriverCopy.proofTitle,
                padding: EdgeInsets.fromLTRB(0, 24, 0, 8),
              ),
              _ProofCard(detail: d),
            ],
          ],
        ),
      ),
      actionBar: _barOf(_actionBar(d, ops, draft != null)),
    );
  }

  /// Alt çubuk içeriği yüksekliğini çocuğundan alır (genişleyen düğmeler çubuğu büyütmesin).
  static Widget? _barOf(Widget? child) => child == null
      ? null
      : Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [child],
        );

  Widget? _actionBar(
    DriverShipmentDetail d,
    DriverShipmentOps? ops,
    bool hasDraft,
  ) {
    final justQueued = _justQueued;
    final startOp = _pick(ops?.start, justQueued);
    final deliverOp = ops?.deliver;

    if (deliverOp != null &&
        (deliverOp.status.isWaiting ||
            deliverOp.status == OutboxStatus.needsAttention ||
            isFreshlyDone(deliverOp))) {
      return OpOutcomePanel(
        op: deliverOp,
        compact: true,
        onFix: () => unawaited(_fixOp(deliverOp)),
        onDiscard: () => unawaited(_discardOp(deliverOp)),
      );
    }
    if (startOp != null && startOp.status == OutboxStatus.needsAttention) {
      return OpOutcomePanel(
        op: startOp,
        compact: true,
        onDiscard: () => unawaited(_discardOp(startOp)),
      );
    }

    final startWaiting = startOp?.status.isWaiting ?? false;
    final showStartOutcome =
        startOp != null &&
        (startWaiting ||
            (startOp.id == justQueued?.id) ||
            isFreshlyDone(startOp));

    final deliverButton = AknButton(
      label: hasDraft
          ? DriverCopy.actionResume
          : d.row.isDisputed
          ? DriverCopy.actionFix
          : DriverCopy.actionDeliver,
      icon: d.row.isDisputed ? Icons.edit_note_rounded : Icons.task_alt_rounded,
      expand: true,
      size: AknButtonSize.large,
      onPressed: () => unawaited(_openDeliver(d)),
    );

    if (showStartOutcome) {
      final canDeliverNow = startWaiting || d.actions.canDeliver;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpOutcomePanel(op: startOp, compact: true),
          if (canDeliverNow) ...[const SizedBox(height: 10), deliverButton],
        ],
      );
    }

    if (d.actions.canStart && d.row.isPlanned) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StartLocationLine(capture: _location),
          SlideToConfirm(
            label: DriverCopy.slideStart,
            doneLabel: DriverCopy.slideStartDone,
            semanticHint: 'Yola çıkmak için iki kez dokunun',
            onConfirmed: () => _start(d),
          ),
        ],
      );
    }
    if (d.actions.canDeliver) return deliverButton;
    if (d.row.status == ShipmentStatus.reported ||
        d.row.status == ShipmentStatus.accepted) {
      return Row(
        children: [
          Icon(Icons.verified_outlined, color: context.akn.dim, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              d.row.status == ShipmentStatus.reported
                  ? 'Teslimat bildirildi; müşteri onayı bekleniyor.'
                  : 'Teslimat müşteri tarafından onaylandı.',
              style: context.aknText.bodySmall,
            ),
          ),
        ],
      );
    }
    return null;
  }

  /// Sağlayıcıdaki sürüm varsa o (aynı işlem), yoksa az önce kuyruğa yazılan.
  static OutboxOp? _pick(OutboxOp? fromStore, OutboxOp? justQueued) {
    if (fromStore == null) return justQueued;
    if (justQueued == null) return fromStore;
    if (fromStore.id == justQueued.id) return fromStore;
    return fromStore.createdAt.isAfter(justQueued.createdAt)
        ? fromStore
        : justQueued;
  }

  Widget _skeleton() => const AppScaffold(
    title: DriverCopy.title,
    body: Shimmer(
      child: Column(
        children: [
          SizedBox(height: 12),
          SkeletonCard(lines: 4),
          SkeletonCard(lines: 3),
          SkeletonCard(lines: 3),
        ],
      ),
    ),
  );

  Widget _errorScaffold(Object? error) {
    final f = AppFailure.from(error ?? const UnknownFailure());
    final controller = ref.read(driverShipmentProvider(widget.id).notifier);
    final Widget body = switch (f) {
      NotFoundFailure() || ForbiddenFailure() => EmptyState(
        title: DriverCopy.notFoundTitle,
        message: DriverCopy.notFoundMessage,
        illustration: AknIllustration.search,
        actionLabel: DriverCopy.backToList,
        onAction: () => context.go(DriverPaths.home),
      ),
      _ => ErrorState(
        offline: f is OfflineFailure,
        message: f is OfflineFailure
            ? DriverCopy.offlineNoCacheMessage
            : f.message,
        traceId: f.traceId,
        onRetry: () => unawaited(controller.refresh()),
      ),
    };
    return AppScaffold(
      title: DriverCopy.title,
      body: Center(child: SingleChildScrollView(child: body)),
    );
  }
}

class _StaleNote extends StatelessWidget {
  const _StaleNote({this.at, this.offline = false});

  final DateTime? at;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    if (at == null && !offline) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            offline ? Icons.cloud_off_rounded : Icons.history_rounded,
            size: 16,
            color: c.dim,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              [
                if (at != null) '${DriverCopy.lastUpdated} ${Fmt.time(at)}',
                if (offline) 'Çevrimdışı',
              ].join(' · '),
              style: t.caption,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lacivert durum başlığı: kod, durum, müşteri, nokta, litre, plan zamanı, plaka; yoldaysa çıkış saati.
class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.detail, this.ops});

  final DriverShipmentDetail detail;
  final DriverShipmentOps? ops;

  @override
  Widget build(BuildContext context) {
    final row = detail.row;
    final op = ops?.primary;
    final style = row.status.statusStyle.withLabel(row.statusLabelFromServer);
    return AknHeroPanel(
      child: Builder(
        builder: (context) {
          final t = context.aknText;
          final c = context.akn;
          final at = row.scheduledAt;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(row.code, style: t.label.copyWith(color: c.dim)),
                  StatusChip.style(style, size: StatusChipSize.small),
                  if (op != null) OpStatusChip(op: op),
                ],
              ),
              const SizedBox(height: 10),
              Semantics(
                header: true,
                child: Text(row.customerTitle ?? row.code, style: t.title),
              ),
              if (row.deliveryPointName != null || row.placeLine != null) ...[
                const SizedBox(height: 2),
                Text(
                  [?row.deliveryPointName, ?row.placeLine].join(' · '),
                  style: t.body.copyWith(color: c.dim),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.deliveredLiters != null
                              ? DriverCopy.delivered
                              : DriverCopy.planned,
                          style: t.caption,
                        ),
                        AmountText(
                          Fmt.liters(row.deliveredLiters ?? row.plannedLiters),
                          large: true,
                        ),
                        if (row.productName != null)
                          Text(row.productName!, style: t.bodySmall),
                      ],
                    ),
                  ),
                  if (row.vehiclePlate != null)
                    Flexible(
                      child: Align(
                        alignment: AlignmentDirectional.bottomEnd,
                        child: PlateBadge(
                          plate: row.vehiclePlate!,
                          fontSize: 14,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _HeroFact(
                    icon: Icons.event_rounded,
                    text: '${Fmt.dayLabel(at)} ${Fmt.time(at)}',
                  ),
                  if (row.windowLabel != null)
                    _HeroFact(
                      icon: Icons.schedule_rounded,
                      text: row.windowLabel!,
                    ),
                  if (detail.dispatchedAt != null)
                    _HeroFact(
                      icon: Icons.local_shipping_rounded,
                      text: DriverCopy.enRouteSince(
                        Fmt.time(detail.dispatchedAt),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroFact extends StatelessWidget {
  const _HeroFact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: c.dim),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: context.aknText.bodySmall.copyWith(color: c.text),
          ),
        ),
      ],
    );
  }
}

class _OrderFacts extends StatelessWidget {
  const _OrderFacts({required this.detail});

  final DriverShipmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final row = detail.row;
    return AknCard(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        children: [
          FactRow(label: DriverCopy.order, value: row.orderNumber),
          if (row.productName != null)
            FactRow(label: DriverCopy.product, value: row.productName!),
          FactRow(
            label: DriverCopy.planned,
            value: Fmt.liters(row.plannedLiters),
          ),
          FactRow(
            label: DriverCopy.scheduled,
            value: Fmt.dateTime(row.scheduledAt),
          ),
          if (row.vehiclePlate != null)
            FactRow(
              label: DriverCopy.plate,
              value: Fmt.plate(row.vehiclePlate),
            ),
          if (detail.dispatchedAt != null)
            FactRow(
              label: DriverCopy.dispatchedAt,
              value: Fmt.dateTime(detail.dispatchedAt),
            ),
        ],
      ),
    );
  }
}

class _ProofCard extends StatelessWidget {
  const _ProofCard({required this.detail});

  final DriverShipmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final row = detail.row;
    final diff = detail.differenceLiters;
    return AknCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (row.deliveredLiters != null)
            FactRow(
              label: DriverCopy.delivered,
              value: Fmt.liters(row.deliveredLiters),
            ),
          if (diff != null && diff.abs() >= 0.001)
            FactRow(
              label: DriverCopy.difference,
              value: DriverCopy.differenceLine(
                Fmt.liters(diff.abs()),
                Fmt.liters(row.plannedLiters),
                less: diff < 0,
              ),
              tone: AknTone.warn,
            ),
          if (detail.deliveryDocumentNo != null)
            FactRow(
              label: DriverCopy.documentNo,
              value: detail.deliveryDocumentNo!,
            ),
          if (detail.recipientName != null)
            FactRow(label: DriverCopy.recipient, value: detail.recipientName!),
          if (detail.deliveredAt != null)
            FactRow(
              label: DriverCopy.deliveredAt,
              value: Fmt.dateTime(detail.deliveredAt),
            ),
          if (detail.signatureWaiverLabel != null)
            FactRow(
              label: DriverCopy.signatureWaived,
              value: detail.signatureWaiverLabel!,
              tone: AknTone.warn,
            ),
          if (detail.deliveryNote != null)
            FactRow(label: DriverCopy.note, value: detail.deliveryNote!),
          if (detail.attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            EvidenceGrid(attachments: detail.attachments),
          ],
        ],
      ),
    );
  }
}
