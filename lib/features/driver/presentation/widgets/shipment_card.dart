import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/models/models.dart';
import '../../../../core/offline/outbox_op.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/driver_ops.dart';
import '../../copy.dart';
import '../../data/deliver_draft.dart';
import '../../data/driver_models.dart';
import 'op_status.dart';

/// Teslimatlarım satırı (tasarım v2 §6.8 ledger satırı, §7.11 "Sonraki duraklar"): güzergâh
/// numarası (24 px halka), müşteri, nokta, sağda litre ve ürün; altında durum lambası ve saat. İtiraz
/// edilmişse müşteri notu ve "Teslimatı düzelt"; bekleyen işlem varsa işlem lambası ("Gönderilmeyi
/// bekliyor" / "Düzelt"); yarım kalan taslak varsa "Devam et". Kart değil satırdır: tam genişlik,
/// ayırıcı çizgileri liste çizer. Sürücü kipinde en az 76 yüksek.
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
    this.number,
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

  /// Güzergâh sırası (bugünkü duraklar); null ise numara çizilmez.
  final int? number;

  bool get _done =>
      row.status == ShipmentStatus.reported ||
      row.status == ShipmentStatus.accepted;

  /// Satırın durum lambası (şoförün gözünden).
  static DriverLamp lampOf(DriverShipmentRow row, DateTime now) {
    DriverLamp l(AknTone tone, String label, {bool solid = false}) =>
        (tone: tone, label: label, solid: solid);
    if (row.isOverdue(now)) return l(AknTone.danger, DriverCopy.overdue);
    return switch (row.status) {
      ShipmentStatus.planned => l(AknTone.info, row.statusLabel),
      ShipmentStatus.inTransit => l(AknTone.info, row.statusLabel),
      ShipmentStatus.reported => l(AknTone.ok, DriverCopy.reportedLamp),
      ShipmentStatus.accepted => l(
        AknTone.ok,
        DriverCopy.acceptedLamp,
        solid: true,
      ),
      ShipmentStatus.disputed => l(AknTone.danger, DriverCopy.disputedTitle),
      ShipmentStatus.cancelled => l(AknTone.neutral, row.statusLabel),
      ShipmentStatus.unknown => l(AknTone.neutral, row.statusLabel),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final op = ops?.primary;
    final deliverWaiting = ops?.deliverWaiting ?? false;
    final at = row.scheduledAt;
    final window = row.windowLabel;
    final delivered = row.deliveredLiters;
    final showDelivered = (history || _done) && delivered != null;
    final litres = Fmt.liters(showDelivered ? delivered : row.plannedLiters);
    final product = row.productName;
    final day = Fmt.dayLabel(at, now: now);
    final when = history
        ? '${Fmt.date(at)} ${Fmt.time(at)}'
        : [
            day == 'Bugün' ? Fmt.time(at) : '$day ${Fmt.time(at)}',
            ?window,
          ].join(', ');
    final place = [?row.deliveryPointName, ?(row.district ?? row.city)];
    final lamp = lampOf(row, now);
    final rightMeta = showDelivered ? DriverCopy.delivered : product;

    final summary = [
      if (number != null) '$number. durak',
      row.code,
      ?row.customerTitle,
      ...place,
      when,
      if (showDelivered) '${DriverCopy.delivered} $litres' else litres,
      ?product,
      lamp.label,
      if (row.isDisputed) ?row.disputeNote,
      if (op != null && op.status.isWaiting) DriverCopy.opWaiting,
      if (op?.status == OutboxStatus.needsAttention) DriverCopy.opAttention,
    ].join(', ');

    final indent = number == null ? 0.0 : 40.0;
    final titleStyle = t.headline.copyWith(color: c.ink);
    final amountStyle = t.amount.copyWith(color: c.ink);
    final metaStyle = t.bodySmall.copyWith(color: c.dim);
    final minHeight = AknDriverMode.maybeOf(context)?.rowMinHeight ?? 64;

    final main = Semantics(
      button: true,
      label: summary,
      onTap: onOpen,
      excludeSemantics: true,
      child: _Pressable(
        onTap: onOpen,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (number != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: StopNumber(number: number!, done: _done),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final stack =
                          box.maxWidth < 280 ||
                          MediaQuery.textScalerOf(context).scale(10) >= 13;
                      final title = Text(
                        row.customerTitle ?? row.code,
                        style: titleStyle,
                        maxLines: stack ? 4 : 2,
                        overflow: TextOverflow.ellipsis,
                      );
                      final sub = place.isEmpty
                          ? null
                          : Text(place.join(', '), style: metaStyle);
                      final status = AknStatusLine(
                        lamp: AknLamp(
                          label: lamp.label,
                          tone: lamp.tone,
                          solid: lamp.solid,
                        ),
                        trailing: Text(when, style: metaStyle),
                      );
                      if (stack) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            title,
                            const SizedBox(height: 2),
                            Text.rich(
                              TextSpan(
                                text: litres,
                                style: amountStyle,
                                children: [
                                  if (rightMeta != null)
                                    TextSpan(
                                      text: '  $rightMeta',
                                      style: metaStyle,
                                    ),
                                ],
                              ),
                            ),
                            if (sub != null) ...[
                              const SizedBox(height: 2),
                              sub,
                            ],
                            const SizedBox(height: 8),
                            status,
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Expanded(child: title),
                              const SizedBox(width: 12),
                              Text(
                                litres,
                                style: amountStyle,
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ],
                          ),
                          if (sub != null || rightMeta != null) ...[
                            const SizedBox(height: 2),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Expanded(child: sub ?? const SizedBox()),
                                if (rightMeta != null) ...[
                                  const SizedBox(width: 12),
                                  Text(rightMeta, style: metaStyle),
                                ],
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          status,
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
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
      if (op != null) _OpRow(op: op, onFix: onFixOp),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        main,
        for (final e in extras)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(20 + indent, 0, 20, 0),
            child: e,
          ),
        if (extras.isNotEmpty) const SizedBox(height: 6),
      ],
    );
  }
}

