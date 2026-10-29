import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/auth/access_policy.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../finance/api.dart' show approvalsOfType;
import '../../application/bayi_grants.dart';
import '../../data/home_models.dart';
import '../../data/order_models.dart';
import '../widgets/bayi_widgets.dart' show openDestination;

/// Sipariş hattındaki durağın görünüşü (tasarım v4 "Sade" §5 03).
enum PipelineStopKind {
  /// Sıra izleyende: sayı Pas, dolu 10 dp turuncu boncuk, etiket mürekkep 700.
  yourMove,

  /// Başkasının sırası: sayı mürekkep, içi boş halka, etiket soluk 600.
  waiting,

  /// Yolda: mürekkep tır simgesi (turuncu yok).
  vehicle,

  /// Teslim (kabul bekliyor): içi boş halka.
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

  /// "Finans", "Teklif", "Müşteri", "Plan", "Yolda", "Teslim".
  final String label;
  final int count;
  final PipelineStopKind kind;

  /// Ekran okuyucu için birim: "sipariş".
  final String unit;
  final VoidCallback? onTap;

  bool get isYourMove => kind == PipelineStopKind.yourMove && count > 0;

  /// "Teklif, 6 sipariş, sıra sizde".
  String get semantics =>
      '$label, ${Fmt.integer(count)} $unit${isYourMove ? ', sıra sizde' : ''}';
}

/// "Sıra sizde" durakları rol ön ayarına göre: sahip / müdür Finans, Teklif, Plan; sipariş masası
/// Teklif; finans Finans; sevkiyat / depo Plan.
Set<String> pipelineYourMoves(RolePreset preset) => switch (preset) {
  RolePreset.owner => const {'Finans', 'Teklif', 'Plan'},
  RolePreset.orderDesk => const {'Teklif'},
  RolePreset.finance => const {'Finans'},
  RolePreset.dispatch => const {'Plan'},
  _ => const {},
};

