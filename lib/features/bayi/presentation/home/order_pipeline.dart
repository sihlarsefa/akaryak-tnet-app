import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/auth/access_policy.dart';
import '../../../../core/models/models.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/bayi_grants.dart';
import '../../data/home_models.dart';
import '../widgets/bayi_widgets.dart' show openDestination;
import 'home_atoms.dart';

/// Sipariş hattındaki durağın görünüşü (tasarım v2 §6.17).
enum PipelineStopKind {
  /// Sıra izleyende: 7 px turuncu nokta + hale, sayı Pas, etiket mürekkep 600.
  yourMove,

  /// Başkasının sırası: 6 px içi boş mürekkep halka, sayı mürekkep, etiket soluk 500.
  waiting,

  /// Yolda: 24 px marka karesi (» araç).
  vehicle,

  /// Teslim (kabul bekliyor): 7 px dolu mürekkep nokta.
  done,
}

/// Hattın bir durağı: sayı, etiket ve dokununca açılan süzülmüş liste.
@immutable
class PipelineStop {
  const PipelineStop({
    required this.label,
    required this.count,
    required this.kind,
    required this.unit,
    this.onTap,
  });

  /// "Finans", "Teklif", "Karar", "Plan", "Yolda", "Teslim".
  final String label;
  final int count;
  final PipelineStopKind kind;

  /// Ekran okuyucu için birim: "sipariş", "sevkiyat".
  final String unit;
  final VoidCallback? onTap;

  bool get isYourMove => kind == PipelineStopKind.yourMove && count > 0;

  /// "Teklif, 6 sipariş, sıra sizde".
  String get semantics =>
      '$label, ${Fmt.integer(count)} $unit${isYourMove ? ', sıra sizde' : ''}';
}

/// "Sıra sizde" durakları rol ön ayarına göre (§6.17): sahip / müdür Finans, Teklif, Plan; sipariş
/// masası Teklif; finans Finans; sevkiyat / depo Plan.
Set<String> pipelineYourMoves(RolePreset preset) => switch (preset) {
  RolePreset.owner => const {'Finans', 'Teklif', 'Plan'},
  RolePreset.orderDesk => const {'Teklif'},
  RolePreset.finance => const {'Finans'},
  RolePreset.dispatch => const {'Plan'},
  _ => const {},
};

/// Ana sayfa yükünden hattın durakları. Sayısı gelmeyen durak gösterilmez (masa bölümü yoksa ilk üç,
/// sevkiyat bölümü yoksa son üç durak düşer).
List<PipelineStop> pipelineStops(
  BuildContext context,
  BayiHomeData data, {
  required RolePreset preset,
  required BayiGrants grants,
}) {
  final yours = pipelineYourMoves(preset);
  PipelineStopKind kindFor(String label) => yours.contains(label)
      ? PipelineStopKind.yourMove
      : PipelineStopKind.waiting;
  VoidCallback? open(String? route) =>
      route == null ? null : () => openDestination(context, route);
  final orders = grants.viewOrders ? AppRoutes.bayiOrders : null;
  final desk = grants.viewDesk ? AppRoutes.quoteDesk : orders;
  final finance = grants.viewApprovals ? AppRoutes.approvals : desk;
  final board = grants.viewShipments ? AppRoutes.dispatch : null;
  final d = data.desk;
  final s = data.shipments;
  return [
    if (d != null) ...[
      PipelineStop(
        label: 'Finans',
        count: d.financeHeld,
        kind: kindFor('Finans'),
        unit: 'sipariş',
        onTap: open(finance),
      ),
      PipelineStop(
        label: 'Teklif',
        count: d.awaitingQuote + d.revisionRequested,
        kind: kindFor('Teklif'),
        unit: 'sipariş',
        onTap: open(desk),
      ),
      PipelineStop(
        label: 'Karar',
        count: d.awaitingCustomer,
        kind: kindFor('Karar'),
        unit: 'sipariş',
        onTap: open(orders),
      ),
    ],
    if (s != null) ...[
      PipelineStop(
        label: 'Plan',
        count: s.planned,
        kind: kindFor('Plan'),
        unit: 'sevkiyat',
        onTap: open(board),
      ),
      PipelineStop(
        label: 'Yolda',
        count: s.inTransit,
        kind: PipelineStopKind.vehicle,
        unit: 'sevkiyat',
        onTap: open(board),
      ),
      PipelineStop(
        label: 'Teslim',
        count: s.reported,
        kind: PipelineStopKind.done,
        unit: 'sevkiyat, kabul bekliyor',
        onTap: open(board),
      ),
    ],
  ];
}

/// "Sipariş hattı" (§6.17): altı durak tek bir 2 px mürekkep çizgide, eşit aralıklı; sayı üstte
/// (Condensed 24), durak çizgide, etiket altta. Her durak ≥ 48 × 84 dokunma hedefidir ve süzülmüş
/// listeyi açar. Dar ekranda (< 340) ya da yazı ≥ 1,3× iken dikey satır listesine döner (sayı sağda).
class OrderPipeline extends StatelessWidget {
  const OrderPipeline({super.key, required this.stops});

