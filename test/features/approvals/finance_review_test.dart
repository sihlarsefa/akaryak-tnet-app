// Finans birimi siparişi telefonda inceler ve onaylar (2026-11-02, "finans tarafını mobilden de
// onaylayabilmeli ve inceleyebilmeli siparişi"): sipariş finansı ayrıntısının bölümleri (gerekçe,
// ödeme, bu siparişle limit ölçeri, cari finans durumu, geçmiş), plakanın okumaları ve "Tahmini
// tutar", tek dokunuşla "Siparişi aç", dört karar rıhtımda ve her kararın onay / sonuç durumu,
// "Sıradaki talep", müşteriden yanıt beklerken başlık, push dokunuşunun açtığı ayrıntı, ana sayfanın
// sipariş finansı sayısı, boş durumlar ve eski sunucuda (summary.finance / satır anahtarı yok) yedek.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/app/tasks/task_inbox.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/push/push_focus.dart';
import 'package:akaryakitnet/core/push/push_payload.dart';
import 'package:akaryakitnet/core/push/push_providers.dart';
import 'package:akaryakitnet/core/push/push_service.dart';
import 'package:akaryakitnet/core/push/unread_count_provider.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/approvals/api.dart';
import 'package:akaryakitnet/features/approvals/application/approval_detail_controller.dart';
import 'package:akaryakitnet/features/approvals/copy.dart';
import 'package:akaryakitnet/features/approvals/data/approval_models.dart';
import 'package:akaryakitnet/features/approvals/presentation/approval_detail_page.dart';
import 'package:akaryakitnet/features/approvals/presentation/widgets/approval_card.dart';
import 'package:akaryakitnet/features/bayi/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/a11y.dart' show pumpSteps, settleIo;
import '../../support/test_app.dart';
import 'a5_test_kit.dart';

const _phone = Size(390, 844);

/// Sipariş finansı 9001'in konusu olan sipariş (Marmara İnşaat, 25.000 L, çek 60 gün).
int _orderOf9001(A5App app) =>
    app.server.world.approval(9001)!['subjectId'] as int;

Finder _key(String k) => find.byKey(ValueKey(k));

/// Eski sunucu: `summary.finance` ve satır anahtarları yok; [oldLabels] iken kartın gecikmesi eski
/// sahte etiketiyle ("Gecikmiş bakiye").
void _serveLegacyDetail(FakeServer server, {bool oldLabels = false}) {
  server.get('approvals/{id:int}', (req) {
    final p = req.requireUser();
    final a = req.world.approval(req.intParam('id'))!;
    final json = A5FakeStore.of(req.world).detail(p, a);
    final summary = Map<String, dynamic>.from(json['summary'] as Map);
    summary.remove('finance');
    summary['facts'] = [
      for (final f in (summary['facts'] as List).cast<Map>())
        {
          for (final e in f.entries)
            if (e.key != 'key') e.key: e.value,
          if (oldLabels && f['label'] == 'Gecikmiş') 'label': 'Gecikmiş bakiye',
          if (oldLabels && f['label'] == 'Gecikmiş') 'value': '120.000 ₺',
        },
    ];
    return {...json, 'summary': summary};
  });
}

/// Push servisi (Firebase yok): olay akışını test sürer.
class _TapPush extends PushService {
  _TapPush() : super(available: false);
  final ctrl = StreamController<PushEvent>.broadcast();
  @override
  Stream<PushEvent> get events => ctrl.stream;
}

