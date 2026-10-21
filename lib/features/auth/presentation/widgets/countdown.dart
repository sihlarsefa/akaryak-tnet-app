import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/auth_clock.dart';

/// [until] anına kadar her saniye yeniden çizer (kilitlenme, yeniden gönderim, kod geçerliliği). Süre
/// dolunca bir kez [onDone] çağrılır. Zamanlayıcı saniye sınırına hizalanır, böylece "45 sn" ile
/// sunucunun beklettiği süre uyuşur. Geri sayım hareket değildir; azaltılmış harekette de işler.
class CountdownBuilder extends ConsumerStatefulWidget {
  const CountdownBuilder({
    super.key,
    required this.until,
    required this.builder,
    this.onDone,
  });

  /// Bitiş anı; null ya da geçmişse kalan süre sıfırdır.
  final DateTime? until;
  final Widget Function(BuildContext context, Duration remaining) builder;
  final VoidCallback? onDone;

  @override
  ConsumerState<CountdownBuilder> createState() => _CountdownBuilderState();
}

class _CountdownBuilderState extends ConsumerState<CountdownBuilder> {
  Timer? _timer;
  bool _doneFired = false;

  DateTime _now() => ref.read(authClockProvider)();

  Duration get _remaining {
    final until = widget.until;
    if (until == null) return Duration.zero;
    final r = until.difference(_now());
    return r.isNegative ? Duration.zero : r;
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(CountdownBuilder old) {
    super.didUpdateWidget(old);
    if (old.until != widget.until) {
      _doneFired = false;
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    final remaining = _remaining;
    if (remaining <= Duration.zero) return;
    final ms = remaining.inMilliseconds % 1000;
    _timer = Timer(Duration(milliseconds: ms == 0 ? 1000 : ms), _tick);
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    if (_remaining <= Duration.zero) {
      _timer = null;
      if (!_doneFired) {
        _doneFired = true;
        widget.onDone?.call();
      }
      return;
    }
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _remaining);
}
