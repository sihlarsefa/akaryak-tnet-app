import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/offline/outbox_op.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/driver_ops.dart';
import '../../copy.dart';
import '../../data/deliver_draft.dart';
import '../../data/driver_models.dart';
import 'op_status.dart';

/// Teslimatlarım kartı: saat bloğu, müşteri ve nokta, durum çipleri; itirazlıysa itiraz notu ve
/// "Teslimatı düzelt"; bekleyen işlem varsa "Gönderilmeyi bekliyor" / "Düzelt"; yarım kalan taslak
/// varsa "Devam et".
class ShipmentCard extends StatelessWidget {
  const ShipmentCard({
    super.key,
    required this.row,
    required this.now,
    required this.onOpen,
    this.ops,
    this.draft,
    this.onCorrect,
    this.onResume,
    this.onFixOp,
    this.history = false,
  });

  final DriverShipmentRow row;
  final DateTime now;
  final VoidCallback onOpen;
  final DriverShipmentOps? ops;
  final DeliverDraft? draft;

  /// İtirazlı teslimatı düzelt.
  final VoidCallback? onCorrect;

  /// Yarım kalan taslağa dön.
  final VoidCallback? onResume;

  /// Sunucunun reddettiği işlemi düzelt.
  final ValueChanged<OutboxOp>? onFixOp;

  /// Geçmiş görünümü (teslim edilen litre ve tarih).
  final bool history;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final op = ops?.primary;
    final overdue = row.isOverdue(now);
    final deliverWaiting = ops?.deliverWaiting ?? false;
    final at = row.scheduledAt;
    final dayLabel = history ? Fmt.date(at) : Fmt.dayLabel(at, now: now);
    final litres = history && row.deliveredLiters != null
        ? '${DriverCopy.delivered} ${Fmt.liters(row.deliveredLiters)}'
        : Fmt.liters(row.plannedLiters);
    final product = row.productName;
    final window = row.windowLabel;

    final summary = [
      row.code,
      ?row.customerTitle,
      ?row.deliveryPointName,
      ?row.placeLine,
      '$dayLabel ${Fmt.time(at)}',
      if (window != null) '${DriverCopy.window} $window',
      [litres, ?product].join(' '),
      row.statusLabel,
      if (overdue) DriverCopy.overdue,
      if (row.isDisputed)
        '${DriverCopy.disputedTitle}: ${row.disputeNote ?? ''}',
      if (op != null && op.status.isWaiting) DriverCopy.opWaiting,
      if (op?.status == OutboxStatus.needsAttention) DriverCopy.opAttention,
    ].join(', ');