/// Hattın durakları. Sayılar Siparişler sayfasının segment sayılarından gelir ([counts], `GET
/// bayi/orders/counts`): her durak dokununca o segmentin listesini açar ve sayı listeyle aynıdır.
/// Sayılar yoksa (yetki ya da yükleme) ana sayfa yükünün masa ve sevkiyat bölümlerinden; masa
/// bölümü yoksa ilk üç, sevkiyat bölümü yoksa son üç durak düşer.
///
/// [financeMine]: izleyenin Bende'sindeki sipariş finansı talepleri (null = henüz bilinmiyor; rol ön
/// ayarı geçerli). Finans durağı yalnızca bu sayı 0 değilken "sıra sizde"dir: ek bilgi bekleyen
/// sipariş müşterinin sırasıdır, sunucu onu Bende'ye koymaz (v4 tur 2 B5).
List<PipelineStop> pipelineStops(
  BuildContext context,
  BayiHomeData data, {
  required RolePreset preset,
  required BayiGrants grants,
  BayiOrderCounts? counts,
  int? financeMine,
}) {
  final yours = pipelineYourMoves(preset);
  PipelineStopKind kindFor(String label) => yours.contains(label)
      ? PipelineStopKind.yourMove
      : PipelineStopKind.waiting;
  VoidCallback? open(String? route) =>
      route == null ? null : () => openDestination(context, route);
  String? segment(BayiOrderSegment s) =>
      grants.viewOrders ? '${AppRoutes.bayiOrders}?segment=${s.key}' : null;
  final desk = grants.viewDesk
      ? AppRoutes.quoteDesk
      : segment(BayiOrderSegment.awaitingQuote);
  final board = grants.viewBoard
      ? '${AppRoutes.dispatch}?lane=plan'
      : grants.viewShipments
      ? AppRoutes.dispatch
      : null;
  final d = data.desk;
  final s = data.shipments;
  final n = counts;
  final hasDesk = d != null || (n != null && grants.viewOrders);
  final hasShipments = s != null || (n != null && grants.viewOrders);
  // v4 tur 2 (B7): finans durağı izleyenin sırasıysa kararın verildiği yeri açar — Onaylar, Sipariş
  // finansı türüne süzülü (Bende); sıra başkasındaysa finans onayındaki siparişlerin listesini. Durak
  // sayısıyla aynı listeyi açar: tutulan siparişlerden bazıları başkasını bekliyorsa (müşterinin
  // yanıtı) Bende daha az satır gösterirdi; o zaman da liste açılır, izleyeninkiler orada Pas
  // "Finans onayınızı bekliyor" der.
  final financeCount =
      n?.of(BayiOrderSegment.financeHeld) ?? d?.financeHeld ?? 0;
  final financeKind = financeMine == 0
      ? PipelineStopKind.waiting
      : kindFor('Finans');
  final financeYours = financeKind == PipelineStopKind.yourMove;
  final allMine = financeMine == null || financeMine >= financeCount;
  final financeRoute = financeYours && grants.viewApprovals && allMine
      ? approvalsOfType(ApprovalType.orderFinance)
      : segment(BayiOrderSegment.financeHeld) ??
            (grants.viewApprovals
                ? approvalsOfType(ApprovalType.orderFinance)
                : null);
  return [
    if (hasDesk) ...[
      PipelineStop(
        label: 'Finans',
        count: financeCount,
        kind: financeKind,
        unit: 'sipariş',
        onTap: open(financeRoute),
      ),
      PipelineStop(
        label: 'Teklif',
        count: n == null
            ? (d?.openForQuote ?? 0)
            : n.of(BayiOrderSegment.awaitingQuote) +
                  n.of(BayiOrderSegment.revisionRequested),
        kind: kindFor('Teklif'),
        unit: 'sipariş',
        onTap: open(desk),
      ),
      PipelineStop(
        label: 'Müşteri',
        count:
            n?.of(BayiOrderSegment.awaitingCustomer) ??
            d?.awaitingCustomer ??
            0,
        kind: kindFor('Müşteri'),
        unit: 'sipariş, müşteri kararında',
        onTap: open(segment(BayiOrderSegment.awaitingCustomer)),
      ),
    ],
    if (hasShipments) ...[
      PipelineStop(
        label: 'Plan',
        count: n?.of(BayiOrderSegment.toPlan) ?? s?.planned ?? 0,
        kind: kindFor('Plan'),
        unit: 'sipariş, planlanacak',
        onTap: open(board ?? segment(BayiOrderSegment.toPlan)),
      ),
      PipelineStop(
        label: 'Yolda',
        count: n?.of(BayiOrderSegment.inTransit) ?? s?.inTransit ?? 0,
        kind: PipelineStopKind.vehicle,
        unit: 'sipariş, yolda',
        onTap: open(
          segment(BayiOrderSegment.inTransit) ??
              (grants.viewShipments ? AppRoutes.dispatch : null),
        ),
      ),
      PipelineStop(
        label: 'Teslim',
        count: n?.of(BayiOrderSegment.reported) ?? s?.reported ?? 0,
        kind: PipelineStopKind.done,
        unit: 'sipariş, teslim onayı bekliyor',
        onTap: open(
          segment(BayiOrderSegment.reported) ??
              (grants.viewShipments ? AppRoutes.dispatch : null),
        ),
      ),
    ],
  ];
}

/// "Sipariş hattı" (tasarım v4 §5 03): "Sıra sizde" kartının içinde, başlığın altında bir genel
/// bakış. Altı durak eşit aralıklı: sayı üstte (`number` 24/30, tablo rakamları; sıra sizdeyse Pas,
/// sıfırsa soluk "0"), boncuk ince hattın üstünde (sıra sizde: dolu 10 dp turuncu; diğerleri içi boş
/// halka; Yolda: mürekkep tır), etiket altta (12/16). Hale yok, döngü yok: liste yerinde durur.
/// Her durak ≥ 48 dp dokunma hedefidir (basınca hafif küçülür) ve süzülmüş listeyi açar.
///
/// Hareket: ilk görünüşte hat soldan sağa çizilir, boncuklar hat ulaştıkça "pop" ile belirir,
/// sayılar sıfırdan sayar (yalnızca bir kez). Yazı ≥ 1,3× iken ya da çok dar ekranda dikey satır
/// listesine döner (sayı sağda).
class OrderPipeline extends StatefulWidget {
  const OrderPipeline({super.key, required this.stops});

