import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/link_opener.dart';
import '../../copy.dart';
import '../../data/server_gate.dart';

/// Destek kanalları (`app/config.support`): ara, WhatsApp, e-posta, destek sayfası. Tanımsız kanal
/// gizlenir; hiçbiri yoksa kısa bir not gösterilir.
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
        textAlign: TextAlign.center,
      );
    }
    Future<void> open(Uri uri, {bool external = true}) async {
      final ok = await ref.read(linkOpenerProvider)(uri, external: external);
      if (!ok) AppToast.error(AuthCopy.linkFailed);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (phone != null)
          _Channel(
            icon: Icons.call_rounded,
            label: AuthCopy.callSupport,
            detail: Fmt.phone(links.supportPhone),
            onTap: () => open(phone),
          ),
        if (whatsapp != null)
          _Channel(
            icon: Icons.chat_rounded,
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
            icon: Icons.support_agent_rounded,
            label: AuthCopy.supportPage,
            detail: page.host,
            onTap: () => open(page, external: false),
          ),
      ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        label: '$label, $detail',
        excludeSemantics: true,
        onTap: onTap,
        child: AknCard(
          padding: EdgeInsets.zero,
          shadow: false,
          onTap: onTap,
          child: AknListTile(
            leadingIcon: icon,
            leadingTone: AknTone.brand,
            title: label,
            subtitle: detail,
            showChevron: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ),
    );
  }
}
