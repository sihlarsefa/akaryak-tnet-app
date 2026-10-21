import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../application/field_access.dart';
import '../application/field_lists.dart';
import '../application/form_wizard_controller.dart';
import '../copy.dart';
import '../data/field_draft.dart';
import '../data/field_models.dart';
import '../data/field_repository.dart';
import 'form_preview.dart';
import 'widgets/field_inputs.dart';
import 'widgets/field_widgets.dart';

/// Sihirbaz adımının gövdesi.
class FieldWizardStepBody extends StatelessWidget {
  const FieldWizardStepBody({
    super.key,
    required this.args,
    required this.step,
  });

  final FormWizardArgs args;
  final FieldWizardStep step;

  @override
  Widget build(BuildContext context) => switch (step) {
    FieldWizardStep.customer => _CustomerStep(args: args),
    FieldWizardStep.supply => _SupplyStep(args: args),
    FieldWizardStep.payment => _PaymentStep(args: args),
    FieldWizardStep.lines => _LinesStep(args: args),
    FieldWizardStep.summary => _SummaryStep(args: args),
  };
}

const _pad = EdgeInsets.fromLTRB(16, 8, 16, 24);
const _gap = SizedBox(height: 14);

// ═══════════════════════════════════════════════════════════════════ 1. Cari

class _CustomerStep extends ConsumerStatefulWidget {
  const _CustomerStep({required this.args});

  final FormWizardArgs args;

  @override
  ConsumerState<_CustomerStep> createState() => _CustomerStepState();
}

