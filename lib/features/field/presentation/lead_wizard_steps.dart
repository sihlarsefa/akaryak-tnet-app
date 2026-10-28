import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/media/image_capture.dart';
import '../../../core/models/enums.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/external_activity.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../../../core/utils/validators.dart';
import '../application/lead_wizard_controller.dart';
import '../copy.dart';
import '../data/lead_models.dart';
import 'location_capture.dart';
import 'widgets/field_inputs.dart';
import 'widgets/field_widgets.dart';

/// Belge seçici (kamera / galeri → sıkıştırılmış JPEG). Testler sahte verir.
typedef LeadDocPicker =
    Future<LeadDocInput?> Function(
      BuildContext context,
      AttachmentKind kind,
      CaptureSource source,
    );

final leadDocPickerProvider = Provider<LeadDocPicker>(
  (ref) => (context, kind, source) async {
    final img = await ImageCapture.pick(
      source: source,
      kind: kind,
      context: context,
    );
    if (img == null) return null;
    return LeadDocInput(
      kind: kind,
      path: img.path,
      fileName: img.fileName,
      contentType: img.contentType,
      sizeBytes: img.sizeBytes,
    );
  },
);

class LeadWizardStepBody extends StatelessWidget {
  const LeadWizardStepBody({super.key, required this.args, required this.step});

  final LeadWizardArgs args;
  final LeadWizardStep step;

  @override
  Widget build(BuildContext context) => switch (step) {
    LeadWizardStep.company => _CompanyStep(args: args),
    LeadWizardStep.fleet => _FleetStep(args: args),
    LeadWizardStep.needs => _NeedsStep(args: args),
    LeadWizardStep.payment => _PaymentStep(args: args),
    LeadWizardStep.visit => _VisitStep(args: args),
    LeadWizardStep.contacts => _ContactsStep(args: args),
    LeadWizardStep.delivery => _DeliveryStep(args: args),
    LeadWizardStep.kvkk => _KvkkStep(args: args),
    LeadWizardStep.documents => _DocumentsStep(args: args),
  };
}

const _pad = EdgeInsets.fromLTRB(16, 8, 16, 24);
const _gap = SizedBox(height: 14);

Widget _heading(BuildContext context, String title, [String? subtitle]) {
  final t = context.aknText;
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title, style: t.headline)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle, style: t.bodySmall),
        ],
      ],
    ),
  );
}

