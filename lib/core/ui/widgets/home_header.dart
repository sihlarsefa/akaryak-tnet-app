import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../utils/turkish_text.dart';
import '../motion.dart';
import '../painters/hero_backdrop.dart';
import '../painters/logo_mark.dart';
import '../theme.dart';
import '../tokens.dart';
import 'app_scaffold.dart' show AppChrome, NotificationBell;

/// The home header of every role (owner decision G, design v3 §4): a
/// **luminous orange band** — the 135° gradient `heroStart` → `heroMid` →
/// `heroEnd` lit by a drifting `heroGlow` light at the top-left, a warm
/// white light at the bottom-right and a soft sweep of light now and then
/// ([AknBand]) — that starts behind the status bar (light status icons) and
/// carries, in white, a 46 px glass avatar with the initial, the greeting
/// ("İyi akşamlar, Elif", 17/22 w800) over the company or station (13/18
/// w500, white 92 %), and the bell (plus any [actions], e.g. the assistant)
/// in 44 px glass circles ([AknBandSquare]).
///
/// ```
/// (E)  İyi akşamlar, Elif                          (🔔)
///      Anadolu Lojistik A.Ş.
/// ```
///
/// Motion (v3 §5): the content enters once (the avatar pops, the names fade
/// up 8 px in 240 ms, the glass buttons pop after them); the lights drift
/// through [AknAmbient]; while the page scrolls under the band the greeting
/// row eases up and back slightly. A band with no hero card on it rounds its
/// bottom corners (28) — the corners square again as soon as an
/// [AknBandOverlap] joins it.
///
/// Put it in `AppScaffold(homeHeader: AknHomeHeader(...))`: the scaffold pins
/// the band at the top (it casts its soft orange shadow once content scrolls
/// under it) and paints the page in `homeBg`. To pull the screen's hero card
/// up onto the band — the first card overlaps it by [overlap] (48) px — make
/// it the first item of the list inside [AknBandOverlap]:
///
/// ```dart
/// ListView(children: [
///   AknBandOverlap(child: MonthPlate(...)),   // the card sits on the band
///   ...
/// ])
/// ```
///
/// The greeting is built from the time of day ([now]) and the first name
/// ([name], or the part of [person] before the comma); [greeting] overrides
/// it. Screen readers hear one header: greeting, company and [person]
/// ("Elif Kaya, yönetici"). With [onOpenProfile] the avatar and names are
/// one ≥ 48 px button. At text scale ≥ 1.6 the lines wrap to two.
///
/// [band] false keeps the plain page-coloured bar (logo tile, company over
/// the person line) for old call sites.
class AknHomeHeader extends StatelessWidget {
  const AknHomeHeader({
    super.key,
    required this.company,
    this.person,
    this.onOpenProfile,
    this.actions = const [],
    this.showBell = true,
    this.profileHint = 'Profili açar',
    this.greeting,
    this.name,
    this.now,
    this.band = true,
  });

  /// "Demir Petrol Akaryakıt Ltd. Şti." — the second line on the band.
  final String company;

  /// "Mehmet Demir, bayi sahibi": read by screen readers; its name part
  /// gives the greeting and the avatar initial.
  final String? person;
  final VoidCallback? onOpenProfile;

  /// Extra icon buttons before the bell (each sits in a 44 px glass circle
  /// on the band; `AknIconButton` icons turn white by themselves).
  final List<Widget> actions;
  final bool showBell;

  /// Screen-reader hint of the names when [onOpenProfile] is set.
  final String profileHint;

  /// Overrides the greeting line ("İyi akşamlar, Elif").
  final String? greeting;

  /// The person's name for the greeting and the avatar initial (default:
  /// [person] up to the first comma).
  final String? name;

  /// Clock for the greeting (tests); default now.
  final DateTime? now;

  /// The orange band (owner decision G). False: the plain page bar.
  final bool band;

  /// The plain bar's height at 1.0× text ([band] false).
  static const double height = 62;

  /// The band's height under the status bar at 1.0× text: 10 + 48 + 22.
  static const double bandHeight = 80;

  /// How far the first card overlaps the band ([AknBandOverlap]).
  static const double overlap = 48;

  /// "Günaydın" (until 12), "İyi günler" (until 18), "İyi akşamlar".
  static String timeGreeting(DateTime now) {
    final h = now.hour;
    if (h < 12) return 'Günaydın';
    if (h < 18) return 'İyi günler';
    return 'İyi akşamlar';
  }

