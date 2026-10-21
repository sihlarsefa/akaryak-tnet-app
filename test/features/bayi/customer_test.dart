// Cariler ve cari 360 kartı: limit + bekleyen limit talebi, finans kartı bağlantısı, tahsilat,
// teslimat noktası ayrıntısı; limit talebi sayfası (CreateLimitChangeRequest alanları), görüşme notu
// ekle / sil; sipariş masası (not / limit yok, "Teklif ver" masaya cari süzgeciyle) ve saha satış
// (yalnızca portföy, "Saha formu").
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/application/customers_controller.dart';
import 'package:akaryakitnet/features/bayi/application/desk_controller.dart';
import 'package:akaryakitnet/features/bayi/presentation/customers/customers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bayi_app.dart';

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet).last, matching: f);

Finder _confirm(String label) =>
    find.descendant(of: find.byType(ConfirmSheet), matching: find.text(label));

void main() {
  testWidgets(
    'cari 360: limit, bekleyen talep, finans kartı, tahsilat ve teslimat noktası',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'sahip',
        location: '/customers/102',
      );
      expect(find.text('Marmara İnşaat Taahhüt Ltd. Şti.'), findsWidgets);
      expect(
        find.text('Bekleyen limit talebi, merkez onayında'),
        findsOneWidget,
      );
      expect(
        find.text('Limit talebi'),
        findsNothing,
        reason: 'bekleyen talep varken yenisi açılmaz',
      );
      expect(find.text('Kullanım'), findsOneWidget);
      // Tahsilat özeti.
      expect(find.text('Vadesi geçen'), findsOneWidget);
      expect(find.textContaining('2 adet'), findsOneWidget);
      // Teslimat noktası: pencere, tank, erişim, sorumlu.
      await reveal(tester, find.text('İzmit Şantiye'));
      expect(find.textContaining('Teslim 08:00–17:00'), findsOneWidget);
      expect(find.textContaining('tank 40.000'), findsOneWidget);
      expect(
        find.textContaining('Sorumlu: Serkan Polat, 0534 333 44 55'),
        findsOneWidget,
      );
      expect(find.text('Sorumluyu ara'), findsOneWidget);
      // Görüşme notları ve eylemler.
      expect(find.textContaining('Görüşme notları'), findsOneWidget);
      expect(find.text('Teklif ver'), findsOneWidget);
      // Finans kartı → /finance/customers/{stationCustomerId}.
      await scrollTap(tester, find.text('Kartı aç'));
      expect(find.text('stub:/finance/customers/502'), findsOneWidget);
      await app.finish(tester);
    },
  );

  testWidgets(
    'limit talebi: zorunlu alanlar, Limitsiz seçimi, gönderim sonrası bekleyen talep',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'sahip',
        location: '/customers/101',
      );
      expect(
        find.text('Bekleyen limit talebi, merkez onayında'),
        findsNothing,
      );
      await scrollTap(tester, find.text('Limit talebi'));
      expect(find.text('Talebi gönder'), findsOneWidget);
      expect(find.text('Mevcut limit'), findsOneWidget);

      await scrollTap(tester, find.text('Talebi gönder'));
      expect(find.text('Bu alan zorunludur.'), findsOneWidget);
      expect(find.text('Talep gerekçesi zorunludur.'), findsOneWidget);

      // Limitsiz: tutar ve tür alanları kalkar.
      await scrollTap(
        tester,
        _inSheet(find.widgetWithText(ChoiceChip, 'Limitsiz')),
      );
      expect(find.text('Limit türü'), findsNothing);
      await scrollTap(
        tester,
        _inSheet(find.widgetWithText(ChoiceChip, 'Aylık')),
      );
      expect(find.text('Limit türü'), findsOneWidget);

      final fields = _inSheet(find.byType(TextField));
      await tester.enterText(fields.at(0), '3000000');
      await tester.enterText(fields.at(1), 'Kış dönemi tüketim artışı');
      await BayiTestApp.settle(tester);
      await scrollTap(tester, find.text('Talebi gönder'));
      expect(
        find.text('Talebi gönder'),
        findsNothing,
        reason: 'gönderildi, sayfa kapandı',
      );

      final s = app.container.read(customerSummaryProvider(101)).data!;
      expect(s.pendingLimitRequest, isNotNull);
      expect(s.pendingLimitRequest!.amount, 3000000);
      expect(s.pendingLimitRequest!.period, 'Aylık');
      expect(s.pendingLimitRequest!.limitType, 'Tutar');
      expect(
        find.text('Bekleyen limit talebi, merkez onayında'),
        findsOneWidget,
      );
      expect(find.text('Limit talebi'), findsNothing);
      await app.finish(tester);
    },
  );

  testWidgets('görüşme notu: eklenir (tek kayıt) ve silinir', (tester) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'sahip',
      location: '/customers/101',
    );
    final before = app.container
        .read(customerSummaryProvider(101))
        .data!
        .notes
        .length;
    await scrollTap(tester, find.text('Not ekle'));
    expect(find.text('Görüşme notu'), findsOneWidget);
    await tester.enterText(
      _inSheet(find.byType(TextField)),
      'Perşembe fiyat için aranacak.',
    );
    await BayiTestApp.settle(tester);
    await scrollTap(tester, find.text('Notu kaydet'));
    expect(find.text('Notu kaydet'), findsNothing);
    final notes = app.container.read(customerSummaryProvider(101)).data!.notes;
    expect(notes.length, before + 1);
    expect(notes.first.body, 'Perşembe fiyat için aranacak.');
    expect(find.text('Perşembe fiyat için aranacak.'), findsOneWidget);

    final row = find
        .ancestor(
          of: find.text('Perşembe fiyat için aranacak.'),
          matching: find.byType(Row),
        )
        .first;
    await scrollTap(
      tester,
      find.descendant(of: row, matching: find.bySemanticsLabel('Notu sil')),
    );
    expect(find.text('Not silinsin mi?'), findsOneWidget);
    await scrollTap(tester, _confirm('Sil'));
    expect(
      app.container.read(customerSummaryProvider(101)).data!.notes.length,
      before,
    );
    expect(find.text('Perşembe fiyat için aranacak.'), findsNothing);
    await app.finish(tester);
  });

  testWidgets(
    'sipariş masası: not / limit talebi yok; "Teklif ver" masayı cari süzgeciyle açar',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'siparis',
        location: '/customers/101',
      );
      expect(find.text('Anadolu Lojistik A.Ş.'), findsWidgets);
      expect(find.text('Not ekle'), findsNothing);
      expect(find.text('Limit talebi'), findsNothing);
      expect(find.text('Saha formu'), findsNothing);
      await scrollTap(tester, find.text('Teklif ver'));
      expect(app.container.read(quoteDeskProvider).customerId, 101);
      expect(find.byType(InputChip), findsOneWidget);
      await app.finish(tester);
    },
  );

  testWidgets(
    'saha satış: Portföyüm yalnızca kendi carileri; "Saha formu" cari ile açılır',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'saha',
        location: '/customers',
      );
      expect(find.text('Portföyüm'), findsWidgets);
      final rows = app.container.read(bayiCustomersProvider).list.items;
      expect(rows, isNotEmpty);
      await scrollTap(tester, find.byType(CustomerRowCard).first);
      final id = rows.first.customerId;
      expect(find.text('Portföyünüzde'), findsOneWidget);
      expect(find.textContaining('Portföy görünümü'), findsOneWidget);
      expect(find.text('Not ekle'), findsNothing);
      expect(find.text('Limit talebi'), findsNothing);
      await scrollTap(tester, find.text('Saha formu'));
      expect(
        find.textContaining(
          'stub:/field/forms/new?customerId=$id&customerTitle=',
        ),
        findsOneWidget,
      );
      await app.finish(tester);
    },
  );
}
