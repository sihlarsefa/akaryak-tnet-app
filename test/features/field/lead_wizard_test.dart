// Ön kayıt sihirbazı denetleyicisi (spec A.3 L1–L2): KVKK açık rızası ve vergi levhası olmadan
// finansa gönderim isteği atılmaz; canlı VKN kontrolü; çevrimdışı kayıt ve kayda bağlı belge.
import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/offline/outbox_op.dart';
import 'package:akaryakitnet/core/offline/outbox_providers.dart';
import 'package:akaryakitnet/core/offline/outbox_store.dart';
import 'package:akaryakitnet/features/field/application/lead_wizard_controller.dart';
import 'package:akaryakitnet/features/field/data/field_location.dart';
import 'package:akaryakitnet/features/field/data/field_outbox.dart';
import 'package:akaryakitnet/features/field/fake/field_fake_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'field_test_kit.dart';

const _args = LeadWizardArgs();

void main() {
  late FieldHarness h;
  late ProviderContainer c;
  late RequestLog log;

  LeadWizardState s() => c.read(leadWizardProvider(_args));
  LeadWizardController ctrl() => c.read(leadWizardProvider(_args).notifier);

  Future<void> open([String persona = 'saha']) async {
    h = await FieldHarness.create();
    c = h.container();
    log = RequestLog()..attach(c);
    await loginAs(c, persona);
    c.listen(leadWizardProvider(_args), (_, _) {});
    await waitUntil(() => s().options != null, reason: 'seçenekler');
  }

  /// Gönderim için gereken her şey (KVKK isteğe bağlı; vergi levhası hariç).
  void fillComplete({bool kvkk = true}) {
    ctrl().update(
      (d) => d.copyWith(
        companyTitle: 'Doğu Lojistik A.Ş.',
        taxNumber: FieldFakeState.vkn('314159265'),
        taxOffice: 'Gebze',
        city: 'Kocaeli',
        district: 'Gebze',
        kvkkConsent: kvkk,
        kvkkConsentMethod: kvkk ? 'Islak imzalı form' : null,
      ),
    );
    ctrl().setProductLiters(1, monthly: 20000, setMonthly: true);
    ctrl().updateContact(
      0,
      (x) => x.copyWith(
        name: 'Selim Doğan',
        phone: '05321112233',
        email: 'selim@dogulojistik.example',
      ),
    );
  }

  LeadDocInput taxPlate() => LeadDocInput(
    kind: AttachmentKind.taxPlate,
    path: h.writePng(),
    fileName: 'levha.png',
    contentType: 'image/png',
    sizeBytes: samplePng.length,
  );

  List<String> posts() => [
    for (final e in log.entries)
      if (e.method == 'POST') e.uri.path,
  ];

  tearDown(() {
    c.dispose();
    h.dispose();
  });

  test(
    'ürün ihtiyaç satırları seçeneklerden gelir; KVKK metni webdeki cümle',
    () async {
      await open();
      expect(s().draft.products.map((p) => p.productId), [1, 2, 3]);
      expect(s().effectiveOptions.kvkkText, contains('açık rıza verdi.'));
      expect(s().draft.contacts.single.isInviteRecipient, isTrue);
    },
  );

  test('KVKK açık rızası yoksa finansa gönderim isteği atılmaz', () async {
    await open();
    fillComplete(kvkk: false);
    await ctrl().addDocument(taxPlate());
    expect(s().taxPlateReady, isTrue);
    log.clear();
    await ctrl().submit();
    expect(s().missing, ['KVKK açık rızası']);
    expect(s().banner, 'Finansa göndermek için eksik: KVKK açık rızası.');
    expect(posts(), isEmpty);
    expect(
      LeadWizardController.stepOfMissing(s().missing.single),
      LeadWizardStep.kvkk,
    );
    // Rıza verilip yöntem seçilmezse yöntem eksik sayılır.
    ctrl().update((d) => d.copyWith(kvkkConsent: true));
    await ctrl().submit();
    expect(s().missing, ['KVKK rızasının alınma yöntemi']);
    expect(posts(), isEmpty);
  });

  test(
    'vergi levhası olmadan gönderilmez; yüklenince kayıt → belge → gönderim',
    () async {
      await open();
      fillComplete();
      log.clear();
      await ctrl().submit();
      expect(s().missing, ['Vergi levhası (Evrak)']);
      expect(posts(), isEmpty);
      expect(
        LeadWizardController.stepOfMissing('Vergi levhası (Evrak)'),
        LeadWizardStep.documents,
      );

      await ctrl().addDocument(taxPlate());
      expect(s().taxPlateReady, isTrue);
      expect(s().taxPlateUploaded, isFalse);
      await ctrl().submit();
      expect(s().outcome, isA<LeadSubmitted>());
      final submitted = s().outcome! as LeadSubmitted;
      final id = submitted.leadId;
      expect(submitted.message, 'Ön kayıt finans onayına gönderildi.');
      expect(submitted.leadNumber, startsWith('ONK-'));
      final create = log.exact('POST', 'leads').single;
      expect(idempotencyKeyOf(create), isNotEmpty);
      expect(log.exact('POST', 'attachments'), hasLength(1));
      expect(log.exact('POST', 'leads/$id/submit'), hasLength(1));
      final lead = h.state.leads.firstWhere((l) => l['id'] == id);
      expect(lead['status'], 1);
      expect(lead['kvkkConsent'], isTrue);
      expect(lead['kvkkConsentMethod'], 'Islak imzalı form');
      expect(lead['kvkkDocumentVersion'], '1.0');
      final approval = h.server.world.approvals.last;
      expect(approval['subjectType'], 'CustomerLead');
      expect(approval['subjectId'], id);
    },
  );

  test('canlı VKN kontrolü: bayide kayıtlı VKN gönderimi engeller', () async {
    await open();
    fillComplete();
    ctrl().update((d) => d.copyWith(taxNumber: '1234567808'));
    ctrl().checkTaxNumber('1234567808');
    expect(s().dupChecking, isTrue);
    await waitUntil(() => !s().dupChecking, reason: 'VKN kontrolü');
    expect(s().dup!.linkedInThisStation, isTrue);
    expect(
      s().dup!.messages.single,
      'Bu VKN ile cari bayinizde kayıtlı (C-0101).',
    );
    await ctrl().addDocument(taxPlate());
    log.clear();
    await ctrl().submit();
    expect(s().missing.first, 'Bu VKN ile cari bayinizde kayıtlı (C-0101)');
    expect(posts(), isEmpty);

    ctrl().checkTaxNumber('12345');
    expect(
      s().dup?.formatError,
      isNull,
      reason: 'yazarken kısa numara hata değil',
    );
    ctrl().checkTaxNumber('1234567809');
    expect(s().dup!.formatError, 'VKN doğrulanamadı; numarayı kontrol edin.');
  });

  test('ziyaret konumu doğrulukla kaydedilir', () async {
    await open();
    ctrl().setVisitLocation(
      FieldLocationFix(
        latitude: 40.8021345678,
        longitude: 29.4304712345,
        accuracyMeters: 12.3456,
        at: DateTime.utc(2026, 10, 21),
      ),
    );
    final d = s().draft;
    expect(d.visitLatitude, 40.802135);
    expect(d.visitLongitude, 29.430471);
    expect(d.visitAccuracyMeters, 12.35);
    expect(d.hasVisitLocation, isTrue);
    ctrl().clearVisitLocation();
    expect(s().draft.hasVisitLocation, isFalse);
  });

  test(
    'çevrimdışı kayıt: ön kayıt ve belgesi sıraya girer, bağlantı gelince gider',
    () async {
      await open();
      fillComplete();
      c.read(onlineProvider.notifier).state = false;
      await ctrl().addDocument(taxPlate());
      await ctrl().saveDraft();
      final outcome = s().outcome;
      expect(outcome, isA<LeadQueued>());
      final opId = (outcome! as LeadQueued).opId;
      final ops = await c.read(outboxStoreProvider).list('u-saha');
      expect(ops.map((o) => o.type).toSet(), {
        FieldOps.leadSaveDraft,
        FieldOps.leadUpload,
      });
      final upload = ops.firstWhere((o) => o.type == FieldOps.leadUpload);
      expect(upload.dependsOn, opId);
      expect(log.exact('POST', 'leads'), isEmpty);
      // Çevrimdışıyken "Finansa gönder" bağlantı ister.
      await ctrl().submit();
      expect(s().banner, startsWith('Finansa göndermek için bağlantı gerekir'));

      c.read(onlineProvider.notifier).state = true;
      await c.read(outboxRunnerProvider).runOnce();
      final saved = await waitOp(c, opId);
      final uploaded = await waitOp(c, upload.id);
      expect(saved.status, OutboxStatus.done);
      expect(uploaded.status, OutboxStatus.done);
      final leadId = saved.result!['leadId'] as int;
      expect(
        h.server.world.attachments.where(
          (a) => a['ownerId'] == leadId && a['kind'] == 10,
        ),
        hasLength(1),
      );
    },
  );

  test('taslak için en az ünvan ya da VKN gerekir', () async {
    await open();
    log.clear();
    await ctrl().saveDraft();
    expect(
      s().errors['companyTitle'],
      'Taslağı kaydetmek için en az firma ünvanı ya da VKN / TCKN girin.',
    );
    expect(posts(), isEmpty);
  });
}
