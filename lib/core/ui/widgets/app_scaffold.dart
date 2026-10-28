import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
/// * [hero] / [navy] are deprecated and render the normal bar.
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
      bottomNavigationBar: widget.actionBar == null
          ? null
          : ActionBar(child: widget.actionBar!),
    );
    // System bars follow the page surface (dark icons on the light page,
    // light on the dark page).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AknTheme.overlayFor(c.brightness),
      child: scaffold,
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
    final circled = lead is IconButton || lead is AknIconButton;
    if (lead != null && circled) lead = _BarLeading(child: lead);
    final titled = titleBlock == null
        ? null
        : Semantics(header: true, child: titleBlock);

    return _FrostedTop(
      frosted: scrolled,
      page: background,
      builder: (context, fill) => AppBar(
        toolbarHeight: toolbarHeight,
        title: titled,
        centerTitle: false,
        titleSpacing: lead == null ? AknSpace.page : (circled ? 8 : 0),
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
