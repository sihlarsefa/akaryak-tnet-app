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

/// Kendisi de teslimat yapan bayi personeli (ör. sahibi) için ana sayfa kartı: "Size atanmış 2 teslimat"
/// → Teslimatlarım. Yalnızca şoför olanlarda (sekmeleri zaten var), sevkiyat yetkisi olmayanlarda ya da
/// atanmış açık teslimat yokken hiçbir şey çizmez. Bayi ana sayfası (A4) yerleştirebilir.
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
    // Beton kuyu (§4.5): bir çağrı, kart değil; dokununca Teslimatlarım.
    return Padding(
      padding: margin,
      child: Semantics(
        button: true,
        label: '$title, ${DriverCopy.title}',
        onTap: open,
        excludeSemantics: true,
        child: Material(
          color: c.surfaceAlt,
          shape: const RoundedRectangleBorder(borderRadius: AknRadius.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: open,
            splashFactory: NoSplash.splashFactory,
            highlightColor: c.line,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: context.minTap),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Row(
                  children: [
                    Icon(Icons.local_shipping_outlined, size: 24, color: c.ink),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: t.bodyStrong.copyWith(color: c.ink),
                          ),
                          Text(
                            'Yola çıkın ve teslim edin: ${DriverCopy.title}',
                            style: t.bodySmall.copyWith(color: c.dim),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 22, color: c.ink),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
