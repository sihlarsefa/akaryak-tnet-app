import 'dart:async';
import 'dart:math' as math;

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

/// Sipariş hattındaki durağın görünüşü (tasarım v3 "Akış").
enum PipelineStopKind {
  /// Sıra izleyende: beyaz halkalı turuncu nokta + nefes alan turuncu hale, sayı Pas, etiket
  /// mürekkep 700.
  yourMove,

  /// Başkasının sırası: içi boş mürekkep halka (boşsa soluk), sayı mürekkep, etiket soluk 600.
  waiting,

  /// Yolda: turuncu yuvarlak içinde tır, hafifçe ilerler.
  vehicle,

  /// Teslim (kabul bekliyor): dolu mürekkep nokta.
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

/// "Sipariş hattı" (tasarım v3 "Akış"): altı durak yumuşak bir hat üzerinde, eşit aralıklı; sayı üstte
/// (`number` 24/30, tablo rakamları), durak hatta, etiket altta. Her durak ≥ 48 × 84 dokunma hedefidir
/// (basınca hafif küçülür, Beton zemin) ve süzülmüş listeyi açar.
///
/// Hareket: ilk görünüşte hat soldan sağa dolar (ucu turuncu ışıyarak akar), duraklar hat ulaştıkça
/// sırayla "pop" ile belirir ve sayılar sıfırdan sayar. Sonra hat canlı kalır: üzerinden ara ara turuncu bir ışık akar, "sıra sizde"
/// durağının halesi nefes alır, yoldaki tır hafifçe ilerler (yalnızca [AknAmbient]; testlerde ve
/// hareket azaltmada durur). Yazı ≥ 1,3× iken ya da çok dar ekranda dikey satır listesine döner (sayı
/// sağda).
class OrderPipeline extends StatefulWidget {
  const OrderPipeline({super.key, required this.stops});

  final List<PipelineStop> stops;

  @override
  State<OrderPipeline> createState() => _OrderPipelineState();
}

class _OrderPipelineState extends State<OrderPipeline>
    with SingleTickerProviderStateMixin {
  // Hattın girişi: çizgi çizilir, duraklar sırayla belirir (bir kez).
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
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
        final vertical = scale >= 1.3 || constraints.maxWidth < 300;
        return Semantics(
          container: true,
          label: 'Sipariş hattı',
          explicitChildNodes: true,
          child: vertical
              ? _VerticalPipeline(stops: stops, flow: _flow)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
                  child: _HorizontalPipeline(stops: stops, flow: _flow),
                ),
        );
      },
    );
  }
}

/// Durağın giriş aralığı: hat ona ulaşınca belirir. (`drive`: dinleyici yalnızca çizilirken bağlanır;
/// her yeniden kurulumda ebeveyne yeni dinleyici eklenmez.)
Animation<double> _appear(Animation<double> flow, int i, int n) {
  final start = n <= 1 ? 0.1 : 0.1 + 0.6 * i / (n - 1);
  return flow.drive(
    CurveTween(
      curve: Interval(start, math.min(1, start + 0.3), curve: AknMotion.pop),
    ),
  );
}

/// Bir durağın girişi: ölçek (fırlayarak) ve opaklık, yeniden kurmadan (dönüşüm katmanı).
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
        child: Transform.scale(scale: 0.4 + 0.6 * v, child: child),
      );
    },
  );
}

class _HorizontalPipeline extends StatelessWidget {
  const _HorizontalPipeline({required this.stops, required this.flow});

  final List<PipelineStop> stops;
  final Animation<double> flow;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final scaler = MediaQuery.textScalerOf(context);
    final countH = scaler.scale(24) * 1.15;
    final labelH = scaler.scale(13) * 18 / 13;
    const markRow = 30.0;
    const gap = 6.0;
    final lineY = countH + gap + markRow / 2;
    final height = countH + gap + markRow + gap + labelH + 10;
    final n = stops.length;
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final step = constraints.maxWidth / n;
          return Stack(
            children: [
              if (n > 1)
                Positioned(
                  left: step / 2,
                  right: step / 2,
                  top: lineY - 2,
                  height: 4,
                  child: _FlowLine(flow: flow),
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
                                      duration: const Duration(
                                        milliseconds: 900,
                                      ),
                                      style: t.number.copyWith(
                                        height: 1.1,
                                        color: _countColor(c, stops[i]),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: gap),
                              SizedBox(
                                height: markRow,
                                child: Center(child: _StopMark(stop: stops[i])),
                              ),
                              const SizedBox(height: gap),
                              SizedBox(
                                height: labelH,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    stops[i].label,
                                    maxLines: 1,
                                    style: t.label.copyWith(
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
          );
        },
      ),
    );
  }
}

/// Sayının rengi: sıra sizdeyse Pas, boşsa soluk, diğerleri mürekkep.
Color _countColor(AknColors c, PipelineStop s) => s.isYourMove
    ? c.brandInk
    : s.count == 0
    ? c.dim
    : c.ink;

