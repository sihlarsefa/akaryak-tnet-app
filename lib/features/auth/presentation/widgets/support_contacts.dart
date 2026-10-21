import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/link_opener.dart';
import '../../copy.dart';
import '../../data/server_gate.dart';

/// Destek kanalları (`app/config.support`): ara, WhatsApp, e-posta, destek sayfası — tek grup kutusunda
/// ince çizgilerle ayrılmış satırlar (tasarım v2 §4.5; kart listesi değil). Tanımsız kanal gizlenir;
/// hiçbiri yoksa kısa bir not gösterilir.
class SupportContacts extends ConsumerWidget {
  const SupportContacts({super.key, required this.links, this.mailSubject});

  final AuthLinks links;
  final String? mailSubject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final c = context.akn;
    final phone = SupportLinks.phone(links.supportPhone);
    final whatsapp = SupportLinks.whatsapp(links.supportWhatsapp);
    final email = SupportLinks.email(links.supportEmail, subject: mailSubject);
    final page = SupportLinks.web(links.supportUrl);
    if (phone == null && whatsapp == null && email == null && page == null) {
      return Text(
        AuthCopy.noSupport,
        style: t.bodySmall.copyWith(color: c.dim),
      );
    }
    Future<void> open(Uri uri, {bool external = true}) async {
      final ok = await ref.read(linkOpenerProvider)(uri, external: external);
      if (!ok) AppToast.error(AuthCopy.linkFailed);
    }

    final channels = <Widget>[
      if (phone != null)
        _Channel(
          icon: Icons.call_outlined,
          label: AuthCopy.callSupport,
          detail: Fmt.phone(links.supportPhone),
          onTap: () => open(phone),
        ),
      if (whatsapp != null)
        _Channel(
          icon: Icons.chat_outlined,
          label: AuthCopy.whatsappSupport,
          detail: Fmt.phone(links.supportWhatsapp),
          onTap: () => open(whatsapp),
        ),
      if (email != null)
        _Channel(
          icon: Icons.mail_outline_rounded,
          label: AuthCopy.emailSupport,
          detail: links.supportEmail!,
          onTap: () => open(email),
        ),
      if (page != null)
        _Channel(
          icon: Icons.support_agent_outlined,
          label: AuthCopy.supportPage,
          detail: page.host,
          onTap: () => open(page, external: false),
        ),
    ];
    return AknCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < channels.length; i++) ...[
            if (i > 0) const AknLedgerDivider(indent: 16),
            channels[i],
          ],
        ],
      ),
    );
  }
}

class _Channel extends StatelessWidget {
  const _Channel({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, $detail',
      excludeSemantics: true,
      onTap: onTap,
      child: AknListTile(
        leadingIcon: icon,
        title: label,
        subtitle: detail,
        titleStyle: context.aknText.bodyStrong,
        showChevron: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        onTap: onTap,
      ),
    );
  }
}
