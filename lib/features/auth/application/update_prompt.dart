import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env/app_config_controller.dart';
import '../../../core/env/app_info.dart';
import '../../../core/models/app_config.dart';
import '../../../core/storage/prefs_store.dart';
import '../../../core/ui/ui.dart';
import '../copy.dart';
import 'link_opener.dart';

/// Mağaza bağlantısı: `app/config.storeUrl`; yoksa Android'de Google Play sayfası (paket adı sabit),
/// iOS'ta bilinmez (ekran "App Store'dan güncelleyin" der).
Uri? storeUriFor(AppConfig config, AppInfo info) {
  final configured = SupportLinks.web(config.storeUrl);
  if (configured != null) return configured;
  if (info.platform == 'android') {
    return Uri.parse(
      'https://play.google.com/store/apps/details?id=com.ortakplatform.akaryakitnet',
    );
  }
  return null;
}

/// Mağazayı açar; açılamazsa bildirim gösterir.
Future<void> openStore(WidgetRef ref) async {
  final uri = storeUriFor(
    ref.read(appConfigProvider),
    ref.read(appInfoProvider),
  );
  if (uri == null) {
    AppToast.info(AuthCopy.noStoreBody);
    return;
  }
  final ok = await ref.read(linkOpenerProvider)(uri, external: true);
  if (!ok) AppToast.error(AuthCopy.linkFailed);
}

/// İsteğe bağlı güncelleme önerisi (F2GO `app_update_coordinator.dart` uyarlaması): `latestBuild` bu
/// derlemeden yüksekse bir kez sorulur; "Daha sonra" o sürüm için bir daha sormaz. Kabuk (A-INT) girişten
/// sonra çağırır; zorunlu güncelleme yönlendiricinin işidir (`/update`).
Future<void> maybeShowOptionalUpdate(
  BuildContext context,
  WidgetRef ref,
) async {
  if (ref.read(updateStatusProvider) != UpdateStatus.optional) return;
  final config = ref.read(appConfigProvider);
  final prefs = ref.read(prefsStoreProvider);
  final snoozed = prefs.getInt(PrefKeys.updateSnoozedBuild) ?? 0;
  if (snoozed >= config.latestBuild) return;
  await prefs.setInt(PrefKeys.updateSnoozedBuild, config.latestBuild);
  if (!context.mounted) return;
  final update = await showAppSheet<bool>(
    context: context,
    showClose: false,
    builder: (ctx) => _OptionalUpdateBody(config: config),
  );
  if (update == true) await openStore(ref);
}

class _OptionalUpdateBody extends StatelessWidget {
  const _OptionalUpdateBody({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Icon(Icons.system_update_outlined, size: 32, color: c.ink),
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            config.updateTitle ?? AuthCopy.optionalTitle,
            style: t.title.copyWith(color: c.ink),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          config.updateMessage ?? AuthCopy.optionalBody,
          style: t.body.copyWith(color: c.dim),
        ),
        const SizedBox(height: 24),
        AknButton(
          label: AuthCopy.updateAction,
          expand: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: 8),
        AknButton.ghost(
          label: AuthCopy.later,
          expand: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
