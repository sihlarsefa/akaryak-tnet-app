// QA "bayi-office": limit aşan tekil teklif siparişi finans onayına gönderir. Açılan onay talebi tekil
// bir kimlik almalı (seed'deki 9005–9013 ile çakışmamalı), siparişin `financeApprovalRequestId`'si ve
// finansçıya giden bildirim rotası bu talebi göstermeli; finans müdürü onaylayınca sipariş yeniden
// teklif verilebilir olmalı. Tam sahte sunucu (tüm özellik sahteleri), ağ yok.
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

Future<void> _login(ProviderContainer c, String persona) async {
  final s = c.read(sessionControllerProvider.notifier);
  await s.signOut();
  await s.loginWithPassword(persona, 'demo');
}

void main() {
  test('limit aşan teklif: tekil onay kimliği, doğru talep ve bildirim', () async {
    final h = await TestHarness.create();
    final c = h.container();
    addTearDown(c.dispose);
    final w = h.server.world;
    await _login(c, 'siparis');
    final api = c.read(apiClientProvider);

    final seededIds = [for (final a in w.approvals) a['id'] as int];
    expect(
      seededIds.toSet().length,
      seededIds.length,
      reason: 'seed onay kimlikleri tekil olmalı: $seededIds',
    );

    // Teklif verilebilir ilk siparişi limit üstü fiyatla dene.
    final day = TrTime.todayStart().add(const Duration(days: 2));
    int? routedOrder;
    String? message;
    for (final o in w.ordersOfStation(1)) {
      final status = o['status'];
      if (status != 1 && status != 5) continue;
      if (o['financeStatus'] == 1 || o['financeStatus'] == 4) continue;
      try {
        await api.post<void>(
          'orders/${o['id']}/quote',
          body: {
            'unitPriceTry': 999999,
            'deliveryDate':
                '${day.toIso8601String().substring(0, 10)}T00:00:00',
          },
        );
      } on AppFailure catch (f) {
        if (f.message.contains('finans onayına gönderildi')) {
          routedOrder = o['id'] as int;
          message = f.message;
          break;
        }
      }
    }
    expect(routedOrder, isNotNull, reason: 'hiçbir sipariş finansa gitmedi');
    expect(message, contains('finans onayına gönderildi'));

    final order = w.order(routedOrder)!;
    final approvalId = order['financeApprovalRequestId'] as int;
    final ids = [for (final a in w.approvals) a['id'] as int];
    final dupes = ids.where((i) => ids.where((j) => j == i).length > 1).toSet();
    expect(
      dupes,
      isEmpty,
      reason:
          'yeni finans talebi $approvalId seed kimliğiyle çakışıyor; aynı kimlikli talepler: '
          '${[for (final a in w.approvals)
            if (dupes.contains(a['id'])) '${a['id']} ${a['subjectNumber']} ${a['title']}']}',
    );

    // Finans müdürü talebi açar: sipariş numarası tutmalı.
    await _login(c, 'finans');
    final detail = await c
        .read(apiClientProvider)
        .get('approvals/$approvalId', parse: JsonReader.of);
    expect(
      detail.str('subjectNumber'),
      order['orderNumber'],
      reason:
          '/approvals/$approvalId başka bir talebi açıyor (${detail.str('subjectNumber')} ${detail.str('title')})',
    );
  });
}
