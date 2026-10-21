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
      SignatureWaiverReason.noRecipient => Icons.local_gas_station_rounded,
      SignatureWaiverReason.refused => Icons.do_not_touch_rounded,
      SignatureWaiverReason.other => Icons.more_horiz_rounded,
    };
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: '${reason.label}, ${reason.description}',
      onTap: onTap,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: AknMotion.of(context, AknMotion.base),
        decoration: BoxDecoration(
          color: selected ? c.brandSoft : c.surface,
          borderRadius: AknRadius.card,
          border: Border.all(
            color: selected ? c.brand : c.line,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AknRadius.card,
            onTap: () {
              AknHaptics.selection();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  AknIconBox(icon: icon, tone: selected ? AknTone.brand : null),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(reason.label, style: t.bodyStrong),
                        const SizedBox(height: 2),
                        Text(reason.description, style: t.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration: AknMotion.of(context, AknMotion.fast),
                    child: Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      key: ValueKey(selected),
                      color: selected ? c.brand : c.dim,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