/// İl önerileri (81 il; Türkçe duyarsız arama).
class _CityField extends StatelessWidget {
  const _CityField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.requiredMark = false,
  });

  final String label;
  final String? value;
  final ValueChanged<String> onChanged;
  final bool requiredMark;

  @override
  Widget build(BuildContext context) {
    final v = value ?? '';
    final matches = v.trim().isEmpty || turkeyCities.contains(v)
        ? const <String>[]
        : turkeyCities.where((c) => TurkishText.matches(c, v)).take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldTextInput(
          label: label,
          value: value,
          requiredMark: requiredMark,
          maxLength: 50,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.addressCity],
          onChanged: onChanged,
        ),
        if (matches.isNotEmpty)
          FilterChips<String>(
            padding: EdgeInsets.zero,
            options: [
              for (final m in matches) FilterOption(value: m, label: m),
            ],
            selected: const {},
            onChanged: (s) {
              if (s.isNotEmpty) onChanged(s.first);
            },
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════ 1. Firma

class _CompanyStep extends ConsumerWidget {
  const _CompanyStep({required this.args});

  final LeadWizardArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(leadWizardProvider(args));
    final ctrl = ref.read(leadWizardProvider(args).notifier);
    final d = s.draft;
    final e = s.errors;
    return FieldStaggeredList(
      padding: _pad,
      children: [
        if (s.resumeCandidate != null) ...[
          AknCard(
            accent: AknTone.info,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Yarım kalan ön kaydınıza devam edin',
                  style: context.aknText.bodyStrong,
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (s.resumeCandidate!.companyTitle.isNotEmpty)
                      s.resumeCandidate!.companyTitle,
                    if (s.resumeSavedAt != null) Fmt.relative(s.resumeSavedAt),
                  ].join(', '),
                  style: context.aknText.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    AknButton(
                      label: 'Devam et',
                      size: AknButtonSize.small,
                      onPressed: ctrl.resume,
                    ),
                    AknButton.ghost(
                      label: 'Yeni başla',
                      size: AknButtonSize.small,
                      onPressed: ctrl.discardResume,
                    ),
                  ],
                ),
              ],
            ),
          ),
          _gap,
        ],
        if (s.decisionNote != null) ...[
          AknBanner(
            tone: AknTone.warn,
            title: 'Finans ek bilgi istedi',
            message: s.decisionNote!,
          ),
          _gap,
        ],
        _heading(
          context,
          'Firma',
          'Ünvan ya da VKN girildiğinde taslak kaydedilebilir.',
        ),
        FieldTextInput(
          label: 'Ünvan',
          hint: 'Örn. ABC Lojistik A.Ş.',
          value: d.companyTitle,
          requiredMark: true,
          maxLength: 200,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.organizationName],
          error: e['companyTitle'],
          onChanged: (v) => ctrl.update(
            (x) => x.copyWith(companyTitle: v),
            clears: {'companyTitle'},
          ),
        ),
        _gap,
        FieldTextInput(
          label: 'VKN / TCKN',
          hint: '10 ya da 11 hane',
          value: d.taxNumber,
          requiredMark: true,
          maxLength: 11,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          error: e['taxNumber'],
          onChanged: (v) {
            ctrl.update((x) => x.copyWith(taxNumber: v), clears: {'taxNumber'});
            ctrl.checkTaxNumber(v);
          },
        ),
        _TaxCheck(state: s),
        _gap,
        FieldTextInput(
          label: 'Vergi dairesi',
          value: d.taxOffice,
          requiredMark: true,
          maxLength: 100,
          textCapitalization: TextCapitalization.words,
          onChanged: (v) => ctrl.update((x) => x.copyWith(taxOffice: v)),
        ),
        _gap,
        _CityField(
          label: 'İl',
          value: d.city,
          requiredMark: true,
          onChanged: (v) => ctrl.update((x) => x.copyWith(city: v)),
        ),
        _gap,
        FieldTextInput(
          label: 'İlçe',
          value: d.district,
          requiredMark: true,
          maxLength: 50,
          textCapitalization: TextCapitalization.words,
          onChanged: (v) => ctrl.update((x) => x.copyWith(district: v)),
        ),
        _gap,
        FieldTextInput(
          label: 'Adres',
          value: d.address,
          maxLength: 500,
          maxLines: 3,
          minLines: 2,
          autofillHints: const [AutofillHints.fullStreetAddress],
          onChanged: (v) => ctrl.update((x) => x.copyWith(address: v)),
        ),
        _gap,
        FieldTextInput(
          label: 'Sektör',
          hint: 'Örn. nakliye, inşaat, tarım',
          value: d.sector,
          maxLength: 80,
          onChanged: (v) => ctrl.update((x) => x.copyWith(sector: v)),
        ),
        _gap,
        FieldNumberInput(
          label: 'Faaliyet yılı',
          integer: true,
          value: d.foundedYear,
          error: e['foundedYear'],
          onChanged: (v) => ctrl.update(
            (x) => x.copyWith(foundedYear: v?.round()),
            clears: {'foundedYear'},
          ),
        ),
        _gap,
        FieldTextInput(
          label: 'Telefon',
          value: d.phone,
          maxLength: 30,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          onChanged: (v) => ctrl.update((x) => x.copyWith(phone: v)),
        ),
        _gap,
        FieldTextInput(
          label: 'E-posta',
          value: d.email,
          maxLength: 256,
          keyboardType: TextInputType.emailAddress,
          textCapitalization: TextCapitalization.none,
          autofillHints: const [AutofillHints.email],
          error: e['email'],
          onChanged: (v) =>
              ctrl.update((x) => x.copyWith(email: v), clears: {'email'}),
        ),
        _gap,
        FieldTextInput(
          label: 'Web',
          hint: 'www.firma.com.tr',
          value: d.website,
          maxLength: 200,
          keyboardType: TextInputType.url,
          textCapitalization: TextCapitalization.none,
          onChanged: (v) => ctrl.update((x) => x.copyWith(website: v)),
        ),
      ],
    );
  }
}

/// Canlı VKN kontrolü sonucu: kontrol sürerken küçük döner simge, sonra sonuç (biçim hatası, engel,
/// bilgi ya da "VKN uygun" çipi) solarak ve yüksekliği kayarak yerine gelir.
class _TaxCheck extends StatelessWidget {
  const _TaxCheck({required this.state});

  final LeadWizardState state;

