// QA "bayi-office" rota taraması: her ofis personası gerçek uygulamada (360×640) giriş yapar, ofis
// rotalarını açar (izinli olan açılmalı, izinsiz olan ilk sekmeye düşmeli), liste uçlarından ilk
// kayıtların ayrıntı sayfalarını açar. Her adımda istisna, taşma, hata durumu ve takılı iskelet aranır.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../support/a11y.dart';
import 'office_support.dart';

const _routes = [
  '/home',
  '/quote-desk',
  '/bayi/orders',
  '/customers',
  '/approvals',
  '/finance',
  '/payments',
  '/bayi/staff',
  // '/stats' ayrı: stats_overflow_test.dart (QA BO-01 / BO-02).
  '/dispatch',
  '/field',
];

Future<void> _sweep(OfficeApp app) async {
  for (final r in _routes) {
    await app.go(r);
  }
  // Ayrıntılar (yetkisi olan personada).
  if (app.allowed('/bayi/orders')) {
    final id = await app.firstId('bayi/orders', 'id');
    if (id == null) {
      app.problems.add('bayi/orders: liste boş ya da hata');
    } else {
      await app.pushAndPop('/bayi/orders/$id', label: 'sipariş ayrıntısı $id');
    }
  }
  if (app.allowed('/customers')) {
    final id = await app.firstId('bayi/customers', 'customerId');
    if (id == null) {
      app.problems.add('bayi/customers: liste boş ya da hata');
    } else {
      await app.pushAndPop('/customers/$id', label: 'cari ayrıntısı $id');
    }
  }
  if (app.allowed('/approvals')) {
    final id = await app.firstId('approvals', 'id', query: {'scope': 1});
    if (id != null) {
      await app.pushAndPop('/approvals/$id', label: 'onay ayrıntısı $id');
    }
  }
  if (app.allowed('/finance')) {
    final id = await app.firstId('finance/customers', 'stationCustomerId');
    if (id == null) {
      app.problems.add('finance/customers: liste boş ya da hata');
    } else {
      await app.pushAndPop('/finance/customers/$id', label: 'finans kartı $id');
    }
  }
  if (app.allowed('/payments')) {
    final id = await app.firstId('payments', 'orderId');
    if (id == null) {
      app.problems.add('payments: liste boş ya da hata');
    } else {
      await app.pushAndPop('/payments/$id', label: 'tahsilat ayrıntısı $id');
    }
  }
}

void main() {
  for (final persona in officePersonas) {
    testWidgets('$persona: ofis rotaları 1,0× açık', (tester) async {
      final app = await OfficeApp.start(tester, persona);
      await _sweep(app);
      await app.finish();
      expectNoProblems(app, '${persona}_sweep_1x');
    });
    testWidgets('$persona: ofis rotaları 2,0× koyu', (tester) async {
      final app = await OfficeApp.start(
        tester,
        persona,
        variant: A11yVariant.largeDark,
      );
      await _sweep(app);
      await app.finish();
      expectNoProblems(app, '${persona}_sweep_2x');
    });
  }

  testWidgets('izleyici: ayrıntıda yazma eylemi görünmez', (tester) async {
    final app = await OfficeApp.start(tester, 'izleyici');
    final id = await app.firstId('bayi/orders', 'id', query: {'view': 'quote'});
    if (id != null) {
      unawaited(app.router.push('/bayi/orders/$id'));
      await app.settle();
      for (final label in const ['Teklif ver', 'Teklif gönder', 'Tamamla']) {
        if (find.text(label).evaluate().isNotEmpty) {
          app.problems.add('izleyici sipariş $id: "$label" görünüyor');
        }
      }
    }
    await app.finish();
    expectNoProblems(app, 'izleyici_readonly');
  });
}