class _CustomerStepState extends ConsumerState<_CustomerStep> {
  bool _changing = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(formWizardProvider(widget.args));
    final ctrl = ref.read(formWizardProvider(widget.args).notifier);
    final t = context.aknText;
    final o = s.options;
    final picking = !s.hasCustomer || _changing;
    return ListView(
      padding: _pad,
      children: [
        if (s.resumeCandidate != null) ...[
          _ResumeCard(
            draft: s.resumeCandidate!,
            savedAt: s.resumeSavedAt,
            onResume: ctrl.resume,
            onDiscard: ctrl.discardResume,
          ),
          _gap,
        ],
        if (picking)
          _CustomerPicker(
            error: s.errors['customer'],
            onPicked: (id, title) {
              setState(() => _changing = false);
              ctrl.selectCustomer(id, title);
            },
          )
        else ...[
          AknCard(
            child: FieldTitleRow(
              title: Row(
                children: [
                  AknAvatar(name: s.draft.customerTitle ?? 'Cari', size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.draft.customerTitle ?? '—', style: t.bodyStrong),
                        if (o?.city != null) Text(o!.city!, style: t.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              trailing: s.draft.isNew
                  ? TextButton(
                      onPressed: () => setState(() => _changing = true),
                      child: const Text('Değiştir'),
                    )
                  : null,
            ),
          ),
          FieldErrorText(s.errors['customer']),
          _gap,
          if (s.optionsLoading && o == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: LoadingView(message: 'Ürünler ve fiyatlar yükleniyor'),
            )
          else if (s.optionsError != null && o == null)
            ErrorState(
              compact: true,
              message: s.optionsError!.message,
              onRetry: ctrl.loadOptions,
            )
          else if (o != null) ...[
            _LimitCard(limit: o.limit),
            _gap,
            DateField(
              label: 'Sevk tarihi',
              value: s.draft.shipDate,
              helper: 'Satır teslim tarihlerinin varsayılanı',
              errorText: s.errors['shipDate'],
              firstDate: TrTime.todayStart(),
              onChanged: ctrl.setShipDate,
            ),
            if (o.payment?.blockedReason != null) ...[
              _gap,
              AknBanner(tone: AknTone.warn, message: o.payment!.blockedReason!),
            ],
          ],
        ],
      ],
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.draft,
    required this.savedAt,
    required this.onResume,
    required this.onDiscard,
  });

  final FieldFormDraft draft;
  final DateTime? savedAt;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return AknCard(
      accent: AknTone.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Yarım kalan formunuza devam edin', style: t.bodyStrong),
          const SizedBox(height: 4),
          Text(
            [
              draft.customerTitle ?? 'Cari seçilmedi',
              if (draft.lines.isNotEmpty) '${draft.lines.length} satır',
              if (savedAt != null) Fmt.relative(savedAt),
            ].join(' · '),
            style: t.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AknButton(
                label: 'Devam et',
                size: AknButtonSize.small,
                onPressed: onResume,
              ),
              AknButton.ghost(
                label: 'Yeni başla',
                size: AknButtonSize.small,
                onPressed: onDiscard,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final _customerSearchProvider = FutureProvider.autoDispose
    .family<List<IdName>, String>((ref, term) {
      final stationId = ref.read(accessPolicyProvider).access?.stationId ?? 0;
      return ref
          .read(fieldRepositoryProvider)
          .searchCustomers(
            stationId: stationId,
            term: term.isEmpty ? null : term,
          );
    });

/// Cari seçimi: temsilci portföyünde, diğerleri bayinin carilerinde arar.
class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker({required this.onPicked, this.error});

  final void Function(int id, String title) onPicked;
  final String? error;

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  String _term = '';

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(fieldAccessProvider);
    final t = context.aknText;
    final List<(int, String, String?)> rows;
    bool loading;
    String? error;
    if (access.isRep) {
      final p = ref.watch(fieldPortfolioProvider(_term));
      rows = [
        for (final r in p.items)
          (
            r.customerId,
            r.customerTitle,
            [
              if (r.customerCode.isNotEmpty) r.customerCode,
              ?r.city,
            ].join(' · '),
          ),
      ];
      loading = p.firstLoading;
      error = p.error?.message;
    } else {
      final res = ref.watch(_customerSearchProvider(_term));
      rows = [
        for (final r in res.valueOrNull ?? const <IdName>[])
          (r.id, r.name, r.extra),
      ];
      loading = res.isLoading;
      error = res.hasError ? 'Cariler yüklenemedi.' : null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Hangi cari için?', style: t.headline),
        ),
        const SizedBox(height: 4),
        Text(
          access.isRep
              ? 'Portföyünüzdeki cariler listelenir.'
              : 'Bayinizin carilerinde arayın.',
          style: t.bodySmall,
        ),
        const SizedBox(height: 12),
        SearchField(
          hint: access.isRep ? 'Portföyünüzde arayın' : 'Ünvan, kod ya da VKN',
          onChanged: (s) => setState(() => _term = s),
        ),
        FieldErrorText(widget.error),
        const SizedBox(height: 8),
        if (loading && rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: ChevronSpinner(size: 26)),
          )
        else if (rows.isEmpty)
          EmptyState(
            compact: true,
            title:
                error ??
                (access.isRep
                    ? FieldCopy.portfolioEmptyTitle
                    : 'Cari bulunamadı'),
            message: error == null && access.isRep && _term.isEmpty
                ? FieldCopy.portfolioEmptyMessage
                : null,
            illustration: error == null
                ? AknIllustration.customers
                : AknIllustration.error,
          )
        else
          for (final (id, title, sub) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AknCard(
                padding: EdgeInsets.zero,
                onTap: () => widget.onPicked(id, title),
                semanticLabel: [
                  title,
                  if (sub != null && sub.isNotEmpty) sub,
                ].join(', '),
                child: AknListTile(
                  title: title,
                  subtitle: sub,
                  leading: AknAvatar(name: title, size: 36),
                ),
              ),
            ),
      ],
    );
  }
}

class _LimitCard extends StatelessWidget {
  const _LimitCard({required this.limit});

