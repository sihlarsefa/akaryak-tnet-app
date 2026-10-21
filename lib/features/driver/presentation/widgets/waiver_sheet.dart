import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../copy.dart';
import '../../data/driver_models.dart';

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
        for (final r in SignatureWaiverReason.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ReasonTile(
              reason: r,
              selected: _reason == r,
              onTap: () => setState(() {
                _reason = r;
                _error = null;
              }),
            ),
          ),
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
        if (_error != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: t.bodySmall.copyWith(color: c.danger.fg),
            ),
          ),
        ],
        const SizedBox(height: 16),
        AknButton(
          label: DriverCopy.waiverConfirm,
          icon: Icons.check_rounded,
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

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final icon = switch (reason) {
      SignatureWaiverReason.noRecipient => Icons.local_gas_station_outlined,
      SignatureWaiverReason.refused => Icons.do_not_touch_outlined,
      SignatureWaiverReason.other => Icons.more_horiz_rounded,
    };
    // Seçim kartı (§6.25): beyaz, 1 px çizgi, r12; seçilince 2 px mürekkep çerçeve ve sağ üstte onay.
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: '${reason.label}, ${reason.description}',
      onTap: onTap,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: AknMotion.of(context, AknMotion.fast),
        decoration: BoxDecoration(
          color: c.isDark ? c.surfaceRaised : c.surface,
          borderRadius: AknRadius.card,
          border: Border.all(
            color: selected ? c.ink : c.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AknRadius.card,
            splashFactory: NoSplash.splashFactory,
            highlightColor: c.surfaceAlt,
            onTap: () {
              AknHaptics.selection();
              onTap();
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: context.minTap),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  selected ? 13 : 14,
                  selected ? 13 : 14,
                  selected ? 13 : 14,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 24, color: c.dim),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            reason.label,
                            style: t.bodyStrong.copyWith(color: c.ink),
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
                      width: 22,
                      height: 22,
                      child: selected
                          ? Icon(
                              Icons.check_circle_rounded,
                              size: 22,
                              color: c.ink,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
