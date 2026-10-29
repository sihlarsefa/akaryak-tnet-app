// Saha ekranları (spec A.4 A6, D.3): kişiye göre Saha sekmesi (temsilci / satış müdürü "Saha ekibi" /
// finans yalnızca ön kayıt), saha ana sayfası, form ayrıntısındaki "Yanıtla" ve "Dönüşümü yeniden
// dene", çevrimdışı taslağın bekleyen sonucu (uyarı tonu + saat), konum izni ön sayfası ve "Hassas
// konum kapalı". Ağ yok.
import 'package:akaryakitnet/core/offline/outbox_providers.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/field/application/form_wizard_controller.dart';
import 'package:akaryakitnet/features/field/application/lead_wizard_controller.dart';
import 'package:akaryakitnet/features/field/copy.dart';
import 'package:akaryakitnet/features/field/data/field_location.dart';
import 'package:akaryakitnet/features/field/presentation/widgets/field_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'field_test_kit.dart';

Finder _segment(String label) => find.text(label);

void main() {
  group('Saha sekmesi kişiye göre', () {
    testWidgets('temsilci: Formlarım · Ön kayıtlarım · Portföy', (
      tester,
    ) async {
      final app = await pumpField(tester, persona: 'saha', location: '/field');
      expect(find.text('Saha'), findsWidgets);
      expect(_segment(FieldCopy.myForms), findsOneWidget);
      expect(_segment(FieldCopy.myLeads), findsOneWidget);
      expect(_segment(FieldCopy.portfolio), findsOneWidget);
      expect(_segment(FieldCopy.pending), findsNothing);
      expect(app.log.exact('GET', 'field-orders/reps'), isEmpty);
      final list = app.log.exact('GET', 'field-orders').last.uri;
      expect(list.queryParameters['skip'], '0');
      expect(list.queryParameters['take'], '25');
      expect(find.text('Ege Tarım Kooperatifi'), findsWidgets);

      await tapText(tester, FieldCopy.portfolio);
      final portfolio = app.log.exact('GET', 'me/portfolio').last.uri;
      expect(portfolio.queryParameters['skip'], '0');
      expect(find.text('Körfez Nakliyat ve Ticaret'), findsOneWidget);

      await tapText(tester, FieldCopy.myLeads);
      expect(
        app.log.exact('GET', 'leads').last.uri.queryParameters['scope'],
        'mine',
      );
      expect(find.text('Başkent Yapı Market'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('satış müdürü: Saha ekibi, temsilci çipleri, Portföy yok', (
      tester,
    ) async {
      final app = await pumpField(tester, persona: 'satis', location: '/field');
      // v4 §3.2: başlık alt menünün kelimesi ("Saha"); ekip görünümü durum satırında.
      expect(find.text('Saha'), findsWidgets);
      expect(
        find.textContaining('Ekibin formları', findRichText: true),
        findsOneWidget,
      );
      for (final s in [
        FieldCopy.forms,
        FieldCopy.pending,
        FieldCopy.rejected,
        FieldCopy.leads,
      ]) {
        expect(_segment(s), findsOneWidget, reason: s);
      }
      expect(_segment(FieldCopy.portfolio), findsNothing);
      expect(app.log.exact('GET', 'field-orders/reps'), hasLength(1));
      expect(find.text('Deniz Koç'), findsWidgets);
      expect(find.text('Murat Şen'), findsWidgets);
      expect(find.text('Selda Ak (pasif)'), findsOneWidget);

      // Temsilciye göre süz.
      await tapText(tester, 'Murat Şen');
      final byRep = app.log.exact('GET', 'field-orders').last.uri;
      expect(byRep.queryParameters['salesRepresentativeId'], '32');

      await tapText(tester, FieldCopy.pending);
      final pending = app.log.exact('GET', 'field-orders').last.uri;
      expect(pending.queryParametersAll['statuses'], ['1']);

      await tapText(tester, FieldCopy.leads);
      expect(
        app.log.exact('GET', 'leads').last.uri.queryParameters['scope'],
        'all',
      );
      await scrollToFind(tester, find.text('Ege Lojistik Hizmetleri'));
      expect(find.text('Ege Lojistik Hizmetleri'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('finans: yalnızca ön kayıtlar (scope=all)', (tester) async {
      final app = await pumpField(
        tester,
        persona: 'finans',
        location: '/field',
      );
      expect(find.text(FieldCopy.tabLeadsOnly), findsWidgets);
      expect(_segment(FieldCopy.forms), findsNothing);
      expect(_segment(FieldCopy.portfolio), findsNothing);
      expect(app.log.exact('GET', 'field-orders'), isEmpty);
      expect(
        app.log.exact('GET', 'leads').last.uri.queryParameters['scope'],
        'all',
      );
      expect(find.text('Başkent Yapı Market'), findsOneWidget);
      await scrollToFind(tester, find.text('Ege Lojistik Hizmetleri'));
      expect(find.text('Ege Lojistik Hizmetleri'), findsOneWidget);
      // Finans ön kayıt açamaz (Ekler yok).
      expect(find.byType(FloatingActionButton), findsNothing);
      await finish(tester);
    });

    testWidgets(
      'temsilci: "Saha formu" yalnızca alt menünün ortasında; ön kayıtta düğme var',
      (tester) async {
        await pumpField(tester, persona: 'saha', location: '/field');
        expect(find.byType(FloatingActionButton), findsNothing);
        await tapText(tester, FieldCopy.myLeads);
        // Yüzen düğme yok (tasarım v2 §4.2): ekleme üst çubukta.
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(find.bySemanticsLabel('Yeni ön kayıt'), findsOneWidget);
        await finish(tester);
      },
    );

    testWidgets(
      'satış müdürü: bantta "Yeni saha formu" düğmesi; başlık "Saha"',
      (tester) async {
        await pumpField(tester, persona: 'satis', location: '/field');
        expect(find.bySemanticsLabel('Yeni saha formu'), findsOneWidget);
        expect(find.text('Saha'), findsWidgets);
        await finish(tester);
      },
    );

    testWidgets('derin bağlantı: ?tab=leads&status=info', (tester) async {
      final app = await pumpField(
        tester,
        persona: 'saha',
        location: '/field?tab=leads&status=info',
      );
      expect(
        app.log.exact('GET', 'leads').last.uri.queryParameters['status'],
        'info',
      );
      expect(find.text('Başkent Yapı Market'), findsOneWidget);
      expect(find.text('Marmara Beton Ltd. Şti.'), findsNothing);
      await finish(tester);
    });
  });

  group('Saha ana sayfası', () {
    testWidgets('temsilci: sayılar, ek bilgi bekleyen ön kayıt, bölümler', (
      tester,
    ) async {
      final app = await pumpField(tester, persona: 'saha', location: '/home');
      // v4 §3.3: "Sıra sizde" bandın üstündeki ilk kart; deste ve formlar altında.
      expect(find.byType(AknTaskCard), findsOneWidget);
      expect(find.text('Sıra sizde'), findsOneWidget);
      await scrollToFind(tester, find.text('Onayda'));
      expect(find.text('Taslak'), findsWidgets);
      expect(find.text('Onayda'), findsWidgets);
      expect(find.text('Portföy'), findsWidgets);
      // Tasarım v2 §7.16 sırası: deste → Saha formlarım (onay bekleyen, taslak, reddedilen) →
      // Ön kayıtlarım (ek bilgi bekleyenler) → Tüpraş.
      await scrollToFind(
        tester,
        find.textContaining('Onay bekleyen formlarım'),
      );
      // Form no defter satırının ikinci satırında: 'SSF-…-000007, 18.000 L, 30 gün vade' (QA LF-4:
      // tohum formları sunucu biçimiyle numaralanır, Onaylarım aynı numarayı gösterir).
      expect(find.textContaining(RegExp(r'SSF-\d{8}-000007')), findsOneWidget);
      await scrollToFind(tester, find.textContaining('Taslaklarım'));
      await scrollToFind(
        tester,
        find.textContaining('Son 30 günde reddedilenler'),
      );
      expect(find.textContaining(RegExp(r'SSF-\d{8}-000009')), findsOneWidget);
      await scrollToFind(
        tester,
        find.textContaining('Ek bilgi bekleyen ön kayıtlar'),
      );
      expect(find.text('Başkent Yapı Market'), findsOneWidget);
      final drafts = app.log
          .exact('GET', 'field-orders')
          .where(
            (r) => r.uri.queryParametersAll['statuses']?.contains('0') ?? false,
          );
      expect(drafts, isNotEmpty);
      expect(app.log.exact('GET', 'me/portfolio'), isNotEmpty);
      // Konum izni yokken hava kartı istem göstermeden beklemede kalır.
      expect(app.location.requests, 0);
      await finish(tester);
    });
  });

  group('Saha ana sayfası · hava', () {
    testWidgets('izin zaten varsa konum sessizce alınır ve hava kartı açılır', (
      tester,
    ) async {
      final app = await pumpField(
        tester,
        persona: 'saha',
        location: '/home',
        setup: (h) => h.location.access = FieldLocationAccess.granted,
      );
      await loadAppConfig(tester, app);
      await scrollToFind(tester, find.text('Bulunduğunuz yerde hava'));
      await pumpFor(tester, const Duration(milliseconds: 1500));
      expect(find.text('Bulunduğunuz yerde hava'), findsOneWidget);
      expect(app.location.requests, 0, reason: 'istem gösterilmez');
      expect(app.location.reads, greaterThanOrEqualTo(1));
      expect(app.log.all('GET', 'weather'), isNotEmpty);
      await finish(tester);
    });

    testWidgets('izin yoksa "Konumu kullan" önce ön sayfayı gösterir', (
      tester,
    ) async {
      final app = await pumpField(tester, persona: 'saha', location: '/home');
      await loadAppConfig(tester, app);
      await scrollToFind(tester, find.text('Konumu kullan'));
      await tapText(tester, 'Konumu kullan');
      expect(find.text(FieldCopy.locationPrimerTitle), findsOneWidget);
      expect(app.location.requests, 0);
      await tapText(tester, 'Şimdi değil');
      expect(app.location.requests, 0);
      await finish(tester);
    });
  });

  group('Form ayrıntısı', () {
    testWidgets('finans ek bilgi istedi → Yanıtla, Onaylarım talebini açar', (
      tester,
    ) async {
      final app = await pumpField(
        tester,
        persona: 'saha',
        location: '/field/forms/7005',
      );
      await scrollToFind(tester, find.text('Finans ek bilgi istedi'));
      expect(find.text('Finans ek bilgi istedi'), findsOneWidget);
      await tapText(tester, 'Yanıtla');
      final id = app.harness.state.forms.firstWhere(
        (f) => f['id'] == 7005,
      )['financeApprovalRequestId'];
      expect(find.text('stub:/approvals/$id'), findsOneWidget);
      await finish(tester);
    });

    testWidgets(
      'taslaktan onaya gönder: onay sayfası, Idempotency-Key, sonuç',
      (tester) async {
        final app = await pumpField(
          tester,
          persona: 'saha',
          location: '/field/forms/7009',
        );
        // 7009: 41,95 ₺/L, Körfez (104) → %5,93 → yönetici bandı.
        await tapText(tester, 'Onaya gönder');
        expect(find.text('Form onaya gönderilsin mi?'), findsOneWidget);
        await tapText(tester, 'Onaya gönder', last: true);
        await pumpFor(tester, const Duration(seconds: 2));
        final submit = app.log.exact('POST', 'field-orders/7009/submit');
        expect(submit, hasLength(1));
        expect(idempotencyKeyOf(submit.single), isNotEmpty);
        expect(
          app.harness.state.forms.firstWhere((f) => f['id'] == 7009)['status'],
          1,
        );
        mainScrollable()?.position.jumpTo(0);
        await pumpFor(tester);
        expect(find.text('Onay bekliyor'), findsWidgets);
        expect(find.text('Onaya gönder'), findsNothing);
        await finish(tester);
      },
    );

    testWidgets('çevrimdışıyken onaya gönder kapalı', (tester) async {
      final app = await pumpField(
        tester,
        persona: 'saha',
        location: '/field/forms/7009',
        online: false,
      );
      await tapText(tester, 'Onaya gönder');
      expect(find.text('Form onaya gönderilsin mi?'), findsNothing);
      expect(app.log.exact('POST', 'field-orders/7009/submit'), isEmpty);
      await finish(tester);
    });

    testWidgets('dönüşüm hatası: temsilci yeniden deneyemez', (tester) async {
      await pumpField(tester, persona: 'saha', location: '/field/forms/7008');
      await scrollToFind(
        tester,
        find.text('Bazı satırlar siparişe dönüşemedi'),
      );
      expect(find.text('Bazı satırlar siparişe dönüşemedi'), findsOneWidget);
      expect(find.text('Dönüşümü yeniden dene'), findsNothing);
      expect(
        find.textContaining('Bayi yöneticiniz kontrol edecek'),
        findsOneWidget,
      );
      await finish(tester);
    });

    testWidgets('dönüşüm hatası: satış müdürü "Dönüşümü yeniden dene"', (
      tester,
    ) async {
      final app = await pumpField(
        tester,
        persona: 'satis',
        location: '/field/forms/7008',
      );
      await scrollToFind(tester, find.text('Dönüşümü yeniden dene'));
      await tapText(tester, 'Dönüşümü yeniden dene');
      expect(find.text('Dönüşüm yeniden denensin mi?'), findsOneWidget);
      await tapText(tester, 'Yeniden dene');
      expect(
        app.log.exact('POST', 'field-orders/7008/retry-conversion'),
        hasLength(1),
      );
      mainScrollable()!.position.jumpTo(0);
      await pumpFor(tester);
      expect(find.text('Bazı satırlar siparişe dönüşemedi'), findsNothing);
      expect(find.text('Siparişe dönüştü'), findsWidgets);
      expect(
        app.harness.state.forms.firstWhere((f) => f['id'] == 7008)['status'],
        4,
      );
      await finish(tester);
    });
  });

  group('Saha formu sihirbazı', () {
    testWidgets(
      'çevrimdışı taslak: "Kaydedildi — bağlantı gelince gönderilecek" (uyarı + saat)',
      (tester) async {
        const args = FormWizardArgs(
          customerId: 103,
          customerTitle: 'Ege Tarım Kooperatifi',
        );
        final app = await pumpField(
          tester,
          persona: 'saha',
          location:
              '/field/forms/new?customerId=103&customerTitle=Ege%20Tar%C4%B1m%20Kooperatifi',
        );
        final ctrl = app.container.read(formWizardProvider(args).notifier);
        final key = app.container
            .read(formWizardProvider(args))
            .draft
            .lines
            .single
            .key;
        ctrl
          ..setLineProduct(key, 1)
          ..updateLine(key, (l) => l.copyWith(liters: 8000));
        await pumpFor(tester);
        app.container.read(onlineProvider.notifier).state = false;
        await pumpFor(tester, const Duration(milliseconds: 200));
        await tapText(tester, 'Kaydet');
        expect(find.text(FieldCopy.queuedTitle), findsOneWidget);
        expect(find.byIcon(PhosphorIconsRegular.clock), findsOneWidget);
        expect(find.text('Taslak kaydedildi'), findsNothing);
        expect(app.log.exact('POST', 'field-orders'), isEmpty);

        // Bağlantı gelince sonuç "kaydedildi"ye döner.
        app.container.read(onlineProvider.notifier).state = true;
        await tester.runAsync(
          () => app.container.read(outboxRunnerProvider).runOnce(),
        );
        await pumpFor(tester);
        expect(find.text('Taslak kaydedildi'), findsOneWidget);
        expect(app.log.exact('POST', 'field-orders'), hasLength(1));
        await finish(tester);
      },
    );
  });

  group('Konum (spec C.7)', () {
    testWidgets('ön sayfa işletim sistemi isteminden önce gelir', (
      tester,
    ) async {
      final app = await pumpField(
        tester,
        persona: 'saha',
        location: '/field/leads/new',
      );
      app.container
          .read(leadWizardProvider(const LeadWizardArgs()).notifier)
          .goTo(LeadWizardStep.visit);
      await pumpFor(tester);
      await scrollToFind(tester, find.text('Konumu ekle'));
      await tapText(tester, 'Konumu ekle');
      expect(find.text(FieldCopy.locationPrimerTitle), findsOneWidget);
      expect(app.location.requests, 0, reason: 'istem henüz gösterilmedi');
      await tapText(tester, 'Devam');
      expect(app.location.requests, 1);
      expect(app.location.reads, 1);
      expect(find.text('±8 m'), findsOneWidget);
      final draft = app.container
          .read(leadWizardProvider(const LeadWizardArgs()))
          .draft;
      expect(draft.visitAccuracyMeters, 8);
      expect(draft.hasVisitLocation, isTrue);
      await finish(tester);
    });

    testWidgets('"Şimdi değil": istem gösterilmez, konum alınmaz', (
      tester,
    ) async {
      final app = await pumpField(
        tester,
        persona: 'saha',
        location: '/field/leads/new',
      );
      app.container
          .read(leadWizardProvider(const LeadWizardArgs()).notifier)
          .goTo(LeadWizardStep.visit);
      await pumpFor(tester);
      await scrollToFind(tester, find.text('Konumu ekle'));
      await tapText(tester, 'Konumu ekle');
      await tapText(tester, 'Şimdi değil');
      expect(app.location.requests, 0);
      expect(app.location.reads, 0);
      await finish(tester);
    });

    testWidgets('yalnızca yaklaşık konum: "Hassas konum kapalı" + Ayarlar', (
      tester,
    ) async {
      final app = await pumpField(
        tester,
        persona: 'saha',
        location: '/field/leads/new',
        setup: (h) => h.location
          ..access = FieldLocationAccess.approximate
          ..approximateFix = true,
      );
      app.container
          .read(leadWizardProvider(const LeadWizardArgs()).notifier)
          .goTo(LeadWizardStep.visit);
      await pumpFor(tester);
      await scrollToFind(tester, find.text('Konumu ekle'));
      await tapText(tester, 'Konumu ekle');
      expect(find.text(FieldCopy.locationPrimerTitle), findsNothing);
      expect(find.text(FieldCopy.preciseOffTitle), findsOneWidget);
      expect(find.text('Yaklaşık konum'), findsOneWidget);
      await tapText(tester, 'Ayarları aç');
      expect(app.location.appSettings, 1);
      await finish(tester);
    });

    testWidgets('kalıcı ret: Ayarlar ve "Konumsuz devam et"', (tester) async {
      final app = await pumpField(
        tester,
        persona: 'saha',
        location: '/field/leads/new',
        setup: (h) => h.location.access = FieldLocationAccess.deniedForever,
      );
      app.container
          .read(leadWizardProvider(const LeadWizardArgs()).notifier)
          .goTo(LeadWizardStep.visit);
      await pumpFor(tester);
      await scrollToFind(tester, find.text('Konumu ekle'));
      await tapText(tester, 'Konumu ekle');
      expect(find.text(FieldCopy.locationDeniedTitle), findsOneWidget);
      expect(find.text('Konumsuz devam et'), findsOneWidget);
      await tapText(tester, 'Ayarları aç');
      expect(app.location.appSettings, 1);
      await finish(tester);
    });

    testWidgets('doğruluk çipi: hassas, düşük, yaklaşık', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AknTheme.light(),
          home: const Scaffold(
            body: Column(
              children: [
                AccuracyChip(meters: 6.4),
                AccuracyChip(meters: 85),
                AccuracyChip(meters: 1800, approximate: true),
                AccuracyChip(meters: null),
              ],
            ),
          ),
        ),
      );
      expect(find.text('±6,4 m'), findsOneWidget);
      expect(find.text('±85 m'), findsOneWidget);
      expect(find.text('Yaklaşık konum'), findsOneWidget);
      expect(find.text('Doğruluk bilinmiyor'), findsOneWidget);
    });
  });
}
