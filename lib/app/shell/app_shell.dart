import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/push/push_permission_primer.dart';
import '../../core/ui/ui.dart';
import '../../features/auth/api.dart';
import '../destinations.dart';
import 'more_sheet.dart';
import 'shell_badges.dart';

/// Sekmeli kabuk (spec A.2): `StatefulShellRoute.indexedStack` gövdesi + alt menü.
/// Sekmeler durumunu korur; aynı sekmeye dokunmak köke döner; "Diğer" sayfası kalan hedefleri açar;
/// ortadaki eylem (Sipariş ver / Saha formu) tam ekran sihirbazı açar. Girişten sonra bir kez: bildirim
/// izni ön sayfası (ilk girişte) ya da isteğe bağlı güncelleme önerisi (aynı oturumda ikisi birden
/// gösterilmez).
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame());
  }

  Future<void> _afterFirstFrame() async {
    if (!mounted) return;
    final primerShown = await maybeShowPushPrimer(context, ref);
    if (!mounted || primerShown) return;
    await maybeShowOptionalUpdate(context, ref);
  }

  void _onSelected(int index) {
    final layout = widget.layout;
    if (index >= layout.bar.length) {
      showMoreSheet(context, layout.more);
      return;
    }
    final shell = widget.navigationShell;
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final badges = ref.watch(destinationBadgesProvider);
    final moreHasBadge = layout.more.any((d) => (badges[d.id] ?? 0) > 0);
    final center = layout.center;
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
          icon: Icons.menu_rounded,
          label: NavLayout.moreLabel,
          showDot: moreHasBadge,
          semanticLabel: moreHasBadge
              ? '${NavLayout.moreLabel}, yeni öğeler var'
              : NavLayout.moreLabel,
        ),
    ];
    return Scaffold(
      body: widget.navigationShell,
      extendBody: false,
      bottomNavigationBar: AnimatedBottomBar(
        items: items,
        currentIndex: widget.navigationShell.currentIndex,
        onSelected: _onSelected,
        centerAction: center == null
            ? null
            : AknCenterAction(
                icon: center.icon,
                label: center.label,
                onPressed: () => context.push(center.path),
              ),
      ),
    );
  }
}
