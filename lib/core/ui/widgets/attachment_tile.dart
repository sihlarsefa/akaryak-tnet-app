import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../utils/format.dart';
import '../../utils/turkish_text.dart';
import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import 'animated_number.dart';
import 'buttons.dart';
import 'cards.dart';
import 'status_widgets.dart';

enum AttachmentTileState { idle, uploading, failed, done }

/// A document or photo (design v3 §4) on a white card (radius 20, the soft
/// card shadow; flat with a hairline on a card, a sheet or the hero card):
/// a 44 px leading — the thumbnail (radius 14) or the file glyph in a soft
/// squircle — the name (15/20 600), a meta line (kind, size) and a status
/// pill, and a small secondary button on the right ("Yükle", "Tekrar dene",
/// "Görüntüle"). At large text, or when the button would squeeze the name,
/// the button moves under the texts (nothing is cut).
///
/// Motion: while uploading, an orange line runs round the leading's own
/// outline — it glides with [progress], or travels round while the share
/// is unknown (ambient, so it rests in tests and under reduce motion) — and
/// the leading sinks a touch; when the upload is done the line closes and
/// fades while a green check pops onto the corner (a failed upload's line
/// retracts). The remove button pops in when it appears. A tappable tile
/// presses (scale 0.97, `surfaceAlt`).
class AttachmentTile extends StatelessWidget {
  const AttachmentTile({
    super.key,
    required this.fileName,
    this.kindLabel,
    this.sizeBytes,
    this.contentType,
    this.subtitle,
    this.thumbnail,
    this.state = AttachmentTileState.idle,
    this.progress,
    this.errorText,
    this.onTap,
    this.onRetry,
    this.onDelete,
    this.onUpload,
    this.actionLabel,
  });

  final String fileName;

  /// "Çek görseli", "Vergi levhası".
  final String? kindLabel;
  final int? sizeBytes;

  /// `application/pdf`, `image/jpeg`… picks the icon.
  final String? contentType;

  /// Extra line (uploader, date).
  final String? subtitle;

  /// Image preview (e.g. `Image.memory`, `CachedNetworkImage`).
  final Widget? thumbnail;
  final AttachmentTileState state;

  /// 0..1 while uploading.
  final double? progress;
  final String? errorText;

  /// Opens the file ("Görüntüle").
  final VoidCallback? onTap;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;

  /// Picks and uploads a file ("Yükle") while the slot is empty.
  final VoidCallback? onUpload;

  /// Replaces the trailing button's label.
  final String? actionLabel;

  bool get _isPdf =>
      (contentType ?? '').contains('pdf') ||
      fileName.asciiLower.endsWith('.pdf');

  bool get _isImage =>
      (contentType ?? '').startsWith('image/') ||
      RegExp(
        r'\.(jpe?g|png|heic|webp)$',
        caseSensitive: false,
      ).hasMatch(fileName);

  /// Below this width the texts get the whole row and the button moves
  /// under them.
  static const double _minInfo = 150;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final scaler = MediaQuery.textScalerOf(context);
    final large = scaler.scale(10) >= 13;
    final details = [
      ?kindLabel,
      if (sizeBytes != null) Fmt.fileSize(sizeBytes),
    ].join(', ');
    final (String? stateText, AknTone tone) = switch (state) {
      AttachmentTileState.uploading => (
        progress == null
            ? 'Yükleniyor'
            : 'Yükleniyor %${((progress ?? 0) * 100).round()}',
        AknTone.info,
      ),
      AttachmentTileState.failed => (
        errorText ?? 'Yüklenemedi',
        AknTone.danger,
      ),
      AttachmentTileState.done => ('Yüklendi', AknTone.ok),
      AttachmentTileState.idle => (null, AknTone.neutral),
    };
    final (String? buttonLabel, VoidCallback? buttonAction) = switch (state) {
      AttachmentTileState.failed when onRetry != null => (
        actionLabel ?? 'Tekrar dene',
        onRetry,
      ),
      AttachmentTileState.idle when onUpload != null => (
        actionLabel ?? 'Yükle',
        onUpload,
      ),
      AttachmentTileState.idle || AttachmentTileState.done when onTap != null =>
        (actionLabel ?? 'Görüntüle', onTap),
      _ => (null, null),
    };
    final failed = state == AttachmentTileState.failed;
    final glyph = _isPdf
        ? PhosphorIconsRegular.filePdf
        : _isImage
        ? PhosphorIconsRegular.image
        : PhosphorIconsRegular.fileText;
    final leading = _Leading(
      thumbnail: thumbnail,
      icon: glyph,
      tone: failed ? AknTone.danger : null,
      state: state,
      progress: progress,
      handoff: ('AttachmentTile.ring', fileName),
    );
    final metaStyle = t.label.copyWith(
      fontWeight: FontWeight.w400,
      color: c.dim,
    );

