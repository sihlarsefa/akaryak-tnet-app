import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../copy.dart';
import '../../data/driver_models.dart';
import 'entrance.dart';

/// "İmza alınamıyor" neden sayfası (spec A.4 A7): Alıcı yok / tanka teslim, İmzadan imtina, Diğer
/// (+ açıklama, Diğer'de zorunlu). Seçim kaydedilince [SignatureWaiver] döner.
Future<SignatureWaiver?> showWaiverSheet(
  BuildContext context, {
  SignatureWaiver? initial,
}) => showAppSheet<SignatureWaiver>(
  context: context,
  title: DriverCopy.waiverTitle,
  subtitle: DriverCopy.waiverSubtitle,
  builder: (ctx) => WaiverForm(initial: initial),
);

class WaiverForm extends StatefulWidget {
  const WaiverForm({super.key, this.initial});

  final SignatureWaiver? initial;

  @override
  State<WaiverForm> createState() => _WaiverFormState();
}

class _WaiverFormState extends State<WaiverForm> {
  late SignatureWaiverReason? _reason = widget.initial?.reason;
  late final TextEditingController _note = TextEditingController(
    text: widget.initial?.note ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = 'İmza alınamama nedenini seçin.');
      return;
    }
    final w = SignatureWaiver(reason, _note.text.trim());
    if (w.validate() != null) {
      setState(() => _error = DriverCopy.waiverNoteRequired);
      return;
    }
    Navigator.of(context).pop(w);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final other = _reason == SignatureWaiverReason.other;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Nedenler sayfa açılırken sırayla yükselir (v3 §5).
        ...driverStaggered([
          for (final r in SignatureWaiverReason.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ReasonTile(
                reason: r,
                selected: _reason == r,
                onTap: () => setState(() {
                  _reason = r;
                  _error = null;
                }),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        AknTextField(
          controller: _note,
          label: DriverCopy.waiverNoteLabel,
          hint: other
              ? DriverCopy.waiverNoteHintOther
              : DriverCopy.waiverNoteHint,
          requiredMark: other,
          maxLines: 3,
          minLines: 2,
          maxLength: SignatureWaiverReason.noteMaxLength,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        AknAnimatedSize(
          alignment: Alignment.topCenter,
          child: _error == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            PhosphorIconsRegular.warningCircle,
                            size: 18,
                            color: c.danger.fg,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: t.bodySmall.copyWith(
                              color: c.danger.fg,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 16),
        AknButton(
          label: DriverCopy.waiverConfirm,
          icon: PhosphorIconsRegular.check,
          expand: true,
          onPressed: _save,
        ),
      ],
    );
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({
    required this.reason,
    required this.selected,
    required this.onTap,
  });

  final SignatureWaiverReason reason;
  final bool selected;
  final VoidCallback onTap;

  static const BorderRadius _radius = BorderRadius.all(Radius.circular(18));

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final icon = switch (reason) {
      SignatureWaiverReason.noRecipient => PhosphorIconsRegular.gasPump,
      SignatureWaiverReason.refused => PhosphorIconsRegular.handPalm,
      SignatureWaiverReason.other => PhosphorIconsRegular.dotsThree,
    };
    final duration = AknMotion.of(context, AknMotion.base);
    // Seçim kartı (tasarım v3 §4): beyaz, 1 px çizgi, r18; seçilince 2 px turuncu çerçeve, yumuşak
    // turuncu simge kuyusu ve sağda yaylanarak beliren onay.
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: '${reason.label}, ${reason.description}',
      onTap: onTap,
      excludeSemantics: true,
      child: PressScale(
        child: AnimatedContainer(
          duration: duration,
          curve: AknMotion.standard,
          decoration: BoxDecoration(
            color: c.isDark ? c.surfaceRaised : c.surface,
            borderRadius: _radius,
            border: Border.all(
              color: selected ? c.brand : c.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: _radius,
              splashFactory: NoSplash.splashFactory,
              highlightColor: c.ink.withValues(alpha: 0.04),
              onTap: () {
                AknHaptics.selection();
                onTap();
              },
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: context.minTap),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    selected ? 13 : 14,
                    selected ? 13 : 14,
                    selected ? 13 : 14,
                    selected ? 13 : 14,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedContainer(
                        duration: duration,
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: selected ? c.brandSoft : c.surfaceAlt,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(AknRadius.sm),
                          ),
                        ),
                        child: Icon(
                          icon,
                          size: 22,
                          color: selected ? c.brandInk : c.ink,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              reason.label,
                              style: t.bodyStrong.copyWith(
                                color: c.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              reason.description,
                              style: t.bodySmall.copyWith(color: c.dim),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: AnimatedSwitcher(
                          duration: AknMotion.of(context, AknMotion.slow),
                          switchInCurve: AknMotion.pop,
                          switchOutCurve: AknMotion.exit,
                          transitionBuilder: (child, a) =>
                              ScaleTransition(scale: a, child: child),
                          child: selected
                              ? Icon(
                                  PhosphorIconsFill.checkCircle,
                                  key: const ValueKey('on'),
                                  size: 24,
                                  color: c.brand,
                                )
                              : const SizedBox.shrink(key: ValueKey('off')),
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
