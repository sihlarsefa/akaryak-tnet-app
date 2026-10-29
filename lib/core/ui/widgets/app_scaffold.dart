import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../driver_mode.dart';
import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';
import 'buttons.dart';
import 'home_header.dart';
import 'skeletons.dart';
import 'states.dart';

export 'home_header.dart';

/// Shell-level state the design system reads: the unread count for the bell,
/// connectivity and pending operations for the offline banner.
///
/// The app shell provides it once above the router, e.g.
///
/// ```dart
/// MaterialApp.router(
///   builder: (context, child) => Consumer(builder: (context, ref, _) =>
///     AppChrome(
///       unreadCount: ref.watch(unreadCountProvider).notifications,
///       onOpenNotifications: () => router.push('/notifications'),
///       offline: ref.watch(isOfflineProvider),
///       pendingOps: ref.watch(pendingOpsCountProvider),
///       child: child!,
///     )),
/// )
/// ```
///
/// Without it the bell is hidden and no offline banner shows.
class AppChrome extends InheritedWidget {
  const AppChrome({
    super.key,
    required super.child,
    this.unreadCount = 0,
    this.onOpenNotifications,
    this.offline = false,
    this.pendingOps = 0,
    this.onOpenPendingOps,
    this.onGoHome,
  });

  final int unreadCount;
  final VoidCallback? onOpenNotifications;
  final bool offline;
  final int pendingOps;
  final VoidCallback? onOpenPendingOps;

  /// Goes to Ana sayfa (v4 §3.5): a pushed page that cannot pop and is not
  /// a tab root shows an "Ana sayfa" house button that calls it. Null while
  /// signed out.
  final VoidCallback? onGoHome;

  static AppChrome? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppChrome>();

  @override
  bool updateShouldNotify(AppChrome old) =>
      old.unreadCount != unreadCount ||
      old.onOpenNotifications != onOpenNotifications ||
      old.offline != offline ||
      old.pendingOps != pendingOps ||
      old.onOpenPendingOps != onOpenPendingOps ||
      old.onGoHome != onGoHome;
}

/// Marks the shell's tab pages (v4 §3.5): the app shell wraps its tab
/// navigators in it, so `AppScaffold` knows a page is a tab root (no house
/// button) and the shell's Android back can spring home.
class AknTabScope extends InheritedWidget {
  const AknTabScope({super.key, required super.child});

  /// True inside the shell's tabs.
  static bool isIn(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AknTabScope>() != null;

  @override
  bool updateShouldNotify(AknTabScope oldWidget) => false;
}

/// The "Ana sayfa" house button of a pushed page that cannot pop (v4
/// §3.5): the house glyph in the bar's circle; screen readers hear "Ana
/// sayfa".
class AknHomeButton extends StatelessWidget {
  const AknHomeButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Ana sayfa',
    onPressed: () {
      AknHaptics.selection();
      onPressed();
    },
    icon: const Icon(PhosphorIconsRegular.house),
  );
}

/// The bell (design v3 §4): the Phosphor `bell` 24 in ink with the count
/// badge, from [AppChrome]. Hidden when the shell provides no notifications
/// callback.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.maybeOf(context);
    if (chrome == null || chrome.onOpenNotifications == null) {
      return const SizedBox.shrink();
    }
    final unread = chrome.unreadCount;
    return AknIconButton(
      icon: PhosphorIconsRegular.bell,
      semanticLabel: 'Bildirimler',
      badgeCount: unread,
      badgeSemantics: (n) => '$n okunmamış',
      color: color,
      onPressed: chrome.onOpenNotifications,
    );
  }
}