    final info = Semantics(
      container: true,
      button: onTap != null,
      label: [
        fileName,
        if (details.isNotEmpty) details,
        ?subtitle,
        ?stateText,
      ].join(', '),
      onTap: onTap,
      excludeSemantics: true,
      child: Row(
        // At large text the leading lines up with the name instead of
        // floating in the middle of a tall block.
        crossAxisAlignment: large
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fileName,
                  style: t.bodyStrong.copyWith(height: 20 / 15),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    style: metaStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: metaStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                // The pill fades through to the new state (Yükleniyor →
                // Yüklendi) and the height follows.
                AknAnimatedSize(
                  alignment: AlignmentDirectional.topStart,
                  child: FadeThroughSwitcher(
                    alignment: AlignmentDirectional.topStart,
                    child: stateText == null
                        ? const SizedBox.shrink()
                        : Padding(
                            key: ValueKey(state),
                            padding: const EdgeInsets.only(top: 6),
                            child: StatusChip(
                              label: stateText,
                              tone: tone,
                              size: StatusChipSize.small,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final showDelete =
        onDelete != null && state != AttachmentTileState.uploading;
    final button = buttonLabel == null
        ? null
        : AknButton.secondary(
            label: buttonLabel,
            size: AknButtonSize.small,
            onPressed: buttonAction,
          );
    final remove = AnimatedSwitcher(
      duration: AknMotion.of(context, const Duration(milliseconds: 300)),
      switchInCurve: AknMotion.pop,
      switchOutCurve: AknMotion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: showDelete
          ? IconButton(
              key: const ValueKey('delete'),
              tooltip: 'Kaldır',
              onPressed: onDelete,
              icon: Icon(PhosphorIconsRegular.trash, color: c.dim),
            )
          : const SizedBox.shrink(key: ValueKey('none')),
    );
    return _AttachmentSurface(
      onTap: onTap,
      child: Padding(
        // The remove button brings its own 48 px target, so the card's
        // right padding shrinks when it is there.
        padding: EdgeInsets.fromLTRB(14, 12, showDelete ? 4 : 14, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The button sits beside the texts only while they keep at least
            // [_minInfo]; at large text, or on a narrow card, it goes under
            // them, lined up with the name.
            var stack = button != null && large;
            if (button != null && !stack && constraints.hasBoundedWidth) {
              final tp = TextPainter(
                text: TextSpan(
                  text: buttonLabel,
                  style: t.button.copyWith(fontSize: 15, height: 20 / 15),
                ),
                textDirection: TextDirection.ltr,
                textScaler: scaler,
                maxLines: 1,
              )..layout();
              final buttonWidth = tp.width + 32;
              tp.dispose();
              final room =
                  constraints.maxWidth -
                  (_Leading.size + 12) -
                  (8 + buttonWidth) -
                  (showDelete ? AknSpace.minTap : 0);
              stack = room < _minInfo;
            }
            // One structure for both layouts: when the button moves (an
            // upload ends and "Görüntüle" appears), the texts and the leading
            // keep their state, so the line still closes and the check pops;
            // the card eases to its new height.
            return AknAnimatedSize(
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: stack
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      Expanded(child: info),
                      if (button != null && !stack) ...[
                        const SizedBox(width: 8),
                        button,
                      ],
                      remove,
                    ],
                  ),
                  if (button != null && stack)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: _Leading.size + 12,
                        top: 10,
                        end: 10,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: button,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The tile's card: white with the soft shadow on the page, flat with a
/// hairline on a surface; presses when tappable.
class _AttachmentSurface extends StatefulWidget {
  const _AttachmentSurface({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_AttachmentSurface> createState() => _AttachmentSurfaceState();
}

class _AttachmentSurfaceState extends State<_AttachmentSurface> {
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final flat = AknCardScope.onSurface(context);
    final reduced = AknMotion.reduced(context);
    final pressed = _pressed && widget.onTap != null;
    final duration = pressed ? AknMotion.press : AknMotion.pressOut;
    const radius = AknRadius.card;
    Widget body = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: radius,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        onHighlightChanged: (v) {
          if (v != _pressed) setState(() => _pressed = v);
        },
        onFocusChange: (v) {
          if (v != _focused) setState(() => _focused = v);
        },
        child: AknCardScope(child: widget.child),
      ),
    );
    body = AnimatedContainer(
      duration: AknMotion.of(context, duration),
      curve: AknMotion.standard,
      decoration: BoxDecoration(
        color: pressed ? c.surfaceAlt : c.surface,
        borderRadius: radius,
        border: flat || c.isDark ? Border.all(color: c.line) : null,
        boxShadow: flat
            ? null
            : pressed
            ? AknShadows.pressed(c)
            : AknShadows.card(c),
      ),
      foregroundDecoration: _focused
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.fromBorderSide(AknTheme.focusRing(c)),
            )
          : null,
      child: ClipRRect(borderRadius: radius, child: body),
    );
    if (widget.onTap == null) return body;
    return AnimatedScale(
      scale: pressed && !reduced ? AknMotion.pressScale : 1,
      duration: duration,
      curve: pressed ? AknMotion.standard : AknMotion.spring,
      child: body,
    );
  }
}

/// The 44 px leading: thumbnail (radius 14) or file glyph in a squircle.
/// While uploading it sinks a touch and an orange line runs round its
/// outline; when done the line closes and fades and a green check pops onto
/// its corner.
class _Leading extends StatelessWidget {
  const _Leading({
    required this.thumbnail,
    required this.icon,
    required this.tone,
    required this.state,
    required this.progress,
    required this.handoff,
  });

  final Widget? thumbnail;
  final IconData icon;
  final AknTone? tone;
  final AttachmentTileState state;
  final double? progress;

  /// Names the tile's progress line for [AknEntranceHandoff].
  final Object handoff;

  static const double size = 44;

  /// The progress line runs this far outside the leading.
  static const double _ringGap = 3;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final thumb = thumbnail;
    final uploading = state == AttachmentTileState.uploading;
    final done = state == AttachmentTileState.done;
    final faceRadius = thumb != null ? 14.0 : size * 0.3;
    final Widget face = thumb != null
        ? ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(faceRadius)),
            child: SizedBox.square(dimension: size, child: thumb),
          )
        : AknIconBox(icon: icon, tone: tone, size: size, iconSize: 22);
    final ring = state == AttachmentTileState.idle
        ? null
        : _UploadRing(
            visible: uploading,
            // Done: the line closes; failed: it retracts.
            progress: uploading
                ? progress
                : done
                ? 1
                : 0,
            size: size + _ringGap * 2,
            radius: faceRadius + _ringGap,
            handoff: handoff,
          );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedScale(
            scale: uploading ? 0.92 : 1,
            duration: AknMotion.of(context, AknMotion.pressOut),
            curve: AknMotion.spring,
            child: face,
          ),
          if (ring != null)
            Positioned(
              left: -_ringGap,
              top: -_ringGap,
              width: size + _ringGap * 2,
              height: size + _ringGap * 2,
              child: ring,
            ),
          PositionedDirectional(
            end: -5,
            bottom: -5,
            child: AnimatedScale(
              scale: done ? 1 : 0,
              duration: AknMotion.of(
                context,
                const Duration(milliseconds: 360),
              ),
              curve: done ? AknMotion.pop : AknMotion.exit,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: c.ok.solid,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.surface, width: 2),
                ),
                alignment: Alignment.center,
                child: Icon(
                  PhosphorIconsBold.check,
                  size: 11,
                  color: c.ok.onSolid,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The upload line round the leading: it glides with [progress], travels
/// round while the share is unknown (ambient), and fades out when the
/// upload ends ([visible] false).
class _UploadRing extends StatelessWidget {
  const _UploadRing({
    required this.visible,
    required this.progress,
    required this.size,
    required this.radius,
    required this.handoff,
  });

  final bool visible;
  final double? progress;
  final double size;
  final double radius;
  final Object handoff;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final p = progress;
    final Widget line;
    if (p == null) {
      line = AknAmbient(
        period: const Duration(milliseconds: 1400),
        curve: Curves.linear,
        builder: (context, t, _) => CustomPaint(
          size: Size.square(size),
          painter: _OutlineProgressPainter(
            value: null,
            phase: t,
            radius: radius,
            color: c.brandBright,
            track: c.line,
          ),
        ),
      );
    } else {
      line = _OutlineFill(
        value: p.clamp(0.0, 1.0),
        appear: visible,
        size: size,
        radius: radius,
        color: c.brandBright,
        track: c.line,
        handoff: handoff,
      );
    }
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AknMotion.of(context, AknMotion.slow),
        curve: visible ? AknMotion.standard : AknMotion.exit,
        child: RepaintBoundary(child: line),
      ),
    );
  }
}

/// A determinate upload line: it grows from empty when it first appears
/// ([appear]) and glides to every new share ([AknMotion.slow]); a remount
/// mid-way resumes from the line on screen ([AknEntranceHandoff]).
class _OutlineFill extends StatefulWidget {
  const _OutlineFill({
    required this.value,
    required this.appear,
    required this.size,
    required this.radius,
    required this.color,
    required this.track,
    required this.handoff,
  });

  final double value;

  /// Grow in from empty when first built (false: start at [value], e.g. a
  /// tile that is already done, whose line is hidden anyway).
  final bool appear;
  final double size;
  final double radius;
  final Color color;
  final Color track;
  final Object handoff;

  @override
  State<_OutlineFill> createState() => _OutlineFillState();
}

class _OutlineFillState extends State<_OutlineFill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    value: 1,
  );
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _c,
    curve: AknMotion.standard,
  );
  double _from = 0;
  late double _to = widget.value;
  bool _started = false;

  double get _shown => _from + (_to - _from) * _t.value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final handed = AknEntranceHandoff.take(widget.handoff);
    _glide(handed ?? (widget.appear ? 0 : widget.value));
  }

