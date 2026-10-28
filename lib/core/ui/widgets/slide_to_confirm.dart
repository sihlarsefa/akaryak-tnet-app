import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../motion.dart';
import '../painters/chevron_spinner.dart';
import '../painters/logo_mark.dart';
import '../theme.dart';
import '../tokens.dart';
import 'sheets.dart';

/// Slide-to-confirm for irreversible field actions (§6.26, v3 §4/§5):
/// "Teslimatı kaydetmek için kaydırın", "Yola çık".
///
/// A 64 px `surfaceAlt` pill track with a 56 px round knob in the orange
/// gradient (with its warm glow) carrying the white » of the logo; the »
/// nudges towards the end and a soft orange glint sweeps across the hint
/// while it waits (ambient). Dragging lifts the knob and lays a soft orange
/// trail behind it; past 85 % it snaps to the end with a medium haptic and
/// [onConfirmed] runs (the knob spins while its future runs), then the knob
/// morphs into a green ok check that pops, the trail turns green, the done
/// label glides into the space beside the knob and a success haptic plays.
/// A short drag springs back.
///
/// Accessible path: with a screen reader or switch control running
/// (`MediaQuery.accessibleNavigation`) the semantic tap opens a
/// [ConfirmSheet] with a normal [confirmLabel] button ("Teslimatı kaydet")
/// instead of asking for a drag; [confirmWithSheet] forces either way.
class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.enabled = true,
    this.doneLabel = 'Onaylandı',
    this.resetAfterDone = false,
    this.semanticHint = 'Onaylamak için iki kez dokunun',
    this.confirmTitle,
    this.confirmMessage,
    this.confirmLabel = 'Onayla',
    this.confirmWithSheet,
  });

  final String label;
  final FutureOr<void> Function() onConfirmed;
  final bool enabled;
  final String doneLabel;

  /// Return to the start after success (when the screen stays open).
  final bool resetAfterDone;
  final String semanticHint;

  /// Title of the accessible confirm sheet (defaults to [label]).
  final String? confirmTitle;

  /// Sentence under the sheet title.
  final String? confirmMessage;

  /// The sheet's confirm button: verb + object ("Teslimatı kaydet").
  final String confirmLabel;

  /// Null: the semantic tap opens the sheet when an accessibility service
  /// drives the app, otherwise it confirms directly. True / false force it.
  final bool? confirmWithSheet;

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

  bool get _canAct =>
      widget.enabled &&
      _state != _SlideState.running &&
      _state != _SlideState.done;

  void _onDragStart(DragStartDetails d) {
    if (!_canAct) return;
    _pos.stop();
    AknHaptics.selection();
    setState(() => _state = _SlideState.dragging);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_canAct) return;
    if (_state != _SlideState.dragging) {
      setState(() => _state = _SlideState.dragging);
    }
    _pos.value = (_pos.value + d.delta.dx / _travel).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_state != _SlideState.dragging) return;
    final fling = (d.primaryVelocity ?? 0) > 900;
    if (_pos.value >= 0.85 || (fling && _pos.value > 0.4)) {
      unawaited(_confirm());
    } else {
      setState(() => _state = _SlideState.idle);
      // A short drag springs back to the start.
      unawaited(
        _pos.animateTo(
          0,
          duration: AknMotion.of(context, const Duration(milliseconds: 420)),
          curve: AknMotion.spring,
        ),
      );
    }
  }

  /// Screen-reader / switch path: a sheet with a plain confirm button.
  Future<void> _accessibleConfirm() async {
    if (!_canAct) return;
    final sheet =
        widget.confirmWithSheet ??
        (MediaQuery.maybeAccessibleNavigationOf(context) ?? false);
    if (!sheet) return _confirm();
    final ok = await showConfirmSheet(
      context,
      title: widget.confirmTitle ?? widget.label,
      message: widget.confirmMessage,
      confirmLabel: widget.confirmLabel,
    );
    if (ok && mounted) await _confirm();
  }

  Future<void> _confirm() async {
    if (!_canAct) return;
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
    final dragging = _state == _SlideState.dragging;
    final idle = _state == _SlideState.idle;
    final reduced = AknMotion.reduced(context);
    final knobColor = done
        ? c.ok.solid
        : enabled
        ? c.logo
        : c.lineStrong;
    final knobFill = done || !enabled
        ? LinearGradient(colors: [knobColor, knobColor])
        : c.buttonGradient;
    final knobGlow = done
        ? AknShadows.glow(c.ok.solid)
        : enabled
        ? AknShadows.button(c)
        : const <BoxShadow>[];
    final glyph = done
        ? c.ok.onSolid
        : enabled
        ? c.onBrandFill
        : c.surface;
    final labelColor = done
        ? c.ok.fg
        : enabled
        ? c.ink
        : c.faint;
    final labelStyle = t.headline.copyWith(fontSize: 16, color: labelColor);
    final sweep = enabled && idle && AknMotion.ambientOf(context);
    final slide = AknMotion.of(context, AknMotion.slideDone);

    Widget hint(String text) => Text(
      text,
      key: ValueKey(text),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: labelStyle,
      // Two lines in the 64 px track; the label clamps at 1.3× (screen
      // readers get the full label and the sheet path).
      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
    );

    Widget label = AnimatedSwitcher(
      duration: slide,
      child: hint(done ? widget.doneLabel : widget.label),
    );
    if (sweep) {
      // A soft orange glint sweeps across the hint (Pas, still AA).
      label = AknAmbient(
        period: const Duration(milliseconds: 2600),
        child: label,
        builder: (context, v, child) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) {
            final x = -0.4 + 1.8 * v;
            return LinearGradient(
              colors: [c.ink, c.ink, c.brandInk, c.ink, c.ink],
              stops: [
                0,
                (x - 0.2).clamp(0.0, 1.0),
                x.clamp(0.0, 1.0),
                (x + 0.2).clamp(0.0, 1.0),
                1,
              ],
            ).createShader(rect);
          },
          child: child,
        ),
      );
    }

    Widget knobGlyph() {
      if (done) {
        return Icon(
          PhosphorIconsRegular.check,
          key: const ValueKey('done'),
          color: glyph,
          size: 30,
        );
      }
      if (running) {
        return ChevronSpinner(
          key: const ValueKey('run'),
          size: 22,
          color: glyph,
          semanticLabel: null,
        );
      }
      final mark = CustomPaint(
        size: const Size.square(44),
        painter: LogoMarkPainter(
          progress: 1,
          showTile: false,
          tileColor: knobColor,
          chevronColor: glyph,
        ),
      );
      // The » leans towards the end while it waits (ambient).
      return KeyedSubtree(
        key: const ValueKey('idle'),
        child: enabled && idle
            ? AknAmbient(
                period: AknMotion.breathe,
                reverse: true,
                child: mark,
                builder: (context, v, child) => Transform.translate(
                  offset: Offset(3.5 * v, 0),
                  child: child,
                ),
              )
            : mark,
      );
    }

    return Semantics(
      button: true,
      enabled: _canAct,
      label: done ? widget.doneLabel : widget.label,
      hint: _canAct ? widget.semanticHint : null,
      onTap: _canAct ? () => unawaited(_accessibleConfirm()) : null,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          _travel = (width - _knob - _pad * 2).clamp(1.0, double.infinity);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            child: AnimatedBuilder(
              animation: _pos,
              builder: (context, _) {
                final p = _pos.value;
                final knobLeft = _pad + _travel * p;
                // The trail behind the knob: soft orange while sliding,
                // green once done.
                final trailOpacity = done ? 1.0 : (p * 2.5).clamp(0.0, 1.0);
                return Container(
                  height: _height,
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: AknRadius.pillAll,
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: done ? width : knobLeft + _knob + _pad,
                        child: Opacity(
                          opacity: trailOpacity,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: AknRadius.pillAll,
                              gradient: LinearGradient(
                                colors: done
                                    ? [c.ok.bg, c.ok.bg]
                                    : [
                                        c.brandSoft.withValues(alpha: 0.4),
                                        c.brandSoft,
                                      ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // The hint sits beside the waiting knob; once done the
                      // label glides into the space left of the knob.
                      AnimatedPositioned(
                        duration: slide,
                        curve: AknMotion.emphasizedCurve,
                        top: 0,
                        bottom: 0,
                        left: done ? 20 : _knob + _pad * 2 + 4,
                        right: done ? _knob + _pad * 2 + 4 : 16,
                        child: Center(
                          child: Opacity(
                            opacity: done ? 1 : (1 - p * 1.6).clamp(0.0, 1.0),
                            child: label,
                          ),
                        ),
                      ),
                      Positioned(
                        left: knobLeft,
                        top: _pad,
                        child: AnimatedScale(
                          scale: dragging && !reduced ? 1.06 : 1,
                          duration: dragging
                              ? AknMotion.press
                              : AknMotion.pressOut,
                          curve: dragging
                              ? AknMotion.standard
                              : AknMotion.spring,
                          child: AnimatedContainer(
                            duration: slide,
                            curve: AknMotion.standard,
                            width: _knob,
                            height: _knob,
                            decoration: BoxDecoration(
                              color: knobColor,
                              gradient: knobFill,
                              shape: BoxShape.circle,
                              boxShadow: knobGlow,
                            ),
                            alignment: Alignment.center,
                            child: AnimatedSwitcher(
                              duration: slide,
                              transitionBuilder: (child, a) => FadeTransition(
                                opacity: a,
                                child: ScaleTransition(
                                  scale: a.drive(
                                    Tween<double>(
                                      begin: 0.4,
                                      end: 1,
                                    ).chain(CurveTween(curve: AknMotion.pop)),
                                  ),
                                  child: child,
                                ),
                              ),
                              child: knobGlyph(),
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