  final List<PipelineStop> stops;

  @override
  State<OrderPipeline> createState() => _OrderPipelineState();
}

class _OrderPipelineState extends State<OrderPipeline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: AknMotion.emphasized,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _flow.value = 1;
    } else {
      _flow.forward();
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stops = widget.stops;
    if (stops.isEmpty) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Duraklar kartın iç boşluğuna 8'er dp taşar: her hedef ≥ 48 dp kalsın; sığmazsa dikey.
        final perStop =
            (constraints.maxWidth + 2 * _HorizontalPipeline.bleed) /
            stops.length;
        final vertical = scale >= 1.3 || perStop < 48;
        return Semantics(
          container: true,
          label: 'Sipariş hattı',
          explicitChildNodes: true,
          child: vertical
              ? _VerticalPipeline(stops: stops, flow: _flow)
              : _HorizontalPipeline(stops: stops, flow: _flow),
        );
      },
    );
  }
}

/// Durağın giriş aralığı: hat ona ulaşınca belirir.
Animation<double> _appear(Animation<double> flow, int i, int n) {
  final start = n <= 1 ? 0.1 : 0.1 + 0.55 * i / (n - 1);
  return flow.drive(
    CurveTween(
      curve: Interval(start, math.min(1, start + 0.35), curve: AknMotion.pop),
    ),
  );
}

/// Bir durağın girişi: ölçek (fırlayarak) ve opaklık.
class _Appear extends StatelessWidget {
  const _Appear({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final v = animation.value;
      if (v >= 1) return child!;
      return Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.6 + 0.4 * v, child: child),
      );
    },
  );
}

/// Sayının rengi: sıra sizdeyse Pas, boşsa soluk, diğerleri mürekkep.
Color _countColor(AknColors c, PipelineStop s) => s.isYourMove
    ? c.brandInk
    : s.count == 0
    ? c.dim
    : c.ink;

class _HorizontalPipeline extends StatelessWidget {
  const _HorizontalPipeline({required this.stops, required this.flow});

  final List<PipelineStop> stops;
  final Animation<double> flow;