/// Şoför satırının lambası: ton, Türkçe etiket, kalın mı.
typedef DriverLamp = ({AknTone tone, String label, bool solid});

/// Güzergâh sırası: 24 px halka içinde numara (Condensed 700). Tamamlanan durakta Beton dolgu ve
/// soluk numara.
class StopNumber extends StatelessWidget {
  const StopNumber({super.key, required this.number, this.done = false});

  final int number;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
    final size = 24 * scale;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: done ? c.surfaceAlt : null,
          shape: BoxShape.circle,
          border: done ? null : Border.all(color: c.ink, width: 1.5),
        ),
        child: Text(
          '$number',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontFamily: AknFonts.condensed,
            fontSize: 13 * scale,
            height: 1,
            fontWeight: FontWeight.w700,
            color: done ? c.dim : c.ink,
          ),
        ),
      ),
    );
  }
}

/// Satırın basılınca Beton zemin alan tıklanabilir alanı (90 ms).
class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        onHighlightChanged: (v) {
          if (v != _pressed) setState(() => _pressed = v);
        },
        child: AnimatedContainer(
          duration: AknMotion.of(
            context,
            _pressed ? AknMotion.press : AknMotion.pressOut,
          ),
          color: _pressed ? c.surfaceAlt : Colors.transparent,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Müşterinin itiraz notu (Beton kuyu, kırmızı simge + mürekkep yazı) ve "Teslimatı düzelt".
class _DisputeBox extends StatelessWidget {
  const _DisputeBox({required this.note, this.onCorrect});

  final String? note;
  final VoidCallback? onCorrect;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: AknRadius.card,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.report_outlined, size: 20, color: c.danger.fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    note ?? DriverCopy.disputedFallback,
                    style: t.bodySmall.copyWith(color: c.ink),
                  ),
                ),
              ],
            ),
          ),
          if (onCorrect != null) ...[
            const SizedBox(height: 8),
            AknButton.secondary(
              label: DriverCopy.actionFix,
              icon: Icons.edit_note_rounded,
              expand: true,
              onPressed: onCorrect,
            ),
          ],
        ],
      ),
    );
  }
}

/// Satırın işlem lambası. Tamamlanan işlem yalnızca başarı anında görünür (sonra kalkar).
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OpStatusChip(op: op),
                ),
              ),
              if (attention && widget.onFix != null)
                AknButton.ghost(
                  label: DriverCopy.opFix,
                  icon: Icons.edit_outlined,
                  size: AknButtonSize.small,
                  onPressed: () => widget.onFix!(op),
                ),
            ],
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(message, style: t.bodySmall.copyWith(color: c.ink)),
            ),
        ],
      ),
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({required this.draft, required this.onResume});

  final DeliverDraft draft;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: AknLamp(
              label: DriverCopy.draftAt(DriverCopy.stepShort[draft.step.index]),
              tone: AknTone.brand,
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
