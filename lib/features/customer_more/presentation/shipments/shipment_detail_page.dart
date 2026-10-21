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
      title: 'Teslimat',
      subtitle: d?.code,
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
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _Hero(detail: d),
              if (d.actions.canAccept)
                const AknBanner(
                  margin: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  tone: AknTone.warn,
                  icon: Icons.fact_check_rounded,
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

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final stacked = MediaQuery.textScalerOf(context).scale(15) > 22;
    final dispute = AknButton.secondary(
      label: 'İtiraz et',
      icon: Icons.report_rounded,
      expand: true,
      onPressed: online && !accepting && detail.actions.canDispute
          ? onDispute
          : null,
    );
    final accept = AknButton(
      label: 'Teslimatı onayla',
      icon: Icons.verified_rounded,
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
        if (stacked) ...[
          accept,
          const SizedBox(height: 8),
          dispute,
        ] else
          Row(
            children: [
              Expanded(child: dispute),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: accept),
            ],
          ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.detail});

  final ShipmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    return AknHeroPanel(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Builder(
        builder: (context) {
          final t = context.aknText;
          final c = context.akn;
          final style = d.status.statusStyle.withLabel(d.statusLabel);
          final fill = d.deliveredLiters == null || d.plannedLiters <= 0
              ? null
              : (d.deliveredLiters! / d.plannedLiters).clamp(0.0, 1.0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    header: true,
                    child: Text(d.code, style: t.headline),
                  ),
                  StatusChip.style(style),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.productName ?? 'Teslimat',
                          style: t.title.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          d.deliveredLiters == null
                              ? '${Fmt.liters(d.plannedLiters)} planlandı'
                              : '${Fmt.liters(d.deliveredLiters)} teslim edildi',
                          style: t.body.copyWith(color: c.text),
                        ),
                      ],
                    ),
                  ),
                  if (fill != null)
                    FuelDrop(
                      fill: fill,
                      size: 48,
                      semanticLabel:
                          'Planlananın yüzde ${(fill * 100).round()} kadarı teslim edildi',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _HeroLink(
                    icon: Icons.receipt_long_rounded,
                    label: d.orderNumber,
                    semantic: 'Sipariş ${d.orderNumber}, siparişi aç',
                    onTap: () => context.push(AppRoutes.order(d.orderId)),
                  ),
                  if (d.stationTitle != null)
                    _HeroInfo(
                      icon: Icons.storefront_rounded,
                      text: d.stationTitle!,
                    ),
                ],
              ),
              if (d.status == ShipmentStatus.inTransit) ...[
                const SizedBox(height: 12),
                const TruckRoute(
                  progress: 0.55,
                  height: 36,
                  semanticLabel: 'Yolda (canlı konum değildir)',
                ),
                const SizedBox(height: 4),
                Text(
                  d.dispatchedAt == null
                      ? 'Yolda (canlı konum değildir)'
                      : 'Yolda · ${Fmt.time(d.dispatchedAt)}\'de çıktı (canlı konum değildir)',
                  style: t.caption,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HeroLink extends StatelessWidget {
  const _HeroLink({
    required this.icon,
    required this.label,
    required this.semantic,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String semantic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AknRadius.chip,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: c.brand),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: t.label.copyWith(
                    color: c.brand,
                    decoration: TextDecoration.underline,
                    decorationColor: c.brand,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroInfo extends StatelessWidget {
  const _HeroInfo({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: c.dim),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text, style: t.label.copyWith(color: c.text)),
          ),
        ],
      ),
    );
  }
}

/// "Teslim kanıtı": teslim / plan litre ve fark, irsaliye no, teslim alan, zaman, fotoğraflar, imza ya
/// da imza alınamama nedeni.
class ProofCard extends StatelessWidget {
  const ProofCard({super.key, required this.detail});

