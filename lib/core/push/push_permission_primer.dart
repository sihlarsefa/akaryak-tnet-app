import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_controller.dart';
import '../storage/prefs_store.dart';
import '../ui/ui.dart';
import 'push_providers.dart';
import 'push_service.dart';

/// İlk girişten sonra bir kez: bildirim izninden önce ne işe yaradığını anlatan yumuşak ön sayfa
/// (spec C.4, C.7). Push kapalıysa (Firebase yapılandırması yok) ya da izin zaten verildi/reddedildiyse
/// gösterilmez. Müşterilere girişte değil, ilk siparişten sonra sorulur (A2); bayi personeli (şoför,
/// onaycı, masa) ve merkez girişte görür. Gösterildiyse true döner (aynı oturumda başka öneri açılmaz).
Future<bool> maybeShowPushPrimer(BuildContext context, WidgetRef ref) async {
  if (!ref.read(firebaseAvailableProvider)) return false;
  if (ref.read(accessPolicyProvider).isCustomer) return false;
  final prefs = ref.read(prefsStoreProvider);
  if (prefs.getBool(PrefKeys.pushPrimerShown)) return false;
  final push = ref.read(pushServiceProvider);
  if (await push.permission() != PushPermission.notDetermined) return false;
  await prefs.setBool(PrefKeys.pushPrimerShown, true);
  if (!context.mounted) return false;
  final accepted = await showAppSheet<bool>(
    context: context,
    showClose: false,
    builder: (ctx) => const _PrimerBody(),
  );
  if (accepted ?? false) unawaited(push.requestPermission());
  return true;
}

class _PrimerBody extends StatelessWidget {
  const _PrimerBody();

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        const Center(
          child: AknIconBox(
            icon: Icons.notifications_active_rounded,
            tone: AknTone.brand,
            size: 56,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Önemli anları kaçırmayın',
          style: t.title,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Teklif hazır olduğunda, siparişiniz onaylandığında, aracınız yola çıktığında ve onayınız '
          'beklendiğinde haber verelim. Ayarlardan istediğiniz zaman değiştirebilirsiniz.',
          style: t.body.copyWith(color: c.dim),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        AknButton(
          label: 'Bildirimlere izin ver',
          expand: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: 8),
        AknButton.ghost(
          label: 'Şimdi değil',
          expand: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