/// Dikey hat (yazı ≥ 1,3× ya da dar ekran): her durak bir satır; işaret solda bir omurga üzerinde,
/// sayı sağda. Satırlar hat sırasıyla belirir.
class _VerticalPipeline extends StatelessWidget {
  const _VerticalPipeline({required this.stops, required this.flow});

  final List<PipelineStop> stops;
  final Animation<double> flow;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final n = stops.length;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < n; i++)
            _StopTarget(
              stop: stops[i],
              radius: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 32,
                        child: CustomPaint(
                          painter: _SpinePainter(
                            color: c.lineStrong.withValues(alpha: 0.45),
                            top: i > 0,
                            bottom: i < n - 1,
                          ),
                          child: Center(
                            child: _Appear(
                              animation: _appear(flow, i, n),
                              child: _StopMark(stop: stops[i]),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
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
                                duration: const Duration(milliseconds: 900),
                                style: t.number.copyWith(
                                  color: _countColor(c, stops[i]),
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
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    if (top) canvas.drawLine(Offset(x, 0), Offset(x, mid), p);
    if (bottom) canvas.drawLine(Offset(x, mid), Offset(x, size.height), p);
  }

  @override
  bool shouldRepaint(_SpinePainter old) =>
      old.color != color || old.top != top || old.bottom != bottom;
}

/// Hattın çizgisi: girişte soldan sağa çizilir ([flow]), sonra üzerinden ara ara turuncu bir ışık
/// akar (ortam hareketi, [AknAmbient]).
class _FlowLine extends StatelessWidget {
  const _FlowLine({required this.flow});

  final Animation<double> flow;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return RepaintBoundary(
      child: AknAmbient(
        period: const Duration(milliseconds: 4200),
        curve: Curves.linear,
        builder: (context, t, _) => CustomPaint(
          painter: _FlowPainter(
            flow: flow,
            glint: t,
            track: c.lineStrong.withValues(alpha: c.isDark ? 0.55 : 0.4),
            light: c.brand,
          ),
        ),
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.flow,
    required this.glint,
    required this.track,
    required this.light,
  }) : super(repaint: flow);

  final Animation<double> flow;

  /// Işığın yolculuğu (0–1; ilk %65'inde akar, sonra bekler).
  final double glint;
  final Color track;
  final Color light;

  @override
  void paint(Canvas canvas, Size size) {
    final p = AknMotion.emphasizedCurve.transform(flow.value.clamp(0.0, 1.0));
    if (p <= 0) return;
    final h = size.height;
    final drawn = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width * p, h),
      Radius.circular(h / 2),
    );
    canvas.drawRRect(drawn, Paint()..color = track);
    // Hat dolarken ucu turuncu ışır (akış başı); arkası raya oturur. Hat tamamlanınca söner.
    if (p < 1) {
      const head = 72.0;
      final x = size.width * p;
      final glow = Rect.fromLTWH(
        math.max(0, x - head),
        0,
        math.min(head, x),
        h,
      );
      canvas
        ..save()
        ..clipRRect(drawn)
        ..drawRect(
          glow,
          Paint()
            ..shader = LinearGradient(
              colors: [light.withValues(alpha: 0), light],
            ).createShader(glow),
        )
        ..restore();
    }
    // Akan ışık: yalnızca çizgi tamamlanınca, ortam hareketi açıkken.
    final run = glint / 0.65;
    if (flow.value < 1 || glint <= 0 || run >= 1) return;
    const span = 64.0;
    final x = -span + run * (size.width + span * 2);
    final rect = Rect.fromLTWH(x - span / 2, 0, span, h);
    final fade = math.sin(run * math.pi).clamp(0.0, 1.0);
    canvas
      ..save()
      ..clipRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(h / 2)),
      )
      ..drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              light.withValues(alpha: 0),
              light.withValues(alpha: 0.85 * fade),
              light.withValues(alpha: 0),
            ],
          ).createShader(rect),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_FlowPainter old) =>
      old.glint != glint || old.track != track || old.light != light;
}

/// Durağın dokunma hedefi: tam yükseklik; basınca hafif küçülür (0,94) ve Beton zemin belirir;
/// ekran okuyucuya "Teklif, 6 sipariş, sıra sizde".
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

/// Durak işareti (tasarım v3): sıra sizde (turuncu nokta, beyaz halka, nefes alan turuncu hale),
/// bekliyor (içi boş halka; boşsa soluk), Yolda (turuncu yuvarlak içinde tır, hafifçe ilerler), Teslim
/// (dolu mürekkep nokta). Hat noktaların arkasından geçer; yüzey halkası hattı keser.
class _StopMark extends StatelessWidget {
  const _StopMark({required this.stop});

