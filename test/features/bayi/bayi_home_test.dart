// Bayi ana sayfası (tasarım v4 "Sade" §3.3, §5 03, §9): "Sıra sizde" bandın üstündeki ilk kart, hat
// kartın içinde, tek birincil "Teklif ver" 746'nın üstünde ve o siparişin teklif sayfasını açar;
// istatistik destesi ilk ekranda; rol kartı ve ipucu kartı yok (ilk oturum "Nasıl çalışır" hariç);
// "Bugün" defteri kahramanın sayısını yinelemez; yüklenemeyen bölüm; tazeleme hatası.
import 'dart:async';

import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/application/home_controller.dart';
import 'package:akaryakitnet/features/bayi/application/role_tip.dart';
import 'package:akaryakitnet/features/bayi/copy.dart';
import 'package:akaryakitnet/features/bayi/fake/home_fake.dart';
import 'package:akaryakitnet/features/bayi/presentation/home/home_sections.dart';
import 'package:akaryakitnet/features/bayi/presentation/home/order_pipeline.dart';
import 'package:akaryakitnet/features/bayi/presentation/home/tasks_page.dart';
import 'package:akaryakitnet/features/stats/api.dart'
    show ManagerStatsDeck, registerStatsFakes;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bayi_app.dart';

/// Telefon ekranı (v4 §9 ölçüleri): 390 × 844, alt çubuk 746'da başlar (bu ortamda çubuk yok;
/// 746 sınırı aynen denetlenir).
const _phone = Size(390, 844);

