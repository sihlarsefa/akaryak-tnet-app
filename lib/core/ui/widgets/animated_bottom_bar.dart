import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../driver_mode.dart';
import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';

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

  /// At rest: the Phosphor Regular (line) icon.
  final IconData icon;

  /// Active: the Phosphor Fill icon (cross-fades in with a pop).
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

/// Bottom navigation (design v3 §4 "Akış"): docked, full width, 64 + safe
/// area. The surface is frosted — `surfaceRaised` at 92 % over a σ 20
/// backdrop blur — and lifts off the content with [AknShadows.bar]; no
/// hairline (dark mode keeps a faint top edge, as dark cards do).
///
/// * Items share the width. At rest: the Phosphor Regular icon (24) and the
///   label in `navLabel` 11/14 w600 `navInactive`. Active — the panel's
///   "you are here": the Fill icon cross-fades in and pops (1 → 1.14 → 1),
///   icon and label turn Pas (`brandInk`, label w700), and the **pill** — a
///   56 × 32 `brandSoft` capsule behind the icon — slides
///   to it on [AknMotion.spring] ([AknMotion.needle]), stretching toward its
///   destination like a drop and settling with a small overshoot. Labels
///   clamp at 1.2× (long-press shows the full name).
/// * [centerAction] ("Sipariş ver"): a 52 × 40 r14 key in the primary
///   button's orange gradient with a white glyph and its warm glow, which
///   breathes ([AknAmbient]); press scale 0.92 + a haptic. Its label (Pas
///   orange w700, never mistaken for the selected tab) shares the others'
///   line.
/// * Badges: a deep-orange count pill (`brandFillPressed`, white 10 w800
///   tabular digits ≥ 4.5:1) or a logo-orange dot, each with a 2 px ring in
///   the bar colour; they pop when the count changes and breathe.
/// * First appearance (the shell opens): the items fade in and rise 12 px one
///   after another (40 ms apart), the key pops in and the pill grows under
///   the active icon.
/// * Driver mode: icon 26 (pill 60 × 34), label 12/15, items ≥ 64 high.
/// * [currentIndex] may be -1 (nothing selected).
class AnimatedBottomBar extends StatefulWidget {
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

  /// Height above the safe area (64; driver mode grows with its icons).
  static const double barHeight = 64;
  static const double _maxWidth = 640;

  /// Space above the pill (and the label line under it).
  static const double _top = 10;
  static const double _labelGap = 4;

  @override
  State<AnimatedBottomBar> createState() => _AnimatedBottomBarState();
}

