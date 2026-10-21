import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../tokens.dart';
import 'buttons.dart';
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

/// App-bar bell with the unread badge (from [AppChrome]).
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
/// [navy] gives the app bar the navy identity (home screens, status heroes;
/// pair with `AknHeroPanel` directly under it).
class AppScaffold extends StatelessWidget {
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
  final bool navy;

  /// Background refresh in progress: thin bar at the top, content stays.
  final bool refreshing;
  final bool showOfflineBanner;
  final Color? backgroundColor;
  final bool resizeToAvoidBottomInset;

  /// False for screens that draw their own header.
  final bool appBar;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final chrome = AppChrome.maybeOf(context);
    final onNavy = navy;
    final fg = onNavy ? c.onNavy : c.ink;

    Widget? titleBlock = titleWidget;
    if (titleBlock == null && title != null) {
      titleBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title!,
            style: t.headline.copyWith(color: fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: t.caption.copyWith(color: onNavy ? c.onNavyDim : c.dim),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      );
    }

    final PreferredSizeWidget? bar = !appBar
        ? null
        : AppBar(
            title: titleBlock == null
                ? null
                : Semantics(header: true, child: titleBlock),
            leading: leading,
            automaticallyImplyLeading: automaticallyImplyLeading,
            backgroundColor: onNavy ? c.navy : null,
            foregroundColor: onNavy ? c.onNavy : null,
            scrolledUnderElevation: onNavy ? 0 : null,
            systemOverlayStyle: onNavy
                ? AknTheme.overlayOnNavy
                : AknTheme.overlayFor(c.brightness),
            iconTheme: onNavy ? IconThemeData(color: c.onNavy) : null,
            actionsIconTheme: onNavy ? IconThemeData(color: c.onNavy) : null,
            actions: [
              ...actions,
              if (showBell) NotificationBell(color: onNavy ? c.onNavy : null),
              const SizedBox(width: 4),
            ],
            bottom: bottom,
          );

    final banner = showOfflineBanner && chrome != null
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
              // Geniş ekranda (tablet, yatay) içerik en fazla 640 dp (spec D.7).
              Positioned.fill(child: ContentMaxWidth(child: body)),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: TopProgressBar(active: refreshing),
              ),
            ],
          ),
        ),
      ],
    );

    final scaffold = Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: bar,
      floatingActionButton: floatingActionButton,
      body: content,
      bottomNavigationBar: actionBar == null
          ? null
          : ActionBar(child: actionBar!),
    );
    // Uygulama çubuğu olmayan ekranda durum çubuğu simgeleri yüzeye göre (kenardan kenara).
    return appBar
        ? scaffold
        : AnnotatedRegion<SystemUiOverlayStyle>(
            value: AknTheme.overlayFor(c.brightness),
            child: scaffold,
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

/// Raised bottom area for a screen's primary actions (safe-area aware).
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
          border: Border(top: BorderSide(color: c.line)),
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