void main() {
  testWidgets(
    'sahip: "Sıra sizde" ilk kart, hat içinde, "Teklif ver" 746 üstünde, deste ilk ekranda',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'sahip',
        location: '/home-bayi',
        size: _phone,
        setup: (h) => registerStatsFakes(h.server),
      );
      await BayiTestApp.settle(tester);
      // Kahraman: bandın üstündeki ilk kart "Sıra sizde".
      final overlap = find.byType(AknBandOverlap).first;
      expect(
        find.descendant(of: overlap, matching: find.byType(AknTaskCard)),
        findsOneWidget,
      );
      expect(find.text('Sıra sizde'), findsOneWidget);
      // Hat kartın içinde (genel bakış), hale yok.
      expect(
        find.descendant(
          of: find.byType(AknTaskCard),
          matching: find.byType(OrderPipeline),
        ),
        findsOneWidget,
      );
      // Sahibin en büyük kuyruğu kartta: gecikmesi olan onaylar öndeki işin hemen altında ve
      // Onaylar'ın "Gecikmiş"iyle aynı sayıyı söyler (ana sayfa sahtesi = Onaylar deposu).
      final card = tester.widget<AknTaskCard>(find.byType(AknTaskCard));
      expect(card.tasks[1].id, 'approvals');
      expect(card.tasks[1].title, startsWith('Kararınızı bekleyen'));
      expect(card.tasks[1].subtitle, endsWith('gecikti'));
      expect(card.tasks[1].tone, AknTaskTone.danger);
      // Tek birincil: "Teklif ver", tamamı alt çubuğun (746) üstünde.
      final give = find.widgetWithText(AknButton, 'Teklif ver');
      expect(give, findsOneWidget);
      expect(tester.getRect(give).bottom, lessThan(746));
      // Deste kahramanın altında, ilk ekranda.
      final deck = find.byType(ManagerStatsDeck);
      expect(deck, findsOneWidget);
      expect(tester.getRect(deck).top, lessThan(746));
      expect(
        tester.getRect(deck).top,
        greaterThanOrEqualTo(tester.getRect(find.byType(AknTaskCard)).bottom),
      );
      // Eski ipucu ve rol kartları yok.
      expect(find.text('Teklif masası tek ekranda'), findsNothing);
      expect(tester.takeException(), isNull);
      await app.finish(tester);
    },
  );

  testWidgets('kahramanın "Teklif ver"i o siparişin teklif sayfasını açar', (
    tester,
  ) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'sahip',
      location: '/home-bayi',
    );
    await scrollTap(tester, find.widgetWithText(AknButton, 'Teklif ver'));
    await BayiTestApp.settle(tester);
    // Teklif sayfası: müşteri ve sipariş no alt başlıkta, "Teklifi gönder".
    expect(find.text('Teklifi gönder'), findsOneWidget);
    expect(find.textContaining('Körfez Nakliyat'), findsWidgets);
    await app.finish(tester);
  });

  testWidgets(
    '"Tüm işler": itilen sayfada bütün işler (alt sayfa değil); kartta ikinci bir sayı yok',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'sahip',
        location: '/home-bayi',
      );
      final card = tester.widget<AknTaskCard>(find.byType(AknTaskCard));
      expect(
        card.tasks.length,
        greaterThan(3),
        reason: 'sahibin kuyrukları karta sığmaz',
      );
      // Kuyruk kartı: başlıkta sayı hapı, altta sayılı "Tümünü gör (n)" yok — sayılar satırlarda
      // (onay satırı = Onaylar rozeti) ve hatta (P2).
      expect(card.showCount, isFalse);
      expect(find.bySemanticsLabel(RegExp(r'^Sıra sizde, \d')), findsNothing);
      expect(find.textContaining('Tümünü gör'), findsNothing);
      await scrollTap(tester, find.text('Tüm işler'));
      // v4 tur 2 (B18): diğer ana sayfalar gibi bir sayfa açılır (alt sayfa değil); başlığı bağlantının
      // sözü, satırları kartın satırları, kartın sırasıyla.
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(BayiTasksPage), findsOneWidget);
      final rows = find.descendant(
        of: find.byType(BayiTasksPage),
        matching: find.byType(AknTaskRow),
      );
      expect(rows, findsNWidgets(card.tasks.length));
      expect(
        [for (final r in tester.widgetList<AknTaskRow>(rows)) r.task.id],
        [for (final t in card.tasks) t.id],
      );
      // Teklif işi burada fiille okunur (düğme yok): "Teklif verin".
      expect(
        tester.widgetList<AknTaskRow>(rows).first.task.title,
        anyOf('Teklif verin', 'Teklifi yenileyin'),
      );
      await app.finish(tester);
    },
  );

  testWidgets('ilk oturum: "Nasıl çalışır" → Anladım; bir daha görünmez', (
    tester,
  ) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'sahip',
      location: '/home-bayi',
    );
    expect(find.text('Nasıl çalışır'), findsOneWidget);
    await scrollTap(tester, find.text('Anladım'));
    expect(find.text('Nasıl çalışır'), findsNothing);
    expect(app.container.read(bayiFirstRunHintProvider), isFalse);
    await app.finish(tester);
  });

  testWidgets('"Bugün": kahramana sığmayan işler önce; hat sayıları yinelenmez', (
    tester,
  ) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'sahip',
      location: '/home-bayi',
    );
    await reveal(tester, find.text('Bugün'));
    final today = tester.widget<BayiTodayLedger>(find.byType(BayiTodayLedger));
    final card = tester.widget<AknTaskCard>(find.byType(AknTaskCard));
    // Karttaki ilk üç iş (öndeki + iki satır) Bugün'de yok; kalanlar en üstte. Hattın saydığı
    // Plan sayısız yazılır (v4 tur 2 B18: "Sevkiyatı planlayın", sayı hatta).
    expect(today.overflow.map((t) => t.id), [
      for (final t in card.tasks.skip(3)) t.id,
    ]);
    final plan = today.overflow.where((t) => t.id == 'plan');
    if (plan.isNotEmpty) {
      expect(plan.single.title, 'Sevkiyatı planlayın');
      expect(plan.single.title, isNot(matches(RegExp(r'\d'))));
    }
    // Kurulum uyarılarında bugünün Tüpraş fiyatı yok (o iş kartta).
    expect(find.textContaining('Tüpraş fiyatı girilmedi'), findsNothing);
    await app.finish(tester);
  });

  testWidgets(
    'depo: rol kartı yok, kahraman "Sıra sizde"; tahsilat ve finans yok',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'depo',
        location: '/home-bayi',
      );
      expect(find.byType(AknTaskCard), findsOneWidget);
      expect(find.text('Sevkiyat panosu'), findsNothing);
      expect(find.textContaining('Vadesi geçen'), findsNothing);
      expect(find.textContaining('finans kartı'), findsNothing);
      expect(tester.takeException(), isNull);
      await app.finish(tester);
    },
  );

  testWidgets(
    'yüklenemeyen bölüm "Bu bölüm yüklenemedi" der; yetkisiz bölüm hiç görünmez',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'muhasebe',
        location: '/home-bayi',
        setup: (h) => h.server.get('home/bayi', (req) {
          final json = bayiHomeJson(req.world, findFakePersona('muhasebe')!);
          (json['sections'] as Map)['collections'] = null;
          json['failedSections'] = ['collections'];
          return json;
        }),
      );
      expect(find.textContaining(BayiCopy.sectionFailed), findsOneWidget);
      expect(find.textContaining(RegExp(r'^Vadesi geçen \d')), findsNothing);
      expect(
        find.textContaining('sevkiyat'),
        findsNothing,
        reason: 'yetki yok',
      );
      await app.finish(tester);
    },
  );

  testWidgets('tazeleme hatası: içerik kalır, "son güncelleme" görünür', (
    tester,
  ) async {
    var fail = false;
    final app = await BayiTestApp.start(
      tester,
      persona: 'sahip',
      location: '/home-bayi',
      setup: (h) => h.server.get('home/bayi', (req) {
        if (fail) throw FakeResponse.server();
        return bayiHomeJson(req.world, findFakePersona('sahip')!);
      }),
    );
    expect(find.byType(OrderPipeline), findsOneWidget);
    fail = true;
    unawaited(app.container.read(bayiHomeProvider.notifier).refresh());
    await BayiTestApp.settle(tester);
    expect(find.byType(OrderPipeline), findsOneWidget, reason: 'içerik kalır');
    await reveal(tester, find.textContaining('son güncelleme'));
    expect(find.textContaining('son güncelleme'), findsOneWidget);
    await app.finish(tester);
  });

  testWidgets('rolü olmayan bayi: "Hesabınıza henüz rol atanmadı"', (
    tester,
  ) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'sahip',
      location: '/home-bayi',
      setup: (h) => h.server
        ..get(
          'home/bayi',
          (req) => {
            'stationId': 1,
            'stationTitle': 'Demir Petrol',
            'sections': <String, Object?>{},
            'failedSections': <String>[],
          },
        )
        ..get(
          'notifications/unread-count',
          (req) => {'notifications': 0, 'approvals': 0},
        )
        ..get('bayi/orders/counts', (req) => <String, Object?>{}),
    );
    expect(find.text(BayiCopy.homeEmptyTitle), findsOneWidget);
    expect(find.text(BayiCopy.homeEmptyMessage), findsOneWidget);
    await app.finish(tester);
  });
}
