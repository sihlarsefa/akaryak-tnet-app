import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/media/attachment_gallery.dart';
import '../../../../core/models/models.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/bayi_actions.dart';
import '../../application/bayi_grants.dart';
import '../../application/dispatch_controller.dart';
import '../../data/dispatch_models.dart';
import '../widgets/bayi_widgets.dart';
import 'driver_picker.dart';
import 'report_sheet.dart';

/// Sevkiyat ayrıntısı ve teslim kanıtı (`shipments/{id}/detail`): kanıt fotoğrafları, imza / imza
/// alınamama nedeni, itiraz notu ve fotoğrafları; yetkiye ve sunucu bayraklarına göre Yola çıkar,
/// Teslim bildir / Teslimatı düzelt, Şoför değiştir, İptal. Sevkiyat uygulamayı kullanan bir şoföre
/// aitse her işlemden önce onay sorulur.
Future<void> showShipmentSheet(
  BuildContext context,
  int shipmentId, {
  String? code,
}) => showAppSheet<void>(
  context: context,
  title: code ?? 'SVK-${shipmentId.toString().padLeft(8, '0')}',
  subtitle: 'Sevkiyat',
  builder: (_) => ShipmentSheetBody(shipmentId: shipmentId),
);

class ShipmentSheetBody extends ConsumerStatefulWidget {
  const ShipmentSheetBody({super.key, required this.shipmentId});

  final int shipmentId;

  @override
  ConsumerState<ShipmentSheetBody> createState() => _ShipmentSheetBodyState();
}

class _ShipmentSheetBodyState extends ConsumerState<ShipmentSheetBody> {
  String? _busy;

  int get _id => widget.shipmentId;

  Future<void> _refresh() =>
      ref.read(shipmentDetailProvider(_id).notifier).refresh();

  /// Uygulama şoförüne ait sevkiyatta personel işleminden önce onay.
  Future<bool> _confirmAppDriver(
    ShipmentDetail d,
    String action,
    String hint,
  ) async {
    if (!d.isAppDriver) return true;
    final name = d.driverAccountName ?? d.driverName ?? 'Şoför';
    return showConfirmSheet(
      context,
      title: '$name uygulamayı kullanıyor',
      message: '$hint Yine de devam etmek istiyor musunuz?',
      confirmLabel: action,
      icon: Icons.phone_iphone_rounded,
      tone: AknTone.warn,
    );
  }

