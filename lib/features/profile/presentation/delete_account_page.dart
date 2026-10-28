import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/outbox_providers.dart';
import '../../../core/routing/nav_keys.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../application/config_extras.dart';
import '../application/links.dart';
import '../application/logout_flow.dart';
import '../copy.dart';
import '../data/profile_models.dart';
import '../data/profile_repository.dart';
import 'widgets/settings_widgets.dart';

/// Hesabımı sil (spec A.4 A8, B.3 `me/deletion-request`): neler silinir / saklanır, 14 günlük süreç,
/// isteğe bağlı neden, şifreyle yeniden doğrulama → 202 → "Talebiniz alındı" → çıkış.
class DeleteAccountPage extends ConsumerStatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  ConsumerState<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends ConsumerState<DeleteAccountPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _note = TextEditingController();
  String? _reason;
  bool _understood = false;
  bool _showPassword = false;
  bool _confirmError = false;
  String? _passwordError;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _note.dispose();
    super.dispose();
  }

  String? get _reasonText {
    final note = _note.text.trim();
    final parts = [?_reason, if (note.isNotEmpty) note];
    if (parts.isEmpty) return null;
    final s = parts.join(': ');
    return s.length > 1000 ? s.substring(0, 1000) : s;
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _passwordError = null;
      _confirmError = !_understood;
    });
    final valid = _form.currentState?.validate() ?? false;
    if (!valid || !_understood) {
      AknHaptics.warning();
      return;
    }
    final ok = await showConfirmSheet(
      context,
      title: ProfileCopy.deleteConfirmTitle,
      message: ProfileCopy.deleteConfirmMessage,
      confirmLabel: ProfileCopy.deleteButton,
      cancelLabel: ProfileCopy.cancel,
      icon: PhosphorIconsRegular.userMinus,
      destructive: true,
    );
    if (!ok || !mounted) return;
    final AccountDeletionResult result;
    try {
      result = await ref
          .read(profileRepositoryProvider)
          .requestDeletion(password: _password.text, reason: _reasonText);
    } on AppFailure catch (f) {
      if (!mounted) return;
      AknHaptics.warning();
      setState(() {
        if (f is ValidationFailure) {
          _passwordError = f.errorFor('password') ?? f.message;
          _password.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _password.text.length,
          );
        } else {
          _error = f.message;
        }
      });
      return;
    }
    if (!mounted) return;
    // Sunucu hesabı kapattı ve tüm oturumları sonlandırdı: sonuç, oturum kapanırken de görünür
    // kalsın diye kök katmanda gösterilir; "Tamam" ile kapanır (altta giriş ekranı açılmıştır).
    showDeletionResult(context, result);
    await discardUnsentOps(ref);
    await ref
        .read(sessionControllerProvider.notifier)
        .signOut(callServer: false, message: ProfileCopy.accountClosed);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final pending = ref.watch(pendingOpsCountProvider);
    return AppScaffold(
      title: ProfileCopy.deleteTitle,
      showBell: false,
      actionBar: barOf(
        AknButton.danger(
          label: ProfileCopy.deleteButton,
          icon: PhosphorIconsRegular.userMinus,
          expand: true,
          showSuccess: false,
          onPressedAsync: _submit,
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AknSpace.page,
            16,
            AknSpace.page,
            32,
          ),
          children: [
            SettingsReveal(
              index: 0,
              child: Text(ProfileCopy.deleteIntro, style: t.body),
            ),
            // Uyarı bantları yerinde açılır (yapı sabit: alanlar yeniden kurulmaz).
            AknAnimatedSize(
              duration: AknMotion.slow,
              curve: AknMotion.emphasizedCurve,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: AknBanner(tone: AknTone.danger, message: _error!),
                    ),
                  if (pending > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: AknBanner(
                        tone: AknTone.warn,
                        icon: PhosphorIconsRegular.cloudArrowUp,
                        message: ProfileCopy.deletePendingWarning(pending),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SettingsReveal(
              index: 1,
              child: _ListCard(
                title: ProfileCopy.deletedTitle,
                icon: PhosphorIconsRegular.trash,
                tone: AknTone.danger,
                items: ProfileCopy.deletedItems,
              ),
            ),
            const SizedBox(height: 12),
            const SettingsReveal(
              index: 2,
              child: _ListCard(
                title: ProfileCopy.keptTitle,
                icon: PhosphorIconsRegular.archive,
                tone: AknTone.info,
                items: ProfileCopy.keptItems,
                note: ProfileCopy.keptNote,
              ),
            ),
            const SectionHeader(
              title: ProfileCopy.timelineTitle,
              padding: EdgeInsets.fromLTRB(0, 24, 0, 8),
            ),
            const AknCard(
              radius: 20,
              child: StepTimeline(
                steps: [
                  TimelineStep(
                    title: ProfileCopy.timelineToday,
                    subtitle: ProfileCopy.timelineTodayBody,
                    state: TimelineState.warning,
                    icon: PhosphorIconsRegular.lock,
                  ),
                  TimelineStep(
                    title: ProfileCopy.timeline14,
                    subtitle: ProfileCopy.timeline14Body,
                    state: TimelineState.upcoming,
                    icon: PhosphorIconsRegular.hourglassLow,
                  ),
                  TimelineStep(
                    title: ProfileCopy.timelineAfter,
                    subtitle: ProfileCopy.timelineAfterBody,
                    state: TimelineState.upcoming,
                    icon: PhosphorIconsRegular.trash,
                  ),
                ],
              ),
            ),
            const SectionHeader(
              title: ProfileCopy.reasonTitle,
              padding: EdgeInsets.fromLTRB(0, 24, 0, 8),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in ProfileCopy.reasons)
                  _ReasonChip(
                    label: r,
                    selected: _reason == r,
                    onTap: () =>
                        setState(() => _reason = _reason == r ? null : r),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            AknTextField(
              controller: _note,
              label: ProfileCopy.reasonNote,
              maxLines: 3,
              minLines: 1,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 20),
            AknTextField(
              controller: _password,
              label: ProfileCopy.passwordToConfirm,
              requiredMark: true,
              obscureText: !_showPassword,
              errorText: _passwordError,
              onChanged: (_) {
                if (_passwordError != null) {
                  setState(() => _passwordError = null);
                }
              },
              autofillHints: const [AutofillHints.password],
              suffixIcon: IconButton(
                tooltip: _showPassword
                    ? ProfileCopy.hidePassword
                    : ProfileCopy.showPassword,
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword
                      ? PhosphorIconsRegular.eyeSlash
                      : PhosphorIconsRegular.eye,
                ),
              ),
              validator: (v) => v == null || v.isEmpty
                  ? ProfileCopy.passwordToConfirmRequired
                  : null,
            ),
            const SizedBox(height: 12),
            MergeSemantics(
              child: CheckboxListTile(
                value: _understood,
                onChanged: (v) => setState(() {
                  _understood = v ?? false;
                  if (_understood) _confirmError = false;
                }),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(ProfileCopy.confirmUnderstand, style: t.body),
                subtitle: _confirmError
                    ? Text(
                        ProfileCopy.confirmUnderstandRequired,
                        style: t.caption.copyWith(color: c.danger.fg),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => unawaited(_openInfo()),
                icon: const Icon(PhosphorIconsRegular.arrowSquareOut, size: 18),
                label: const Text(ProfileCopy.deletionInfoLink),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openInfo() async {
    final extras = ref.read(configExtrasProvider).valueOrNull;
    final uri =
        SupportUris.web(extras?.accountDeletionUrl) ??
        ref.read(legalUrisProvider).accountDeletion;
    final ok = await ref.read(profileLinkOpenerProvider)(uri);
    if (!ok) AppToast.error(ProfileCopy.linkFailed);
  }
}

/// Neden çipi (tasarım v3): hap biçimli, 40 px görünür (48 dp hedef); dinlenirken beyaz zemin ve ince
/// çizgi, seçilince ink dolgu ve beyaz yazı; onay simgesi küçükten büyüyerek kayar gelir. Basınca içe
/// çöker.
class _ReasonChip extends StatelessWidget {
  const _ReasonChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final duration = AknMotion.of(context, AknMotion.base);
    final fg = selected ? c.onInverse : c.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: PressScale(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            AknHaptics.selection();
            onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AknSpace.minTap),
            child: Center(
              widthFactor: 1,
              child: AnimatedContainer(
                duration: duration,
                curve: AknMotion.standard,
                constraints: const BoxConstraints(minHeight: 40),
                padding: EdgeInsetsDirectional.fromSTEB(
                  selected ? 10 : 14,
                  8,
                  14,
                  8,
                ),
                decoration: BoxDecoration(
                  color: selected ? c.ink : c.surface,
                  borderRadius: AknRadius.pillAll,
                  border: Border.all(color: selected ? c.ink : c.line),
                ),
                child: AknAnimatedSize(
                  duration: duration,
                  alignment: AlignmentDirectional.centerStart,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected) ...[
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: duration,
                          curve: AknMotion.pop,
                          builder: (context, v, child) =>
                              Transform.scale(scale: v, child: child),
                          child: Icon(
                            PhosphorIconsBold.check,
                            size: 16,
                            color: fg,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          style: t.label.copyWith(
                            fontSize: 14,
                            height: 20 / 14,
                            color: fg,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.title,
    required this.icon,
    required this.tone,
    required this.items,
    this.note,
  });

  final String title;
  final IconData icon;
  final AknTone tone;
  final List<String> items;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return AknCard(
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SettingsIconTile(icon: icon, tone: tone),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: t.bodyStrong),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 12, left: 14),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: c.tone(tone).fg,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(child: Text(item, style: t.body)),
                ],
              ),
            ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note!, style: t.bodySmall),
          ],
        ],
      ),
    );
  }
}

OverlayEntry? _resultEntry;

/// "Talebiniz alındı" sonucunu kök katmanda gösterir: oturum kapanıp giriş ekranı açılırken de görünür
/// kalır; "Tamam" ile kapanır.
void showDeletionResult(BuildContext context, AccountDeletionResult result) {
  final overlay =
      Overlay.maybeOf(context, rootOverlay: true) ??
      rootNavigatorKey.currentState?.overlay;
  if (overlay == null) return;
  _resultEntry?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => DeletionResultView(
      result: result,
      onDone: () {
        if (identical(_resultEntry, entry)) _resultEntry = null;
        entry.remove();
      },
    ),
  );
  _resultEntry = entry;
  overlay.insert(entry);
}

/// "Talebiniz alındı" ekranı (tam ekran).
class DeletionResultView extends StatelessWidget {
  const DeletionResultView({
    super.key,
    required this.result,
    required this.onDone,
  });

  final AccountDeletionResult result;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final id = result.requestId;
    final at = result.scheduledFor;
    return BlockSemantics(
      child: Material(
        color: c.bg,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ResultView(
                  title: ProfileCopy.deleteDoneTitle,
                  message: result.message.isEmpty
                      ? ProfileCopy.deleteDoneDefault
                      : result.message,
                  details: id == null && at == null
                      ? null
                      : AknCard(
                          child: Column(
                            children: [
                              if (id != null)
                                FactRow(
                                  label: ProfileCopy.requestIdLabel,
                                  value: id,
                                ),
                              if (at != null)
                                FactRow(
                                  label: ProfileCopy.scheduledLabel,
                                  value: Fmt.date(at),
                                ),
                            ],
                          ),
                        ),
                  primaryLabel: ProfileCopy.deleteDoneButton,
                  onPrimary: onDone,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
