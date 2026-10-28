import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/ui/ui.dart';
import '../application/driver_lists.dart';
import '../copy.dart';
import '../driver_paths.dart';

/// Kendisi de teslimat yapan bayi personeli (ör. sahibi) için ana sayfa kartı (tasarım v3: beyaz
/// kart, yumuşak turuncu tır kuyusu, basınca küçülür): "Size atanmış 2 teslimat" → Teslimatlarım.
/// Yalnızca şoför olanlarda (sekmeleri zaten var), sevkiyat yetkisi olmayanlarda ya da atanmış açık
/// teslimat yokken hiçbir şey çizmez. Bayi ana sayfası (A4) yerleştirebilir.
class AssignedDeliveriesCard extends ConsumerWidget {
  const AssignedDeliveriesCard({super.key, this.margin = EdgeInsets.zero});

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(accessPolicyProvider);
    if (!policy.isBayi ||
        policy.isDriverOnly ||
        !policy.can(Pg.stationShipments)) {
      return const SizedBox.shrink();
    }
    final count = ref.watch(driverAssignedCountProvider).valueOrNull ?? 0;
    if (count <= 0) return const SizedBox.shrink();
    void open() => unawaited(context.push(DriverPaths.home));
    final c = context.akn;
    final t = context.aknText;
    final title = 'Size atanmış $count teslimat';
    // v3 kart: beyaz, kart gölgesi; yumuşak turuncu kuyuda tır (sıra sizde), basınca küçülür.
    return Padding(
      padding: margin,
      child: Semantics(
        button: true,
        label: '$title, ${DriverCopy.title}',
        onTap: open,
        excludeSemantics: true,
        child: AknCard(
          onTap: open,
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: context.minTap - 24),
            child: Row(
              children: [
                const AknIconBox(
                  icon: PhosphorIconsRegular.truck,
                  tone: AknTone.brand,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: t.bodyStrong.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Yola çıkın ve teslim edin: ${DriverCopy.title}',
                        style: t.bodySmall.copyWith(color: c.dim),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(PhosphorIconsRegular.caretRight, size: 20, color: c.dim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
