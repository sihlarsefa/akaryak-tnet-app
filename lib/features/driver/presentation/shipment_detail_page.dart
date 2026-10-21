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
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../../weather/api.dart';
import '../application/driver_home_state.dart';
import '../application/driver_lists.dart';
import '../application/driver_ops.dart';
import '../application/location.dart';
import '../application/proximity.dart';
import '../copy.dart';
import '../data/driver_models.dart';
import '../data/driver_outbox.dart';
import '../driver_paths.dart';
import 'driver_home.dart' show ContactRow, distanceReadout;
import 'widgets/delivery_point_card.dart';
import 'widgets/evidence_grid.dart';
import 'widgets/location_card.dart';
import 'widgets/navigation.dart';
import 'widgets/op_status.dart';
import 'widgets/stop_dock.dart';
import 'widgets/stop_plate.dart';

/// Teslimat ayrıntısı (tasarım v2 §5.2 ve §7.11; spec A.4 A7). Sürücü kipinde: müşteri ve adres,
/// durum lambası; **tek plaka** (açık teslimatta bu durağın litresi + plan / uzaklık / teslim saati,
/// teslim edilende teslim edilen litre + planlanan / fark / saat); kapı notu ve teslim alacak kişi;
/// teslimat noktası, hava durumu, sipariş bilgileri ve teslim kanıtı bölümleri.
///
/// Alt raf durumuna göre: planlıysa "Yola çıkmak için kaydırın" (konum satırıyla); yoldaysa
/// "Yol tarifi" + "Teslim et" (birincil olan tırı izler); itirazlıysa "Teslimatı düzelt"; bekleyen
/// işlem varsa sonucu (gönderiliyor / telefona kaydedildi / gönderildi / reddedildi).
class ShipmentDetailPage extends StatelessWidget {
  const ShipmentDetailPage({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context) =>
      AknDriverScope(child: _ShipmentDetailView(id: id));
}

class _ShipmentDetailView extends ConsumerStatefulWidget {
  const _ShipmentDetailView({required this.id});

  final int id;

  @override
  ConsumerState<_ShipmentDetailView> createState() =>
      _ShipmentDetailPageState();
}

class _ShipmentDetailPageState extends ConsumerState<_ShipmentDetailView> {
  late final ProximityWatch _proximity;
  late final AppLifecycleListener _lifecycle;

  LocationCapture get _location => _proximity.capture;