  /// Durak hedeflerinin kartın iç boşluğuna taştığı genişlik (her yanda).
  static const double bleed = 8;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final scaler = MediaQuery.textScalerOf(context);
    final countH = scaler.scale(30);
    final labelH = scaler.scale(16);
    const markRow = 16.0;
    const gap = 4.0;
    final lineY = countH + gap + markRow / 2;
    final height = countH + gap + markRow + gap + labelH + 2;
    final n = stops.length;
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth + 2 * bleed;
          final step = width / n;
          return OverflowBox(
            minWidth: width,
            maxWidth: width,
            alignment: Alignment.center,
            child: Stack(
              children: [
                if (n > 1)
                  Positioned(
                    left: step / 2,
                    right: step / 2,
                    top: lineY - 1,
                    height: 2,
                    child: _TrackLine(flow: flow),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: _StopTarget(
                          stop: stops[i],
                          child: _Appear(
                            animation: _appear(flow, i, n),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: countH,
                                  child: Center(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: AnimatedNumber(
                                        value: stops[i].count,
                                        style: t.number.copyWith(
                                          height: 30 / 24,
                                          color: _countColor(c, stops[i]),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: gap),
                                SizedBox(
                                  height: markRow,
                                  child: Center(
                                    child: _StopMark(stop: stops[i]),
                                  ),
                                ),
                                const SizedBox(height: gap),
                                SizedBox(
                                  height: labelH,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      stops[i].label,
                                      maxLines: 1,
                                      style: t.caption.copyWith(
                                        fontWeight: stops[i].isYourMove
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: stops[i].isYourMove
                                            ? c.ink
                                            : c.dim,
                                      ),
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
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Dikey hat (yazı ≥ 1,3× ya da dar ekran): her durak bir satır; işaret solda, sayı sağda.
class _VerticalPipeline extends StatelessWidget {
  const _VerticalPipeline({required this.stops, required this.flow});

  final List<PipelineStop> stops;
  final Animation<double> flow;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final n = stops.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < n; i++)
          _StopTarget(
            stop: stops[i],
            radius: 12,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Center(
                      child: _Appear(
                        animation: _appear(flow, i, n),
                        child: _StopMark(stop: stops[i]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      stops[i].label,
                      style: t.body.copyWith(
                        fontWeight: stops[i].isYourMove
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: stops[i].isYourMove ? c.ink : c.dim,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedNumber(
                    value: stops[i].count,
                    style: t.number.copyWith(color: _countColor(c, stops[i])),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Hattın ince çizgisi: girişte soldan sağa çizilir, sonra durur (döngü yok).
class _TrackLine extends StatelessWidget {
  const _TrackLine({required this.flow});

  final Animation<double> flow;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _TrackPainter(
          flow: flow,
          color: c.lineStrong.withValues(alpha: c.isDark ? 0.6 : 0.45),
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({required this.flow, required this.color})
    : super(repaint: flow);

  final Animation<double> flow;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = AknMotion.emphasizedCurve.transform(flow.value.clamp(0.0, 1.0));
    if (p <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width * p, size.height),
        Radius.circular(size.height / 2),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.color != color;
}

/// Durağın dokunma hedefi: tam yükseklik, ≥ 48 dp; basınca 0,94 ve Beton zemin; ekran okuyucuya
/// "Teklif, 6 sipariş, sıra sizde".
class _StopTarget extends StatefulWidget {
  const _StopTarget({
    required this.stop,
    required this.child,
    this.radius = 14,
  });

  final PipelineStop stop;
  final Widget child;
  final double radius;

  @override
  State<_StopTarget> createState() => _StopTargetState();
}

class _StopTargetState extends State<_StopTarget> {
  bool _pressed = false;

  void _set(bool v) {
    if (v != _pressed) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stop;
    final tap = s.onTap;
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
      child: widget.child,
    );
    final reduced = AknMotion.reduced(context);
    final d = _pressed ? AknMotion.press : AknMotion.pressOut;
    return Semantics(
      label: s.semantics,
      button: tap != null,
      excludeSemantics: true,
      onTap: tap,
      child: tap == null
          ? body
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => _set(true),
              onTapUp: (_) => _set(false),
              onTapCancel: () => _set(false),
              onTap: () {
                AknHaptics.selection();
                tap();
              },
              child: AnimatedScale(
                scale: _pressed && !reduced ? 0.94 : 1,
                duration: d,
                curve: _pressed ? AknMotion.standard : AknMotion.spring,
                child: AnimatedContainer(
                  duration: AknMotion.of(context, d),
                  curve: AknMotion.standard,
                  decoration: BoxDecoration(
                    color: _pressed
                        ? context.akn.surfaceAlt
                        : context.akn.surfaceAlt.withValues(alpha: 0),
                    borderRadius: BorderRadius.circular(widget.radius),
                  ),
                  child: body,
                ),
              ),
            ),
    );
  }
}

/// Durak işareti: sıra sizde (dolu 10 dp turuncu boncuk), diğerleri (içi boş halka; boşsa soluk),
/// Yolda (mürekkep tır, turuncu yok). Hat boncukların arkasından geçer; yüzey halkası hattı keser.
class _StopMark extends StatelessWidget {
  const _StopMark({required this.stop});

  final PipelineStop stop;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final has = stop.count > 0;
    if (stop.kind == PipelineStopKind.vehicle) {
      return Container(
        width: 22,
        height: 16,
        alignment: Alignment.center,
        color: c.surface,
        child: Icon(
          PhosphorIconsRegular.truck,
          size: 16,
          color: has ? c.ink : c.dim,
        ),
      );
    }
    final yours = stop.isYourMove;
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.surface),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: yours ? c.brandFill : c.surface,
          border: yours
              ? null
              : Border.all(color: has ? c.ink : c.lineStrong, width: 2),
        ),
      ),
    );
  }
}
