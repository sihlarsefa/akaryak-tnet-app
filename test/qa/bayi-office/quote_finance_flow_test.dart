// QA "bayi-office" uçtan uca akış (gerçek uygulama, tam sahte sunucu, 360×640):
// 1. Sipariş masası (siparis) sipariş ayrıntısında "Teklif ver": boş fiyat gönderilmez (doğrulama),
//    limit üstü fiyat siparişi finans onayına gönderir (uyarı bildirimi, sayfada istisna yok).
// 2. Finans müdürü (finans) aynı dünyada Onaylarım'da talebi açar ve "Onayla" ile karar verir.
// 3. Sipariş masası siparişi yeniden açar: finans engeli kalkmış, teklif yeniden verilebilir.
import 'dart:async';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/a11y.dart';
import 'office_support.dart';

Future<void> _relogin(OfficeApp app, String persona) async {
  await app.tester.runAsync(() async {
    final s = app.container.read(sessionControllerProvider.notifier);
    await s.signOut();
    await s.loginWithPassword(persona, 'demo');
  });
  await app.settle(rounds: 10);
}

Future<void> _tapText(OfficeApp app, String text) async {
  AppToast.dismiss();
  await app.tester.pump(const Duration(milliseconds: 300));
  final f = find.text(text).last;
  await app.tester.ensureVisible(f);
  await app.tester.pump(const Duration(milliseconds: 100));
  await app.tester.tap(f, warnIfMissed: false);
  await app.settle(rounds: 8);
}

Future<void> _flow(
  WidgetTester tester,
  A11yVariant variant, {
  String? unitPrice,
  String tag = '',
}) async {
  final app = await OfficeApp.start(tester, 'siparis', variant: variant);
  final w = app.harness.server.world;
  // Teklif verilebilir, finans engeli olmayan, cari limiti tanımlı bir sipariş.
  JsonMap? target;
  for (final o in w.ordersOfStation(1)) {
    if (o['status'] != 1) continue;
    if (o['financeStatus'] == 1 || o['financeStatus'] == 4) continue;
    final link = w.link(1, o['customerId'] as int);
    if (link?['limitAmount'] == null || link?['limitType'] == 'Litre') {
      continue;
    }
    target = o;
    break;
  }
  expect(target, isNotNull, reason: 'limitli, teklif bekleyen sipariş yok');
  final id = target!['id'] as int;

  unawaited(app.router.push('/bayi/orders/$id'));
  await app.settle(rounds: 10);
  app.check('sipariş ayrıntısı $id');
  expect(find.text('Teklif ver'), findsWidgets);
  await _tapText(app, 'Teklif ver');
  expect(find.text('Teklifi gönder'), findsOneWidget);

  // Boş fiyat: gönderilmez, sayfa açık kalır.
  final field = find.descendant(
    of: find.byType(BottomSheet),
    matching: find.byType(TextField),
  );
  await tester.enterText(field.first, '');
  await _tapText(app, 'Teklifi gönder');
  expect(
    find.text('Teklifi gönder'),
    findsOneWidget,
    reason: 'boş fiyatla sayfa kapandı',
  );
  expect(target['financeStatus'] == 1, isFalse);

  // Limit üstü (gerçekçi) fiyat: kullanılabilir limiti %20 aşan tutar, finans onayına gider.
  final link = w.link(1, target['customerId'] as int)!;
  final limit = (link['limitAmount'] as num).toDouble();
  final used = (link['used'] as num?)?.toDouble() ?? 0;
  final qty = (target['quantityLiters'] as num).toDouble();
  final over = ((limit - used) * 1.2 / qty).clamp(1, 999999).toDouble();
  final price = unitPrice ?? (over.ceilToDouble()).toStringAsFixed(0);
  await tester.enterText(field.first, price);
  await app.settle(rounds: 4);
  await _tapText(app, 'Teklifi gönder');
  app.check('limit üstü teklif');
  expect(target['financeStatus'], 1, reason: 'sipariş finansa gitmedi');
  final approvalId = target['financeApprovalRequestId'] as int;

  // Finans müdürü karar verir.
  await _relogin(app, 'finans');
  app.router.go('/approvals');
  await app.settle(rounds: 10);
  app.check('finans Onaylarım');
  unawaited(app.router.push('/approvals/$approvalId'));
  await app.settle(rounds: 10);
  app.check('finans onay ayrıntısı $approvalId');
  expect(find.text('Onayla'), findsWidgets, reason: 'karar düğmesi yok');
  await _tapText(app, 'Onayla');
  // Karar sayfası açıldıysa onu da onayla.
  if (find.text('Onayla').evaluate().length > 1 ||
      find.byType(BottomSheet).evaluate().isNotEmpty) {
    await _tapText(app, 'Onayla');
  }
  app.check('finans onay kararı');
  final approval = w.approvals.firstWhere((a) => a['id'] == approvalId);
  expect(approval['status'], isNot(0), reason: 'talep hâlâ bekliyor');
  expect(
    target['financeStatus'] == 1 || target['financeStatus'] == 4,
    isFalse,
    reason: 'onaydan sonra sipariş hâlâ finans engelinde',
  );

  // Sipariş masası yeniden teklif verebilir.
  await _relogin(app, 'siparis');
  unawaited(app.router.push('/bayi/orders/$id'));
  await app.settle(rounds: 10);
  app.check('onay sonrası sipariş ayrıntısı');
  expect(
    find.textContaining('Teklif'),
    findsWidgets,
    reason: 'onay sonrası teklif eylemi yok',
  );
  await app.finish();
  expectNoProblems(
    app,
    'quote_finance_flow_${variant.textScale.toStringAsFixed(0)}x$tag',
  );
}

void main() {
  testWidgets('teklif → finans onayı → onay → yeniden teklif (1,0× açık)', (
    tester,
  ) async {
    await _flow(tester, const A11yVariant(1, Brightness.light));
  });
  // QA BO-03 (quote_sheet.dart "Tahmini tutar" satırı) ve QA BO-04 (decision_sheets.dart karar
  // sayfası özet tutarı) 2,0×'te taşıyordu; düzeltildi, bu akış onları korur.
  testWidgets('teklif → finans onayı → onay → yeniden teklif (2,0× koyu)', (
    tester,
  ) async {
    await _flow(tester, A11yVariant.largeDark);
  });
  // QA BO-04: 1,0×'te 11+ haneli tutar (birim fiyat 999.999 ₺) karar özetinde 41 px taşıyordu.
  testWidgets('teklif → finans onayı → onay (1,0× açık, çok büyük tutar)', (
    tester,
  ) async {
    await _flow(
      tester,
      const A11yVariant(1, Brightness.light),
      unitPrice: '999999',
      tag: '_buyuk',
    );
  });
}