  /// Az önce kuyruğa yazılan yola çıkış (sağlayıcı güncellenene kadar gösterilir).
  OutboxOp? _justQueued;
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    _proximity = ProximityWatch(ref.read(driverLocationServiceProvider));
    _lifecycle = AppLifecycleListener(onResume: _proximity.resume);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _proximity.start();
    });
  }

  @override
  void dispose() {
    _settle?.cancel();
    _lifecycle.dispose();
    _proximity.dispose();
    super.dispose();
  }

  Future<void> _start(DriverShipmentDetail d) async {
    try {
      final position = _location.hasPosition ? await _location.latest() : null;
      final op = await ref
          .read(driverCommandsProvider)
          .start(shipmentId: d.id, code: d.code, position: position);
      if (!mounted) return;
      setState(() => _justQueued = op);
      // Başarı animasyonu bittikten sonra alt raf "Teslim et"e geçsin.
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
    final ops = ref.watchDriverOps()[d.id];
    final draft = ref.watch(driverDraftsProvider)[d.id];
    final weatherOn = ref.watch(
      appConfigProvider.select((c) => c.features.weather),
    );
    final online = ref.watchOnline();
    final controller = ref.read(driverShipmentProvider(widget.id).notifier);
    final row = d.row;
    final open = row.isPlanned || row.isInTransit;
    final dockHasNavigate = row.isInTransit || (ops?.startWaiting ?? false);

    return AppScaffold(
      title: d.code,
      refreshing: state.refreshing,
      showBell: false,
      body: PullToRefresh(
        onRefresh: controller.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (state.refreshError != null || state.cachedAt != null || !online)
              _StaleNote(
                at: state.cachedAt,
                offline: !online || state.refreshError is OfflineFailure,
              ),
            _Head(detail: d, ops: ops),
            if (row.isDisputed)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: AknBanner(
                  tone: AknTone.danger,
                  icon: Icons.report_outlined,
                  title: DriverCopy.disputedTitle,
                  message: row.disputeNote ?? DriverCopy.disputedFallback,
                ),
              ),
            ListenableBuilder(
              listenable: _proximity,
              builder: (context, _) => _plate(d),
            ),
            if (open && d.accessNotes != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _DoorNote(text: d.accessNotes!),
              ),
            if (open && (d.contactName != null || d.contactPhone != null))
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: ContactRow(
                  name: d.contactName,
                  phone: d.contactPhone,
                  role: DriverCopy.recipientRole,
                ),
              ),
            if (weatherOn && d.hasCoordinates && row.isOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DrivingAlertBanner(
                      lat: d.latitude!,
                      lng: d.longitude!,
                      at: row.scheduledAt,
                    ),
                    WeatherCard(lat: d.latitude!, lng: d.longitude!),
                  ],
                ),
              ),
            const SectionHeader(title: DriverCopy.deliveryPoint),
            DeliveryPointCard(detail: d, showNavigate: !dockHasNavigate),
            if (!open && (d.contactName != null || d.contactPhone != null))
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: ContactRow(
                  name: d.contactName,
                  phone: d.contactPhone,
                  role: DriverCopy.contactRole,
                ),
              ),
            const SectionHeader(title: DriverCopy.order),
            _OrderFacts(detail: d),
            if (row.deliveredLiters != null || d.attachments.isNotEmpty) ...[
              const SectionHeader(title: DriverCopy.proofTitle),
              _Proof(detail: d),
            ],
          ],
        ),
      ),
      actionBar: _barOf(
        ListenableBuilder(
          listenable: _proximity,
          builder: (context, _) =>
              _actionBar(d, ops, draft != null) ?? const SizedBox.shrink(),
        ),
        visible: _actionBar(d, ops, draft != null) != null,
      ),
    );
  }

  /// Ekranın tek plakası: açıkta bu durağın litresi, teslim edilende teslim edilen litre.
  Widget _plate(DriverShipmentDetail d) {
    final row = d.row;
    final now = TrTime.now();
    final delivered = row.deliveredLiters;
    final margin = const EdgeInsets.fromLTRB(20, 16, 20, 0);
    if (delivered != null && !row.isPlanned && !row.isInTransit) {
      final diff = d.differenceLiters ?? 0;
      return DriverStopPlate(
        product: row.productName,
        title: DriverCopy.plateDelivered,
        figure: Fmt.number(delivered, maxFraction: 3),
        margin: margin,
        readouts: [
          StopReadout(
            label: DriverCopy.readoutPlanned,
            value: Fmt.number(row.plannedLiters, maxFraction: 3),
            unit: 'L',
          ),
          StopReadout(
            label: DriverCopy.readoutDiff,
            value: diff.abs() < 0.001
                ? '0'
                : '${diff < 0 ? '−' : '+'}${Fmt.number(diff.abs(), maxFraction: 3)}',
            unit: 'L',
          ),
          if (d.deliveredAt != null)
            StopReadout(
              label: DriverCopy.readoutTime,
              value: Fmt.time(d.deliveredAt),
            ),
        ],
      );
    }
    final at = row.scheduledAt;
    final day = Fmt.dayLabel(at, now: now);
    final dist = row.isOpen
        ? _proximity.distanceTo(d.latitude, d.longitude)
        : null;
    return DriverStopPlate(
      product: row.productName,
      figure: Fmt.number(row.plannedLiters, maxFraction: 3),
      margin: margin,
      readouts: [
        if (at != null)
          StopReadout(
            label: day == 'Bugün'
                ? DriverCopy.readoutPlan
                : DriverCopy.readoutPlanOn(TurkishText.lower(day)),
            value: Fmt.time(at),
          ),
        if (dist != null)
          distanceReadout(dist)
        else if (d.tankCapacityLiters != null)
          StopReadout(
            label: DriverCopy.readoutTank,
            value: Fmt.number(d.tankCapacityLiters),
            unit: 'L',
          ),
        if (row.windowLabel != null)
          StopReadout(label: DriverCopy.readoutWindow, value: row.windowLabel!),
      ],
    );
  }

  /// Alt raf içeriği yüksekliğini çocuğundan alır (genişleyen düğmeler rafı büyütmesin).
  static Widget? _barOf(Widget child, {required bool visible}) => !visible
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

    Widget deliverDock() => DriverStopDock(
      onNavigate: () => unawaited(
        openNavigation(
          context,
          lat: d.latitude,
          lng: d.longitude,
          address: d.fullAddress,
        ),
      ),
      actionLabel: hasDraft
          ? DriverCopy.actionResume
          : DriverCopy.actionDeliver,
      actionIcon: Icons.task_alt_rounded,
      actionSemanticLabel: hasDraft
          ? '${DriverCopy.actionDeliver}: ${DriverCopy.resumeDraft}'
          : null,
      actionIsPrimary: _proximity.deliverIsPrimary(d.latitude, d.longitude),
      onAction: () => unawaited(_openDeliver(d)),
    );

    if (showStartOutcome) {
      final canDeliverNow = startWaiting || d.actions.canDeliver;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpOutcomePanel(op: startOp, compact: true),
          if (canDeliverNow) ...[const SizedBox(height: 10), deliverDock()],
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
            confirmLabel: DriverCopy.confirmStart,
            onConfirmed: () => _start(d),
          ),
        ],
      );
    }
    if (d.actions.canDeliver && d.row.isDisputed) {
      return AknButton(
        label: hasDraft ? DriverCopy.actionResume : DriverCopy.actionFix,
        icon: Icons.edit_note_rounded,
        expand: true,
        onPressed: () => unawaited(_openDeliver(d)),
      );
    }
    if (d.actions.canDeliver) return deliverDock();
    if (d.row.status == ShipmentStatus.reported ||
        d.row.status == ShipmentStatus.accepted) {
      final c = context.akn;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(Icons.verified_outlined, color: c.ok.fg, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                d.row.status == ShipmentStatus.reported
                    ? 'Teslimat bildirildi; müşteri onayı bekleniyor.'
                    : 'Teslimat müşteri tarafından onaylandı.',
                style: context.aknText.bodySmall.copyWith(color: c.ink),
              ),
            ),
          ],
        ),
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
    showBell: false,
    body: Shimmer(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SkeletonLine(widthFactor: 0.7, height: 24),
            SizedBox(height: 8),
            SkeletonLine(widthFactor: 0.9, height: 16),
            SizedBox(height: 16),
            SkeletonBox(height: 214, radius: 20),
            SizedBox(height: 16),
            SkeletonLine(widthFactor: 0.8, height: 16),
            SizedBox(height: 8),
            SkeletonLine(widthFactor: 0.6, height: 16),
          ],
        ),
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
      showBell: false,
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
    final text = offline
        ? at == null
              ? DriverCopy.offlineLine
              : '${DriverCopy.offlineLine} ${DriverCopy.lastUpdated} ${Fmt.time(at)}.'
        : '${DriverCopy.lastUpdated} ${Fmt.time(at)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              offline ? Icons.cloud_off_outlined : Icons.history_rounded,
              size: 20,
              color: c.dim,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: t.label.copyWith(
                color: c.dim,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Başlık: müşteri (24/30), adres, durum lambası ve (varsa) işlem lambası; yoldaysa çıkış saati.
class _Head extends StatelessWidget {
  const _Head({required this.detail, this.ops});

  final DriverShipmentDetail detail;
  final DriverShipmentOps? ops;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final row = detail.row;
    final op = ops?.primary;
    final style = row.status.statusStyle.withLabel(row.statusLabelFromServer);
    final place = [
      ?row.deliveryPointName,
      ?(row.district ?? row.city),
    ].join(', ');
    final dispatched = detail.dispatchedAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Durak adı 24/30; büyük yazıda en çok 1,6× (başlıklar gibi).
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.6,
            child: Semantics(
              header: true,
              child: Text(
                row.customerTitle ?? row.code,
                style: AknDriverMode.stopName(
                  t,
                ).copyWith(color: c.ink, letterSpacing: -0.4),
              ),
            ),
          ),
          if (place.isNotEmpty)
            Text(place, style: t.body.copyWith(color: c.ink)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AknLamp.style(style),
              if (row.isInTransit && dispatched != null)
                Text(
                  DriverCopy.dispatchedMeta(Fmt.time(dispatched)),
                  style: t.bodySmall.copyWith(color: c.dim),
                ),
              if (row.isOverdue(TrTime.now()))
                const AknLamp(label: DriverCopy.overdue, tone: AknTone.danger),
              if (op != null) OpStatusChip(op: op),
            ],
          ),
        ],
      ),
    );
  }
}

