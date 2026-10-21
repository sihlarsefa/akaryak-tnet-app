import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../application/auth_clock.dart';
import '../../application/auth_throttle.dart';
import '../../copy.dart';
import 'countdown.dart';

/// Birincil eylem düğmesi; sunucu [scope] için bekleme istediyse kapalıdır ve kalan süreyi sayar
/// ("Tekrar dene · 0:45"). Süre dolunca bekleme kalkar, düğme eski hâline döner.
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
      builder: (context, remaining) => _button(
        label: AuthCopy.retryIn(formatWait(remaining)),
        semanticLabel: AuthCopy.retryInSpoken(spokenWait(remaining)),
        onPressed: null,
      ),
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