  final FieldLimitStatus limit;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final ratio = limit.usedRatio;
    final blocking = limit.isBlocking;
    return AknCard(
      accent: blocking ? AknTone.danger : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.speed_rounded, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Limit', style: t.bodyStrong)),
              if (limit.isUnlimited)
                const StatusChip(
                  label: 'Limitsiz',
                  tone: AknTone.ok,
                  icon: Icons.all_inclusive_rounded,
                  size: StatusChipSize.small,
                ),
            ],
          ),
          if (ratio != null) ...[
            const SizedBox(height: 10),
            UsageBar(
              value: ratio,
              label: '${limit.limitPeriod ?? 'Dönem'} kullanım',
              valueLabel: '%${(ratio * 100).round()}',
            ),
          ],
          if (limit.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(limit.message, style: t.bodySmall),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════ 2. Tedarik

class _SupplyStep extends ConsumerWidget {
  const _SupplyStep({required this.args});

  final FormWizardArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(formWizardProvider(args));
    final ctrl = ref.read(formWizardProvider(args).notifier);
    final d = s.draft;
    final o = s.options;
    final t = context.aknText;
    final distributors = [
      for (final x in s.supply)
        if (x.isDistributor) x.name,
    ];
    final terminals = [
      for (final x in s.supply)
        if (!x.isDistributor) x.name,
    ];
    return ListView(
      padding: _pad,
      children: [
        FieldTextInput(
          label: 'Anadağıtım',
          hint: 'Dağıtıcı',
          value: d.distributorName,
          maxLength: 80,
          onChanged: (v) => ctrl.update((x) => x.copyWith(distributorName: v)),
        ),
        _Suggestions(
          values: distributors,
          selected: d.distributorName,
          onPick: (v) => ctrl.update((x) => x.copyWith(distributorName: v)),
        ),
        _gap,
        FieldTextInput(
          label: 'Terminal',
          hint: 'Terminal / depo',
          value: d.terminalName,
          maxLength: 80,
          onChanged: (v) => ctrl.update((x) => x.copyWith(terminalName: v)),
        ),
        _Suggestions(
          values: terminals,
          selected: d.terminalName,
          onPick: (v) => ctrl.update((x) => x.copyWith(terminalName: v)),
        ),
        _gap,
        if (o != null && o.locations.isNotEmpty) ...[
          Text('Tüpraş lokasyonu', style: t.label),
          const SizedBox(height: 4),
          Text(
            'Satırlardaki Tüpraş referans fiyatı bu lokasyondan gelir.',
            style: t.caption,
          ),
          FilterChips<String>(
            padding: EdgeInsets.zero,
            options: [
              for (final l in o.locations)
                FilterOption(value: l.code, label: l.label),
            ],
            selected: {?d.refineryLocation},
            allowEmpty: false,
            onChanged: (sel) {
              if (sel.isNotEmpty) ctrl.setLocation(sel.first);
            },
          ),
          _gap,
        ],
        Text('Nakliye', style: t.bodyStrong),
        const SizedBox(height: 8),
        FieldNumberInput(
          label: 'Nakliye mesafesi',
          unit: 'km',
          decimals: 2,
          value: d.transportKm,
          error: s.errors['transportKm'],
          onChanged: (v) => ctrl.update(
            (x) => x.copyWith(transportKm: v),
            clears: {'transportKm'},
          ),
        ),
        if (!d.isCombinedShipment) ...[
          _gap,
          FieldNumberInput(
            label: 'Nakliye tutarı',
            unit: '₺',
            value: d.transportTotal,
            helper: 'Litreye göre satırlara bölünür.',
            error: s.errors['transportTotal'],
            onChanged: (v) => ctrl.update(
              (x) => x.copyWith(transportTotal: v),
              clears: {'transportTotal'},
            ),
          ),
        ],
        const SizedBox(height: 8),
        FieldSwitchTile(
          title: 'Birleştirilmiş sevkiyat',
          subtitle: 'Tır başka siparişlerle paylaşılıyor',
          value: d.isCombinedShipment,
          onChanged: (v) =>
              ctrl.update((x) => x.copyWith(isCombinedShipment: v)),
        ),
        if (d.isCombinedShipment) ...[
          const SizedBox(height: 8),
          FieldNumberInput(
            label: 'Tırın toplam litresi',
            unit: 'L',
            decimals: 3,
            value: d.combinedTruckLiters,
            error: s.errors['combinedTruckLiters'],
            onChanged: (v) => ctrl.update(
              (x) => x.copyWith(combinedTruckLiters: v),
              clears: {'combinedTruckLiters'},
            ),
          ),
          _gap,
          FieldNumberInput(
            label: 'Tır nakliye tutarı',
            unit: '₺',
            value: d.combinedTruckCost,
            helper: 'Bu forma litresi oranında düşer.',
            error: s.errors['combinedTruckCost'],
            onChanged: (v) => ctrl.update(
              (x) => x.copyWith(combinedTruckCost: v),
              clears: {'combinedTruckCost'},
            ),
          ),
        ],
        if (s.showCosts) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Maliyet girdileri · yalnızca bayi içi',
                  style: t.captionStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FieldNumberInput(
            label: 'Alım vadesi',
            unit: 'gün',
            integer: true,
            value: d.purchaseTermDays,
            helper: 'Boş = satış vadesi.',
            onChanged: (v) =>
                ctrl.update((x) => x.copyWith(purchaseTermDays: v?.round())),
          ),
          _gap,
          FieldNumberInput(
            label: 'Alım şartı',
            unit: '%',
            decimals: 4,
            value: d.purchaseTermPercent,
            helper: 'Boş = barem setinin alım şartı tablosu.',
            error: s.errors['purchaseTermPercent'],
            onChanged: (v) => ctrl.update(
              (x) => x.copyWith(purchaseTermPercent: v),
              clears: {'purchaseTermPercent'},
            ),
          ),
          _gap,
          FieldNumberInput(
            label: 'Diğer',
            unit: '%',
            decimals: 4,
            value: d.otherPercent,
            helper: 'Visa / diğer kesintilere eklenir.',
            error: s.errors['otherPercent'],
            onChanged: (v) => ctrl.update(
              (x) => x.copyWith(otherPercent: v),
              clears: {'otherPercent'},
            ),
          ),
          if (!d.isCombinedShipment) ...[
            _gap,
            FieldNumberInput(
              label: 'Nakliye',
              unit: '%',
              decimals: 4,
              value: d.transportPercent,
              helper: 'Alım maliyeti üzerinden.',
              onChanged: (v) =>
                  ctrl.update((x) => x.copyWith(transportPercent: v)),
            ),
          ],
        ],
      ],
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.values,
    required this.selected,
    required this.onPick,
  });