  @override
  void didUpdateWidget(_OutlineFill old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _glide(_shown);
  }

  void _glide(double from) {
    _from = from;
    _to = widget.value;
    final d = AknMotion.of(context, AknMotion.slow);
    if (d == Duration.zero || (_to - from).abs() < 0.001) {
      _c.value = 1;
      return;
    }
    _c.duration = d;
    _c.forward(from: 0);
  }

  @override
  void deactivate() {
    AknEntranceHandoff.put(widget.handoff, _shown);
    super.deactivate();
  }

  @override
  void dispose() {
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    builder: (context, _) => CustomPaint(
      size: Size.square(widget.size),
      painter: _OutlineProgressPainter(
        value: _shown,
        radius: widget.radius,
        color: widget.color,
        track: widget.track,
      ),
    ),
  );
}

/// Paints upload progress along a rounded square: a soft [track] all round
/// and the [color] run from the top centre, clockwise, to [value] — or,
/// while the share is unknown ([value] null), a short run that travels
/// round ([phase] 0–1).
class _OutlineProgressPainter extends CustomPainter {
  const _OutlineProgressPainter({
    required this.value,
    required this.radius,
    required this.color,
    required this.track,
    this.phase = 0,
  });

  final double? value;
  final double radius;
  final Color color;
  final Color track;
  final double phase;

