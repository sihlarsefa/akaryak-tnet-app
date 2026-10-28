import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_failure.dart';
import '../../../core/ui/ui.dart';
import '../../profile/api.dart';
import '../application/assistant_gate.dart';
import '../copy.dart';
import '../data/assistant_models.dart';
import 'widgets/assistant_avatar.dart';

/// Tam ekran aydınlatma metni (spec A.6; tasarım v3): süzülen logo karosu, `display` başlık, olgular
/// beyaz kartta turuncu onay simgeleriyle, bölümler, "Kart, şifre, kod paylaşmayın" uyarısı; bölümler
/// sırayla belirir. "Kabul ediyorum" → `POST assistant/consent`; "Vazgeç" kapatır.
class DisclosureView extends ConsumerWidget {
  const DisclosureView({
    super.key,
    required this.gate,
    required this.onDecline,
  });

  final GateNeedsConsent gate;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.akn;
    final t = context.aknText;
    final d = gate.disclosure;
    final sections = d.displaySections;
    final facts = [
      if (d.provider != null)
        d.providerCountry == null
            ? d.provider!
            : '${d.provider}, ${d.providerCountry}',
      if (d.retentionDays != null) AssistantCopy.retention(d.retentionDays!),
      AssistantCopy.optional,
    ];
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AknSpace.page,
              20,
              AknSpace.page,
              24,
            ),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AknAmbient(
                  period: AknMotion.float,
                  reverse: true,
                  builder: (context, t, child) => Transform.translate(
                    offset: Offset(0, -4 * t),
                    child: child,
                  ),
                  child: const AssistantAvatar(size: 48),
                ),
              ),
              const SizedBox(height: 20),
              FadeUp(
                offset: 14,
                duration: const Duration(milliseconds: 360),
                child: Semantics(
                  header: true,
                  child: Text(
                    d.title,
                    style: t.display.copyWith(color: c.ink),
                    textScaler: MediaQuery.textScalerOf(
                      context,
                    ).clamp(maxScaleFactor: 1.6),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FadeUp(
                offset: 14,
                delay: const Duration(milliseconds: 40),
                duration: const Duration(milliseconds: 360),
                child: Text(
                  AssistantCopy.disclosureLead,
                  style: t.body.copyWith(color: c.dim),
                ),
              ),
              const SizedBox(height: 18),
              // Olgular: virgülle değil, ayrı satırlarda; her biri turuncu onay dairesiyle.
              FadeUp(
                offset: 14,
                delay: const Duration(milliseconds: 80),
                duration: const Duration(milliseconds: 360),
                child: AknCard(
                  radius: 20,
                  padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < facts.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExcludeSemantics(
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: c.brandSoft,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  PhosphorIconsBold.check,
                                  size: 13,
                                  color: c.brandInk,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                facts[i],
                                style: t.bodySmall.copyWith(
                                  color: c.ink,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (gate.notice != null) ...[
                const SizedBox(height: 16),
                AknBanner(tone: AknTone.info, message: gate.notice!),
              ],
              const SizedBox(height: 16),
              for (final s in sections) _Section(section: s),
              const SizedBox(height: 4),
              const AknBanner(
                tone: AknTone.warn,
                icon: PhosphorIconsRegular.shieldWarning,
                title: AssistantCopy.doNotShare,
                message: AssistantCopy.doNotShareBody,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AknInlineLink(
                  label: AssistantCopy.fullText,
                  onTap: () => unawaited(_openFull(ref, d)),
                ),
              ),
            ],
          ),
        ),
        ActionBar(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AknButton(
                label: AssistantCopy.accept,
                expand: true,
                showSuccess: false,
                onPressedAsync: () => _accept(ref),
              ),
              AknButton.ghost(
                label: AssistantCopy.decline,
                expand: true,
                onPressed: onDecline,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Future<void> _accept(WidgetRef ref) async {
    try {
      await ref.read(assistantGateProvider.notifier).accept();
    } on AppFailure catch (f) {
      AppToast.error(
        f is OfflineFailure || f is TimeoutFailure
            ? f.message
            : AssistantCopy.acceptFailed,
      );
    }
  }

  static Future<void> _openFull(WidgetRef ref, AssistantDisclosure d) async {
    final target =
        SupportUris.web(d.legalUrl) ?? ref.read(legalUrisProvider).ai;
    final ok = await ref.read(profileLinkOpenerProvider)(target);
    if (!ok) AppToast.error(AssistantCopy.linkFailed);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.section});

  final DisclosureSection section;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.title.isNotEmpty) ...[
            Semantics(
              header: true,
              child: Text(
                section.title,
                style: t.headline.copyWith(color: c.ink),
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(section.body, style: t.body.copyWith(color: c.ink)),
        ],
      ),
    );
  }
}
