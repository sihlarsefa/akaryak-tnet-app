import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/cm_access.dart';
import '../../application/delivery_points_controller.dart';
import '../../copy.dart';
import '../../data/delivery_point.dart';
import '../cm_widgets.dart';

/// Teslimat noktaları listesi (çevrimdışı önbellekli). Ekle / düzenle sayfası `/delivery-points/new`,
/// `/delivery-points/{id}`.
class DeliveryPointsPage extends ConsumerWidget {
  const DeliveryPointsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(deliveryPointsControllerProvider);
    final ctrl = ref.read(deliveryPointsControllerProvider.notifier);
    final policy = ref.watch(accessPolicyProvider);
    final online = ref.watch(isOnlineProvider);
    final points = [...s.active, if (s.includeInactive) ...s.inactive];
    Widget body;
    if (s.loading && s.points.isEmpty) {
      body = const SkeletonList(itemCount: 4, lines: 4);
    } else if (s.points.isEmpty && s.error != null) {
      body = ListView(
        children: [CmFailureView(failure: s.error!, onRetry: ctrl.load)],
      );
    } else if (points.isEmpty) {
      body = PullToRefresh(
        onRefresh: () => ctrl.load(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            EmptyState(
              title: CmCopy.pointsEmpty,
              message: CmCopy.pointsEmptyMessage,
              illustration: AknIllustration.delivery,
              actionLabel: policy.cmPointCreate && online
                  ? 'Teslimat noktası ekle'
                  : null,
              onAction: () => context.push('/delivery-points/new'),
            ),
          ],
        ),
      );
    } else {
      body = PullToRefresh(
        onRefresh: () => ctrl.load(refresh: true),
        child: StaggerScope(
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            itemCount: points.length,
            itemBuilder: (context, i) => StaggerItem(
              index: i,
              child: DeliveryPointCard(
                point: points[i],
                onEdit: policy.cmPointEdit && points[i].isActive
                    ? () => context.push('/delivery-points/${points[i].id}')
                    : null,
              ),
            ),
          ),
        ),
      );
    }
    return AppScaffold(
      title: CmCopy.pointsTitle,
      subtitle: s.points.isEmpty ? null : '${s.active.length} etkin nokta',
      refreshing: s.refreshing,
      actionBar: policy.cmPointCreate
          ? cmBar(
              AknButton(
                label: 'Yeni teslimat noktası',
                icon: Icons.add_location_alt_rounded,
                expand: true,
                onPressed: online
                    ? () => context.push('/delivery-points/new')
                    : null,
              ),
            )
          : null,
      body: Column(
        children: [
          if (s.fromCache) CachedNote(storedAt: s.storedAt),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FilterChips<bool>(
              options: const [
                FilterOption(value: true, label: 'Pasifleri göster'),
              ],
              selected: {if (s.includeInactive) true},
              multi: true,
              onChanged: (set) => ctrl.setIncludeInactive(set.isNotEmpty),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Teslimat noktası kartı: adres, saat aralığı, tank, sorumlu, erişim notu, konum.
class DeliveryPointCard extends StatelessWidget {
  const DeliveryPointCard({super.key, required this.point, this.onEdit});

  final DeliveryPoint point;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final p = point;
    final t = context.aknText;
    final c = context.akn;
    final contact = [
      p.contactName,
      p.contactPhone == null ? null : Fmt.phone(p.contactPhone),
    ].whereType<String>().join(' · ');
    Widget info(IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: c.dim),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text, style: t.caption.copyWith(color: c.text)),
        ),
      ],
    );
    return AknCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      onTap: onEdit,
      semanticLabel: [
        p.name,
        if (!p.isActive) 'pasif',
        p.address,
        p.cityDistrict,
        if (p.window != null) 'Kabul saati ${p.window}',
        if (p.tankCapacityLiters != null)
          'Tank ${Fmt.liters(p.tankCapacityLiters)}',
        if (contact.isNotEmpty) 'Sorumlu $contact',
        p.hasLocation ? 'konum kayıtlı' : 'konum yok',
        if (onEdit != null) 'düzenle',
      ].where((x) => x.isNotEmpty).join(', '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!p.isActive)
                  CmHeadRow(
                    title: Text(p.name, style: t.bodyStrong),
                    trailing: const StatusChip(
                      label: 'Pasif',
                      tone: AknTone.neutral,
                      icon: Icons.block_rounded,
                      size: StatusChipSize.small,
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(child: Text(p.name, style: t.bodyStrong)),
                      if (onEdit != null)
                        Icon(Icons.edit_rounded, size: 18, color: c.faint),
                    ],
                  ),
                const SizedBox(height: 4),
                if (p.address.isNotEmpty) Text(p.address, style: t.bodySmall),
                if (p.cityDistrict.isNotEmpty)
                  Text(p.cityDistrict, style: t.caption),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    if (p.window != null)
                      info(Icons.schedule_rounded, p.window!),
                    if (p.tankCapacityLiters != null)
                      info(
                        Icons.propane_tank_rounded,
                        'Tank ${Fmt.liters(p.tankCapacityLiters)}',
                      ),
                    if (contact.isNotEmpty) info(Icons.person_rounded, contact),
                    info(
                      p.hasLocation
                          ? Icons.place_rounded
                          : Icons.location_off_rounded,
                      p.hasLocation ? 'Konum kayıtlı' : 'Konum yok',
                    ),
                  ],
                ),
                if (p.accessNotes != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    p.accessNotes!,
                    style: t.bodySmall.copyWith(fontStyle: FontStyle.italic),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (p.contactPhone != null || p.hasLocation) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                if (p.contactPhone != null)
                  AknButton.ghost(
                    label: 'Ara',
                    icon: Icons.call_rounded,
                    size: AknButtonSize.small,
                    semanticLabel: '${p.contactName ?? 'Sorumlu'} kişiyi ara',
                    onPressed: () => callPhone(p.contactPhone!),
                  ),
                if (p.hasLocation)
                  AknButton.ghost(
                    label: CmCopy.openInMaps,
                    icon: Icons.map_rounded,
                    size: AknButtonSize.small,
                    onPressed: () =>
                        openInMaps(p.latitude!, p.longitude!, label: p.name),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
