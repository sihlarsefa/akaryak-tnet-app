import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../application/location.dart';
import '../../copy.dart';
import 'permission_primer.dart';

/// "Konum ekle": izin sorulmadıysa önce ön sayfa (spec C.7), sonra sistem penceresi ve konum.
/// [auto] true ise (zorunlu konum ekranı açılırken) reddedilmiş ön sayfa 7 gün gösterilmez.
Future<void> requestLocation(
  BuildContext context,
  WidgetRef ref,
  LocationCapture capture, {
  bool auto = false,
}) async {
  final prefs = ref.read(driverPrimerPrefsProvider);
  final perm = await capture.service.permission();
  if (perm == DriverLocationPermission.notDetermined) {
    if (auto && !prefs.mayAutoShowLocation) return;
    if (!context.mounted) return;
    final ok = await showDriverPrimer(context, kind: DriverPrimerKind.location);
    if (!ok) {
      await prefs.locationDeclined();
      return;
    }
  }
  await capture.requestAndAcquire();
}

/// Teslim konumu kartı (özet adımı): durum, hassasiyet, "Hassas konum kapalı", izin / servis kapalıysa
/// "Ayarları aç", zorunlu değilse "Konumsuz devam et". Ayarlardan dönünce konum yeniden denenir.
class LocationCard extends ConsumerStatefulWidget {
  const LocationCard({
    super.key,
    required this.capture,
    required this.required,
    this.title = DriverCopy.locationTitle,
  });

  final LocationCapture capture;

  /// Konum olmadan gönderilemez (ayar ya da imza alınamadı).
  final bool required;
  final String title;

  @override
  ConsumerState<LocationCard> createState() => _LocationCardState();
}

class _LocationCardState extends ConsumerState<LocationCard> {
  late final AppLifecycleListener _lifecycle;
  bool _awaitingSettings = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _onResume() {
    if (!_awaitingSettings) return;
    _awaitingSettings = false;
    unawaited(widget.capture.prime());
  }

