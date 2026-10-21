import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../utils/turkish_text.dart';
import '../motion.dart';
import '../painters/logo_mark.dart';
import '../theme.dart';
import '../tokens.dart';
import 'app_scaffold.dart' show AppChrome, NotificationBell;

/// The home header of every role (owner decision G "F2GO kart dili",
/// 2026-10-21): an **orange gradient band** (135° #FF8A47 → #F26A21 →
/// #E2560E; dark #C2410C → #9A3A09) that starts behind the status bar (light
/// status icons) and carries, in white, a round avatar with the initial, the
/// greeting ("İyi akşamlar, Elif", 15/20 w700) over the company or station
/// (13/18 w500, white 92 %), and the bell (plus any [actions], e.g. the
/// assistant) in white-22 % rounded squares.
///
/// ```
/// (E)  İyi akşamlar, Elif                          [🔔]
///      Anadolu Lojistik A.Ş.
/// ```
///
/// Put it in `AppScaffold(homeHeader: AknHomeHeader(...))`: the scaffold pins
/// the band at the top (it casts its soft orange shadow once content scrolls
/// under it) and paints the page in `homeBg` (#F9FAFB). To pull the screen's
/// hero card up onto the band — the first card overlaps it by [overlap]
/// (48) px — make it the first item of the list inside [AknBandOverlap]:
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
/// [band] false keeps the plain white bar of design v2 (logo tile, company
/// over the person line) for old call sites.
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

  /// Extra icon buttons before the bell (each sits in a white-22 % square
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

  /// The orange band (owner decision G). False: the old white bar.
  final bool band;

  /// The white bar's height at 1.0× text ([band] false).
  static const double height = 62;

  /// The band's height under the status bar at 1.0× text: 10 + 50 + 20.
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
  Widget build(BuildContext context) => band
      ? AknBand(
          topInset: true,
          padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 12, 20),
          // The band's lines grow up to 1.6× (like the bar titles) so the
          // hero card stays on the first screen at 2.0× text.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.6,
            child: Builder(builder: _bandContent),
          ),
        )
      : _buildBar(context);

  Widget _bandContent(BuildContext context) {
    final c = context.akn; // the band palette: white ink
    final t = context.aknText;
    final large = MediaQuery.textScalerOf(context).scale(10) >= 16;
    final hello = greetingText();
    final who = person;
    final greetingStyle = t.headline.copyWith(
      fontSize: 15,
      height: 20 / 15,
      fontWeight: FontWeight.w700,
      color: c.ink,
    );
    final companyStyle = t.bodySmall.copyWith(
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w500,
      color: c.dim,
    );
    final names = Column(
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
    );
    final spoken = [
      hello,
      if (company.isNotEmpty) company,
      if (who != null && who.isNotEmpty) who,
    ].join(', ');
    Widget identity = Row(
      crossAxisAlignment: large
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        _BandAvatar(name: _name.isEmpty ? company : _name),
        const SizedBox(width: 14),
        Expanded(child: names),
      ],
    );
    if (onOpenProfile != null) {
      identity = GestureDetector(
        behavior: HitTestBehavior.opaque,
        // The Semantics around it carries the label, the hint and the tap.
        excludeFromSemantics: true,
        onTap: () {
          AknHaptics.selection();
          onOpenProfile!();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: identity,
        ),
      );
    }
    // One labelled node (≥ 48 px when it is a button).
    identity = Semantics(
      label: spoken,
      header: true,
      button: onOpenProfile != null,
      hint: onOpenProfile == null ? null : profileHint,
      onTap: onOpenProfile,
      excludeSemantics: true,
      child: identity,
    );
    final chrome = AppChrome.maybeOf(context);
    final bell = showBell && chrome?.onOpenNotifications != null;
    return Row(
      crossAxisAlignment: large
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Expanded(child: identity),
        for (final a in actions) ...[
          const SizedBox(width: 4),
          AknBandSquare(child: a),
        ],
        if (bell) ...[
          const SizedBox(width: 4),
          const AknBandSquare(child: NotificationBell()),
        ],
      ],
    );
  }

  /// The white bar of design v2 (logo tile, company over the person line).
  Widget _buildBar(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final large = MediaQuery.textScalerOf(context).scale(10) >= 16;
    final who = person;
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
    Widget text = names;
    if (onOpenProfile != null) {
      text = GestureDetector(
        behavior: HitTestBehavior.opaque,
        // The Semantics around it carries the label, the hint and the tap.
        excludeFromSemantics: true,
        onTap: () {
          AknHaptics.selection();
          onOpenProfile!();
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
      button: onOpenProfile != null,
      hint: onOpenProfile == null ? null : profileHint,
      header: true,
      excludeSemantics: true,
      onTap: onOpenProfile,
      child: text,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: height),
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
            ...actions,
            if (showBell) const NotificationBell(),
          ],
        ),
      ),
    );
  }
}

/// The round avatar on the band: 50 px, white 25 % fill, a 2 px white 35 %
/// ring and the initial (20 w800 white). Decorative (the header reads the
/// name).
class _BandAvatar extends StatelessWidget {
  const _BandAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final initials = TurkishText.initials(name);
    final initial = initials.isEmpty ? '' : initials.characters.first;
    return ExcludeSemantics(
      child: Container(
        width: 50,
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x40FFFFFF),
          border: Border.all(color: const Color(0x59FFFFFF), width: 2),
        ),
        child: Text(
          initial,
          textScaler: TextScaler.noScaling,
          style: context.aknText.headline.copyWith(
            fontSize: 20,
            height: 1,
            fontWeight: FontWeight.w800,
            color: c.ink,
          ),
        ),
      ),
    );
  }
}

