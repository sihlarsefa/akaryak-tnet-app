import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/lock_settings.dart';
import '../core/auth/session_controller.dart';
import '../core/auth/session_state.dart';
import '../core/env/app_env.dart';
import '../core/ui/ui.dart';
import '../core/utils/external_activity.dart';

/// Canlı olmayan derlemelerde köşe şeridi (spec D.7): sahte veride "DEMO", test sunucusunda "TEST".
/// Sağ üst köşede çapraz şerit; Flutter'ın hata ayıklama şeridiyle aynı yerde durur, böylece yuvarlak
/// ekran köşeli telefonlarda (iPhone köşe yarıçapı 39–62 pt) da görünür. Tasarım v3: bandın turuncusu
/// (kalınlığı boyunca #E5530A → #C2410C → #A9380A, üstte ince ışık çizgisi) ve beyaz 9 w800 yazı; ilk
/// açılışta köşeden süzülerek gelir. Dokunmayı engellemez, ekran okuyucuya görünmez; canlı derlemede
/// hiç çizilmez.
class EnvRibbon extends ConsumerWidget {
  const EnvRibbon({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = ref.watch(appEnvProvider).ribbon;
    if (label == null) return child;
    final base =
        Theme.of(context).textTheme.labelSmall ??
        DefaultTextStyle.of(context).style;
    final style = base.copyWith(
      color: const Color(0xFFFFFFFF),
      fontSize: 9,
      fontWeight: FontWeight.w800,
      height: 1,
      letterSpacing: 1.2,
      decoration: TextDecoration.none,
    );
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        child,
        Positioned(
          top: 0,
          right: 0,
          width: EnvRibbonGeometry.box,
          height: EnvRibbonGeometry.box,
          child: IgnorePointer(
            child: ExcludeSemantics(
              // İlk açılışta şerit köşeden içeri süzülür (bir kez).
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: AknMotion.of(context, AknMotion.emphasized),
                curve: AknMotion.emphasizedCurve,
                child: CustomPaint(
                  painter: _CornerRibbonPainter(label: label, style: style),
                ),
                builder: (context, v, child) => Opacity(
                  opacity: v.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(18 * (1 - v), -18 * (1 - v)),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Şerit ölçüleri (dp). Şerit merkezi köşeden köşegen boyunca [offset] uzakta: en büyük iPhone köşe
/// yarıçapında (62 pt) köşegenin görünmeyen kısmı ≈ 26 pt olduğundan yazı bunun dışında kalır.
abstract final class EnvRibbonGeometry {
  static const double offset = 32;
  static const double thickness = 12;

  /// Şeridin üst ve sağ kenarı kestiği noktaları içeren kare.
  static const double box = 64;
}

class _CornerRibbonPainter extends CustomPainter {
  _CornerRibbonPainter({required this.label, required this.style});

  final String label;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(size.width, 0)
      ..rotate(0.785398) // 45°
      ..translate(0, EnvRibbonGeometry.offset);
    final band = Rect.fromCenter(
      center: Offset.zero,
      width: EnvRibbonGeometry.offset * 3,
      height: EnvRibbonGeometry.thickness,
    );
    canvas
      ..drawRect(
        band.shift(const Offset(0, 1.5)),
        Paint()
          ..color = const Color(0x40000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      )
      // Tasarım v3: bandın turuncusu, ortası Pas (#C2410C) — beyaz yazı 5,18:1.
      ..drawRect(
        band,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE5530A), Color(0xFFC2410C), Color(0xFFA9380A)],
          ).createShader(band),
      )
      ..drawLine(
        band.topLeft,
        band.topRight,
        Paint()
          ..color = const Color(0x40FFFFFF)
          ..strokeWidth = 1,
      );
    final tp = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CornerRibbonPainter old) =>
      old.label != label || old.style != style;
}

/// Gizlilik örtüsü (spec D.7): biyometrik kilit açıkken uygulama etkin değilken (uygulama değiştirici,
/// bildirim merkezi) içerik yerel açılış ekranının zemini (açık temada beyaz, koyu temada grafit
/// #0E0F11; tasarım v3 — lacivert yok) + » işaretiyle gizlenir; ekran görüntüsünde müşteri ve tutar
/// görünmez. Örtü anında gelir (görüntü yakalanmadan önce), uygulamaya dönünce yumuşakça kalkar.
/// Uygulamanın açtığı dış etkinlikte (kamera, paylaşım, tarayıcı) örtü gösterilmez.
class PrivacyCover extends ConsumerStatefulWidget {
  const PrivacyCover({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PrivacyCover> createState() => _PrivacyCoverState();
}

class _PrivacyCoverState extends ConsumerState<PrivacyCover> {
  late final AppLifecycleListener _listener;
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onStateChange: _onState);
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  void _onState(AppLifecycleState state) {
    final away =
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused;
    final shouldCover =
        away &&
        !ExternalActivity.active &&
        ref.read(biometricLockProvider) &&
        ref.read(sessionControllerProvider) is SessionAuthenticated;
    if (shouldCover != _covered && mounted) {
      setState(() => _covered = shouldCover);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_covered,
            child: ExcludeSemantics(
              // Gelişi anında (uygulama değiştirici görüntüsünden önce), gidişi 250 ms solarak.
              child: AnimatedSwitcher(
                duration: Duration.zero,
                reverseDuration: AknMotion.of(context, AknMotion.base),
                child: _covered
                    ? ColoredBox(
                        key: const ValueKey('cover'),
                        // Yerel açılış ekranıyla aynı zemin.
                        color: dark
                            ? const Color(0xFF0E0F11)
                            : const Color(0xFFFFFFFF),
                        child: const Center(child: LogoMark(size: 72)),
                      )
                    : const SizedBox.shrink(key: ValueKey('none')),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
