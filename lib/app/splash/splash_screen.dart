import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ui/motion.dart';
import '../../core/ui/painters/chevron_spinner.dart';
import '../../core/ui/painters/logo_mark.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';

/// Flutter splash (spec C.6; tasarım v3 "Akış"), continuing the native splash
/// seamlessly.
///
/// The native splash (`flutter_native_splash`: white — #0E0F11 in dark mode
/// — with `akn-mark-512.png` at 4× → 128 pt, centred) is reproduced exactly
/// on the first frame. Then, in 1 s:
///
/// 1. the » chevrons dim to a faint track (150 ms);
/// 2. they draw in again along their strokes (600 ms) while the tile
///    settles to 96 px and lifts a little, and a soft luminous orange light
///    blooms behind it;
/// 3. the tile gives a small pop as the chevrons complete, a light sweeps
///    across it, and the "AkaryakıtNet" wordmark fades and slides up under
///    it;
/// 4. [onFinished] fires and the router moves on.
///
/// While the splash stays up the light behind the mark keeps drifting
/// (ambient motion); if the app is still starting a while later, a small
/// orange chevron loader fades in. The page itself stays white (dark: the
/// dark page colour); the light is painted on it, never a purple or navy
/// tint. Dark status-bar icons on white (light icons in dark mode). Under
/// reduce motion the final frame shows at once and [onFinished] fires after
/// 300 ms.
///
/// The router decides where to go next; keep the splash up for at least
/// [minimumDisplay] (or wait for [onFinished]) so the entrance is not cut.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onFinished, this.tagline});

  final VoidCallback? onFinished;

  /// Deprecated: the splash shows no tagline (kept for API stability;
  /// ignored).
  final String? tagline;

  /// Length of the entrance animation.
  static const Duration minimumDisplay = Duration(milliseconds: 1000);

  /// Size of the mark in the native splash (512 px source at 4×).
  static const double nativeMarkSize = 128;

  /// Size of the mark after it settles: the 96 px logo tile.
  static const double settledMarkSize = 96;

  /// Splash background: white (the native splash colour), the dark page
  /// colour #0E0F11 in dark mode (the native dark splash colour).
  static Color background(AknColors c) =>
      c.isDark ? c.bg : const Color(0xFFFFFFFF);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// Wordmark size and its gap under the settled tile.
  static const double _wordSize = 26;
  static const double _wordGap = 22;

  /// How far the settled tile lifts so the tile + wordmark lock-up is
  /// centred.
  static const double _lift = (_wordGap + _wordSize * 1.18) / 2;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: SplashScreen.minimumDisplay,
  );
  late final AnimationController _wait = AnimationController(
    vsync: this,
    duration: AknMotion.slow,
  );
  late final Listenable _ticks = Listenable.merge([_c, _wait]);
  Timer? _waitTimer;
  bool _started = false;
  bool _finished = false;

  final List<CurvedAnimation> _curves = [];

  Animation<double> _interval(
    double a,
    double b, [
    Curve curve = Curves.linear,
  ]) {
    final anim = CurvedAnimation(
      parent: _c,
      curve: Interval(a, b, curve: curve),
    );
    _curves.add(anim);
    return anim;
  }

  // 0–150 ms dim, 150–750 ms draw (600 ms), 250–900 ms settle to 96 px,
  // 80–900 ms the light blooms, 500–1000 ms the wordmark rises, 720–1000 ms
  // the tile pops and a light sweeps across it.
  late final Animation<double> _dim = _interval(0, 0.15, Curves.easeOut);
  late final Animation<double> _draw = _interval(
    0.15,
    0.75,
    AknMotion.emphasizedCurve,
  );
  late final Animation<double> _settle = _interval(
    0.25,
    0.9,
    AknMotion.emphasizedCurve,
  );
  late final Animation<double> _bloom = _interval(0.08, 0.9, Curves.easeOut);
  late final Animation<double> _word = _interval(
    0.5,
    1,
    AknMotion.emphasizedCurve,
  );
  late final Animation<double> _sheen = _interval(
    0.72,
    1,
    Curves.easeInOutCubic,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
      _waitTimer = Timer(const Duration(milliseconds: 300), _finish);
    } else {
      _c.forward().whenComplete(_finish);
    }
  }

  void _finish() {
    if (!mounted || _finished) return;
    _finished = true;
    widget.onFinished?.call();
    // Still here a while later: the app is waiting on something; show a
    // quiet loader so the screen does not look frozen.
    _waitTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      if (AknMotion.reduced(context)) {
        _wait.value = 1;
      } else {
        _wait.forward();
      }
    });
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    for (final a in _curves) {
      a.dispose();
    }
    _c.dispose();
    _wait.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AknTheme.overlayFor(c.brightness),
      child: Scaffold(
        backgroundColor: SplashScreen.background(c),
        body: Semantics(
          label: 'AkaryakıtNet açılıyor',
          liveRegion: true,
          excludeSemantics: true,
          child: LayoutBuilder(
            builder: (context, constraints) => AknAmbient(
              period: AknMotion.bandDrift,
              curve: Curves.linear,
              builder: (context, drift, _) => AnimatedBuilder(
                animation: _ticks,
                builder: (context, _) => _frame(constraints.biggest, c, drift),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _frame(Size size, AknColors c, double drift) {
    final settle = _settle.value;
    final markSize = ui.lerpDouble(
      SplashScreen.nativeMarkSize,
      SplashScreen.settledMarkSize,
      settle,
    )!;
    final center = Offset(size.width / 2, size.height / 2 - _lift * settle);
    final markTop = center.dy - markSize / 2;
    final dimmed = 1 - 0.68 * _dim.value;
    final draw = _draw.value;
    // While nothing is drawn yet the whole chevron shows at the dim level;
    // the drawn part is always full white.
    final track = draw >= 1 ? 0.0 : dimmed;
    // A small pop as the chevrons complete (layout size stays the same).
    final pop = 1 + 0.045 * math.sin(math.pi * _sheen.value);
    final word = _word.value;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The soft luminous light behind the mark (blooms, then drifts).
        Positioned.fill(
          child: CustomPaint(
            painter: _SplashLightPainter(
              center: center,
              bloom: _bloom.value,
              drift: drift,
              glow: c.heroGlow,
              brand: c.brandBright,
              dark: c.isDark,
            ),
          ),
        ),
        Positioned(
          left: (size.width - markSize) / 2,
          top: markTop,
          width: markSize,
          height: markSize,
          child: Transform.scale(
            scale: pop,
            child: CustomPaint(
              painter: LogoMarkPainter(
                progress: _dim.value < 1 ? 0 : draw,
                showTile: true,
                tileColor: c.logo,
                chevronColor: const Color(0xFFFFFFFF),
                trackOpacity: _dim.value < 1 ? dimmed : track,
              ),
              foregroundPainter: _TileSheenPainter(progress: _sheen.value),
            ),
          ),
        ),
        // The wordmark fades and slides up under the settled tile.
        Positioned(
          left: AknSpace.page,
          right: AknSpace.page,
          top:
              center.dy +
              SplashScreen.settledMarkSize / 2 +
              _wordGap +
              14 * (1 - word),
          child: Opacity(
            opacity: word,
            child: const Center(
              child: AknWordmark(fontSize: _wordSize, semanticLabel: null),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.paddingOf(context).bottom + 48,
          child: Opacity(
            opacity: _wait.value,
            child: _wait.value == 0
                ? const SizedBox.shrink()
                : Center(
                    child: ChevronSpinner(
                      size: 16,
                      color: c.brandBright,
                      semanticLabel: null,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// The light behind the splash mark: a wide warm glow ([glow], the band's
/// light) and a tighter orange aura ([brand]) around the tile. [bloom]
/// (0..1) grows and brightens them in; [drift] (0..1, looping) moves the
/// wide glow on a slow ellipse and lets it breathe.
class _SplashLightPainter extends CustomPainter {
  _SplashLightPainter({
    required this.center,
    required this.bloom,
    required this.drift,
    required this.glow,
    required this.brand,
    required this.dark,
  });

  final Offset center;
  final double bloom;
  final double drift;
  final Color glow;
  final Color brand;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (bloom <= 0) return;
    final angle = 2 * math.pi * drift;
    final breathe = 1 + 0.05 * math.sin(2 * angle);
    final wide = size.shortestSide * (0.5 + 0.28 * bloom) * breathe;
    final wideCenter =
        center + Offset(math.cos(angle) * 22, math.sin(angle) * 14 - 18);
    final wideAlpha = (dark ? 0.22 : 0.5) * bloom;
    canvas.drawCircle(
      wideCenter,
      wide,
      Paint()
        ..shader = RadialGradient(
          colors: [
            glow.withValues(alpha: wideAlpha),
            glow.withValues(alpha: wideAlpha * 0.35),
            glow.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: wideCenter, radius: wide)),
    );
    final core = 70 + 70 * bloom;
    final coreAlpha = (dark ? 0.28 : 0.16) * bloom;
    canvas.drawCircle(
      center,
      core,
      Paint()
        ..shader = RadialGradient(
          colors: [
            brand.withValues(alpha: coreAlpha),
            brand.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: core)),
    );
  }

  @override
  bool shouldRepaint(_SplashLightPainter old) =>
      old.center != center ||
      old.bloom != bloom ||
      old.drift != drift ||
      old.glow != glow ||
      old.brand != brand ||
      old.dark != dark;
}

/// One soft diagonal light sweeping across the logo tile ([progress] 0..1;
/// nothing at the ends), clipped to the tile's rounded square.
class _TileSheenPainter extends CustomPainter {
  _TileSheenPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final s = size.shortestSide / 80;
    final tile = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        (size.width - 80 * s) / 2 + 2 * s,
        (size.height - 80 * s) / 2 + 2 * s,
        76 * s,
        76 * s,
      ),
      Radius.circular(18 * s),
    );
    canvas.save();
    canvas.clipRRect(tile);
    // A band leaning 30°, travelling from beyond the left edge to beyond
    // the right one.
    final band = size.width * 0.5;
    final x = -band + (size.width + band * 2) * progress;
    final strength = math.sin(math.pi * progress);
    canvas.drawRect(
      tile.outerRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(x - band, 0),
          Offset(x, band * 0.58),
          [
            const Color(0x00FFFFFF),
            const Color(0xFFFFFFFF).withValues(alpha: 0.38 * strength),
            const Color(0x00FFFFFF),
          ],
          const [0, 0.5, 1],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TileSheenPainter old) => old.progress != progress;
}
