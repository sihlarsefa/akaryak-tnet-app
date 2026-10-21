import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/env/app_env.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../copy.dart';
import '../../data/driver_models.dart';
import 'navigation.dart';

/// "Teslimat noktası" bölümü (tasarım v2 §4.5: başlık + içerik, kutu yok): harita açık derlemelerde
/// küçük harita iğnesi, nokta adı ve adres, "Yol tarifi" (alttaki rafta yoksa) ve "Haritada aç";
/// teslim saatleri ve tank kapasitesi olgu satırları. Kapı notu ve teslim alacak kişi plakanın
/// hemen altında durur (ayrıntı sayfası).
class DeliveryPointCard extends ConsumerWidget {
  const DeliveryPointCard({
    super.key,
    required this.detail,
    this.showNavigate = true,
  });

  final DriverShipmentDetail detail;

  /// "Yol tarifi" düğmesi (alt raf zaten gösteriyorsa false).
  final bool showNavigate;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mapsEnabled && lat != null && lng != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _MapPin(lat: lat, lng: lng, title: row.deliveryPointName),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AknSpace.page),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.place_outlined, size: 22, color: c.dim),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.deliveryPointName ?? DriverCopy.deliveryPoint,
                      style: t.bodyStrong.copyWith(color: c.ink),
                    ),
                    Text(
                      address ?? DriverCopy.noAddress,
                      style: t.body.copyWith(color: c.ink),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (hasTarget)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (showNavigate)
                  AknButton.secondary(
                    label: DriverCopy.actionNavigate,
                    icon: Icons.directions_outlined,
                    onPressed: () => openNavigation(
                      context,
                      lat: lat,
                      lng: lng,
                      address: address,
                    ),
                  ),
                AknButton.ghost(
                  label: DriverCopy.openInMaps,
                  icon: Icons.map_outlined,
                  onPressed: () =>
                      showOnMap(context, lat: lat, lng: lng, address: address),
                ),
              ],
            ),
          ),
        if (row.windowLabel != null || detail.tankCapacityLiters != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              children: [
                if (row.windowLabel != null)
                  FactRow(
                    icon: Icons.schedule_outlined,
                    label: DriverCopy.window,
                    value: row.windowLabel!,
                  ),
                if (row.windowLabel != null &&
                    detail.tankCapacityLiters != null)
                  Divider(height: 1, thickness: 1, color: c.line),
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
        borderRadius: AknRadius.card,
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
