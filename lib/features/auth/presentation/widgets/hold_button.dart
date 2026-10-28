import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../application/auth_clock.dart';
import '../../application/auth_throttle.dart';
import '../../copy.dart';
import 'countdown.dart';

/// Birincil eylem düğmesi; sunucu [scope] için bekleme istediyse kapalıdır ve kalan süreyi sayar
/// ("Tekrar dene (0:45)", eş genişlikte rakamlar). Beklerken düğmenin altında ince bir çizgi kalan süre
/// kadar dolu durur ve her saniye yumuşakça boşalır. Süre dolunca bekleme kalkar, düğme eski hâline
/// döner.
class HoldAwareButton extends ConsumerWidget {
  const HoldAwareButton({
    super.key,
    required this.scope,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.busyLabel = 'Gönderiliyor',
    this.icon,
    this.variant = AknButtonVariant.primary,
    this.size = AknButtonSize.large,
  });

  final ThrottleScope scope;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final String busyLabel;
  final IconData? icon;
  final AknButtonVariant variant;
  final AknButtonSize size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hold = ref.watch(authThrottleProvider)[scope];
    final now = ref.watch(authClockProvider)();
    if (hold == null || !hold.until.isAfter(now)) {
      return _button(label: label, onPressed: onPressed, loading: busy);
    }
    return CountdownBuilder(
      until: hold.until,
      onDone: () => ref.read(authThrottleProvider.notifier).clear(scope),
      builder: (context, remaining) {
        final total = hold.wait.inMilliseconds;
        final left = total <= 0
            ? 0.0
            : (remaining.inMilliseconds / total).clamp(0.0, 1.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _button(
              label: AuthCopy.retryIn(formatWait(remaining)),
              semanticLabel: AuthCopy.retryInSpoken(spokenWait(remaining)),
              onPressed: null,
            ),
            const SizedBox(height: 10),
            _DrainLine(value: left),
          ],
        );
      },
    );
  }

  Widget _button({
    required String label,
    required VoidCallback? onPressed,
    String? semanticLabel,
    bool loading = false,
  }) => switch (variant) {
    AknButtonVariant.secondary => AknButton.secondary(
      label: label,
      semanticLabel: semanticLabel,
      icon: icon,
      size: size,
      expand: true,
      loading: loading,
      loadingLabel: busyLabel,
      onPressed: onPressed,
    ),
    _ => AknButton(
      label: label,
      semanticLabel: semanticLabel,
      icon: icon,
      size: size,
      expand: true,
      loading: loading,
      loadingLabel: busyLabel,
      onPressed: onPressed,
    ),
  };
}

/// Bekleme çizgisi: 4 px hap biçimli kuyu, içinde kalan süre kadar turuncu dolgu; her saniye yumuşakça
/// kısalır (400 ms). Süs; süre düğmenin etiketinde okunur.
class _DrainLine extends StatelessWidget {
  const _DrainLine({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return ExcludeSemantics(
      child: SizedBox(
        height: 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: AknRadius.pillAll,
          ),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: value),
            duration: AknMotion.of(context, AknMotion.slow),
            curve: AknMotion.standard,
            builder: (context, v, _) => FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: v,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [c.brandFillStart, c.brand]),
                  borderRadius: AknRadius.pillAll,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
