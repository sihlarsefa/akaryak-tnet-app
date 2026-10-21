import 'dart:async';

import 'package:flutter/material.dart';

import '../../utils/format.dart';
import '../../utils/tr_time.dart';
import '../../utils/turkish_text.dart';
import '../motion.dart';
import '../painters/progress_ring.dart';
import '../status.dart';
import '../theme.dart';
import '../tokens.dart';

enum StatusChipSize { small, medium }

/// Status pill: tone tint + icon + Turkish label (never colour alone).
/// Colour changes cross-fade (base 250 ms).
///
/// ```dart
/// StatusChip.style(order.status.statusStyle.withLabel(order.statusLabel))
/// ```
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.solid = false,
    this.size = StatusChipSize.medium,
    this.showIcon = true,
  });

  StatusChip.style(
    StatusStyle style, {
    super.key,
    this.size = StatusChipSize.medium,
    this.showIcon = true,
  }) : label = style.label,
       tone = style.tone,
       icon = style.icon,
       solid = style.solid;

  final String label;
  final AknTone tone;
  final IconData? icon;
  final bool solid;
  final StatusChipSize size;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final tc = c.tone(tone);
    final small = size == StatusChipSize.small;
    final fg = solid ? tc.onSolid : tc.fg;
    final duration = AknMotion.of(context, AknMotion.base);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: duration,
        curve: AknMotion.standard,
        padding: EdgeInsets.symmetric(
          horizontal: small ? 7 : 9,
          vertical: small ? 2 : 3,
        ),
        decoration: BoxDecoration(
          color: solid ? tc.solid : tc.bg,
          borderRadius: AknRadius.pillAll,
          border: Border.all(color: solid ? tc.solid : tc.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showIcon && icon != null) ...[
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: fg),
                duration: duration,
                builder: (context, color, _) =>
                    Icon(icon, size: small ? 12 : 14, color: color),
              ),
              SizedBox(width: small ? 3 : 4),
            ],
            Flexible(
              child: AnimatedDefaultTextStyle(
                duration: duration,
                style: context.aknText.captionStrong.copyWith(
                  color: fg,
                  fontSize: small ? 11 : 12,
                  height: small ? 14 / 11 : 16 / 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Expiry countdown ("2 sa 15 dk") with an optional ring showing the time
/// left. Tone: neutral → warn under 2 h → danger under 30 min; expired is
/// neutral "Süresi doldu". Ticks every second in the last hour.
class CountdownBadge extends StatefulWidget {
  const CountdownBadge({
    super.key,
    required this.deadline,
    this.start,
    this.prefix,
    this.showRing = true,
    this.warnBefore = const Duration(hours: 2),
    this.dangerBefore = const Duration(minutes: 30),
    this.onExpired,
  });

  /// Expiry instant (UTC `DateTime` per `TrTime`).
  final DateTime deadline;

  /// When the countdown started (quote time); enables the ring.
  final DateTime? start;

  /// Text before the time ("Kalan").
  final String? prefix;
  final bool showRing;
  final Duration warnBefore;
  final Duration dangerBefore;
  final VoidCallback? onExpired;

  @override
  State<CountdownBadge> createState() => _CountdownBadgeState();
}

class _CountdownBadgeState extends State<CountdownBadge> {
  Timer? _timer;
  bool _expiredNotified = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(CountdownBadge old) {
    super.didUpdateWidget(old);
    if (old.deadline != widget.deadline) {
      _expiredNotified = false;
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    final left = widget.deadline.difference(TrTime.now());
    if (left.isNegative) return;
    final every = left.inMinutes < 60
        ? const Duration(seconds: 1)
        : const Duration(seconds: 30);
    _timer = Timer.periodic(every, (_) {
      if (!mounted) return;
      final l = widget.deadline.difference(TrTime.now());
      setState(() {});
      if (l.isNegative) {
        _timer?.cancel();
        if (!_expiredNotified) {
          _expiredNotified = true;
          widget.onExpired?.call();
        }
      } else if (l.inMinutes < 60 && every.inSeconds > 1) {
        _schedule();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final left = widget.deadline.difference(TrTime.now());
    final expired = left.inSeconds <= 0;
    final tone = expired
        ? AknTone.neutral
        : left <= widget.dangerBefore
        ? AknTone.danger
        : left <= widget.warnBefore
        ? AknTone.warn
        : AknTone.neutral;
    final tc = c.tone(tone);
    final text = expired
        ? 'Süresi doldu'
        : '${widget.prefix == null ? '' : '${widget.prefix} '}'
              '${Fmt.countdown(left)}';
    double? fraction;
    final start = widget.start;
    if (widget.showRing && start != null && !expired) {
      final total = widget.deadline.difference(start).inSeconds;
      if (total > 0) fraction = (left.inSeconds / total).clamp(0.0, 1.0);
    }
    return Semantics(
      label: expired ? 'Süresi doldu' : 'Kalan süre ${Fmt.countdown(left)}',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: AknMotion.of(context, AknMotion.base),
        padding: const EdgeInsets.fromLTRB(6, 3, 9, 3),
        decoration: BoxDecoration(
          color: tc.bg,
          borderRadius: AknRadius.pillAll,
          border: Border.all(color: tc.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (fraction != null)
              ProgressRing(
                value: fraction,
                size: 14,
                strokeWidth: 2,
                color: tc.fg,
                trackColor: tc.line,
                duration: AknMotion.slow,
              )
            else
              Icon(
                expired ? Icons.timer_off_rounded : Icons.schedule_rounded,
                size: 14,
                color: tc.fg,
              ),
            const SizedBox(width: 5),
            // Dar yerde (2,0× yazı) taşmaz: iki satıra iner.
            Flexible(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.aknText.captionStrong.copyWith(
                  color: tc.fg,
                  fontSize: 12,
                  height: 16 / 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Initials avatar with a calm, deterministic tint (never purple), or an
/// image when given.
class AknAvatar extends StatelessWidget {
  const AknAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.image,
    this.tone,
  });

  final String name;
  final double size;
  final ImageProvider? image;

  /// Forces a tint; otherwise derived from the name.
  final AknTone? tone;

  static const _tints = [
    AknTone.info,
    AknTone.ok,
    AknTone.warn,
    AknTone.brand,
    AknTone.neutral,
  ];

  static AknTone toneFor(String name) {
    var h = 0;
    for (final r in TurkishText.searchKey(name).runes) {
      h = (h * 31 + r) & 0x7fffffff;
    }
    return _tints[h % _tints.length];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final tc = c.tone(tone ?? toneFor(name));
    final initials = TurkishText.initials(name);
    return Semantics(
      label: name,
      image: true,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: tc.bg,
          shape: BoxShape.circle,
          border: Border.all(color: tc.line),
          image: image == null
              ? null
              : DecorationImage(image: image!, fit: BoxFit.cover),
        ),
        alignment: Alignment.center,
        child: image != null
            ? null
            : Text(
                initials,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: tc.fg,
                  fontSize: size * 0.38,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}