  @override
  Widget build(BuildContext context) {
    final (key, child) = _content(context);
    return AknAnimatedSize(
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: AknMotion.of(context, AknMotion.base),
        switchInCurve: AknMotion.emphasizedCurve,
        switchOutCurve: AknMotion.exit,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topLeft,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
            alignment: Alignment.centerLeft,
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(key), child: child),
      ),
    );
  }

  (String, Widget) _content(BuildContext context) {
    final t = context.aknText;
    final dup = state.dup;
    final digits = Validators.digitsOnly(state.draft.taxNumber);
    if (state.dupChecking) {
      return (
        'checking',
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              const ChevronSpinner(size: 16, semanticLabel: null),
              const SizedBox(width: 8),
              Text('VKN kontrol ediliyor…', style: t.caption),
            ],
          ),
        ),
      );
    }
    if (dup == null) return ('none', const SizedBox(width: double.infinity));
    if (dup.formatError != null) {
      return ('format', FieldErrorText(dup.formatError));
    }
    if (dup.blocksSubmit) {
      return (
        'blocked',
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: AknBanner(
            tone: AknTone.danger,
            message: dup.messages.isNotEmpty
                ? dup.messages.join(' ')
                : dup.openLeadNumber != null
                ? 'Bu VKN ile açık ön kayıt var: ${dup.openLeadNumber}.'
                : 'Bu VKN ile cari bayinizde kayıtlı (${dup.existingCustomerCode ?? '—'}).',
          ),
        ),
      );
    }
    if (dup.existsElsewhere) {
      return (
        'elsewhere',
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: AknBanner(
            tone: AknTone.info,
            title: 'Bu VKN sistemde kayıtlı',
            message:
                'Ön kayıt finansa gönderilebilir; cari açılışı merkez onayıyla yapılır.',
          ),
        ),
      );
    }
    if (digits.length >= 10) {
      return (
        'ok',
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(
              label: 'VKN uygun',
              tone: AknTone.ok,
              icon: PhosphorIconsFill.checkCircle,
              size: StatusChipSize.small,
            ),
          ),
        ),
      );
    }
    return ('none', const SizedBox(width: double.infinity));
  }
}

// ═══════════════════════════════════════════════════════════════════ 2. Filo / depo

class _FleetStep extends ConsumerWidget {
  const _FleetStep({required this.args});

