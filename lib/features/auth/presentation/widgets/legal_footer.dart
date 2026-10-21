import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/env/app_info.dart';
import '../../../../core/ui/ui.dart';
import '../../application/link_opener.dart';
import '../../application/server_gate_controller.dart';
import '../../copy.dart';

/// Giriş ekranının alt bilgisi (tasarım v2 §7.2): solda "Gizlilik  KVKK  Koşullar" (13/18 dim,
/// aralıklı, nokta yok; `app/config.legal`, uygulama içi tarayıcıda), sağda "Sürüm 1.0.0". Adresi
/// olmayan bağlantı gizlenir. Sahte kipte sürümün yanında küçük bir "Demo" bağlantısı ([demo]) sayfanın
/// başındaki demo hesaplarına götürür.
class LegalFooter extends ConsumerWidget {
  const LegalFooter({super.key, this.demo});

  /// Sahte kipte demo hesaplarına götürür (giriş ekranı bölüme kaydırır); null ise düğme yok.
  final VoidCallback? demo;

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
    final small = t.label.copyWith(
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w500,
      color: c.dim,
    );
    final version = Text(
      AuthCopy.version(info.versionLabel),
      style: small,
      textAlign: TextAlign.end,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(AknSpace.page, 0, AknSpace.page, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (items.isNotEmpty)
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final i in items)
                      _LegalLink(
                        label: i.label,
                        spoken: i.spoken,
                        style: small,
                        onTap: () => _open(ref, i.uri),
                      ),
                  ],
                ),
              Wrap(
                spacing: 0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Sahte kipte küçük "Demo" bağlantısı: demo hesaplarına götürür.
                  if (demo != null) ...[
                    _LegalLink(
                      label: AuthCopy.demoCaption,
                      spoken: AuthCopy.demoButton,
                      style: small.copyWith(
                        color: c.ink,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: c.ink,
                      ),
                      onTap: demo!,
                      link: false,
                    ),
                    const SizedBox(width: 12),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AknSpace.minTap,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      widthFactor: 1,
                      child: version,
                    ),
                  ),
                ],
              ),
            ],
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
    required this.style,
    required this.onTap,
    this.link = true,
  });

  final String label;
  final String spoken;
  final TextStyle style;
  final VoidCallback onTap;

  /// Bağlantı (yasal metin) ya da düğme (demo sayfası).
  final bool link;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: link,
      button: !link,
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
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            child: Text(label, style: style),
          ),
        ),
      ),
    );
  }
}
