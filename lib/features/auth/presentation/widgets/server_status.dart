import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/env/app_config_controller.dart';
import '../../../../core/env/app_info.dart';
import '../../../../core/storage/prefs_store.dart';
import '../../../../core/ui/ui.dart';
import '../../application/server_gate_controller.dart';
import '../../application/update_prompt.dart';
import '../../copy.dart';
import 'gate_view.dart';
import 'support_contacts.dart';

/// Güncelleme ekranının varyantları (spec A.4 A1).
enum UpdateReason {
  /// `minBuild` ya da 426: güncellemeden devam edilemez.
  forced('forced'),

  /// `latestBuild` daha yeni: "Daha sonra" ile geçilebilir.
  optional('optional'),

  /// `app/config` 404 ya da sözleşme sürümü farklı: "Sunucu güncel değil".
  server('server'),

  /// `app/config.maintenance.active`: "Bakımdayız".
  maintenance('maintenance');

  const UpdateReason(this.code);

  /// Rota sorgusundaki değer: `/update?reason=maintenance`.
  final String code;

  static UpdateReason? parse(String? value) {
    final v = value?.trim();
    for (final r in values) {
      if (r.code == v) return r;
    }
    return null;
  }
}

/// Varyantın gövdesi. Giriş ekranı da bakım ve uyumsuz sunucu için bunu gösterir.
class UpdateGateBody extends ConsumerWidget {
  const UpdateGateBody({
    super.key,
    required this.reason,
    this.maintenanceMessage,
    this.onLater,
  });

  final UpdateReason reason;

  /// Sunucunun bakım metni (boşsa varsayılan).
  final String? maintenanceMessage;

  /// İsteğe bağlı güncellemede "Daha sonra".
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final info = ref.watch(appInfoProvider);
    final t = context.aknText;
    final c = context.akn;
    final version = Text(
      AuthCopy.installedVersion(info.versionLabel),
      style: t.caption.copyWith(color: c.dim),
    );
    switch (reason) {
      case UpdateReason.forced:
        final store = storeUriFor(config, info);
        return GateView(
          icon: PhosphorIconsRegular.downloadSimple,
          tone: AknTone.brand,
          title: config.updateTitle ?? AuthCopy.forcedTitle,
          message: config.updateMessage ?? AuthCopy.forcedBody,
          primary: store == null
              ? null
              : AknButton(
                  label: AuthCopy.openStore,
                  expand: true,
                  size: AknButtonSize.large,
                  onPressed: () => openStore(ref),
                ),
          secondary: AknButton.ghost(
            label: AuthCopy.checkAgain,
            expand: true,
            showSuccess: false,
            loadingLabel: AuthCopy.checking,
            onPressedAsync: () => ref.read(appConfigProvider.notifier).load(),
          ),
          below: store == null
              ? const AknBanner(
                  message: AuthCopy.noStoreBody,
                  icon: PhosphorIconsRegular.storefront,
                )
              : null,
          footer: version,
        );
      case UpdateReason.optional:
        return GateView(
          icon: PhosphorIconsRegular.sealWarning,
          tone: AknTone.brand,
          title: config.updateTitle ?? AuthCopy.optionalTitle,
          message: config.updateMessage ?? AuthCopy.optionalBody,
          primary: AknButton(
            label: AuthCopy.updateAction,
            expand: true,
            size: AknButtonSize.large,
            onPressed: () => openStore(ref),
          ),
          secondary: AknButton.ghost(
            label: AuthCopy.later,
            expand: true,
            onPressed: () async {
              await ref
                  .read(prefsStoreProvider)
                  .setInt(PrefKeys.updateSnoozedBuild, config.latestBuild);
              onLater?.call();
            },
          ),
          footer: version,
        );
      case UpdateReason.server:
      case UpdateReason.maintenance:
        final maintenance = reason == UpdateReason.maintenance;
        final checking = ref.watch(serverGateProvider).isLoading;
        return GateView(
          icon: maintenance
              ? PhosphorIconsRegular.wrench
              : PhosphorIconsRegular.arrowsClockwise,
          tone: maintenance ? AknTone.info : AknTone.warn,
          title: maintenance ? AuthCopy.maintenanceTitle : AuthCopy.serverTitle,
          message: maintenance
              ? (maintenanceMessage ?? AuthCopy.maintenanceBody)
              : AuthCopy.serverBody,
          primary: AknButton(
            label: AuthCopy.tryAgain,
            expand: true,
            size: AknButtonSize.large,
            loading: checking,
            loadingLabel: AuthCopy.checking,
            onPressed: () => ref.read(serverGateProvider.notifier).recheck(),
          ),
          below: SupportContacts(links: ref.watch(authLinksProvider)),
          footer: version,
        );
    }
  }
}
