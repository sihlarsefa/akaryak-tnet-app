import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/ui/ui.dart';

/// Ortada sabit iğneli harita (yalnızca `MAPS_ENABLED` derlemelerinde). Harita kaydırılıp durunca iğnenin
/// altındaki nokta [onPicked] ile bildirilir. Harita anahtarı yoksa bu bileşen hiç kurulmaz.
class MapPinPicker extends StatefulWidget {
  const MapPinPicker({
    super.key,
    required this.onPicked,
    this.initial,
    this.enabled = true,
    this.height = 240,
  });

  final void Function(double latitude, double longitude) onPicked;
  final (double, double)? initial;
  final bool enabled;
  final double height;

  /// Konum yokken Türkiye geneli.
  static const fallback = LatLng(39.0, 35.2);

  @override
  State<MapPinPicker> createState() => _MapPinPickerState();
}

class _MapPinPickerState extends State<MapPinPicker> {
  GoogleMapController? _map;
  LatLng? _center;
  bool _moving = false;

  /// Kamera kod ile taşındı (açılış, konum düğmesi); duruşta bildirilmez. Açılıştaki ilk duruş da
  /// atlanır: kullanıcı haritayı kaydırmadan varsayılan merkez konum olarak kaydedilmez.
  bool _programmatic = true;

  @override
  void didUpdateWidget(MapPinPicker old) {
    super.didUpdateWidget(old);
    final i = widget.initial;
    if (i != null && i != old.initial && !_moving) {
      final target = LatLng(i.$1, i.$2);
      if (_center == null ||
          (_center!.latitude - target.latitude).abs() > 1e-6 ||
          (_center!.longitude - target.longitude).abs() > 1e-6) {
        _programmatic = true;
        _center = target;
        _map?.animateCamera(CameraUpdate.newLatLngZoom(target, 17));
      }
    }
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final i = widget.initial;
    final start = i == null ? MapPinPicker.fallback : LatLng(i.$1, i.$2);
    return Semantics(
      label:
          'Harita. Haritayı kaydırarak iğneyi teslimat noktasına getirin; iğnenin altındaki konum kaydedilir.',
      child: ClipRRect(
        borderRadius: AknRadius.card,
        child: SizedBox(
          height: widget.height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: start,
                  zoom: i == null ? 5.5 : 17,
                ),
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
                scrollGesturesEnabled: widget.enabled,
                zoomGesturesEnabled: widget.enabled,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                gestureRecognizers:
                    const <Factory<OneSequenceGestureRecognizer>>{
                      Factory<OneSequenceGestureRecognizer>(
                        EagerGestureRecognizer.new,
                      ),
                    },
                onMapCreated: (m) => _map = m,
                onCameraMoveStarted: () => setState(() => _moving = true),
                onCameraMove: (p) => _center = p.target,
                onCameraIdle: () {
                  setState(() => _moving = false);
                  if (_programmatic) {
                    _programmatic = false;
                    return;
                  }
                  final cpos = _center;
                  if (cpos != null && widget.enabled) {
                    widget.onPicked(
                      double.parse(cpos.latitude.toStringAsFixed(6)),
                      double.parse(cpos.longitude.toStringAsFixed(6)),
                    );
                  }
                },
              ),
              // Sabit iğne: ucu tam merkezde.
              IgnorePointer(
                child: Transform.translate(
                  offset: const Offset(0, -20),
                  child: AnimatedScale(
                    scale: _moving ? 1.12 : 1,
                    duration: AknMotion.of(context, AknMotion.fast),
                    child: Icon(
                      Icons.location_on_rounded,
                      size: 44,
                      color: c.brandFill,
                      shadows: const [
                        Shadow(blurRadius: 6, color: Color(0x55000000)),
                      ],
                    ),
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