/// Page scaffold (design v3 §4 "Akış"): the bar, the offline line under it,
/// a refresh bar that keeps content visible, and a sticky [actionBar].
///
/// * **Home** ([homeHeader], e.g. [AknHomeHeader]): with an [AknHomeHeader]
///   (owner decision G) the pinned orange band behind the status bar, the
///   page in `homeBg`, and the band's warm shadow, which grows as content
///   scrolls under the band. The home's hero card joins the band through
///   [AknBandOverlap]. Any other header widget sits on the page colour.
/// * **Root tab pages** (no back button: Siparişlerim, Onaylarım, Teklif
///   masası …): 60 px bar, the title in `display` 28/34 800 left at 20,
///   ink action buttons (and the bell).
/// * **Pushed pages**: 52 px bar, the back button — Phosphor `arrowLeft` 22
///   in a 40 px white circle with the card shadow (a `BackButton`, so its
///   tooltip, semantics and pop behaviour are the platform's; full-screen
///   dialogs get the close ✕) — and the title in `headline` 17/22 700 (one
///   line). Every leading button sits in the same circle.
/// * The bar is the page colour at rest. Once content scrolls under it the
///   bar turns frosted — `surface` at 85 % over a σ 16 blur — and casts a
///   soft shadow (200 ms), never a hairline.
/// * The offline line slides down and fades in under the bar.
///   [largeTitle] overrides the root / pushed detection.
/// * **Page band** (the web panel's `.page-hero`): a root page with a
///   [bandIcon] trades the big title for the panel's band — a soft orange
///   tinted card with a 1 px orange-tinted line, the icon in a white tile,
///   a sentence-case [eyebrow] (Pas), the title (20 700) and a one-line
///   [description]; the page actions and the bell sit at its right
///   ([AknPageBand]).
/// * [hero] / [navy] are deprecated and render the normal bar.
///
/// Design v4 "Sade":
/// * A root page's band carries the tab's word ([title]) and ONE live
///   [status] line ([AknStatusClause]s, a String with [statusTone], or an
///   `InlineSpan`); [eyebrow] is ignored and [description] maps to the
///   status. At most two band actions; no bell ([showBell] defaults to
///   false — the bell lives in the home band only).
/// * A pushed page shows [collapsedTitle] (the object's human name) in the
///   frosted bar once the page scrolls.
/// * A page that cannot pop and is not a tab root leads with the "Ana
///   sayfa" house button ([AppChrome.onGoHome]).
/// * Every page installs an [AknAmbientBudget]: the band light plus one
///   focus loop per viewport.
class AppScaffold extends StatefulWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.actions = const [],
    this.showBell = false,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.bottom,
    this.actionBar,
    this.floatingActionButton,
    this.hero = false,
    this.navy = false,
    this.refreshing = false,
    this.showOfflineBanner = true,
    this.backgroundColor,
    this.resizeToAvoidBottomInset = true,
    this.appBar = true,
    this.homeHeader,
    this.largeTitle,
    this.bandIcon,
    this.eyebrow,
    this.description,
    this.status,
    this.statusTone,
    this.onStatusTap,
    this.collapsedTitle,
  });

  final Widget body;
  final String? title;
  final Widget? titleWidget;
  final String? subtitle;
  final List<Widget> actions;

  /// Shows the bell when [AppChrome] provides a notifications callback.
  /// v4: false by default (the bell lives in the home band only).
  final bool showBell;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  /// Under the bar (e.g. a `TabBar`).
  final PreferredSizeWidget? bottom;

  /// Sticky bottom area for the screen's primary actions ([ActionBar]).
  final Widget? actionBar;
  final Widget? floatingActionButton;

  /// Deprecated: the orange header strip is gone; renders the normal bar.
  final bool hero;

  /// Deprecated alias of [hero].
  final bool navy;

  /// Background refresh in progress: thin bar under the app bar, content
  /// stays.
  final bool refreshing;
  final bool showOfflineBanner;
  final Color? backgroundColor;
  final bool resizeToAvoidBottomInset;

  /// False for screens that draw their own header.
  final bool appBar;

  /// The home header (§4), pinned in place of the app bar.
  final Widget? homeHeader;

  /// Forces the root (`display` title, 60 px) or pushed (`headline`, 52 px)
  /// bar; null detects it from the route (a back button means pushed).
  final bool? largeTitle;

  /// The page band's icon (root pages): with it the root bar becomes the
  /// panel's page band ([AknPageBand]).
  final IconData? bandIcon;

  /// Ignored (v4: the band has no eyebrow).
  final String? eyebrow;

  /// Old call sites: the band's status line when [status] is null.
  final String? description;

  /// v4: the band's live status line — a `String`, an `InlineSpan`, an
  /// [AknStatusClause] or a `List<AknStatusClause>` (see [AknPageBand]).
  final Object? status;

  /// The tone of a String [status] (brand: Pas 600, danger: `danger.fg`
  /// 600; else dim).
  final AknTone? statusTone;

  /// Tapping the status line (e.g. jump to "Gecikmiş").
  final VoidCallback? onStatusTap;

  /// v4: the object's human name, shown in the frosted bar of a pushed page
  /// once the page scrolls ("Motorin, 8.000 L").
  final String? collapsedTitle;

  /// Deprecated: always false visually (kept for API stability).
  bool get isHero => hero || navy;

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  bool _scrolled = false;

  /// How far the page has scrolled under the top (px): the home band's
  /// shadow grows with it without rebuilding the page.
  final ValueNotifier<double> _offset = ValueNotifier<double>(0);

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final before = n.metrics.extentBefore;
    _offset.value = before;
    final scrolled = before > 0.5;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    return false;
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final chrome = AppChrome.maybeOf(context);
    final home = widget.homeHeader;
    final band = home is AknHomeHeader && home.band;
    final pageColor = widget.backgroundColor ?? (band ? c.homeBg : c.bg);

    PreferredSizeWidget? bar;
    if (widget.appBar && home == null) {
      final route = ModalRoute.of(context);
      final canGoBack =
          widget.leading != null ||
          (widget.automaticallyImplyLeading &&
              (route?.impliesAppBarDismissal ?? false));
      // v4 §3.5: a page that cannot pop and is not a tab root leads home.
      final goHome = chrome?.onGoHome;
      final Widget? homeLeading =
          !canGoBack &&
              widget.leading == null &&
              widget.automaticallyImplyLeading &&
              goHome != null &&
              !AknTabScope.isIn(context)
          ? AknHomeButton(onPressed: goHome)
          : null;
      final root = widget.largeTitle ?? (!canGoBack && homeLeading == null);
      final scaler = MediaQuery.textScalerOf(context);
      final t = context.aknText;
      final driver = context.isDriverMode;
      final bandIcon = widget.bandIcon;
      final pageTitle = widget.title;
      if (root && bandIcon != null && pageTitle != null) {
        final Object? status =
            widget.status ?? widget.description ?? widget.subtitle;
        final hasStatus =
            status != null && AknPageBand.plainStatus(status).isNotEmpty;
        final band = AknPageBand(
          icon: bandIcon,
          title: pageTitle,
          status: status,
          statusTone: widget.status is String ? widget.statusTone : null,
          onStatusTap: widget.onStatusTap,
          actions: [
            ...widget.actions,
            if (widget.showBell) const NotificationBell(),
          ],
        );
        bar = _AknAppBar(
          root: true,
          toolbarHeight:
              AknPageBand.heightFor(scaler, description: hasStatus) +
              AknPageBand.margin * 2,
          titleScale: AknPageBand.maxTextScale,
          scrolled: _scrolled,
          title: null,
          titleWidget: band,
          titleIsBand: true,
          subtitle: null,
          // A band page that cannot pop and is not a tab root leads home
          // (§3.5), like a pushed bar.
          leading: widget.leading ?? homeLeading,
          automaticallyImplyLeading: widget.automaticallyImplyLeading,
          background: pageColor,
          actions: const [],
          bottom: widget.bottom,
        );
      }
      final titleStyle = root ? t.display : t.headline;
      final titleScale = root ? 1.5 : 1.6;
      final line =
          scaler.clamp(maxScaleFactor: titleScale).scale(titleStyle.fontSize!) *
          (titleStyle.height ?? 1.2);
      final subtitleLine = widget.subtitle == null
          ? 0.0
          : scaler.clamp(maxScaleFactor: 1.6).scale(14) * 20 / 14;
      final toolbar = root
          ? (line + subtitleLine + 24).clamp(
              driver ? 64.0 : AknTheme.rootBarHeight,
              200.0,
            )
          : (line + subtitleLine + 8).clamp(
              driver ? 60.0 : AknTheme.pushedBarHeight,
              200.0,
            );
      bar ??= _AknAppBar(
        root: root,
        toolbarHeight: toolbar,
        titleScale: titleScale,
        scrolled: _scrolled,
        title: widget.title,
        titleWidget: widget.titleWidget,
        subtitle: widget.subtitle,
        collapsedTitle: widget.collapsedTitle,
        leading: widget.leading ?? homeLeading,
        automaticallyImplyLeading: widget.automaticallyImplyLeading,
        background: pageColor,
        actions: [
          ...widget.actions,
          if (widget.showBell) const NotificationBell(),
          const SizedBox(width: 6),
        ],
        bottom: widget.bottom,
      );
    }

    final banner = widget.showOfflineBanner && chrome != null
        ? _BannerReveal(
            visible: chrome.offline || chrome.pendingOps > 0,
            child: OfflineBanner(
              offline: chrome.offline,
              pendingCount: chrome.pendingOps,
              onTap: chrome.onOpenPendingOps,
            ),
          )
        : null;

    final content = Column(
      children: [
        if (home != null && band)
          home
        else if (home != null)
          ColoredBox(
            color: pageColor,
            child: SafeArea(bottom: false, child: home),
          ),
        ?banner,
        Expanded(
          child: Stack(
            children: [
              // Geniş ekranda (tablet, yatay) içerik en fazla 640 dp.
              Positioned.fill(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: ContentMaxWidth(child: widget.body),
                ),
              ),
              // The header's shadow over the content, growing as the page
              // scrolls under it (the band's warm shadow; a soft ink one under
              // other headers).
              if (home != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 48,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _TopShadowPainter(
                        offset: _offset,
                        color: band
                            ? AknShadows.band(c).first.color
                            : (c.isDark
                                  ? const Color(0x80000000)
                                  : const Color(0x2915171A)),
                        radius: band ? AknRadius.xl : 0,
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: TopProgressBar(active: widget.refreshing),
              ),
            ],
          ),
        ),
      ],
    );

    final scaffold = Scaffold(
      backgroundColor: pageColor,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      appBar: bar,
      floatingActionButton: widget.floatingActionButton,
      body: content,
      bottomNavigationBar: switch (widget.actionBar) {
        null => null,
        final ActionBar dock => dock,
        final other => ActionBar(child: other),
      },
    );
    // System bars follow the page surface (dark icons on the light page,
    // light on the dark page).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AknTheme.overlayFor(c.brightness),
      // v4 §6: one loop budget per page (the band light + one focus loop).
      child: AknAmbientBudget(child: scaffold),
    );
  }
}

