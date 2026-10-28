import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/offline/connectivity.dart';
import '../../../core/offline/outbox_op.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../application/lead_wizard_controller.dart';
import '../copy.dart';
import '../data/field_outbox.dart';
import 'lead_wizard_steps.dart';
import 'widgets/field_inputs.dart';

/// Ön kayıt sihirbazı (spec A.3 L1): Firma → Filo / depo → İhtiyaç → Ödeme talebi → Ziyaret →
/// Yetkililer → İlk teslimat noktası → KVKK → Belgeler. Tasarım v3: adım şeridi kayarak ilerler,
/// adımlar yatay ortak eksende geçer ve alanlar sırayla belirir; alt çubukta "Geri" yana açılarak gelir,
/// birincil düğme "İleri" ↔ "Finansa gönder" yaylanarak değişir. Kayıt çevrimdışı güvenlidir; finansa
/// gönderim KVKK açık rızası ve vergi levhası ister.
class FieldLeadWizardPage extends ConsumerStatefulWidget {
  const FieldLeadWizardPage({super.key, required this.args});

  final LeadWizardArgs args;

  @override
  ConsumerState<FieldLeadWizardPage> createState() =>
      _FieldLeadWizardPageState();
}

class _FieldLeadWizardPageState extends ConsumerState<FieldLeadWizardPage> {
  int _lastStep = 0;
  bool _reverse = false;

  LeadWizardController get _ctrl =>
      ref.read(leadWizardProvider(widget.args).notifier);

  Future<void> _close() async {
    final s = ref.read(leadWizardProvider(widget.args));
    if (s.outcome != null || !s.dirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final choice = await showWizardLeaveSheet(
      context,
      canSave: s.draft.canSaveDraft,
    );
    if (!mounted) return;
    switch (choice) {
      case WizardLeaveChoice.save:
        await _ctrl.saveDraft();
      case WizardLeaveChoice.discard:
        Navigator.of(context).pop();
      case WizardLeaveChoice.stay:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    final s = ref.watch(leadWizardProvider(args));
    final step = s.step.index;
    if (step != _lastStep) {
      _reverse = step < _lastStep;
      _lastStep = step;
    }
    final outcome = s.outcome;
    if (outcome != null) {
      return AppScaffold(
        title: 'Ön kayıt',
        showBell: false,
        automaticallyImplyLeading: false,
        leading: AknIconButton(
          icon: PhosphorIconsRegular.x,
          semanticLabel: 'Kapat',
          onPressed: () => Navigator.of(context).pop(),
        ),
        body: SingleChildScrollView(child: _LeadOutcomeView(outcome: outcome)),
      );
    }
    final title =
        s.leadNumber ?? (s.draft.isNew ? 'Yeni ön kayıt' : 'Ön kayıt');
    final online = ref.watch(isOnlineProvider);
    return PopScope(
      canPop: !s.dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: AppScaffold(
        title: title,
        subtitle: s.draft.companyTitle.isEmpty ? null : s.draft.companyTitle,
        showBell: false,
        automaticallyImplyLeading: false,
        leading: AknIconButton(
          icon: PhosphorIconsRegular.x,
          semanticLabel: 'Sihirbazı kapat',
          onPressed: _close,
        ),
        actions: [
          TextButton(
            onPressed: s.busy || !s.draft.canSaveDraft ? null : _ctrl.saveDraft,
            child: const Text('Kaydet'),
          ),
        ],
        body: s.loading
            ? const LoadingView(message: 'Ön kayıt açılıyor')
            : s.loadError != null
            ? ErrorState(
                message: s.loadError!.message,
                onRetry: () => ref.invalidate(leadWizardProvider(args)),
              )
            : Column(
                children: [
                  StepperHeader(
                    steps: [for (final x in LeadWizardStep.values) x.title],
                    // Adım çubuklarına dokunma yok (16 dp hedef); eksik maddeye "Eksiği tamamla" götürür.
                    current: step,
                  ),
                  if (s.banner != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: AknBanner(
                        tone: s.conflict
                            ? AknTone.warn
                            : (s.missing.isNotEmpty
                                  ? AknTone.warn
                                  : AknTone.danger),
                        title: s.conflict
                            ? 'Bu kayıt sizden sonra güncellendi'
                            : null,
                        message: s.banner!,
                        actionLabel: s.conflict
                            ? 'Yenile'
                            : (s.missing.isNotEmpty ? 'Eksiği tamamla' : null),
                        onAction: s.conflict
                            ? _ctrl.reloadAfterConflict
                            : (s.missing.isNotEmpty
                                  ? () => _ctrl.goTo(
                                      LeadWizardController.stepOfMissing(
                                        s.missing.first,
                                      ),
                                    )
                                  : null),
                      ),
                    ),
                  Expanded(
                    child: SharedAxisSwitcher(
                      reverse: _reverse,
                      child: KeyedSubtree(
                        key: ValueKey(s.step),
                        child: LeadWizardStepBody(args: args, step: s.step),
                      ),
                    ),
                  ),
                ],
              ),
        actionBar: s.loading || s.loadError != null
            ? null
            : _LeadBottomBar(args: args, online: online),
      ),
    );
  }
}

class _LeadBottomBar extends ConsumerWidget {
  const _LeadBottomBar({required this.args, required this.online});

  final LeadWizardArgs args;
  final bool online;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(leadWizardProvider(args));
    final ctrl = ref.read(leadWizardProvider(args).notifier);
    final last = s.step == LeadWizardStep.documents;
    final t = context.aknText;
    final missing = last ? s.missingNow : const <String>[];
    final left = last
        ? AknButton.secondary(
            label: 'Taslak kaydet',
            expand: true,
            loading: s.busy && s.busyLabel == 'Kaydediliyor',
            onPressed: s.busy || !s.draft.canSaveDraft ? null : ctrl.saveDraft,
          )
        : s.step.index > 0
        ? AknButton.secondary(
            label: 'Geri',
            expand: true,
            onPressed: s.busy ? null : ctrl.back,
          )
        : null;
    final primary = last
        ? AknButton(
            label: 'Finansa gönder',
            icon: PhosphorIconsRegular.paperPlaneRight,
            expand: true,
            loading: s.busy && s.busyLabel != 'Kaydediliyor',
            onPressed: s.busy || !online ? null : ctrl.submit,
          )
        : AknButton(
            label: 'İleri',
            trailingIcon: PhosphorIconsRegular.arrowRight,
            expand: true,
            onPressed: s.busy ? null : () => ctrl.next(),
          );
    final String? state = last && missing.isNotEmpty
        ? 'Göndermek için eksik: ${missing.join(', ')}'
        : last && !online
        ? 'Çevrimdışısınız: kaydedebilirsiniz; finansa göndermek için bağlantı gerekir.'
        : null;
    final notes = <Widget>[
      if (s.busy && s.busyLabel != null)
        Semantics(
          liveRegion: true,
          child: Text(
            s.busyLabel!,
            style: t.caption,
            textAlign: TextAlign.center,
          ),
        ),
      if (state != null)
        Text(state, style: t.caption, textAlign: TextAlign.center),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AknAnimatedSize(
          alignment: Alignment.bottomCenter,
          child: notes.isEmpty
              ? const SizedBox(width: double.infinity)
              // Büyük yazıda uzun "eksik" listesi alt çubuğu ekranın üstüne taşırmasın: en çok
              // ekranın beşte biri, gerisi kaydırılarak okunur.
              : ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.2,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final n in notes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: n,
                          ),
                      ],
                    ),
                  ),
                ),
        ),
        FieldWizardButtons(stepKey: last, left: left, primary: primary),
      ],
    );
  }
}

