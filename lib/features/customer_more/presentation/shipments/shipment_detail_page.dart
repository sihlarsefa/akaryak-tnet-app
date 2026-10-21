import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/media/attachment_gallery.dart';
import '../../../../core/models/attachment.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../application/cm_access.dart';
import '../../application/documents_controller.dart';
import '../../application/shipments_controller.dart';
import '../../copy.dart';
import '../../data/shipments.dart';
import '../cm_widgets.dart';
import '../documents/document_viewer.dart';
import 'dispute_page.dart';

/// Teslimat ayrıntısı (`GET shipments/{id}/detail`): durum, teslim kanıtı, itiraz, zaman çizgisi,
/// araç, teslimat noktası, belgeler; kabul / itiraz eylemleri (yalnızca sunucu izin verdiyse).
class ShipmentDetailPage extends ConsumerStatefulWidget {
  const ShipmentDetailPage({super.key, required this.shipmentId});

  final int shipmentId;

  @override
  ConsumerState<ShipmentDetailPage> createState() => _ShipmentDetailPageState();
}

class _ShipmentDetailPageState extends ConsumerState<ShipmentDetailPage> {
  bool _accepting = false;
  bool _checking = false;

  int get _id => widget.shipmentId;

  Future<void> _refresh() async {
    ref.invalidate(shipmentDetailProvider(_id));
    try {
      await ref.read(shipmentDetailProvider(_id).future);
    } catch (_) {}
  }

  Future<void> _accept(ShipmentDetail d) async {
    final ok = await showConfirmSheet(
      context,
      title: CmCopy.acceptConfirmTitle,
      message:
          'Teslimat "Teslim alındı" olarak kaydedilir ve bayinize bildirilir. Bu işlem geri alınamaz.',
      confirmLabel: 'Onayla',
      icon: Icons.verified_rounded,
      tone: AknTone.ok,
      content: AknCard(
        shadow: false,
        child: Column(
          children: [
            FactRow(
              label: 'Teslim edilen',
              value: Fmt.liters(d.deliveredLiters),
            ),
            FactRow(label: 'Planlanan', value: Fmt.liters(d.plannedLiters)),
            if (d.deliveryDocumentNo != null)
              FactRow(label: 'İrsaliye no', value: d.deliveryDocumentNo!),
            if (d.recipientName != null)
              FactRow(label: 'Teslim alan', value: d.recipientName!),
          ],
        ),
      ),
    );
    if (!ok || !mounted) return;
    setState(() {
      _accepting = true;
      _checking = false;
    });
    try {
      await ref
          .read(shipmentCommandsProvider)
          .accept(
            _id,
            onChecking: () {
              if (mounted) setState(() => _checking = true);
            },
          );
      if (!mounted) return;
      AknHaptics.success();
      // Bildirim ekran okuyucuya da duyurulur (AppToast).
      AppToast.success(CmCopy.accepted, context: context);
    } catch (e) {
      if (mounted) {
        showFailureToast(context, e);
        await _refresh();
      }
    } finally {
      if (mounted) {
        setState(() {
          _accepting = false;
          _checking = false;
        });
      }
    }
  }