  final LeadWizardArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(leadWizardProvider(args));
    final ctrl = ref.read(leadWizardProvider(args).notifier);
    final d = s.draft;
    return FieldStaggeredList(
      padding: _pad,
      children: [
        _heading(context, 'Filo ve depo'),
        FieldNumberInput(
          label: 'Araç sayısı',
          integer: true,
          value: d.vehicleCount,
          error: s.errors['vehicleCount'],
          onChanged: (v) => ctrl.update(
            (x) => x.copyWith(vehicleCount: v?.round()),
            clears: {'vehicleCount'},
          ),
        ),
        _gap,
        FieldTextInput(
          label: 'Araç tipleri',
          hint: 'Örn. çekici, kamyon, iş makinesi',
          value: d.vehicleTypes,
          maxLength: 200,
          onChanged: (v) => ctrl.update((x) => x.copyWith(vehicleTypes: v)),
        ),
        _gap,
        FieldSwitchTile(
          title: 'Firmanın kendi yakıt deposu var',
          value: d.hasTank,
          onChanged: (v) => ctrl.update((x) => x.copyWith(hasTank: v)),
        ),
        if (d.hasTank) ...[
          const SizedBox(height: 8),
          FieldNumberInput(
            label: 'Depo kapasitesi',
            unit: 'L',
            decimals: 3,
            value: d.tankCapacityLiters,
            onChanged: (v) =>
                ctrl.update((x) => x.copyWith(tankCapacityLiters: v)),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════ 3. İhtiyaç + ilk sipariş + tedarik

class _NeedsStep extends ConsumerWidget {
  const _NeedsStep({required this.args});

  final LeadWizardArgs args;

  static const _terminals = ['İzmit', 'Aliağa (İzmir)', 'Kırıkkale', 'Batman'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(leadWizardProvider(args));
    final ctrl = ref.read(leadWizardProvider(args).notifier);
    final d = s.draft;
    final o = s.effectiveOptions;
    final t = context.aknText;
    return FieldStaggeredList(
      padding: _pad,
      children: [
        _heading(
          context,
          'Yakıt ihtiyacı',
          'Kullanılan her ürün için aylık litreyi girin; taahhüt sözleşmeyle garanti edilen aylık miktardır.',
        ),
        if (d.products.isEmpty)
          Text(
            s.optionsError == null
                ? 'Ürünler yükleniyor…'
                : 'Ürün listesi yüklenemedi; bağlantı gelince tekrar deneyin.',
            style: t.bodySmall,
          ),
        for (final p in d.products)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AknCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    p.productName ?? o.productName(p.productId),
                    style: t.bodyStrong,
                  ),
                  const SizedBox(height: 8),
                  FieldNumberInput(
                    label: 'Aylık litre',
                    unit: 'L',
                    decimals: 3,
                    value: p.monthlyLiters == 0 ? null : p.monthlyLiters,
                    onChanged: (v) => ctrl.setProductLiters(
                      p.productId,
                      monthly: v,
                      setMonthly: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FieldNumberInput(
                    label: 'Taahhüt',
                    unit: 'L',
                    decimals: 3,
                    value: p.committedMonthlyLiters,
                    onChanged: (v) => ctrl.setProductLiters(
                      p.productId,
                      committed: v,
                      setCommitted: true,
                    ),
                  ),
                  FieldErrorText(s.errors['product:${p.productId}']),
                ],
              ),
            ),
          ),
        FactRow(
          label: 'Toplam aylık ihtiyaç',
          value: d.totalMonthlyLiters > 0
              ? Fmt.liters(d.totalMonthlyLiters)
              : '—',
        ),
        const SizedBox(height: 16),
        _heading(context, 'İlk sipariş'),
        FieldPickerTile<int>(
          label: 'İlk sipariş ürünü',
          value: d.firstOrderProductId,
          options: [
            for (final p in o.products)
              if (int.tryParse(p.value) case final id?)
                FieldPickerOption(value: id, title: p.text),
          ],
          onSelected: (v) =>
              ctrl.update((x) => x.copyWith(firstOrderProductId: v)),
        ),
        _gap,
        FieldNumberInput(
          label: 'İlk sipariş litresi',
          unit: 'L',
          decimals: 3,
          value: d.firstOrderLiters,
          onChanged: (v) => ctrl.update((x) => x.copyWith(firstOrderLiters: v)),
        ),
        _gap,
        DateField(
          label: 'İlk sevk tarihi',
          value: d.firstShipDate,
          firstDate: TrTime.todayStart(),
          onChanged: (v) => ctrl.update((x) => x.copyWith(firstShipDate: v)),
        ),
        _gap,
        FieldNumberInput(
          label: 'Sözleşme süresi',
          unit: 'ay',
          integer: true,
          value: d.contractMonths,
          error: s.errors['contractMonths'],
          onChanged: (v) => ctrl.update(
            (x) => x.copyWith(contractMonths: v?.round()),
            clears: {'contractMonths'},
          ),
        ),
        const SizedBox(height: 16),
        _heading(context, 'Mevcut tedarik'),
        FieldTextInput(
          label: 'Anadağıtım (mevcut / tercih)',
          value: d.currentDistributor,
          maxLength: 80,
          onChanged: (v) =>
              ctrl.update((x) => x.copyWith(currentDistributor: v)),
        ),
        if (o.distributors.isNotEmpty)
          FilterChips<String>(
            padding: EdgeInsets.zero,
            options: [
              for (final x in o.distributors.take(8))
                FilterOption(value: x, label: x),
            ],
            selected: {?d.currentDistributor},
            onChanged: (sel) {
              if (sel.isNotEmpty) {
                ctrl.update((x) => x.copyWith(currentDistributor: sel.first));
              }
            },
          ),
        _gap,
        FieldTextInput(
          label: 'Terminal',
          value: d.currentTerminal,
          maxLength: 80,
          onChanged: (v) => ctrl.update((x) => x.copyWith(currentTerminal: v)),
        ),
        FilterChips<String>(
          padding: EdgeInsets.zero,
          options: [
            for (final x in _terminals) FilterOption(value: x, label: x),
          ],
          selected: {?d.currentTerminal},
          onChanged: (sel) {
            if (sel.isNotEmpty) {
              ctrl.update((x) => x.copyWith(currentTerminal: sel.first));
            }
          },
        ),
        _gap,
        FieldTextInput(
          label: 'Mevcut fiyat / iskonto',
          hint: 'Örn. pompa −%2,5',
          value: d.currentPriceNote,
          maxLength: 300,
          onChanged: (v) => ctrl.update((x) => x.copyWith(currentPriceNote: v)),
        ),
        _gap,
        FieldTextInput(
          label: 'Fiyat beklentisi',
          value: d.priceExpectation,
          maxLength: 300,
          onChanged: (v) => ctrl.update((x) => x.copyWith(priceExpectation: v)),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════ 4. Ödeme talebi + teminat

class _PaymentStep extends ConsumerWidget {
  const _PaymentStep({required this.args});

  final LeadWizardArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(leadWizardProvider(args));
    final ctrl = ref.read(leadWizardProvider(args).notifier);
    final d = s.draft;
    final o = s.effectiveOptions;
    final t = context.aknText;
    return FieldStaggeredList(
      padding: _pad,
      children: [
        _heading(context, 'Ödeme talebi'),
        Text('İstenen ödeme yöntemleri', style: t.label),
        const SizedBox(height: 4),
        FilterChips<String>(
          padding: EdgeInsets.zero,
          multi: true,
          options: [
            for (final m in o.paymentMethods)
              FilterOption(value: m.value, label: m.text),
          ],
          selected: d.requestedMethodCodes.toSet(),
          onChanged: (sel) => ctrl.update(
            (x) => x.copyWith(
              requestedMethodCodes: [
                for (final m in o.paymentMethods)
                  if (sel.contains(m.value)) m.value,
              ],
            ),
          ),
        ),
        _gap,
        FieldNumberInput(
          label: 'Vade',
          unit: 'gün',
          integer: true,
          value: d.requestedTermDays,
          error: s.errors['requestedTermDays'],
          onChanged: (v) => ctrl.update(
            (x) => x.copyWith(requestedTermDays: v?.round()),
            clears: {'requestedTermDays'},
          ),
        ),
        _gap,
        FieldNumberInput(
          label: 'Talep edilen limit',
          unit: '₺',
          value: d.requestedLimitAmount,
          helper: 'Finans onayında aylık tutar limiti olarak önerilir.',
          onChanged: (v) =>
              ctrl.update((x) => x.copyWith(requestedLimitAmount: v)),
        ),
        const SizedBox(height: 16),
        _heading(context, 'Teminat önerisi'),
        FieldPickerTile<int>(
          label: 'Teminat türü',
          value: d.collateralOfferKind?.code ?? 0,
          options: [
            const FieldPickerOption(value: 0, title: 'Teminat yok'),
            for (final k in CollateralOfferKind.values)
              FieldPickerOption(value: k.code, title: k.label),
          ],
          onSelected: (v) => ctrl.update(
            (x) => x.copyWith(
              collateralOfferKind: CollateralOfferKind.fromCode(v),
            ),
          ),
        ),
        if (d.collateralOfferKind != null) ...[
          _gap,
          FieldNumberInput(
            label: 'Teminat tutarı',
            unit: '₺',
            value: d.collateralOfferAmount,
            onChanged: (v) =>
                ctrl.update((x) => x.copyWith(collateralOfferAmount: v)),
          ),
          _gap,
          FieldTextInput(
            label: 'Teminat notu',
            hint: 'Banka, şube, vade…',
            value: d.collateralOfferNote,
            maxLength: 150,
            onChanged: (v) =>
                ctrl.update((x) => x.copyWith(collateralOfferNote: v)),
          ),
        ],
        _gap,
        FieldNumberInput(
          label: 'Teminat oranı',
          unit: '%',
          value: d.collateralRatioPercent,
          helper: 'DBS ve teminat mektubu %100 sayılır.',
          error: s.errors['collateralRatioPercent'],
          onChanged: (v) => ctrl.update(
            (x) => x.copyWith(collateralRatioPercent: v),
            clears: {'collateralRatioPercent'},
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════ 5. Ziyaret

class _VisitStep extends ConsumerStatefulWidget {
  const _VisitStep({required this.args});

  final LeadWizardArgs args;

  @override
  ConsumerState<_VisitStep> createState() => _VisitStepState();
}

class _VisitStepState extends ConsumerState<_VisitStep> {
  FieldLocationOutcome? _outcome;
  bool _busy = false;

  Future<void> _locate() async {
    setState(() => _busy = true);
    final o = await captureFieldLocation(
      context,
      ref,
      reason: FieldCopy.visitPrimerReason,
      icon: PhosphorIconsRegular.storefront,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = o;
    });
    if (o is LocationCaptured) {
      ref
          .read(leadWizardProvider(widget.args).notifier)
          .setVisitLocation(o.fix);
      final view = View.maybeOf(context);
      if (view != null) {
        await SemanticsService.sendAnnouncement(
          view,
          'Konum eklendi, doğruluk ${Fmt.number(o.fix.accuracyMeters, maxFraction: 0)} metre',
          TextDirection.ltr,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(leadWizardProvider(widget.args));
    final ctrl = ref.read(leadWizardProvider(widget.args).notifier);
    final d = s.draft;
    final t = context.aknText;
    final today = TrTime.todayStart();
    final approximate =
        _outcome is LocationCaptured &&
        (_outcome! as LocationCaptured).fix.approximate;
    return FieldStaggeredList(
      padding: _pad,
      children: [
        _heading(context, 'Ziyaret'),
        DateField(
          label: 'Ziyaret tarihi',
          value: d.visitAt,
          firstDate: TrTime.addDays(today, -365),
          lastDate: TrTime.addDays(today, 30),
          onChanged: (v) => ctrl.update((x) => x.copyWith(visitAt: v)),
        ),
        _gap,
        AknCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const AknIconBox(icon: PhosphorIconsRegular.gpsFix),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ziyaret konumu', style: t.bodyStrong),
                        Text(
                          d.hasVisitLocation
                              ? '${Fmt.number(d.visitLatitude, maxFraction: 6)}, ${Fmt.number(d.visitLongitude, maxFraction: 6)}'
                              : 'İsteğe bağlı; konum yalnızca bu kayda eklenir',
                          style: t.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (d.hasVisitLocation) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AccuracyChip(
                      meters: d.visitAccuracyMeters,
                      approximate: approximate,
                    ),
                    if ((d.visitAccuracyMeters ?? 0) > 50 && !approximate)
                      Text('Konum doğruluğu düşük', style: t.caption),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AknButton.secondary(
                    label: _busy
                        ? 'Konum alınıyor…'
                        : d.hasVisitLocation
                        ? 'Konumu güncelle'
                        : 'Konumu ekle',
                    icon: PhosphorIconsRegular.gpsFix,
                    size: AknButtonSize.small,
                    onPressed: _busy ? null : _locate,
                  ),
                  if (d.hasVisitLocation) ...[
                    AknButton.ghost(
                      label: 'Haritada aç',
                      icon: PhosphorIconsRegular.mapTrifold,
                      size: AknButtonSize.small,
                      onPressed: () => launchExternal(
                        Uri.parse(
                          'https://www.google.com/maps/search/?api=1&query=${d.visitLatitude},${d.visitLongitude}',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    AknButton.ghost(
                      label: 'Temizle',
                      size: AknButtonSize.small,
                      onPressed: () {
                        setState(() => _outcome = null);
                        ctrl.clearVisitLocation();
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        FieldLocationNotice(
          outcome: _outcome,
          onRetry: _locate,
          onContinueWithout: () => setState(() => _outcome = null),
          margin: const EdgeInsets.only(top: 12),
        ),
        _gap,
        FieldTextInput(
          label: 'Ziyaret notu',
          hint: 'Görüşülen kişi, ihtiyaç, rakip teklifi, sonraki adım…',
          value: d.visitNote,
          maxLength: 1000,
          maxLines: 4,
          minLines: 3,
          onChanged: (v) => ctrl.update((x) => x.copyWith(visitNote: v)),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════ 6. Yetkililer

class _ContactsStep extends ConsumerWidget {
  const _ContactsStep({required this.args});

  final LeadWizardArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(leadWizardProvider(args));
    final ctrl = ref.read(leadWizardProvider(args).notifier);
    final contacts = s.draft.contacts;
    final t = context.aknText;
    return FieldStaggeredList(
      padding: _pad,
      children: [
        _heading(
          context,
          'Yetkililer',
          'En az bir yetkili; portal daveti alacak kişiyi seçin.',
        ),
        for (var i = 0; i < contacts.length; i++)
          Padding(
            key: ValueKey('contact-$i-${contacts.length}'),
            padding: const EdgeInsets.only(bottom: 12),
            child: AknCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Yetkili ${i + 1}', style: t.bodyStrong),
                      ),
                      if (contacts.length > 1)
                        AknIconButton(
                          icon: PhosphorIconsRegular.trash,
                          semanticLabel: 'Yetkili ${i + 1} kaldır',
                          onPressed: () => ctrl.removeContact(i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FieldTextInput(
                    label: 'Ad soyad',
                    value: contacts[i].name,
                    requiredMark: true,
                    maxLength: 150,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    onChanged: (v) =>
                        ctrl.updateContact(i, (c) => c.copyWith(name: v)),
                  ),
                  _gap,
                  FieldTextInput(
                    label: 'Unvan',
                    hint: 'Örn. Satın alma müdürü',
                    value: contacts[i].title,
                    maxLength: 100,
                    onChanged: (v) =>
                        ctrl.updateContact(i, (c) => c.copyWith(title: v)),
                  ),
                  _gap,
                  FieldTextInput(
                    label: 'Telefon',
                    value: contacts[i].phone,
                    requiredMark: true,
                    maxLength: 30,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    onChanged: (v) =>
                        ctrl.updateContact(i, (c) => c.copyWith(phone: v)),
                  ),
                  _gap,
                  FieldTextInput(
                    label: 'E-posta',
                    value: contacts[i].email,
                    requiredMark: true,
                    maxLength: 256,
                    keyboardType: TextInputType.emailAddress,
                    textCapitalization: TextCapitalization.none,
                    autofillHints: const [AutofillHints.email],
                    onChanged: (v) =>
                        ctrl.updateContact(i, (c) => c.copyWith(email: v)),
                  ),
                  FieldErrorText(s.errors['contact:$i']),
                  const SizedBox(height: 8),
                  ChoiceCard(
                    title: 'Portal daveti bu kişiye',
                    leadingIcon: PhosphorIconsRegular.envelopeSimple,
                    selected: contacts[i].isInviteRecipient,
                    onTap: () => ctrl.setInviteRecipient(i),
                  ),
                ],
              ),
            ),
          ),
        AknButton.secondary(
          label: 'Yetkili ekle',
          icon: PhosphorIconsRegular.userPlus,
          expand: true,
          onPressed: contacts.length >= LeadRules.maxContacts
              ? null
              : ctrl.addContact,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════ 7. İlk teslimat noktası

class _DeliveryStep extends ConsumerWidget {
  const _DeliveryStep({required this.args});

  final LeadWizardArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(leadWizardProvider(args));
    final ctrl = ref.read(leadWizardProvider(args).notifier);
    final d = s.draft;
    return FieldStaggeredList(
      padding: _pad,
      children: [
        _heading(
          context,
          'İlk teslimat noktası',
          'Cari açılışında oluşturulur.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: AknButton.ghost(
            label: 'Firma adresiyle aynı',
            icon: PhosphorIconsRegular.copy,
            onPressed: ctrl.copyCompanyAddressToDelivery,
          ),
        ),
        _gap,
        FieldTextInput(
          label: 'Nokta adı',
          hint: 'Örn. Merkez depo, Şantiye',
          value: d.deliveryPointName,
          maxLength: 150,
          onChanged: (v) =>
              ctrl.update((x) => x.copyWith(deliveryPointName: v)),
        ),
        _gap,
        _CityField(
          label: 'İl',
          value: d.deliveryPointCity,
          onChanged: (v) =>
              ctrl.update((x) => x.copyWith(deliveryPointCity: v)),
        ),
        _gap,
        FieldTextInput(
          label: 'İlçe',
          value: d.deliveryPointDistrict,
          maxLength: 50,
          textCapitalization: TextCapitalization.words,
          onChanged: (v) =>
              ctrl.update((x) => x.copyWith(deliveryPointDistrict: v)),
        ),
        _gap,
        FieldTextInput(
          label: 'Adres',
          value: d.deliveryPointAddress,
          maxLength: 500,
          maxLines: 3,
          minLines: 2,
          onChanged: (v) =>
              ctrl.update((x) => x.copyWith(deliveryPointAddress: v)),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════ 8. KVKK

class _KvkkStep extends ConsumerWidget {
  const _KvkkStep({required this.args});

  final LeadWizardArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(leadWizardProvider(args));
    final ctrl = ref.read(leadWizardProvider(args).notifier);
    final d = s.draft;
    final o = s.effectiveOptions;
    final t = context.aknText;
    final text = o.kvkkText.isEmpty ? LeadRules.kvkkTextFallback : o.kvkkText;
    final methods = o.kvkkMethods.isEmpty
        ? LeadRules.kvkkMethodsFallback
        : o.kvkkMethods;
    // "açık rıza" web formundaki gibi vurgulanır; cümle değişmez.
    const strong = 'açık rıza';
    final i = text.indexOf(strong);
    final span = i < 0
        ? TextSpan(text: text)
        : TextSpan(
            children: [
              TextSpan(text: text.substring(0, i)),
              TextSpan(
                text: strong,
                style: t.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.akn.ink,
                ),
              ),
              TextSpan(text: text.substring(i + strong.length)),
            ],
          );
    return FieldStaggeredList(
      padding: _pad,
      children: [
        _heading(
          context,
          'KVKK açık rıza',
          'Finansa göndermek için firma yetkilisinin açık rızası ve alınma yöntemi gerekir.',
        ),
        AknCard(
          child: FieldCheckTile(
            title: text,
            value: d.kvkkConsent,
            onChanged: (v) => ctrl.update((x) => x.copyWith(kvkkConsent: v)),
            child: Text.rich(span, style: t.body),
          ),
        ),
        if (d.kvkkConsent) ...[
          _gap,
          FieldPickerTile<String>(
            label: 'Rızanın alınma yöntemi',
            requiredMark: true,
            value: d.kvkkConsentMethod,
            options: [
              for (final m in methods) FieldPickerOption(value: m, title: m),
            ],
            onSelected: (v) =>
                ctrl.update((x) => x.copyWith(kvkkConsentMethod: v)),
          ),
        ],
        if (o.kvkkVersion.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Metin sürümü ${o.kvkkVersion}', style: t.caption),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════ 9. Belgeler

class _DocumentsStep extends ConsumerWidget {
  const _DocumentsStep({required this.args});

  final LeadWizardArgs args;

  static const _optional = [
    AttachmentKind.signatureCircular,
    AttachmentKind.tradeRegistryGazette,
    AttachmentKind.activityCertificate,
    AttachmentKind.visitPhoto,
    AttachmentKind.other,
  ];

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    AttachmentKind kind,
  ) async {
    final source = await showAppSheet<CaptureSource>(
      context: context,
      title: kind.label,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AknListTile(
            title: 'Fotoğraf çek',
            leadingIcon: PhosphorIconsRegular.camera,
            onTap: () => Navigator.of(ctx).pop(CaptureSource.camera),
          ),
          AknListTile(
            title: 'Galeriden seç',
            leadingIcon: PhosphorIconsRegular.images,
            onTap: () => Navigator.of(ctx).pop(CaptureSource.gallery),
          ),
          // Saha fotoğrafı her zaman kameradan / galeriden; belgeler hazır PDF de olabilir.
          if (kind != AttachmentKind.visitPhoto)
            AknListTile(
              title: 'Dosya (PDF)',
              leadingIcon: PhosphorIconsRegular.filePdf,
              onTap: () => Navigator.of(ctx).pop(CaptureSource.file),
            ),
        ],
      ),
    );
    if (source == null || !context.mounted) return;
    final input = await ref.read(leadDocPickerProvider)(context, kind, source);
    if (input == null) return;
    await ref.read(leadWizardProvider(args).notifier).addDocument(input);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(leadWizardProvider(args));
    final ctrl = ref.read(leadWizardProvider(args).notifier);
    final t = context.aknText;
    final missing = s.missingNow;
    final required = s.effectiveOptions.requiredKinds;
    final kinds = [
      ...required,
      for (final k in _optional)
        if (!required.contains(k)) k,
    ];
    return FieldStaggeredList(
      padding: _pad,
      children: [
        _heading(
          context,
          'Belgeler',
          'Vergi levhası zorunludur; imza sirküleri, ticaret sicil gazetesi, faaliyet belgesi ve saha fotoğrafları isteğe bağlıdır.',
        ),
        if (missing.isNotEmpty) ...[
          AknCard(
            accent: AknTone.warn,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Finansa göndermeden önce', style: t.bodyStrong),
                const SizedBox(height: 4),
                for (final m in missing)
                  // Tam yükseklikte satır: dokunma hedefi en az 48 dp.
                  AknListTile(
                    title: m,
                    leadingIcon: PhosphorIconsRegular.circle,
                    leadingTone: AknTone.warn,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    onTap: () =>
                        ctrl.goTo(LeadWizardController.stepOfMissing(m)),
                  ),
              ],
            ),
          ),
          _gap,
        ] else ...[
          const AknBanner(
            tone: AknTone.ok,
            message: 'Finansa göndermek için gerekenler tamam.',
          ),
          _gap,
        ],
        if (s.draft.isNew && s.queuedOpId == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Bağlantı varsa belgeler hemen yüklenir; yoksa kayıtla birlikte bağlantı gelince gönderilir.',
              style: t.caption,
            ),
          ),
        for (final kind in kinds) ...[
          _KindRow(
            kind: kind,
            required: required.contains(kind),
            uploaded: s.serverDocs
                .where((a) => a.kind == kind && a.isActive)
                .length,
            local: s.localDocs.where((d) => d.input.kind == kind).length,
            onAdd: () => _add(context, ref, kind),
          ),
          const SizedBox(height: 8),
        ],
        if (s.localDocs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Bu cihazda', style: t.bodyStrong),
          const SizedBox(height: 8),
          for (final d in s.localDocs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AttachmentTile(
                fileName: d.input.fileName,
                kindLabel: d.input.kind.label,
                sizeBytes: d.input.sizeBytes == 0 ? null : d.input.sizeBytes,
                contentType: d.input.contentType,
                thumbnail:
                    d.input.contentType.startsWith('image/') &&
                        File(d.input.path).existsSync()
                    ? Image.file(
                        File(d.input.path),
                        fit: BoxFit.cover,
                        cacheWidth: 120,
                      )
                    : null,
                subtitle: switch (d.state) {
                  LeadDocState.queued => 'Bağlantı gelince yüklenecek',
                  LeadDocState.pending => 'Kayıtla birlikte yüklenecek',
                  _ => null,
                },
                state: switch (d.state) {
                  LeadDocState.uploading => AttachmentTileState.uploading,
                  LeadDocState.failed => AttachmentTileState.failed,
                  _ => AttachmentTileState.idle,
                },
                progress: d.progress,
                errorText: d.error,
                onRetry: d.state == LeadDocState.failed
                    ? () => ctrl.retryDocument(d.localId)
                    : null,
                onDelete: d.state == LeadDocState.uploading
                    ? null
                    : () => ctrl.removeLocalDocument(d.localId),
              ),
            ),
        ],
        if (s.serverDocs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Yüklenenler', style: t.bodyStrong),
          const SizedBox(height: 8),
          FieldDocumentList(
            attachments: s.serverDocs,
            onDelete: (a) => ctrl.removeServerDocument(a),
          ),
        ],
      ],
    );
  }
}

class _KindRow extends StatelessWidget {
  const _KindRow({
    required this.kind,
    required this.required,
    required this.uploaded,
    required this.local,
    required this.onAdd,
  });

  final AttachmentKind kind;
  final bool required;
  final int uploaded;
  final int local;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final done = uploaded > 0;
    final (tone, icon, status) = done
        ? (AknTone.ok, PhosphorIconsFill.checkCircle, 'Yüklendi')
        : local > 0
        ? (AknTone.warn, PhosphorIconsRegular.clock, 'Yüklenmeyi bekliyor')
        : required
        ? (AknTone.danger, PhosphorIconsRegular.warningCircle, 'Zorunlu')
        : (AknTone.neutral, PhosphorIconsRegular.cameraPlus, 'İsteğe bağlı');
    return AknCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          AknIconBox(icon: icon, tone: tone, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  required ? '${kind.label} *' : kind.label,
                  style: t.bodyStrong,
                ),
                Text(
                  [
                    status,
                    if (uploaded + local > 0) '${uploaded + local} dosya',
                  ].join(', '),
                  style: t.caption,
                ),
              ],
            ),
          ),
          AknButton.ghost(
            label: 'Ekle',
            icon: PhosphorIconsRegular.cameraPlus,
            size: AknButtonSize.small,
            semanticLabel: '${kind.label} ekle',
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}
