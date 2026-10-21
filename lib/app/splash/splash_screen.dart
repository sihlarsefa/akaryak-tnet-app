import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ui/motion.dart';
import '../../core/ui/painters/chevron_spinner.dart';
import '../../core/ui/painters/logo_mark.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';

/// Flutter splash (spec C.6, redesign §1.3), continuing the native splash
/// seamlessly.
///
/// The native splash (`flutter_native_splash`: white — #0F1114 in dark mode
/// — with `akn-mark-512.png` at 4× → 128 pt, centered) is reproduced exactly
/// on the first frame. Then, in about 1.1 s:
///
/// 1. the » chevrons dim to a faint track (180 ms),
/// 2. they draw in again along their strokes (500 ms) while a soft peach
///    glow blooms behind the mark,
/// 3. the mark settles upward and the "AkaryakıtNet" wordmark fades in (ink
///    "Akaryakıt" + logo-orange "Net"; white + orange in dark mode),
/// 4. the tagline appears; [onFinished] fires.
///
/// If the app is still starting after that, a small orange chevron loader
/// fades in. Dark status-bar icons on white (light icons in dark mode).
/// Under reduce motion the final frame shows at once and [onFinished] fires
/// after 300 ms. Never purple.
///
/// The router decides where to go next; keep the splash up for at least
/// [minimumDisplay] (or wait for [onFinished]) so the entrance is not cut.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onFinished, this.tagline});

  final VoidCallback? onFinished;

  /// Line under the wordmark (default "Siparişten teslimata").
  final String? tagline;

  /// Length of the entrance animation.
  static const Duration minimumDisplay = Duration(milliseconds: 1100);

  /// Size of the mark in the native splash (512 px source at 4×).
  static const double nativeMarkSize = 128;

  /// Size of the mark after it settles.
  static const double settledMarkSize = 92;

  /// Splash background: white (the native splash colour), charcoal #0F1114
  /// in dark mode (the native dark splash colour).
  static Color background(AknColors c) =>
      c.isDark ? c.bg : const Color(0xFFFFFFFF);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: SplashScreen.minimumDisplay,
  );
  late final AnimationController _wait = AnimationController(
    vsync: this,
    duration: AknMotion.slow,
  );
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

  late final Animation<double> _dim = _interval(0, 0.16, Curves.easeOut);
  late final Animation<double> _draw = _interval(0.14, 0.6);
  late final Animation<double> _settle = _interval(
    0.42,
    0.86,
    AknMotion.emphasizedCurve,
  );
  late final Animation<double> _word = _interval(0.5, 0.86, AknMotion.standard);
  late final Animation<double> _tag = _interval(0.68, 1, AknMotion.standard);
  late final Animation<double> _light = _interval(0.3, 1, Curves.easeInOut);

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
            builder: (context, constraints) => AnimatedBuilder(
              animation: Listenable.merge([_c, _wait]),
              builder: (context, _) => _frame(constraints.biggest, c),
            ),
          ),
        ),
      ),
    );
  }

  Widget _frame(Size size, AknColors c) {
    final settle = _settle.value;
    final markSize = lerpDouble(
      SplashScreen.nativeMarkSize,
      SplashScreen.settledMarkSize,
      settle,
    )!;
    final centerY = size.height / 2 - 52 * settle;
    final markTop = centerY - markSize / 2;
    final wordTop = centerY + SplashScreen.settledMarkSize / 2 + 22;
    final dimmed = 1 - 0.68 * _dim.value;
    final draw = _draw.value;
    // While nothing is drawn yet the whole chevron shows at the dim level;
    // the drawn part is always full white.
    final track = draw >= 1 ? 0.0 : dimmed;
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    return Stack(
      fit: StackFit.expand,
      children: [
        // A soft peach bloom behind the mark (calm, no motion after).
        Positioned(
          left: size.width / 2 - 200,
          top: centerY - 200,
          width: 400,
          height: 400,
          child: Opacity(
            opacity: _light.value,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    c.brandBright.withValues(alpha: c.isDark ? 0.16 : 0.10),
                    c.brandBright.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: (size.width - markSize) / 2,
          top: markTop,
          width: markSize,
          height: markSize,
          child: CustomPaint(
            painter: LogoMarkPainter(
              progress: _dim.value < 1 ? 0 : draw,
              showTile: true,
              tileColor: c.logo,
              chevronColor: const Color(0xFFFFFFFF),
              trackOpacity: _dim.value < 1 ? dimmed : track,
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          top: wordTop + 10 * (1 - _word.value),
          child: Opacity(
            opacity: _word.value,
            child: Center(
              child: AknWordmark(
                fontSize: 30,
                onDark: c.isDark,
                semanticLabel: null,
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          top: wordTop + 46 + 6 * (1 - _tag.value),
          child: Opacity(
            opacity: _tag.value,
            child: Text(
              widget.tagline ?? 'Siparişten teslimata',
              textAlign: TextAlign.center,
              textScaler: scaler,
              style: TextStyle(
                color: c.dim,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
              ),
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