class _AnimatedBottomBarState extends State<AnimatedBottomBar>
    with SingleTickerProviderStateMixin {
  /// One item's entrance and the step between two items.
  static const Duration _enterRun = Duration(milliseconds: 420);
  static const Duration _enterStep = Duration(milliseconds: 40);
  static const int _enterSteps = 5;

  /// The first appearance: every slot rises in, one after another.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: _enterRun + _enterStep * _enterSteps,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _enter.value = 1;
    } else {
      _enter.forward();
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  /// The linear 0 → 1 entrance of [slot] within [_enter].
  Animation<double> _slotEnter(int slot) {
    final total = _enter.duration!.inMicroseconds;
    final start =
        (_enterStep * math.min(slot, _enterSteps)).inMicroseconds / total;
    final end = math.min(1.0, start + _enterRun.inMicroseconds / total);
    return _enter.drive(CurveTween(curve: Interval(start, end)));
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final currentIndex = widget.currentIndex;
    final onSelected = widget.onSelected;
    const barHeight = AnimatedBottomBar.barHeight;
    const top = AnimatedBottomBar._top;
    const labelGap = AnimatedBottomBar._labelGap;
    final c = context.akn;
    final driver = context.driverMode;
    final center = widget.centerAction;
    final slots = items.length + (center == null ? 0 : 1);
    final centerSlot = center == null ? -1 : (items.length / 2).ceil();
    int slotOf(int itemIndex) =>
        center == null || itemIndex < centerSlot ? itemIndex : itemIndex + 1;
    int itemAt(int slot) =>
        center == null || slot < centerSlot ? slot : slot - 1;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final itemHeight = driver?.navItemHeight ?? barHeight;
    final iconSize = driver?.navIconSize ?? 24;
    final pillHeight = iconSize + 8;
    final selectedSlot = currentIndex >= 0 && currentIndex < items.length
        ? slotOf(currentIndex)
        : -1;
    final fill = c.surfaceRaised;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Kenardan kenara: alttaki sistem gezinme çubuğu simgeleri çubuğa göre.
      value: AknTheme.overlayFor(c.brightness),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.2,
        child: _FrostedDock(
          child: Padding(
            padding: EdgeInsets.only(bottom: safeBottom),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AnimatedBottomBar._maxWidth,
                ),
                child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  // 6 px side padding: the outer items do not sit on the
                  // screen edge.
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final slotWidth =
                            constraints.maxWidth / math.max(slots, 1);
                        final pillWidth = math.min(
                          iconSize * 2 + 8,
                          slotWidth - 8,
                        );
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: _PillTrack(
                                slot: selectedSlot,
                                slotWidth: slotWidth,
                                pill: Size(pillWidth, pillHeight),
                                top: top,
                                color: c.brandSoft,
                              ),
                            ),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: itemHeight,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var s = 0; s < slots; s++)
                                    Expanded(
                                      child: _SlotEnter(
                                        animation: _slotEnter(s),
                                        pop: s == centerSlot,
                                        child: s == centerSlot
                                            ? _NavKey(
                                                action: center!,
                                                height: itemHeight,
                                                iconSize: iconSize,
                                                labelTop:
                                                    top + pillHeight + labelGap,
                                              )
                                            : _NavButton(
                                                item: items[itemAt(s)],
                                                selected: s == selectedSlot,
                                                height: itemHeight,
                                                iconSize: iconSize,
                                                pillHeight: pillHeight,
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
                                    ),
                                ],
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

/// The frosted dock: [AknShadows.bar] around a σ 20 backdrop blur under
/// `surfaceRaised` at 92 % (dark: plus a faint top edge).
class _FrostedDock extends StatelessWidget {
  const _FrostedDock({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return DecoratedBox(
      decoration: BoxDecoration(boxShadow: AknShadows.bar(c)),
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surfaceRaised.withValues(alpha: 0.92),
              border: c.isDark
                  ? Border(
                      top: BorderSide(color: c.line.withValues(alpha: 0.7)),
                    )
                  : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// One slot's first entrance ([animation] runs 0 → 1 once): an item fades in
/// and rises 12 px on the emphasized curve; the key ([pop]) fades in and
/// pops from 0.6. Paint-only; the slot is laid out (and tappable) at once.
class _SlotEnter extends StatelessWidget {
  const _SlotEnter({
    required this.animation,
    required this.child,
    this.pop = false,
  });

  final Animation<double> animation;
  final bool pop;
  final Widget child;

  static const Interval _fade = Interval(0, 0.6, curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final v = animation.value;
      if (v >= 1) return child!;
      final Widget moved = pop
          ? Transform.scale(
              scale: 0.6 + 0.4 * AknMotion.pop.transform(v),
              child: child,
            )
          : Transform.translate(
              offset: Offset(
                0,
                12 * (1 - AknMotion.emphasizedCurve.transform(v)),
              ),
              child: child,
            );
      return Opacity(opacity: _fade.transform(v), child: moved);
    },
  );
}

/// The active pill: one capsule for the whole bar that travels between the
/// slots. While it moves, the edge in the direction of travel leads and the
/// other follows (both on [AknMotion.spring]), so the capsule stretches,
/// thins a little and settles with a small overshoot. Paint-only per frame.
class _PillTrack extends StatefulWidget {
  const _PillTrack({
    required this.slot,
    required this.slotWidth,
    required this.pill,
    required this.top,
    required this.color,
  });

  /// The selected slot, -1 for none.
  final int slot;
  final double slotWidth;
  final Size pill;
  final double top;
  final Color color;

  @override
  State<_PillTrack> createState() => _PillTrackState();
}

class _PillTrackState extends State<_PillTrack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AknMotion.needle,
    value: 1,
  );

  /// Where the current move started and where it goes (slot units).
  late double _from = widget.slot.toDouble();
  late int _to = widget.slot;

  /// Appearing (true) or leaving (false) instead of travelling.
  bool? _fade;
  bool _started = false;

  /// The bar's first appearance: the pill grows in under the active icon.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.slot < 0 || AknMotion.reduced(context)) return;
    _fade = true;
    _c.forward(from: 0);
  }

  @override
  void didUpdateWidget(_PillTrack old) {
    super.didUpdateWidget(old);
    if (old.slot == widget.slot) return;
    if (AknMotion.reduced(context)) {
      _from = widget.slot.toDouble();
      _to = widget.slot;
      _fade = null;
      _c.value = 1;
      return;
    }
    if (old.slot < 0 || widget.slot < 0) {
      _fade = widget.slot >= 0;
      _from = (widget.slot >= 0 ? widget.slot : old.slot).toDouble();
      _to = widget.slot;
    } else {
      _from = _travelling ? _centreAt(_c.value) : old.slot.toDouble();
      _to = widget.slot;
      _fade = null;
    }
    _c.duration = AknMotion.needle + _extraFor((_to - _from).abs());
    _c.forward(from: 0);
  }

  bool get _travelling => _c.isAnimating && _fade == null && _to >= 0;

  /// Longer moves take a little longer (three slots: +90 ms).
  static Duration _extraFor(double slots) =>
      Duration(milliseconds: (math.max(0, slots - 1) * 45).round());

  double _centreAt(double t) =>
      _from + (_to - _from) * AknMotion.spring.transform(t);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _PillPainter(
          progress: _c,
          from: _from,
          to: _to,
          fade: _fade,
          slotWidth: widget.slotWidth,
          pill: widget.pill,
          top: widget.top,
          color: widget.color,
        ),
      ),
    );
  }
}

