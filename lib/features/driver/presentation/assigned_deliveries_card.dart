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
    return Padding(
      padding: margin,
      child: AknCard(
        accent: AknTone.brand,
        padding: EdgeInsets.zero,
        child: AknListTile(
          leadingIcon: Icons.local_shipping_rounded,
          leadingTone: AknTone.brand,
          title: 'Size atanmış $count teslimat',
          subtitle: 'Yola çıkın ve teslim edin: ${DriverCopy.title}',
          semanticLabel: 'Size atanmış $count teslimat, ${DriverCopy.title}',
          onTap: open,
        ),
      ),
    );
  }
}