  Future<void> _run(String key, Future<void> Function() action) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    try {
      await action();
    } catch (e) {
      if (mounted) showActionFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _dispatch(ShipmentDetail d) async {
    final ok = await _confirmAppDriver(
      d,
      'Yola çıkar',
      'Yola çıkışı genellikle şoför kendi telefonundan bildirir.',
    );
    if (!ok || !mounted) return;
    await _run('dispatch', () async {
      await ref.read(bayiActionsProvider).dispatch(d.id);
      if (mounted) {
        AppToast.success('Sevkiyat yola çıkarıldı.', context: context);
      }
      await _refresh();
    });
  }

  Future<void> _report(ShipmentDetail d) async {
    final ok = await _confirmAppDriver(
      d,
      d.status == ShipmentStatus.disputed
          ? 'Teslimatı düzelt'
          : 'Teslim bildir',
      'Teslimi genellikle şoför kanıtlarıyla (fotoğraf, imza) kendisi bildirir.',
    );
    if (!ok || !mounted) return;
    final done = await showReportSheet(context, d);
    if (done && mounted) await _refresh();
  }

  Future<void> _reassign(ShipmentDetail d) async {
    final ok = await _confirmAppDriver(
      d,
      'Şoför değiştir',
      'Şoför değişirse sevkiyat ${d.driverAccountName ?? d.driverName ?? 'şoförün'} '
          'uygulamasından kalkar.',
    );
    if (!ok || !mounted) return;
    final choice = await showDriverPicker(
      context,
      allowManual: false,
      title: 'Yeni şoför',
    );
    final account = choice?.account;
    if (account == null || !mounted) return;
    await _run('reassign', () async {
      await ref
          .read(bayiActionsProvider)
          .assignDriver(d.id, driver: account, vehiclePlate: d.vehiclePlate);
      if (mounted) {
        AppToast.success(
          'Şoför ${account.displayName} olarak değişti.',
          context: context,
        );
      }
      await _refresh();
    });
  }

  Future<void> _cancel(ShipmentDetail d) async {
    final name = d.driverAccountName ?? d.driverName;
    final ok = await showConfirmSheet(
      context,
      title: 'Sevkiyat planı iptal edilsin mi?',
      message: d.isAppDriver && name != null
          ? '$name uygulamasındaki teslimat da kalkar. Planlanan litre yeniden planlanabilir.'
          : 'Planlanan litre yeniden planlanabilir.',
      confirmLabel: 'Planı iptal et',
      cancelLabel: 'Vazgeç',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run('cancel', () async {
      await ref.read(bayiActionsProvider).cancelShipment(d.id);
      if (mounted) {
        AppToast.success('Sevkiyat planı iptal edildi.', context: context);
      }
      await _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shipmentDetailProvider(_id));
    final d = state.data;
    if (d == null) {
      final f = state.error;
      if (f != null) {
        return FailureView(failure: f, compact: true, onRetry: _refresh);
      }
      return const SkeletonList(
        itemCount: 3,
        lines: 3,
        padding: EdgeInsets.zero,
        shrinkWrap: true,
      );
    }
    return _Content(
      detail: d,
      busy: _busy,
      onDispatch: () => unawaited(_dispatch(d)),
      onReport: () => unawaited(_report(d)),
      onReassign: () => unawaited(_reassign(d)),
      onCancel: () => unawaited(_cancel(d)),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({
    required this.detail,
    required this.busy,
    required this.onDispatch,
    required this.onReport,
    required this.onReassign,
    required this.onCancel,
  });

  final ShipmentDetail detail;
  final String? busy;
  final VoidCallback onDispatch;
  final VoidCallback onReport;
  final VoidCallback onReassign;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = detail;
    final t = context.aknText;
    final c = context.akn;
    final grants = ref.watch(bayiGrantsProvider);
    final online = ref.watch(isOnlineProvider);
    final a = d.actions;
    final canDispatch = a.canDispatch && grants.dispatchOrReport;
    final canReport = a.canReport && grants.dispatchOrReport;
    final canReassign = a.canReassign && grants.assignDriver;
    final canCancel = a.canCancel && grants.cancelShipment;
    final hasActions = canDispatch || canReport || canReassign || canCancel;
    final diff = d.differenceLiters;
    final point = d.deliveryPoint;
    final lamp = AknStatus.shipmentLamp(d.status, grants.viewer);
    final facts = <Widget>[
      FactRow(label: 'Plan zamanı', value: Fmt.dateTime(d.scheduledAt)),
      if (d.dispatchedAt != null)
        FactRow(label: 'Yola çıkış', value: Fmt.dateTime(d.dispatchedAt)),
      if (d.deliveredAt != null)
        FactRow(
          label: 'Teslim',
          value: d.timeSource == 'device'
              ? '${Fmt.dateTime(d.deliveredAt)} (cihaz saati)'
              : Fmt.dateTime(d.deliveredAt),
        ),
      if (d.acceptedAt != null)
        FactRow(
          label: 'Cari kabulü',
          value: Fmt.dateTime(d.acceptedAt),
          tone: AknTone.ok,
        ),
      if (d.driverLabel != null)
        FactRow(
          label: 'Şoför',
          value:
              d.driverAccountName != null && d.driverAccountName != d.driverName
              ? '${d.driverLabel} (${d.driverAccountName})'
              : d.driverLabel!,
        ),
      if (d.driverUserId == null && d.viewerSide == 'bayi')
        const FactRow(
          label: 'Şoför hesabı',
          value: 'Atanmamış (uygulamada görünmez)',
          tone: AknTone.warn,
        ),
      if (d.deliveryDocumentNo != null)
        FactRow(label: 'İrsaliye no', value: d.deliveryDocumentNo!),
      if (d.recipientName != null)
        FactRow(label: 'Teslim alan', value: d.recipientName!),
      if (d.reportedByName != null)
        FactRow(label: 'Bildiren', value: d.reportedByName!),
      if (d.distanceToDeliveryPointMeters != null)
        FactRow(
          label: 'Teslim konumu',
          value: 'Noktaya ${Fmt.integer(d.distanceToDeliveryPointMeters)} m',
          tone: d.distanceToDeliveryPointMeters! > 500 ? AknTone.warn : null,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AknLamp.status(lamp),
            if (d.isAppDriver)
              const AknLamp(
                label: 'uygulamada',
                tone: AknTone.ok,
                size: AknLampSize.small,
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.customerTitle ?? '',
                    style: t.headline.copyWith(color: c.ink),
                  ),
                  Text(
                    [?d.productName, d.orderNumber].join(', '),
                    style: t.bodySmall.copyWith(color: c.dim),
                  ),
                ],
              ),
            ),
            if (AdrPlate.forProduct(d.productName, height: 30) case final adr?)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 12),
                child: adr,
              ),
          ],
        ),
        const SizedBox(height: 12),
        KpiRow(
          children: [
            KpiTile(
              label: 'Planlanan',
              value: d.plannedLiters,
              format: (v) => Fmt.number(v, maxFraction: 3),
              unit: 'L',
            ),
            if (d.deliveredLiters != null)
              KpiTile(
                label: 'Teslim edilen',
                value: d.deliveredLiters,
                format: (v) => Fmt.number(v, maxFraction: 3),
                unit: 'L',
              ),
            if (diff != null && diff.abs() >= 0.001)
              KpiTile(
                label: 'Fark',
                value: diff,
                format: (v) =>
                    '${v > 0 ? '+' : ''}${Fmt.number(v, maxFraction: 3)}',
                unit: 'L',
              ),
          ],
        ),
        if (d.status == ShipmentStatus.inTransit) ...[
          const SizedBox(height: 14),
          TruckRoute(
            moving: true,
            originLabel: d.dispatchedAt == null
                ? 'Yolda'
                : '${Fmt.time(d.dispatchedAt)} çıktı',
            destinationLabel: point.name,
            semanticLabel:
                'Yolda, canlı konum değildir${d.dispatchedAt == null ? '' : ', ${Fmt.time(d.dispatchedAt)} çıkış'}',
          ),
        ],
        if (d.disputeNote != null) ...[
          const SizedBox(height: 12),
          AknBanner(
            tone: AknTone.danger,
            icon: Icons.report_outlined,
            title: 'Carinin itirazı',
            message: d.disputeNote!,
          ),
        ],
        if (d.signatureWaiverLabel != null) ...[
          const SizedBox(height: 12),
          AknBanner(
            tone: AknTone.warn,
            icon: Icons.gesture_rounded,
            title: 'İmza alınamadı',
            message: d.signatureWaiverLabel!,
          ),
        ],
        const SizedBox(height: 8),
        for (var i = 0; i < facts.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: c.line),
          facts[i],
        ],
        if (d.vehiclePlate != null) ...[
          Divider(height: 1, thickness: 1, color: c.line),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Plaka',
                    style: t.bodySmall.copyWith(color: c.dim),
                  ),
                ),
                PlateBadge(plate: d.vehiclePlate!),
              ],
            ),
          ),
        ],
        if (d.deliveryNote != null) ...[
          const SizedBox(height: 12),
          Text('Teslim notu', style: t.label.copyWith(color: c.ink)),
          const SizedBox(height: 2),
          Text(d.deliveryNote!, style: t.body.copyWith(color: c.ink)),
        ],
        if (d.proofAttachments.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Teslim kanıtı', style: t.bodyStrong.copyWith(color: c.ink)),
          const SizedBox(height: 8),
          AttachmentGallery(attachments: d.proofAttachments),
        ],
        if (d.disputeAttachments.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'İtiraz fotoğrafları',
            style: t.bodyStrong.copyWith(color: c.ink),
          ),
          const SizedBox(height: 8),
          AttachmentGallery(attachments: d.disputeAttachments),
        ],
        const SizedBox(height: 16),
        Text(
          point.name ?? 'Teslimat noktası',
          style: t.bodyStrong.copyWith(color: c.ink),
        ),
        if (point.address != null || point.place != null)
          Text(
            [?point.address, ?point.place].join(', '),
            style: t.bodySmall.copyWith(color: c.dim),
          ),
        if (point.window != null)
          Text(
            'Teslim penceresi ${point.window}',
            style: t.bodySmall.copyWith(color: c.dim),
          ),
        Wrap(
          spacing: 20,
          children: [
            if (point.canOpenMap)
              AknInlineLink(
                label: 'Haritada aç',
                onTap: () => openMap(
                  context,
                  latitude: point.latitude!,
                  longitude: point.longitude!,
                  label: point.name,
                ),
              ),
            if (grants.viewOrders)
              AknInlineLink(
                label: 'Siparişi aç',
                onTap: () {
                  final router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  unawaited(router.push(AppRoutes.bayiOrder(d.orderId)));
                },
              ),
          ],
        ),
        if (hasActions) ...[
          const SizedBox(height: 16),
          if (!online)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Çevrimdışıyken sevkiyat işlemi yapılamaz.',
                style: t.bodySmall.copyWith(color: c.dim),
              ),
            ),
          if (canDispatch)
            _ActionButton(
              label: 'Yola çıkar',
              primary: true,
              loading: busy == 'dispatch',
              enabled: online && busy == null,
              onPressed: onDispatch,
            ),
          if (canReport)
            _ActionButton(
              label: d.status == ShipmentStatus.disputed
                  ? 'Teslimatı düzelt'
                  : 'Teslim bildir',
              primary: !canDispatch,
              loading: busy == 'report',
              enabled: online && busy == null,
              onPressed: onReport,
            ),
          if (canReassign)
            _ActionButton(
              label: 'Şoför değiştir',
              loading: busy == 'reassign',
              enabled: online && busy == null,
              onPressed: onReassign,
            ),
          if (canCancel)
            _ActionButton(
              label: 'Planı iptal et',
              danger: true,
              loading: busy == 'cancel',
              enabled: online && busy == null,
              onPressed: onCancel,
            ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onPressed,
    required this.enabled,
    this.loading = false,
    this.primary = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final bool loading;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final cb = enabled ? onPressed : null;
    final Widget b = danger
        ? AknButton.danger(
            label: label,
            expand: true,
            loading: loading,
            onPressed: cb,
          )
        : primary
        ? AknButton(label: label, expand: true, loading: loading, onPressed: cb)
        : AknButton.secondary(
            label: label,
            expand: true,
            loading: loading,
            onPressed: cb,
          );
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: b);
  }
}
