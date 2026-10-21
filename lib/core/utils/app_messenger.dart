import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bildirim tonu (renk + ikon; görünüm `core/ui` içinde).
enum AppMessageTone { info, success, warning, error }

/// Bağlamsız yerlerden (ağ katmanı, push, bekleyen işlemler) kullanıcıya kısa bildirim.
class AppMessage {
  const AppMessage(
    this.text, {
    this.tone = AppMessageTone.info,
    this.route,
    this.title,
  });
  final String text;
  final String? title;
  final AppMessageTone tone;

  /// Dokununca açılacak uygulama rotası (ör. ön plandaki push).
  final String? route;
}

/// Uygulama kabuğu bu akışı dinleyip bildirimi gösterir (`app/app.dart`).
class AppMessenger {
  final _controller = StreamController<AppMessage>.broadcast();
  final Map<String, DateTime> _recent = {};

  Stream<AppMessage> get stream => _controller.stream;

  /// Aynı metin [dedupe] süresi içinde tekrar gösterilmez.
  void show(
    AppMessage message, {
    Duration dedupe = const Duration(seconds: 3),
  }) {
    final now = DateTime.now();
    final last = _recent[message.text];
    if (last != null && now.difference(last) < dedupe) return;
    _recent[message.text] = now;
    if (!_controller.isClosed) _controller.add(message);
  }

  void info(String text) => show(AppMessage(text));
  void success(String text) =>
      show(AppMessage(text, tone: AppMessageTone.success));
  void warning(String text) =>
      show(AppMessage(text, tone: AppMessageTone.warning));
  void error(String text) => show(AppMessage(text, tone: AppMessageTone.error));

  Future<void> dispose() => _controller.close();
}

final appMessengerProvider = Provider<AppMessenger>((ref) {
  final m = AppMessenger();
  ref.onDispose(m.dispose);
  return m;
});