/// A white-22 % rounded square (42 × 42, radius 14) behind an icon button on
/// the band (bell, assistant). The button keeps its 48 px target.
class AknBandSquare extends StatelessWidget {
  const AknBandSquare({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final fill = c.isBandPalette
        ? c.surfaceAlt
        : AknTheme.bandPalette(c).surfaceAlt;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// The orange header band (owner decision G) as a container: the 135°
/// gradient (`heroStart` → `heroMid` → `heroEnd`), white content
/// ([AknTheme.onBand]: texts, icons, `LogoMark`, `AknWordmark` and icon
/// buttons turn white by themselves) and, with [topInset], the status-bar
/// height added on top with light status icons.
///
/// The gradient is anchored to the screen (a CSS-exact 135° gradient over
/// the screen width × [referenceHeight]), so the band header and the
/// [AknBandOverlap] tail under the first card join without a seam. It fits
/// the login band too:
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
  });

  final Widget child;

  /// Inner padding (the status-bar height is added on top with [topInset]).
  final EdgeInsetsGeometry padding;

  /// The band reaches the top of the screen: adds the status-bar height and
  /// sets light status icons.
  final bool topInset;

  /// The soft orange shadow under the band (`0 6 14` rgba(232,89,12,.22)).
  final bool shadow;

  /// The height the band's gradient is laid over (status bar + band +
  /// overlap), shared by the header and the [AknBandOverlap] tail.
  static double referenceHeight(BuildContext context) =>
      MediaQuery.paddingOf(context).top +
      AknHomeHeader.bandHeight +
      AknHomeHeader.overlap;

  /// The CSS-exact 135° band gradient over a box of [size] (the colour lines
  /// run at 45° whatever the box's aspect ratio).
  static LinearGradient gradientFor(AknColors c, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return c.bandGradient;
    final ax = (w + h) / (2 * w);
    final ay = (w + h) / (2 * h);
    return LinearGradient(
      begin: Alignment(-ax, -ay),
      end: Alignment(ax, ay),
      colors: [c.heroStart, c.heroMid, c.heroEnd],
      stops: const [0, 0.5, 1],
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = context.akn;
    final top = topInset ? MediaQuery.paddingOf(context).top : 0.0;
    Widget body = Theme(
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
    body = AknBandFill(
      reference: Size(
        MediaQuery.sizeOf(context).width,
        referenceHeight(context),
      ),
      child: body,
    );
    if (shadow) {
      body = DecoratedBox(
        decoration: BoxDecoration(boxShadow: AknShadows.band(page)),
        child: body,
      );
    }
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
/// gradient is anchored to the screen) and the card keeps [padding] from the
/// screen edges. Put it full-bleed as the FIRST item of the home's list:
///
/// ```dart
/// AknBandOverlap(child: AknPlate(...))
/// ```
///
/// The tail scrolls with the content; the pinned band covers it.
class AknBandOverlap extends StatelessWidget {
  const AknBandOverlap({
    super.key,
    required this.child,
    this.overlap = AknHomeHeader.overlap,
    this.padding = const EdgeInsets.symmetric(horizontal: 18),
  });

  final Widget child;

  /// The band height behind the card (48).
  final double overlap;

  /// Space around the card (18 px sides, like the reference).
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final position = Scrollable.maybeOf(context)?.position;
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: overlap,
          child: ExcludeSemantics(
            child: AknBandFill(
              reference: Size(
                MediaQuery.sizeOf(context).width,
                AknBand.referenceHeight(context),
              ),
              repaint: position,
              child: const SizedBox.expand(),
            ),
          ),
        ),
        Padding(
          padding: padding,
          child: RepaintBoundary(child: child),
        ),
      ],
    );
  }
}

/// Paints the band gradient behind [child], anchored to the screen: the
/// gradient is laid over `Rect(0, 0, reference)` in global coordinates, so
/// two pieces of band (the header and the tail under the first card) join
/// without a seam. [repaint] (e.g. the scroll position) repaints it while
/// it moves.
class AknBandFill extends SingleChildRenderObjectWidget {
  const AknBandFill({
    super.key,
    required this.reference,
    this.repaint,
    super.child,
  });

  /// The gradient's box in global (screen) coordinates, from the top-left
  /// corner of the screen.
  final Size reference;
  final Listenable? repaint;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderAknBandFill(
    colors: Theme.of(context).extension<AknColors>() ?? AknColors.light,
    reference: reference,
    repaint: repaint,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderAknBandFill renderObject,
  ) {
    renderObject
      ..colors = Theme.of(context).extension<AknColors>() ?? AknColors.light
      ..reference = reference
      ..repaint = repaint;
  }
}

/// The render object of [AknBandFill].
class RenderAknBandFill extends RenderProxyBox {
  RenderAknBandFill({
    required AknColors colors,
    required Size reference,
    Listenable? repaint,
  }) : _colors = colors,
       _reference = reference,
       _repaint = repaint;

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
      final shader = AknBand.gradientFor(_colors, _reference).createShader(ref);
      context.canvas.drawRect(rect, Paint()..shader = shader);
    }
    super.paint(context, offset);
  }
}
