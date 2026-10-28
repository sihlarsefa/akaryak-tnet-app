import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/ui.dart';
import '../copy.dart';
import '../data/field_location.dart';

/// Konum alma akışının sonucu.
sealed class FieldLocationOutcome {
  const FieldLocationOutcome();
}

/// Konum alındı ([FieldLocationFix.approximate]: "Hassas konum kapalı").
class LocationCaptured extends FieldLocationOutcome {
  const LocationCaptured(this.fix);
  final FieldLocationFix fix;
}

/// Kullanıcı ön sayfada "Şimdi değil" dedi ya da işletim sistemi isteminde reddetti.
class LocationDeclined extends FieldLocationOutcome {
  const LocationDeclined();
}

/// İzin kalıcı kapalı: "Ayarları aç".
class LocationBlocked extends FieldLocationOutcome {
  const LocationBlocked();
}

/// Telefonun konum servisi kapalı.
class LocationServiceOff extends FieldLocationOutcome {
  const LocationServiceOff();
}

/// Konum alınamadı (zaman aşımı vb.) ya da desteklenmiyor.
class LocationFailed extends FieldLocationOutcome {
  const LocationFailed(this.message);
  final String message;
}

/// Konum alma akışı (spec C.7): işletim sistemi isteminden önce bir ön sayfa (ikon, tek cümlelik neden,
/// "Devam" / "Şimdi değil"), kalıcı ret ve yalnızca yaklaşık izin için ayrı sonuçlar. İstem yalnızca
/// kullanıcı dokununca gösterilir.
Future<FieldLocationOutcome> captureFieldLocation(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
  IconData icon = PhosphorIconsRegular.gpsFix,
}) async {
  final svc = ref.read(fieldLocationServiceProvider);
  var access = await svc.status();
  switch (access) {
    case FieldLocationAccess.serviceDisabled:
      return const LocationServiceOff();
    case FieldLocationAccess.unavailable:
      return const LocationFailed('Bu cihazda konum alınamıyor.');
    case FieldLocationAccess.deniedForever:
      return const LocationBlocked();
    case FieldLocationAccess.notDetermined:
    case FieldLocationAccess.denied:
      if (!context.mounted) return const LocationDeclined();
      final go = await showLocationPrimer(context, reason: reason, icon: icon);
      if (!go) return const LocationDeclined();
      access = await svc.request();
    case FieldLocationAccess.granted:
    case FieldLocationAccess.approximate:
      break;
  }
  switch (access) {
    case FieldLocationAccess.deniedForever:
      return const LocationBlocked();
    case FieldLocationAccess.serviceDisabled:
      return const LocationServiceOff();
    case FieldLocationAccess.notDetermined:
    case FieldLocationAccess.denied:
      return const LocationDeclined();
    case FieldLocationAccess.unavailable:
      return const LocationFailed('Bu cihazda konum alınamıyor.');
    case FieldLocationAccess.granted:
    case FieldLocationAccess.approximate:
      break;
  }
  try {
    final fix = await svc.current();
    return LocationCaptured(fix);
  } on FieldLocationException catch (e) {
    if (e.access == FieldLocationAccess.serviceDisabled) {
      return const LocationServiceOff();
    }
    return LocationFailed(e.message);
  }
}

/// Konum izni ön sayfası (tasarım v3): turuncu simge kutusunun çevresinde yavaşça genişleyip sönen
/// konum halkası (ortam hareketi), başlık, tek cümlelik neden, "Devam" / "Şimdi değil". Dönüş: "Devam".
Future<bool> showLocationPrimer(
  BuildContext context, {
  required String reason,
  IconData icon = PhosphorIconsRegular.gpsFix,
}) async {
  final ok = await showAppSheet<bool>(
    context: context,
    showClose: false,
    builder: (ctx) {
      final t = ctx.aknText;
      final c = ctx.akn;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(child: _LocationBeacon(icon: icon)),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(
              FieldCopy.locationPrimerTitle,
              style: t.title,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            reason,
            style: t.body.copyWith(color: c.dim),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          AknButton(
            label: 'Devam',
            expand: true,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
          const SizedBox(height: 4),
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

/// Konum durum bandı: hassas konum kapalı, izin kapalı, servis kapalı, alınamadı.
/// Gösterilecek durum yoksa hiçbir şey çizmez.
class FieldLocationNotice extends ConsumerWidget {
  const FieldLocationNotice({
    super.key,
    required this.outcome,
    this.onRetry,
    this.onContinueWithout,
    this.margin = EdgeInsets.zero,
  });

  final FieldLocationOutcome? outcome;
  final VoidCallback? onRetry;

  /// "Konumsuz devam et" (konum zorunlu değilken).
  final VoidCallback? onContinueWithout;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = outcome;
    final svc = ref.read(fieldLocationServiceProvider);
    Widget? banner;
    switch (o) {
      case LocationCaptured(:final fix) when fix.approximate:
        banner = AknBanner(
          tone: AknTone.warn,
          icon: PhosphorIconsRegular.gps,
          title: FieldCopy.preciseOffTitle,
          message: FieldCopy.preciseOffMessage,
          actionLabel: 'Ayarları aç',
          onAction: svc.openAppSettings,
        );
      case LocationBlocked():
        banner = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AknBanner(
              tone: AknTone.warn,
              icon: PhosphorIconsRegular.gpsSlash,
              title: FieldCopy.locationDeniedTitle,
              message: FieldCopy.locationDeniedMessage,
              actionLabel: 'Ayarları aç',
              onAction: svc.openAppSettings,
            ),
            if (onContinueWithout != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onContinueWithout,
                  child: const Text('Konumsuz devam et'),
                ),
              ),
          ],
        );
      case LocationServiceOff():
        banner = AknBanner(
          tone: AknTone.warn,
          icon: PhosphorIconsRegular.gpsSlash,
          title: FieldCopy.locationServiceOffTitle,
          message: FieldCopy.locationServiceOffMessage,
          actionLabel: 'Konum ayarlarını aç',
          onAction: svc.openLocationSettings,
        );
      case LocationFailed(:final message):
        banner = AknBanner(
          tone: AknTone.danger,
          message: message,
          actionLabel: onRetry == null ? null : FieldCopy.retry,
          onAction: onRetry,
        );
      case LocationDeclined():
      case LocationCaptured():
      case null:
        banner = null;
    }
    if (banner == null) return const SizedBox.shrink();
    return Padding(padding: margin, child: banner);
  }
}

/// Ön sayfanın simgesi: 56 px turuncu tonlu kutu ve arkasında radar gibi genişleyip sönen yumuşak
/// halka (yalnızca ortam hareketi açıkken; testlerde ve hareket azaltmada durgun).
class _LocationBeacon extends StatelessWidget {
  const _LocationBeacon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final box = AknIconBox(icon: icon, tone: AknTone.brand, size: 56);
    return SizedBox(
      width: 96,
      height: 96,
      child: AknAmbient(
        period: const Duration(milliseconds: 2200),
        restValue: 1,
        curve: Curves.easeOut,
        child: box,
        builder: (context, t, child) => Stack(
          alignment: Alignment.center,
          children: [
            if (t < 1)
              Opacity(
                opacity: (1 - t) * 0.6,
                child: Container(
                  width: 56 + 40 * t,
                  height: 56 + 40 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.brandLine, width: 2),
                    color: c.brandSoft.withValues(alpha: 0.5),
                  ),
                ),
              ),
            child!,
          ],
        ),
      ),
    );
  }
}
