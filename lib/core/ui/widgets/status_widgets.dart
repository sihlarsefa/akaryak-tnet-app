import 'dart:async';

import 'package:flutter/material.dart';

import '../../utils/format.dart';
import '../../utils/tr_time.dart';
import '../../utils/turkish_text.dart';
import '../status.dart';
import '../theme.dart';
import '../tokens.dart';
import 'lamp.dart';

export 'lamp.dart';

enum StatusChipSize { small, medium }

/// A status, rendered as a lamp and a word ([AknLamp], design v2 §6.12) —
/// no pill, no tint, no icon (the [icon] stays in the data for semantics).
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

  /// Kept for semantics and API stability; lamps draw no icon.
  final IconData? icon;
  final bool solid;
  final StatusChipSize size;

  /// Ignored in v2 (lamps draw no icon).
  final bool showIcon;

  @override
  Widget build(BuildContext context) => AknLamp(
    label: label,
    tone: tone,
    solid: solid,
    size: size == StatusChipSize.small ? AknLampSize.small : AknLampSize.medium,
    maxLines: 2,
  );
}

/// The expiry countdown (design v2 §6.13): `timer_outlined` 17 and
/// "2 sa 57 dk kaldı" (14/20).
///
/// * Dim 500 by default; Pas 600 when it is the viewer's turn ([yourMove]);
///   under [dangerBefore] (30 min) danger 600 with the filled
///   `timer_rounded`. Expired: "Süresi doldu", dim.
/// * The text sits in a fixed-width box measured once per magnitude ("88 sa
///   88 dk kaldı"), right-aligned, so it never jitters while it ticks — once
///   a minute (every second in the last minute).
/// * Screen readers hear "Teklif 2 saat 57 dakika içinde sona eriyor"
///   ([subject] + the time left).
///
/// [start], [showRing] and [warnBefore] are kept for API stability (v2 has
/// no ring and no warn stage). A [prefix] other than "Kalan" replaces the
/// "kaldı" form ("Ödeme 2 sa 57 dk").
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
    this.yourMove = false,
    this.subject,
    this.expiredLabel = 'Süresi doldu',
  });

  /// Expiry instant (UTC `DateTime` per `TrTime`).
  final DateTime deadline;

  /// Kept for API stability (no ring in v2).
  final DateTime? start;

  /// Text before the time; "Kalan" (or null) uses "… kaldı".
  final String? prefix;

  /// Kept for API stability (no ring in v2).
  final bool showRing;

  /// Kept for API stability (v2: dim → Pas → danger).
  final Duration warnBefore;
  final Duration dangerBefore;
  final VoidCallback? onExpired;

  /// The viewer has to act: Pas 600.
  final bool yourMove;

  /// What expires, for screen readers ("Teklif", "Onay").
  final String? subject;
  final String expiredLabel;

  /// "2 saat 57 dakika" (screen readers).
  static String spoken(Duration d) {
    if (d.inSeconds <= 0) return '0 dakika';
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    if (days > 0) return hours > 0 ? '$days gün $hours saat' : '$days gün';
    if (d.inHours > 0) {
      return minutes > 0
          ? '${d.inHours} saat $minutes dakika'
          : '${d.inHours} saat';
    }
    if (d.inMinutes > 0) return '${d.inMinutes} dakika';
    return '${d.inSeconds} saniye';
  }

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
    if (left.inSeconds <= 0) return;
    final Duration next;
    if (left.inMinutes < 1) {
      next = const Duration(seconds: 1);
    } else {
      final rem = left - Duration(minutes: left.inMinutes);
      next = rem <= Duration.zero
          ? const Duration(minutes: 1)
          : rem + const Duration(milliseconds: 20);
    }
    _timer = Timer(next, () {
      if (!mounted) return;
      setState(() {});
      final l = widget.deadline.difference(TrTime.now());
      if (l.inSeconds <= 0) {
        if (!_expiredNotified) {
          _expiredNotified = true;
          widget.onExpired?.call();
        }
      } else {
        _schedule();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _text(Duration left) => _wrap(Fmt.countdown(left));

  String _wrap(String time) {
    final p = widget.prefix?.trim();
    if (p == null || p.isEmpty || TurkishText.lower(p) == 'kalan') {
      return '$time kaldı';
    }
    return '$p $time';
  }

  /// The widest text of the same magnitude (fixed box, §3.3).
  String _widest(Duration left) => _wrap(
    left.inDays > 0
        ? '8 g 88 sa'
        : left.inHours > 0
        ? '88 sa 88 dk'
        : left.inMinutes > 0
        ? '88 dk'
        : '88 sn',
  );

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final left = widget.deadline.difference(TrTime.now());
    final expired = left.inSeconds <= 0;
    final urgent = !expired && left <= widget.dangerBefore;
    final color = expired
        ? c.dim
        : urgent
        ? c.danger.fg
        : widget.yourMove
        ? c.brandInk
        : c.dim;
    final weight = !expired && (urgent || widget.yourMove)
        ? FontWeight.w600
        : FontWeight.w500;
    final style = t.bodySmall.copyWith(color: color, fontWeight: weight);
    final text = expired ? widget.expiredLabel : _text(left);
    final scaler = MediaQuery.textScalerOf(context);
    final iconSize = scaler.scale(17).clamp(17.0, 34.0);
    final subject = widget.subject;
    final spoken = expired
        ? '${subject == null ? '' : '$subject, '}${widget.expiredLabel}'
        : '${subject == null ? '' : '$subject '}'
              '${CountdownBadge.spoken(left)} içinde sona eriyor';
    final icon = Icon(
      expired
          ? Icons.timer_off_outlined
          : urgent
          ? Icons.timer_rounded
          : Icons.timer_outlined,
      size: iconSize,
      color: color,
    );
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      // The fixed box holds icon + text, right-aligned, so the icon hugs the
      // text and nothing moves while the minutes tick (§3.3, §6.13).
      child: LayoutBuilder(
        builder: (context, constraints) {
          var box = 0.0;
          if (!expired) {
            final tp = TextPainter(
              text: TextSpan(text: _widest(left), style: style),
              textDirection: TextDirection.ltr,
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            box = tp.width.ceilToDouble() + iconSize + 5;
            tp.dispose();
          }
          final min = constraints.hasBoundedWidth
              ? box.clamp(0.0, constraints.maxWidth)
              : box;
          return ConstrainedBox(
            constraints: BoxConstraints(minWidth: min),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                icon,
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    text,
                    style: style,
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Initials avatar (§6.28): a Beton circle with ink initials 600 (no hue
/// tints), or an image when given.
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

  /// Kept for API stability (v2 avatars have no tints).
  final AknTone? tone;

  static const _tints = [
    AknTone.info,
    AknTone.ok,
    AknTone.warn,
    AknTone.brand,
    AknTone.neutral,
  ];

  /// A stable tone per name (kept for API stability; v2 draws no tint).
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
    final initials = TurkishText.initials(name);
    return Semantics(
      label: name,
      image: true,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          shape: BoxShape.circle,
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
                style: context.aknText.label.copyWith(
                  color: c.ink,
                  fontSize: size * 0.38,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}
