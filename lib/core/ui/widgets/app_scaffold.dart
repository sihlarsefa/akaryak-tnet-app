import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion.dart';
import '../painters/hero_backdrop.dart';
import '../theme.dart';
import '../tokens.dart';
import 'buttons.dart';
import 'cards.dart';
import 'skeletons.dart';
import 'states.dart';

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

/// App-bar bell with the unread badge (from [AppChrome]). White on the hero
/// app bar (it reads the on-hero theme).
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
      icon: unread > 0
          ? Icons.notifications_rounded
          : Icons.notifications_none_rounded,
      semanticLabel: 'Bildirimler',
      badgeCount: unread,
      badgeSemantics: (n) => '$n okunmamış',
      color: color,
      onPressed: chrome.onOpenNotifications,
    );
  }
}

/// Page scaffold: app bar (title + optional subtitle, actions, the bell),
/// offline banner, a refresh progress bar that keeps content visible, and a
/// bottom action bar for primary actions.
///
/// * Default: a white app bar with an ink title (left, w800); a hairline and
///   a soft shadow fade in once content scrolls under it. Dark status-bar
///   icons in light mode, light icons in dark mode.
/// * [hero]: the orange header strip — the app bar runs under the status bar
///   in the hero gradient with light status icons, a white title, white
///   actions and a white bell. Put an `AknHeroHeader` first in the body to
///   continue the strip (greeting, subtitle, chips) without a seam.
/// * [navy] is the old name of [hero] (kept so existing screens compile).
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

  /// Under the app bar (e.g. a `TabBar`).
  final PreferredSizeWidget? bottom;

  /// Bottom bar for the screen's primary actions (on a raised surface).
  final Widget? actionBar;
  final Widget? floatingActionButton;

  /// Orange header strip (home screens, status heroes).
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

  bool get isHero => hero || navy;

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  bool _scrolled = false;

  /// Top overscroll (iOS bounce) under a hero bar: filled with the strip so
  /// pulling down never opens a grey gap between the bar and the header.
  final ValueNotifier<double> _overscroll = ValueNotifier<double>(0);

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final m = n.metrics;
    final scrolled = m.extentBefore > 0.5;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    if (widget.isHero && m.hasPixels && m.hasContentDimensions) {
      final over = m.minScrollExtent - m.pixels;
      _overscroll.value = over > 0 ? over : 0;
    }
    return false;
  }

  @override
  void dispose() {
    _overscroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final chrome = AppChrome.maybeOf(context);
    final hero = widget.isHero;

    final PreferredSizeWidget? bar = !widget.appBar
        ? null
        : _AknAppBar(
            hero: hero,
            scrolled: _scrolled,
            refreshing: widget.refreshing,
            title: widget.title,
            titleWidget: widget.titleWidget,
            subtitle: widget.subtitle,
            leading: widget.leading,
            automaticallyImplyLeading: widget.automaticallyImplyLeading,
            actions: [
              ...widget.actions,
              if (widget.showBell) const NotificationBell(),
              const SizedBox(width: 4),
            ],
            bottom: widget.bottom,
          );

    final banner = widget.showOfflineBanner && chrome != null
        ? OfflineBanner(
            offline: chrome.offline,
            pendingCount: chrome.pendingOps,
            onTap: chrome.onOpenPendingOps,
          )
        : null;

    final content = Column(
      children: [
        ?banner,
        Expanded(
          child: Stack(
            children: [
              if (hero && widget.appBar)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _overscroll,
                    builder: (context, over, _) => SizedBox(
                      height: over,
                      child: over <= 0
                          ? null
                          : const AknHeroBackground(
                              style: AknHeroStyle.strip,
                              watermark: false,
                              highlight: false,
                            ),
                    ),
                  ),
                ),
              // Geniş ekranda (tablet, yatay) içerik en fazla 640 dp (spec D.7).
              Positioned.fill(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: ContentMaxWidth(child: widget.body),
                ),
              ),
              // The hero bar shows its own (white) refresh bar.
              if (!hero || !widget.appBar)
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
      backgroundColor: widget.backgroundColor,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      appBar: bar,
      floatingActionButton: widget.floatingActionButton,
      body: content,
      bottomNavigationBar: widget.actionBar == null
          ? null
          : ActionBar(child: widget.actionBar!),
    );
    // System bars follow the page surface (the app bar sets the status bar
    // for its own area; this region covers the rest, incl. the nav bar).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AknTheme.overlayFor(c.brightness),
      child: scaffold,
    );
  }
}

/// The scaffold's app bar: white (hairline + soft shadow once scrolled) or
/// the orange hero strip.
class _AknAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AknAppBar({
    required this.hero,
    required this.scrolled,
    required this.refreshing,
    required this.title,
    required this.titleWidget,
    required this.subtitle,
    required this.leading,
    required this.automaticallyImplyLeading,
    required this.actions,
    required this.bottom,
  });

  final bool hero;
  final bool scrolled;
  final bool refreshing;
  final String? title;
  final Widget? titleWidget;
  final String? subtitle;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final duration = AknMotion.of(context, AknMotion.base);
    final appBar = Builder(
      builder: (context) {
        final c = context.akn;
        final t = context.aknText;
        Widget? titleBlock = titleWidget;
        if (titleBlock == null && title != null) {
          titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title!,
                style: AknTheme.appBarTitle(t).copyWith(color: c.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: t.caption.copyWith(color: c.dim),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          );
        }
        return AppBar(
          title: titleBlock == null
              ? null
              : Semantics(header: true, child: titleBlock),
          leading: leading,
          automaticallyImplyLeading: automaticallyImplyLeading,
          backgroundColor: hero ? const Color(0x00000000) : c.surface,
          foregroundColor: c.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: const Color(0x00000000),
          systemOverlayStyle: hero
              ? AknTheme.overlayOnHero
              : AknTheme.overlayFor(c.brightness),
          flexibleSpace: hero
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    const AknHeroBackground(
                      style: AknHeroStyle.strip,
                      watermark: false,
                      highlight: false,
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: TopProgressBar(active: refreshing),
                    ),
                  ],
                )
              : null,
          actions: actions,
          bottom: bottom,
        );
      },
    );
    if (hero) {
      return _ScrollEdge(
        visible: scrolled,
        hero: true,
        duration: duration,
        child: OnHero(child: appBar),
      );
    }
    return _ScrollEdge(
      visible: scrolled,
      hero: false,
      duration: duration,
      child: appBar,
    );
  }
}

/// Hairline + soft shadow under the app bar while content is scrolled under
/// it (fades in and out).
class _ScrollEdge extends StatelessWidget {
  const _ScrollEdge({
    required this.visible,
    required this.hero,
    required this.duration,
    required this.child,
  });

  final bool visible;
  final bool hero;
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
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  color: hero ? const Color(0x00000000) : c.line,
                  boxShadow: [
                    BoxShadow(
                      color: c.isDark
                          ? const Color(0x66000000)
                          : hero
                          ? const Color(0x29101828)
                          : const Color(0x14101828),
                      offset: const Offset(0, 3),
                      blurRadius: 10,
                    ),
                  ],
                ),
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

/// Raised bottom area for a screen's primary actions (safe-area aware): white
/// with a hairline and a soft upward shadow.
class ActionBar extends StatelessWidget {
  const ActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Alttaki sistem gezinme çubuğu simgeleri yükseltilmiş yüzeye göre.
      value: AknTheme.overlayFor(c.brightness),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          border: Border(top: BorderSide(color: c.lineSoft)),
          boxShadow: AknShadows.bar(c),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
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