  final List<String> values;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final list = values.take(8).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return FilterChips<String>(
      padding: EdgeInsets.zero,
      options: [for (final v in list) FilterOption(value: v, label: v)],
      selected: {
        for (final v in list)
          if (v == selected) v,
      },
      onChanged: (s) {
        if (s.isNotEmpty) onPick(s.first);
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════ 3. Ödeme

class _PaymentStep extends ConsumerWidget {
  const _PaymentStep({required this.args});

  final FormWizardArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(formWizardProvider(args));
    final ctrl = ref.read(formWizardProvider(args).notifier);
    final d = s.draft;
    final o = s.options;
    final t = context.aknText;
    final pay = o?.payment;
    final method = pay?.method(d.paymentMethodCode);
    final ship = d.shipDate;
    final due = ship == null ? null : TrTime.addDays(ship, d.paymentTermDays);
    final maxTerm = method?.maxTermDays ?? o?.maxPaymentTermDays ?? 365;
    final minTerm = method?.minTermDays ?? 0;
    return ListView(
      padding: _pad,
      children: [
        if (pay == null || !pay.enabled)
          const AknBanner(
            tone: AknTone.info,
            message:
                'Ödeme yöntemi seçimi bu bayide kapalı; yalnızca vadeyi girin. Yöntem siparişte belirlenir.',
          )
        else ...[
          Semantics(
            header: true,
            child: Text('Ödeme tipi', style: t.bodyStrong),
          ),
          const SizedBox(height: 8),
          ChoiceCard(
            title: 'Belirtilmemiş',
            subtitle: 'Siparişte bayinin varsayılanı uygulanır',
            leadingIcon: Icons.help_outline_rounded,
            selected: d.paymentMethodCode == null,
            margin: const EdgeInsets.only(bottom: 8),
            onTap: () => ctrl.setPaymentMethod(null),
          ),
          for (final m in pay.methods)
            ChoiceCard(
              title: m.name,
              subtitle: [
                if (m.isDeferred) 'Vadeli',
                if (m.requiresFinance) 'Finans onayına düşebilir',
                ?m.hint,
              ].join(' · '),
              tag: m.code == pay.defaultMethodCode ? 'Varsayılan' : null,
              leadingIcon: _methodIcon(m.code),
              selected: d.paymentMethodCode == m.code,
              margin: const EdgeInsets.only(bottom: 8),
              onTap: () => ctrl.setPaymentMethod(m.code),
            ),
          if (pay.blockedReason != null) ...[
            const SizedBox(height: 4),
            AknBanner(tone: AknTone.warn, message: pay.blockedReason!),
          ],
        ],
        _gap,
        FieldNumberInput(
          label: 'Vade',
          unit: 'gün',
          integer: true,
          value: d.paymentTermDays,
          helper: minTerm > 0
              ? '$minTerm–$maxTerm gün'
              : '0 = peşin · en çok $maxTerm gün',
          error: s.errors['paymentTermDays'],
          onChanged: (v) => ctrl.update(
            (x) => x.copyWith(paymentTermDays: v?.round() ?? 0),
            clears: {'paymentTermDays'},
          ),
        ),
        const SizedBox(height: 8),
        FactRow(
          label: 'Ödeme tarihi',
          value: due == null
              ? 'Sevk tarihi seçilince hesaplanır'
              : '${Fmt.date(due)} · ${Fmt.weekday(due)}',
          icon: Icons.event_rounded,
        ),
        Text('Sevk tarihi + vade', style: t.caption),
        if (method != null && method.fields.isNotEmpty) ...[
          const SizedBox(height: 16),
          _PaymentDetails(args: args, method: method),
        ],
        if (method?.documentKind != null) ...[
          const SizedBox(height: 12),
          AknBanner(
            tone: AknTone.info,
            icon: Icons.photo_camera_outlined,
            message:
                '${method!.documentKind!.label} sipariş açıldıktan sonra müşteri ya da bayi tarafından yüklenir.',
          ),
        ],
      ],
    );
  }

  static IconData _methodIcon(String code) => switch (code) {
    'CEK' => Icons.receipt_long_outlined,
    'SENET' => Icons.description_outlined,
    'HAVALE' => Icons.account_balance_outlined,
    'KART' => Icons.credit_card_rounded,
    'NAKIT' => Icons.payments_outlined,
    'DBS' => Icons.account_balance_wallet_outlined,
    'TEMINAT' => Icons.verified_user_outlined,
    _ => Icons.payments_outlined,
  };
}

/// Ödeme belgesi bilgileri (saha formunda isteğe bağlı).
class _PaymentDetails extends ConsumerWidget {
  const _PaymentDetails({required this.args, required this.method});

  final FormWizardArgs args;
  final PaymentMethodChoice method;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(formWizardProvider(args));
    final ctrl = ref.read(formWizardProvider(args).notifier);
    final details = s.draft.paymentDetails;
    final t = context.aknText;
    void set(String key, String value) => ctrl.update(
      (x) => x.copyWith(paymentDetails: {...x.paymentDetails, key: value}),
    );
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text('Ödeme belgesi bilgileri', style: t.bodyStrong),
        subtitle: Text(
          'İsteğe bağlı; sipariş açılınca da girilebilir.',
          style: t.caption,
        ),
        children: [
          for (final f in method.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: switch (f.type) {
                'money' => FieldNumberInput(
                  label: f.label,
                  unit: '₺',
                  value: double.tryParse(details[f.key] ?? ''),
                  onChanged: (v) => set(f.key, v == null ? '' : '$v'),
                ),
                'number' => FieldNumberInput(
                  label: f.label,
                  integer: true,
                  value: double.tryParse(details[f.key] ?? ''),
                  onChanged: (v) => set(f.key, v == null ? '' : '${v.round()}'),
                ),
                'date' => DateField(
                  label: f.label,
                  value: TrTime.parseDate(details[f.key]),
                  quickPicks: false,
                  onChanged: (v) => set(f.key, TrTime.isoDate(v)),
                ),
                'select' => FieldPickerTile<String>(
                  label: f.label,
                  value: details[f.key],
                  options: [
                    for (final c in f.choices)
                      FieldPickerOption(value: c.value, title: c.label),
                    if (f.choices.isEmpty)
                      for (final o in f.options)
                        FieldPickerOption(value: o, title: o),
                  ],
                  onSelected: (v) => set(f.key, v),
                ),
                _ => FieldTextInput(
                  label: f.label,
                  hint: f.placeholder,
                  value: details[f.key],
                  maxLength: f.maxLength,
                  maxLines: f.type == 'textarea' ? 3 : 1,
                  onChanged: (v) => set(f.key, v),
                ),
              },
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════ 4. Satırlar

class _LinesStep extends ConsumerWidget {
  const _LinesStep({required this.args});

  final FormWizardArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = ref.watch(
      formWizardProvider(
        args,
      ).select((s) => s.draft.lines.map((l) => l.key).join(',')),
    );
    final lines = keys.isEmpty ? const <String>[] : keys.split(',');
    final s = ref.watch(formWizardProvider(args).select((s) => s.options));
    final ctrl = ref.read(formWizardProvider(args).notifier);
    final error = ref.watch(
      formWizardProvider(args).select((s) => s.errors['lines']),
    );
    if (s == null) {
      return ListView(
        padding: _pad,
        children: const [
          EmptyState(
            compact: true,
            title: 'Önce cari seçin',
            message:
                'Ürünler, teslimat noktaları, Tüpraş referansı ve pompa fiyatı cari seçilince gelir.',
            illustration: AknIllustration.customers,
          ),
        ],
      );
    }
    return ListView(
      padding: _pad,
      children: [
        for (var i = 0; i < lines.length; i++)
          Padding(
            key: ValueKey(lines[i]),
            padding: const EdgeInsets.only(bottom: 12),
            child: _LineCard(
              args: args,
              lineKey: lines[i],
              index: i,
              removable: lines.length > 1,
            ),
          ),
        FieldErrorText(error),
        AknButton.secondary(
          label: 'Satır ekle',
          icon: Icons.add_rounded,
          expand: true,
          onPressed: lines.length >= 20 ? null : ctrl.addLine,
        ),
        if (lines.length >= 20)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Bir formda en çok 20 satır olabilir.',
              style: context.aknText.caption,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _LineCard extends ConsumerWidget {
  const _LineCard({
    required this.args,
    required this.lineKey,
    required this.index,
    required this.removable,
  });

  final FormWizardArgs args;
  final String lineKey;
  final int index;
  final bool removable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(formWizardProvider(args));
    final ctrl = ref.read(formWizardProvider(args).notifier);
    final o = s.options!;
    final line = s.draft.lines.firstWhere(
      (l) => l.key == lineKey,
      orElse: () => FieldLineDraft(key: lineKey),
    );
    final t = context.aknText;
    final c = context.akn;
    final product = o.product(line.productId);
    final location = s.draft.refineryLocation;
    final refTupras = product == null || location == null
        ? null
        : product.tuprasPricesM3[location];
    final refDate = product == null || location == null
        ? null
        : product.tuprasPriceDates[location];
    final stale = product?.isTuprasStale(location) ?? false;
    final pv = s.previewLine(lineKey);
    final error = s.errors['line:$lineKey'];
    final percentMode = s.showCosts && line.priceEntryMode == 1;
    void upd(FieldLineDraft Function(FieldLineDraft l) f) =>
        ctrl.updateLine(lineKey, f);

    return AknCard(
      accent: error != null ? AknTone.danger : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.brandSoft,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: t.label.copyWith(color: c.brandInk),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    product?.name ?? 'Satır ${index + 1}',
                    style: t.bodyStrong,
                  ),
                ),
              ),
              if (line.tuprasEdited)
                const StatusChip(
                  label: 'Tüpraş elle',
                  tone: AknTone.warn,
                  icon: Icons.edit_rounded,
                  size: StatusChipSize.small,
                ),
              if (removable)
                AknIconButton(
                  icon: Icons.delete_outline_rounded,
                  semanticLabel: '${index + 1}. satırı sil',
                  onPressed: () => ctrl.removeLine(lineKey),
                ),
            ],
          ),
          const SizedBox(height: 10),
          FieldPickerTile<int>(
            label: 'Ürün',
            requiredMark: true,
            value: line.productId,
            icon: Icons.local_gas_station_outlined,
            options: [
              for (final p in o.products)
                FieldPickerOption(
                  value: p.id,
                  title: p.name,
                  subtitle: p.suggestedUnitPrice == null
                      ? p.code
                      : '${Fmt.unitPrice(p.suggestedUnitPrice)}${p.suggestedSourceLabel == null ? '' : ' · ${p.suggestedSourceLabel}'}',
                ),
            ],
            onSelected: (id) => ctrl.setLineProduct(lineKey, id),
          ),
          _gap,
          FieldPickerTile<int>(
            label: 'Teslimat noktası',
            requiredMark: true,
            value: line.deliveryPointId,
            icon: Icons.place_outlined,
            options: [
              for (final p in o.points)
                FieldPickerOption(
                  value: p.id,
                  title: p.name,
                  subtitle: p.place,
                ),
            ],
            onSelected: (id) => upd((l) => l.copyWith(deliveryPointId: id)),
          ),
          _gap,
          FieldNumberInput(
            label: 'Litre',
            unit: 'L',
            decimals: 3,
            requiredMark: true,
            value: line.liters,
            onChanged: (v) => upd((l) => l.copyWith(liters: v)),
          ),
          _gap,
          DateField(
            label: 'Teslim tarihi',
            value: line.date ?? s.draft.shipDate,
            requiredMark: true,
            firstDate: TrTime.todayStart(),
            quickPicks: false,
            onChanged: (d) => upd((l) => l.copyWith(date: d)),
          ),
          _gap,
          if (s.showCosts && (o.costInputs?.profitPercentEntry ?? false)) ...[
            FilterChips<int>(
              padding: EdgeInsets.zero,
              options: const [
                FilterOption(value: 0, label: 'Fiyat ₺/L'),
                FilterOption(value: 1, label: 'Kâr %'),
              ],
              selected: {line.priceEntryMode},
              allowEmpty: false,
              onChanged: (m) {
                if (m.isNotEmpty) {
                  upd((l) => l.copyWith(priceEntryMode: m.first));
                }
              },
            ),
            const SizedBox(height: 10),
          ],
          if (percentMode)
            FieldNumberInput(
              label: 'Satış kârı',
              unit: '%',
              decimals: 4,
              requiredMark: true,
              value: line.profitPercent,
              helper: 'Fiyat sunucuda kârdan hesaplanır.',
              onChanged: (v) => upd((l) => l.copyWith(profitPercent: v)),
            )
          else
            FieldNumberInput(
              label: 'Fiyat',
              unit: '₺/L',
              decimals: 4,
              requiredMark: true,
              value: line.unitPrice,
              helper: _priceHelper(product, o.pricesIncludeVat),
              onChanged: (v) =>
                  upd((l) => l.copyWith(unitPrice: v, priceEdited: true)),
            ),
          _gap,
          FieldNumberInput(
            label: 'Tüpraş (KDV dahil)',
            unit: '₺/m³',
            decimals: 2,
            value: line.tuprasM3,
            helper: refTupras == null
                ? 'Referans fiyat yok; günün fiyatını yazabilirsiniz.'
                : stale
                ? 'Bugünün Tüpraş fiyatı girilmedi (son ${Fmt.date(refDate)}).'
                : 'Referans ${Fmt.pricePerM3(refTupras)}${refDate == null ? '' : ' · ${Fmt.dayMonth(refDate)}'}',
            onChanged: (v) => upd(
              (l) => l.copyWith(
                tuprasM3: v,
                tuprasEdited:
                    v != null &&
                    (refTupras == null || (v - refTupras).abs() >= 0.01),
              ),
            ),
          ),
          if (line.tuprasEdited && refTupras != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => ctrl.resetLineTupras(lineKey),
                child: const Text('Referansa dön'),
              ),
            ),
          _gap,
          FieldNumberInput(
            label: 'Pompa (KDV dahil)',
            unit: '₺/L',
            decimals: 4,
            value: line.pumpPrice,
            helper: product?.pumpPricePerLiter == null
                ? null
                : 'Liste ${Fmt.unitPrice(product!.pumpPricePerLiter)}',
            onChanged: (v) =>
                upd((l) => l.copyWith(pumpPrice: v, pumpEdited: true)),
          ),
          if (s.showCosts) ...[
            _gap,
            FieldNumberInput(
              label: 'Bindirim (KDV hariç)',
              unit: '₺/m³',
              decimals: 2,
              value: line.bindirimM3,
              helper:
                  'Boş = referans fiyatlardaki varsayılan; bindirim yoksa 0 yazın.',
              onChanged: (v) => upd((l) => l.copyWith(bindirimM3: v)),
            ),
          ],
          if (pv != null) ...[
            const SizedBox(height: 12),
            _LineResult(line: pv, showCosts: s.showCosts),
          ],
          FieldErrorText(error),
        ],
      ),
    );
  }

  static String? _priceHelper(FieldProductOption? p, bool includesVat) {
    if (p == null) return includesVat ? 'KDV dahil' : 'KDV hariç';
    final parts = <String>[
      includesVat ? 'KDV dahil' : 'KDV hariç',
      if (p.suggestedUnitPrice != null)
        '${p.suggestedSourceLabel ?? 'Öneri'} ${Fmt.unitPrice(p.suggestedUnitPrice)}',
      if (p.lastUnitPrice != null)
        'Son teklif ${Fmt.unitPrice(p.lastUnitPrice)}',
    ];
    return parts.join(' · ');
  }
}