  Future<void> _openSettings({bool location = false}) async {
    _awaitingSettings = true;
    final s = widget.capture.service;
    await (location ? s.openLocationSettings() : s.openAppSettings());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.capture,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final cap = widget.capture;
    final p = cap.position;
    final optional = !widget.required;

    late final AknTone tone;
    late final IconData icon;
    late final String status;
    String? detail;
    final actions = <Widget>[];

    void addLocationButton(String label) => actions.add(
      AknButton.secondary(
        label: label,
        icon: Icons.my_location_rounded,
        size: AknButtonSize.small,
        onPressed: () => unawaited(requestLocation(context, ref, cap)),
      ),
    );
    void addSkip() {
      if (optional) {
        actions.add(
          AknButton.ghost(
            label: DriverCopy.locationSkip,
            size: AknButtonSize.small,
            onPressed: cap.skip,
          ),
        );
      }
    }

    switch (cap.phase) {
      case LocationPhase.idle:
      case LocationPhase.acquiring:
        tone = AknTone.info;
        icon = Icons.my_location_rounded;
        status = DriverCopy.locationAcquiring;
      case LocationPhase.ready:
        final pos = p!;
        if (pos.approximate) {
          tone = AknTone.warn;
          icon = Icons.location_searching_rounded;
          status = DriverCopy.locationApproximate;
          detail =
              '${DriverCopy.locationApproximateBody} (${pos.accuracyLabel})';
          actions.add(
            AknButton.ghost(
              label: DriverCopy.locationOpenSettings,
              size: AknButtonSize.small,
              onPressed: () => unawaited(_openSettings()),
            ),
          );
        } else if (pos.isLowAccuracy) {
          tone = AknTone.warn;
          icon = Icons.location_searching_rounded;
          status = DriverCopy.locationOk(pos.accuracyLabel);
          detail = DriverCopy.locationLowAccuracy(pos.accuracyLabel);
          actions.add(
            AknButton.ghost(
              label: DriverCopy.locationRetry,
              icon: Icons.refresh_rounded,
              size: AknButtonSize.small,
              onPressed: () => unawaited(cap.requestAndAcquire()),
            ),
          );
        } else {
          tone = AknTone.ok;
          icon = Icons.location_on_rounded;
          status = DriverCopy.locationOk(pos.accuracyLabel);
        }
      case LocationPhase.needsPermission:
        tone = widget.required ? AknTone.warn : AknTone.neutral;
        icon = Icons.location_off_rounded;
        status = widget.required
            ? DriverCopy.summaryNeedsGps
            : DriverCopy.locationOptionalHint;
        addLocationButton(DriverCopy.locationAdd);
        addSkip();
      case LocationPhase.denied:
        tone = widget.required ? AknTone.danger : AknTone.warn;
        icon = Icons.location_disabled_rounded;
        status = DriverCopy.locationDenied;
        detail = DriverCopy.locationDeniedBody;
        actions.add(
          AknButton.secondary(
            label: DriverCopy.locationOpenSettings,
            icon: Icons.settings_rounded,
            size: AknButtonSize.small,
            onPressed: () => unawaited(_openSettings()),
          ),
        );
        addSkip();
      case LocationPhase.serviceOff:
        tone = widget.required ? AknTone.danger : AknTone.warn;
        icon = Icons.location_disabled_rounded;
        status = DriverCopy.locationServiceOff;
        detail = DriverCopy.locationServiceOffBody;
        actions.add(
          AknButton.secondary(
            label: DriverCopy.locationOpenSettings,
            icon: Icons.settings_rounded,
            size: AknButtonSize.small,
            onPressed: () => unawaited(_openSettings(location: true)),
          ),
        );
        addSkip();
      case LocationPhase.failed:
        tone = widget.required ? AknTone.danger : AknTone.warn;
        icon = Icons.location_searching_rounded;
        status = DriverCopy.locationFailed;
        detail = DriverCopy.locationFailedBody;
        actions.add(
          AknButton.secondary(
            label: DriverCopy.locationRetry,
            icon: Icons.refresh_rounded,
            size: AknButtonSize.small,
            onPressed: () => unawaited(cap.requestAndAcquire()),
          ),
        );
        addSkip();
      case LocationPhase.skipped:
        tone = AknTone.neutral;
        icon = Icons.location_off_rounded;
        status = DriverCopy.locationSkipped;
        addLocationButton(DriverCopy.locationAdd);
    }

    final tc = c.tone(tone);
    final busy = cap.isBusy || cap.phase == LocationPhase.idle;
    return AknCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title, style: t.label.copyWith(color: c.dim)),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tc.bg,
                    shape: BoxShape.circle,
                    border: Border.all(color: tc.line),
                  ),
                  child: Center(
                    child: busy
                        ? ChevronSpinner(
                            size: 16,
                            color: tc.fg,
                            semanticLabel: null,
                          )
                        : Icon(icon, size: 20, color: tc.fg),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        status,
                        style: t.bodyStrong.copyWith(
                          color: tone == AknTone.neutral ? c.ink : tc.fg,
                        ),
                      ),
                      if (detail != null) ...[
                        const SizedBox(height: 2),
                        Text(detail, style: t.bodySmall),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: actions),
          ],
        ],
      ),
    );
  }
}

/// Yola çıkış kaydırıcısının üstündeki tek satırlık konum durumu (konum isteğe bağlıdır).
class StartLocationLine extends ConsumerWidget {
  const StartLocationLine({super.key, required this.capture});

  final LocationCapture capture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListenableBuilder(
      listenable: capture,
      builder: (context, _) {
        final c = context.akn;
        final t = context.aknText;
        final p = capture.position;
        final String text;
        final IconData icon;
        var canAdd = false;
        switch (capture.phase) {
          case LocationPhase.ready when p != null:
            text = p.approximate
                ? '${DriverCopy.locationApproximate} · ${p.accuracyLabel}'
                : DriverCopy.locationStartWill(p.accuracyLabel);
            icon = Icons.location_on_rounded;
          case LocationPhase.idle || LocationPhase.acquiring:
            text = DriverCopy.locationAcquiring;
            icon = Icons.my_location_rounded;
          case _:
            text = DriverCopy.locationStartOptional;
            icon = Icons.location_off_rounded;
            canAdd = capture.phase != LocationPhase.serviceOff;
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: c.dim),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: t.bodySmall)),
              if (canAdd)
                AknButton.ghost(
                  label: DriverCopy.locationAdd,
                  size: AknButtonSize.small,
                  onPressed: () =>
                      unawaited(requestLocation(context, ref, capture)),
                ),
            ],
          ),
        );
      },
    );
  }
}