/// How long the bar takes to turn frosted (and back).
const Duration _frostDuration = Duration(milliseconds: 200);

/// The scaffold's app bar: the page colour at rest, frosted with a soft
/// shadow once content scrolls under it; a root (`display`) or pushed
/// (`headline`) title; the leading button in a white circle.
class _AknAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AknAppBar({
    required this.root,
    required this.toolbarHeight,
    required this.titleScale,
    required this.scrolled,
    required this.title,
    required this.titleWidget,
    required this.subtitle,
    required this.leading,
    required this.automaticallyImplyLeading,
    required this.background,
    required this.actions,
    required this.bottom,
    this.titleIsBand = false,
    this.collapsedTitle,
  });

  /// Shown instead of [title] once content scrolls under a pushed bar.
  final String? collapsedTitle;

  /// [titleWidget] is an [AknPageBand]: it spans the bar between the page
  /// gutters and marks its own title as the header.
  final bool titleIsBand;

  final bool root;
  final double toolbarHeight;
  final double titleScale;
  final bool scrolled;
  final String? title;
  final Widget? titleWidget;
  final String? subtitle;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final Color background;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  /// The leading slot: a 48 px target whose 40 px circle starts on the page
  /// gutter (20), in line with the cards under it.
  static const double _leadingWidth = 64;

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    Widget? titleBlock = titleWidget;
    if (titleBlock == null && title != null) {
      final style =
          (root ? AknTheme.rootAppBarTitle(t) : AknTheme.appBarTitle(t))
              .copyWith(color: c.ink);
      // v4: a pushed page's bar shows the object's name once it scrolls.
      final shown = !root && scrolled && collapsedTitle != null
          ? collapsedTitle!
          : title!;
      titleBlock = MediaQuery.withClampedTextScaling(
        maxScaleFactor: titleScale,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeThroughSwitcher(
              duration: AknMotion.statusFade,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                shown,
                key: ValueKey(shown),
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: t.bodySmall.copyWith(color: c.dim),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      );
    }
    // The platform's back (or, on full-screen dialogs, close) button, as the
    // AppBar would imply it — drawn in the v3 circle.
    var lead = leading;
    if (lead == null && automaticallyImplyLeading) {
      final route = ModalRoute.of(context);
      if (route?.impliesAppBarDismissal ?? false) {
        final close = route is PageRoute && route.fullscreenDialog;
        lead = close ? const CloseButton() : const BackButton();
      }
    }
    // Icon buttons (back, close ✕) sit in the circle; any other leading
    // widget keeps the platform's slot.
    final circled =
        lead is IconButton || lead is AknIconButton || lead is AknHomeButton;
    if (lead != null && circled) lead = _BarLeading(child: lead);
    final spacing = lead == null ? AknSpace.page : (circled ? 8.0 : 0.0);
    final Widget? titled;
    if (titleBlock == null) {
      titled = null;
    } else if (titleIsBand) {
      // The toolbar leaves only [spacing] after its middle: a band behind a
      // back or house button still ends on the page gutter, in line with the
      // switcher and the ledgers under it.
      titled = lead == null || spacing >= AknSpace.page
          ? titleBlock
          : Padding(
              padding: EdgeInsetsDirectional.only(end: AknSpace.page - spacing),
              child: titleBlock,
            );
    } else {
      titled = Semantics(header: true, child: titleBlock);
    }

    return _FrostedTop(
      frosted: scrolled,
      page: background,
      builder: (context, fill) => AppBar(
        toolbarHeight: toolbarHeight,
        // The band marks its own title as the header; its buttons stay
        // separate nodes.
        excludeHeaderSemantics: titleIsBand,
        title: titled,
        centerTitle: false,
        titleSpacing: spacing,
        leading: lead,
        leadingWidth: circled ? _leadingWidth : null,
        automaticallyImplyLeading: false,
        backgroundColor: fill,
        foregroundColor: c.ink,
        iconTheme: IconThemeData(color: c.ink, size: 24),
        actionsIconTheme: IconThemeData(color: c.ink, size: 24),
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: AknTheme.overlayFor(c.brightness),
        actions: actions,
        bottom: bottom,
      ),
    );
  }
}

