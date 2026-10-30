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

/// Teslimatlar kartı (tasarım v3 §4 liste kartı, §7.11 "Sonraki duraklar"): beyaz kart (r20,
/// yumuşak kart gölgesi; koyu temada 1 px çizgi) sayfanın 20 px kenarında yüzer. Güzergâh numarası
/// (32 px yumuşak daire; tamamlananda yeşil onay), müşteri, nokta, sağda litre (tablo rakamları) ve
/// ürün; altında durum lambası ve saat. İtiraz edilmişse müşteri notu (kırmızı kuyu) ve "Teslimatı
/// düzelt"; bekleyen işlem varsa işlem lambası ("Gönderilmeyi bekliyor" / "Düzelt"); yarım kalan
/// taslak varsa "Devam et". Basınca kartın tamamı 0,97'ye küçülür, gölgesi sayfaya oturur ve zemini
/// kuyu rengine döner (yaylı bırakış, seçim titreşimi). Sürücü kipinde en az 76 yüksek.
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

    final indent = number == null ? 0.0 : 48.0;
    final titleStyle = t.headline.copyWith(color: c.ink);
    final amountStyle = t.amount.copyWith(color: c.ink);
    final metaStyle = t.bodySmall.copyWith(color: c.dim);
    final whenStyle = metaStyle.copyWith(fontFeatures: AknNumerals.tabular);
    final minHeight = AknDriverMode.maybeOf(context)?.rowMinHeight ?? 64;

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

    final main = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, extras.isEmpty ? 16 : 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (number != null) ...[
              StopNumber(number: number!, done: _done),
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
                    trailing: Text(when, style: whenStyle),
                  );
                  if (stack) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 2),
                        // Litre sayaç gibi yuvarlanarak gelir (değişince eski rakamdan döner).
                        RollingText(
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
                          maxLines: null,
                          softWrap: true,
                        ),
                        if (sub != null) ...[const SizedBox(height: 2), sub],
                        const SizedBox(height: 10),
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
                          RollingText(
                            TextSpan(text: litres, style: amountStyle),
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
                      const SizedBox(height: 10),
                      status,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    return _StopCardSurface(
      onTap: onOpen,
      semanticLabel: summary,
      main: main,
      extras: [
        for (final e in extras)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(16 + indent, 0, 16, 0),
            child: e,
          ),
      ],
    );
  }
}

/// Şoför satırının lambası: ton, Türkçe etiket, kalın mı.
typedef DriverLamp = ({AknTone tone, String label, bool solid});

/// Güzergâh sırası (tasarım v3): 32 px yumuşak daire içinde numara (800, tablo rakamları; yazıyla
/// en çok 1,3× büyür). Tamamlanan durakta yeşil kuyu ve onay işareti; durum değişince işaret
/// yaylanarak belirir.
class StopNumber extends StatelessWidget {
  const StopNumber({super.key, required this.number, this.done = false});