class _PillPainter extends CustomPainter {
  _PillPainter({
    required this.progress,
    required this.from,
    required this.to,
    required this.fade,
    required this.slotWidth,
    required this.pill,
    required this.top,
    required this.color,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final double from;
  final int to;
  final bool? fade;
  final double slotWidth;
  final Size pill;
  final double top;
  final Color color;

  static const Interval _lead = Interval(0, 0.86);
  static const Interval _trail = Interval(0.1, 1);

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final w = pill.width;
    final h = pill.height;
    double centre(double slot) => slotWidth * (slot + 0.5);
    var left = 0.0;
    var right = 0.0;
    var height = h;
    var opacity = 1.0;
    final appear = fade;
    if (appear != null) {
      // Appearing grows in on the spring; leaving shrinks away.
      final s = appear
          ? 0.6 + 0.4 * AknMotion.spring.transform(t)
          : 1 - 0.4 * AknMotion.exit.transform(t);
      opacity = appear ? t.clamp(0.0, 1.0) : 1 - t;
      if (opacity <= 0) return;
      final cx = centre(from);
      left = cx - w * s / 2;
      right = cx + w * s / 2;
      height = h * s;
    } else {
      if (to < 0) return;
      final a = centre(from);
      final b = centre(to.toDouble());
      final lead = a + (b - a) * AknMotion.spring.transform(_lead.transform(t));
      final trail =
          a + (b - a) * AknMotion.spring.transform(_trail.transform(t));
      if (b >= a) {
        right = lead + w / 2;
        left = trail - w / 2;
      } else {
        left = lead - w / 2;
        right = trail + w / 2;
      }
      // Never thinner than 85 % (the trailing overshoot squeezes a little).
      if (right - left < w * 0.85) {
        final mid = (left + right) / 2;
        left = mid - w * 0.425;
        right = mid + w * 0.425;
      }
      // Stretched, the capsule thins (up to 12 %).
      final stretch = ((right - left) / w - 1).clamp(0.0, 1.0);
      height = h * (1 - 0.12 * stretch);
    }
    final rect = Rect.fromLTRB(
      left,
      top + (h - height) / 2,
      right,
      top + (h + height) / 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(height / 2)),
      Paint()..color = color.withValues(alpha: color.a * opacity),
    );
  }

  @override
  bool shouldRepaint(_PillPainter old) =>
      old.progress != progress ||
      old.from != from ||
      old.to != to ||
      old.fade != fade ||
      old.slotWidth != slotWidth ||
      old.pill != pill ||
      old.top != top ||
      old.color != color;
}

