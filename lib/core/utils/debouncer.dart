import 'dart:async';

/// Son çağrıdan [delay] sonra bir kez çalışır (ör. saha formu canlı önizlemesi 600 ms).
class Debouncer {
  Debouncer(this.delay);

  final Duration delay;
  Timer? _timer;

  void call(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  bool get isPending => _timer?.isActive ?? false;

  void cancel() => _timer?.cancel();

  void dispose() => cancel();
}