  Future<void> _dispute(ShipmentDetail d) async {
    final sent = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => DisputePage(detail: d),
      ),
    );
    if (sent == true && mounted) await _refresh();
  }

  Future<void> _openDoc(DocRequest r) => openGeneratedDocument(context, ref, r);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(shipmentDetailProvider(_id));
    final policy = ref.watch(accessPolicyProvider);
    final online = ref.watch(isOnlineProvider);
    final d = async.valueOrNull;
    final canAct = d != null && (d.actions.canAccept || d.actions.canDispute);
    return AppScaffold(
      title: d?.code ?? 'Teslimat',
      refreshing: async.isLoading && d != null,
      actionBar: canAct
          ? _ActionBar(
              detail: d,
              online: online,
              accepting: _accepting,
              checking: _checking,
              onAccept: () => _accept(d),
              onDispute: () => _dispute(d),
            )
          : null,
      body: async.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const _DetailSkeleton(),
        error: (e, _) =>
            CmFailureView(failure: AppFailure.from(e), onRetry: _refresh),
        data: (d) => PullToRefresh(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _Hero(detail: d),
              if (d.isDelivered) DeliveredPlate(detail: d),
              if (d.actions.canAccept)
                const AknBanner(
                  margin: EdgeInsets.fromLTRB(20, 16, 20, 0),
                  tone: AknTone.brand,
                  icon: Icons.fact_check_outlined,
                  title: 'Teslimatı kontrol edip onaylayın',
                  message:
                      'Teslim edilen miktarı, irsaliye numarasını ve fotoğrafları kontrol edin. Sorun varsa itiraz edin.',
                ),
              if (d.isDelivered) ProofCard(detail: d),
              if (d.status == ShipmentStatus.disputed ||
                  d.disputePhotos.isNotEmpty)
                _DisputeCard(detail: d, onAddPhoto: () => _dispute(d)),
              _TimelineCard(detail: d),
              _VehicleCard(detail: d),
              _PlaceCard(place: d.place),
              if (policy.cmShipmentDocuments &&
                  d.status != ShipmentStatus.unknown)
                _DocumentsCard(detail: d, onOpen: _openDoc),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.detail,
    required this.online,
    required this.accepting,
    required this.checking,
    required this.onAccept,
    required this.onDispute,
  });

  final ShipmentDetail detail;
  final bool online;
  final bool accepting;
  final bool checking;
  final VoidCallback onAccept;
  final VoidCallback onDispute;

  static const _disputeLabel = 'İtiraz et';
  static const _acceptLabel = 'Teslimatı onayla';

  /// Yan yana (itiraz 2, onay 3 pay) yalnızca iki etiket de simgesiyle tek satırda bütün sığıyorsa;
  /// dar telefonda onay üstte, itiraz altında tam genişlikte (itiraz hiç kısalmaz).
  static bool _fitsRow(BuildContext context, double width) {
    if (MediaQuery.textScalerOf(context).scale(15) > 22) return false;
    const gap = 12.0;
    final unit = (width - gap) / 5;
    return AknButton.fitsOneLine(
          context,
          _disputeLabel,
          unit * 2,
          bordered: true,
        ) &&
        AknButton.fitsOneLine(context, _acceptLabel, unit * 3);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final dispute = AknButton.danger(
      label: _disputeLabel,
      expand: true,
      onPressed: online && !accepting && detail.actions.canDispute
          ? onDispute
          : null,
    );
    final accept = AknButton(
      label: _acceptLabel,
      expand: true,
      loading: accepting,
      loadingLabel: checking ? CmCopy.acceptChecking : 'Gönderiliyor',
      onPressed: online && detail.actions.canAccept ? onAccept : null,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!online)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              CmCopy.offlineAction,
              style: t.caption,
              textAlign: TextAlign.center,
            ),
          )
        else if (checking)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                CmCopy.acceptChecking,
                style: t.caption,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) =>
              constraints.hasBoundedWidth &&
                  _fitsRow(context, constraints.maxWidth)
              ? Row(
                  children: [
                    Expanded(flex: 2, child: dispute),
                    const SizedBox(width: 10),
                    Expanded(flex: 3, child: accept),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [accept, const SizedBox(height: 8), dispute],
                ),
        ),
      ],
    );
  }
}

/// Nesne sayfasının başı (tasarım v2 §6.1, §7.10): `display` başlık ("10.000 L motorin"), nokta ve
/// gün, müşterinin gözünden durum lambası ve saat, sipariş bağlantısı; yolda ya da planlıyken büyük
/// rota çizgisi (bayi → nokta). Canlı konum iddiası yok: araç işareti çizginin ortasında durur.
class _Hero extends StatelessWidget {
  const _Hero({required this.detail});

