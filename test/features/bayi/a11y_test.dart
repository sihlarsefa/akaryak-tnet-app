// Erişilebilirlik (spec C.7): ana bayi ekranları 360×640'ta, metin ölçeği 1.0 ve 2.0, açık ve koyu
// temada taşmasız (liste sonuna kadar kaydırılarak); Android / iOS dokunma hedefi, etiketli dokunma
// hedefi ve metin kontrastı kılavuzları (üstte ve sonda).
import 'dart:math' as math;

import 'package:akaryakitnet/core/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bayi_app.dart';

typedef _Screen = ({String name, String persona, String location});

const _detail = 'detail';

const List<_Screen> _screens = [
  (name: 'Ana sayfa', persona: 'sahip', location: '/home-bayi'),
  (name: 'Teklif masası', persona: 'siparis', location: '/quote-desk'),
  (name: 'Siparişler', persona: 'sahip', location: '/bayi/orders'),
  (name: 'Sipariş ayrıntısı', persona: 'sahip', location: _detail),
  (name: 'Cariler', persona: 'sahip', location: '/customers'),
  (name: 'Cari 360', persona: 'sahip', location: '/customers/101'),
  (name: 'Sevkiyat panosu', persona: 'sevkiyat', location: '/dispatch'),
  (name: 'Sevkiyatlar (depo)', persona: 'depo', location: '/dispatch'),
  (name: 'Ekip', persona: 'sahip', location: '/bayi/staff'),
];

final Finder _vertical = find.byWidgetPredicate(
  (w) =>
      w is Scrollable && axisDirectionToAxis(w.axisDirection) == Axis.vertical,
);

/// Bu testte bildirilen çerçeve hatalarının tam ayrıntısı (taşan widget zinciri).
final List<String> _reports = [];

/// Yakalanan hata (taşma) varsa ayrıntısıyla başarısız olur.
void _noException(WidgetTester tester, String where) {
  final e = tester.takeException();
  if (e != null) fail('$where: $e\n${_reports.join('\n')}');
}

/// Ana dikey listeyi sonuna kadar kaydırır; her adımda taşma (RenderFlex overflow) olmamalı.
Future<void> _scrollThrough(WidgetTester tester) async {
  if (_vertical.evaluate().isEmpty) return;
  for (var i = 0; i < 60; i++) {
    final position = tester.state<ScrollableState>(_vertical.first).position;
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo(math.min(position.pixels + 400, position.maxScrollExtent));
    await tester.pump(const Duration(milliseconds: 80));
    _noException(tester, 'kaydırma adımı $i');
  }
  await BayiTestApp.settle(tester, rounds: 4);
}

void main() {
  for (final screen in _screens) {
    for (final scale in const [1.0, 2.0]) {
      for (final brightness in Brightness.values) {
        testWidgets('${screen.name} · ölçek $scale · ${brightness.name}', (
          tester,
        ) async {
          _reports.clear();
          final previous = FlutterError.onError;
          FlutterError.onError = (d) {
            _reports.add(d.toString());
            previous?.call(d);
          };
          final app = await BayiTestApp.start(
            tester,
            persona: screen.persona,
            location: screen.location == _detail
                ? '/bayi/orders'
                : screen.location,
            size: const Size(360, 640),
            textScale: scale,
            brightness: brightness,
          );
          if (screen.location == _detail) {
            final order = app.harness.world.orders.firstWhere(
              (o) =>
                  o['status'] == OrderStatus.approved.code &&
                  o['stationId'] == 1,
            );
            await app.push(tester, '/bayi/orders/${order['id']}');
          }
          _noException(tester, 'açılış');
          await expectA11y(tester);
          await _scrollThrough(tester);
          await expectA11y(tester);
          FlutterError.onError = previous;
          await app.finish(tester);
        });
      }
    }
  }
}
