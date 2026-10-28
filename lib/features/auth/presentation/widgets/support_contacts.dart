import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/link_opener.dart';
import '../../copy.dart';
import '../../data/server_gate.dart';

/// Destek kanalları (`app/config.support`): ara, WhatsApp, e-posta, destek sayfası — tek beyaz kartta
/// (r20, kart gölgesi) içeriden başlayan ince çizgilerle ayrılmış satırlar; her satırın başında 40 px
/// yuvarlak köşeli simge karosu (tasarım v3 §4). Tanımsız kanal gizlenir; hiçbiri yoksa kısa bir not
/// gösterilir.
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
          icon: PhosphorIconsRegular.phone,
          label: AuthCopy.callSupport,
          detail: Fmt.phone(links.supportPhone),
          onTap: () => open(phone),
        ),
      if (whatsapp != null)
        _Channel(
          icon: PhosphorIconsRegular.chatText,
          label: AuthCopy.whatsappSupport,
          detail: Fmt.phone(links.supportWhatsapp),
          onTap: () => open(whatsapp),
        ),
      if (email != null)
        _Channel(
          icon: PhosphorIconsRegular.envelopeSimple,
          label: AuthCopy.emailSupport,
          detail: links.supportEmail!,
          onTap: () => open(email),
        ),
      if (page != null)
        _Channel(
          icon: PhosphorIconsRegular.headset,
          label: AuthCopy.supportPage,
          detail: page.host,
          onTap: () => open(page, external: false),
        ),
    ];
    return AknCard(
      padding: EdgeInsets.zero,
      radius: 20,
      child: ClipRRect(
        borderRadius: AknRadius.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < channels.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 70),
                  child: Divider(height: 1, thickness: 1, color: c.lineSoft),
                ),
              channels[i],
            ],
          ],
        ),
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
        leading: _IconTile(icon: icon),
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

/// Kanal simgesi: 40 px, r12 yumuşak turuncu karo, turuncu (Pas) simge.
class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon});

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