  final List<PipelineStop> stops;

  @override
  Widget build(BuildContext context) {
    if (stops.isEmpty) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    return LayoutBuilder(
      builder: (context, constraints) {
        final vertical = scale >= 1.3 || constraints.maxWidth < 340;
        return Semantics(
          container: true,
          label: 'Sipariş hattı',
          explicitChildNodes: true,
          child: vertical
              ? _VerticalPipeline(stops: stops)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: _HorizontalPipeline(stops: stops),
                ),
        );
      },
    );
  }
}

class _HorizontalPipeline extends StatelessWidget {
  const _HorizontalPipeline({required this.stops});

  final List<PipelineStop> stops;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final scaler = MediaQuery.textScalerOf(context);
    final countH = scaler.scale(24);
    final labelH = scaler.scale(13) * 18 / 13;
    const markRow = 24.0;
    const gap = 6.0;
    final lineY = countH + gap + markRow / 2;
    final height = countH + gap + markRow + gap + labelH + 6;
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final step = constraints.maxWidth / stops.length;
          return Stack(
            children: [
              if (stops.length > 1)
                Positioned(
                  left: step / 2,
                  right: step / 2,
                  top: lineY - 1,
                  height: 2,
                  child: ColoredBox(color: c.ink),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in stops)
                    Expanded(
                      child: _StopTarget(
                        stop: s,
                        child: Column(
                          children: [
                            SizedBox(
                              height: countH,
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    Fmt.integer(s.count),
                                    maxLines: 1,
                                    style: t.number.copyWith(
                                      height: 1,
                                      color: s.isYourMove ? c.brandInk : c.ink,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: gap),
                            SizedBox(
                              height: markRow,
                              child: Center(child: _StopMark(stop: s)),
                            ),
                            const SizedBox(height: gap),
                            SizedBox(
                              height: labelH,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  s.label,
                                  maxLines: 1,
                                  style: t.label.copyWith(
                                    fontWeight: s.isYourMove
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: s.isYourMove ? c.ink : c.dim,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Dikey hat (yazı ≥ 1,3× ya da dar ekran): her durak bir satır; işaret solda, sayı sağda.
class _VerticalPipeline extends StatelessWidget {
  const _VerticalPipeline({required this.stops});

  final List<PipelineStop> stops;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < stops.length; i++)
            _StopTarget(
              stop: stops[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 28,
                        child: CustomPaint(
                          painter: _SpinePainter(
                            color: c.ink,
                            top: i > 0,
                            bottom: i < stops.length - 1,
                          ),
                          child: Center(child: _StopMark(stop: stops[i])),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  stops[i].label,
                                  style: t.body.copyWith(
                                    fontWeight: stops[i].isYourMove
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: stops[i].isYourMove ? c.ink : c.dim,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                Fmt.integer(stops[i].count),
                                style: t.number.copyWith(
                                  color: stops[i].isYourMove
                                      ? c.brandInk
                                      : c.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SpinePainter extends CustomPainter {
  const _SpinePainter({
    required this.color,
    required this.top,
    required this.bottom,
  });

  final Color color;
  final bool top;
  final bool bottom;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final mid = size.height / 2;
    final p = Paint()
      ..color = color
      ..strokeWidth = 2;
    if (top) canvas.drawLine(Offset(x, 0), Offset(x, mid), p);
    if (bottom) canvas.drawLine(Offset(x, mid), Offset(x, size.height), p);
  }

  @override
  bool shouldRepaint(_SpinePainter old) =>
      old.color != color || old.top != top || old.bottom != bottom;
}

/// Durağın dokunma hedefi: tam yükseklik, basınca Beton; ekran okuyucuya "Teklif, 6 sipariş, sıra
/// sizde".
class _StopTarget extends StatefulWidget {
  const _StopTarget({required this.stop, required this.child});

  final PipelineStop stop;
  final Widget child;

  @override
  State<_StopTarget> createState() => _StopTargetState();
}

class _StopTargetState extends State<_StopTarget> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.stop;
    final tap = s.onTap;
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
      child: widget.child,
    );
    return Semantics(
      label: s.semantics,
      button: tap != null,
      excludeSemantics: true,
      onTap: tap,
      child: tap == null
          ? body
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: () {
                AknHaptics.selection();
                tap();
              },
              child: AnimatedOpacity(
                opacity: _pressed ? 0.6 : 1,
                duration: AknMotion.of(
                  context,
                  _pressed ? AknMotion.press : AknMotion.pressOut,
                ),
                child: body,
              ),
            ),
    );
  }
}

/// Durak işareti: sıra sizde (turuncu nokta + hale), bekliyor (içi boş halka), Yolda (» kare),
/// Teslim (dolu nokta).
class _StopMark extends StatelessWidget {
  const _StopMark({required this.stop});

  final PipelineStop stop;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    switch (stop.kind) {
      case PipelineStopKind.vehicle:
        return const LogoMark(size: 24, semanticLabel: null);
      case PipelineStopKind.done:
        return _Dot(size: 14, color: c.ink);
      case PipelineStopKind.yourMove when stop.isYourMove:
        // Hale: tahtadaki gibi %20 turuncu, sayfa rengi üstünde (koyu temada koyu kahve).
        final halo = Color.alphaBlend(c.logo.withValues(alpha: 0.2), c.bg);
        return SizedBox(
          width: 26,
          height: 26,
          child: CustomPaint(
            painter: _HaloPainter(dot: c.logo, halo: halo),
          ),
        );
      case PipelineStopKind.yourMove:
      case PipelineStopKind.waiting:
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: c.bg,
            shape: BoxShape.circle,
            border: Border.all(color: c.ink, width: 2),
          ),
        );
    }
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _HaloPainter extends CustomPainter {
  const _HaloPainter({required this.dot, required this.halo});

  final Color dot;
  final Color halo;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas
      ..drawCircle(
        center,
        11,
        Paint()
          ..color = halo
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      )
      ..drawCircle(center, 7, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.dot != dot || old.halo != halo;
}

/// Hattın altındaki acil satır (§6.17): süresi en yakın dolan teklif. "Körfez Nakliyat’ın teklif
/// süresi **41 dk** içinde doluyor." + küçük ikincil "Teklif ver". Süre dakikada bir güncellenir; 30
/// dakikanın altında kırmızı ve dolu saat simgesi.
class PipelineUrgentLine extends StatefulWidget {
  const PipelineUrgentLine({
    super.key,
    required this.row,
    this.onAction,
    this.actionLabel = 'Teklif ver',
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 0),
  });

  final DashboardOrderRow row;
  final VoidCallback? onAction;
  final String actionLabel;
  final EdgeInsetsGeometry padding;

  /// Masadaki süresi en yakın dolacak teklif (yoksa null).
  static DashboardOrderRow? mostUrgent(BayiDeskSection? desk) {
    if (desk == null || !desk.expiryEnabled) return null;
    if ((desk.expiringSoon ?? 0) <= 0) return null;
    final rows = [
      ...desk.expiring,
      ...desk.awaitingQuoteList,
    ].where((r) => r.msLeft > 0).toList();
    if (rows.isEmpty) return null;
    rows.sort((a, b) => a.remaining().compareTo(b.remaining()));
    return rows.first;
  }

  @override
  State<PipelineUrgentLine> createState() => _PipelineUrgentLineState();
}

class _PipelineUrgentLineState extends State<PipelineUrgentLine> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final r = widget.row;
    final left = r.remaining();
    final urgent = left.inMinutes < 30;
    // Pas yalnızca "sıra sizde" demektir: teklif veremeyen (salt okunur) için mürekkep.
    final yours = widget.onAction != null;
    final color = urgent
        ? c.danger.fg
        : yours
        ? c.brandInk
        : c.ink;
    final who = r.customerTitle ?? r.orderNumber;
    // Bölünmez boşluk: "41 dk" iki satıra ayrılmaz.
    final leftText = Fmt.countdown(left).replaceAll(' ', '\u00A0');
    final expired = left <= Duration.zero;
    final base = t.bodySmall.copyWith(color: c.ink);
    final sentence = Text.rich(
      expired
          ? TextSpan(text: '${trGenitive(who)} teklif süresi doldu.')
          : TextSpan(
              children: [
                TextSpan(text: '${trGenitive(who)} teklif süresi '),
                TextSpan(
                  text: leftText,
                  style: base.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const TextSpan(text: ' içinde doluyor.'),
              ],
            ),
      style: base,
    );
    final deadline = TrTime.wall(TrTime.now().add(left));
    final spoken = expired
        ? '${trGenitive(who)} teklif süresi doldu'
        : '${trGenitive(who)} teklif süresi ${left.inHours > 0 ? '${left.inHours} saat ' : ''}${left.inMinutes % 60} dakika içinde, saat ${deadline.hour.toString().padLeft(2, '0')}:${deadline.minute.toString().padLeft(2, '0')}’de doluyor';
    final action = widget.onAction == null
        ? null
        : AknButton.secondary(
            label: widget.actionLabel,
            size: AknButtonSize.small,
            onPressed: widget.onAction,
          );
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final icon = Icon(
      urgent ? Icons.timer_rounded : Icons.timer_outlined,
      size: 20,
      color: color,
    );
    final text = Semantics(
      label: spoken,
      excludeSemantics: true,
      child: sentence,
    );
    return Padding(
      padding: widget.padding,
      child: large || action == null
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 1), child: icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      text,
                      if (action != null) ...[
                        const SizedBox(height: 8),
                        action,
                      ],
                    ],
                  ),
                ),
              ],
            )
          : Row(
              children: [
                icon,
                const SizedBox(width: 12),
                Expanded(child: text),
                const SizedBox(width: 12),
                action,
              ],
            ),
    );
  }
}
