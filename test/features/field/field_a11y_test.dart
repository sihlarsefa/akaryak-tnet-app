// C.7 erişilebilirlik: saha ekranları 360×640'ta, yazı ölçeği 1.0 / 2.0, açık / koyu tema; taşma yok,
// dokunma hedefleri (Android 48 dp, iOS 44 pt), etiketli hedefler ve metin kontrastı yönergelere uygun.
import 'package:akaryakitnet/features/field/application/form_wizard_controller.dart';
import 'package:akaryakitnet/features/field/application/lead_wizard_controller.dart';
import 'package:akaryakitnet/features/field/data/field_location.dart';
import 'package:flutter_test/flutter_test.dart';

import 'field_test_kit.dart';

const _newFormArgs = FormWizardArgs(
  customerId: 103,
  customerTitle: 'Ege Tarım Kooperatifi',
);
const _newFormPath =
    '/field/forms/new?customerId=103&customerTitle=Ege%20Tar%C4%B1m%20Kooperatifi';

void main() {
  group('C.7 Saha', () {
    a11yMatrix(
      'saha ana sayfası (temsilci)',
      persona: 'saha',
      location: '/home',
    );
    a11yMatrix(
      'saha ana sayfası · hava ve asistan kartı',
      persona: 'saha',
      location: '/home',
      prepare: (tester, app) async {
        app.location.access = FieldLocationAccess.granted;
        await loadAppConfig(tester, app);
        await pumpFor(tester, const Duration(milliseconds: 1500));
      },
    );
    a11yMatrix('Formlarım (temsilci)', persona: 'saha', location: '/field');
    a11yMatrix(
      'Portföy (temsilci)',
      persona: 'saha',
      location: '/field?tab=portfolio',
    );
    a11yMatrix(
      'Saha ekibi (satış müdürü)',
      persona: 'satis',
      location: '/field',
    );
    a11yMatrix(
      'Onayda (satış müdürü)',
      persona: 'satis',
      location: '/field?tab=pending',
    );
    a11yMatrix('ön kayıtlar (finans)', persona: 'finans', location: '/field');
    a11yMatrix(
      'form ayrıntısı · finans ek bilgi (temsilci)',
      persona: 'saha',
      location: '/field/forms/7005',
    );
    a11yMatrix(
      'form ayrıntısı · maliyetli (satış müdürü)',
      persona: 'satis',
      location: '/field/forms/7001',
    );
    a11yMatrix(
      'saha formu sihirbazı · satırlar ve önizleme',
      persona: 'saha',
      location: _newFormPath,
      prepare: (tester, app) async {
        final c = app.container;
        final ctrl = c.read(formWizardProvider(_newFormArgs).notifier);
        final key = c
            .read(formWizardProvider(_newFormArgs))
            .draft
            .lines
            .single
            .key;
        ctrl
          ..setLineProduct(key, 1)
          ..updateLine(key, (l) => l.copyWith(liters: 8000))
          ..goTo(FieldWizardStep.lines);
        await pumpFor(tester, const Duration(milliseconds: 1500));
      },
    );
    a11yMatrix(
      'saha formu sihirbazı · özet',
      persona: 'saha',
      location: _newFormPath,
      prepare: (tester, app) async {
        final c = app.container;
        final ctrl = c.read(formWizardProvider(_newFormArgs).notifier);
        final key = c
            .read(formWizardProvider(_newFormArgs))
            .draft
            .lines
            .single
            .key;
        ctrl
          ..setLineProduct(key, 1)
          ..updateLine(key, (l) => l.copyWith(liters: 8000))
          ..goTo(FieldWizardStep.summary);
        await pumpFor(tester, const Duration(milliseconds: 1500));
      },
    );
    for (final step in const [
      FieldWizardStep.supply,
      FieldWizardStep.payment,
    ]) {
      a11yMatrix(
        'saha formu sihirbazı · ${step.title} (maliyetli)',
        persona: 'satis',
        location: _newFormPath,
        prepare: (tester, app) async {
          final c = app.container;
          final ctrl = c.read(formWizardProvider(_newFormArgs).notifier);
          final key = c
              .read(formWizardProvider(_newFormArgs))
              .draft
              .lines
              .single
              .key;
          ctrl
            ..setLineProduct(key, 1)
            ..updateLine(key, (l) => l.copyWith(liters: 8000))
            ..setPaymentMethod('CEK')
            ..goTo(step);
          await pumpFor(tester, const Duration(milliseconds: 1500));
        },
      );
    }
    a11yMatrix(
      'saha formu sihirbazı · satırlar (maliyetli, kâr %)',
      persona: 'satis',
      location: _newFormPath,
      prepare: (tester, app) async {
        final c = app.container;
        final ctrl = c.read(formWizardProvider(_newFormArgs).notifier);
        final key = c
            .read(formWizardProvider(_newFormArgs))
            .draft
            .lines
            .single
            .key;
        ctrl
          ..setLineProduct(key, 1)
          ..updateLine(
            key,
            (l) =>
                l.copyWith(liters: 8000, priceEntryMode: 1, profitPercent: 6),
          )
          ..goTo(FieldWizardStep.lines);
        await pumpFor(tester, const Duration(milliseconds: 1500));
      },
    );
    a11yMatrix(
      'Portföy · cari kartı',
      persona: 'saha',
      location: '/field?tab=portfolio',
      prepare: (tester, app) async {
        await tapText(tester, 'Ege Tarım Kooperatifi');
        await pumpFor(tester, const Duration(milliseconds: 800));
      },
    );
    a11yMatrix(
      'form ayrıntısı · dönüşüm hatası (satış müdürü)',
      persona: 'satis',
      location: '/field/forms/7008',
    );
    a11yMatrix(
      'ön kayıt ayrıntısı · dönüştü',
      persona: 'saha',
      location: '/field/leads/8006',
    );
    for (final step in const [
      LeadWizardStep.needs,
      LeadWizardStep.payment,
      LeadWizardStep.visit,
      LeadWizardStep.contacts,
      LeadWizardStep.documents,
    ]) {
      a11yMatrix(
        'ön kayıt sihirbazı · ${step.title}',
        persona: 'saha',
        location: '/field/leads/new',
        prepare: (tester, app) async {
          app.container
              .read(leadWizardProvider(const LeadWizardArgs()).notifier)
              .goTo(step);
          await pumpFor(tester);
        },
      );
    }
    a11yMatrix(
      'ön kayıt sihirbazı · firma',
      persona: 'saha',
      location: '/field/leads/new',
    );
    a11yMatrix(
      'ön kayıt sihirbazı · KVKK',
      persona: 'saha',
      location: '/field/leads/new',
      prepare: (tester, app) async {
        app.container
            .read(leadWizardProvider(const LeadWizardArgs()).notifier)
            .goTo(LeadWizardStep.kvkk);
        await pumpFor(tester);
      },
    );
    a11yMatrix(
      'ön kayıt ayrıntısı · ek bilgi istendi',
      persona: 'saha',
      location: '/field/leads/8001',
    );
  });
}
