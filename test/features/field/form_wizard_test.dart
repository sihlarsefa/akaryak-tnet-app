// Saha formu sihirbazı denetleyicisi (spec A.3 F, C.5): 600 ms önizleme gecikmesi, temsilciye
// maliyetsiz bant, maliyet görene kâr, çevrimdışı kayıt → bekleyen işlem, gönderimde Idempotency-Key.
import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/offline/outbox_op.dart';
import 'package:akaryakitnet/core/offline/outbox_providers.dart';
import 'package:akaryakitnet/core/offline/outbox_store.dart';
import 'package:akaryakitnet/features/field/application/form_wizard_controller.dart';
import 'package:akaryakitnet/features/field/data/field_outbox.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'field_test_kit.dart';

const _args = FormWizardArgs(
  customerId: 103,
  customerTitle: 'Ege Tarım Kooperatifi',
);

void main() {
  late FieldHarness h;
  late ProviderContainer c;
  late RequestLog log;

  FormWizardState s() => c.read(formWizardProvider(_args));
  FormWizardController ctrl() => c.read(formWizardProvider(_args).notifier);

  Future<void> open(String persona) async {
    h = await FieldHarness.create();
    c = h.container();
    log = RequestLog()..attach(c);
    await loginAs(c, persona);
    c.listen(formWizardProvider(_args), (_, _) {});
    await waitUntil(() => s().options != null, reason: 'seçenekler');
  }

  /// İlk satırı Motorin, 8.000 L ile doldurur (fiyat cari fiyatından gelir).
  void fillLine() {
    final key = s().draft.lines.single.key;
    ctrl().setLineProduct(key, 1);
    ctrl().updateLine(key, (l) => l.copyWith(liters: 8000));
  }

  tearDown(() {
    c.dispose();
    h.dispose();
  });

  test(
    'seçenekler varsayılanları doldurur (tek nokta, cari fiyatı, Tüpraş)',
    () async {
      await open('saha');
      final d = s().draft;
      expect(d.customerTitle, 'Ege Tarım Kooperatifi');
      expect(d.paymentMethodCode, 'HAVALE');
      expect(d.refineryLocation, 'İZMİT');
      expect(d.shipDate, isNotNull);
      final line = d.lines.single;
      expect(line.deliveryPointId, 1004);
      expect(line.productId, isNull);
      fillLine();
      final filled = s().draft.lines.single;
      expect(filled.unitPrice, 41.9); // cari fiyatı (liste − 0,20)
      expect(filled.tuprasM3, 38400);
      expect(filled.pumpPrice, 43.9);
      expect(filled.bindirimM3, isNull, reason: 'temsilci maliyet girmez');
    },
  );

  test(
    'önizleme 600 ms sessizlikten sonra tek istek atar; temsilciye bant maliyetsiz gelir',
    () async {
      await open('saha');
      expect(
        FormWizardController.previewDelay,
        const Duration(milliseconds: 600),
      );
      final key = s().draft.lines.single.key;
      ctrl().setLineProduct(key, 1);
      for (final liters in [1000.0, 4000.0, 6000.0, 8000.0]) {
        ctrl().updateLine(key, (l) => l.copyWith(liters: liters));
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        log.all('POST', 'preview-v2'),
        isEmpty,
        reason: 'henüz 600 ms dolmadı',
      );
      await waitUntil(() => s().preview != null, reason: 'önizleme');
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final calls = log.all('POST', 'preview-v2');
      expect(calls, hasLength(1));
      final body = calls.single.data as Map;
      final line = (body['lines'] as List).single as Map;
      expect(line['quantityLiters'], 8000);
      expect(body['includesCostInputs'], isFalse);
      expect(line.containsKey('bindirimM3'), isFalse);
      expect(body.containsKey('otherPercent'), isFalse);

      final p = s().preview!;
      expect(s().showCosts, isFalse);
      expect(p.showCosts, isFalse);
      // 41,90 ₺/L: (41.900 − 39.600) / 39.600 = %5,81 → satış müdürü onayı (Roller v5 1. bant).
      expect(p.band.key, 'mid');
      expect(p.band.label, 'Satış müdürü onayı');
      expect(p.lines.single.profitPercent, isNull);
      expect(p.chip, isNull);
      expect(s().previewKeys, [key]);

      // Aynı içerik yeniden istek atmaz; değişiklik yeni istek atar.
      ctrl().updateLine(key, (l) => l.copyWith(liters: 8000));
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(log.all('POST', 'preview-v2'), hasLength(1));
      ctrl().updateLine(
        key,
        (l) => l.copyWith(unitPrice: 42.5, priceEdited: true),
      );
      await waitUntil(() => log.all('POST', 'preview-v2').length == 2);
      await waitUntil(() => s().preview!.band.key == 'ok');
    },
  );

  test('maliyet gören satış müdürü bindirim gönderir ve kâr görür', () async {
    await open('satis');
    fillLine();
    expect(s().showCosts, isTrue);
    expect(s().draft.lines.single.bindirimM3, 1000);
    await waitUntil(() => s().preview != null, reason: 'önizleme');
    final body = log.last('POST', 'preview-v2')!.data as Map;
    expect(body['includesCostInputs'], isTrue);
    expect(((body['lines'] as List).single as Map)['bindirimM3'], 1000);
    final p = s().preview!;
    expect(p.showCosts, isTrue);
    expect(p.lines.single.profitPercent, closeTo(5.81, 0.01));
    expect(p.chip, isNotNull);
  });

  test(
    'çevrimdışı "Taslak kaydet" bekleyen işleme alınır; bağlantı gelince gider',
    () async {
      await open('saha');
      fillLine();
      c.read(onlineProvider.notifier).state = false;
      await ctrl().saveDraft();
      final outcome = s().outcome;
      expect(outcome, isA<FieldDraftQueued>());
      final opId = (outcome! as FieldDraftQueued).opId;
      final op = (await c.read(outboxStoreProvider).get(opId))!;
      expect(op.type, FieldOps.saveDraft);
      expect(op.status, OutboxStatus.pending);
      expect(op.idempotencyKey, isNotEmpty);
      expect(log.exact('POST', 'field-orders'), isEmpty);

      c.read(onlineProvider.notifier).state = true;
      await c.read(outboxRunnerProvider).runOnce();
      final done = await waitOp(c, opId);
      expect(done.status, OutboxStatus.done);
      expect(
        idempotencyKeyOf(log.exact('POST', 'field-orders').single),
        op.idempotencyKey,
      );
      final id = done.result!['formId'] as int;
      final saved = h.state.forms.firstWhere((f) => f['id'] == id);
      expect(saved['totalLiters'], 8000);
      expect(saved['customerId'], 103);
    },
  );

  test(
    'çevrimiçi kayıt → gönder: Idempotency-Key ile POST ve submit',
    () async {
      await open('saha');
      fillLine();
      final key = s().draft.lines.single.key;
      ctrl().updateLine(
        key,
        (l) => l.copyWith(unitPrice: 42.5, priceEdited: true),
      );
      await ctrl().submit();
      final outcome = s().outcome;
      expect(outcome, isA<FieldFormSubmitted>());
      final result = (outcome! as FieldFormSubmitted).result;
      expect(result.status, FieldOrderFormStatus.converted);
      final post = log.exact('POST', 'field-orders').single;
      expect(idempotencyKeyOf(post), isNotEmpty);
      final submit = log.last('POST', '/submit')!;
      expect(idempotencyKeyOf(submit), isNotEmpty);
      expect(idempotencyKeyOf(submit), isNot(idempotencyKeyOf(post)));
    },
  );

  test('gönderim bağlantı ister; eksik satır gönderilmez', () async {
    await open('saha');
    await ctrl().submit();
    expect(s().step, FieldWizardStep.lines);
    expect(s().errors.values.single, '1. satır: ürün seçin.');
    fillLine();
    c.read(onlineProvider.notifier).state = false;
    await ctrl().submit();
    expect(s().banner, startsWith('Göndermek için bağlantı gerekir'));
    expect(log.exact('POST', 'field-orders'), isEmpty);
  });

  test(
    'kayıtlı taslak düzenlenir; başka biri değiştirdiyse çakışma bildirilir',
    () async {
      await open('saha');
      final editArgs = const FormWizardArgs(formId: 7009);
      c.listen(formWizardProvider(editArgs), (_, _) {});
      FormWizardState es() => c.read(formWizardProvider(editArgs));
      await waitUntil(() => es().options != null && !es().loading);
      expect(es().draft.formNumber, startsWith('SSF-'));
      expect(es().step, FieldWizardStep.lines);
      expect(es().dirty, isFalse);
      // Sunucuda başka biri değiştirdi.
      h.state.forms.firstWhere((f) => f['id'] == 7009)['concurrencyToken'] =
          'baska-belirtec';
      final key = es().draft.lines.single.key;
      final e = c.read(formWizardProvider(editArgs).notifier)
        ..updateLine(key, (l) => l.copyWith(liters: 13000));
      await e.saveDraft();
      expect(es().conflict, isTrue);
      expect(es().banner, contains('başka biri tarafından değiştirildi'));
      await e.reloadAfterConflict();
      expect(es().conflict, isFalse);
      await e.saveDraft();
      expect(es().outcome, isA<FieldDraftSaved>());
      expect(
        h.state.forms.firstWhere((f) => f['id'] == 7009)['totalLiters'],
        13000,
      );
    },
  );
}