  /// The name part of [person] ("Elif Kaya, yönetici" → "Elif Kaya").
  static String nameOf(String? person) {
    final p = person?.trim() ?? '';
    if (p.isEmpty) return '';
    final i = p.indexOf(',');
    return (i < 0 ? p : p.substring(0, i)).trim();
  }

  String get _name {
    final n = name?.trim() ?? '';
    return n.isNotEmpty ? n : nameOf(person);
  }

  /// The greeting line as shown ("İyi akşamlar, Elif").
  String greetingText([DateTime? at]) {
    final g = greeting;
    if (g != null && g.isNotEmpty) return g;
    final first = _name.split(RegExp(r'\s+')).first;
    final hello = timeGreeting(at ?? now ?? DateTime.now());
    return first.isEmpty ? hello : '$hello, $first';
  }

  @override
  Widget build(BuildContext context) =>
      band ? _HomeBand(header: this) : _HomeBar(header: this);
}

/// The band of [AknHomeHeader]: entrance, scroll reaction and the
/// stand-alone corners.
class _HomeBand extends StatefulWidget {
  const _HomeBand({required this.header});

  final AknHomeHeader header;

  @override
  State<_HomeBand> createState() => _HomeBandState();
}

class _HomeBandState extends State<_HomeBand>
    with SingleTickerProviderStateMixin {
  /// The one-time entrance: avatar pop, names fade up, buttons pop.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );

  /// How far the page has scrolled under the band (0–1 over [_scrollSpan]).
  final ValueNotifier<double> _scroll = ValueNotifier<double>(0);
  static const double _scrollSpan = 72;

  ScrollController? _primary;
  Object? _tailKey;

  /// True once no [AknBandOverlap] sits on this band: rounded corners.
  bool _alone = false;
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    _BandTails.changes.addListener(_syncAlone);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_entered) {
      _entered = true;
      if (AknMotion.reduced(context)) {
        _enter.value = 1;
      } else {
        _enter.forward();
      }
    }
    final primary = PrimaryScrollController.maybeOf(context);
    if (!identical(primary, _primary)) {
      _primary?.removeListener(_onScroll);
      _primary = primary;
      primary?.addListener(_onScroll);
    }
    _tailKey = _BandTails.keyOf(context);
    // Decided after the first frame, when the page's list (and its
    // AknBandOverlap, if any) has been built.
    _BandTails.ping();
  }

  void _syncAlone() {
    if (!mounted) return;
    final alone = !_BandTails.has(_tailKey);
    if (alone != _alone) setState(() => _alone = alone);
  }

  void _onScroll() {
    final positions = _primary?.positions;
    if (positions == null || positions.isEmpty) return;
    final p = positions.first;
    if (!p.hasPixels || p.axis != Axis.vertical) return;
    final v = (p.pixels / _scrollSpan).clamp(0.0, 1.0);
    if ((v - _scroll.value).abs() > 0.004 || (v == 0) != (_scroll.value == 0)) {
      _scroll.value = v;
    }
  }

  @override
  void dispose() {
    _BandTails.changes.removeListener(_syncAlone);
    _primary?.removeListener(_onScroll);
    _scroll.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = MediaQuery.withClampedTextScaling(
      // The band's lines grow up to 1.6× (like the bar titles) so the hero
      // card stays on the first screen at 2.0× text.
      maxScaleFactor: 1.6,
      child: Builder(builder: _content),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _alone ? AknRadius.xl : 0),
      duration: AknMotion.of(context, AknMotion.slow),
      curve: AknMotion.emphasizedCurve,
      child: content,
      builder: (context, radius, child) {
        // A stand-alone band floats: its warm shadow comes in with the
        // corners (always in the tree, so the band is never remounted).
        final k = (radius / AknRadius.xl).clamp(0.0, 1.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(radius),
            ),
            boxShadow: k <= 0
                ? null
                : [
                    for (final s in AknShadows.band(context.akn))
                      s.copyWith(
                        color: s.color.withValues(alpha: s.color.a * k),
                      ),
                  ],
          ),
          child: AknBand(
            topInset: true,
            bottomRadius: radius,
            padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 18, 22),
            child: child!,
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context) {
    final header = widget.header;
    final c = context.akn; // the band palette: white ink
    final t = context.aknText;
    final large = MediaQuery.textScalerOf(context).scale(10) >= 16;
    final hello = header.greetingText();
    final company = header.company;
    final who = header.person;
    // A soft warm shade under the white words keeps them crisp where the
    // band's light is brightest.
    final lift = [
      Shadow(
        color: c.heroEnd.withValues(alpha: 0.32),
        offset: const Offset(0, 1),
        blurRadius: 10,
      ),
    ];
    final greetingStyle = t.headline.copyWith(
      fontSize: 17,
      height: 22 / 17,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
      color: c.ink,
      shadows: lift,
    );
    final companyStyle = t.bodySmall.copyWith(
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
      color: c.dim,
      shadows: lift,
    );
    final names = _Enter(
      animation: _enter,
      interval: const Interval(0.04, 0.47, curve: Curves.easeOutCubic),
      offset: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hello,
            style: greetingStyle,
            maxLines: large ? 2 : 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (company.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              company,
              style: companyStyle,
              maxLines: large ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
    final spoken = [
      hello,
      if (company.isNotEmpty) company,
      if (who != null && who.isNotEmpty) who,
    ].join(', ');
    final open = header.onOpenProfile;
    Widget identity = Row(
      crossAxisAlignment: large
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        _Enter(
          animation: _enter,
          interval: const Interval(0, 0.72, curve: AknMotion.pop),
          scale: 0.72,
          child: _BandAvatar(
            name: header._name.isEmpty ? company : header._name,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: names),
      ],
    );
    if (open != null) {
      identity = PressScale(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // The Semantics around it carries the label, the hint and the tap.
          excludeFromSemantics: true,
          onTap: () {
            AknHaptics.selection();
            open();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: identity,
          ),
        ),
      );
    }
    // While the page scrolls under the band the greeting row eases up and
    // back a little (depth); it never fades below 84 %. The wrappers stay in
    // the tree at rest (identity), so nothing under them is rebuilt.
    identity = ValueListenableBuilder<double>(
      valueListenable: _scroll,
      child: identity,
      builder: (context, s, child) => Opacity(
        opacity: 1 - 0.16 * s,
        alwaysIncludeSemantics: true,
        child: Transform.translate(
          offset: Offset(0, -4 * s),
          child: Transform.scale(
            scale: 1 - 0.03 * s,
            alignment: AlignmentDirectional.centerStart,
            child: child,
          ),
        ),
      ),
    );
    // One labelled node (≥ 48 px when it is a button).
    identity = Semantics(
      label: spoken,
      header: true,
      button: open != null,
      hint: open == null ? null : header.profileHint,
      onTap: open,
      excludeSemantics: true,
      child: identity,
    );
    final chrome = AppChrome.maybeOf(context);
    final bell = header.showBell && chrome?.onOpenNotifications != null;
    final buttons = <Widget>[
      for (final a in header.actions) AknBandSquare(child: a),
      if (bell) const AknBandSquare(child: NotificationBell()),
    ];
    return Row(
      crossAxisAlignment: large
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Expanded(child: identity),
        for (var i = 0; i < buttons.length; i++) ...[
          const SizedBox(width: 4),
          _Enter(
            animation: _enter,
            interval: Interval(
              math.min(0.5, 0.22 + 0.1 * i),
              1,
              curve: AknMotion.pop,
            ),
            scale: 0.6,
            child: buttons[i],
          ),
        ],
      ],
    );
  }
}