/// A page-coloured top that turns frosted while content is scrolled under
/// it: the frost ([_Frost]) fades in behind while [builder]'s background
/// eases from [page] to clear, both over [_frostDuration].
class _FrostedTop extends StatelessWidget {
  const _FrostedTop({
    required this.frosted,
    required this.page,
    required this.builder,
  });

  final bool frosted;
  final Color page;
  final Widget Function(BuildContext context, Color fill) builder;

  @override
  Widget build(BuildContext context) {
    final duration = AknMotion.of(context, _frostDuration);
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: frosted ? 1 : 0,
              duration: duration,
              curve: AknMotion.standard,
              child: const _Frost(),
            ),
          ),
        ),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(end: frosted ? 1 : 0),
          duration: duration,
          curve: AknMotion.standard,
          builder: (context, f, _) => builder(
            context,
            f <= 0 ? page : page.withValues(alpha: page.a * (1 - f)),
          ),
        ),
      ],
    );
  }
}

/// The frosted glass of a scrolled bar: `surface` at 85 % over a σ 16
/// backdrop blur, a soft shadow under it (dark: plus a faint edge).
class _Frost extends StatelessWidget {
  const _Frost();

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: c.isDark
            ? const [
                BoxShadow(
                  color: Color(0x80000000),
                  offset: Offset(0, 6),
                  blurRadius: 18,
                  spreadRadius: -6,
                ),
              ]
            : const [
                BoxShadow(
                  color: Color(0x0A15171A),
                  offset: Offset(0, 1),
                  blurRadius: 1.5,
                ),
                BoxShadow(
                  color: Color(0x1F15171A),
                  offset: Offset(0, 8),
                  blurRadius: 20,
                  spreadRadius: -10,
                ),
              ],
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface.withValues(alpha: 0.85),
              border: c.isDark
                  ? Border(
                      bottom: BorderSide(color: c.line.withValues(alpha: 0.8)),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// The leading button of a bar in its v3 circle: 40 px, `surface`, the card
/// shadow (dark: a 1 px line), inside the button's 48 px target. The glyph
/// is 22 px ink — a `BackButton` / `CloseButton` draws Phosphor `arrowLeft`
/// / `x` (their tooltips and semantics stay the platform's). Presses shrink
/// the circle on the spring.
class _BarLeading extends StatelessWidget {
  const _BarLeading({required this.child});

  final Widget child;

  static String? _androidLabel(BuildContext context, {required bool back}) {
    // Like the platform icon: Android reads the label on the glyph too.
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    final l = MaterialLocalizations.of(context);
    return back ? l.backButtonTooltip : l.closeButtonTooltip;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    const transparent = WidgetStatePropertyAll<Color>(Colors.transparent);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: PressScale(
        scale: 0.9,
        child: SizedBox.square(
          dimension: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface,
                    shape: BoxShape.circle,
                    boxShadow: AknShadows.card(c),
                    border: c.isDark ? Border.all(color: c.line) : null,
                  ),
                  child: const SizedBox.square(dimension: 40),
                ),
              ),
              ActionIconTheme(
                data: ActionIconThemeData(
                  backButtonIconBuilder: (context) => Icon(
                    PhosphorIconsRegular.arrowLeft,
                    size: 22,
                    semanticLabel: _androidLabel(context, back: true),
                  ),
                  closeButtonIconBuilder: (context) => Icon(
                    PhosphorIconsRegular.x,
                    size: 22,
                    semanticLabel: _androidLabel(context, back: false),
                  ),
                ),
                child: IconButtonTheme(
                  data: IconButtonThemeData(
                    style: ButtonStyle(
                      iconSize: const WidgetStatePropertyAll<double>(22),
                      minimumSize: const WidgetStatePropertyAll<Size>(
                        Size(48, 48),
                      ),
                      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                        EdgeInsets.zero,
                      ),
                      foregroundColor: WidgetStatePropertyAll<Color>(c.ink),
                      iconColor: WidgetStatePropertyAll<Color>(c.ink),
                      backgroundColor: transparent,
                      overlayColor: transparent,
                      shape: const WidgetStatePropertyAll<OutlinedBorder>(
                        CircleBorder(),
                      ),
                      side: WidgetStateProperty.resolveWith(
                        (s) => s.contains(WidgetState.focused)
                            ? AknTheme.focusRing(c)
                            : null,
                      ),
                      splashFactory: NoSplash.splashFactory,
                    ),
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fades and slides the offline line down from under the bar (and back up)
/// while its own size animates.
class _BannerReveal extends StatelessWidget {
  const _BannerReveal({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: visible ? 1 : 0),
      duration: AknMotion.of(context, AknMotion.slow),
      curve: AknMotion.emphasizedCurve,
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, -14 * (1 - v)),
          child: child,
        ),
      ),
    );
  }
}

/// The header's shadow cast on the content under it: the shadow of a
/// header-wide shape whose lower corners are [radius] (the band's), strength
/// and depth growing over the first 56 px of scroll. Paint-only.
class _TopShadowPainter extends CustomPainter {
  _TopShadowPainter({
    required this.offset,
    required this.color,
    required this.radius,
  }) : super(repaint: offset);