  static const double _stroke = 2.5;

  /// The share of the outline the travelling run covers.
  static const double _run = 0.3;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(_stroke / 2);
    final rr = math.min(radius - _stroke / 2, r.shortestSide / 2);
    final corner = Radius.circular(rr);
    final path = Path()
      ..moveTo(r.center.dx, r.top)
      ..lineTo(r.right - rr, r.top)
      ..arcToPoint(Offset(r.right, r.top + rr), radius: corner)
      ..lineTo(r.right, r.bottom - rr)
      ..arcToPoint(Offset(r.right - rr, r.bottom), radius: corner)
      ..lineTo(r.left + rr, r.bottom)
      ..arcToPoint(Offset(r.left, r.bottom - rr), radius: corner)
      ..lineTo(r.left, r.top + rr)
      ..arcToPoint(Offset(r.left + rr, r.top), radius: corner)
      ..close();
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, stroke..color = track);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final length = metric.length;
    stroke.color = color;
    final v = value;
    if (v != null) {
      final p = v.clamp(0.0, 1.0);
      if (p <= 0) return;
      canvas.drawPath(metric.extractPath(0, length * p), stroke);
      return;
    }
    final start = length * (phase % 1);
    final end = start + length * _run;
    canvas.drawPath(metric.extractPath(start, math.min(end, length)), stroke);
    if (end > length) {
      canvas.drawPath(metric.extractPath(0, end - length), stroke);
    }
  }

  @override
  bool shouldRepaint(_OutlineProgressPainter old) =>
      old.value != value ||
      old.radius != radius ||
      old.color != color ||
      old.track != track ||
      old.phase != phase;
}