/// One piece of the header's entrance: fades in over [interval] of
/// [animation], rising [offset] px and growing from [scale]. The wrappers
/// stay in the tree once it has entered (identity), so the child is never
/// remounted.
class _Enter extends StatelessWidget {
  const _Enter({
    required this.animation,
    required this.interval,
    required this.child,
    this.offset = 0,
    this.scale = 1,
  });

  final Animation<double> animation;
  final Interval interval;
  final Widget child;
  final double offset;
  final double scale;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final v = animation.value;
      final p = v >= 1 ? 1.0 : interval.transform(v);
      final fade = v >= 1
          ? 1.0
          : Curves.easeOut.transform(
              ((v - interval.begin) / ((interval.end - interval.begin) * 0.6))
                  .clamp(0.0, 1.0),
            );
      return Opacity(
        opacity: fade,
        alwaysIncludeSemantics: true,
        child: Transform.translate(
          offset: Offset(0, offset * (1 - p)),
          child: Transform.scale(scale: scale + (1 - scale) * p, child: child),
        ),
      );
    },
  );
}

/// The plain page-coloured bar of [AknHomeHeader] (`band: false`): logo
/// tile, company over the person line; the names fade in once.
class _HomeBar extends StatelessWidget {
  const _HomeBar({required this.header});

