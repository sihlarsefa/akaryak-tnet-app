import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/env/app_info.dart';
import '../../../../core/ui/ui.dart';
import '../../application/link_opener.dart';
import '../../application/server_gate_controller.dart';
import '../../copy.dart';

/// Giriş ekranının alt bilgisi: "Gizlilik · KVKK · Koşullar" (`app/config.legal`, uygulama içi
/// tarayıcıda) ve sürüm. Adresi olmayan bağlantı gizlenir.
class LegalFooter extends ConsumerWidget {
  const LegalFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final links = ref.watch(authLinksProvider);
    final info = ref.watch(appInfoProvider);
    final t = context.aknText;
    final c = context.akn;
    final items = <({String label, String spoken, Uri uri})>[
      if (SupportLinks.web(links.privacyUrl) case final u?)
        (label: AuthCopy.privacy, spoken: AuthCopy.privacySpoken, uri: u),
      if (SupportLinks.web(links.kvkkUrl) case final u?)
        (label: AuthCopy.kvkk, spoken: AuthCopy.kvkkSpoken, uri: u),
      if (SupportLinks.web(links.termsUrl) case final u?)
        (label: AuthCopy.terms, spoken: AuthCopy.termsSpoken, uri: u),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          if (items.isNotEmpty)
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    ExcludeSemantics(
                      child: Text('·', style: t.body.copyWith(color: c.dim)),
                    ),
                  _LegalLink(
                    label: items[i].label,
                    spoken: items[i].spoken,
                    onTap: () => _open(ref, items[i].uri),
                  ),
                ],
              ],
            ),
          const SizedBox(height: 4),
          Text(
            AuthCopy.version(info.versionLabel),
            style: t.caption.copyWith(color: c.dim),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _open(WidgetRef ref, Uri uri) async {
    final ok = await ref.read(linkOpenerProvider)(uri);
    if (!ok) AppToast.error(AuthCopy.linkFailed);
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({
    required this.label,
    required this.spoken,
    required this.onTap,
  });

  final String label;
  final String spoken;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Semantics(
      link: true,
      label: spoken,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: AknRadius.chip,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AknSpace.minTap,
            minWidth: AknSpace.minTap,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: t.label.copyWith(color: c.text),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