class _DoorNote extends StatelessWidget {
  const _DoorNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.door_front_door_outlined, size: 22, color: c.ink),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: '${DriverCopy.doorNote} ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: text),
              ],
            ),
            style: t.body.copyWith(color: c.ink),
          ),
        ),
      ],
    );
  }
}

/// Olgu satırları (bölüm, kutu yok): etiket solda soluk, değer sağda; aralarında ince çizgi.
class _Facts extends StatelessWidget {
  const _Facts({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AknSpace.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.line),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _OrderFacts extends StatelessWidget {
  const _OrderFacts({required this.detail});

  final DriverShipmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final row = detail.row;
    return _Facts(
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
          FactRow(label: DriverCopy.plate, value: Fmt.plate(row.vehiclePlate)),
        if (detail.dispatchedAt != null)
          FactRow(
            label: DriverCopy.dispatchedAt,
            value: Fmt.dateTime(detail.dispatchedAt),
          ),
      ],
    );
  }
}

class _Proof extends StatelessWidget {
  const _Proof({required this.detail});

  final DriverShipmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final row = detail.row;
    final diff = detail.differenceLiters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Facts(
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
              FactRow(
                label: DriverCopy.recipient,
                value: detail.recipientName!,
              ),
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
          ],
        ),
        if (detail.attachments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: EvidenceGrid(attachments: detail.attachments),
          ),
      ],
    );
  }
}
