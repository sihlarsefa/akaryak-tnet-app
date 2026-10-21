import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../driver_mode.dart';
import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import 'buttons.dart';

/// One destination of the [AnimatedBottomBar].
@immutable
class AknNavItem {
  const AknNavItem({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.badgeCount = 0,
    this.showDot = false,
    this.semanticLabel,
    this.tooltip,
  });

  /// At rest: the outlined icon (`*_outlined`).
  final IconData icon;

  /// Active: the filled icon (`*_rounded`).
  final IconData? selectedIcon;

  /// Short bar label (≤ 10 characters).
  final String label;

  /// Count badge (Onaylarım). 0 hides it.
  final int badgeCount;

  /// Small dot without a number ("Diğer" when a hidden item has a badge).
  final bool showDot;

  /// Full screen-reader label including the badge ("Onaylarım, 3 bekleyen").
  /// Used as is; without it the bar reads "[label], N yeni".
  final String? semanticLabel;

  /// Full name shown on long-press when the bar label is shortened
  /// ("Teklif masası" for "Teklifler").
  final String? tooltip;
}

/// The key in the bar ("Sipariş ver", "Saha formu").
@immutable
class AknCenterAction {
  const AknCenterAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

/// Bottom navigation (design v2 §6.4): docked, full width, 56 + safe area,
/// `surfaceRaised` (dark: `surface`) with a 1 px hairline on top — no
/// shadow, no floating pill, no bulging centre button.
///
/// * Items share the width; a 30 px icon box (icon 24) keeps every label on
///   one baseline; labels `navLabel` 11/14, clamped at 1.2× (long-press
///   shows the full name).
/// * Active: the filled icon, an ink label 600 and the **needle** — a
///   22 × 3 logo-orange mark on the bar's top edge that slides between items
///   ([AknMotion.needle], spring; instant under reduce motion). Inactive:
///   the outlined icon and label in `navInactive`.
/// * [centerAction] ("Sipariş ver"): a 48 × 30 r10 orange-gradient key with a
///   white icon in the icon box, its label in ink 600 — an item like the
///   others.
/// * Badges: Asfalt count pills (§6.3) or a logo dot.
/// * Driver mode: item height 64, icon 26, label 12/15.
/// * [currentIndex] may be -1 (nothing selected).
class AnimatedBottomBar extends StatelessWidget {
  const AnimatedBottomBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelected,
    this.centerAction,
  });

  final List<AknNavItem> items;
  final int currentIndex;

  /// Also called for the already selected tab (the shell may pop to root).
  final ValueChanged<int> onSelected;
  final AknCenterAction? centerAction;

  /// Height above the safe area (56; driver mode 64).
  static const double barHeight = 56;
  static const double _maxWidth = 640;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final driver = context.driverMode;
    final fill = c.isDark ? c.surface : c.surfaceRaised;
    final center = centerAction;
    final slots = items.length + (center == null ? 0 : 1);
    final centerSlot = center == null ? -1 : (items.length / 2).ceil();
    int slotOf(int itemIndex) =>
        center == null || itemIndex < centerSlot ? itemIndex : itemIndex + 1;
    int itemAt(int slot) =>
        center == null || slot < centerSlot ? slot : slot - 1;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final itemHeight = driver?.navItemHeight ?? barHeight;
    final selectedSlot = currentIndex >= 0 && currentIndex < items.length
        ? slotOf(currentIndex)
        : -1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Kenardan kenara: alttaki sistem gezinme çubuğu simgeleri çubuğa göre.
      value: AknTheme.overlayFor(c.brightness),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.2,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            border: Border(top: BorderSide(color: c.line)),
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: safeBottom),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxWidth),
                child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  // 6 px side padding (board): the outer items do not sit on
                  // the screen edge.
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final slotWidth = width / math.max(slots, 1);
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: itemHeight,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var s = 0; s < slots; s++)
                                    Expanded(
                                      child: s == centerSlot
                                          ? _NavKey(
                                              action: center!,
                                              height: itemHeight,
                                              iconSize:
                                                  driver?.navIconSize ?? 24,
                                            )
                                          : _NavButton(
                                              item: items[itemAt(s)],
                                              selected: s == selectedSlot,
                                              height: itemHeight,
                                              iconSize:
                                                  driver?.navIconSize ?? 24,
                                              ring: fill,
                                              onTap: () {
                                                final i = itemAt(s);
                                                if (i != currentIndex) {
                                                  AknHaptics.selection();
                                                }
                                                onSelected(i);
                                              },
                                            ),
                                    ),
                                ],
                              ),
                            ),
                            if (selectedSlot >= 0)
                              AnimatedPositioned(
                                duration: AknMotion.of(
                                  context,
                                  AknMotion.needle,
                                ),
                                curve: AknMotion.spring,
                                left:
                                    slotWidth * selectedSlot +
                                    slotWidth / 2 -
                                    11,
                                top: -1,
                                width: 22,
                                height: 3,
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: c.logo,
                                      borderRadius: const BorderRadius.vertical(
                                        bottom: Radius.circular(2),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.height,
    required this.iconSize,
    required this.ring,
    required this.onTap,
  });

  final AknNavItem item;
  final bool selected;
  final double height;
  final double iconSize;
  final Color ring;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final color = selected ? c.ink : c.navInactive;
    final badge = item.badgeCount;
    final semantic =
        item.semanticLabel ??
        (badge > 0
            ? '${item.label}, $badge yeni'
            : item.showDot
            ? '${item.label}, yeni öğe var'
            : item.label);
    final tooltip = item.tooltip ?? item.label;
    final Widget button = InkResponse(
      onTap: onTap,
      containedInkWell: true,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Padding(
          padding: const EdgeInsets.only(top: 9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: iconSize + 6,
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        selected ? (item.selectedIcon ?? item.icon) : item.icon,
                        size: iconSize,
                        color: color,
                      ),
                      if (badge > 0 || item.showDot)
                        Positioned(
                          right: badge > 0 ? -12 : -4,
                          top: badge > 0 ? -5 : -2,
                          child: AknCountBadge(
                            count: badge,
                            dot: badge <= 0 && item.showDot,
                            ringColor: ring,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 3),
              // A long label (large text) shrinks to its slot instead of
              // touching the neighbour or ending in "…".
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: t.navLabel.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: semantic,
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        triggerMode: TooltipTriggerMode.longPress,
        excludeFromSemantics: true,
        preferBelow: false,
        child: button,
      ),
    );
  }
}

/// The "Sipariş ver" key: a 48 × 30 r10 orange-gradient key with a white icon in
/// the icon box, the label in ink 600 under it.
class _NavKey extends StatelessWidget {
  const _NavKey({
    required this.action,
    required this.height,
    required this.iconSize,
  });

  final AknCenterAction action;
  final double height;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    void run() {
      AknHaptics.medium();
      action.onPressed();
    }

    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      onTap: action.onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: run,
        child: PressScale(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: iconSize + 6,
                    child: Center(
                      child: Container(
                        width: 48,
                        height: iconSize + 6,
                        // Owner decision G: the key wears the primary
                        // button's orange gradient with a white glyph.
                        decoration: BoxDecoration(
                          gradient: c.buttonGradient,
                          borderRadius: AknRadius.chip,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          action.icon,
                          size: iconSize,
                          color: c.onBrandFill,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        action.label,
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center,
                        style: t.navLabel.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
