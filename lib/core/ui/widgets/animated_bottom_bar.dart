import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  final IconData icon;
  final IconData? selectedIcon;

  /// Short bar label (≤ 10 characters, spec C.7).
  final String label;

  /// Count bubble (Onaylarım). 0 hides it.
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

/// The raised action in the bar's notch ("Sipariş ver", "Saha formu").
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

/// Bottom navigation (spec A.2 bar rules, C.6 motion).
///
/// * 4 destinations + "Diğer", or 3 + a [centerAction] in a notch + "Diğer" —
///   the shell builds the list; "Diğer" is an ordinary item with [AknNavItem.showDot].
/// * Long-press shows the full name of a shortened label; the center action's
///   label is tappable too.
/// * The selection pill slides between tabs; badges pop; tab changes give a
///   selection haptic. Labels always show (clamped to 1.3× text scale).
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

  static const double _barHeight = 64;
  static const double _pillWidth = 56;
  static const double _pillHeight = 30;
  static const double _centerSize = 56;
  static const double _centerRise = 22;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final center = centerAction;
    final slots = items.length + (center == null ? 0 : 1);
    final centerSlot = center == null ? -1 : (items.length / 2).ceil();
    int slotOf(int itemIndex) =>
        center == null || itemIndex < centerSlot ? itemIndex : itemIndex + 1;
    int itemAt(int slot) =>
        center == null || slot < centerSlot ? slot : slot - 1;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Kenardan kenara: alttaki sistem gezinme çubuğu simgeleri bu yüzeye göre.
      value: AknTheme.overlayFor(c.brightness),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final slotWidth = width / math.max(slots, 1);
              final selectedSlot =
                  currentIndex >= 0 && currentIndex < items.length
                  ? slotOf(currentIndex)
                  : -1;
              final notchX = center == null
                  ? null
                  : slotWidth * centerSlot + slotWidth / 2;
              // With a center action the widget is taller by the button's rise
              // (transparent band), so the whole button stays tappable.
              final rise = center == null ? 0.0 : _centerRise;
              return CustomPaint(
                painter: _BarPainter(
                  color: c.surfaceRaised,
                  line: c.line,
                  shadow: c.isDark
                      ? const Color(0x66000000)
                      : const Color(0x1A0F172A),
                  top: rise,
                  notchX: notchX,
                  notchRadius: _centerSize / 2 + 6,
                  notchCenterY: _centerSize / 2,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: rise, bottom: bottomInset),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: _barHeight,
                        ),
                        child: Stack(
                          children: [
                            if (selectedSlot >= 0)
                              AnimatedPositioned(
                                duration: AknMotion.of(context, AknMotion.base),
                                curve: AknMotion.emphasizedCurve,
                                left:
                                    slotWidth * selectedSlot +
                                    (slotWidth - _pillWidth) / 2,
                                top: 8,
                                width: _pillWidth,
                                height: _pillHeight,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: c.brandSoft,
                                    borderRadius: AknRadius.pillAll,
                                  ),
                                ),
                              ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var s = 0; s < slots; s++)
                                  Expanded(
                                    child: s == centerSlot
                                        ? _CenterLabel(action: center!)
                                        : _NavButton(
                                            item: items[itemAt(s)],
                                            selected: s == selectedSlot,
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
                          ],
                        ),
                      ),
                    ),
                    if (center != null)
                      Positioned(
                        left: notchX! - _centerSize / 2,
                        top: 0,
                        child: _CenterButton(action: center, size: _centerSize),
                      ),
                  ],
                ),
              );
            },
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
    required this.onTap,
  });

  final AknNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final duration = AknMotion.of(context, AknMotion.base);
    final color = selected ? c.brand : c.dim;
    final badge = item.badgeCount;
    final semantic =
        item.semanticLabel ??
        (badge > 0
            ? '${item.label}, $badge yeni'
            : item.showDot
            ? '${item.label}, yeni öğe var'
            : item.label);
    final tooltip = item.tooltip;
    final Widget button = InkResponse(
      onTap: onTap,
      containedInkWell: false,
      highlightShape: BoxShape.circle,
      radius: 32,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 30,
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: color),
                      duration: duration,
                      builder: (context, col, _) => AnimatedSwitcher(
                        duration: AknMotion.of(context, AknMotion.fast),
                        child: Icon(
                          selected
                              ? (item.selectedIcon ?? item.icon)
                              : item.icon,
                          key: ValueKey(selected),
                          size: 24,
                          color: col,
                        ),
                      ),
                    ),
                    Positioned(
                      right: badge > 0 ? -10 : -3,
                      top: badge > 0 ? -6 : -1,
                      child: AknCountBadge(
                        count: badge,
                        dot: badge <= 0 && item.showDot,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: duration,
              style: t.captionStrong.copyWith(
                color: selected ? c.brandInk : c.dim,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 11.5,
              ),
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: semantic,
      excludeSemantics: true,
      onTap: onTap,
      child: tooltip == null || tooltip == item.label
          ? button
          : Tooltip(
              message: tooltip,
              triggerMode: TooltipTriggerMode.longPress,
              excludeFromSemantics: true,
              preferBelow: false,
              child: button,
            ),
    );
  }
}

class _CenterLabel extends StatelessWidget {
  const _CenterLabel({required this.action});

  final AknCenterAction action;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    // The label sits under the raised button, inside the bar; tapping it
    // runs the action too (the button above carries the semantics).
    return ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AknHaptics.medium();
          action.onPressed();
        },
        child: Padding(
          padding: const EdgeInsets.only(top: 41, bottom: 8),
          child: Text(
            action.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: t.captionStrong.copyWith(
              color: c.brandInk,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _CenterButton extends StatelessWidget {
  const _CenterButton({required this.action, required this.size});

  final AknCenterAction action;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      onTap: action.onPressed,
      child: PressScale(
        scale: 0.94,
        child: GestureDetector(
          onTap: () {
            AknHaptics.medium();
            action.onPressed();
          },
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: c.brandFill,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: c.brandFill.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(action.icon, color: c.onBrandFill, size: 28),
          ),
        ),
      ),
    );
  }
}

/// Bar surface with rounded top corners, a soft upward shadow, a hairline
/// and an optional circular notch for the center action.
class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.color,
    required this.line,
    required this.shadow,
    required this.top,
    required this.notchX,
    required this.notchRadius,
    required this.notchCenterY,
  });

  final Color color;
  final Color line;
  final Color shadow;

  /// Transparent band above the bar (center button rise).
  final double top;
  final double? notchX;
  final double notchRadius;
  final double notchCenterY;

  Path _path(Size size) {
    const r = AknRadius.xl;
    final rect = Rect.fromLTWH(0, top, size.width, size.height - top);
    final base = Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: const Radius.circular(r),
          topRight: const Radius.circular(r),
        ),
      );
    final x = notchX;
    if (x == null) return base;
    final notched = const CircularNotchedRectangle().getOuterPath(
      rect,
      Rect.fromCircle(center: Offset(x, notchCenterY), radius: notchRadius),
    );
    return Path.combine(PathOperation.intersect, base, notched);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path(size);
    canvas.drawPath(
      path.shift(const Offset(0, -2)),
      Paint()
        ..color = shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = line,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.color != color ||
      old.line != line ||
      old.shadow != shadow ||
      old.top != top ||
      old.notchX != notchX ||
      old.notchRadius != notchRadius ||
      old.notchCenterY != notchCenterY;
}