void main() {
  // Eski onay akışı (birim onaycısı yöneticiyi de süzer, ön kayıt finansa gider): `FakeWorld.firstStageApprovals` kapalı.
  setUpAll(() => FakeWorld.defaultFirstStageApprovals = false);

  group('ayrıntı: finans incelemesi (yapılandırılmış summary.finance)', () {
    testWidgets(
      'plaka "Tahmini tutar" ve ödeme · limit · gecikmiş; limit aşımı plakada; "Siparişi aç" ilk ekranda',
      (tester) async {
        final app = await pumpA5(
          tester,
          persona: 'finans',
          location: '/approvals/9001',
          size: _phone,
        );
        final d = app.container.read(approvalDetailProvider(9001)).detail!;
        final r = d.financeReview!;
        expect(
          r.structured,
          isTrue,
          reason: 'sahte sunucu summary.finance verir',
        );
        // G3: teklif öncesi tutar tahmin (plakanın başlığı; siparişin satırında da tahmini tutar).
        expect(
          find.descendant(
            of: find.byType(PlateHead),
            matching: find.text(ApprovalsCopy.estimatedAmount),
          ),
          findsOneWidget,
        );
        expect(find.text(ApprovalsCopy.orderAmount), findsNothing);
        // G1: kararın üç sayısı plakada.
        final readouts = tester.widget<PlateReadouts>(
          find.byType(PlateReadouts),
        );
        expect(
          [
            for (final x in readouts.items)
              [x.label, x.value, ?x.unit].join(' '),
          ],
          ['Çek 60 gün', 'Limit %199', 'Gecikmiş Yok'],
        );
        expect(find.text('Limit aşımı 992.500 TL'), findsWidgets);
        // G10: tek dokunuş, plakanın hemen altında, finans incelemesinden önce; ilk görünümde
        // (kaydırmadan). Gerçek yazı tipiyle konum: after/f10_9001_detay.png.
        final open = _key('approval-open-order');
        expect(open, findsOneWidget);
        final link = tester.getRect(open);
        expect(
          link.top,
          greaterThan(tester.getRect(find.byType(AknPlate)).bottom),
        );
        expect(
          link.bottom,
          lessThan(
            tester.getRect(find.text(ApprovalsCopy.financeReviewTitle)).top,
          ),
        );
        expect(link.bottom, lessThan(844));
        // Alttaki "İlgili kayıtlar"da tekrarlanmaz.
        expect(find.text(ApprovalsCopy.openOrder), findsOneWidget);
        // Rıhtımın altında kalmasın (test yazı tipi gerçekten geniştir).
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -240),
        );
        await pumpFor(tester, const Duration(milliseconds: 400));
        await tapFinder(tester, open);
        expect(
          find.text('stub:/bayi/orders/${_orderOf9001(app)}'),
          findsOneWidget,
        );
        await finish(tester);
      },
    );

    testWidgets(
      'bölümler: gerekçe lambaları, ödeme ve belge, bu siparişle limit ölçeri, cari, geçmiş, sipariş',
      (tester) async {
        final app = await pumpA5(
          tester,
          persona: 'finans',
          location: '/approvals/9001',
          size: _phone,
        );
        expect(find.text(ApprovalsCopy.financeReviewTitle), findsOneWidget);
        // Gerekçe: kural sırası ve tonları (limit kırmızı, vadeli amber, kart nötr).
        for (final (kind, tone) in const [
          ('limitOverrun', AknTone.danger),
          ('paymentMethod', AknTone.warn),
          ('cardStatus', AknTone.neutral),
        ]) {
          final lamp = tester.widget<AknLamp>(_key('finance-reason-$kind'));
          expect(lamp.tone, tone, reason: kind);
        }
        // Ödeme: yöntem ve vade, belge eksik, kartla çelişki.
        expect(find.text('Çek, 60 gün vade'), findsOneWidget);
        expect(find.text('Çek görseli eklenmedi'), findsOneWidget);
        expect(
          find.text(ApprovalsCopy.termExceedsCard(45)),
          findsOneWidget,
          reason: 'sipariş 60 gün, kartın en uzun vadesi 45 gün',
        );
        // Karar verebilen eksik çek görselini talebe ekleyebilir (G8).
        expect(
          _key('approver-upload-${AttachmentKind.chequeImage.code}'),
          findsOneWidget,
        );
        // Limit: bu siparişle (940.000 + 1.052.500) / 1.000.000.
        final meter = tester.widget<UsageBar>(_key('finance-limit-meter'));
        expect(meter.value, closeTo(1.99, 0.01));
        expect(meter.label, ApprovalsCopy.usageAfter);
        expect(find.text('Kalan'), findsOneWidget);
        expect(find.text('60.000 ₺'), findsOneWidget);
        expect(find.text('Sipariş sonrası kalan'), findsOneWidget);
        expect(find.textContaining('→'), findsNothing, reason: 'yazım kuralı');
        expect(find.text('992.500 ₺'), findsOneWidget);
        expect(find.text('≈ 1.052.500 ₺'), findsWidgets);
        // Cari finans durumu: risk, rapor, gecikmiş, gözden geçirme (bant olarak tekrarlanmaz).
        expect(find.text(ApprovalsCopy.financeCardTitle), findsOneWidget);
        expect(find.textContaining('skor 588'), findsOneWidget);
        expect(find.textContaining('tarihi geçti'), findsOneWidget);
        expect(
          find.text('Finans kartının gözden geçirme tarihi geçti.'),
          findsNothing,
        );
        // Bölüm başlığında "Finans kartı" kartı açar.
        expect(find.text(ApprovalsCopy.financeCardOpen), findsOneWidget);
        // Geçmiş ve siparişin kendi satırları.
        expect(find.text(ApprovalsCopy.financeHistoryTitle), findsOneWidget);
        expect(find.text('Önceki siparişler'), findsOneWidget);
        expect(find.text(ApprovalsCopy.orderFactsTitle), findsOneWidget);
        expect(find.text('Teslimat noktası'), findsOneWidget);
        // Düz "Özet" listesi yok.
        expect(find.text('Özet'), findsNothing);
        expect(
          app.container.read(approvalDetailProvider(9001)).detail,
          isNotNull,
        );
        await finish(tester);
      },
    );

    testWidgets('liste satırı: ödeme, istisna gerekçe ve tahmini tutar (G5)', (
      tester,
    ) async {
      await pumpA5(
        tester,
        persona: 'finans',
        location: '/approvals',
        size: _phone,
      );
      final tile = tester.widget<ApprovalRowTile>(
        find.byWidgetPredicate((w) => w is ApprovalRowTile && w.row.id == 9001),
      );
      final facts = orderFinanceRowFacts(tile.row.summary);
      expect(facts.payment, 'Çek 60 gün');
      expect(facts.estimate, isTrue);
      expect(
        [for (final r in facts.reasons) r.kind],
        [
          FinanceReasonKind.limitOverrun,
          FinanceReasonKind.paymentMethod,
          FinanceReasonKind.cardStatus,
        ],
      );
      final row = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is ApprovalRowTile && w.row.id == 9001,
        ),
        matching: find.byType(AknListTile),
      );
      final list = tester.widget<AknListTile>(row);
      expect(list.amount, '≈ 1.052.500 ₺');
      expect(list.status, isNotNull, reason: 'istisna satırı');
      expect(list.semanticLabel, contains('Limit aşımı 992.500 TL'));
      // Vadeli yöntem ödeme satırında; istisna satırında tekrarlanmaz.
      expect(list.semanticLabel, isNot(contains('Vadeli yöntem')));
      await finish(tester);
    });
  });

  group('karar rıhtımı ve kararlar (onay → sonuç)', () {
    testWidgets(
      'Onayla: sonucun anlamı ve olgular sayfada; sonuç bandı, "Sıradaki talep" sıradakini açar',
      (tester) async {
        final app = await pumpA5(
          tester,
          persona: 'finans',
          location: '/approvals/9001',
          size: _phone,
        );
        // Dört karar rıhtımda (G4).
        for (final l in const [
          'Onayla',
          'Koşullu onayla',
          'Ek bilgi iste',
          'Reddet',
        ]) {
          expect(
            find.descendant(of: find.byType(ActionBar), matching: find.text(l)),
            findsOneWidget,
            reason: l,
          );
        }
        await tapText(tester, 'Onayla');
        expect(
          find.text(
            'Onaylayınca sipariş teklif aşamasına geçer. Karar kaydı geri alınamaz.',
          ),
          findsOneWidget,
        );
        expect(inSheet(find.text('Sipariş finansı')), findsOneWidget);
        expect(inSheet(find.text(ApprovalsCopy.usageAfter)), findsOneWidget);
        expect(inSheet(find.text('%199, 992.500 ₺ aşım')), findsOneWidget);
        expect(inSheet(find.text('≈ 1.052.500,00 ₺')), findsOneWidget);
        await tapText(tester, 'Onayla', last: true);
        final body = app.log.last('POST', 'approvals/9001/decide')!.data as Map;
        expect(body['decision'], ApprovalDecision.approve.code);
        await pumpFor(tester);
        expect(find.text('Talep onaylandı.'), findsOneWidget);
        final banner = tester.widget<AknBanner>(_key('approval-outcome'));
        expect(banner.title, 'Onaylandı');
        expect(banner.message, contains('Sipariş teklif aşamasına geçti.'));
        expect(banner.actionLabel, ApprovalsCopy.nextRequest);
        // Sıradaki: Bende'nin ilk talebi (gecikmiş saha formu finansı 9006).
        await tapText(tester, ApprovalsCopy.nextRequest);
        await pumpFor(tester);
        expect(
          app.router.routerDelegate.currentConfiguration.last.matchedLocation,
          '/approvals/9006',
        );
        // Aynı sayfanın yerine açılır (geri, talepten önceki sayfaya döner).
        expect(_key('approval-9006'), findsOneWidget);
        expect(_key('approval-9001'), findsNothing);
        await finish(tester);
      },
    );

    testWidgets(
      'Reddet: not zorunlu; sipariş kapanır ve limit serbest kalır denir; sonuç "Sipariş kapandı."',
      (tester) async {
        final app = await pumpA5(
          tester,
          persona: 'finans',
          location: '/approvals/9001',
          size: _phone,
        );
        await tapText(tester, 'Reddet');
        expect(
          find.text(
            'Sipariş kapanır, ayrılan limit serbest kalır. Gerekçe müşteriye iletilir.',
          ),
          findsOneWidget,
        );
        await tapText(tester, 'Reddet', last: true);
        expect(find.text('Reddetmek için gerekçe yazın.'), findsOneWidget);
        expect(app.log.all('POST', '/decide'), isEmpty);
        await typeInto(
          tester,
          'Ret gerekçesi',
          'Limit aşımı ve gecikme nedeniyle şimdilik onaylanamaz.',
        );
        await tapText(tester, 'Reddet', last: true);
        final body = app.log.last('POST', 'approvals/9001/decide')!.data as Map;
        expect(body['decision'], ApprovalDecision.reject.code);
        await pumpFor(tester);
        final banner = tester.widget<AknBanner>(_key('approval-outcome'));
        expect(banner.title, 'Reddedildi');
        expect(banner.message, contains('Sipariş kapandı.'));
        // Karardan sonra "onaydan önce Ek bilgi iste" çağrısı kalmaz (G19b).
        expect(find.textContaining('onaydan önce'), findsNothing);
        await finish(tester);
      },
    );

    testWidgets(
      'Ek bilgi iste: çek görseli önceden seçili; sonra sıra müşteride (turuncu "Karar verin" yok)',
      (tester) async {
        final app = await pumpA5(
          tester,
          persona: 'finans',
          location: '/approvals/9001',
          size: _phone,
        );
        await tapText(tester, 'Ek bilgi iste');
        expect(
          find.text('Müşteri yanıtlayana kadar sipariş bekler.'),
          findsOneWidget,
        );
        await typeInto(tester, 'Ne istiyorsunuz', 'Çek görselini yükleyin.');
        await tapText(tester, 'Ek bilgi iste', last: true);
        final body = app.log.last('POST', 'approvals/9001/decide')!.data as Map;
        expect(body['decision'], ApprovalDecision.requestInfo.code);
        expect(body['requiredAttachmentKind'], AttachmentKind.chequeImage.code);
        await pumpFor(tester);
        expect(find.text(ApprovalsCopy.waitingCustomer), findsOneWidget);
        expect(find.text(ApprovalsCopy.decideNext), findsNothing);
        expect(find.textContaining('Ek bilgi bekleniyor'), findsOneWidget);
        expect(_key('info-waiting-next'), findsOneWidget);
        await finish(tester);
      },
    );

    testWidgets(
      'Koşullu onayla rıhtımda; sonuçta koşullar okunur (yöntem, vade) ve günlükte JSON yok',
      (tester) async {
        final app = await pumpA5(
          tester,
          persona: 'finans',
          location: '/approvals/9001',
          size: _phone,
        );
        await tapText(tester, 'Koşullu onayla');
        await tapText(tester, 'Havale / EFT (peşin)');
        await typeInto(tester, 'Vade (gün)', '15');
        await tapText(tester, 'Koşullu onayla', last: true);
        final body = app.log.last('POST', 'approvals/9001/decide')!.data as Map;
        expect(body['decision'], ApprovalDecision.conditionalApprove.code);
        expect(body['conditions'], {'methodCode': 'HAVALE', 'termDays': 15});
        await pumpFor(tester);
        final banner = tester.widget<AknBanner>(_key('approval-outcome'));
        expect(banner.title, 'Koşullu onaylandı');
        expect(
          banner.message,
          contains('Ödeme yöntemi: Havale / EFT, Vade: 15 gün'),
        );
        expect(find.textContaining('methodCode'), findsNothing);
        await finish(tester);
      },
    );

    testWidgets(
      'bekleyen talep: "Bilgi alındı" sayfasında belge eklenir (G8)',
      (tester) async {
        final app = await pumpA5(
          tester,
          persona: 'finans',
          location: '/approvals/9005',
          size: _phone,
        );
        await tapText(tester, ApprovalsCopy.infoReceived);
        final add = _key('approver-upload-${AttachmentKind.chequeImage.code}');
        expect(add, findsOneWidget);
        await tapFinder(tester, add);
        expect(app.files.lastKind, AttachmentKind.chequeImage);
        final upload = app.log.last('POST', 'attachments')!;
        await finish(tester);
        expect(upload, isNotNull);
      },
    );
  });

  testWidgets(
    'müşteriden yanıt beklenirken: başlık "Müşteriden yanıt bekleniyor", rıhtım Bilgi alındı + Reddet (G2)',
    (tester) async {
      await pumpA5(
        tester,
        persona: 'finans',
        location: '/approvals/9005',
        size: _phone,
      );
      expect(find.text(ApprovalsCopy.waitingCustomer), findsOneWidget);
      expect(find.text(ApprovalsCopy.decideNext), findsNothing);
      final countdown = tester.widget<CountdownBadge>(
        find.byType(CountdownBadge),
      );
      expect(countdown.yourMove, isFalse, reason: 'geri sayım nötr');
      expect(
        find.descendant(
          of: find.byType(ActionBar),
          matching: find.text(ApprovalsCopy.infoReceived),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ActionBar),
          matching: find.text('Reddet'),
        ),
        findsOneWidget,
      );
      await finish(tester);
    },
  );

  group('eski sunucu (summary.finance ve satır anahtarı yok): aynı bölümler', () {
    testWidgets(
      'gerekçe, ödeme, kullanım ölçeri ve kart satırları özet satırlarından; plaka "Tahmini tutar"',
      (tester) async {
        final app = await pumpA5(
          tester,
          persona: 'finans',
          location: '/approvals/9001',
          size: _phone,
          overrides: const [],
        );
        _serveLegacyDetail(app.server);
        unawaited(
          app.container.read(approvalDetailProvider(9001).notifier).refresh(),
        );
        await pumpFor(tester);
        final d = app.container.read(approvalDetailProvider(9001)).detail!;
        expect(d.summary.finance, isNull);
        expect(d.summary.facts.every((f) => f.key == null), isTrue);
        final r = d.financeReview!;
        expect(r.structured, isFalse);
        expect(
          find.descendant(
            of: find.byType(PlateHead),
            matching: find.text(ApprovalsCopy.estimatedAmount),
          ),
          findsOneWidget,
        );
        expect(find.text(ApprovalsCopy.financeReviewTitle), findsOneWidget);
        expect(_key('finance-reason-limitOverrun'), findsOneWidget);
        // Ödeme satırı ve kullanım (eski satır bu siparişi içermeyebilir: "Kullanım").
        final meter = tester.widget<UsageBar>(_key('finance-limit-meter'));
        expect(meter.value, closeTo(0.94, 0.001));
        expect(meter.label, ApprovalsCopy.usageNow);
        final readouts = tester.widget<PlateReadouts>(
          find.byType(PlateReadouts),
        );
        expect(
          [
            for (final x in readouts.items)
              [x.label, x.value, ?x.unit].join(' '),
          ],
          ['Çek 60 gün', 'Kullanım %94', 'Gecikmiş Yok'],
        );
        // Kart satırları sunucunun biçimiyle (yapılandırılmış kart yok).
        expect(find.text('Cari finans durumu'), findsWidgets);
        expect(find.text('Son risk raporu'), findsOneWidget);
        // Sunucunun kart uyarıları bant olarak kalır (işaret bölümü yok).
        expect(
          find.text('Finans kartının gözden geçirme tarihi geçti.'),
          findsOneWidget,
        );
        // Karar rıhtımı aynı.
        expect(find.text('Koşullu onayla'), findsOneWidget);
        await finish(tester);
      },
    );

    testWidgets('eski etiket "Gecikmiş bakiye" plakaya okunur', (tester) async {
      final app = await pumpA5(
        tester,
        persona: 'finans',
        location: '/approvals/9001',
        size: _phone,
      );
      _serveLegacyDetail(app.server, oldLabels: true);
      unawaited(
        app.container.read(approvalDetailProvider(9001).notifier).refresh(),
      );
      await pumpFor(tester);
      final readouts = tester.widget<PlateReadouts>(find.byType(PlateReadouts));
      expect(
        readouts.items.map((x) => [x.label, x.value, ?x.unit].join(' ')),
        contains('Gecikmiş 120.000 ₺'),
      );
      await finish(tester);
    });

    test('canlı sunucunun eski örneği (sözleşme) yedekle okunur', () {
      final d = ApprovalDetail.fromJson(
        jsonDecode(
          File(
            'test/contract/server/approvals-id.order-finance.json',
          ).readAsStringSync(),
        ),
      );
      expect(d.summary.finance, isNull);
      final r = d.financeReview!;
      expect(r.structured, isFalse);
      // "Limit kullanımı: %92 → %131" (önce → bu siparişle).
      expect(r.limit!.hasLimit, isTrue);
      expect(r.limit!.usagePercentAfter, 131);
      expect(r.limit!.wouldExceed, isTrue);
      expect(r.limit!.ratio, closeTo(1.31, 0.0001));
      expect(r.amountIsEstimate, isTrue, reason: '"Tahmini tutar" satırı');
      expect(r.payment.methodName, 'Çek');
      expect(r.payment.termDays, 60);
      // "Tutar" biçimi de okunur (kullanım; bu sipariş hariç).
      final t = OrderFinanceLimit.fromUsageText(
        '30.000\u00A0₺ / 100.000\u00A0₺ (%30)',
      )!;
      expect(t.limitAmount, 100000);
      expect(t.usedByOthers, 30000);
      expect(t.usagePercentAfter, 30);
      expect(t.includesThisOrder, isFalse);
      expect(t.available, 70000);
      expect(OrderFinanceLimit.fromUsageText('Limit yok')!.hasLimit, isFalse);
      expect(OrderFinanceLimit.fromUsageText('ölçülemedi')!.text, 'ölçülemedi');
      expect(ApprovalsCopy.usageText('%92 → %131'), '%92, bu siparişle %131');
    });
  });

  test(
    'sunucunun yeni örneği: summary.finance ve satır anahtarları okunur',
    () {
      final d = ApprovalDetail.fromJson(
        jsonDecode(
          File(
            'test/contract/samples/approval_detail_finance_review.json',
          ).readAsStringSync(),
        ),
      );
      final r = d.summary.finance!;
      expect(d.financeReview, same(r));
      expect(r.financeStatus, OrderFinanceStatus.pending);
      expect(r.amountIsEstimate, isTrue);
      expect(r.estimatedAmount, 80000);
      expect(r.quotedAmount, isNull);
      expect(
        [for (final x in r.reasons) x.kind],
        [
          FinanceReasonKind.limitOverrun,
          FinanceReasonKind.paymentMethod,
          FinanceReasonKind.highRisk,
        ],
      );
      expect(r.payment.methodCode, 'CEK');
      expect(r.payment.termDays, 60);
      expect(r.payment.dueDate, isNotNull);
      expect(r.payment.documentKind, AttachmentKind.chequeImage);
      expect(r.payment.documentMissing, isTrue);
      expect(r.limit!.usagePercentAfter, 110);
      expect(r.limit!.ratio, closeTo(1.1, 0.0001));
      expect(r.limit!.overrunAmount, 10000);
      expect(r.limit!.availableAfter, 0);
      expect(r.limit!.unpricedOthers, 40000);
      expect(r.card!.riskClass, RiskClass.c);
      expect(r.card!.overdueAmount, 5000);
      expect(r.card!.reviewOverdue, isTrue);
      expect(r.card!.hasBouncedCheque, isTrue);
      expect(r.card!.allowedMethodCodes, ['CEK', 'HAVALE', 'NAKIT']);
      expect(r.riskReport!.score, 640);
      expect(r.history!.orderCount, 5);
      expect(r.history!.overdueAmount, 30000);
      expect(r.history!.maxOverdueDays, 5);
      expect(r.paymentGroup.single.approvalRequestId, 2);
      expect(d.summary.facts.every((f) => f.key != null), isTrue);
      expect(r.termExceedsCard, isFalse, reason: 'kart 90 gün, sipariş 60 gün');
      expect(r.exceptions.map((x) => x.text), [
        'Limit aşımı 10.000 TL',
        'Yüksek risk (C)',
      ]);
    },
  );

  group('push → ayrıntı', () {
    testWidgets(
      'approval.pending dokunuşu talebi açar, talebin bloğu parlar, finans incelemesi görünür',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = _phone;
        addTearDown(tester.view.reset);
        final h = await TestHarness.create(
          prefs: const {'akn.onboardingDone': true},
        );
        final push = _TapPush();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...h.overrides,
              pushServiceProvider.overrideWith((ref) => push),
            ],
            child: const AknApp(),
          ),
        );
        await pumpSteps(tester, const Duration(seconds: 2));
        final c = ProviderScope.containerOf(
          tester.element(find.byType(AknApp)),
        );
        await tester.runAsync(() async {
          final s = c.read(sessionControllerProvider.notifier);
          final outcome = await s.loginWithPassword('finans', 'demo');
          if (outcome is LoginNeedsCode) {
            await s.verifyCode(outcome.challenge.challengeId, '123456');
          }
        });
        await pumpSteps(tester, const Duration(seconds: 2));
        await settleIo(tester);
        expect(c.read(sessionControllerProvider), isA<SessionAuthenticated>());
        expect(
          withPushFocus('/approvals/9001', 'approval.pending'),
          '/approvals/9001?focus=request',
        );
        push.ctrl.add(
          PushEvent(
            PushPayload(
              type: 'approval.pending',
              route: '/approvals/9001',
              entityType: 'ApprovalRequest',
              entityId: 9001,
              category: 'approvals',
              title: 'Onayınız bekleniyor',
              body: 'Sipariş finans onayı · Marmara İnşaat.',
              receivedAt: DateTime.now().toUtc(),
            ),
            PushOrigin.tap,
          ),
        );
        await pumpSteps(tester, const Duration(seconds: 2));
        await settleIo(tester, rounds: 4);
        await pumpSteps(tester, const Duration(milliseconds: 800));
        final config = c
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration;
        expect(config.last.matchedLocation, '/approvals/9001');
        // `?focus=request` (push_focus): ayrıntı talebin bloğuna odaklı açılır.
        final page = tester.widget<ApprovalDetailPage>(
          find.byType(ApprovalDetailPage),
        );
        expect(page.id, 9001);
        expect(page.focusRequest, isTrue);
        final flash = tester.widget<AknFocusFlash>(find.byType(AknFocusFlash));
        expect(flash.active, isTrue);
        expect(find.text(ApprovalsCopy.financeReviewTitle), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(PlateHead),
            matching: find.text(ApprovalsCopy.estimatedAmount),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 6));
      },
    );
  });

  group('ana sayfa "Sıra sizde" ve rozet', () {
    ApprovalRow row(int id, ApprovalType type) => ApprovalRow(
      id: id,
      type: type,
      status: ApprovalStatus.pending,
      canDecide: true,
    );

    test(
      'tümü sipariş finansıysa: "Finans onayınızı bekleyen N sipariş" ve süzülü Onaylar',
      () {
        final items = buildBayiTasks(
          data: const BayiHomeData(stationId: 1, stationTitle: 'Demir Petrol'),
          approvalsBadge: 2,
          bende: [
            row(1, ApprovalType.orderFinance),
            row(2, ApprovalType.orderFinance),
          ],
        );
        final t = items.firstWhere((t) => t.kind == TaskKind.approvals);
        expect(t.count, 2, reason: 'sayı rozettir (P2)');
        expect(t.title, 'Finans onayınızı bekleyen 2 sipariş');
        expect(t.route, '/approvals?type=${ApprovalType.orderFinance.code}');
        expect(t.actionLabel, 'Siparişleri incele');
      },
    );

    test('karışıksa: başlık aynı, alt satır "1\'i sipariş finansı"', () {
      final items = buildBayiTasks(
        data: const BayiHomeData(stationId: 1, stationTitle: 'Demir Petrol'),
        approvalsBadge: 3,
        bende: [
          row(1, ApprovalType.orderFinance),
          row(2, ApprovalType.customerOnboarding),
          row(3, ApprovalType.leadFinance),
        ],
      );
      final t = items.firstWhere((t) => t.kind == TaskKind.approvals);
      expect(t.count, 3);
      expect(t.title, 'Kararınızı bekleyen 3 talep');
      expect(t.subtitle, "1'i sipariş finansı");
      expect(t.route, '/approvals');
    });

    test(
      'Finans birimine "Bugünün Tüpraş fiyatını girin" görevi verilmez (G22)',
      () {
        const home = BayiHomeData(
          stationId: 1,
          stationTitle: 'Demir Petrol',
          setup: BayiSetupSection(tuprasMissingToday: true),
        );
        expect(
          buildBayiTasks(data: home).map((t) => t.kind),
          contains(TaskKind.tuprasToday),
        );
        expect(
          buildBayiTasks(data: home, canEnterPrices: false).map((t) => t.kind),
          isNot(contains(TaskKind.tuprasToday)),
        );
      },
    );

    testWidgets(
      'finans: rozet = Bende = ana sayfanın onay satırı; satır sipariş finansını sayar; karardan sonra düşer',
      (tester) async {
        final app = await pumpA5(
          tester,
          persona: 'finans',
          location: '/approvals',
          size: _phone,
        );
        final c = app.container;
        final badge = c.read(unreadCountProvider).approvals;
        expect(badge, greaterThan(0));
        final bende = c.read(approvalsListProvider(const ApprovalsQuery()));
        expect(bende.totalCount, badge);
        final finance = bende.items
            .where((r) => r.type == ApprovalType.orderFinance)
            .length;
        expect(finance, greaterThan(0));
        final tasks = buildBayiTasks(
          data: const BayiHomeData(stationId: 1, stationTitle: 'Demir Petrol'),
          approvalsBadge: badge,
          bende: bende.items,
        );
        final t = tasks.firstWhere((t) => t.kind == TaskKind.approvals);
        expect(t.count, badge);
        expect(t.subtitle, contains('sipariş finansı'));
        // Onaylayınca rozet bir azalır.
        app.router.go('/approvals/9001');
        await pumpFor(tester);
        await tapText(tester, 'Onayla');
        await tapText(tester, 'Onayla', last: true);
        await pumpFor(tester, const Duration(milliseconds: 2400));
        unawaited(c.read(unreadCountProvider.notifier).refresh());
        await pumpFor(tester);
        expect(c.read(unreadCountProvider).approvals, badge - 1);
        await finish(tester);
      },
    );
  });

  group('boş durumlar', () {
    testWidgets('onaylayanın boş Bende\'si: "Kararlarımı göster"', (
      tester,
    ) async {
      final app = await pumpA5(
        tester,
        persona: 'finans',
        location: '/approvals/9001',
        size: _phone,
      );
      for (final a in app.server.world.approvals) {
        a['status'] = ApprovalStatus.cancelled.code;
      }
      app.container.invalidate(approvalsListProvider);
      app.container.invalidate(approvalBadgeProvider);
      app.router.go('/approvals?scope=bende');
      await pumpFor(tester);
      expect(
        find.descendant(
          of: find.byType(EmptyState),
          matching: find.text(ApprovalsCopy.emptyTitle(ApprovalScope.toMe)),
        ),
        findsOneWidget,
      );
      expect(find.text(ApprovalsCopy.approverEmptyMessage), findsOneWidget);
      expect(find.text(ApprovalsCopy.showDecided), findsOneWidget);
      expect(find.text(ApprovalsCopy.showMine), findsNothing);
      await tapText(tester, ApprovalsCopy.showDecided);
      expect(
        app.log.last('GET', '/approvals')!.queryParameters['scope'],
        ApprovalScope.decidedByMe.code,
      );
      await finish(tester);
    });

    testWidgets(
      'Sipariş finansı süzgeci boş: finans birimine göre söz, "Tüm talepleri göster"',
      (tester) async {
        final app = await pumpA5(
          tester,
          persona: 'finans',
          location: '/approvals/9001',
          size: _phone,
        );
        for (final a in app.server.world.approvals) {
          if (a['type'] == ApprovalType.orderFinance.code) {
            a['status'] = ApprovalStatus.cancelled.code;
          }
        }
        app.container.invalidate(approvalsListProvider);
        app.router.go('/approvals?type=${ApprovalType.orderFinance.code}');
        await pumpFor(tester);
        expect(find.text(ApprovalsCopy.financeEmptyTitle), findsOneWidget);
        await tapText(tester, ApprovalsCopy.showAllTypes);
        expect(
          app.log.last('GET', '/approvals')!.queryParameters['type'],
          isNull,
        );
        expect(find.byType(ApprovalRowTile), findsWidgets);
        await finish(tester);
      },
    );
  });

  // Doğrulama (2026-11-03): birimin onaycısı başkası olan bayi kullanıcısı inceler ama karar vermez;
  // cari kendi siparişinin finans onayında iç değerlendirmenin hiçbir parçasını görmez.
  group('yetki ve gizlilik', () {
    testWidgets(
      'onaycı başkası (sahip; Finans birimi onaycısı Can Öztürk): inceleme görünür, karar ve belge ekleme yok',
      (tester) async {
        await pumpA5(
          tester,
          persona: 'sahip',
          location: '/approvals/9001',
          size: _phone,
        );
        expect(_key('finance-review'), findsOneWidget);
        expect(
          find.text('Bu birimin onaycısı Can Öztürk; talebi o onaylar.'),
          findsOneWidget,
        );
        for (final l in const [
          'Onayla',
          'Koşullu onayla',
          'Ek bilgi iste',
          'Reddet',
        ]) {
          expect(
            find.descendant(of: find.byType(ActionBar), matching: find.text(l)),
            findsNothing,
            reason: l,
          );
        }
        expect(
          _key('approver-upload-${AttachmentKind.chequeImage.code}'),
          findsNothing,
        );
        expect(find.text(ApprovalsCopy.decideNext), findsNothing);
        await finish(tester);
      },
    );

    testWidgets(
      'cari (müşteri görünümü): finans incelemesi, kart, risk, limit ve gecikme yok',
      (tester) async {
        final app = await pumpA5(
          tester,
          persona: 'musteri',
          location: '/approvals/9005',
          size: _phone,
        );
        final world = app.server.world;
        final json = A5FakeStore.of(
          world,
        ).detail(world.personaByUserId('u-musteri')!, world.approval(9005)!);
        expect((json['summary'] as Map)['finance'], isNull);
        for (final k in const [
          'finance-review',
          'finance-card',
          'finance-history',
          'finance-limit-meter',
          'approval-open-order',
        ]) {
          expect(_key(k), findsNothing, reason: k);
        }
        for (final t in const [
          ApprovalsCopy.financeReviewTitle,
          ApprovalsCopy.financeCardTitle,
          'Risk sınıfı',
          'Son risk raporu',
          'Gecikmiş',
          'Limit kullanımı',
          'Açık bakiye',
        ]) {
          expect(find.text(t), findsNothing, reason: t);
        }
        await finish(tester);
      },
    );
  });
}
