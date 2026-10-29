import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/env/app_env.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../copy.dart';
import '../../data/location_service.dart';
import '../cm_widgets.dart';
import 'map_pin_picker.dart';

/// Seçilen konum (doğruluk yalnızca "Bulunduğum konumu kullan" ile gelir).
@immutable
class PickedLocation {
  const PickedLocation(
    this.latitude,
    this.longitude, {
    this.accuracyMeters,
    this.approximate = false,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final bool approximate;
}

/// Teslimat noktası konumu.
///
/// * Harita kapalıyken (`MAPS_ENABLED=false`): "Bulunduğum konumu kullan" (izin ön sayfası, doğruluk çipi,
///   50 m üstünde uyarı) + "Haritada aç" + "Konumu kaldır".
/// * Harita açıkken: ortada sabit iğneli harita; harita kaydırılınca iğnenin altındaki nokta seçilir.
class LocationSection extends ConsumerStatefulWidget {
  const LocationSection({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.enabled = true,
  });

  final PickedLocation? value;
  final ValueChanged<PickedLocation?> onChanged;

  /// "Haritada aç" etiketi (nokta adı).
  final String? label;
  final bool enabled;

  @override
  ConsumerState<LocationSection> createState() => _LocationSectionState();
}

class _LocationSectionState extends ConsumerState<LocationSection> {
  bool _busy = false;
  LocationAccess? _blocked;

  Future<bool> _primer() async {
    final ok = await showAppSheet<bool>(
      context: context,
      showClose: false,
      builder: (ctx) {
        final c = ctx.akn;
        final t = ctx.aknText;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: FadeUp(
                offset: 8,
                scale: 0.8,
                curve: AknMotion.pop,
                child: AknIconBox(
                  icon: PhosphorIconsRegular.gpsFix,
                  tone: AknTone.brand,
                  size: 52,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              CmCopy.locationPrimerTitle,
              style: t.title.copyWith(color: c.ink),
            ),
            const SizedBox(height: 8),
            Text(
              CmCopy.locationPrimerMessage,
              style: t.body.copyWith(color: c.text),
            ),
            const SizedBox(height: 20),
            AknButton(
              label: 'Devam',
              expand: true,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            AknButton.ghost(
              label: 'Şimdi değil',
              expand: true,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
          ],
        );
      },
    );
    return ok ?? false;
  }

  Future<void> _useMyLocation() async {
    final svc = ref.read(cmLocationServiceProvider);
    setState(() {
      _busy = true;
      _blocked = null;
    });
    try {
      var access = await svc.access();
      if (access == LocationAccess.notAsked ||
          access == LocationAccess.denied) {
        if (!mounted || !await _primer()) return;
        access = await svc.request();
      }
      if (access == LocationAccess.deniedForever ||
          access == LocationAccess.serviceOff ||
          access == LocationAccess.denied) {
        if (mounted) setState(() => _blocked = access);
        return;
      }
      final fix = await svc.current();
      if (!mounted) return;
      if (fix == null) {
        AppToast.warning(
          'Konum alınamadı. Açık bir alanda tekrar deneyin.',
          context: context,
        );
        return;
      }
      AknHaptics.selection();
      widget.onChanged(
        PickedLocation(
          fix.latitude,
          fix.longitude,
          accuracyMeters: fix.accuracyMeters,
          approximate: fix.approximate || access == LocationAccess.approximate,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapsEnabled = ref.watch(appEnvProvider).mapsEnabled;
    final v = widget.value;
    final t = context.aknText;
    final c = context.akn;
    final svc = ref.read(cmLocationServiceProvider);
    final acc = v?.accuracyMeters;
    final imprecise =
        v != null &&
        (v.approximate || (acc != null && acc > LocationFix.warnAboveMeters));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mapsEnabled) ...[
          MapPinPicker(
            initial: v == null ? null : (v.latitude, v.longitude),
            enabled: widget.enabled,
            onPicked: (lat, lng) => widget.onChanged(PickedLocation(lat, lng)),
          ),
          const SizedBox(height: 12),
        ],
        if (v != null)
          Semantics(
            container: true,
            label:
                'Konum ${v.latitude.toStringAsFixed(6)}, ${v.longitude.toStringAsFixed(6)}'
                '${acc == null ? '' : ', doğruluk yaklaşık ${acc.round()} metre'}',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: AknRadius.card,
              ),
              child: Row(
                children: [
                  Icon(PhosphorIconsRegular.mapPin, color: c.ink),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${v.latitude.toStringAsFixed(6)}, ${v.longitude.toStringAsFixed(6)}',
                      style: t.amount.copyWith(fontSize: 14),
                    ),
                  ),
                  if (acc != null)
                    StatusChip(
                      label: '±${Fmt.number(acc, maxFraction: 0)} m',
                      tone: imprecise ? AknTone.warn : AknTone.ok,
                      icon: imprecise
                          ? PhosphorIconsRegular.gps
                          : PhosphorIconsRegular.gpsFix,
                      size: StatusChipSize.small,
                    ),
                ],
              ),
            ),
          )
        else
          Text(
            mapsEnabled
                ? 'Haritayı kaydırıp iğneyi teslimat noktasına getirin.'
                : 'Konum kayıtlı değil. Şoförün noktayı bulması için konum eklemeniz önerilir.',
            style: t.bodySmall.copyWith(color: c.dim),
          ),
        if (v != null && imprecise) ...[
          const SizedBox(height: 8),
          AknBanner(
            tone: AknTone.warn,
            title: v.approximate ? CmCopy.preciseOff : 'Konum doğruluğu düşük',
            message: v.approximate
                ? 'Yalnızca yaklaşık konum izni var. Ayarlardan "Hassas konum"u açıp tekrar deneyin.'
                : 'Konum yaklaşık ${acc!.round()} m sapabilir. Açık alanda, noktanın yanında tekrar deneyin.',
            actionLabel: v.approximate ? 'Ayarları aç' : null,
            onAction: v.approximate ? svc.openAppSettings : null,
          ),
        ],
        if (_blocked != null) ...[
          const SizedBox(height: 8),
          AknBanner(
            tone: AknTone.info,
            icon: PhosphorIconsRegular.gpsSlash,
            title: _blocked == LocationAccess.serviceOff
                ? 'Konum servisleri kapalı'
                : 'Konum izni verilmedi',
            message: _blocked == LocationAccess.serviceOff
                ? 'Telefonunuzun konum servislerini açıp tekrar deneyin. Konumsuz da kaydedebilirsiniz.'
                : 'Ayarlardan konum iznini açabilir ya da konumsuz devam edebilirsiniz.',
            actionLabel: 'Ayarları aç',
            onAction: () => _blocked == LocationAccess.serviceOff
                ? svc.openLocationSettings()
                : svc.openAppSettings(),
            onClose: () => setState(() => _blocked = null),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            // Genişlemeyen düğmede `loading` biçim değiştirir; burada etiket durumu anlatır.
            AknButton.secondary(
              label: _busy ? 'Konum alınıyor…' : CmCopy.useMyLocation,
              icon: _busy
                  ? PhosphorIconsRegular.hourglassHigh
                  : PhosphorIconsRegular.gpsFix,
              size: AknButtonSize.small,
              onPressed: widget.enabled && !_busy ? _useMyLocation : null,
            ),
            if (v != null)
              AknButton.ghost(
                label: CmCopy.openInMaps,
                icon: PhosphorIconsRegular.mapTrifold,
                size: AknButtonSize.small,
                onPressed: () =>
                    openInMaps(v.latitude, v.longitude, label: widget.label),
              ),
            if (v != null && widget.enabled)
              AknButton.ghost(
                label: 'Konumu kaldır',
                icon: PhosphorIconsRegular.gpsSlash,
                size: AknButtonSize.small,
                onPressed: () => widget.onChanged(null),
              ),
          ],
        ),
      ],
    );
  }
}