  final ValueListenable<double> offset;
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final p = AknMotion.standard.transform((offset.value / 56).clamp(0.0, 1.0));
    if (p <= 0) return;
    final shadow = BoxShadow(
      color: color.withValues(alpha: color.a * p),
      offset: Offset(0, 3 + 7 * p),
      blurRadius: 12 + 16 * p,
      spreadRadius: -8 + 2 * p,
    );
    final r = Radius.circular(radius);
    final shape = RRect.fromLTRBAndCorners(
      0,
      -120,
      size.width,
      0,
      bottomLeft: r,
      bottomRight: r,
    );
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..drawRRect(
        shape.shift(shadow.offset).inflate(shadow.spreadRadius),
        shadow.toPaint(),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_TopShadowPainter old) =>
      old.offset != offset || old.color != color || old.radius != radius;
}

/// Geniş ekranlarda içeriği [maxWidth] ile sınırlar ve ortalar (telefonda etkisiz).
class ContentMaxWidth extends StatelessWidget {
  const ContentMaxWidth({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!constraints.hasBoundedWidth || constraints.maxWidth <= maxWidth) {
        return child;
      }
      return Center(
        child: SizedBox(width: maxWidth, child: child),
      );
    },
  );
}

/// The sticky dock for a screen's primary actions (v3 §4): the bottom bar's
/// frosted surface — `surfaceRaised` at 92 % over a σ 20 blur — lifted by
/// [AknShadows.bar], no hairline (dark: a faint top edge); padding 12/20
/// plus the safe area. When the dock first appears its actions rise into
/// place (fade + 16 px, [AknMotion.sheet], emphasized). One primary region
/// per screen.
///
/// v4: [ActionBar.decision] builds the decision dock (one 52 dp primary,
/// an optional caption, a row of borderless 48 dp ghosts).
class ActionBar extends StatelessWidget {
  const ActionBar({super.key, required this.child});