    final style = row.status.statusStyle.withLabel(row.statusLabelFromServer);
    final main = Semantics(
      button: true,
      label: summary,
      onTap: onOpen,
      excludeSemantics: true,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TimeBlock(
                time: Fmt.time(at),
                day: dayLabel,
                tone: overdue
                    ? AknTone.danger
                    : row.isInTransit
                    ? AknTone.brand
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.customerTitle ?? row.code,
                      style: t.bodyStrong,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [?row.deliveryPointName, ?row.placeLine].join(' · '),
                      style: t.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusChip.style(style, size: StatusChipSize.small),
                        if (overdue)
                          const StatusChip(
                            label: DriverCopy.overdue,
                            tone: AknTone.danger,
                            icon: Icons.history_toggle_off_rounded,
                            size: StatusChipSize.small,
                          ),
                        _Meta(
                          icon: Icons.local_gas_station_outlined,
                          text: [litres, ?product].join(' · '),
                        ),
                        if (window != null && !history)
                          _Meta(icon: Icons.schedule_rounded, text: window),
                        if (row.vehiclePlate != null)
                          PlateBadge(plate: row.vehiclePlate!, fontSize: 11),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: c.dim,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final extras = <Widget>[
      if (row.isDisputed)
        _DisputeBox(
          note: row.disputeNote,
          onCorrect: deliverWaiting ? null : onCorrect,
        ),
      if (draft != null && !deliverWaiting && onResume != null)
        _DraftRow(draft: draft!, onResume: onResume!),
    ];

    return AknCard(
      padding: EdgeInsets.zero,
      accent: row.isDisputed
          ? AknTone.danger
          : row.isInTransit
          ? AknTone.brand
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          main,
          for (final e in extras) ...[
            Divider(height: 1, thickness: 1, color: c.lineSoft),
            e,
          ],
          if (op != null) _OpRow(op: op, onFix: onFixOp),
        ],
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({required this.time, required this.day, this.tone});

  final String time;
  final String day;
  final AknTone? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final fg = tone == null
        ? c.ink
        : tone == AknTone.brand
        ? c.brandInk
        : c.tone(tone!).fg;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 52),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            time,
            style: t.amount.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          Text(day, style: t.caption),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c.dim),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            text,
            style: context.aknText.caption.copyWith(
              color: c.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _DisputeBox extends StatelessWidget {
  const _DisputeBox({required this.note, this.onCorrect});

  final String? note;
  final VoidCallback? onCorrect;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final tc = c.danger;
    return Container(
      color: tc.bg,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.report_rounded, size: 18, color: tc.fg),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DriverCopy.disputedTitle,
                      style: t.label.copyWith(color: tc.fg),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      note ?? DriverCopy.disputedFallback,
                      style: t.bodySmall.copyWith(color: c.text),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onCorrect != null) ...[
            const SizedBox(height: 10),
            AknButton.secondary(
              label: DriverCopy.actionFix,
              icon: Icons.edit_note_rounded,
              size: AknButtonSize.small,
              expand: true,
              onPressed: onCorrect,
            ),
          ],
        ],
      ),
    );
  }
}

/// Kartın işlem satırı. Tamamlanan işlem yalnızca başarı anında görünür (sonra satır kalkar).
class _OpRow extends StatefulWidget {
  const _OpRow({required this.op, this.onFix});

  final OutboxOp op;
  final ValueChanged<OutboxOp>? onFix;

  @override
  State<_OpRow> createState() => _OpRowState();
}

class _OpRowState extends State<_OpRow> {
  bool _celebrate = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (isFreshlyDone(widget.op)) _start();
  }

  @override
  void didUpdateWidget(_OpRow old) {
    super.didUpdateWidget(old);
    if (widget.op.status == OutboxStatus.done &&
        old.op.status != OutboxStatus.done) {
      _start();
    }
  }

  void _start() {
    _celebrate = true;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _celebrate = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final op = widget.op;
    if (op.status == OutboxStatus.done && !_celebrate) {
      return const SizedBox.shrink();
    }
    final attention = op.status == OutboxStatus.needsAttention;
    final message = attention ? op.lastError : null;
    final t = context.aknText;
    final c = context.akn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, thickness: 1, color: c.lineSoft),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OpStatusChip(op: op),
                    ),
                  ),
                  if (attention && widget.onFix != null)
                    AknButton.ghost(
                      label: DriverCopy.opFix,
                      icon: Icons.edit_rounded,
                      size: AknButtonSize.small,
                      onPressed: () => widget.onFix!(op),
                    ),
                ],
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 6, bottom: 4),
                  child: Text(
                    message,
                    style: t.bodySmall.copyWith(color: c.danger.fg),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({required this.draft, required this.onResume});

  final DeliverDraft draft;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      child: Row(
        children: [
          Icon(Icons.edit_note_rounded, size: 20, color: c.brandInk),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              DriverCopy.resumeDraft,
              style: t.label.copyWith(color: c.brandInk),
            ),
          ),
          AknButton.ghost(
            label: DriverCopy.actionResume,
            size: AknButtonSize.small,
            onPressed: onResume,
          ),
        ],
      ),
    );
  }
}