  final AknHomeHeader header;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final large = MediaQuery.textScalerOf(context).scale(10) >= 16;
    final company = header.company;
    final who = header.person;
    final open = header.onOpenProfile;
    final names = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          company,
          style: t.headline.copyWith(color: c.ink),
          maxLines: large ? 2 : 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (!large && who != null && who.isNotEmpty)
          Text(
            who,
            style: t.bodySmall.copyWith(height: 18 / 14, color: c.dim),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
    final spoken = [company, if (who != null && who.isNotEmpty) who].join(', ');
    Widget text = _Rise(
      offset: 8,
      duration: const Duration(milliseconds: 240),
      child: names,
    );
    if (open != null) {
      text = GestureDetector(
        behavior: HitTestBehavior.opaque,
        // The Semantics around it carries the label, the hint and the tap.
        excludeFromSemantics: true,
        onTap: () {
          AknHaptics.selection();
          open();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: text,
          ),
        ),
      );
    }
    // One labelled node (≥ 48 px when it is a button).
    text = Semantics(
      label: spoken,
      button: open != null,
      hint: open == null ? null : header.profileHint,
      header: true,
      excludeSemantics: true,
      onTap: open,
      child: text,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AknHomeHeader.height),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          20,
          large ? 8 : 0,
          10,
          large ? 6 : 0,
        ),
        child: Row(
          crossAxisAlignment: large
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.only(top: large ? 6 : 0),
              child: const LogoMark(size: 32, semanticLabel: null),
            ),
            const SizedBox(width: 12),
            Expanded(child: text),
            ...header.actions,
            if (header.showBell) const NotificationBell(),
          ],
        ),
      ),
    );
  }
}