  /// The decision dock (design v4 §4): the [primary] full width at 52 dp —
  /// it must be enabled (P3: the next real step, never a dead button;
  /// asserted in debug) — an optional [caption] 13/18 dim under it, then
  /// the [secondaries] in one row of borderless 48 dp ghosts 12 apart (a
  /// `danger` secondary, "Reddet", keeps its `danger.fg` label). The
  /// primary's label morphs when the step changes ("Çek görselini yükle" →
  /// "Teklifi onayla"; pass `celebrate: true` for the check pop).
  ///
  /// ```dart
  /// AppScaffold(
  ///   actionBar: ActionBar.decision(
  ///     primary: AknButton(label: 'Çek görselini yükle', onPressed: upload),
  ///     caption: 'Yükledikten sonra teklifi onaylayabilirsiniz',
  ///     secondaries: [
  ///       AknButton.ghost(label: 'Revize iste', onPressed: revise),
  ///       AknButton.danger(label: 'Reddet', onPressed: reject),
  ///     ],
  ///   ),
  /// )
  /// ```
  factory ActionBar.decision({
    Key? key,
    required AknButton primary,
    String? caption,
    List<AknButton> secondaries = const [],
  }) {
    assert(
      primary.onPressed != null || primary.onPressedAsync != null,
      'ActionBar.decision: the primary names a step the viewer can take now '
      '(v4 P3); turn a missing prerequisite into the primary instead of '
      'disabling it.',
    );
    return ActionBar(
      key: key,
      child: _DecisionDock(
        primary: primary,
        caption: caption,
        secondaries: secondaries,
      ),
    );
  }

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Alttaki sistem gezinme çubuğu simgeleri yüzeye göre.
      value: AknTheme.overlayFor(c.brightness),
      child: DecoratedBox(
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
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  // The bar sizes to its content: an expanded button (or a
                  // Row of them) placed here directly never stretches to the
                  // screen height.
                  child: FadeUp(
                    offset: 16,
                    duration: AknMotion.sheet,
                    curve: AknMotion.emphasizedCurve,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [child],
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

/// The body of [ActionBar.decision].
class _DecisionDock extends StatelessWidget {
  const _DecisionDock({
    required this.primary,
    required this.caption,
    required this.secondaries,
  });

  final AknButton primary;
  final String? caption;
  final List<AknButton> secondaries;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final p = primary;
    final main = AknButton(
      key: p.key,
      label: p.label,
      onPressed: p.onPressed,
      onPressedAsync: p.onPressedAsync,
      size: AknButtonSize.large,
      icon: p.icon,
      trailingIcon: p.trailingIcon,
      loading: p.loading,
      success: p.success,
      showSuccess: p.showSuccess,
      expand: true,
      haptic: p.haptic,
      semanticLabel: p.semanticLabel,
      loadingLabel: p.loadingLabel,
      celebrate: p.celebrate,
    );
    final cap = caption;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        main,
        if (cap != null && cap.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            cap,
            textAlign: TextAlign.center,
            style: t.label.copyWith(fontWeight: FontWeight.w500, color: c.dim),
          ),
        ],
        if (secondaries.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < secondaries.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: _ghost(secondaries[i])),
              ],
            ],
          ),
        ],
      ],
    );
  }

  static AknButton _ghost(AknButton b) => AknButton(
    key: b.key,
    label: b.label,
    onPressed: b.onPressed,
    onPressedAsync: b.onPressedAsync,
    variant:
        b.variant == AknButtonVariant.danger ||
            b.variant == AknButtonVariant.ghostDanger
        ? AknButtonVariant.ghostDanger
        : AknButtonVariant.ghost,
    size: AknButtonSize.medium,
    icon: b.icon,
    loading: b.loading,
    success: b.success,
    showSuccess: b.showSuccess,
    expand: true,
    haptic: b.haptic,
    semanticLabel: b.semanticLabel,
    loadingLabel: b.loadingLabel,
  );
}

