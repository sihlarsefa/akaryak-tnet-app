import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/env/app_env.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../copy.dart';
import '../../data/driver_models.dart';
import 'navigation.dart';

/// Teslimat noktası kartı: harita iğnesi (harita açık derlemelerde) ya da adres, "Yol tarifi",
/// "Haritada aç"; yetkili ve "Ara"; giriş notları; tank kapasitesi ve teslim saatleri.
class DeliveryPointCard extends ConsumerWidget {
  const DeliveryPointCard({super.key, required this.detail});

  final DriverShipmentDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.akn;
    final t = context.aknText;
    final mapsEnabled = ref.watch(appEnvProvider).mapsEnabled;
    final row = detail.row;
    final address = detail.fullAddress;
    final lat = detail.latitude;
    final lng = detail.longitude;
    final hasTarget = detail.hasCoordinates || address != null;

    return AknCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mapsEnabled && lat != null && lng != null)
            _MapPin(lat: lat, lng: lng, title: row.deliveryPointName)
          else
            _AddressHeader(
              name: row.deliveryPointName ?? DriverCopy.deliveryPoint,
              hasCoordinates: detail.hasCoordinates,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mapsEnabled && lat != null && lng != null)
                  Text(
                    row.deliveryPointName ?? DriverCopy.deliveryPoint,
                    style: t.bodyStrong,
                  ),
                Text(
                  address ?? DriverCopy.noAddress,
                  style: t.body.copyWith(color: c.text),
                ),
              ],
            ),
          ),
          if (hasTarget)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: AknButton(
                      label: DriverCopy.actionNavigate,
                      icon: Icons.directions_rounded,
                      expand: true,
                      onPressed: () => openNavigation(
                        context,
                        lat: lat,
                        lng: lng,
                        address: address,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AknButton.secondary(
                      label: DriverCopy.openInMaps,
                      icon: Icons.map_outlined,
                      expand: true,
                      onPressed: () => showOnMap(
                        context,
                        lat: lat,
                        lng: lng,
                        address: address,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (detail.contactName != null || detail.contactPhone != null) ...[
            Divider(height: 1, color: c.lineSoft),
            _ContactRow(name: detail.contactName, phone: detail.contactPhone),
          ],
          if (detail.accessNotes != null) ...[
            Divider(height: 1, color: c.lineSoft),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 20, color: c.info.fg),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DriverCopy.accessNotes,
                          style: t.label.copyWith(color: c.dim),
                        ),
                        const SizedBox(height: 2),
                        Text(detail.accessNotes!, style: t.body),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (detail.tankCapacityLiters != null || row.windowLabel != null) ...[
            Divider(height: 1, color: c.lineSoft),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                children: [
                  if (row.windowLabel != null)
                    FactRow(
                      icon: Icons.schedule_rounded,
                      label: DriverCopy.window,
                      value: row.windowLabel!,
                    ),
                  if (detail.tankCapacityLiters != null)
                    FactRow(
                      icon: Icons.propane_tank_outlined,
                      label: DriverCopy.tankCapacity,
                      value: Fmt.liters(detail.tankCapacityLiters),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddressHeader extends StatelessWidget {
  const _AddressHeader({required this.name, required this.hasCoordinates});

  final String name;
  final bool hasCoordinates;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.brandSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.brandLine),
            ),
            child: Icon(Icons.place_rounded, color: c.brandInk, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DriverCopy.deliveryPoint, style: t.caption),
                Text(name, style: t.bodyStrong),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Harita açık derlemelerde küçük, hareketsiz harita iğnesi (dokununca yol tarifi).
class _MapPin extends StatelessWidget {
  const _MapPin({required this.lat, required this.lng, this.title});

  final double lat;
  final double lng;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final target = LatLng(lat, lng);
    return Semantics(
      label: '${DriverCopy.deliveryPoint} haritası',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AknRadius.md),
        ),
        child: SizedBox(
          height: 150,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: target, zoom: 15),
            markers: {
              Marker(
                markerId: const MarkerId('teslimat'),
                position: target,
                infoWindow: InfoWindow(title: title),
              ),
            },
            liteModeEnabled: true,
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            scrollGesturesEnabled: false,
            zoomGesturesEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            onTap: (_) => openNavigation(context, lat: lat, lng: lng),
          ),
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({this.name, this.phone});

  final String? name;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          AknAvatar(name: name ?? DriverCopy.contact, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DriverCopy.contact, style: t.caption),
                Text(name ?? Fmt.dash, style: t.bodyStrong),
                if (phone != null)
                  Text(
                    Fmt.phone(phone),
                    style: t.bodySmall.copyWith(color: c.text),
                  ),
              ],
            ),
          ),
          if (phone != null)
            AknButton.secondary(
              label: DriverCopy.actionCall,
              icon: Icons.call_rounded,
              size: AknButtonSize.small,
              semanticLabel: '${name ?? DriverCopy.contact} kişisini ara',
              onPressed: () => callPhone(context, phone),
            ),
        ],
      ),
    );
  }
}
