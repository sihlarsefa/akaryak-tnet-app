import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/route_plan.dart';
import '../../copy.dart';

/// Tanker yük çubuğu (tasarım v3 §4–5): bugünkü her durak, litresi kadar genişlikte bir bölüm;
/// uçları yuvarlak 8 px hap, bölümler arası 2 px. Sıradaki durak turuncu degrade (hafif sıcak
/// parıltıyla), sonrakiler grafik bağlam grisi, teslim edilenler iz rengi. İlk çizimde çubuk soldan
/// sağa dolar (700 ms, vurgulu eğri); teslim edilen durağın bölümü boşalır (300 ms). Uygulamada
/// sıradaki bölümün üstünden yumuşak bir ışık geçer (ortam hareketi; testlerde ve hareket
/// azaltılınca durur).
class DriverLoadBar extends StatelessWidget {
  const DriverLoadBar({super.key, required this.plan, this.height = 8});

  final DriverRoutePlan plan;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final stops = plan.stops;
    if (stops.isEmpty) return SizedBox(height: height);
    final duration = AknMotion.of(context, AknMotion.loadBarEmpty);
    final r = Radius.circular(height / 2);
    final bar = Row(
      children: [
        for (var i = 0; i < stops.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Expanded(
            flex: (stops[i].liters / 100).round().clamp(1, 1 << 20),
            child: _Segment(
              state: stops[i].state,
              duration: duration,
              radius: BorderRadius.horizontal(
                left: i == 0 ? r : Radius.zero,
                right: i == stops.length - 1 ? r : Radius.zero,
              ),
              colors: c,
            ),
          ),
        ],
      ],
    );
    return Semantics(
      label: DriverCopy.loadSemantics(
        Fmt.liters(plan.remainingLiters),
        plan.total,
      ),
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: AknMotion.of(context, const Duration(milliseconds: 700)),
          curve: AknMotion.emphasizedCurve,
          child: bar,
          // Ağaç hep aynı kalır (bölümler yeniden kurulmaz); dolunca kırpma kalkar.
          builder: (context, v, child) => ClipRRect(
            clipper: _RevealClipper(v),
            clipBehavior: v >= 1 ? Clip.none : Clip.antiAlias,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.state,
    required this.duration,
    required this.radius,
    required this.colors,
  });

  final StopState state;
  final Duration duration;
  final BorderRadius radius;
  final AknColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final current = state == StopState.current;
    final fill = AnimatedContainer(
      duration: duration,
      curve: AknMotion.standard,
      decoration: BoxDecoration(
        // Gece plakanın turuncu tonları kahverengi okunur: bekleyen ve teslim edilen bölümler
        // orada grafit (v4 §9; sıradaki turuncu kalır).
        color: switch (state) {
          StopState.current => c.logo,
          StopState.upcoming => c.plateChartContext,
          StopState.done => c.plateChartTrack,
        },
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: c.logo.withValues(alpha: current && !c.isDark ? 0.35 : 0),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      // Sıradaki durağın turuncu degradesi rengin üstünde; durak değişince söner.
      child: AnimatedOpacity(
        opacity: current ? 1 : 0,
        duration: duration,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(colors: [c.brandFillStart, c.logo]),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    if (!current || !AknMotion.ambientOf(context)) return fill;
    // Sıradaki bölümün üstünden geçen yumuşak ışık (yalnızca ortam hareketi açıkken).
    return AknAmbient(
      period: const Duration(milliseconds: 2600),
      curve: Curves.easeInOutSine,
      child: fill,
      builder: (context, t, child) {
        return Stack(
          fit: StackFit.passthrough,
          children: [
            child!,
            Positioned.fill(
              child: ClipRRect(
                borderRadius: radius,
                child: IgnorePointer(
                  child: FractionallySizedBox(
                    alignment: Alignment(-1.6 + 3.2 * t, 0),
                    widthFactor: 0.4,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0x00FFFFFF),
                            Color(0x73FFFFFF),
                            Color(0x00FFFFFF),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Çubuğu soldan sağa açan kırpma (yeniden yerleşim yok, yalnızca boyama).
class _RevealClipper extends CustomClipper<RRect> {
  const _RevealClipper(this.fraction);

  final double fraction;

  @override
  RRect getClip(Size size) {
    final r = Radius.circular(size.height / 2);
    return RRect.fromLTRBR(
      0,
      0,
      size.width * fraction.clamp(0.0, 1.0),
      size.height,
      r,
    );
  }

  @override
  bool shouldReclip(_RevealClipper old) => old.fraction != fraction;
}