class _LeadOutcomeView extends ConsumerWidget {
  const _LeadOutcomeView({required this.outcome});

  final LeadWizardOutcome outcome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void close() => Navigator.of(context).pop();
    switch (outcome) {
      case LeadSaved(:final result):
        return ResultView(
          title: 'Ön kayıt kaydedildi',
          message:
              '${result.leadNumber} taslak olarak kaydedildi.${result.warnings.isEmpty ? '' : ' ${result.warnings.join(' ')}'}',
          primaryLabel: 'Ön kaydı aç',
          onPrimary: () =>
              context.pushReplacement(AppRoutes.fieldLead(result.id)),
          secondaryLabel: 'Kapat',
          onSecondary: close,
        );
      case LeadQueued(:final opId, :final submitRequested):
        return _LeadQueuedView(opId: opId, submitRequested: submitRequested);
      case LeadSubmitted(:final leadId, :final message):
        return ResultView(
          title: 'Finansa gönderildi',
          message: '$message Finans ek bilgi isterse size bildirim gelir.',
          tone: AknTone.ok,
          primaryLabel: 'Ön kaydı aç',
          onPrimary: () => context.pushReplacement(AppRoutes.fieldLead(leadId)),
          secondaryLabel: 'Kapat',
          onSecondary: close,
        );
    }
  }
}

class _LeadQueuedView extends ConsumerWidget {
  const _LeadQueuedView({required this.opId, required this.submitRequested});

  final String opId;
  final bool submitRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final op = ref.watch(fieldOpProvider(opId));
    void close() => Navigator.of(context).pop();
    if (op != null && op.status == OutboxStatus.done) {
      final id = op.result?['leadId'] as int?;
      final number = op.result?['leadNumber'] as String?;
      return ResultView(
        title: 'Ön kayıt kaydedildi',
        message: '${number ?? 'Ön kayıt'} sunucuya ulaştı.',
        primaryLabel: id == null ? 'Kapat' : 'Ön kaydı aç',
        onPrimary: id == null
            ? close
            : () => context.pushReplacement(AppRoutes.fieldLead(id)),
        secondaryLabel: id == null ? null : 'Kapat',
        onSecondary: id == null ? null : close,
      );
    }
    if (op != null && op.status == OutboxStatus.needsAttention) {
      return ResultView(
        title: 'Ön kayıt gönderilemedi',
        message: op.lastError ?? 'Sunucu ön kaydı kabul etmedi.',
        tone: AknTone.danger,
        icon: PhosphorIconsRegular.warningCircle,
        primaryLabel: 'Düzelt',
        onPrimary: () =>
            context.pushReplacement('${AppRoutes.fieldLeadNew}?op=$opId'),
        secondaryLabel: 'Kapat',
        onSecondary: close,
      );
    }
    return ResultView(
      title: FieldCopy.queuedTitle,
      message: submitRequested
          ? '${FieldCopy.queuedLeadMessage} Finansa göndermek için bağlantı gelince ön kaydı açın.'
          : FieldCopy.queuedLeadMessage,
      tone: AknTone.warn,
      icon: PhosphorIconsRegular.clock,
      primaryLabel: 'Tamam',
      onPrimary: close,
    );
  }
}