/// One clause of a page band's status line (design v4 §3.2): the viewer's
/// move in Pas 600 ([AknStatusClause.yourMove]), the overdue part in
/// `danger.fg` 600 ([AknStatusClause.overdue]), the rest dim. Clauses are
/// joined with " · ".
///
/// ```dart
/// AppScaffold(
///   title: 'Onaylar',
///   status: const [
///     AknStatusClause.yourMove('9 talep kararınızı bekliyor'),
///     AknStatusClause.overdue("2'si gecikti"),
///   ],
///   …
/// )
/// ```
@immutable
class AknStatusClause {
  const AknStatusClause(this.text, {this.tone});

  /// The viewer's move (Pas 600).
  const AknStatusClause.yourMove(this.text) : tone = AknTone.brand;

  /// Overdue (`danger.fg` 600).
  const AknStatusClause.overdue(this.text) : tone = AknTone.danger;

  final String text;

  /// [AknTone.brand], [AknTone.danger]; anything else is dim.
  final AknTone? tone;
}

/// The web panel's page band (`.page-hero`) on a mobile root page — design
/// v4 §4 "AknPageBand v4": a card with the 90° wash `brandInk` 8 % → 3 % →
/// surface and a 1 px line tinted 14 % toward `brandInk` (dark: a flat 4 %
/// tint and a 10 % line), radius 16; the tab's own glyph ([icon], the same
/// as in the bar) in Pas on a 36 dp white tile; the [title] 20/24 700 ink —
/// the tab's word, the page's header for screen readers — and ONE [status]
/// line 13/18 that says what waits ([AknStatusClause]s, a String with a
/// [statusTone], or an `InlineSpan`); at most two [actions]
/// (`AknIconButton`s) at the right. No eyebrow ([eyebrow] is ignored) and
/// no bell. ≈ 66 dp tall (plus [margin] above and below). A new status line
/// fades through (250 ms). Text grows up to [maxTextScale].
class AknPageBand extends StatelessWidget {
  const AknPageBand({
    super.key,
    required this.icon,
    required this.title,
    this.eyebrow,
    this.description,
    this.actions = const [],
    this.status,
    this.statusTone,
    this.onStatusTap,
  });

  final IconData icon;
  final String title;

  /// Ignored (v4: no eyebrow).
  final String? eyebrow;

  /// Kept for old call sites: the status line when [status] is null.
  final String? description;

  /// At most two `AknIconButton`s (search, filter).
  final List<Widget> actions;

  /// The live status line: a `String`, an `InlineSpan`, an
  /// [AknStatusClause] or a `List<AknStatusClause>`.
  final Object? status;

  /// The tone of a String [status] (brand: Pas 600, danger: `danger.fg`
  /// 600; else dim).
  final AknTone? statusTone;

  /// Tapping the status line (e.g. the overdue clause scrolls to
  /// "Gecikmiş").
  final VoidCallback? onStatusTap;

  /// Space above and below the band inside the bar.
  static const double margin = 8;

  /// The band's texts clamp at 1.5× (like the root titles).
  static const double maxTextScale = 1.5;

  static const double _padding = 8;
  static const double _tile = 36;

  /// The status the band shows ([status], else [description]).
  Object? get _line => status ?? description;

