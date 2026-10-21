import 'dart:async';

import 'package:flutter/material.dart';

import '../motion.dart';
import '../painters/chevron_spinner.dart';
import '../painters/logo_mark.dart';
import '../theme.dart';
import '../tokens.dart';
import 'sheets.dart';

/// Slide-to-confirm for irreversible field actions (§6.26): "Teslimatı
/// kaydetmek için kaydırın", "Yola çık".
///
/// A 64 px Beton track (r14) with a 56 px logo-orange knob carrying the
/// black » of the logo. Drag the knob past 85 % to confirm: it snaps to the
/// end with a medium haptic and [onConfirmed] runs (the knob spins while its
/// future runs, then turns into an ok check in 300 ms). A short drag springs
/// back.
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

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_canAct) return;
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
    final knobColor = done
        ? c.ok.solid
        : enabled
        ? c.logo
        : c.lineStrong;
    final glyph = done
        ? c.ok.onSolid
        : enabled
        ? c.onBrandFill
        : c.surface;
    final labelStyle = t.headline.copyWith(
      color: done
          ? c.ok.fg
          : enabled
          ? c.ink
          : c.faint,
    );

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
                    color: c.surfaceAlt,
                    borderRadius: BorderRadius.circular(AknRadius.driver),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        left: _knob + _pad * 2 + 4,
                        right: 16,
                        child: Center(
                          child: Opacity(
                            opacity: done ? 1 : (1 - p * 1.6).clamp(0.0, 1.0),
                            // Two lines in the 64 px track; the label
                            // clamps at 1.3× (screen readers get the full
                            // label and the sheet path).
                            child: Text(
                              done ? widget.doneLabel : widget.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: labelStyle,
                              textScaler: MediaQuery.textScalerOf(
                                context,
                              ).clamp(maxScaleFactor: 1.3),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: knobLeft,
                        top: _pad,
                        child: AnimatedContainer(
                          duration: AknMotion.of(context, AknMotion.slideDone),
                          curve: AknMotion.standard,
                          width: _knob,
                          height: _knob,
                          decoration: BoxDecoration(
                            color: knobColor,
                            borderRadius: AknRadius.button,
                          ),
                          alignment: Alignment.center,
                          child: AnimatedSwitcher(
                            duration: AknMotion.of(
                              context,
                              AknMotion.slideDone,
                            ),
                            child: done
                                ? Icon(
                                    Icons.check_rounded,
                                    key: const ValueKey('done'),
                                    color: glyph,
                                    size: 30,
                                  )
                                : running
                                ? ChevronSpinner(
                                    key: const ValueKey('run'),
                                    size: 22,
                                    color: glyph,
                                    semanticLabel: null,
                                  )
                                : CustomPaint(
                                    key: const ValueKey('idle'),
                                    size: const Size.square(44),
                                    painter: LogoMarkPainter(
                                      progress: 1,
                                      showTile: false,
                                      tileColor: knobColor,
                                      chevronColor: glyph,
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
