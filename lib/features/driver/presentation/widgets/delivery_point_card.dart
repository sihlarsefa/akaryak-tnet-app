import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/env/app_env.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../copy.dart';
import '../../data/driver_models.dart';
import 'navigation.dart';

/// "Teslimat noktası" kartı (tasarım v3 §4: beyaz kart r20, kart gölgesi, sayfanın 20 px
/// kenarında): harita açık derlemelerde üstte küçük harita iğnesi (r14), solda yumuşak turuncu
/// kuyuda konum simgesi, nokta adı ve adres, "Yol tarifi" (alttaki rafta yoksa) ve "Haritada aç";
/// teslim saatleri ve tank kapasitesi içeriden ince çizgilerle ayrılmış olgu satırları. Kapı notu
/// ve teslim alacak kişi plakanın hemen altında durur (ayrıntı sayfası).
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
    final facts = [
      if (row.windowLabel != null)
        FactRow(
          icon: PhosphorIconsRegular.clock,
          label: DriverCopy.window,
          value: row.windowLabel!,
        ),
      if (detail.tankCapacityLiters != null)
        FactRow(
          icon: PhosphorIconsRegular.cylinder,
          label: DriverCopy.tankCapacity,
          value: Fmt.liters(detail.tankCapacityLiters),
        ),
    ];

    return AknCard(
      margin: const EdgeInsets.symmetric(horizontal: AknSpace.page),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mapsEnabled && lat != null && lng != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _MapPin(lat: lat, lng: lng, title: row.deliveryPointName),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: 40,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.brandSoft,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(AknRadius.sm),
                    ),
                  ),
                  child: Icon(
                    PhosphorIconsRegular.mapPin,
                    size: 22,
                    color: c.brandInk,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.deliveryPointName ?? DriverCopy.deliveryPoint,
                      style: t.bodyStrong.copyWith(
                        color: c.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      address ?? DriverCopy.noAddress,
                      style: t.body.copyWith(color: c.dim),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasTarget)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (showNavigate)
                    AknButton.secondary(
                      label: DriverCopy.actionNavigate,
                      icon: PhosphorIconsRegular.navigationArrow,
                      onPressed: () => openNavigation(
                        context,
                        lat: lat,
                        lng: lng,
                        address: address,
                      ),
                    ),
                  AknButton.ghost(
                    label: DriverCopy.openInMaps,
                    icon: PhosphorIconsRegular.mapTrifold,
                    onPressed: () => showOnMap(
                      context,
                      lat: lat,
                      lng: lng,
                      address: address,
                    ),
                  ),
                ],
              ),
            ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (var i = 0; i < facts.length; i++) ...[
              const AknLedgerDivider(indent: 0),
              facts[i],
            ],
          ],
          if (facts.isEmpty) const SizedBox(height: 8),
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
        borderRadius: const BorderRadius.all(Radius.circular(AknRadius.md)),
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
