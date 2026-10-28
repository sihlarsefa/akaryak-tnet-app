import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/approval_detail_controller.dart';
import '../../copy.dart';
import '../../data/approval_models.dart';
import '../../data/condition_values.dart';
import '../../shared/layout.dart';
import 'condition_form_view.dart';
import 'decision_bar.dart' show decisionIcon;

/// Karar sayfasını açar; başarıda sunucu mesajını döndürür (vazgeçilirse null).
Future<String?> showDecisionSheet(
  BuildContext context, {
  required int approvalId,
  required ApprovalDecision decision,
}) => showAppSheet<String>(
  context: context,
  title: _title(decision),
  subtitle: _subtitle(decision),
  builder: (_) => DecisionSheet(approvalId: approvalId, decision: decision),
);

String _title(ApprovalDecision d) => switch (d) {
  ApprovalDecision.approve => 'Talebi onayla',
  ApprovalDecision.conditionalApprove => 'Koşullu onayla',
  ApprovalDecision.requestInfo => 'Ek bilgi iste',
  ApprovalDecision.reject => 'Talebi reddet',
  ApprovalDecision.unknown => 'Karar ver',
};

String? _subtitle(ApprovalDecision d) => switch (d) {
  ApprovalDecision.approve => 'Karar kaydı geri alınamaz.',
  ApprovalDecision.conditionalApprove =>
    'Yalnızca değiştirmek istediğiniz koşulları doldurun.',
  ApprovalDecision.requestInfo => 'Talep eden yanıtlayana kadar talep bekler.',
  ApprovalDecision.reject => 'Gerekçe talep edene iletilir.',
  ApprovalDecision.unknown => null,
};

/// Karar sayfası gövdesi (tasarım v3 §4 sayfa): kararın tonunda simgeli özet, not, (koşullu onayda)
/// koşul formu, (ek bilgide) istenen belge; çakışmada "Yenile" (yazılanlar korunur; bant yumuşakça
/// açılır), alan hataları satır içinde — eksik bilgide alan kısa bir sarsıntıyla uyarır.
class DecisionSheet extends ConsumerStatefulWidget {
  const DecisionSheet({
    super.key,
    required this.approvalId,
    required this.decision,
  });

  final int approvalId;
  final ApprovalDecision decision;

  @override
  ConsumerState<DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends ConsumerState<DecisionSheet> {
  final _note = TextEditingController();
  final ConditionValues _values = {};
  AttachmentKind? _kind;
  bool _busy = false;
  String? _phase;
  ActionOutcome? _problem;
  Map<String, String> _errors = const {};

  /// Her reddedilen gönderimde artar: hatalı alan kısa bir sarsıntıyla uyarır.
  int _shakes = 0;

  ApprovalDecision get _d => widget.decision;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  ApprovalDetail? get _detail =>
      ref.read(approvalDetailProvider(widget.approvalId)).detail;

  /// Yerel doğrulama (sunucu yine denetler).
  Map<String, String> _validate(ApprovalDetail d) {
    final errors = <String, String>{};
    final note = _note.text.trim();
    switch (_d) {
      case ApprovalDecision.requestInfo:
        if (note.isEmpty) {
          errors['note'] = 'Ne istediğinizi yazın.';
        }
      case ApprovalDecision.reject:
        final min = d.minRejectNoteLength;
        if (note.isEmpty) {
          errors['note'] = 'Reddetmek için gerekçe yazın.';
        } else if (note.length < min) {
          errors['note'] = 'Gerekçe en az $min karakter olmalı.';
        }
      case ApprovalDecision.conditionalApprove:
        final form = d.conditionForm;
        if (form != null) {
          errors.addAll(ConditionValueCodec.validate(form, _values));
          final conditions = ConditionValueCodec.build(form, _values);
          if (errors.isEmpty && conditions.isEmpty && note.isEmpty) {
            errors['conditions'] =
                'En az bir koşulu değiştirin ya da koşulu karar notuna yazın.';
          }
        } else if (note.isEmpty) {
          errors['note'] = 'Koşulu karar notuna yazın.';
        }
      default:
        break;
    }
    return errors;
  }

  Future<void> _submit() async {
    final d = _detail;
    if (d == null || _busy) return;
    final errors = _validate(d);
    if (errors.isNotEmpty) {
      setState(() {
        _errors = errors;
        _problem = null;
        _shakes++;
      });
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          errors.values.first,
          TextDirection.ltr,
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _phase = 'Kararınız gönderiliyor…';
      _problem = null;
      _errors = const {};
    });
    final form = d.conditionForm;
    final outcome = await ref
        .read(approvalDetailProvider(widget.approvalId).notifier)
        .decide(
          _d,
          note: _note.text,
          conditions: _d == ApprovalDecision.conditionalApprove && form != null
              ? ConditionValueCodec.build(form, _values)
              : null,
          requiredKind: _kind,
          onPhase: (p) {
            if (mounted) setState(() => _phase = p);
          },
        );
    if (!mounted) return;
    switch (outcome) {
      case ActionDone(:final message):
        AknHaptics.success();
        Navigator.of(context).pop(message);
        return;
      case ActionInvalid(:final fieldErrors):
        setState(() {
          _busy = false;
          _phase = null;
          _errors = fieldErrors;
          _problem = fieldErrors.isEmpty ? outcome : null;
          _shakes++;
        });
      default:
        setState(() {
          _busy = false;
          _phase = null;
          _problem = outcome;
        });
    }
  }

