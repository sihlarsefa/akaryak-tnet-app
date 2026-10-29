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
              key: const ValueKey('empty'),
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
      // Kartlar sırayla yükselerek gelir; "Pasifleri göster" değişince akış yeniden başlar.
      body = StaggerScope(
        key: ValueKey(s.includeInactive),
        child: PullToRefresh(
          onRefresh: () => ctrl.load(refresh: true),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              top: 4,
              bottom: 16 + MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: points.length,
            itemBuilder: (context, i) => StaggerItem(
              key: ValueKey(points[i].id),
              index: i,
              child: Padding(
                padding: cmListMargin,
                child: DeliveryPointCard(
                  point: points[i],
                  onEdit: policy.cmPointEdit && points[i].isActive
                      ? () => context.push('/delivery-points/${points[i].id}')
                      : null,
                ),
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
                icon: PhosphorIconsRegular.mapPinPlus,
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
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilterChips<bool>(
                options: const [
                  FilterOption(value: true, label: 'Pasifleri göster'),
                ],
                selected: {if (s.includeInactive) true},
                multi: true,
                onChanged: (set) => ctrl.setIncludeInactive(set.isNotEmpty),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Teslimat noktası kartı (tasarım v3 §4): beyaz r20 kart; başta iğne karosu, ad, adres ve il /
/// ilçe; kabul saati, tank ve konum sessiz haplarda; sorumlu ve erişim notu; altta "Ara" ve
/// "Haritada aç". Düzenlenebilirse kart düzenlemeyi açar (ok işareti, basınca 0,97). Pasif nokta
/// soluk ve "Pasif" lambalı.
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
    ].whereType<String>().join(', ');
    final factStyle = t.label.copyWith(
      color: c.ink,
      fontWeight: FontWeight.w500,
    );
    Widget info(IconData icon, String text) => Container(
      padding: const EdgeInsets.fromLTRB(9, 4, 11, 4),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: AknRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: c.dim),
          const SizedBox(width: 5),
          Flexible(child: Text(text, style: factStyle)),
        ],
      ),
    );
    final place = [
      p.address,
      p.cityDistrict,
    ].where((x) => x.isNotEmpty).join(', ');
    final edit = onEdit;
    final tile = AknListTile(
      title: p.name,
      titleStyle: p.isActive
          ? cmRowTitle(context)
          : cmRowTitle(context).copyWith(color: c.dim),
      subtitle: place.isEmpty ? null : place,
      showChevron: edit != null,
      onTap: edit == null
          ? null
          : () {
              AknHaptics.selection();
              edit();
            },
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
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
        ?p.accessNotes,
        if (edit != null) 'düzenle',
      ].where((x) => x.isNotEmpty).join(', '),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!p.isActive) ...[
            const AknLamp(label: 'Pasif', tone: AknTone.neutral),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (p.window != null) info(PhosphorIconsRegular.clock, p.window!),
              if (p.tankCapacityLiters != null)
                info(
                  PhosphorIconsRegular.cylinder,
                  'Tank ${Fmt.liters(p.tankCapacityLiters)}',
                ),
              info(
                p.hasLocation
                    ? PhosphorIconsRegular.mapPin
                    : PhosphorIconsRegular.gpsSlash,
                p.hasLocation ? 'Konum kayıtlı' : 'Konum yok',
              ),
            ],
          ),
          if (contact.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(PhosphorIconsRegular.user, size: 16, color: c.dim),
                const SizedBox(width: 6),
                Flexible(child: Text(contact, style: factStyle)),
              ],
            ),
          ],
          if (p.accessNotes != null) ...[
            const SizedBox(height: 6),
            Text(
              p.accessNotes!,
              style: t.bodySmall.copyWith(color: c.dim),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
    final actions = p.contactPhone != null || p.hasLocation;
    // Kartın içinde düğme varsa kart basılmaz (düğme kendi basışını yapar); satır vurgulanır.
    return AknCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          tile,
          if (actions)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (p.contactPhone != null)
                    AknButton.secondary(
                      label: 'Ara',
                      icon: PhosphorIconsRegular.phone,
                      size: AknButtonSize.small,
                      semanticLabel: '${p.contactName ?? 'Sorumlu'} kişiyi ara',
                      onPressed: () => callPhone(p.contactPhone!),
                    ),
                  if (p.hasLocation)
                    AknButton.secondary(
                      label: CmCopy.openInMaps,
                      icon: PhosphorIconsRegular.mapTrifold,
                      size: AknButtonSize.small,
                      onPressed: () =>
                          openInMaps(p.latitude!, p.longitude!, label: p.name),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