/// One bar item: the icon over the (shared) pill, the badge, the label.
class _NavButton extends StatefulWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.height,
    required this.iconSize,
    required this.pillHeight,
    required this.ring,
    required this.onTap,
  });

  final AknNavItem item;
  final bool selected;
  final double height;
  final double iconSize;
  final double pillHeight;
  final Color ring;
  final VoidCallback onTap;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton>
    with SingleTickerProviderStateMixin {
  /// The icon pop: 1 → 1.14 → 1, the way down on the spring.
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: AknMotion.needle,
  );
  bool _pressed = false;

  static final Animatable<double> _popScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 1.14,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 32,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.14,
        end: 1,
      ).chain(CurveTween(curve: AknMotion.spring)),
      weight: 68,
    ),
  ]);

  void _popIcon() {
    if (AknMotion.reduced(context)) return;
    _pop.forward(from: 0);
  }

  @override
  void didUpdateWidget(_NavButton old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) _popIcon();
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final item = widget.item;
    final selected = widget.selected;
    final badge = item.badgeCount;
    final semantic =
        item.semanticLabel ??
        (badge > 0
            ? '${item.label}, $badge yeni'
            : item.showDot
            ? '${item.label}, yeni öğe var'
            : item.label);
    final tooltip = item.tooltip ?? item.label;
    final swap = AknMotion.of(context, AknMotion.iconSwap);
    final iconData = selected ? (item.selectedIcon ?? item.icon) : item.icon;

    // Regular → Fill cross-fade; the colour eases with it.
    Widget icon = TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: selected ? c.brandInk : c.navInactive),
      duration: swap,
      curve: AknMotion.standard,
      builder: (context, color, child) => IconTheme.merge(
        data: IconThemeData(color: color, size: widget.iconSize),
        child: child!,
      ),
      child: AnimatedSwitcher(
        duration: swap,
        switchInCurve: AknMotion.standard,
        switchOutCurve: AknMotion.exit,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: Icon(iconData, key: ValueKey<IconData>(iconData)),
      ),
    );
    icon = AnimatedBuilder(
      animation: _pop,
      child: icon,
      builder: (context, child) {
        final s = _popScale.evaluate(_pop);
        if (s == 1) return child!;
        return Transform.translate(
          // A pop also lifts the glyph a hair.
          offset: Offset(0, -12 * (s - 1)),
          child: Transform.scale(scale: s, child: child),
        );
      },
    );
    icon = AnimatedScale(
      scale: _pressed && !AknMotion.reduced(context) ? 0.86 : 1,
      duration: _pressed ? AknMotion.press : AknMotion.pressOut,
      curve: _pressed ? AknMotion.standard : AknMotion.spring,
      child: icon,
    );

    final inactive = t.navLabel.copyWith(
      color: c.navInactive,
      fontWeight: FontWeight.w600,
    );
    final active = t.navLabel.copyWith(
      color: c.brandInk,
      fontWeight: FontWeight.w700,
    );
    final label = TweenAnimationBuilder<double>(
      tween: Tween<double>(end: selected ? 1 : 0),
      duration: swap,
      curve: AknMotion.standard,
      builder: (context, v, _) => Text(
        item.label,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
        style: v <= 0
            ? inactive
            : v >= 1
            ? active
            : TextStyle.lerp(inactive, active, v),
      ),
    );

    final Widget button = InkResponse(
      onTap: () {
        if (selected) _popIcon();
        widget.onTap();
      },
      onHighlightChanged: (v) {
        if (v != _pressed) setState(() => _pressed = v);
      },
      containedInkWell: true,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: widget.height),
        child: Padding(
          padding: const EdgeInsets.only(top: AnimatedBottomBar._top),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: widget.pillHeight,
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      icon,
                      // Always there (it pops in and shrinks away by
                      // itself): the badge hangs off the icon's top-right
                      // corner and grows to the right with more digits.
                      Positioned(
                        left: widget.iconSize - 9,
                        top: -7,
                        child: _NavBadge(
                          count: badge,
                          dot: badge <= 0 && item.showDot,
                          ring: widget.ring,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AnimatedBottomBar._labelGap),
              // A long label (large text) shrinks to its slot instead of
              // touching the neighbour or ending in "…".
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(fit: BoxFit.scaleDown, child: label),
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
      onTap: widget.onTap,
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

/// The bar's badge: a deep-orange count pill (`brandFillPressed` — the white
/// digits stay ≥ 4.5:1 — 10 w800 tabular) or an 8 px logo-orange dot, each
/// in a 2 px ring of the bar colour. It stays in the tree: it pops in (also
/// on first show), pops again when the count changes, shrinks away when it
/// empties, and breathes while shown ([AknAmbient]).
class _NavBadge extends StatefulWidget {
  const _NavBadge({required this.count, required this.dot, required this.ring});

  final int count;
  final bool dot;
  final Color ring;

  @override
  State<_NavBadge> createState() => _NavBadgeState();
}

class _NavBadgeState extends State<_NavBadge> with TickerProviderStateMixin {
  late final AnimationController _show = AnimationController(
    vsync: this,
    duration: AknMotion.slow,
    reverseDuration: AknMotion.fast,
  );
  late final AnimationController _bump = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  /// The last count shown (kept while the badge shrinks away).
  late int _shown = widget.count;
  late bool _shownDot = widget.dot;

  bool get _visible => widget.count > 0 || widget.dot;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!_visible) return;
    if (AknMotion.reduced(context)) {
      _show.value = 1;
    } else {
      _show.forward();
    }
  }

  static final Animatable<double> _bumpScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 1.3,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.3,
        end: 1,
      ).chain(CurveTween(curve: AknMotion.pop)),
      weight: 70,
    ),
  ]);

  @override
  void didUpdateWidget(_NavBadge old) {
    super.didUpdateWidget(old);
    final reduced = AknMotion.reduced(context);
    if (_visible) {
      _shown = widget.count;
      _shownDot = widget.dot;
    }
    final was = old.count > 0 || old.dot;
    if (_visible && !was) {
      if (reduced) {
        _show.value = 1;
      } else {
        _show.forward();
      }
    } else if (!_visible && was) {
      if (reduced) {
        _show.value = 0;
      } else {
        _show.reverse();
      }
    } else if (_visible &&
        widget.count != old.count &&
        widget.count > 0 &&
        old.count > 0 &&
        !reduced) {
      _bump.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _show.dispose();
    _bump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final count = _shown;
    final Widget body = count > 0
        ? Container(
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.brandFillPressed,
              borderRadius: AknRadius.pillAll,
              border: Border.all(color: widget.ring, width: 2),
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              textScaler: TextScaler.noScaling,
              style: context.aknText.captionStrong.copyWith(
                color: c.onBrandFill,
                fontSize: 10,
                height: 12 / 10,
                fontWeight: FontWeight.w800,
                fontFeatures: AknNumerals.tabular,
              ),
            ),
          )
        // The dot sits a little lower and further in than a count.
        : Padding(
            padding: const EdgeInsets.only(left: 1, top: 5),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _shownDot ? c.logo : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: widget.ring, width: 2),
              ),
            ),
          );
    Widget badge = body;
    if (_visible) {
      badge = AknAmbient(
        period: AknMotion.breathe,
        reverse: true,
        builder: (context, t, child) => t == 0
            ? child!
            : Transform.scale(scale: 1 + 0.07 * t, child: child),
        child: badge,
      );
    }
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: Listenable.merge([_show, _bump]),
        child: badge,
        builder: (context, child) {
          final v = _show.value;
          if (v <= 0 && !_visible) return const SizedBox(width: 12, height: 12);
          final grow = _show.status == AnimationStatus.reverse
              ? v
              : AknMotion.pop.transform(v);
          final s = grow * _bumpScale.evaluate(_bump);
          return s == 1 ? child! : Transform.scale(scale: s, child: child);
        },
      ),
    );
  }
}

