import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/ui.dart';
import '../../features/auth/api.dart';
import '../destinations.dart';
import '../tasks/task_inbox.dart';
import 'more_sheet.dart';
import 'shell_badges.dart';

/// Sekmeli kabuk (spec A.2): `StatefulShellRoute.indexedStack` gövdesi + alt menü.
/// Sekmeler durumunu korur; aynı sekmeye dokunmak köke döner; "Diğer" sayfası kalan hedefleri açar;
/// ortadaki eylem (Sipariş ver / Saha formu) tam ekran sihirbazı açar. Açılışta bir kez isteğe bağlı
/// güncelleme önerisi. Bildirim izni burada değil, uygulamanın ilk açılışında sorulur
/// (`PushCoordinator`).
///
/// Tasarım v3 "Akış": sekme içeriği yönlendiricinin `FadeThroughIndexedStack`'i ile geçer (yeni
/// sekme 0,96 → 1 ölçekle belirir); alt menünün turuncu hapı seçilen sekmeye yaylanarak kayar.
/// "Diğer" sayfası açıkken hap "Diğer"in üzerinde durur, sayfa kapanınca geri döner.
///
/// v4 "Sade" (§3.1): Android'de geri tuşu bir sekme kökünde Ana sayfa'ya döner (hap yaylanarak
/// eve kayar); "Diğer" noktası yalnızca "Diğer"deki sıra sizde işler için yanar (okunmamış
/// bildirimler için asla); Sipariş ver tuşunun ışığı yalnızca ana sayfa sakinken (bekleyen iş
/// yokken) nefes alır. Sekme sayfaları [AknTabScope] içindedir (kök sayfada "Ana sayfa" düğmesi
/// çıkmaz).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
    required this.layout,
  });

  final StatefulNavigationShell navigationShell;
  final NavLayout layout;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// "Diğer" sayfası açık: alt menüde hap "Diğer"in üzerinde.
  bool _moreOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame());
  }

  Future<void> _afterFirstFrame() async {
    if (!mounted) return;
    await maybeShowOptionalUpdate(context, ref);
  }

  void _onSelected(int index) {
    final layout = widget.layout;
    if (index >= layout.bar.length) {
      setState(() => _moreOpen = true);
      showMoreSheet(context, layout.more).whenComplete(() {
        if (mounted) setState(() => _moreOpen = false);
      });
      return;
    }
    final shell = widget.navigationShell;
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  /// Android geri: bir sekme kökünde Ana sayfa'ya (ilk sekmeye) döner.
  void _backToHome() {
    final shell = widget.navigationShell;
    if (shell.currentIndex == 0) return;
    AknHaptics.selection();
    shell.goBranch(0);
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final badges = ref.watch(destinationBadgesProvider);
    final moreHasBadge = layout.more.any(
      (d) => yourMoveDestinations.contains(d.id) && (badges[d.id] ?? 0) > 0,
    );
    final center = layout.center;
    // Tuşun ışığı yalnızca bekleyen iş yokken nefes alır.
    final calm = ref.watch(taskCountProvider) == 0;
    final items = [
      for (final d in layout.bar)
        AknNavItem(
          icon: d.icon,
          selectedIcon: d.selectedIcon,
          label: d.barLabel,
          tooltip: d.label,
          badgeCount: badges[d.id] ?? 0,
          semanticLabel: destinationSemantics(d, badges[d.id] ?? 0),
        ),
      if (layout.hasMore)
        AknNavItem(
          icon: PhosphorIconsRegular.list,
          label: NavLayout.moreLabel,
          showDot: moreHasBadge,
          semanticLabel: moreHasBadge
              ? '${NavLayout.moreLabel}, yeni öğeler var'
              : NavLayout.moreLabel,
        ),
    ];
    final atHome = widget.navigationShell.currentIndex == 0;
    final scaffold = Scaffold(
      body: AknTabScope(child: widget.navigationShell),
      extendBody: false,
      bottomNavigationBar: AnimatedBottomBar(
        items: items,
        currentIndex: _moreOpen && layout.hasMore
            ? layout.bar.length
            : widget.navigationShell.currentIndex,
        onSelected: _onSelected,
        centerAction: center == null
            ? null
            : AknCenterAction(
                icon: center.icon,
                label: center.label,
                breathe: calm,
                onPressed: () => context.push(center.path),
              ),
      ),
    );
    // Sekme kökünde geri: önce Ana sayfa (uygulamadan çıkmaz).
    return PopScope(
      canPop: atHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToHome();
      },
      child: scaffold,
    );
  }
}