  Future<void> _reload() async {
    setState(() => _problem = null);
    await ref
        .read(approvalDetailProvider(widget.approvalId).notifier)
        .refresh();
    if (!mounted) return;
    final d = _detail;
    if (d == null || !d.can(_d)) {
      Navigator.of(context).pop();
      AppToast.info(
        'Talep güncellendi; bu karar artık verilemiyor.',
        context: context,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(approvalDetailProvider(widget.approvalId));
    final d = s.detail;
    final online = ref.watch(isOnlineProvider);
    if (d == null) return const SizedBox(height: 120, child: LoadingView());
    final t = context.aknText;
    final c = context.akn;
    final form = d.conditionForm;
    final noteError = _errors['note'];
    final problem = _problem;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Recap(detail: d, decision: _d),
        if (d.onBehalfOfName != null) ...[
          const SizedBox(height: 12),
          AknBanner(
            tone: AknTone.info,
            icon: PhosphorIconsRegular.shareNetwork,
            message: '${d.onBehalfOfName} ${ApprovalsCopy.behalfNote}',
          ),
        ],
        _ProblemSlot(outcome: problem, onReload: _reload, onRetry: _submit),
        if ((_d == ApprovalDecision.reject ||
                _d == ApprovalDecision.requestInfo) &&
            d.isCustomerAddressed) ...[
          const SizedBox(height: 12),
          const AknBanner(
            tone: AknTone.neutral,
            icon: PhosphorIconsRegular.envelopeSimple,
            message:
                'Bu not cariye iletilir. İç değerlendirmeyi (risk, limit, teminat) nota yazmayın.',
          ),
        ],
        if (_d == ApprovalDecision.conditionalApprove && form != null) ...[
          const SizedBox(height: 16),
          ConditionFormView(
            form: form,
            values: _values,
            errors: _errors,
            onChanged: (k, v) => setState(() {
              _values[k] = v;
              _errors = {..._errors}
                ..remove(k)
                ..remove('conditions.$k')
                ..remove('conditions');
            }),
          ),
          AknAnimatedSize(
            alignment: Alignment.topCenter,
            child: _errors['conditions'] == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: A5Shake(
                      trigger: _shakes,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(
                              PhosphorIconsRegular.warningCircle,
                              size: 16,
                              color: c.danger.fg,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _errors['conditions']!,
                              style: t.captionStrong.copyWith(
                                color: c.danger.fg,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
        if (_d == ApprovalDecision.requestInfo) ...[
          const SizedBox(height: 16),
          Text('İstenen belge (isteğe bağlı)', style: t.label),
          const SizedBox(height: 4),
          FilterChips<AttachmentKind>(
            padding: EdgeInsets.zero,
            options: [
              for (final k in ApprovalsCopy.requestableKinds)
                FilterOption(
                  value: k,
                  label: k.label,
                  icon: AknStatus.attachmentKind(k).icon,
                ),
            ],
            selected: {?_kind},
            onChanged: (s) =>
                setState(() => _kind = s.isEmpty ? null : s.first),
          ),
          const SizedBox(height: 4),
          Text(
            _kind == null
                ? 'Belge seçmezseniz yalnızca notunuz iletilir.'
                : 'Talep eden "${_kind!.label}" türünde belge ekleyerek yanıtlar.',
            style: t.caption,
          ),
        ],
        const SizedBox(height: 16),
        A5Shake(
          trigger: noteError == null ? 0 : _shakes,
          child: AknTextField(
            controller: _note,
            label: _noteLabel(d),
            hint: _noteHint(),
            requiredMark:
                _d == ApprovalDecision.reject ||
                _d == ApprovalDecision.requestInfo,
            helper: _d == ApprovalDecision.reject
                ? 'En az ${d.minRejectNoteLength} karakter'
                : null,
            errorText: noteError,
            minLines: 3,
            maxLines: 6,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (_errors.containsKey('note')) {
                setState(() => _errors = {..._errors}..remove('note'));
              }
            },
          ),
        ),
        const SizedBox(height: 16),
        if (!online)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              ApprovalsCopy.offlineDecision,
              style: t.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        _button(online),
        AknAnimatedSize(
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: AknMotion.of(context, AknMotion.base),
            child: _phase == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    key: ValueKey(_phase),
                    padding: const EdgeInsets.only(top: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _phase!,
                        style: t.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _button(bool online) {
    final label = switch (_d) {
      ApprovalDecision.approve => 'Onayla',
      ApprovalDecision.conditionalApprove => 'Koşullu onayla',
      ApprovalDecision.requestInfo => 'Ek bilgi iste',
      ApprovalDecision.reject => 'Reddet',
      ApprovalDecision.unknown => 'Gönder',
    };
    final onPressed = online && !_busy ? _submit : null;
    if (_d == ApprovalDecision.reject) {
      return AknButton.danger(
        label: label,
        icon: PhosphorIconsRegular.x,
        expand: true,
        loading: _busy,
        onPressed: onPressed,
      );
    }
    return AknButton(
      label: label,
      icon: _d == ApprovalDecision.requestInfo
          ? PhosphorIconsFill.chatCircleDots
          : PhosphorIconsRegular.check,
      expand: true,
      size: AknButtonSize.large,
      loading: _busy,
      onPressed: onPressed,
    );
  }

  String _noteLabel(ApprovalDetail d) => switch (_d) {
    ApprovalDecision.approve => 'Karar notu (isteğe bağlı)',
    ApprovalDecision.conditionalApprove => 'Karar notu (isteğe bağlı)',
    ApprovalDecision.requestInfo => 'Ne istiyorsunuz?',
    ApprovalDecision.reject => 'Ret gerekçesi',
    ApprovalDecision.unknown => 'Not',
  };

  String? _noteHint() => switch (_d) {
    ApprovalDecision.requestInfo => 'Ör. Çek görselinin arka yüzünü yükleyin.',
    ApprovalDecision.reject => 'Neden reddettiğinizi açıkça yazın.',
    ApprovalDecision.conditionalApprove =>
      'Koşulu açıklayın (ör. ilk iki sipariş peşin).',
    _ => null,
  };
}

/// Talebin kısa özeti (karar sayfasının üstü; tasarım v3): kuyu renginde r16 alan, solda kararın
/// tonunda simge kuyusu (onay yeşil, ret kırmızı, ek bilgi ve koşullu onay turuncu), başlık ve tür,
/// sağda tutar (tablo rakamları; sığmazsa küçülür, büyük yazıda alta iner).
class _Recap extends StatelessWidget {
  const _Recap({required this.detail, required this.decision});

  final ApprovalDetail detail;
  final ApprovalDecision decision;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final d = detail;
    final amount = d.summary.amount ?? d.row.amount;
    final liters = d.summary.liters ?? d.row.liters;
    final headline = d.summary.headline.isNotEmpty
        ? d.summary.headline
        : (d.row.subjectNumber ?? d.row.title);
    final c = context.akn;
    final tone = switch (decision) {
      ApprovalDecision.approve => AknTone.ok,
      ApprovalDecision.reject => AknTone.danger,
      ApprovalDecision.unknown => AknTone.neutral,
      _ => AknTone.brand,
    };
    final figure = amount != null || liters != null
        ? Text(
            amount != null ? Fmt.money(amount) : Fmt.liters(liters),
            style: t.amount.copyWith(color: c.ink),
            maxLines: 1,
            softWrap: false,
          )
        : null;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          headline.replaceAll(' · ', ', '),
          style: t.bodyStrong.copyWith(
            color: c.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(d.row.displayTypeLabel, style: t.label.copyWith(color: c.dim)),
      ],
    );
    // QA BO-04: tutar başlığın yanında esnemiyordu (2,0× ve 11+ haneli tutarda taşma). Büyük
    // yazıda tutar başlığın altında kendi satırına iner; normal yazıda yer kalmazsa küçülür.
    final large = MediaQuery.textScalerOf(context).scale(10) > 13;
    final text = figure == null
        ? heading
        : large
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: figure,
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: heading),
              const SizedBox(width: 12),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.topEnd,
                  child: figure,
                ),
              ),
            ],
          );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: const BorderRadius.all(Radius.circular(16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: A5FadeUp(
              offset: 0,
              scale: 0.6,
              duration: AknMotion.slow,
              curve: AknMotion.emphasizedCurve,
              child: AknIconBox(icon: decisionIcon(decision), tone: tone),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: text),
        ],
      ),
    );
  }
}

/// Sorun bandının yeri: bant solarak ve hafifçe büyüyerek belirir, solarak kalkar.
class _ProblemSlot extends StatelessWidget {
  const _ProblemSlot({
    required this.outcome,
    required this.onReload,
    required this.onRetry,
  });

