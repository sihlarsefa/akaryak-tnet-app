import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/offline/connectivity.dart';
import '../../../core/offline/outbox_op.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../application/form_wizard_controller.dart';
import '../copy.dart';
import '../data/field_models.dart';
import '../data/field_outbox.dart';
import 'form_preview.dart';
import 'form_wizard_steps.dart';
import 'widgets/field_inputs.dart';

/// Saha formu v2 sihirbazı (spec A.3 F2–F3; tam ekran, açık "Kapat"). Adımlar: Cari → Tedarik → Ödeme
/// → Satırlar → Özet. Canlı önizleme alt şeritte; "Kaydet" çevrimdışı güvenli, "Onaya gönder" bağlantı
/// ister.
class FieldFormWizardPage extends ConsumerStatefulWidget {
  const FieldFormWizardPage({super.key, required this.args});

  final FormWizardArgs args;

  @override
  ConsumerState<FieldFormWizardPage> createState() =>
      _FieldFormWizardPageState();
}

class _FieldFormWizardPageState extends ConsumerState<FieldFormWizardPage> {
  int _lastStep = 0;
  bool _reverse = false;

  FormWizardController get _ctrl =>
      ref.read(formWizardProvider(widget.args).notifier);

  Future<void> _close() async {
    final s = ref.read(formWizardProvider(widget.args));
    if (s.outcome != null || !s.dirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final choice = await showWizardLeaveSheet(context, canSave: s.hasCustomer);
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

  Future<void> _submit() async {
    final p = ref.read(formWizardProvider(widget.args)).preview;
    if (p != null && p.band.isReject) {
      final go = await showConfirmSheet(
        context,
        title: 'Form otomatik reddedilecek',
        message:
            'Bu fiyatla kâr barem alt sınırının altında kalıyor. Fiyatı güncelleyin ya da gerekçeyle stratejik istisna isteyin. Yine de gönderilsin mi?',
        confirmLabel: 'Yine de gönder',
        cancelLabel: 'Düzenle',
        tone: AknTone.danger,
      );
      if (!go) return;
    }
    await _ctrl.submit();
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    final s = ref.watch(formWizardProvider(args));
    final step = s.step.index;
    if (step != _lastStep) {
      _reverse = step < _lastStep;
      _lastStep = step;
    }

    final outcome = s.outcome;
    if (outcome != null) {
      return PopScope(
        child: AppScaffold(
          title: 'Saha formu',
          showBell: false,
          automaticallyImplyLeading: false,
          leading: AknIconButton(
            icon: Icons.close_rounded,
            semanticLabel: 'Kapat',
            onPressed: () => Navigator.of(context).pop(),
          ),
          body: SingleChildScrollView(
            child: _OutcomeView(outcome: outcome, ctrl: _ctrl),
          ),
        ),
      );
    }

    final online = ref.watch(isOnlineProvider);
    final title = s.draft.formNumber ?? 'Yeni saha formu';
    return PopScope(
      canPop: !s.dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: AppScaffold(
        title: title,
        subtitle: s.draft.customerTitle,
        showBell: false,
        automaticallyImplyLeading: false,
        leading: AknIconButton(
          icon: Icons.close_rounded,
          semanticLabel: 'Sihirbazı kapat',
          onPressed: _close,
        ),
        actions: [
          if (s.hasCustomer)
            TextButton(
              onPressed: s.busy ? null : _ctrl.saveDraft,
              child: const Text('Kaydet'),
            ),
        ],
        refreshing: s.optionsLoading,
        body: s.loading
            ? const LoadingView(message: 'Form açılıyor')
            : s.loadError != null
            ? ErrorState(
                message: s.loadError!.message,
                onRetry: () => ref.invalidate(formWizardProvider(args)),
              )
            : Column(
                children: [
                  StepperHeader(
                    steps: [for (final x in FieldWizardStep.values) x.title],
                    // Adım çubuklarına dokunma yok (16 dp hedef); geri dönüş "Geri" ile.
                    current: step,
                  ),
                  if (s.banner != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: AknBanner(
                        tone: s.conflict ? AknTone.warn : AknTone.danger,
                        title: s.conflict
                            ? 'Bu kayıt sizden sonra güncellendi'
                            : null,
                        message: s.banner!,
                        actionLabel: s.conflict ? 'Yenile' : null,
                        onAction: s.conflict ? _ctrl.reloadAfterConflict : null,
                      ),
                    ),
                  Expanded(
                    child: SharedAxisSwitcher(
                      reverse: _reverse,
                      child: KeyedSubtree(
                        key: ValueKey(s.step),
                        child: FieldWizardStepBody(args: args, step: s.step),
                      ),
                    ),
                  ),
                ],
              ),
        actionBar: s.loading || s.loadError != null
            ? null
            : _BottomBar(args: args, online: online, onSubmit: _submit),
      ),
    );
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({
    required this.args,
    required this.online,
    required this.onSubmit,
  });

  final FormWizardArgs args;
  final bool online;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(formWizardProvider(args));
    final ctrl = ref.read(formWizardProvider(args).notifier);
    final last = s.step == FieldWizardStep.summary;
    final t = context.aknText;
    final showStrip =
        s.options != null && s.step != FieldWizardStep.customer && !last;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showStrip) FieldPreviewStrip(args: args),
        if (s.busy && s.busyLabel != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Semantics(
              liveRegion: true,
              child: Text(
                s.busyLabel!,
                style: t.caption,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        if (last && !online)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Çevrimdışısınız: taslağı kaydedebilirsiniz; göndermek için bağlantı gerekir.',
              style: t.caption,
              textAlign: TextAlign.center,
            ),
          ),
        Row(
          children: [
            if (s.step.index > 0 && !last)
              Expanded(
                child: AknButton.secondary(
                  label: 'Geri',
                  expand: true,
                  onPressed: s.busy ? null : ctrl.back,
                ),
              ),
            if (last)
              Expanded(
                child: AknButton.secondary(
                  label: 'Taslak kaydet',
                  expand: true,
                  loading: s.busy && s.busyLabel == 'Kaydediliyor',
                  onPressed: s.busy ? null : ctrl.saveDraft,
                ),
              ),
            if (s.step.index > 0 || last) const SizedBox(width: 12),
            Expanded(
              child: last
                  ? AknButton(
                      label: 'Onaya gönder',
                      icon: Icons.send_rounded,
                      expand: true,
                      loading: s.busy && s.busyLabel != 'Kaydediliyor',
                      onPressed: s.busy || !online ? null : onSubmit,
                    )
                  : AknButton(
                      label: 'İleri',
                      trailingIcon: Icons.arrow_forward_rounded,
                      expand: true,
                      onPressed: s.busy ? null : () => ctrl.next(),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Kaydet / gönder sonucu.
class _OutcomeView extends ConsumerWidget {
  const _OutcomeView({required this.outcome, required this.ctrl});

  final FieldWizardOutcome outcome;
  final FormWizardController ctrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void openForm(int id) => context.pushReplacement(AppRoutes.fieldForm(id));
    void close() => Navigator.of(context).pop();
    switch (outcome) {
      case FieldDraftSaved(:final form):
        return ResultView(
          title: 'Taslak kaydedildi',
          message:
              '${form.formNumber} Formlarım’da. Hazır olduğunuzda onaya gönderebilirsiniz.',
          details: _FormFacts(
            customer: form.customerTitle,
            liters: form.totalLiters,
            amount: form.totalAmount,
          ),
          primaryLabel: 'Formu aç',
          onPrimary: () => openForm(form.id),
          secondaryLabel: 'Kapat',
          onSecondary: close,
        );
      case FieldDraftQueued(:final opId, :final submitRequested):
        return _QueuedOutcome(opId: opId, submitRequested: submitRequested);
      case FieldFormSubmitted(:final result):
        return _SubmittedOutcome(result: result);
    }
  }
}

class _FormFacts extends StatelessWidget {
  const _FormFacts({this.customer, this.liters, this.amount});

  final String? customer;
  final double? liters;
  final double? amount;

  @override
  Widget build(BuildContext context) => AknCard(
    child: Column(
      children: [
        if (customer != null) FactRow(label: 'Cari', value: customer!),
        if (liters != null) FactRow(label: 'Toplam', value: Fmt.liters(liters)),
        if (amount != null && amount! > 0)
          FactRow(label: 'Tutar', value: Fmt.money(amount)),
      ],
    ),
  );
}

/// Kuyruktaki taslağın canlı sonucu: sırada iken uyarı tonu + saat; sunucu onaylayınca başarı işareti
/// çizilir; reddedilirse sunucu mesajı + "Düzelt" (spec C.4a).
class _QueuedOutcome extends ConsumerWidget {
  const _QueuedOutcome({required this.opId, required this.submitRequested});

  final String opId;
  final bool submitRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final op = ref.watch(fieldOpProvider(opId));
    void close() => Navigator.of(context).pop();
    if (op != null && op.status == OutboxStatus.done) {
      final number = op.result?['formNumber'] as String?;
      final id = op.result?['formId'] as int?;
      return ResultView(
        title: 'Taslak kaydedildi',
        message: submitRequested
            ? '${number ?? 'Taslak'} sunucuya ulaştı. Şimdi onaya gönderebilirsiniz.'
            : '${number ?? 'Taslak'} sunucuya ulaştı ve Formlarım’da.',
        primaryLabel: id == null ? 'Kapat' : 'Formu aç',
        onPrimary: id == null
            ? close
            : () => context.pushReplacement(AppRoutes.fieldForm(id)),
        secondaryLabel: id == null ? null : 'Kapat',
        onSecondary: id == null ? null : close,
      );
    }
    if (op != null && op.status == OutboxStatus.needsAttention) {
      return ResultView(
        title: 'Taslak gönderilemedi',
        message: op.lastError ?? 'Sunucu taslağı kabul etmedi.',
        tone: AknTone.danger,
        icon: Icons.error_outline_rounded,
        primaryLabel: 'Düzelt',
        onPrimary: () =>
            context.pushReplacement('${AppRoutes.fieldFormNew}?op=$opId'),
        secondaryLabel: 'Kapat',
        onSecondary: close,
      );
    }
    return ResultView(
      title: FieldCopy.queuedTitle,
      message: submitRequested
          ? '${FieldCopy.queuedFormMessage} Onaya göndermek için bağlantı gelince formu açın.'
          : FieldCopy.queuedFormMessage,
      tone: AknTone.warn,
      icon: Icons.schedule_rounded,
      primaryLabel: 'Tamam',
      onPrimary: close,
    );
  }
}

class _SubmittedOutcome extends StatelessWidget {
  const _SubmittedOutcome({required this.result});

  final FieldSubmitResult result;

  @override
  Widget build(BuildContext context) {
    void openForm() =>
        context.pushReplacement(AppRoutes.fieldForm(result.formId));
    void newForm() => context.pushReplacement(AppRoutes.fieldFormNew);
    final (title, tone, icon, message) = switch (result.status) {
      FieldOrderFormStatus.converted => (
        'Form onaylandı',
        AknTone.ok,
        null,
        result.message.isNotEmpty
            ? result.message
            : 'Form otomatik onaylandı ve siparişe dönüştü; teklif müşteri onayına gitti.',
      ),
      FieldOrderFormStatus.rejected => (
        'Form reddedildi',
        AknTone.danger,
        Icons.cancel_rounded,
        result.message.isNotEmpty
            ? result.message
            : 'Form kârlılık kuralı gereği otomatik reddedildi.',
      ),
      FieldOrderFormStatus.approved => (
        'Kârlılık onayı tamam',
        AknTone.info,
        Icons.account_balance_outlined,
        'Finans onayı bekleniyor. Finans onaylayınca siparişler otomatik açılır.',
      ),
      _ => (
        'Onaya gönderildi',
        AknTone.info,
        Icons.hourglass_top_rounded,
        [
          FieldLevels.waitingText(result.requiredApprovalLevel),
          if (result.financeStatus.isAwaitingDecision)
            'Finans onayı paralel yürüyor.',
        ].join(' '),
      ),
    };
    return ResultView(
      title: title,
      message: message,
      tone: tone,
      icon: icon,
      details: result.convertedOrderIds.isEmpty
          ? null
          : AknCard(
              child: FactRow(
                label: 'Açılan sipariş',
                value: '${result.convertedOrderIds.length} sipariş',
              ),
            ),
      primaryLabel: 'Formu aç',
      onPrimary: openForm,
      secondaryLabel: 'Yeni form',
      onSecondary: newForm,
    );
  }
}
