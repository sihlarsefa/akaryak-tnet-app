// Spec A.1 "Action → grant" tablosu: düğmeler yalnızca AccessPolicy.can / hasCap'e bakar. Personalar
// sahte sunucudan gerçek `me/access` ile gelir (rol şablonu harfleri → sayfa:yetki).
import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/features/bayi/application/bayi_grants.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bayi_harness.dart';

Future<BayiGrants> _grants(String persona) async {
  final h = await BayiHarness.create();
  final c = h.container();
  addTearDown(c.dispose);
  await BayiHarness.login(c, persona);
  return c.read(bayiGrantsProvider);
}

/// Bir personanın beklenen düğme matrisi.
Map<String, bool> _matrix(BayiGrants g) => {
  'viewDesk': g.viewDesk,
  'quoteOnDesk': g.quoteOnDesk,
  'quoteOnOrder': g.quoteOnOrder,
  'completeOrder': g.completeOrder,
  'viewBoard': g.viewBoard,
  'viewShipments': g.viewShipments,
  'planShipment': g.planShipment,
  'assignDriver': g.assignDriver,
  'dispatchOrReport': g.dispatchOrReport,
  'cancelShipment': g.cancelShipment,
  'viewCustomers': g.viewCustomers,
  'addCustomerNote': g.addCustomerNote,
  'requestLimit': g.requestLimit,
  'viewStaff': g.viewStaff,
  'manageStaff': g.manageStaff,
  'ownOnly': g.ownOnly,
};

Map<String, bool> _all(bool v, {Map<String, bool> except = const {}}) => {
  for (final k in const [
    'viewDesk',
    'quoteOnDesk',
    'quoteOnOrder',
    'completeOrder',
    'viewBoard',
    'viewShipments',
    'planShipment',
    'assignDriver',
    'dispatchOrReport',
    'cancelShipment',
    'viewCustomers',
    'addCustomerNote',
    'requestLimit',
    'viewStaff',
    'manageStaff',
    'ownOnly',
  ])
    k: except[k] ?? v,
};

void main() {
  test('bayi sahibi: her işlem açık, ownOnly değil', () async {
    expect(
      _matrix(await _grants('sahip')),
      _all(true, except: {'ownOnly': false}),
    );
  });

  test('bayi müdürü: Ekip yalnızca görüntüleme', () async {
    expect(
      _matrix(await _grants('mudur')),
      _all(true, except: {'manageStaff': false, 'ownOnly': false}),
    );
  });

  test(
    'sipariş masası: teklif ve tamamlama var; sevkiyat salt okunur, not/limit yok',
    () async {
      expect(
        _matrix(await _grants('siparis')),
        _all(
          false,
          except: {
            'viewDesk': true,
            'quoteOnDesk': true,
            'quoteOnOrder': true,
            'completeOrder': true,
            'viewBoard': true,
            'viewShipments': true,
            'viewCustomers': true,
          },
        ),
      );
    },
  );

  test(
    'sevkiyat: plan, atama, yola çıkarma, iptal; teklif ve Ekip yok',
    () async {
      expect(
        _matrix(await _grants('sevkiyat')),
        _all(
          false,
          except: {
            'viewBoard': true,
            'viewShipments': true,
            'planShipment': true,
            'assignDriver': true,
            'dispatchOrReport': true,
            'cancelShipment': true,
            'viewCustomers': true,
          },
        ),
      );
    },
  );

  test(
    'depo: yola çıkarır / teslim bildirir ama planlamaz, atamaz, iptal etmez',
    () async {
      final g = await _grants('depo');
      expect(
        _matrix(g),
        _all(
          false,
          except: {
            'viewBoard': true,
            'viewShipments': true,
            'dispatchOrReport': true,
          },
        ),
      );
      expect(g.viewOrders, isTrue);
      expect(
        g.listDrivers,
        isTrue,
        reason: 'pano görüntüleme şoför listesini açar',
      );
    },
  );

  test(
    'görüntüleyici: her şeyi görür, hiçbir işlem yapamaz; Ekip ve finans yok',
    () async {
      final g = await _grants('izleyici');
      expect(
        _matrix(g),
        _all(
          false,
          except: {
            'viewDesk': true,
            'viewBoard': true,
            'viewShipments': true,
            'viewCustomers': true,
          },
        ),
      );
      expect(g.viewPayments, isFalse);
      expect(g.viewFinance, isFalse);
      expect(g.viewApprovals, isTrue);
    },
  );

  test(
    'şoför (ownOnly): sevkiyatları görür, personel işlemleri hep kapalı',
    () async {
      final g = await _grants('sofor');
      expect(g.ownOnly, isTrue);
      expect(g.viewShipments, isTrue);
      expect(g.planShipment, isFalse);
      expect(g.assignDriver, isFalse);
      expect(g.dispatchOrReport, isFalse, reason: 'Düzenler olsa da ownOnly');
      expect(g.cancelShipment, isFalse);
      expect(g.listDrivers, isFalse);
      expect(g.viewBoard, isFalse);
    },
  );

  test('saha satış: yalnızca portföy carileri; Ekip hiçbir zaman', () async {
    final g = await _grants('saha');
    expect(g.isFieldSales, isTrue);
    expect(g.viewCustomers, isTrue);
    expect(g.addCustomerNote, isFalse);
    expect(g.requestLimit, isFalse);
    expect(g.viewStaff, isFalse);
    expect(g.viewFieldForms, isTrue);
    expect(g.createFieldForm, isTrue);
    expect(g.viewDesk, isFalse);
  });

  test('satış müdürü ve finans: not var, limit talebi (Ekler) yok', () async {
    final s = await _grants('satis');
    expect(s.addCustomerNote, isTrue);
    expect(s.requestLimit, isFalse);
    expect(s.viewStaff, isTrue);
    expect(s.manageStaff, isFalse);
    final f = await _grants('finans');
    expect(f.addCustomerNote, isTrue);
    expect(f.requestLimit, isFalse);
    expect(f.viewFinance, isTrue);
    expect(f.viewStaff, isFalse);
  });

  test('merkez: her şey açık, ownOnly hiçbir zaman', () async {
    expect(
      _matrix(await _grants('merkez')),
      _all(true, except: {'ownOnly': false}),
    );
  });

  test('canQuoteOrder: durum, finans kararı ve masa engeli', () async {
    final g = await _grants('siparis');
    const none = OrderFinanceStatus.notRequired;
    expect(g.canQuoteOrder(OrderStatus.awaitingQuote, none), isTrue);
    expect(g.canQuoteOrder(OrderStatus.revisionRequested, none), isTrue);
    expect(g.canQuoteOrder(OrderStatus.approved, none), isFalse);
    expect(
      g.canQuoteOrder(OrderStatus.awaitingQuote, OrderFinanceStatus.pending),
      isFalse,
    );
    expect(
      g.canQuoteOrder(
        OrderStatus.awaitingQuote,
        OrderFinanceStatus.infoRequested,
      ),
      isFalse,
    );
    expect(
      g.canQuoteOrder(OrderStatus.awaitingQuote, OrderFinanceStatus.rejected),
      isFalse,
    );
    expect(
      g.canQuoteOrder(OrderStatus.awaitingQuote, OrderFinanceStatus.approved),
      isTrue,
    );
    expect(
      g.canQuoteOrder(OrderStatus.awaitingQuote, none, quotingBlocked: true),
      isFalse,
    );
    final v = await _grants('izleyici');
    expect(v.canQuoteOrder(OrderStatus.awaitingQuote, none), isFalse);
  });
}
