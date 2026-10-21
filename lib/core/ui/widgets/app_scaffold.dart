import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../driver_mode.dart';
import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
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
  });

  final int unreadCount;
  final VoidCallback? onOpenNotifications;
  final bool offline;
  final int pendingOps;
  final VoidCallback? onOpenPendingOps;

  static AppChrome? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppChrome>();

  @override
  bool updateShouldNotify(AppChrome old) =>
      old.unreadCount != unreadCount ||
      old.onOpenNotifications != onOpenNotifications ||
      old.offline != offline ||
      old.pendingOps != pendingOps ||
      old.onOpenPendingOps != onOpenPendingOps;
}

/// The bell (design v2 §6.3): `notifications_none_rounded` 24 in ink with an
/// Asfalt count badge (dark: a light badge), from [AppChrome]. Hidden when
/// the shell provides no notifications callback.
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
      icon: Icons.notifications_none_rounded,
      semanticLabel: 'Bildirimler',
      badgeCount: unread,
      badgeSemantics: (n) => '$n okunmamış',
      color: color,
      onPressed: chrome.onOpenNotifications,
    );
  }
}

/// Page scaffold (design v2 §6.1): the bar, the offline line under it, a
/// refresh bar that keeps content visible, and a sticky [actionBar].
///
/// * **Home** ([homeHeader], e.g. [AknHomeHeader]): with an [AknHomeHeader]
///   (owner decision G) the pinned orange gradient band behind the status
///   bar (light icons; avatar, greeting, company, bell in white), its soft
///   orange shadow once content scrolls under it, and the page in `homeBg`
///   (#F9FAFB). The home's hero card joins the band through
///   [AknBandOverlap]. Any other header widget sits on the page colour.
/// * **Root tab pages** (no back button: Siparişlerim, Onaylarım, Teklif
///   masası …): 60 px bar, the title in `display` 30/36 left at 20, 44 px
///   ink action buttons (and the bell).
/// * **Pushed pages**: 52 px bar, the platform back button, the title in
///   `headline` 17/22 600 (one line), actions on the right. Object pages then
///   start the body with a `display` title.
/// * The bar is the page colour (white; dark #16191D). A hairline appears
///   only after content scrolls under it — no shadow, no orange strip.
///   [largeTitle] overrides the root / pushed detection.
/// * [hero] / [navy] are deprecated and render the normal white bar.
class AppScaffold extends StatefulWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.actions = const [],
    this.showBell = true,
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
  });

  final Widget body;
  final String? title;
  final Widget? titleWidget;
  final String? subtitle;
  final List<Widget> actions;

  /// Shows the bell when [AppChrome] provides a notifications callback.
  final bool showBell;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  /// Under the bar (e.g. a `TabBar`).
  final PreferredSizeWidget? bottom;

  /// Sticky bottom area for the screen's primary actions ([ActionBar]).
  final Widget? actionBar;
  final Widget? floatingActionButton;

  /// Deprecated: the orange header strip is gone; renders the white bar.
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

  /// The home header (§6.2), pinned in place of the app bar.
  final Widget? homeHeader;

  /// Forces the root (`display` title, 60 px) or pushed (`headline`, 52 px)
  /// bar; null detects it from the route (a back button means pushed).
  final bool? largeTitle;

  /// Deprecated: always false visually (kept for API stability).
  bool get isHero => hero || navy;

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  bool _scrolled = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final scrolled = n.metrics.extentBefore > 0.5;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    return false;
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
      final root = widget.largeTitle ?? !canGoBack;
      final scaler = MediaQuery.textScalerOf(context);
      final t = context.aknText;
      final driver = context.isDriverMode;
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
      bar = _AknAppBar(
        root: root,
        toolbarHeight: toolbar,
        titleScale: titleScale,
        scrolled: _scrolled,
        title: widget.title,
        titleWidget: widget.titleWidget,
        subtitle: widget.subtitle,
        leading: widget.leading,
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
        ? OfflineBanner(
            offline: chrome.offline,
            pendingCount: chrome.pendingOps,
            onTap: chrome.onOpenPendingOps,
          )
        : null;

    final content = Column(
      children: [
        if (home != null && band)
          home
        else if (home != null)
          ColoredBox(
            color: pageColor,
            child: SafeArea(
              bottom: false,
              child: _ScrollEdge(
                visible: _scrolled,
                duration: AknMotion.of(context, AknMotion.base),
                child: home,
              ),
            ),
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
              // The band's soft orange shadow (0 6 14 rgba(232,89,12,.22))
              // over the content once it scrolls under the band.
              if (band)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 14,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _scrolled ? 1 : 0,
                      duration: AknMotion.of(context, AknMotion.base),
                      curve: AknMotion.standard,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              c.isDark
                                  ? const Color(0x59000000)
                                  : const Color(0x38E8590C),
                              c.isDark
                                  ? const Color(0x00000000)
                                  : const Color(0x00E8590C),
                            ],
                          ),
                        ),
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
      bottomNavigationBar: widget.actionBar == null
          ? null
          : ActionBar(child: widget.actionBar!),
    );
    // System bars follow the page surface (dark icons on white, light on the
    // dark page).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AknTheme.overlayFor(c.brightness),
      child: scaffold,
    );
  }
}

/// The scaffold's app bar: the page colour, a root (`display`) or pushed
/// (`headline`) title, a hairline once content scrolls under it.
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
  });

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
      titleBlock = MediaQuery.withClampedTextScaling(
        maxScaleFactor: titleScale,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title!,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
    final appBar = AppBar(
      toolbarHeight: toolbarHeight,
      title: titleBlock == null
          ? null
          : Semantics(header: true, child: titleBlock),
      centerTitle: false,
      titleSpacing: leading == null && root ? AknSpace.page : 0,
      leading: leading,
      leadingWidth: 52,
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: background,
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
    );
    return _ScrollEdge(
      visible: scrolled && bottom == null,
      duration: AknMotion.of(context, AknMotion.base),
      child: appBar,
    );
  }
}

/// The hairline under a bar while content is scrolled under it (fades in
/// and out). No shadow.
class _ScrollEdge extends StatelessWidget {
  const _ScrollEdge({
    required this.visible,
    required this.duration,
    required this.child,
  });

  final bool visible;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: duration,
              curve: AknMotion.standard,
              child: SizedBox(
                height: 1,
                width: double.infinity,
                child: ColoredBox(color: c.line),
              ),
            ),
          ),
        ),
      ],
    );
  }
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

/// The sticky dock for a screen's primary actions (§6.1): `surfaceRaised`
/// (dark: `surface`) with a 1 px hairline on top, padding 12/20 plus the
/// safe area, no shadow. One primary region per screen.
class ActionBar extends StatelessWidget {
  const ActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Alttaki sistem gezinme çubuğu simgeleri yüzeye göre.
      value: AknTheme.overlayFor(c.brightness),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.isDark ? c.surface : c.surfaceRaised,
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            // The bar sizes to its content: an expanded button (or a Row of
            // them) placed here directly never stretches to the screen height.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [child],
            ),
          ),
        ),
      ),
    );
  }
}
