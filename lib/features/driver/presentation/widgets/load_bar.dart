import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/route_plan.dart';
import '../../copy.dart';

/// Tanker yük çubuğu (tahta ekran 6): bugünkü her durak, litresi kadar genişlikte bir bölüm. Sıradaki
/// durak logo turuncusu, sonrakiler grafik bağlam grisi; teslim edilen durağın bölümü boşalır
/// (300 ms, iz rengine döner). 8 px yüksek, uçları yuvarlak, bölümler arası 2 px.
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
    return Semantics(
      label: DriverCopy.loadSemantics(
        Fmt.liters(plan.remainingLiters),
        plan.total,
      ),
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (var i = 0; i < stops.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: (stops[i].liters / 100).round().clamp(1, 1 << 20),
                child: AnimatedContainer(
                  duration: duration,
                  curve: AknMotion.standard,
                  decoration: BoxDecoration(
                    color: switch (stops[i].state) {
                      StopState.current => c.logo,
                      StopState.upcoming => c.chartContext,
                      StopState.done => c.chartTrack,
                    },
                    borderRadius: BorderRadius.horizontal(
                      left: i == 0 ? r : Radius.zero,
                      right: i == stops.length - 1 ? r : Radius.zero,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
