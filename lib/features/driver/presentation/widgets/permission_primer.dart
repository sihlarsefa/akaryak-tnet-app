import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../copy.dart';
import 'entrance.dart';

/// İzin türü.
enum DriverPrimerKind { location, camera }

/// Sistem izin penceresinden önce gösterilen ön sayfa (spec C.7; tasarım v3): yumuşak turuncu
/// dairede simge (yaylanarak belirir, uygulamada çevresinde nefes alan bir halka), tek cümle neden,
/// "Devam" / "Şimdi değil". Kullanıcı "Devam" derse true döner.
Future<bool> showDriverPrimer(
  BuildContext context, {
  required DriverPrimerKind kind,
}) async {
  final result = await showAppSheet<bool>(
    context: context,
    showClose: false,
    builder: (ctx) => DriverPrimerBody(kind: kind),
  );
  return result ?? false;
}

class DriverPrimerBody extends StatelessWidget {
  const DriverPrimerBody({super.key, required this.kind});

  final DriverPrimerKind kind;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final (icon, title, body) = switch (kind) {
      DriverPrimerKind.location => (
        PhosphorIconsRegular.gpsFix,
        DriverCopy.primerLocationTitle,
        DriverCopy.primerLocationBody,
      ),
      DriverPrimerKind.camera => (
        PhosphorIconsRegular.camera,
        DriverCopy.primerCameraTitle,
        DriverCopy.primerCameraBody,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Center(child: _PrimerMark(icon: icon)),
        const SizedBox(height: 18),
        Semantics(
          header: true,
          child: Text(
            title,
            style: t.title.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: t.body.copyWith(color: c.dim),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        AknButton(
          label: DriverCopy.primerContinue,
          expand: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: 8),
        AknButton.ghost(
          label: DriverCopy.primerNotNow,
          expand: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}

/// Ön sayfanın simgesi: 84 px alanda 72 px yumuşak turuncu daire, Pas renkli simge; ilk çizimde
/// yaylanarak büyür, uygulamada çevresinde yumuşak bir halka nefes alır.
class _PrimerMark extends StatelessWidget {
  const _PrimerMark({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final disc = DecoratedBox(
      decoration: BoxDecoration(color: c.brandSoft, shape: BoxShape.circle),
      child: SizedBox.square(
        dimension: 72,
        child: Icon(icon, size: 36, color: c.brandInk),
      ),
    );
    return ExcludeSemantics(
      child: DriverFadeUp(
        offset: 6,
        scale: 0.7,
        duration: AknMotion.slow,
        curve: AknMotion.pop,
        child: SizedBox.square(
          dimension: 96,
          child: AknAmbient(
            period: AknMotion.breathe,
            reverse: true,
            child: disc,
            builder: (context, v, child) => Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 72 + 24 * v,
                  height: 72 + 24 * v,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.brandSoft.withValues(alpha: 0.55 * (1 - v)),
                  ),
                ),
                child!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