  final ShipmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final t = context.aknText;
    final c = context.akn;
    final lamp = AknStatus.shipmentLamp(
      d.status,
      StatusViewer.customer(canDecide: d.actions.canAccept),
      serverLabel: d.statusLabel,
    );
    final litres = Fmt.liters(d.deliveredLiters ?? d.plannedLiters);
    final product = d.productName == null
        ? null
        : TurkishText.lower(d.productName!);
    final title = product == null ? litres : '$litres $product';
    final day = d.deliveredAt ?? d.scheduledAt;
    final sub = [?d.place.name, if (day != null) _dayPhrase(day)].join(', ');
    final inTransit = d.status == ShipmentStatus.inTransit;
    final planned = d.status == ShipmentStatus.planned;
    final timeNote = switch (d.status) {
      ShipmentStatus.inTransit || ShipmentStatus.planned =>
        d.scheduledAt == null ? null : 'planlanan ${Fmt.time(d.scheduledAt)}',
      ShipmentStatus.reported ||
      ShipmentStatus.accepted ||
      ShipmentStatus.disputed =>
        d.deliveredAt == null ? null : 'teslim ${Fmt.time(d.deliveredAt)}',
      _ => null,
    };
    final from = d.stationTitle == null ? null : shortTitle(d.stationTitle!);
    final origin = [
      ?from,
      if (d.dispatchedAt != null) '${Fmt.time(d.dispatchedAt)} çıktı',
    ].join(', ');
    final destination = d.scheduledAt == null
        ? (d.place.name ?? '')
        : 'planlanan varış ${Fmt.time(d.scheduledAt)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Nesne başlığı en çok 1,5× büyür (büyük yazıda ilk ekranda durum ve plaka görünsün).
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.5,
            child: Semantics(
              header: true,
              child: Text(title, style: t.display.copyWith(color: c.ink)),
            ),
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(sub, style: t.bodySmall.copyWith(color: c.dim)),
          ],
          const SizedBox(height: 14),
          AknStatusLine(
            lamp: AknLamp.status(lamp),
            trailing: timeNote == null
                ? null
                : Text(
                    timeNote,
                    style: t.bodySmall.copyWith(
                      color: c.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
          if (inTransit || planned) ...[
            const SizedBox(height: 16),
            TruckRoute(
              moving: inTransit,
              progress: inTransit ? null : 0,
              height: 22,
              originLabel: origin.isEmpty ? null : origin,
              destinationLabel: destination.isEmpty ? null : destination,
              semanticLabel: [
                lamp.label,
                if (from != null)
                  '$from bayisinden ${d.place.name ?? 'teslimat noktasına'}',
                if (d.scheduledAt != null)
                  'planlanan varış ${Fmt.time(d.scheduledAt)}',
                'Araç konumu canlı izlenmez',
              ].join('. '),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 16,
            runSpacing: 0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AknInlineLink(
                label: 'Sipariş ${d.orderNumber}',
                onTap: () => context.push(AppRoutes.order(d.orderId)),
              ),
              if (d.stationTitle != null)
                Text(
                  d.stationTitle!,
                  style: t.bodySmall.copyWith(color: c.dim),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "22 Ekim Perşembe" (bugün / yarın / dün sözcükle).
String _dayPhrase(DateTime instant) {
  final label = Fmt.dayLabel(instant);
  if (label == 'Bugün' || label == 'Yarın' || label == 'Dün') {
    return TurkishText.lower(label);
  }
  final w = TrTime.wall(instant);
  return '${w.day} ${Fmt.monthNames[w.month - 1]} ${Fmt.weekdayNames[w.weekday - 1]}';
}

/// "Demir Petrol Akaryakıt Ltd. Şti." → "Demir Petrol".
String shortTitle(String title) {
  const stops = {'akaryakıt', 'ltd.', 'şti.', 'a.ş.', 'tic.', 'san.', 've'};
  final kept = <String>[];
  for (final w in title.trim().split(RegExp(r'\s+'))) {
    if (stops.contains(TurkishText.lower(w))) break;
    kept.add(w);
  }
  return kept.isEmpty ? title.trim() : kept.join(' ');
}

/// Teslim edilenin plakası (tasarım v2 §5.2, §7.10): sayaç okuması büyük, kuralın altında sipariş
/// edilen, fark ve teslim saati. Ekranın tek plakası.
class DeliveredPlate extends StatelessWidget {
  const DeliveredPlate({super.key, required this.detail});

  final ShipmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final diff = d.difference;
    final same = diff == null || diff.abs() < 0.0005;
    final diffValue = diff == null
        ? Fmt.dash
        : same
        ? '0'
        : '${diff > 0 ? '+' : '−'}${Fmt.number(diff.abs(), maxFraction: 3)}';
    final at = d.deliveredAt;
    final today = at != null && Fmt.dayLabel(at) == 'Bugün';
    final spoken = [
      'Teslim edilen ${Fmt.liters(d.deliveredLiters)}',
      'sipariş ${Fmt.liters(d.plannedLiters)}',
      diff == null
          ? 'fark bilinmiyor'
          : same
          ? 'fark yok'
          : 'fark ${diff > 0 ? 'artı' : 'eksi'} ${Fmt.liters(diff.abs())}',
      if (at != null) 'teslim ${Fmt.dateTime(at)}',
    ].join(', ');
    return CmPlate(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      semanticLabel: spoken,
      head: const PlateHead(
        icon: Icons.local_gas_station_outlined,
        title: 'Teslim edilen',
      ),
      figure: PlateFigure(
        value: Fmt.number(d.deliveredLiters, maxFraction: 3),
        unit: 'L',
      ),
      readouts: [
        PlateReadout(
          label: 'Sipariş',
          value: Fmt.number(d.plannedLiters, maxFraction: 3),
          unit: 'L',
        ),
        PlateReadout(
          label: 'Fark',
          value: diffValue,
          unit: diff == null ? null : 'L',
        ),
        PlateReadout(
          label: today || at == null ? 'Saat' : 'Teslim',
          value: at == null
              ? Fmt.dash
              : today
              ? Fmt.time(at)
              : Fmt.dayMonth(at),
        ),
      ],
    );
  }
}

/// "Teslim kanıtı": irsaliye no, teslim alan, not, zaman, fotoğraflar, imza ya da imza alınamama
/// nedeni. Litreler ve fark plakadadır ([DeliveredPlate]).
class ProofCard extends StatelessWidget {
  const ProofCard({super.key, required this.detail});

  final ShipmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final c = context.akn;
    final t = context.aknText;
    final photos = d.deliveryPhotos;
    final signature = d.signature;
    return CmSection(
      title: CmCopy.proofTitle,
      subtitle: d.deliveredAt == null
          ? null
          : '${Fmt.dateTime(d.deliveredAt)}${d.timeSource == 'device' ? ', cihaz saati' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FactRow(
            label: 'İrsaliye no',
            value: d.deliveryDocumentNo ?? Fmt.dash,
          ),
          FactRow(label: 'Teslim alan', value: d.recipientName ?? Fmt.dash),
          if (d.deliveryNote != null)
            FactRow(label: 'Not', value: d.deliveryNote!),
          const SizedBox(height: 12),
          Text(
            'Teslimat fotoğrafları',
            style: t.label.copyWith(color: c.ink, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (photos.isEmpty)
            Text(
              'Fotoğraf eklenmemiş.',
              style: t.bodySmall.copyWith(color: c.dim),
            )
          else
            AttachmentGallery(attachments: photos),
          const SizedBox(height: 16),
          Text(
            'İmza',
            style: t.label.copyWith(color: c.ink, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (signature != null)
            _SignatureView(attachment: signature)
          else if (d.signatureWaiverLabel != null)
            AknBanner(
              tone: AknTone.info,
              icon: Icons.draw_outlined,
              title: 'İmza alınamadı',
              message: d.signatureWaiverLabel!,
            )
          else
            Text('İmza alınmamış.', style: t.bodySmall.copyWith(color: c.dim)),
        ],
      ),
    );
  }
}

class _SignatureView extends ConsumerWidget {
  const _SignatureView({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.akn;
    final bytes = ref.watch(
      attachmentBytesProvider((
        publicId: attachment.publicId,
        approvalId: null,
      )),
    );
    return Semantics(
      container: true,
      image: true,
      label: 'Teslim imzası',
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: AknRadius.card,
          border: Border.all(color: c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: bytes.when(
          data: (b) => Image.memory(b, fit: BoxFit.contain, cacheHeight: 240),
          loading: () => const Center(child: ChevronSpinner(size: 20)),
          error: (_, _) =>
              Center(child: Icon(Icons.broken_image_outlined, color: c.dim)),
        ),
      ),
    );
  }
}

class _DisputeCard extends StatelessWidget {
  const _DisputeCard({required this.detail, required this.onAddPhoto});

  final ShipmentDetail detail;
  final VoidCallback onAddPhoto;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final t = context.aknText;
    return CmSection(
      title: 'İtiraz',
      subtitle: d.status == ShipmentStatus.disputed
          ? 'Bayiniz düzeltme bildirince yeniden onayınız istenecek.'
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (d.disputeNote != null) Text(d.disputeNote!, style: t.body),
          if (d.disputePhotos.isNotEmpty) ...[
            const SizedBox(height: 12),
            AttachmentGallery(attachments: d.disputePhotos),
          ],
          if (d.actions.canAddDisputePhoto &&
              d.status == ShipmentStatus.disputed) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: AknButton.secondary(
                label: 'Fotoğraf ekle',
                icon: Icons.add_a_photo_outlined,
                size: AknButtonSize.small,
                onPressed: onAddPhoto,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.detail});

  final ShipmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final s = d.status;
    String? at(DateTime? v) =>
        v == null ? null : '${Fmt.dayLabel(v)} ${Fmt.time(v)}';
    // Büyük yazı boyutunda zaman, başlığın yanına sığmaz; alt satıra iner.
    final stack = MediaQuery.textScalerOf(context).scale(10) > 13;
    String? time(DateTime? v) => stack ? null : at(v);
    String? sub(DateTime? v, [String? rest]) {
      final parts = [if (stack) ?at(v), ?rest];
      return parts.isEmpty ? null : parts.join(', ');
    }

    final cancelled = s == ShipmentStatus.cancelled;
    final steps = <TimelineStep>[
      TimelineStep(
        title: 'Planlandı',
        subtitle: d.scheduledAt == null
            ? null
            : 'Plan ${Fmt.dateTime(d.scheduledAt)}${d.place.window == null ? '' : ', kabul ${d.place.window}'}',
        state: TimelineState.done,
        icon: Icons.event_rounded,
      ),
      if (cancelled)
        const TimelineStep(
          title: 'İptal edildi',
          subtitle: 'Bayi bu sevkiyatı iptal etti.',
          state: TimelineState.failed,
          icon: Icons.block_rounded,
        )
      else ...[
        TimelineStep(
          title: 'Yolda',
          time: time(d.dispatchedAt),
          subtitle: sub(d.dispatchedAt),
          state: s == ShipmentStatus.planned
              ? TimelineState.upcoming
              : (s == ShipmentStatus.inTransit
                    ? TimelineState.current
                    : TimelineState.done),
          icon: Icons.local_shipping_rounded,
        ),
        TimelineStep(
          title: 'Teslim edildi',
          time: time(d.deliveredAt),
          subtitle: sub(
            d.deliveredAt,
            d.deliveredLiters == null
                ? null
                : '${Fmt.liters(d.deliveredLiters)}, ${d.recipientName ?? 'teslim alan belirtilmemiş'}',
          ),
          state: d.isDelivered
              ? (s == ShipmentStatus.reported
                    ? TimelineState.current
                    : TimelineState.done)
              : TimelineState.upcoming,
          icon: Icons.fact_check_rounded,
        ),
        TimelineStep(
          title: s == ShipmentStatus.disputed ? 'İtiraz edildi' : 'Kabul',
          time: time(d.acceptedAt),
          subtitle: sub(d.acceptedAt),
          state: switch (s) {
            ShipmentStatus.accepted => TimelineState.done,
            ShipmentStatus.disputed => TimelineState.failed,
            _ => TimelineState.upcoming,
          },
          icon: s == ShipmentStatus.disputed
              ? Icons.report_rounded
              : Icons.verified_rounded,
        ),
      ],
    ];
    return CmSection(
      title: 'Sevkiyat akışı',
      child: StepTimeline(
        steps: steps,
        yourMove: s == ShipmentStatus.reported && d.actions.canAccept,
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.detail});

  final ShipmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final t = context.aknText;
    final c = context.akn;
    if (d.vehiclePlate == null && d.driverName == null) {
      return const SizedBox.shrink();
    }
    return CmSection(
      title: 'Araç ve şoför',
      child: Semantics(
        container: true,
        label: [
          if (d.driverName != null) 'Şoför ${d.driverName}',
          if (d.vehiclePlate != null) 'plaka ${Fmt.plate(d.vehiclePlate)}',
        ].join(', '),
        excludeSemantics: true,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.driverName ?? 'Şoför atanmadı',
                    style: t.headline.copyWith(color: c.ink),
                  ),
                  Text('Şoför', style: t.bodySmall.copyWith(color: c.dim)),
                ],
              ),
            ),
            if (d.vehiclePlate != null) ...[
              const SizedBox(width: 12),
              PlateBadge(plate: d.vehiclePlate!),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place});

  final ShipmentPlace place;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return CmSection(
      title: 'Teslimat noktası',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            place.name ?? Fmt.dash,
            style: t.headline.copyWith(color: context.akn.ink),
          ),
          if (place.address != null)
            Text(
              place.address!,
              style: t.bodySmall.copyWith(color: context.akn.dim),
            ),
          if (place.cityDistrict != null)
            Text(
              place.cityDistrict!,
              style: t.bodySmall.copyWith(color: context.akn.dim),
            ),
          if (place.window != null) ...[
            const SizedBox(height: 6),
            FactRow(label: 'Kabul saati', value: place.window!),
          ],
          if (place.hasCoordinates) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: AknButton.secondary(
                label: CmCopy.openInMaps,
                icon: Icons.map_outlined,
                size: AknButtonSize.small,
                onPressed: () => openInMaps(
                  place.latitude!,
                  place.longitude!,
                  label: place.name,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DocumentsCard extends StatelessWidget {
  const _DocumentsCard({required this.detail, required this.onOpen});

  final ShipmentDetail detail;
  final Future<void> Function(DocRequest r) onOpen;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final docs = <DocRequest>[
      if (d.status != ShipmentStatus.cancelled) ReceiptDocRequest(d.id),
      WaybillDocRequest(d.id),
    ];
    return CmSection(
      title: CmCopy.documentsTitle,
      subtitle: 'PDF olarak oluşturulur; paylaşabilir ya da yazdırabilirsiniz.',
      bleed: true,
      child: AknLedger(
        children: [
          for (final r in docs)
            DocumentTile(request: r, onTap: () => onOpen(r)),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) => Shimmer(
    semanticLabel: 'Teslimat yükleniyor',
    child: ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: const [
        SkeletonBox(height: 36, width: 220, radius: 6),
        SizedBox(height: 10),
        SkeletonBox(height: 14, width: 180),
        SizedBox(height: 20),
        SkeletonBox(height: 22, radius: 6),
        SizedBox(height: 28),
        SkeletonBox(height: 180, radius: 20),
      ],
    ),
  );
}