/// The "Sipariş ver" key: a 52 × 40 r14 orange-gradient key with the white
/// glyph and the primary button's warm glow (breathing), the label under it
/// on the items' line.
class _NavKey extends StatelessWidget {
  const _NavKey({
    required this.action,
    required this.height,
    required this.iconSize,
    required this.labelTop,
  });

  final AknCenterAction action;
  final double height;
  final double iconSize;

  /// The y of the items' label line (the key sits right above it).
  final double labelTop;

  static const Size _key = Size(52, 40);
  static const double _gap = 2;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    void run() {
      AknHaptics.medium();
      action.onPressed();
    }

    final glow = c.brandFill;
    final restAlpha = c.isDark ? 0.35 : 0.55;
    final key = AknAmbient(
      period: AknMotion.breathe,
      reverse: true,
      builder: (context, v, child) => DecoratedBox(
        // Owner decision G: the key wears the primary button's orange
        // gradient and warm glow (AknShadows.button at rest), which breathes.
        decoration: BoxDecoration(
          gradient: c.buttonGradient,
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          boxShadow: [
            BoxShadow(
              color: glow.withValues(alpha: restAlpha + 0.2 * v),
              offset: Offset(0, 8 - 2 * v),
              blurRadius: 18 + 10 * v,
              spreadRadius: -6 + 2 * v,
            ),
          ],
        ),
        child: child,
      ),
      child: SizedBox.fromSize(
        size: _key,
        child: Center(
          child: Icon(action.icon, size: iconSize, color: c.onBrandFill),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      onTap: action.onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: run,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: Padding(
            padding: EdgeInsets.only(
              top: math.max(0, labelTop - _gap - _key.height),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PressScale(scale: 0.92, child: RepaintBoundary(child: key)),
                const SizedBox(height: _gap),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      action.label,
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      // The action's own colour: orange text (Pas,
                      // 5.18:1), so it never reads as a second selected tab.
                      style: t.navLabel.copyWith(
                        color: c.brandInk,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
