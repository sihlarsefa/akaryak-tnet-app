import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../copy.dart';

/// İzin türü.
enum DriverPrimerKind { location, camera }

/// Sistem izin penceresinden önce gösterilen ön sayfa (spec C.7): ikon, tek cümle neden,
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
        Icons.my_location_outlined,
        DriverCopy.primerLocationTitle,
        DriverCopy.primerLocationBody,
      ),
      DriverPrimerKind.camera => (
        Icons.photo_camera_outlined,
        DriverCopy.primerCameraTitle,
        DriverCopy.primerCameraBody,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Center(child: Icon(icon, size: 40, color: c.ink)),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(title, style: t.title, textAlign: TextAlign.center),
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