  /// The band's height (border included) at [scaler]; [description] means
  /// "has a status line". [eyebrow] is ignored (v4).
  static double heightFor(
    TextScaler scaler, {
    bool eyebrow = false,
    bool description = true,
  }) {
    final s = scaler.clamp(maxScaleFactor: maxTextScale);
    final lines =
        s.scale(20) * 24 / 20 + (description ? s.scale(13) * 18 / 13 : 0);
    return math.max(lines, AknSpace.minTap) + _padding * 2 + 2;
  }

  /// The plain text of a status value (tests, semantics, switch keys).
  static String plainStatus(Object? status) => switch (status) {
    null => '',
    final String s => s,
    final InlineSpan span => span.toPlainText(),
    final AknStatusClause c => c.text,
    final List<AknStatusClause> l => l.map((c) => c.text).join(' · '),
    _ => '$status',
  };

  /// The status value as a span in palette [c].
  static InlineSpan statusSpan(
    AknColors c,
    AknTextStyles t,
    Object status, {
    AknTone? tone,
  }) {
    final base = t.label.copyWith(fontWeight: FontWeight.w500, color: c.dim);
    TextStyle styleOf(AknTone? tn) => switch (tn) {
      AknTone.brand => base.copyWith(
        fontWeight: FontWeight.w600,
        color: c.brandInk,
      ),
      AknTone.danger => base.copyWith(
        fontWeight: FontWeight.w600,
        color: c.danger.fg,
      ),
      _ => base,
    };
    return switch (status) {
      final String s => TextSpan(text: s, style: styleOf(tone)),
      final InlineSpan span => TextSpan(style: base, children: [span]),
      final AknStatusClause cl => TextSpan(
        text: cl.text,
        style: styleOf(cl.tone),
      ),
      final List<AknStatusClause> l => TextSpan(
        style: base,
        children: [
          for (var i = 0; i < l.length; i++) ...[
            if (i > 0) const TextSpan(text: ' · '),
            TextSpan(text: l[i].text, style: styleOf(l[i].tone)),
          ],
        ],
      ),
      _ => TextSpan(text: '$status', style: base),
    };
  }

  /// The band's card: the 90° wash `brandInk` 8 % → 3 % → surface and a
  /// 1 px line tinted 14 % toward `brandInk` (at night a flat 4 % tint and a
  /// 10 % line), radius 16.
  static BoxDecoration decorationOf(AknColors c) => BoxDecoration(
    borderRadius: const BorderRadius.all(Radius.circular(16)),
    border: Border.all(
      color: Color.lerp(c.line, c.brandInk, c.isDark ? 0.10 : 0.14)!,
    ),
    color: c.isDark ? Color.lerp(c.surface, c.brandInk, 0.04) : null,
    gradient: c.isDark
        ? null
        : LinearGradient(
            colors: [
              Color.lerp(c.surface, c.brandInk, 0.08)!,
              Color.lerp(c.surface, c.brandInk, 0.03)!,
              c.surface,
            ],
            stops: const [0, 0.55, 1],
          ),
  );

  /// The band's 36 dp icon tile: white, a 22 % tinted line, a Pas glyph.
  /// Decorative.
  static Widget tileOf(BuildContext context, IconData icon) {
    final c = context.akn;
    return ExcludeSemantics(
      child: Container(
        width: _tile,
        height: _tile,
        decoration: BoxDecoration(
          color: c.isDark ? c.surfaceAlt : c.surface,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          border: Border.all(color: Color.lerp(c.line, c.brandInk, 0.22)!),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: c.brandInk),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final line = _line;
    final plain = plainStatus(line);
    Widget? statusText;
    if (line != null && plain.isNotEmpty) {
      statusText = Text.rich(
        statusSpan(c, t, line, tone: status == null ? null : statusTone),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      if (onStatusTap != null) {
        statusText = Semantics(
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onStatusTap,
            child: statusText,
          ),
        );
      }
      // A new status line fades through (v4 §6 Add 6).
      statusText = FadeThroughSwitcher(
        duration: AknMotion.statusFade,
        alignment: AlignmentDirectional.centerStart,
        child: KeyedSubtree(key: ValueKey(plain), child: statusText),
      );
    }
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.title.copyWith(height: 24 / 20, color: c.ink),
          ),
        ),
        ?statusText,
      ],
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxTextScale,
      child: DecoratedBox(
        decoration: decorationOf(c),
        // Keep the title (header) and every action its own node.
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            10,
            _padding,
            actions.isEmpty ? 14 : 2,
            _padding,
          ),
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AknSpace.minTap),
              child: Row(
                children: [
                  tileOf(context, icon),
                  const SizedBox(width: 12),
                  Expanded(child: text),
                  ...actions,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
