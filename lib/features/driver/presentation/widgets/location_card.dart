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

/// Teslim konumu kartı (özet adımı; tasarım v3 §4): beyaz kart, solda tonun yumuşak kuyusunda durum
/// simgesi (alınırken dönen » ve çevresinde nefes alan halka), durum, hassasiyet, "Hassas konum
/// kapalı", izin / servis kapalıysa "Ayarları aç", zorunlu değilse "Konumsuz devam et". Durum
/// değişince simge ve kuyu rengi yaylanarak değişir. Ayarlardan dönünce konum yeniden denenir.
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
        icon: PhosphorIconsRegular.gpsFix,
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
        icon = PhosphorIconsRegular.gpsFix;
        status = DriverCopy.locationAcquiring;
      case LocationPhase.ready:
        final pos = p!;
        if (pos.approximate) {
          tone = AknTone.warn;
          icon = PhosphorIconsRegular.gps;
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
          icon = PhosphorIconsRegular.gps;
          status = DriverCopy.locationOk(pos.accuracyLabel);
          detail = DriverCopy.locationLowAccuracy(pos.accuracyLabel);
          actions.add(
            AknButton.ghost(
              label: DriverCopy.locationRetry,
              icon: PhosphorIconsRegular.arrowClockwise,
              size: AknButtonSize.small,
              onPressed: () => unawaited(cap.requestAndAcquire()),
            ),
          );
        } else {
          tone = AknTone.ok;
          icon = PhosphorIconsRegular.mapPin;
          status = DriverCopy.locationOk(pos.accuracyLabel);
        }
      case LocationPhase.needsPermission:
        tone = widget.required ? AknTone.warn : AknTone.neutral;
        icon = PhosphorIconsRegular.gpsSlash;
        status = widget.required
            ? DriverCopy.summaryNeedsGps
            : DriverCopy.locationOptionalHint;
        addLocationButton(DriverCopy.locationAdd);
        addSkip();
      case LocationPhase.denied:
        tone = widget.required ? AknTone.danger : AknTone.warn;
        icon = PhosphorIconsRegular.gpsSlash;
        status = DriverCopy.locationDenied;
        detail = DriverCopy.locationDeniedBody;
        actions.add(
          AknButton.secondary(
            label: DriverCopy.locationOpenSettings,
            icon: PhosphorIconsRegular.gear,
            size: AknButtonSize.small,
            onPressed: () => unawaited(_openSettings()),
          ),
        );
        addSkip();
      case LocationPhase.serviceOff:
        tone = widget.required ? AknTone.danger : AknTone.warn;
        icon = PhosphorIconsRegular.gpsSlash;
        status = DriverCopy.locationServiceOff;
        detail = DriverCopy.locationServiceOffBody;
        actions.add(
          AknButton.secondary(
            label: DriverCopy.locationOpenSettings,
            icon: PhosphorIconsRegular.gear,
            size: AknButtonSize.small,
            onPressed: () => unawaited(_openSettings(location: true)),
          ),
        );
        addSkip();
      case LocationPhase.failed:
        tone = widget.required ? AknTone.danger : AknTone.warn;
        icon = PhosphorIconsRegular.gps;
        status = DriverCopy.locationFailed;
        detail = DriverCopy.locationFailedBody;
        actions.add(
          AknButton.secondary(
            label: DriverCopy.locationRetry,
            icon: PhosphorIconsRegular.arrowClockwise,
            size: AknButtonSize.small,
            onPressed: () => unawaited(cap.requestAndAcquire()),
          ),
        );
        addSkip();
      case LocationPhase.skipped:
        tone = AknTone.neutral;
        icon = PhosphorIconsRegular.gpsSlash;
        status = DriverCopy.locationSkipped;
        addLocationButton(DriverCopy.locationAdd);
    }

    final tc = c.tone(tone);
    final busy = cap.isBusy || cap.phase == LocationPhase.idle;
    final quiet = tone == AknTone.neutral || tone == AknTone.info;
    final wellColor = quiet ? c.surfaceAlt : tc.bg;
    final glyphColor = quiet ? c.ink : tc.fg;
    final Widget glyph = busy
        ? ChevronSpinner(
            key: const ValueKey('busy'),
            size: 18,
            color: c.ink,
            semanticLabel: null,
          )
        : Icon(icon, key: ValueKey('$icon$tone'), size: 22, color: glyphColor);
    final duration = AknMotion.of(context, AknMotion.base);
    final tile = AnimatedContainer(
      duration: duration,
      curve: AknMotion.standard,
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: wellColor, shape: BoxShape.circle),
      child: Center(
        child: AnimatedSwitcher(
          duration: AknMotion.of(context, AknMotion.iconSwap),
          switchInCurve: AknMotion.pop,
          transitionBuilder: (child, a) => ScaleTransition(
            scale: a,
            child: FadeTransition(opacity: a, child: child),
          ),
          child: glyph,
        ),
      ),
    );
    // Konum aranırken simgenin çevresinde yumuşak bir halka nefes alır (ortam hareketi).
    final mark = busy
        ? AknAmbient(
            period: AknMotion.breathe,
            reverse: true,
            child: tile,
            builder: (context, v, child) => SizedBox.square(
              dimension: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 44 + 8 * v,
                    height: 44 + 8 * v,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.ink.withValues(alpha: 0.06 * (1 - v)),
                    ),
                  ),
                  child!,
                ],
              ),
            ),
          )
        : SizedBox.square(dimension: 52, child: Center(child: tile));
    return AknCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                mark,
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: t.label.copyWith(
                            color: c.dim,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          status,
                          style: t.bodyStrong.copyWith(
                            color: c.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (detail != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            detail,
                            style: t.bodySmall.copyWith(color: c.ink),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 62),
              child: Wrap(spacing: 8, runSpacing: 4, children: actions),
            ),
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
        var color = c.dim;
        var canAdd = false;
        switch (capture.phase) {
          case LocationPhase.ready when p != null:
            text = p.approximate
                ? '${DriverCopy.locationApproximate}, ${p.accuracyLabel}'
                : DriverCopy.locationStartWill(p.accuracyLabel);
            icon = PhosphorIconsRegular.mapPin;
            if (!p.approximate) color = c.ok.fg;
          case LocationPhase.idle || LocationPhase.acquiring:
            text = DriverCopy.locationAcquiring;
            icon = PhosphorIconsRegular.gpsFix;
          case _:
            text = DriverCopy.locationStartOptional;
            icon = PhosphorIconsRegular.gpsSlash;
            canAdd = capture.phase != LocationPhase.serviceOff;
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: AknMotion.of(context, AknMotion.iconSwap),
                switchInCurve: AknMotion.pop,
                transitionBuilder: (child, a) =>
                    ScaleTransition(scale: a, child: child),
                child: Icon(icon, key: ValueKey(icon), size: 20, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: t.bodySmall.copyWith(color: c.ink)),
              ),
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