  final ShipmentDetail detail;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final c = context.akn;
    final t = context.aknText;
    final diff = d.difference;
    final diffTone = diff == null
        ? AknTone.neutral
        : (diff.abs() < 0.0005
              ? AknTone.ok
              : (diff < 0 ? AknTone.warn : AknTone.info));
    final diffText = diff == null
        ? Fmt.dash
        : (diff.abs() < 0.0005
              ? 'Fark yok'
              : '${diff > 0 ? '+' : '−'}${Fmt.liters(diff.abs())}');
    final photos = d.deliveryPhotos;
    final signature = d.signature;
    return CmSection(
      title: CmCopy.proofTitle,
      subtitle: d.deliveredAt == null
          ? null
          : '${Fmt.dateTime(d.deliveredAt)}${d.timeSource == 'device' ? ' · cihaz saati' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label:
                'Teslim edilen ${Fmt.liters(d.deliveredLiters)}, planlanan ${Fmt.liters(d.plannedLiters)}, $diffText',
            excludeSemantics: true,
            child: Row(
              children: [
                Expanded(
                  child: _LitreTile(
                    label: 'Teslim edilen',
                    value: Fmt.liters(d.deliveredLiters),
                    strong: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LitreTile(
                    label: 'Planlanan',
                    value: Fmt.liters(d.plannedLiters),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(
              label: diffText,
              tone: diffTone,
              icon: diff == null || diff.abs() < 0.0005
                  ? Icons.check_rounded
                  : Icons.compare_arrows_rounded,
            ),
          ),
          const Divider(height: 24),
          FactRow(
            label: 'İrsaliye no',
            value: d.deliveryDocumentNo ?? Fmt.dash,
            icon: Icons.tag_rounded,
          ),
          FactRow(
            label: 'Teslim alan',
            value: d.recipientName ?? Fmt.dash,
            icon: Icons.person_rounded,
          ),
          if (d.deliveryNote != null)
            FactRow(
              label: 'Not',
              value: d.deliveryNote!,
              icon: Icons.notes_rounded,
            ),
          const SizedBox(height: 8),
          Text('Teslimat fotoğrafları', style: t.label),
          const SizedBox(height: 8),
          if (photos.isEmpty)
            Text('Fotoğraf eklenmemiş.', style: t.bodySmall)
          else
            AttachmentGallery(attachments: photos),
          const SizedBox(height: 16),
          Text('İmza', style: t.label),
          const SizedBox(height: 8),
          if (signature != null)
            _SignatureView(attachment: signature)
          else if (d.signatureWaiverLabel != null)
            AknBanner(
              tone: AknTone.info,
              icon: Icons.draw_rounded,
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

class _LitreTile extends StatelessWidget {
  const _LitreTile({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: strong ? c.brandSoft : c.surfaceAlt,
        borderRadius: AknRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.caption.copyWith(color: c.text)),
          const SizedBox(height: 2),
          AmountText(value, style: t.headline.copyWith(color: c.ink)),
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
          color: const Color(0xFFFFFFFF),
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
      accent: AknTone.danger,
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
              child: AknButton.ghost(
                label: 'Fotoğraf ekle',
                icon: Icons.add_a_photo_rounded,
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
      return parts.isEmpty ? null : parts.join(' · ');
    }

    final cancelled = s == ShipmentStatus.cancelled;
    final steps = <TimelineStep>[
      TimelineStep(
        title: 'Planlandı',
        subtitle: d.scheduledAt == null
            ? null
            : 'Plan: ${Fmt.dateTime(d.scheduledAt)}${d.place.window == null ? '' : ' · ${d.place.window}'}',
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
          title: 'Yola çıktı',
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
                : '${Fmt.liters(d.deliveredLiters)} · ${d.recipientName ?? 'teslim alan belirtilmemiş'}',
          ),
          state: d.isDelivered
              ? (s == ShipmentStatus.reported
                    ? TimelineState.current
                    : TimelineState.done)
              : TimelineState.upcoming,
          icon: Icons.fact_check_rounded,
        ),
        TimelineStep(
          title: s == ShipmentStatus.disputed
              ? 'İtiraz edildi'
              : 'Teslim alındı',
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
      title: 'Süreç',
      child: StepTimeline(steps: steps),
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
    if (d.vehiclePlate == null && d.driverName == null) {
      return const SizedBox.shrink();
    }
    return CmSection(
      title: 'Araç ve şoför',
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (d.vehiclePlate != null) PlateBadge(plate: d.vehiclePlate!),
          if (d.driverName != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.badge_rounded, size: 18),
                const SizedBox(width: 6),
                Flexible(child: Text(d.driverName!, style: t.body)),
              ],
            ),
        ],
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
          Text(place.name ?? Fmt.dash, style: t.bodyStrong),
          if (place.address != null) Text(place.address!, style: t.bodySmall),
          if (place.cityDistrict != null)
            Text(place.cityDistrict!, style: t.bodySmall),
          if (place.window != null) ...[
            const SizedBox(height: 6),
            FactRow(
              label: 'Kabul saati',
              value: place.window!,
              icon: Icons.schedule_rounded,
            ),
          ],
          if (place.hasCoordinates) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: AknButton.ghost(
                label: CmCopy.openInMaps,
                icon: Icons.map_rounded,
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
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
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonBox(height: 150, radius: 24),
        SizedBox(height: 16),
        SkeletonCard(lines: 4, leading: false),
        SkeletonCard(lines: 3, leading: false),
      ],
    ),
  );
}