  final PipelineStop stop;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final has = stop.count > 0;
    switch (stop.kind) {
      case PipelineStopKind.vehicle:
        if (!has) {
          return _Node(
            size: 26,
            fill: c.surfaceAlt,
            ring: c.surface,
            child: Icon(PhosphorIconsRegular.truck, size: 14, color: c.dim),
          );
        }
        final truck = Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c.brandFillStart, c.brandFill],
            ),
            border: Border.all(color: c.surface, width: 2),
            boxShadow: AknShadows.glow(c.brand),
          ),
          child: Icon(PhosphorIconsFill.truck, size: 14, color: c.onBrandFill),
        );
        // Tır yolda: hafifçe ileri geri "sürer".
        return AknAmbient(
          period: AknMotion.breathe,
          reverse: true,
          builder: (context, t, child) => Transform.translate(
            offset: Offset(-1.5 + 3 * t, 0),
            child: child,
          ),
          child: truck,
        );
      case PipelineStopKind.done:
        return _Node(
          size: has ? 14 : 12,
          fill: has ? c.ink : c.surface,
          ring: c.surface,
          border: has ? null : c.lineStrong,
        );
      case PipelineStopKind.yourMove when stop.isYourMove:
        final dot = Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.brand,
            border: Border.all(color: c.surface, width: 3),
            boxShadow: AknShadows.glow(c.brand),
          ),
        );
        // Sıra sizde: turuncu hale nefes alır.
        return SizedBox(
          width: 30,
          height: 30,
          child: AknAmbient(
            period: AknMotion.breathe,
            reverse: true,
            builder: (context, t, child) => Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 24 + 6 * t,
                  height: 24 + 6 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.brand.withValues(alpha: 0.22 - 0.12 * t),
                  ),
                ),
                child!,
              ],
            ),
            child: dot,
          ),
        );
      case PipelineStopKind.yourMove:
      case PipelineStopKind.waiting:
        return _Node(
          size: 14,
          fill: c.surface,
          ring: c.surface,
          border: has ? c.ink : c.lineStrong,
          borderWidth: 2.5,
        );
    }
  }
}

/// Hattın üstünde yuvarlak düğüm: dolgu, isteğe bağlı çerçeve ve hattı kesen yüzey halkası.
class _Node extends StatelessWidget {
  const _Node({
    required this.size,
    required this.fill,
    required this.ring,
    this.border,
    this.borderWidth = 2,
    this.child,
  });

  final double size;
  final Color fill;
  final Color ring;
  final Color? border;
  final double borderWidth;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
    width: size + 6,
    height: size + 6,
    decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
    alignment: Alignment.center,
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: border == null
            ? null
            : Border.all(color: border!, width: borderWidth),
      ),
      child: child,
    ),
  );
}

/// Hattın altındaki acil satır (tasarım v3): süresi en yakın dolan teklif, tonun yumuşak kuyusunda.
/// "Körfez Nakliyat’ın teklif süresi **41 dk** içinde doluyor." + "Teklif ver" (sıra sizdeyse birincil
/// turuncu düğme). Solda yuvarlak içinde saat; sıra sizdeyken halesi nefes alır. Süre yarım dakikada
/// bir güncellenir; 30 dakikanın altında kırmızı kuyu ve dolu saat simgesi.
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
    final tone = urgent
        ? AknTone.danger
        : yours
        ? AknTone.brand
        : AknTone.neutral;
    final tc = c.tone(tone);
    final color = urgent
        ? c.danger.fg
        : yours
        ? c.brandInk
        : c.ink;
    final who = r.customerTitle ?? r.orderNumber;
    // Bölünmez boşluk: "41 dk" iki satıra ayrılmaz.
    final leftText = Fmt.countdown(left).replaceAll(' ', ' ');
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
                    fontWeight: FontWeight.w700,
                    fontFeatures: AknNumerals.tabular,
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
        : AknButton(
            label: widget.actionLabel,
            size: AknButtonSize.small,
            onPressed: widget.onAction,
          );
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final icon = _UrgentIcon(
      icon: urgent ? PhosphorIconsFill.timer : PhosphorIconsRegular.timer,
      tone: tone,
      live: yours || urgent,
    );
    final text = Semantics(
      label: spoken,
      excludeSemantics: true,
      child: sentence,
    );
    return Padding(
      padding: widget.padding,
      child: AnimatedContainer(
        duration: AknMotion.of(context, AknMotion.slow),
        curve: AknMotion.standard,
        padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: tc.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tc.line),
        ),
        child: large || action == null
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          text,
                          if (action != null) ...[
                            const SizedBox(height: 10),
                            action,
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(child: text),
                  const SizedBox(width: 10),
                  action,
                ],
              ),
      ),
    );
  }
}

/// Acil satırın saati: 36 px yuvarlak; canlıyken ([live]) tonun halesi nefes alır.
class _UrgentIcon extends StatelessWidget {
  const _UrgentIcon({
    required this.icon,
    required this.tone,
    required this.live,
  });

  final IconData icon;
  final AknTone tone;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final tc = c.tone(tone);
    final glyph = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.isDark ? tc.line : c.surface,
      ),
      child: Icon(icon, size: 20, color: tc.fg),
    );
    if (!live) return glyph;
    return AknAmbient(
      period: AknMotion.breathe,
      reverse: true,
      builder: (context, t, child) => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: tc.solid.withValues(alpha: 0.28 * t),
              blurRadius: 6 + 8 * t,
              spreadRadius: 1 + 2 * t,
            ),
          ],
        ),
        child: child,
      ),
      child: glyph,
    );
  }
}
