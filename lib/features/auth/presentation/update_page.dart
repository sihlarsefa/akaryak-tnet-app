import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/env/app_config_controller.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../application/server_gate_controller.dart';
import '../data/server_gate.dart';
import 'widgets/server_status.dart';

/// Güncelleme ekranı (`/update`, spec A.4 A1). Varyant rota sorgusundan gelir
/// (`/update?reason=forced|optional|server|maintenance`); verilmezse durumdan çıkarılır: zorunlu
/// güncelleme → "Güncelleme gerekli", bakım → "Bakımdayız", uyumsuz sunucu → "Sunucu güncel değil".
/// Yönlendirici zorunlu güncellemede buraya gönderir; bakım ve sunucu varyantlarını giriş ekranı da
/// kendi içinde gösterir.
class UpdatePage extends ConsumerWidget {
  const UpdatePage({super.key, this.reason});

  final UpdateReason? reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = reason ?? _resolve(ref);
    final gate = resolved == UpdateReason.maintenance
        ? ref.watch(serverGateProvider).valueOrNull
        : null;
    return AppScaffold(
      appBar: false,
      showBell: false,
      body: UpdateGateBody(
        reason: resolved,
        maintenanceMessage: gate?.maintenanceMessage,
        onLater: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(AppRoutes.home);
          }
        },
      ),
    );
  }

  UpdateReason _resolve(WidgetRef ref) {
    final status = ref.watch(updateStatusProvider);
    if (status == UpdateStatus.required) return UpdateReason.forced;
    final gate = ref.watch(serverGateProvider).valueOrNull;
    return switch (gate?.kind) {
      ServerGateKind.maintenance => UpdateReason.maintenance,
      ServerGateKind.outdated => UpdateReason.server,
      _ =>
        status == UpdateStatus.optional
            ? UpdateReason.optional
            : UpdateReason.forced,
    };
  }
}