/// The round glass avatar on the band: 46 px, white 20 % with a 1 px white
/// 28 % ring that catches the light at its top-left, and the initial (18
/// w800 white). Decorative (the header reads the name).
class _BandAvatar extends StatelessWidget {
  const _BandAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final initials = TurkishText.initials(name);
    final initial = initials.isEmpty ? '' : initials.characters.first;
    return ExcludeSemantics(
      child: CustomPaint(
        painter: _GlassPainter(
          fill: c.onHero.withValues(alpha: 0.2),
          ring: c.onHero.withValues(alpha: 0.28),
          light: c.onHero,
        ),
        child: SizedBox.square(
          dimension: 46,
          child: Center(
            child: Text(
              initial,
              textScaler: TextScaler.noScaling,
              style: context.aknText.headline.copyWith(
                fontSize: 18,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
                color: c.onHero,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 44 px glass circle (white 18 %, a 1 px white 26 % ring) behind an icon
/// button on the band (bell, assistant). The button keeps its 48 px target
/// and the circle presses in with it.
class AknBandSquare extends StatelessWidget {
  const AknBandSquare({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final white = context.akn.onHero;
    return SizedBox(
      width: 48,
      height: 48,
      child: PressScale(
        scale: 0.92,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ExcludeSemantics(
              child: CustomPaint(
                size: const Size.square(44),
                painter: _GlassPainter(
                  fill: white.withValues(alpha: 0.18),
                  ring: white.withValues(alpha: 0.26),
                  light: white,
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

/// A glass disc on the band: [fill], a soft light in its top-left, and a
/// 1 px ring that is brighter where the light falls ([ring] on average).
class _GlassPainter extends CustomPainter {
  const _GlassPainter({
    required this.fill,
    required this.ring,
    required this.light,
  });

  final Color fill;
  final Color ring;
  final Color light;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final centre = size.center(Offset.zero);
    final disc = Rect.fromCircle(center: centre, radius: r);
    canvas.drawCircle(centre, r, Paint()..color = fill);
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.55, -0.6),
          radius: 0.9,
          colors: [light.withValues(alpha: 0.14), light.withValues(alpha: 0)],
        ).createShader(disc),
    );
    final a = ring.a;
    canvas.drawCircle(
      centre,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ring.withValues(alpha: math.min(1, a * 1.6)),
            ring.withValues(alpha: a * 0.55),
          ],
        ).createShader(disc),
    );
  }

  @override
  bool shouldRepaint(_GlassPainter old) =>
      old.fill != fill || old.ring != ring || old.light != light;
}

/// The orange header band (owner decision G, design v3 §4) as a container:
/// the 135° gradient (`heroStart` → `heroMid` → `heroEnd`) lit by soft
/// lights that drift slowly ([HeroBackdropPainter], [AknAmbient] over
/// [AknMotion.bandDrift]), white content ([AknTheme.onBand]: texts, icons,
/// `LogoMark`, `AknWordmark` and icon buttons turn white by themselves) and,
/// with [topInset], the status-bar height added on top with light status
/// icons. [bottomRadius] rounds the bottom corners (a stand-alone home band:
/// 28).
///
/// The gradient and its lights are anchored to the screen (a CSS-exact 135°
/// gradient over the screen width × [referenceHeight]) and share one clock,
/// so the band header and the [AknBandOverlap] tail under the first card
/// join without a seam, even while the lights move. It fits the login band
/// too:
///
/// ```dart
/// AknBand(
///   topInset: true,
///   shadow: true,
///   padding: const EdgeInsets.fromLTRB(20, 31, 20, 22),
///   child: Column(children: [LogoMark(size: 56), Text('Siparişten teslimata.')]),
/// )
/// ```
class AknBand extends StatelessWidget {
  const AknBand({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.topInset = false,
    this.shadow = false,
    this.bottomRadius = 0,
    this.lights = true,
  });

  final Widget child;

  /// Inner padding (the status-bar height is added on top with [topInset]).
  final EdgeInsetsGeometry padding;

  /// The band reaches the top of the screen: adds the status-bar height and
  /// sets light status icons.
  final bool topInset;

  /// The warm band shadow under it ([AknShadows.band]).
  final bool shadow;

  /// Radius of the bottom corners (0: square, as under a hero card).
  final double bottomRadius;

  /// Paint the band's lights and let them drift (false: the plain
  /// gradient).
  final bool lights;

  /// The height the band's gradient is laid over (status bar + band +
  /// overlap), shared by the header and the [AknBandOverlap] tail.
  static double referenceHeight(BuildContext context) =>
      MediaQuery.paddingOf(context).top +
      AknHomeHeader.bandHeight +
      AknHomeHeader.overlap;

  /// The CSS-exact 135° band gradient over a box of [size] (the colour lines
  /// run at 45° whatever the box's aspect ratio).
  static LinearGradient gradientFor(AknColors c, Size size) =>
      AknHeroGradient.anchored(c, size);

  @override
  Widget build(BuildContext context) {
    final page = context.akn;
    final top = topInset ? MediaQuery.paddingOf(context).top : 0.0;
    final content = Theme(
      data: AknTheme.onBand(Theme.of(context)),
      child: Builder(
        builder: (context) => DefaultTextStyle.merge(
          style: TextStyle(color: context.akn.ink),
          child: IconTheme.merge(
            data: IconThemeData(color: context.akn.ink),
            child: Padding(
              padding: padding.add(EdgeInsets.only(top: top)),
              child: child,
            ),
          ),
        ),
      ),
    );
    Widget body = _LiveBandFill(
      reference: Size(
        MediaQuery.sizeOf(context).width,
        referenceHeight(context),
      ),
      lights: lights,
      // The content keeps its own layer while the lights repaint.
      child: RepaintBoundary(child: content),
    );
    final radius = BorderRadius.vertical(
      bottom: Radius.circular(math.max(0.0, bottomRadius)),
    );
    // Always in the tree (the corners animate in and out without remounting
    // the band); it only clips while the corners are round.
    body = ClipRRect(
      borderRadius: radius,
      clipBehavior: bottomRadius > 0 ? Clip.antiAlias : Clip.none,
      child: body,
    );
    body = RepaintBoundary(child: body);
    body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadow ? AknShadows.band(page) : null,
      ),
      child: body,
    );
    if (topInset) {
      body = AnnotatedRegion<SystemUiOverlayStyle>(
        value: AknTheme.overlayOnBand(page.brightness),
        child: body,
      );
    }
    return body;
  }
}

/// Pulls a home's hero card up onto the header band (owner decision G): the
/// band continues behind the top [overlap] px of the card (seamlessly — the
/// gradient and its drifting lights are anchored to the screen) and the card
/// keeps [padding] from the screen edges. Put it full-bleed as the FIRST
/// item of the home's list:
///
/// ```dart
/// AknBandOverlap(child: AknPlate(...))
/// ```
///
/// On its first build the card rises into place (design v3 §5: fade, 24 px
/// rise and a 0.94 → 1 scale over [AknMotion.heroRise] on the emphasized
/// curve, never remounting the card; [rise] false shows it at once, as does
/// reduce motion). While it is
/// mounted the home band above keeps square bottom corners. The tail scrolls
/// with the content; the pinned band covers it.
class AknBandOverlap extends StatefulWidget {
  const AknBandOverlap({
    super.key,
    required this.child,
    this.overlap = AknHomeHeader.overlap,
    this.padding = const EdgeInsets.symmetric(horizontal: AknSpace.page),
    this.rise = true,
  });

  final Widget child;

  /// The band height behind the card (48).
  final double overlap;

  /// Space around the card (the 20 px page gutter).
  final EdgeInsetsGeometry padding;

  /// The card rises into place on its first build.
  final bool rise;

  @override
  State<AknBandOverlap> createState() => _AknBandOverlapState();
}

class _AknBandOverlapState extends State<AknBandOverlap> {
  Object? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final key = _BandTails.keyOf(context);
    if (!identical(key, _key)) {
      if (_key != null) _BandTails.remove(_key!);
      _key = key;
      _BandTails.add(key);
    }
  }

  @override
  void dispose() {
    if (_key != null) _BandTails.remove(_key!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = Scrollable.maybeOf(context)?.position;
    Widget card = RepaintBoundary(child: widget.child);
    if (widget.rise) {
      card = _Rise(
        offset: 24,
        scale: 0.94,
        duration: AknMotion.heroRise,
        curve: AknMotion.emphasizedCurve,
        child: card,
      );
    }
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: widget.overlap,
          child: ExcludeSemantics(
            child: RepaintBoundary(
              child: _LiveBandFill(
                reference: Size(
                  MediaQuery.sizeOf(context).width,
                  AknBand.referenceHeight(context),
                ),
                repaint: position,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        Padding(padding: widget.padding, child: card),
      ],
    );
  }
}

/// Fades its child in once while lifting it by [offset] px and growing it
/// from [scale] — like `FadeUp`, but its wrappers stay in the tree when it
/// has risen, so the child (the hero card and its own entrance motion) is
/// never remounted. Static under reduce motion.
class _Rise extends StatefulWidget {
  const _Rise({
    required this.child,
    this.offset = 12,
    this.scale = 1,
    this.duration = const Duration(milliseconds: 320),
    this.curve = AknMotion.standard,
  });

  final Widget child;
  final double offset;
  final double scale;
  final Duration duration;
  final Curve curve;

  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      final v = _c.value >= 1 ? 1.0 : widget.curve.transform(_c.value);
      return Opacity(
        opacity: v.clamp(0.0, 1.0),
        alwaysIncludeSemantics: true,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - v)),
          child: Transform.scale(
            scale: widget.scale + (1 - widget.scale) * v,
            child: child,
          ),
        ),
      );
    },
  );
}

/// Which pages show an [AknBandOverlap] tail right now (keyed by the
/// nearest [Scaffold], else the route): the home band squares its corners
/// there. Changes are announced after the frame (never during a build).
abstract final class _BandTails {
  static final Map<Object, int> _counts = <Object, int>{};
  static final ValueNotifier<int> _version = ValueNotifier<int>(0);
  static bool _scheduled = false;

  static Listenable get changes => _version;

  static Object keyOf(BuildContext context) =>
      Scaffold.maybeOf(context) ?? ModalRoute.of(context) ?? _BandTails;

  static bool has(Object? key) => key != null && (_counts[key] ?? 0) > 0;

  static void add(Object key) {
    _counts[key] = (_counts[key] ?? 0) + 1;
    ping();
  }

  static void remove(Object key) {
    final n = (_counts[key] ?? 0) - 1;
    if (n <= 0) {
      _counts.remove(key);
    } else {
      _counts[key] = n;
    }
    ping();
  }

  /// Tells the listening bands to look again after this frame.
  static void ping() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _scheduled = false;
        _version.value++;
      })
      ..ensureVisualUpdate();
  }
}

