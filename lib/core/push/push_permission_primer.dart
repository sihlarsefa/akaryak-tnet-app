import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_controller.dart';
import '../storage/prefs_store.dart';
import '../ui/ui.dart';
import 'push_providers.dart';
import 'push_service.dart';

/// İlk girişten sonra bir kez: bildirim izninden önce ne işe yaradığını anlatan yumuşak ön sayfa
/// (spec C.4, C.7). Push kapalıysa (Firebase yapılandırması yok) ya da izin zaten verildi/reddedildiyse
/// gösterilmez. Müşterilere girişte değil, ilk siparişten sonra sorulur (A2); bayi personeli (şoför,
/// onaycı, masa) ve merkez girişte görür. Gösterildiyse true döner (aynı oturumda başka öneri açılmaz).
Future<bool> maybeShowPushPrimer(BuildContext context, WidgetRef ref) async {
  if (!ref.read(firebaseAvailableProvider)) return false;
  if (ref.read(accessPolicyProvider).isCustomer) return false;
  final prefs = ref.read(prefsStoreProvider);
  if (prefs.getBool(PrefKeys.pushPrimerShown)) return false;
  final push = ref.read(pushServiceProvider);
  if (await push.permission() != PushPermission.notDetermined) return false;
  await prefs.setBool(PrefKeys.pushPrimerShown, true);
  if (!context.mounted) return false;
  final accepted = await showAppSheet<bool>(
    context: context,
    showClose: false,
    builder: (ctx) => const _PrimerBody(),
  );
  if (accepted ?? false) unawaited(push.requestPermission());
  return true;
}

/// Tasarım v3: yumuşak turuncu bir dairede zil belirir, birkaç kez çalar (sönümlenen sallanma) ve
/// çevresine iki dalga yayar; ardından başlık, metin ve düğmeler sırayla yükselir. Hareket azaltmada
/// her şey son karesiyle görünür.
class _PrimerBody extends StatefulWidget {
  const _PrimerBody();

  @override
  State<_PrimerBody> createState() => _PrimerBodyState();
}

class _PrimerBodyState extends State<_PrimerBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
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

  /// Linear progress of [_c] between [a] and [b] (0..1).
  double _seg(double a, double b) => ((_c.value - a) / (b - a)).clamp(0.0, 1.0);

  /// Fades and lifts [child] in between [a] and [b] (structure stays fixed).
  Widget _rise(double a, double b, Widget child) => AnimatedBuilder(
    animation: _c,
    child: child,
    builder: (context, child) {
      final v = AknMotion.emphasizedCurve.transform(_seg(a, b));
      return Opacity(
        opacity: v,
        alwaysIncludeSemantics: true,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - v)),
          child: child,
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Center(child: _bell(c)),
        const SizedBox(height: 18),
        _rise(
          0.12,
          0.45,
          Text(
            'Önemli anları kaçırmayın',
            style: t.title.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        _rise(
          0.17,
          0.5,
          Text(
            'Teklif hazır olduğunda, siparişiniz onaylandığında, aracınız yola çıktığında ve onayınız '
            'beklendiğinde haber verelim. Ayarlardan istediğiniz zaman değiştirebilirsiniz.',
            style: t.body.copyWith(color: c.dim),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        _rise(
          0.22,
          0.55,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AknButton(
                label: 'Bildirimlere izin ver',
                expand: true,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 8),
              AknButton.ghost(
                label: 'Şimdi değil',
                expand: true,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The ringing bell on its soft orange disc, with two ripples.
  Widget _bell(AknColors c) {
    const size = 76.0;
    return SizedBox.square(
      dimension: size + 36,
      child: AnimatedBuilder(
        animation: _c,
        child: Icon(
          PhosphorIconsRegular.bellRinging,
          color: c.brandInk,
          size: 34,
        ),
        builder: (context, icon) {
          final appear = _seg(0, 0.3);
          final scale = 0.6 + 0.4 * AknMotion.pop.transform(appear);
          // The bell swings four times from its top, each swing smaller.
          final ring = _seg(0.22, 0.78);
          final angle = ring <= 0 || ring >= 1
              ? 0.0
              : 0.32 * math.sin(ring * 4 * 2 * math.pi) * (1 - ring);
          return Stack(
            alignment: Alignment.center,
            children: [
              for (final start in const [0.24, 0.46])
                _ripple(c, size, _seg(start, start + 0.5)),
              Opacity(
                opacity: appear,
                alwaysIncludeSemantics: true,
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: c.brandSoft,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.brandLine),
                    ),
                    alignment: Alignment.center,
                    child: Transform.rotate(
                      angle: angle,
                      alignment: const Alignment(0, -0.8),
                      child: icon,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// One ripple: a fixed ring that scales outwards and fades (no relayout).
  Widget _ripple(AknColors c, double size, double v) {
    return IgnorePointer(
      child: Opacity(
        opacity: v <= 0 || v >= 1 ? 0 : (1 - v),
        child: Transform.scale(
          scale: 1 + 0.45 * Curves.easeOut.transform(v),
          child: SizedBox.square(
            dimension: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: c.brand.withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