  final int number;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
    final size = 32 * scale;
    final onCard = AknCardScope.onSurface(context) || !c.isDark;
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: AknMotion.of(context, AknMotion.base),
        curve: AknMotion.standard,
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: done ? c.ok.bg : (onCard ? c.surfaceAlt : c.surfaceRaised),
          shape: BoxShape.circle,
          border: done ? Border.all(color: c.ok.line) : null,
        ),
        child: AnimatedSwitcher(
          duration: AknMotion.of(context, AknMotion.iconSwap),
          switchInCurve: AknMotion.pop,
          transitionBuilder: (child, a) => ScaleTransition(
            scale: a,
            child: FadeTransition(opacity: a, child: child),
          ),
          child: done
              ? Icon(
                  PhosphorIconsBold.check,
                  key: const ValueKey('done'),
                  size: 16 * scale,
                  color: c.ok.fg,
                )
              : Text(
                  '$number',
                  key: const ValueKey('number'),
                  textScaler: TextScaler.noScaling,
                  style: context.aknText.label.copyWith(
                    fontSize: 14 * scale,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    fontFeatures: AknNumerals.tabular,
                    color: c.ink,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Kartın yüzeyi: beyaz, r20, kart gölgesi. Üst bölüm (müşteri, litre, durum) dokunulabilir
/// alandır; basılınca kartın tamamı küçülür, gölge sayfaya oturur, zemin kuyu rengine döner (100 ms
/// içeri, 260 ms yaylı geri). Alt eylemler (düzelt, devam et) kendi düğmeleridir.
class _StopCardSurface extends StatefulWidget {
  const _StopCardSurface({
    required this.onTap,
    required this.semanticLabel,
    required this.main,
    required this.extras,
  });

  final VoidCallback onTap;

  /// Üst bölümün ekran okuyucu metni (tek düğüm: düğme + özet).
  final String semanticLabel;
  final Widget main;
  final List<Widget> extras;

  @override
  State<_StopCardSurface> createState() => _StopCardSurfaceState();
}

class _StopCardSurfaceState extends State<_StopCardSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final reduced = AknMotion.reduced(context);
    final duration = _pressed ? AknMotion.press : AknMotion.pressOut;
    final surface = AnimatedContainer(
      duration: AknMotion.of(context, duration),
      curve: AknMotion.standard,
      decoration: BoxDecoration(
        color: _pressed ? c.surfaceAlt : c.surface,
        borderRadius: AknRadius.card,
        border: c.isDark ? Border.all(color: c.line) : null,
        boxShadow: _pressed ? AknShadows.pressed(c) : AknShadows.card(c),
      ),
      child: ClipRRect(
        borderRadius: AknRadius.card,
        child: AknCardScope(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                button: true,
                label: widget.semanticLabel,
                onTap: widget.onTap,
                excludeSemantics: true,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () {
                      AknHaptics.selection();
                      widget.onTap();
                    },
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    onHighlightChanged: (v) {
                      if (v != _pressed) setState(() => _pressed = v);
                    },
                    child: widget.main,
                  ),
                ),
              ),
              ...widget.extras,
              if (widget.extras.isNotEmpty) const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    return AnimatedScale(
      scale: _pressed && !reduced ? AknMotion.pressScale : 1,
      duration: duration,
      curve: _pressed ? AknMotion.standard : AknMotion.spring,
      child: surface,
    );
  }
}

/// Müşterinin itiraz notu (yumuşak kırmızı kuyu, kırmızı simge + mürekkep yazı) ve "Teslimatı
/// düzelt".
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
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            decoration: BoxDecoration(
              color: c.danger.bg,
              borderRadius: const BorderRadius.all(
                Radius.circular(AknRadius.md),
              ),
              border: Border.all(color: c.danger.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  PhosphorIconsRegular.warningOctagon,
                  size: 20,
                  color: c.danger.fg,
                ),
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
            const SizedBox(height: 10),
            // Doğal genişlikte, 48 dp (sahip 2026-10-30: kart boyu düğme gereksiz büyüktü).
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AknButton.secondary(
                label: DriverCopy.actionFix,
                icon: PhosphorIconsRegular.notePencil,
                onPressed: onCorrect,
              ),
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
    final hidden = op.status == OutboxStatus.done && !_celebrate;
    final attention = op.status == OutboxStatus.needsAttention;
    final message = attention ? op.lastError : null;
    final t = context.aknText;
    final c = context.akn;
    if (hidden) return const SizedBox.shrink();
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
                  icon: PhosphorIconsRegular.pencilSimple,
                  size: AknButtonSize.small,
                  onPressed: () => widget.onFix!(op),
                ),
            ],
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
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
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: AknLamp(
                label: DriverCopy.draftAt(
                  DriverCopy.stepShort[draft.step.index],
                ),
                tone: AknTone.brand,
              ),
            ),
          ),
          const SizedBox(width: 8),
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