/// The shared clock of the band's drifting lights: every piece of band (the
/// header and the tail under the card) reads the same phase in a frame, so
/// they stay seamless while the lights move.
abstract final class _BandClock {
  static final Stopwatch _watch = Stopwatch()..start();

  static double get phase {
    final period = AknMotion.bandDrift.inMicroseconds;
    return (_watch.elapsedMicroseconds % period) / period;
  }
}

/// [AknBandFill] whose lights drift: [AknAmbient] supplies the frames (off in
/// tests and under reduce motion, where the lights rest at phase 0) and
/// [_BandClock] the phase.
class _LiveBandFill extends StatelessWidget {
  const _LiveBandFill({
    required this.reference,
    required this.child,
    this.repaint,
    this.lights = true,
  });

  final Size reference;
  final Listenable? repaint;
  final bool lights;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!lights) {
      return AknBandFill(
        reference: reference,
        repaint: repaint,
        lights: false,
        child: child,
      );
    }
    return AknAmbient(
      period: AknMotion.bandDrift,
      curve: Curves.linear,
      child: child,
      builder: (context, t, child) => AknBandFill(
        reference: reference,
        repaint: repaint,
        phase: AknMotion.ambientOf(context) ? _BandClock.phase : 0,
        child: child,
      ),
    );
  }
}

