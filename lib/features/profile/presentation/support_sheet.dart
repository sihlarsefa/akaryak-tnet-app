import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env/app_config_controller.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../application/config_extras.dart';
import '../application/links.dart';
import '../copy.dart';

/// "Destek ile görüş" (spec A.4 A8; asistandan da açılır): `app/config` destek kanalları (telefon,
/// WhatsApp, e-posta) ve destek sayfası. Tanımlı olmayan kanal gösterilmez.
Future<void> showSupportSheet(BuildContext context) => showAppSheet<void>(
  context: context,
  title: ProfileCopy.supportTitle,
  subtitle: ProfileCopy.supportSubtitle,
  padding: const EdgeInsets.only(bottom: 16),
  builder: (_) => const _SupportBody(),
);

class _SupportBody extends ConsumerWidget {
  const _SupportBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final support = ref.watch(appConfigProvider.select((c) => c.support));
    final legal = ref.watch(legalUrisProvider);
    final page =
        SupportUris.web(
          ref.watch(configExtrasProvider).valueOrNull?.supportUrl,
        ) ??
        legal.support;
    final open = ref.read(profileLinkOpenerProvider);
    final phone = SupportUris.phone(support.phone);
    final whatsapp = SupportUris.whatsapp(support.whatsapp);
    final email = SupportUris.email(
      support.email,
      subject: ProfileCopy.supportMailSubject,
    );

    Future<void> launch(Uri uri, {bool external = true}) async {
      final ok = await open(uri, external: external);
      if (!ok) AppToast.error(ProfileCopy.linkFailed);
    }

    return AknLedger(
      children: [
        if (phone != null)
          AknListTile(
            leading: const _Tile(PhosphorIconsRegular.phone),
            showChevron: true,
            title: ProfileCopy.supportCall,
            subtitle: Fmt.phone(support.phone),
            onTap: () => unawaited(launch(phone)),
          ),
        if (whatsapp != null)
          AknListTile(
            leading: const _Tile(PhosphorIconsRegular.chatText),
            showChevron: true,
            title: ProfileCopy.supportWhatsapp,
            subtitle: Fmt.phone(support.whatsapp),
            onTap: () => unawaited(launch(whatsapp)),
          ),
        if (email != null)
          AknListTile(
            leading: const _Tile(PhosphorIconsRegular.envelopeSimple),
            showChevron: true,
            title: ProfileCopy.supportEmail,
            subtitle: support.email,
            onTap: () => unawaited(launch(email)),
          ),
        AknListTile(
          leading: const _Tile(PhosphorIconsRegular.question),
          showChevron: true,
          title: ProfileCopy.supportPage,
          subtitle: ProfileCopy.supportPageHint,
          onTap: () => unawaited(launch(page, external: false)),
        ),
      ],
    );
  }
}

/// Kanal simgesi (v3): 40 px, r12 yumuşak turuncu karo, turuncu (Pas) simge.
class _Tile extends StatelessWidget {
  const _Tile(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c.brandSoft,
          borderRadius: AknRadius.buttonSmall,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: c.brandInk),
      ),
    );
  }
}