  final ActionOutcome? outcome;
  final VoidCallback onReload;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final o = outcome;
    return AnimatedSwitcher(
      duration: AknMotion.of(context, AknMotion.base),
      switchInCurve: AknMotion.spring,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(a),
          child: child,
        ),
      ),
      child: o == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              key: ValueKey(o),
              padding: const EdgeInsets.only(top: 12),
              child: _ProblemBanner(
                outcome: o,
                onReload: onReload,
                onRetry: onRetry,
              ),
            ),
    );
  }
}

/// Karar / işlem hatası bandı: çakışmada "Yenile", doğrulanamayan sonuçta "Tekrar dene".
class _ProblemBanner extends StatelessWidget {
  const _ProblemBanner({
    required this.outcome,
    required this.onReload,
    required this.onRetry,
  });

  final ActionOutcome outcome;
  final VoidCallback onReload;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => switch (outcome) {
    ActionConflict(:final message) => AknBanner(
      tone: AknTone.warn,
      title: 'Bu kayıt sizden sonra güncellendi',
      message: message,
      actionLabel: 'Yenile',
      onAction: onReload,
    ),
    ActionUnverified(:final message) => AknBanner(
      tone: AknTone.warn,
      title: 'Sonuç doğrulanamadı',
      message: message,
      actionLabel: 'Tekrar dene',
      onAction: onRetry,
    ),
    ActionFailed(:final message) => AknBanner(
      tone: AknTone.danger,
      message: message,
    ),
    ActionInvalid(:final message) => AknBanner(
      tone: AknTone.danger,
      message: message,
    ),
    ActionDone() => const SizedBox.shrink(),
  };
}

