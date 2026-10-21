import 'dart:async';

import 'package:flutter/material.dart';

import '../motion.dart';
import '../painters/chevron_spinner.dart';
import '../theme.dart';
import '../tokens.dart';

/// Slide-to-confirm for irreversible field actions (Yola çık, Teslim et).
///
/// Drag the knob past 85 % to confirm; it snaps to the end with a medium
/// haptic and [onConfirmed] runs (the knob spins while its future runs, then
/// shows a check). A short drag springs back. Screen-reader users confirm
/// with a double tap (semantic tap action).
class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.enabled = true,
    this.doneLabel = 'Onaylandı',
    this.resetAfterDone = false,
    this.semanticHint = 'Onaylamak için iki kez dokunun',
  });

  final String label;
  final FutureOr<void> Function() onConfirmed;
  final bool enabled;
  final String doneLabel;

  /// Return to the start after success (when the screen stays open).
  final bool resetAfterDone;
  final String semanticHint;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

enum _SlideState { idle, dragging, running, done }

class _SlideToConfirmState extends State<SlideToConfirm>
    with SingleTickerProviderStateMixin {
  static const double _height = 64;
  static const double _pad = 4;
  static const double _knob = _height - _pad * 2;

  late final AnimationController _pos = AnimationController(
    vsync: this,
    duration: AknMotion.base,
  );
  _SlideState _state = _SlideState.idle;
  double _travel = 1;

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  Duration get _d => AknMotion.of(context, AknMotion.base);

  void _onDragUpdate(DragUpdateDetails d) {
    if (!widget.enabled || _state == _SlideState.running) return;
    if (_state == _SlideState.done) return;
    _state = _SlideState.dragging;
    _pos.value = (_pos.value + d.delta.dx / _travel).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_state != _SlideState.dragging) return;
    final fling = (d.primaryVelocity ?? 0) > 900;
    if (_pos.value >= 0.85 || (fling && _pos.value > 0.4)) {
      unawaited(_confirm());
    } else {
      _state = _SlideState.idle;
      unawaited(
        _pos.animateTo(0, duration: _d, curve: AknMotion.emphasizedCurve),
      );
    }
  }

  Future<void> _confirm() async {
    if (!widget.enabled || _state == _SlideState.running) return;
    if (_state == _SlideState.done) return;
    setState(() => _state = _SlideState.running);
    AknHaptics.medium();
    await _pos.animateTo(1, duration: _d, curve: AknMotion.emphasizedCurve);
    var ok = false;
    try {
      await widget.onConfirmed();
      ok = true;
    } catch (e, st) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'akn ui',
          context: ErrorDescription('SlideToConfirm "${widget.label}"'),
        ),
      );
    }
    if (!mounted) return;
    if (ok) {
      AknHaptics.success();
      setState(() => _state = _SlideState.done);
      if (widget.resetAfterDone) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (!mounted) return;
        setState(() => _state = _SlideState.idle);
        await _pos.animateTo(0, duration: _d, curve: AknMotion.standard);
      }
    } else {
      setState(() => _state = _SlideState.idle);
      await _pos.animateTo(0, duration: _d, curve: AknMotion.emphasizedCurve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final enabled = widget.enabled;
    final done = _state == _SlideState.done;
    final running = _state == _SlideState.running;
    final trackColor = enabled ? c.brandSoft : c.surfaceAlt;
    final lineColor = enabled ? c.brandLine : c.line;
    final knobColor = done
        ? c.ok.solid
        : enabled
        ? c.brandFill
        : c.lineStrong;
    final onKnob = done ? c.ok.onSolid : const Color(0xFFFFFFFF);

    return Semantics(
      button: true,
      enabled: enabled && !running && !done,
      label: done ? widget.doneLabel : widget.label,
      hint: enabled && !done ? widget.semanticHint : null,
      onTap: enabled && !running && !done ? () => unawaited(_confirm()) : null,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          _travel = (width - _knob - _pad * 2).clamp(1.0, double.infinity);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            child: AnimatedBuilder(
              animation: _pos,
              builder: (context, _) {
                final p = _pos.value;
                final knobLeft = _pad + _travel * p;
                return Container(
                  height: _height,
                  decoration: BoxDecoration(
                    color: trackColor,
                    borderRadius: AknRadius.pillAll,
                    border: Border.all(color: lineColor),
                  ),
                  child: Stack(
                    children: [
                      // Filled trail behind the knob.
                      Positioned(
                        left: _pad,
                        top: _pad,
                        bottom: _pad,
                        width: knobLeft - _pad + _knob,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: (done ? c.ok.solid : c.brandFill).withValues(
                              alpha: 0.14 + 0.2 * p,
                            ),
                            borderRadius: AknRadius.pillAll,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        left: _knob + _pad * 2,
                        right: 16,
                        child: Center(
                          child: Opacity(
                            opacity: done ? 1 : (1 - p * 1.6).clamp(0.0, 1.0),
                            child: Text(
                              done ? widget.doneLabel : widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodyStrong.copyWith(
                                color: done
                                    ? c.ok.fg
                                    : enabled
                                    ? c.brandInk
                                    : c.faint,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: knobLeft,
                        top: _pad,
                        child: AnimatedContainer(
                          duration: _d,
                          width: _knob,
                          height: _knob,
                          decoration: BoxDecoration(
                            color: knobColor,
                            shape: BoxShape.circle,
                            boxShadow: enabled
                                ? [
                                    BoxShadow(
                                      color: c.brandFill.withValues(alpha: 0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: AnimatedSwitcher(
                            duration: AknMotion.of(context, AknMotion.fast),
                            child: done
                                ? Icon(
                                    Icons.check_rounded,
                                    key: const ValueKey('done'),
                                    color: onKnob,
                                    size: 28,
                                  )
                                : running
                                ? ChevronSpinner(
                                    key: const ValueKey('run'),
                                    size: 22,
                                    color: onKnob,
                                    semanticLabel: null,
                                  )
                                : CustomPaint(
                                    key: const ValueKey('idle'),
                                    size: ChevronRowPainter.sizeFor(22, 2),
                                    painter: ChevronRowPainter(
                                      color: onKnob,
                                      count: 2,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