/// Paints the band behind [child], anchored to the screen: the gradient and
/// its lights ([HeroBackdropPainter.paintBand]) are laid over `Rect(0, 0,
/// reference)` in global coordinates, so two pieces of band (the header and
/// the tail under the first card) join without a seam. [phase] places the
/// drifting lights (0 = rest); [repaint] (e.g. the scroll position)
/// repaints it while it moves.
class AknBandFill extends SingleChildRenderObjectWidget {
  const AknBandFill({
    super.key,
    required this.reference,
    this.repaint,
    this.lights = true,
    this.phase = 0,
    super.child,
  });

  /// The gradient's box in global (screen) coordinates, from the top-left
  /// corner of the screen.
  final Size reference;
  final Listenable? repaint;

  /// Paint the band's lights over the gradient.
  final bool lights;

  /// Where the lights are in their drift (0–1, [AknMotion.bandDrift]).
  final double phase;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderAknBandFill(
    colors: Theme.of(context).extension<AknColors>() ?? AknColors.light,
    reference: reference,
    repaint: repaint,
    lights: lights,
    phase: phase,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderAknBandFill renderObject,
  ) {
    renderObject
      ..colors = Theme.of(context).extension<AknColors>() ?? AknColors.light
      ..reference = reference
      ..repaint = repaint
      ..lights = lights
      ..phase = phase;
  }
}

/// The render object of [AknBandFill].
class RenderAknBandFill extends RenderProxyBox {
  RenderAknBandFill({
    required AknColors colors,
    required Size reference,
    Listenable? repaint,
    bool lights = true,
    double phase = 0,
  }) : _colors = colors,
       _reference = reference,
       _repaint = repaint,
       _lights = lights,
       _phase = phase;

  AknColors _colors;
  set colors(AknColors v) {
    if (v == _colors) return;
    _colors = v;
    markNeedsPaint();
  }

  Size _reference;
  set reference(Size v) {
    if (v == _reference) return;
    _reference = v;
    markNeedsPaint();
  }

  Listenable? _repaint;
  set repaint(Listenable? v) {
    if (identical(v, _repaint)) return;
    if (attached) _repaint?.removeListener(markNeedsPaint);
    _repaint = v;
    if (attached) _repaint?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  bool _lights;
  set lights(bool v) {
    if (v == _lights) return;
    _lights = v;
    markNeedsPaint();
  }

  double _phase;
  set phase(double v) {
    if (v == _phase) return;
    _phase = v;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _repaint?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final rect = offset & size;
    if (!rect.isEmpty) {
      final origin = localToGlobal(Offset.zero);
      final ref = (offset - origin) & _reference;
      HeroBackdropPainter.paintBand(
        context.canvas,
        rect,
        _colors,
        reference: ref,
        phase: _phase,
        lights: _lights,
      );
    }
    super.paint(context, offset);
  }
}