/// Not ve tek düğmeli işlem sayfası ("Bilgi alındı", "Merkeze ilet").
Future<String?> showNoteActionSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? message,
  required String noteLabel,
  String? noteHint,
  required String buttonLabel,
  required IconData icon,
  required Future<ActionOutcome> Function(String note) run,
  Future<void> Function()? onReload,
}) => showAppSheet<String>(
  context: context,
  title: title,
  subtitle: subtitle,
  builder: (_) => _NoteActionSheet(
    message: message,
    noteLabel: noteLabel,
    noteHint: noteHint,
    buttonLabel: buttonLabel,
    icon: icon,
    run: run,
    onReload: onReload,
  ),
);

class _NoteActionSheet extends ConsumerStatefulWidget {
  const _NoteActionSheet({
    required this.noteLabel,
    required this.buttonLabel,
    required this.icon,
    required this.run,
    this.message,
    this.noteHint,
    this.onReload,
  });

  final String? message;
  final String noteLabel;
  final String? noteHint;
  final String buttonLabel;
  final IconData icon;
  final Future<ActionOutcome> Function(String note) run;
  final Future<void> Function()? onReload;

  @override
  ConsumerState<_NoteActionSheet> createState() => _NoteActionSheetState();
}

class _NoteActionSheetState extends ConsumerState<_NoteActionSheet> {
  final _note = TextEditingController();
  bool _busy = false;
  ActionOutcome? _problem;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    final outcome = await widget.run(_note.text);
    if (!mounted) return;
    if (outcome is ActionDone) {
      AknHaptics.success();
      Navigator.of(context).pop(outcome.message);
      return;
    }
    setState(() {
      _busy = false;
      _problem = outcome;
    });
  }

  Future<void> _reload() async {
    setState(() => _problem = null);
    await widget.onReload?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final online = ref.watch(isOnlineProvider);
    final problem = _problem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.message != null)
          Text(widget.message!, style: t.body.copyWith(color: context.akn.dim)),
        _ProblemSlot(outcome: problem, onReload: _reload, onRetry: _submit),
        const SizedBox(height: 16),
        AknTextField(
          controller: _note,
          label: widget.noteLabel,
          hint: widget.noteHint,
          minLines: 2,
          maxLines: 5,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 16),
        if (!online)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              ApprovalsCopy.offlineDecision,
              style: t.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        AknButton(
          label: widget.buttonLabel,
          icon: widget.icon,
          expand: true,
          size: AknButtonSize.large,
          loading: _busy,
          onPressed: online && !_busy ? _submit : null,
        ),
      ],
    );
  }
}