/// Satırın önizleme sonucu (satış görüşmesi alanları; maliyet yalnızca showCosts).
class _LineResult extends StatelessWidget {
  const _LineResult({required this.line, required this.showCosts});

  final FieldPreviewLine line;
  final bool showCosts;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    String pct(double? v) => v == null
        ? '—'
        : '${v >= 0 ? '+' : '−'}${Fmt.percent(v.abs(), maxFraction: 1)}';
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: AknRadius.card,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FactRow(
            label: 'Fatura (KDV dahil)',
            value: line.invoicePerLiter == null
                ? '—'
                : '${Fmt.unitPrice(line.invoicePerLiter)} · ${Fmt.pricePerM3(line.unitPriceM3)}',
            padding: const EdgeInsets.symmetric(vertical: 3),
          ),
          FactRow(
            label: 'Satır tutarı',
            value: Fmt.money(line.amount),
            padding: const EdgeInsets.symmetric(vertical: 3),
          ),
          if (line.tuprasDiffPercent != null)
            FactRow(
              label: 'Tüpraş ±',
              value:
                  '${pct(line.tuprasDiffPercent)} · ${Fmt.pricePerM3(line.tuprasDiffM3)}',
              padding: const EdgeInsets.symmetric(vertical: 3),
            ),
          if (line.pumpDiscountPercent != null)
            FactRow(
              label: line.pumpAbove ? 'Pompanın üstünde' : 'Pompa iskontosu',
              value: Fmt.percent(
                line.pumpDiscountPercent!.abs(),
                maxFraction: 1,
              ),
              tone: line.pumpAbove ? AknTone.warn : null,
              padding: const EdgeInsets.symmetric(vertical: 3),
            ),
          if (line.costUnknown)
            Text(
              'Tüpraş fiyatı olmadan kârlılık doğrulanamaz.',
              style: t.caption.copyWith(color: c.warn.fg),
            ),
          if (showCosts && line.profitPercent != null)
            FactRow(
              label: 'Satış kârı',
              value:
                  '${Fmt.percent(line.profitPercent, maxFraction: 2)}${line.netProfit == null ? '' : ' · ${Fmt.money(line.netProfit)}'}',
              tone: line.loss ? AknTone.danger : null,
              padding: const EdgeInsets.symmetric(vertical: 3),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════ 5. Özet

class _SummaryStep extends ConsumerWidget {
  const _SummaryStep({required this.args});

  final FormWizardArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(formWizardProvider(args));
    final ctrl = ref.read(formWizardProvider(args).notifier);
    final d = s.draft;
    final t = context.aknText;
    final c = context.akn;
    final justification = d.exceptionJustification ?? '';
    return ListView(
      padding: _pad,
      children: [
        FieldPreviewPanel(args: args),
        const SizedBox(height: 20),
        FieldTextInput(
          label: 'Not',
          hint: 'Müşteriyle görüşme notu, teslim ayrıntısı…',
          value: d.note,
          maxLines: 3,
          minLines: 2,
          maxLength: 1000,
          error: s.errors['note'],
          onChanged: (v) =>
              ctrl.update((x) => x.copyWith(note: v), clears: {'note'}),
        ),
        const SizedBox(height: 8),
        FieldSwitchTile(
          title: 'Stratejik istisna iste',
          subtitle:
              'Kâr barem alt sınırının altındaysa gerekçeyle istisna onayına gider.',
          value: d.strategicExceptionRequested,
          onChanged: (v) => ctrl.update(
            (x) => x.copyWith(strategicExceptionRequested: v),
            clears: {'exceptionJustification'},
          ),
        ),
        if (d.strategicExceptionRequested) ...[
          const SizedBox(height: 8),
          FieldTextInput(
            label: 'İstisna gerekçesi',
            hint: 'Rekabet, müşteri potansiyeli, süre…',
            value: d.exceptionJustification,
            requiredMark: true,
            maxLines: 3,
            minLines: 2,
            maxLength: 1000,
            helper: justification.trim().length < 20
                ? 'En az 20 karakter (${justification.trim().length}/20)'
                : null,
            error: s.errors['exceptionJustification'],
            onChanged: (v) => ctrl.update(
              (x) => x.copyWith(exceptionJustification: v),
              clears: {'exceptionJustification'},
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: c.dim),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Gönderilen form düzenlenemez. Onaylanan fiyat müşteriye teklif olarak gider; müşteri maliyet ve kârı görmez.',
                style: t.caption,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
