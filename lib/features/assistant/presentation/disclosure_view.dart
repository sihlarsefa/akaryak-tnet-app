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

/// Tam ekran aydınlatma metni (spec A.6): ne gönderilir, kime (OpenAI, ABD), neden, ne kadar saklanır,
/// "Kart, şifre, kod paylaşmayın". "Kabul ediyorum" → `POST assistant/consent`; "Vazgeç" kapatır.
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
            : '${d.provider} · ${d.providerCountry}',
      if (d.retentionDays != null) AssistantCopy.retention(d.retentionDays!),
      AssistantCopy.optional,
    ];
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const Center(child: AssistantAvatar(size: 56)),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(
                  d.title,
                  style: t.title,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AssistantCopy.disclosureLead,
                style: t.body.copyWith(color: c.dim),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in facts)
                    StatusChip(
                      label: f,
                      tone: AknTone.neutral,
                      showIcon: false,
                    ),
                ],
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
                icon: Icons.privacy_tip_rounded,
                title: AssistantCopy.doNotShare,
                message: AssistantCopy.doNotShareBody,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => unawaited(_openFull(ref, d)),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text(AssistantCopy.fullText),
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
              child: Text(section.title, style: t.bodyStrong),
            ),
            const SizedBox(height: 4),
          ],
          Text(section.body, style: t.body.copyWith(color: c.text)),
        ],
      ),
    );
  }
}
